#!/usr/bin/env python3
"""Turns a photographed pencil drawing and a small recipe into the game's portrait pictures.

    tools/.venv/bin/python -I tools/portraits/sketch_to_portrait.py --sketch <jpg> --recipe <json> --out <folder> [--only <expr>] [--stages <folder>]
    tools/.venv/bin/python -I tools/portraits/sketch_to_portrait.py --init-recipe <jpg> --out <recipe.json>

(That Python is the project's venv, made by `tools/setup.sh --portraits`; the tool says so, in one line, when it is run without Pillow
and numpy.) The second form writes a first recipe for a new drawing by itself (the paper found, ruled or plain; the crop at the
drawing's own bounds; the expression from the file's name, `<speaker>-<expression>-<date>.jpg`, else `neutral` with a note; no erase,
no tints; a `keep` only where the tool would otherwise take a stroke out with a rule) and stops, always, when the page is a drawing at all,
even when the tool would still refuse it (it says so, and what to do); the first form then makes an untinted portrait that is the drawing,
cleaned.

It writes `<expr>.png` (464 x 640, RGB, no alpha) for each expression of the recipe. With `--stages` it also writes each
stage's picture for a person to look at: `flat.png` (the paper evened out), `rules.png` (the notebook's rules the tool
found, in red over the evened page), `clean.png` (the pencil alone, the rules gone), `crop.png` (the card's shape, the
line alone) and `tint.png` (the soft washes alone on the paper).

The stages, in the order they run:

  page     refused (exit 2, one line saying why) when under 600 pixels on its short side, more than a third dark (too dark: it needs more
           light), with less than three quarters of its middle paper once the light is evened and thin lines are looked past (a photograph
           of a thing), or squared (graph) paper.
  flat     the page's own brightness is divided out, so a shadow and a grey cast go: the paper is white, the pencil dark.
  rules    (paper "ruled" only) a ruled page is ONE LATTICE: one tilt (where the thin dark lines with paper each side line up in rows), one
           spacing (the finest at which every row it names is a line: not a half, a third or a double) and one phase. Every lattice row on
           the page is a rule and is treated as one, however faint (but a lattice the levels would make nothing is left alone); each is
           followed across the page, curve and all, from where the last put it. No lattice, or fewer than three rules: "rules: none found".
  clean    a narrow band along each rule is filled from the pencil above and below it, along every direction a stroke could cross it; what
           is not on a rule is not touched. In a `keep` rectangle only the rule's own darkness comes off; an `erase` rectangle is wiped to
           paper, fading out over a few pixels. The levels then make paper nothing and the pencil's darkest full.
  check    the finished picture is measured by a road that does not use the rules the finder found: (1) a straight line left across the
           paper, at any row and angle within 6 degrees of level (thin ink covering more than 38% of the width of a sheared row), and (2) a
           stroke along a rule that lost more than a tenth of its ink to the rule's removal (25 columns or more, not running on past both
           ends) each refuse, exit 2, with their rows and the `keep` that would hold them if they are strokes of the drawing.
  crop     the recipe's `crop` of the page, padded with paper (never squashed) to the card's shape, made 464 x 640.
  tint     soft washes under the line, then the line over them in the card's ink, its darkness raised to the recipe's `line_gain`.

The recipe (JSON), whose keys are exactly these, every one written out (an unknown key and a missing key are each an error that
names it, "recipe: ..."):

  paper        "ruled" or "plain"
  crop         [x0, y0, x1, y1], fractions of the page
  erase, keep  lists of [x0, y0, x1, y1], fractions of the page; `erase` wipes to paper and fades out over 8 working pixels outside
               its rectangle; `keep` leaves a stroke along a rule alone but takes the rule's own darkness off it
  tints        a list of {name, colour ("#rrggbb"), polygon [[x, y], ...]}: polygons in fractions of the card's picture
               (what `crop.png` shows). The colour is the wash at its full strength; its edge is feathered
  card         {paper, ink}: colours, "#rrggbb"
  line_gain    the line's darkness is raised to this power under the ink: 1.0 is the line as drawn, 0.7 a heavier pencil
  expressions  {name: {}}; "neutral" is the drawing as it is
  notes        free text, ignored

The tool is deterministic: the same drawing and recipe give the same bytes. Exit status 0 when it is done, 2 with one line
on stderr ("sketch_to_portrait: <stage>: <what>") when it cannot do its work.
"""
import argparse
import json
import os
import re
import sys

try:
    import numpy as np
    from numpy.lib.stride_tricks import sliding_window_view
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as _missing:
    # One line and exit 2, not a traceback: a plain `pip install` goes to the user's site folder, which `python3 -I` does not read.
    print("sketch_to_portrait: this tool needs Pillow and numpy and this Python has not got %s: from the all-divine folder run `tools/setup.sh --portraits`, "
          "then run the tool as `tools/.venv/bin/python -I tools/portraits/sketch_to_portrait.py ...`" % (_missing.name or "them"), file=sys.stderr)
    sys.exit(2)

CARD_PICTURE = (464, 640)
WORK_WIDTH = 900

RECIPE_KEYS = {"paper", "crop", "erase", "keep", "tints", "card", "line_gain", "expressions", "notes"}
TINT_KEYS = {"name", "colour", "polygon"}
CARD_KEYS = {"paper", "ink"}
CROP_LEAST = 0.1

# The lattice: the tilts looked for (rise per column; 0.105 is 6 degrees), the thinnest spacing (rows), the share of the best comb score that
# a finer spacing must reach to be the spacing, the comb score under which a page has no rules, and how much of the page's width a row of the
# lattice must be seen across to count as seen (gaps of LATTICE_GAP seen-less rows between seen ones are closed).
LATTICE_SLOPE = 0.105
SPACING_LEAST = 8
SPACING_SHARE = 0.7
SPACING_STRIPS = 10
SPACING_STRENGTH = 0.12
SPACING_PARTS = 6
RIDGE_REACH = 4
LATTICE_GAP = 2
# The rule finder: how far above and below a pixel paper must lie for the pixel to be evidence of a rule, and how dark a rule is at the least
# above that paper. The reach and the distances in `RuleScale` are for rules 100 working pixels apart: they follow the lattice's spacing.
RULE_REACH = 9
RULE_MIN_RIDGE = 0.03
# The lattice's rules are left alone when they are fainter than this share of the levels' noise cut (over it): the levels make them nothing.
FAINT_RULE = 1.5
# Rules closer than this many working pixels cannot be taken out without the pencil.
RULE_SPACING_LEAST = 11
# A rule's fit is the page's width seen at least this much of; a fit that strays further than this share of the spacing from the lattice is dropped
# for the lattice's own line.
RULE_MIN_SPAN = 0.25
RULE_STRAY = 0.3
# A page is at least this many pixels on its short side (a card is made of about 60% of it, to 464 x 640); not more than this
# share of it is dark (a photograph with the desk across it, a lamp-less room); at least this share of the evened middle of the page is
# paper, thin lines looked past (a drawing's page is 85% paper and more; a photograph of a thing is not).
PAGE_LEAST = 600
PAGE_DARK_MOST = 0.35
PAGE_PAPER_LEAST = 0.75
# The finished picture: ink darker than RESIDUE_INK that has paper (under it) RESIDUE_REACH rows above and below is a thin line; a row of the picture
# sheared along any slope within LATTICE_SLOPE with thin ink in more than RESIDUE_COVER of the middle 80% of its columns is a line across the paper.
RESIDUE_INK = 0.08
RESIDUE_REACH = 4
RESIDUE_COVER = 0.38
# A stroke of the drawing on a rule is lost to the rule removal (see `_ink_taken`): a column of a rule has one on it when more than
# INK_COLUMN times the rule's own ink lies in its band and a row beyond (and INK_EXCESS more than the rule's own); a run of INK_RUN_MOST such
# columns or more that has lost more than INK_LOSS of its ink is refused, unless it runs on past both its ends (a stroke crossing at a shallow
# angle is on the rule for a stretch) and is no longer than INK_THROUGH of the page's width (gaps of INK_RUN_GAP columns or less close a run).
INK_COLUMN = 2.0
INK_EXCESS = 0.9
INK_RUN_MOST = 25
INK_RUN_GAP = 3
INK_LOSS = 0.10
INK_THROUGH = 0.2
INK_EDGE = 0.03
# A run is "continued" when pencil (darker than INK_PENCIL, at least INK_PENCIL_PIXELS pixels of it) lies within INK_END_ROWS rows of
# the rule's band, in the INK_END_REACH columns past each end of it.
INK_END_REACH = 15
INK_END_ROWS = 8
INK_PENCIL = 0.15
INK_PENCIL_PIXELS = 4
# A rule more than this many times as dark as the middle one of the other rules is a stroke of the drawing (see `check_rules_alike`).
DARK_RULE = 1.6
ERASE_FEATHER = 8.0
# --init-recipe: a cell of 12 x 12 working pixels holds pencil when this many of its pixels are over INIT_PENCIL; fewer cells than
# INIT_CELLS_LEAST is no drawing ; the crop gets INIT_MARGIN of the drawing's size on each side.
INIT_PENCIL = 0.2
INIT_CELL_INK = 6
INIT_CELLS_LEAST = 12
INIT_MARGIN = 0.04
INIT_CARD = {"paper": "#efe6cc", "ink": "#2b2a30"}
# The expressions a portrait can be (the game's), and the file name a drawing is given: <speaker>-<expression>-<date>.
EXPRESSIONS = ("neutral", "smile", "serious", "angry", "sad", "surprise")
FILE_NAME = re.compile(r"^[a-z][a-z0-9_]*-(?P<expression>[a-z]+)-\d{4}-\d{2}-\d{2}$")
LEVEL_NOISE = 0.05
# The most a rule's band is, in rows each side of its middle, and the least.
BAND_MAX = 5
BAND_MIN = 1
# A rule's band reaches as far as its darkness is over this share of its darkest row.
BAND_SHARE = 0.3
# How far a rule's line may lie from its fit, in rows.
CENTRE_REACHES = (10, 6, 5)
# How far from a rule's middle its halo is taken off.
HALO_REACH = 9
# A pixel darker than this many times the rule's halo there has pencil on it.
HALO_COVER = 1.3
HALO_SLACK = 0.03
# The rule's own darkness (its halo, and inside a `keep` the whole of its profile) is the middle of this many columns each side.
KEEP_STRETCH = 100
# How far along the rule a stroke may cross it, in columns per row of the band.
BRIDGE_SLANT = 2.75
BRIDGE_STEP = 0.25
BRIDGE_FLOOR = 0.08


class PortraitError(Exception):
    """The tool cannot do its work: `stage` says where, `message` what is wrong; `keeps` are the `keep` rectangles (fractions of the page) that
    would hold the strokes the message is about, for --init-recipe to put in the recipe it writes."""

    def __init__(self, stage, message, keeps=()):
        super().__init__("%s: %s" % (stage, message))
        self.stage = stage
        self.message = message
        self.keeps = list(keeps)


# ---------------------------------------------------------------------------------------------------------------- the page

def load_page(path):
    """The sketch as grey 0..1 at the working size."""
    try:
        with Image.open(path) as opened:
            image = opened.convert("L")
    except (OSError, ValueError) as error:
        raise PortraitError("sketch", "cannot read %s (%s)" % (path, error))
    if image.width > WORK_WIDTH:
        image = image.resize((WORK_WIDTH, round(image.height * WORK_WIDTH / image.width)), Image.LANCZOS)
    return np.asarray(image, dtype=np.float32) / 255.0


def _blur(a, n):
    """`a` blurred by three passes of a box of n pixels each way (close to a Gaussian), with zeros past the edge."""
    out = a.astype(np.float64)
    for axis in (0, 1):
        for _ in range(3):
            pad = n // 2
            widths = [(0, 0), (0, 0)]
            widths[axis] = (pad + 1, n - pad)
            csum = np.cumsum(np.pad(out, widths), axis=axis)
            length = out.shape[axis]
            hi = np.take(csum, np.arange(n, n + length), axis=axis)
            lo = np.take(csum, np.arange(0, length), axis=axis)
            out = (hi - lo) / n
    return out.astype(np.float32)


def _max_filter(a, n):
    """The largest value in the n x n square round each pixel (the edge's own values repeated past it): the same numbers as
    PIL's MaxFilter(n), as two passes of a row's maximum, which is a great deal faster."""
    pad = n // 2
    out = a
    for axis in (0, 1):
        widths = [(0, 0), (0, 0)]
        widths[axis] = (pad, pad)
        out = sliding_window_view(np.pad(out, widths, mode="edge"), n, axis=axis).max(axis=-1)
    return np.ascontiguousarray(out)


def flatten(grey):
    """The page with its own brightness divided out: paper 1.0 (within the paper's own grain), pencil darker."""
    as_bytes = (np.clip(grey, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    brightest = Image.fromarray(_max_filter(as_bytes, 21)).filter(ImageFilter.GaussianBlur(30))
    paper = np.asarray(brightest, dtype=np.float32) / 255.0
    flat = grey / np.maximum(paper, 1e-3)
    # The brightest neighbour overestimates the paper a little where the page's brightness slopes: what is left of the
    # slope is the paper's own average, taken over the pixels that are paper (not pencil, not a rule) and divided out too.
    is_paper = (flat > 0.88).astype(np.float32)
    average = _blur(flat * is_paper, 50) / np.maximum(_blur(is_paper, 50), 1e-3)
    return np.clip(flat / np.maximum(average, 0.5), 0.0, 1.0)



# --------------------------------------------------------------------------------------------------------------- the rules

_SMOOTHED = {}


def _smooth_columns(a, n):
    """`a` averaged over n neighbouring columns. The last answer for each n is kept for the same array (every rule of a page asks
    for the same smoothing of the same page)."""
    kept = _SMOOTHED.get(n)
    if kept is not None and kept[0] is a:
        return kept[1]
    out = _smooth_columns_of(a, n)
    _SMOOTHED[n] = (a, out)
    return out


def _smooth_columns_of(a, n):
    pad = n // 2
    padded = np.pad(a, [(0, 0), (pad, n - 1 - pad)], mode="edge")
    csum = np.cumsum(np.pad(padded, [(0, 0), (1, 0)]), axis=1, dtype=np.float64)
    return ((csum[:, n:] - csum[:, :-n]) / n).astype(np.float32)



class RuleScale:
    """The rule finder's distances for a page whose rules lie `spacing` working pixels apart: the same as the constants
    above for rules 100 apart, closer in as the rules come closer."""

    def __init__(self, spacing):
        self.spacing = float(spacing)
        s = self.spacing
        self.reach = int(max(3, min(RULE_REACH, round(0.4 * s))))
        grow = min(1.0, s / 40.0)
        self.tolerances = tuple(max(1.5, t * grow) for t in (6.0, 4.0, 3.0, 2.5))
        near = max(3, int(0.45 * s))
        self.centre_reaches = tuple(min(r, near) for r in CENTRE_REACHES)
        self.halo_reach = min(HALO_REACH, near)


class Lattice:
    """A ruled page's rules as one lattice: the tilt the rules share (`slope`, rows per column), the `spacing` between them (rows) and the rules
    themselves, `rules`, as cubic coefficients (rows as a cubic of the column minus the page's middle), top to bottom: every row of the lattice that
    lies on the page, each followed across the page."""

    def __init__(self, slope, spacing, rules):
        self.slope, self.spacing, self.rules = slope, spacing, rules


def _coverage(ys, xs, xc, slope, w):
    """How much of the page's width has evidence in each row of the page sheared along `slope`."""
    top = int(LATTICE_SLOPE * w / 2.0) + 4
    rows = np.floor(ys - slope * xc).astype(np.int64) + top
    keys = np.unique(rows * (w + 1) + xs)
    return np.bincount(keys // (w + 1)).astype(np.float64) / w, top


def _shear(dark, slope):
    """The page with each column moved up or down so that a rule of tilt `slope` lies level."""
    h, w = dark.shape
    shift = np.round(slope * (np.arange(w) - w / 2.0)).astype(int)
    return dark[np.clip(np.arange(h)[:, None] + shift[None, :], 0, h - 1), np.arange(w)[None, :]]


def _strip_profiles(dark):
    """The page's row profile in each of SPACING_STRIPS strips (a rule bends a few rows across the page, hardly any across a strip): the middle
    darkness of each row (a stroke of the drawing covers a minority of a strip's columns), and of that the thin lines only: how much darker each row
    is than the darker of the rows RIDGE_REACH above and below it. Broad things (the desk round a photographed page, a shadow, the edge of the page)
    are not thin lines and are left out; a rule is."""
    h, w = dark.shape
    edges = np.linspace(0, w, SPACING_STRIPS + 1).astype(int)
    profiles = []
    for a, b in zip(edges[:-1], edges[1:]):
        profile = np.median(dark[:, a:b], axis=1).astype(np.float64)
        above = np.concatenate([np.full(RIDGE_REACH, profile[0]), profile[:-RIDGE_REACH]])
        below = np.concatenate([profile[RIDGE_REACH:], np.full(RIDGE_REACH, profile[-1])])
        ridge = np.clip(profile - np.maximum(above, below), 0.0, None)
        profiles.append(ridge - ridge.mean())
    return profiles


def _comb_score(profile, spacing):
    """How well rules `spacing` apart explain a strip's row profile: at the best phase, the profile's mean on the rows the spacing says (a tooth each
    `spacing` rows) less its mean half a spacing past each tooth. The right spacing scores the rule's whole darkness; a half of it, its half (the other
    teeth are on paper); a third, a third; double, none (the mid-points are rules too); and a triple, all of it again (so the finest of the good ones
    is the spacing)."""
    h = len(profile)
    smooth = np.convolve(profile, np.ones(5) / 5.0, mode="same")
    phases = np.arange(0.0, spacing, 1.0)
    teeth = phases[:, None] + spacing * np.arange(0, int(h / spacing) + 1)[None, :]
    inside = teeth + spacing / 2.0 <= h - 1
    rows = np.arange(h)
    on = np.interp(teeth, rows, smooth)
    off = np.interp(teeth + spacing / 2.0, rows, smooth)
    return float((((on - off) * inside).sum(axis=1) / np.maximum(inside.sum(axis=1), 1)).max())


def _rhythm(dark):
    """(rows between the page's rules, how strongly the page repeats at that spacing 0..1, how dark the rules are, as the comb's score: 0 for a page
    with none, about 0.003 for the paper's grain). The page, its rules level, is read in strips and each strip's row profile is compared with itself
    shifted down: the shift at which they agree best, after the first where they disagree, is a spacing of the page's rhythm, but it may be a multiple
    of the rules' own. So that lag, its sixth, fifth, ... half, and its double are each scored against the page (`_comb_score`: a spacing whose rules are
    all found, and no other rule in between), and the finest that scores as well as the best is the spacing. Each strip has its own phase, so a page
    whose rules bend is read as well as a flat one."""
    h, w = dark.shape
    profiles = _strip_profiles(dark)
    total = np.zeros(h)
    for profile in profiles:
        spectrum = np.fft.rfft(profile, 2 * h)
        shifted = np.fft.irfft(spectrum * np.conj(spectrum))[:h]
        total += shifted / (shifted[0] + 1e-9)
    total /= SPACING_STRIPS
    below = np.nonzero(total[SPACING_LEAST:] < 0.0)[0]
    start = SPACING_LEAST + (int(below[0]) if len(below) else 0)
    stop = max(h // 3, start + 2)
    at = start + int(np.argmax(total[start:stop]))
    lag = float(at)
    if 0 < at < h - 1:  # between the rows: the peak's top, from its two neighbours (a whole row off over 36 rules is 36 rows)
        left, mid, right = total[at - 1], total[at], total[at + 1]
        bend = left - 2.0 * mid + right
        if bend < 0.0:
            lag += float(np.clip(0.5 * (left - right) / bend, -0.5, 0.5))
    candidates = [lag / float(k) for k in range(1, SPACING_PARTS + 1) if lag / float(k) >= SPACING_LEAST]
    if 2 * at <= stop:
        candidates.append(2.0 * lag)
    scores = [float(np.mean([_comb_score(p, c) for p in profiles])) for c in candidates]
    best = max(scores)
    spacing = min(c for c, score in zip(candidates, scores) if score >= SPACING_SHARE * best)
    return float(spacing), float(total[at]), float(best)


def find_lattice(dark):
    """The page's rules as a `Lattice`, or None when the page has none. The evidence is the thin dark lines with paper each side of them. The tilt the
    rules share is the slope at which the evidence, counted by the columns it covers in each row of the page sheared that way, is sharpest; with the rules
    level the page's rhythm is the spacing (`_rhythm`). Rules are then followed from the page's best-seen one in both directions, one spacing at a time:
    the next is put where the last one's curve, moved by the spacing between the last two, says, and followed across the page. A rule the evidence does
    not show is still a rule (the lattice says so): it is taken at that place; the lattice ends where two rules in a row are off the page or unseen.
    None when fewer than three rules are seen across a quarter of the page's width."""
    h, w = dark.shape
    ys, xs, ridge = rule_evidence(dark, 3)
    if len(ys) < 3 * w // 4:
        return None
    ys = ys.astype(np.float64)
    xc = xs.astype(np.float64) - w / 2.0

    def sharpness(slope):
        cover, _ = _coverage(ys, xs, xc, slope, w)
        return float((np.convolve(cover, np.ones(3), mode="same") ** 2).sum())
    coarse = np.arange(-LATTICE_SLOPE, LATTICE_SLOPE + 1e-9, 0.006)
    slope = float(coarse[int(np.argmax([sharpness(s) for s in coarse]))])
    fine = np.arange(slope - 0.005, slope + 0.00501, 0.001)
    slope = float(fine[int(np.argmax([sharpness(s) for s in fine]))])
    spacing, strength, _amplitude = _rhythm(_shear(dark, slope))
    if strength < SPACING_STRENGTH:
        return None
    scale = RuleScale(spacing)
    ys, xs, ridge = rule_evidence(dark, scale.reach)
    ys = ys.astype(np.float64)
    # where the rules stand on the page, at the slope: the phase at which the teeth of a comb of this spacing stand on the most evidence
    cover, top = _coverage(ys, xs, xs.astype(np.float64) - w / 2.0, slope, w)
    blurred = np.convolve(cover, np.ones(max(3, int(0.1 * spacing)) | 1), mode="same")
    phases = np.arange(0.0, spacing, 1.0)
    teeth = phases[:, None] + spacing * np.arange(0, int(len(blurred) / spacing))[None, :]
    phase = float(phases[int(np.argmax(np.interp(teeth, np.arange(len(blurred)), blurred).sum(axis=1)))])
    centre = [(phase - top) + k * spacing for k in range(int((h + 2 * top) / spacing) + 1)]
    seen_at = {}

    def follow(coef0):
        coef, seen = _fit_rule(ys, xs, ridge, w, coef0, scale.tolerances)
        stray = float(np.abs(np.polyval(coef, np.arange(0, w, 8) - w / 2.0) - np.polyval(coef0, np.arange(0, w, 8) - w / 2.0)).max())
        ok = seen >= RULE_MIN_SPAN * w and stray <= RULE_STRAY * spacing
        return (coef if ok else np.array(coef0, dtype=np.float64)), ok
    starts = [follow(np.array([0.0, 0.0, slope, row])) for row in centre if -scale.reach <= row < h + scale.reach]
    seen_here = [(float(np.polyval(c, 0.0)), c) for c, ok in starts if ok]
    if len(seen_here) < 3:
        return None
    # the start is the seen rule that is nearest the middle of the seen ones; the walk goes down, then up
    mids = sorted(seen_here, key=lambda m: m[0])
    first = mids[len(mids) // 2][1]
    rules = [first]
    for direction in (1.0, -1.0):
        previous, gap, misses, walked = first, spacing, 0, []
        while misses < LATTICE_GAP:
            seed = previous.copy()
            seed[3] += direction * gap
            if not (-spacing <= float(np.polyval(seed, 0.0)) <= h + spacing):
                break
            coef, ok = follow(seed)
            misses = 0 if ok else misses + 1
            walked.append((coef, ok))
            if ok:
                gap = float(np.clip(abs(float(np.polyval(coef, 0.0)) - float(np.polyval(previous, 0.0))), 0.75 * spacing, 1.25 * spacing))
            previous = coef
        while walked and not walked[-1][1]:   # the rules after the last one seen are not on the page
            walked.pop()
        rules = rules + [c for c, _ in walked] if direction > 0 else [c for c, _ in reversed(walked)] + rules
    return Lattice(slope, spacing, rules)


def rule_evidence(dark, reach=RULE_REACH):
    """The pixels that look like part of a thin long line with paper above and below: (ys, xs, ridge)."""
    h, w = dark.shape
    c = _smooth_columns(dark, 9)
    above = np.empty_like(c)
    below = np.empty_like(c)
    above[reach:] = c[:-reach]
    above[:reach] = c[:1]
    below[:-reach] = c[reach:]
    below[-reach:] = c[-1:]
    ridge = c - np.maximum(above, below)
    ys, xs = np.nonzero(ridge > RULE_MIN_RIDGE)
    return ys, xs, ridge[ys, xs]


def _fit_rule(ys, xs, weight, w, start, tolerances=(6.0, 4.0, 3.0, 2.5)):
    """Follows one rule across the page from (slope, height at the middle) by fitting the middle of its evidence in each
    column, with a tolerance that closes in; the fit is a straight line first, then a curve (a cubic: a photographed
    page bends). Returns (cubic coefficients, columns seen)."""
    xc = xs.astype(np.float64) - w / 2.0
    coef = np.array(start, dtype=np.float64) if len(start) == 4 else np.array([0.0, 0.0, start[0], start[1]])
    seen = 0
    for degree, tol in zip((1, 2, 3, 3), tolerances):
        pred = np.polyval(coef, xc)
        near = np.abs(ys - pred) <= tol
        if near.sum() < 20:
            break
        # one sample a column: the evidence's weighted middle
        cols = xs[near]
        order = np.argsort(cols, kind="stable")
        cols, rows, wts = cols[order], ys[near][order].astype(np.float64), weight[near][order].astype(np.float64)
        uniq, inverse = np.unique(cols, return_inverse=True)
        mids = np.bincount(inverse, weights=wts * rows) / np.bincount(inverse, weights=wts)
        seen = len(uniq)
        if seen < 20:
            break
        fit = np.polyfit(uniq - w / 2.0, mids, degree)
        coef = np.concatenate([np.zeros(4 - len(fit)), fit])
    return coef, seen


def _smooth_shift(cols, values, w):
    """The offset of a rule from its fit as a smooth curve over the page: a cubic through the measured offsets, the
    outliers (a stroke that was close to the rule) let go of and the curve fitted again."""
    x = (cols - w / 2.0) / w
    keep = np.ones(len(cols), dtype=bool)
    fit = np.zeros(4)
    for _ in range(4):
        if keep.sum() < 8:
            break
        fit = np.polyfit(x[keep], values[keep], 3)
        resid = np.abs(values - np.polyval(fit, x))
        limit = max(1.0, 2.5 * float(np.median(resid[keep])))
        keep = resid <= limit
    return np.polyval(fit, (np.arange(w) - w / 2.0) / w)


_CENTRES = {}


def rule_centre(dark, coef, w, reaches=CENTRE_REACHES):
    """`_rule_centre`, kept for the page it was asked about (the rule removal and the check of its work ask for the same rules of the
    same page; nothing changes what is returned)."""
    key = (tuple(float(c) for c in coef), int(w), tuple(reaches))
    kept = _CENTRES.get("page")
    if kept is None or kept[0] is not dark:
        kept = _CENTRES["page"] = (dark, {})
    if key not in kept[1]:
        kept[1][key] = _rule_centre(dark, coef, w, reaches)
    return kept[1][key]


def _rule_centre(dark, coef, w, reaches=CENTRE_REACHES):
    """Where a rule's middle is in each column: the fit, nudged to the line itself. The fit is a curve through the
    whole page and is a few rows out at its ends; the offset of the line from it is measured in the columns where the
    line stands alone (paper at both ends of the window) and carried across the columns where it does not, three times,
    each time from where the last left it. Also returns which columns the line stands alone in and how dark it is
    there (the window's darkest, paper taken off)."""
    h = dark.shape[0]
    xs = np.arange(w)
    centre = np.polyval(coef, xs - w / 2.0)
    c = _smooth_columns(dark, 5)
    alone = np.zeros(w, dtype=bool)
    peak = np.zeros(w)
    for reach in reaches:  # a wide window first, then closer in: a stroke near the rule must not pull it
        offs = np.arange(-reach, reach + 1)
        rows = np.clip(np.round(centre).astype(int)[:, None] + offs[None, :], 0, h - 1)
        profile = c[rows, xs[:, None]]
        base = np.minimum(profile[:, 0], profile[:, -1])
        lifted = np.clip(profile - base[:, None], 0.0, None)
        peak = lifted.max(axis=1)
        alone = (profile[:, 0] < 0.12) & (profile[:, -1] < 0.12) & (peak > 0.06)
        if alone.sum() < 20:
            break
        weight = np.clip(lifted - 0.02, 0.0, None)
        moved = (weight * offs[None, :]).sum(axis=1) / np.maximum(weight.sum(axis=1), 1e-6)
        good = np.nonzero(alone)[0]
        centre = centre + _smooth_shift(good, moved[good], w)
    return centre, alone, peak


def rule_half_width(dark, centre):
    """How many rows each side of its middle a rule's core reaches: as far as its mean darkness (over the columns where
    it stands alone, the paper's own level taken off) is over BAND_SHARE of its darkest row. What lies beyond is the
    rule's blur, which `_take_off_halo` takes off without removing anything from the drawing."""
    h, w = dark.shape
    xs = np.arange(0, w, 2)
    mid = np.round(centre[xs]).astype(int)
    offs = np.arange(-BAND_MAX - 3, BAND_MAX + 4)
    rows = np.clip(mid[:, None] + offs[None, :], 0, h - 1)
    profile = dark[rows, xs[:, None]]
    quiet = (profile[:, 0] < 0.08) & (profile[:, -1] < 0.08)
    if quiet.sum() < 10:
        return BAND_MAX
    mean = profile[quiet].mean(axis=0)
    lifted = mean - min(mean[0], mean[-1])
    peak = float(lifted.max())
    reach = [abs(int(o)) for o, v in zip(offs, lifted) if v > BAND_SHARE * peak]
    return int(min(BAND_MAX, max(BAND_MIN, (max(reach) if reach else 0))))


def _running_median(values, k):
    """The median of each value's neighbours, k each side (fewer at the ends)."""
    padded = np.pad(values, (k, k), mode="edge")
    return np.median(sliding_window_view(padded, 2 * k + 1), axis=-1)


def _take_off_halo(clean, dark, mid, alone, peak, half, keep_mask, halo_reach=HALO_REACH):
    """A rule is blurred, so its darkness trails off beyond the band as a faint streak, wider in one place than in
    another. At each row's distance from the rule's middle, how dark the paper is there beside the rule is measured in
    the columns where the rule stands alone, smoothed along the rule and carried across the columns where it does not,
    and that is taken off the rows beyond the band."""
    h, w = dark.shape
    xs = np.arange(w)
    offs = np.arange(-halo_reach, halo_reach + 1)
    rows = np.clip(mid[:, None] + offs[None, :], 0, h - 1)
    profile = dark[rows, xs[:, None]]
    # only the columns where the rule stands alone out to the halo's reach tell what its halo is
    quiet = alone & (profile[:, 0] < 0.08) & (profile[:, -1] < 0.08)
    good = np.nonzero(quiet)[0]
    if len(good) < 20:
        return
    profile = profile[good]
    base = np.minimum(profile[:, 0], profile[:, -1])
    # a halo is never darker than the rule's own core: what is darker than that, beside the rule, is pencil (a stroke that
    # hugs a rule for a stretch would be taken for its halo, and taken out, if the median were let follow it)
    lifted = np.clip(profile - base[:, None], 0.0, float(np.median(peak[good])))
    for slot, o in enumerate(offs):
        if abs(o) <= half:
            continue
        halo = np.interp(xs, good, _running_median(lifted[:, slot], 15))
        y = mid + o
        ok = (y >= 0) & (y < h)
        yy, xx = y[ok], xs[ok]
        free = ~keep_mask[yy, xx]
        yy, xx = yy[free], xx[free]
        local = halo[xx]
        value = clean[yy, xx]
        # pencil laid over a rule hides it (the darker of the two shows), so a pixel clearly darker than the halo is the
        # pencil's and stays; one near the halo's darkness is the halo alone
        clean[yy, xx] = np.where(value <= HALO_COVER * local + HALO_SLACK, np.maximum(value - local, 0.0), value)




def _own_profile(dark, mid, alone, keep_mask, halo_reach):
    """What a rule alone holds at each distance from its middle, along its length: (profile, align), or None when too few columns tell. The rule's
    middle `mid` is a row out here and there (a rule two rows thick falls on one row or the next): `align` is how many rows the rule's darkest row lies
    from `mid` (smoothed along the rule, carried across the columns it cannot be read in), and the profile is taken from that row, so it is crisp. It is
    measured from the columns where the rule stands alone and that lie outside every `keep` rectangle (a stroke the recipe marks would be taken for the
    rule), smoothed over a long stretch of them (what a crossing stroke or a speck adds is a minority of the stretch)."""
    h, w = dark.shape
    xs = np.arange(w)
    offs = np.arange(-halo_reach, halo_reach + 1)
    rows = np.clip(mid[:, None] + offs[None, :], 0, h - 1)
    profile = dark[rows, xs[:, None]]
    quiet = alone & ~keep_mask[np.clip(mid, 0, h - 1), xs] & (profile[:, 0] < 0.08) & (profile[:, -1] < 0.08)
    good = np.nonzero(quiet)[0]
    if len(good) < 40:
        return None
    base = np.minimum(profile[good, 0], profile[good, -1])
    lifted = np.clip(profile[good] - base[:, None], 0.0, None)
    near = np.abs(offs) <= 3
    darkest = offs[near][np.argmax(lifted[:, near], axis=1)]
    align = np.round(np.interp(xs, good, _running_median(darkest.astype(np.float64), KEEP_STRETCH))).astype(int)
    slots = np.clip(np.arange(len(offs))[None, :] + align[good][:, None], 0, len(offs) - 1)
    aligned = np.take_along_axis(lifted, slots, axis=1)
    smooth = np.stack([np.interp(xs, good, _running_median(aligned[:, slot], KEEP_STRETCH)) for slot in range(len(offs))])
    # the rule's own rows may be a row off from one column to the next: a row next to a row of the rule's core is the rule's, as far as the core
    core = smooth >= 0.5 * smooth.max(axis=0)[None, :]
    wide = smooth.copy()
    wide[1:] = np.maximum(wide[1:], smooth[:-1] * core[:-1])
    wide[:-1] = np.maximum(wide[:-1], smooth[1:] * core[1:])
    return smooth, align, wide


def _take_rule_off_kept(clean, dark, mid, own, keep_mask, halo_reach):
    """In a `keep` rectangle nothing is filled in (a stroke lies along the rule there), but the rule itself is not the drawing: `own` (the rule's
    profile and alignment, `_own_profile`) comes off where the pixel is the rule's alone; a pixel clearly darker than the rule is the stroke's."""
    h, w = dark.shape
    xs = np.arange(w)
    profile, align, wide = own
    offs = np.arange(-halo_reach, halo_reach + 1)
    for o in offs:
        y = mid + o
        ok = (y >= 0) & (y < h)
        yy, xx = y[ok], xs[ok]
        kept = keep_mask[yy, xx]
        yy, xx = yy[kept], xx[kept]
        slot = np.clip(o - align[xx] + halo_reach, 0, len(offs) - 1)
        value = dark[yy, xx]
        local, local_wide = profile[slot, xx], wide[slot, xx]
        # the rule alone goes; pencil over the rule hides it, and the rule's share of what is seen there (paper, then the rule, then the pencil,
        # each darkening what is under it) is taken off the same way, so a stroke along a rule is one even stroke, as it was drawn
        clean[yy, xx] = np.where(value <= HALO_COVER * local_wide + HALO_SLACK, np.maximum(value - local_wide, 0.0), (value - local) / (1.0 - local))


def remove_rules(dark, rules, keep_mask, scale):
    """`dark` with a band along each rule filled from above and below. Returns (cleaned, band mask, bands, taken): `taken` is, for each rule, what
    `_ink_taken` says of the strokes of the drawing that lie on it."""
    h, w = dark.shape
    clean = dark.copy()
    band_mask = np.zeros(dark.shape, dtype=bool)
    xs = np.arange(w)
    bands, taken = [], []
    found = [rule_centre(dark, coef, w, scale.centre_reaches) for coef in rules]
    mids = [np.round(centre).astype(int) for centre, _alone, _peak in found]
    # a rule's own profile is only wanted where a `keep` rectangle lies along it; one with no column of its own outside the keeps is taken to be
    # like the others (the middle of what they hold)
    reach_rows = np.arange(-scale.halo_reach, scale.halo_reach + 1)
    wanted = [bool(keep_mask[np.clip(mid[None, :] + reach_rows[:, None], 0, h - 1), xs[None, :]].any()) for mid in mids]
    owns = [_own_profile(dark, mid, alone, keep_mask, scale.halo_reach) if want else None for mid, (_c, alone, _p), want in zip(mids, found, wanted)]
    shared = None
    if any(want and own is None for want, own in zip(wanted, owns)):
        told = [o for o in (own if own is not None else _own_profile(dark, mid, alone, keep_mask, scale.halo_reach)
                            for own, mid, (_c, alone, _p) in zip(owns, mids, found)) if o is not None]
        shared = [np.median(np.stack([np.median(o[k], axis=1) for o in told]), axis=0) for k in (0, 2)] if told else None
    for (centre, alone, peak), own, wanted_here in zip(found, owns, wanted):
        half = rule_half_width(dark, centre)
        bands.append(half)
        mid = np.round(centre).astype(int)
        _take_off_halo(clean, dark, mid, alone, peak, half, keep_mask, scale.halo_reach)
        reach = half + 2
        # the strip along the rule: strip[o + reach, x] = the cleaned darkness `o` rows from the rule's middle
        offs = np.arange(-reach, reach + 1)
        rows = np.clip(mid[None, :] + offs[:, None], 0, h - 1)
        strip = clean[rows, xs[None, :]]  # with the halo already off: the rule's own blur is not a stroke
        # a stroke that crosses is seen above the band and below it along one straight line, in the two rows each side
        # outside the band, as the mean of the two (a textured stroke has gaps in a row; one pixel each side is no
        # evidence, any two specks are on some line)
        near_above, far_above, near_below, far_below = strip[1], strip[0], strip[-2], strip[-1]
        fill = np.zeros((2 * half + 1, w), dtype=np.float32)
        for slot, o in enumerate(range(-half, half + 1)):
            best = np.zeros(w, dtype=np.float32)
            k = -BRIDGE_SLANT
            while k <= BRIDGE_SLANT + 1e-9:
                def at(row):
                    return np.clip(np.round(xs + k * (row - o)).astype(int), 0, w - 1)
                seen_above = (near_above[at(-half - 1)] + far_above[at(-half - 2)]) / 2.0
                seen_below = (near_below[at(half + 1)] + far_below[at(half + 2)]) / 2.0
                best = np.maximum(best, np.minimum(seen_above, seen_below))
                k += BRIDGE_STEP
            fill[slot] = np.where(best > BRIDGE_FLOOR, best, 0.0)  # the best of many lines is always a little dark: only a stroke counts
        for slot, o in enumerate(range(-half, half + 1)):
            y = mid + o
            ok = (y >= 0) & (y < h)
            yy, xx = y[ok], xs[ok]
            free = ~keep_mask[yy, xx]
            clean[yy[free], xx[free]] = fill[slot][ok][free]
            band_mask[yy, xx] = True
        if wanted_here:
            own = own if own is not None else (None if shared is None else (np.tile(shared[0][:, None], (1, w)), np.zeros(w, dtype=int), np.tile(shared[1][:, None], (1, w))))
            if own is not None:
                _take_rule_off_kept(clean, dark, mid, own, keep_mask, scale.halo_reach)
        taken.extend(_ink_taken(dark, clean, mid, scale.halo_reach, keep_mask, half))
    return clean, band_mask, bands, taken


class Taken:
    """A run of columns along a rule that lost more than INK_LOSS of its ink to the rule removal (see `_ink_taken`): `run` columns long at `cols`
    (first, last) and `rows` (first, last) of the working page, which lost `loss` (0..1) of it."""

    def __init__(self, run=0, cols=(0, 0), rows=(0, 0), loss=0.0):
        self.run, self.cols, self.rows, self.loss = run, cols, rows, loss


def _ink_taken(dark, clean, mid, reach, keep_mask, half):
    """The stroke ink the rule removal took out along one rule. A column of the rule has a stroke on it when more than INK_COLUMN times the
    rule's own ink lies in its band and a row beyond (the ink within `half` + 1 rows of the rule's middle, above the paper `reach` rows away,
    summed down the column; the rule's own is what the quarter-way column holds). A run of such columns (small gaps closed, the middle of the
    page's width, never a column inside a `keep`) has lost `1 - what is left / what lay on the rule` of its ink; a run of INK_RUN_MOST columns
    or more (a mouth's corner is 30; a mole or a lash's tip is less) that lost more than INK_LOSS is a stroke taken out with its rule, unless it runs on past both its ends and is short (a stroke crossing
    at a shallow angle: it is bridged, and goes on). Returns a list of `Taken`, one for each such run along the rule."""
    h, w = dark.shape
    xs = np.arange(w)
    offs = np.arange(-reach, reach + 1)
    rows = np.clip(mid[None, :] + offs[:, None], 0, h - 1)
    before = dark[rows, xs[None, :]]
    base = np.minimum(before[0], before[-1])
    zone = np.abs(offs) <= half + 1
    held = np.clip(before[zone] - base[None, :], 0.0, None).sum(axis=0)
    left = clean[rows, xs[None, :]][zone].sum(axis=0)
    c0, c1 = int(0.1 * w), int(0.9 * w)
    own = float(np.percentile(held[c0:c1], 25))
    free = ~keep_mask[np.clip(mid, 0, h - 1), xs]
    bad = (held - own > max((INK_COLUMN - 1.0) * own, INK_EXCESS)) & free
    r0, r1 = int(INK_EDGE * w), int((1.0 - INK_EDGE) * w)
    runs, start, last = [], None, None
    for x in np.nonzero(bad[r0:r1])[0].tolist() + [None]:
        if x is not None and last is not None and x - last <= INK_RUN_GAP:
            last = x
            continue
        if start is not None:
            runs.append((last - start + 1, start + r0, last + r0))
        start = last = x
    out = []
    for length, a, b in sorted(runs, reverse=True):
        if length < INK_RUN_MOST:
            break
        stroke = float(np.clip(held[a: b + 1] - own, 0.0, None).sum())
        loss = 1.0 - float(left[a: b + 1].sum()) / max(stroke, 1e-6)
        continued = ((a <= r0 or _pencil_beyond(dark, mid, half, max(a - INK_END_REACH, 0), a))
                     and (b >= r1 - 1 or _pencil_beyond(dark, mid, half, b + 1, min(b + 1 + INK_END_REACH, w))))
        if loss > INK_LOSS and not (continued and length <= INK_THROUGH * w):
            out.append(Taken(length, (a, b), (int(mid[a: b + 1].min()) - reach // 2, int(mid[a: b + 1].max()) + reach // 2), loss))
    return out


def _pencil_beyond(dark, mid, half, x0, x1):
    """Whether there is pencil (INK_PENCIL, at least INK_PENCIL_PIXELS of it) in columns x0..x1-1 within INK_END_ROWS rows of a
    rule, outside its band: the pencil of a stroke that leaves the rule there."""
    h, w = dark.shape
    count = 0
    for o in list(range(half + 2, half + 2 + INK_END_ROWS)) + list(range(-half - 1 - INK_END_ROWS, -half - 1)):
        rows = np.clip(mid[x0:x1] + o, 0, h - 1)
        count += int((dark[rows, np.arange(x0, x1)] > INK_PENCIL).sum())
    return count >= INK_PENCIL_PIXELS


# ------------------------------------------------------------------------------------------------------------------ levels

def levels(dark, floor=None):
    """Paper to nothing, the pencil's darkest to full. Returns the picture and the (floor, ceiling) used."""
    if floor is None:
        floor = float(np.median(dark)) + 0.03
    ceiling = max(float(np.percentile(dark, 99.7)), floor + 0.05)
    scaled = np.clip((dark - floor) / (ceiling - floor), 0.0, 1.0)
    # what is left of the paper's grain and of a rule's last trace is under LEVEL_NOISE and goes; the pencil's lightest does not
    return np.clip((scaled - LEVEL_NOISE) / (1.0 - LEVEL_NOISE), 0.0, 1.0).astype(np.float32), (floor, ceiling)


def _rect_mask(shape, rects):
    """A boolean mask of `rects` (fractions of the page) on a page of `shape`."""
    h, w = shape
    mask = np.zeros(shape, dtype=bool)
    for x0, y0, x1, y1 in rects:
        mask[max(int(y0 * h), 0): int(np.ceil(y1 * h)), max(int(x0 * w), 0): int(np.ceil(x1 * w))] = True
    return mask


def _min_filter(a, n):
    return -_max_filter(-a, n)


def check_page(grey, paper_kind):
    """Refuses a page that is not a pencil drawing on paper, or too small to make a card from: one line, what would help."""
    h, w = grey.shape
    if min(h, w) < PAGE_LEAST:
        raise PortraitError("page", "too small: %d x %d pixels (the short side is at least %d: photograph the whole page from nearer)" % (w, h, PAGE_LEAST))
    help_text = "try plain paper, the whole page in the photograph, even light"
    dark_share = float((grey < 0.3).mean())
    flat = flatten(grey)
    # the paper's share is taken in the middle of the picture (the page, not the desk round it) with thin dark lines (rules, pencil) closed
    closed = _min_filter(_max_filter(flat, 5), 5)
    middle = closed[int(0.15 * h): int(0.85 * h), int(0.15 * w): int(0.85 * w)]
    paper_share = float((middle > 0.94).mean())
    if dark_share > PAGE_DARK_MOST:
        if paper_share >= PAGE_PAPER_LEAST:   # a page, evened out, is paper with a drawing on it: the photograph is only dark
            raise PortraitError("page", "the photograph is too dark: %.1f%% of it is under-exposed (at most %.1f%%); it needs more light "
                                        "(daylight, a lamp beside the page, no shadow across it)" % (100 * dark_share, 100 * PAGE_DARK_MOST))
        raise PortraitError("page", "not a pencil drawing on paper: %.1f%% of the photograph is dark (at most %.1f%%); %s" % (
            100 * dark_share, 100 * PAGE_DARK_MOST, help_text))
    if paper_share < PAGE_PAPER_LEAST:
        raise PortraitError("page", "not a pencil drawing on paper: only %.1f%% of the page is paper (at least %.1f%%); %s" % (
            100 * paper_share, 100 * PAGE_PAPER_LEAST, help_text))
    if find_lattice((1.0 - flat).T.copy()) is not None:   # lines that run up the page
        raise PortraitError("page", "this looks like squared (graph) paper, or paper with its lines running up the page: the tool takes the lines out of "
                                    "plain paper (none) and ruled paper (across the page), not a grid; draw on plain or ruled paper, or turn the page so that its lines run across")
    return flat


def rule_contrast(dark, coef, w, scale, keep_mask=None):
    """How much darker a rule is than the paper beside it: the middle, over the columns where paper lies above and below,
    of its darkest row within three rows of the fit (a stroke that crosses it is in a minority of the columns; a stroke the recipe's
    `keep` marks, which may be most of them, is left out: 0.0 when too few columns are left to tell)."""
    h = dark.shape[0]
    xs = np.arange(w)
    centre = np.round(np.polyval(coef, xs - w / 2.0)).astype(int)
    reach = scale.reach
    c = _smooth_columns(dark, 5)
    offs = np.arange(-reach, reach + 1)
    rows = np.clip(centre[:, None] + offs[None, :], 0, h - 1)
    profile = c[rows, xs[:, None]]
    base = np.minimum(profile[:, 0], profile[:, -1])
    lift = profile[:, reach - 3: reach + 4].max(axis=1) - base
    quiet = (profile[:, 0] < 0.12) & (profile[:, -1] < 0.12)
    if keep_mask is not None:
        quiet &= ~keep_mask[np.clip(centre, 0, h - 1), xs]
    return float(np.median(lift[quiet])) if int(quiet.sum()) >= 20 else 0.0


def _photograph_span(first, last, row_scale):
    return "%d-%d" % (int(round(first * row_scale)), int(round(last * row_scale)))


def _keep_box(cols, rows, shape):
    """A `keep` rectangle (fractions of the page) round columns and rows (working pixels), a few pixels wider each way."""
    h, w = shape
    return [round(max(cols[0] - 10, 0) / w, 3), round(max(rows[0] - 4, 0) / h, 3), round(min(cols[1] + 10, w) / w, 3), round(min(rows[1] + 4, h) / h, 3)]


def _keep_text(box):
    return "\"keep\": [[%.3f, %.3f, %.3f, %.3f]]" % tuple(box)


def check_ink(taken, shape, row_scale=1.0):
    """Refuses a page with a stroke of the drawing lying along a rule: `taken` is, for each rule, a `Taken` (`remove_rules`). The rule removal
    takes out the band of the rule, and a stroke that lies in it goes with it, wholly or in part (hollowed). The line names the rows and columns
    (of the photograph, `row_scale` times the working ones) and the `keep` rectangle that would hold each stroke, as fractions of the page."""
    bad = [t for t in taken if t.run > 0]
    if not bad:
        return
    worst = max(bad, key=lambda t: (t.loss * t.run))
    boxes = [_keep_box(t.cols, t.rows, shape) for t in bad]
    raise PortraitError("clean", "the drawing was being erased: a stroke lies along a rule and would lose %.0f%% of its ink with it (at rows %s, columns %s of "
                        "the photograph, %d columns long); if that is a stroke of the drawing, mark it in the recipe's `keep`, e.g. %s, or use plain paper" % (
                            100 * worst.loss, _photograph_span(*worst.rows, row_scale), _photograph_span(*worst.cols, row_scale), worst.run,
                            _keep_text(_keep_box(worst.cols, worst.rows, shape))), boxes)


def check_rules_alike(rules, contrasts, shape, keep_mask, row_scale=1.0):
    """The rules of a notebook are alike: a rule more than DARK_RULE times as dark as the middle one of the others is a stroke of
    the drawing laid along the page's whole width of it (a ground line, a long mouth), and taking it out as a rule would erase
    it. Refuses with the rows and columns, unless the recipe's `keep` holds most of that rule."""
    if len(rules) < 4:
        return
    h, w = shape
    xs = np.arange(w)
    c0, c1 = int(0.1 * w), int(0.9 * w)
    for i, (coef, lift) in enumerate(zip(rules, contrasts)):
        others = [c for j, c in enumerate(contrasts) if j != i]
        if lift <= DARK_RULE * float(np.median(others)):
            continue
        mid = np.clip(np.round(np.polyval(coef, xs - w / 2.0)).astype(int), 0, h - 1)
        if float(keep_mask[mid, xs][c0:c1].mean()) >= 0.5:
            continue
        rows = (int(mid[c0:c1].min()) - 3, int(mid[c0:c1].max()) + 3)
        box = [0.0, round(max(rows[0] - 4, 0) / h, 3), 1.0, round(min(rows[1] + 4, h) / h, 3)]
        raise PortraitError("clean", "the drawing was being erased: a line %.1f times as dark as the other rules lies along rows %s, columns %s of the photograph "
                            "(a stroke along the whole rule?); if that is a stroke of the drawing, mark it in the recipe's `keep`, e.g. %s" % (
                                lift / float(np.median(others)), _photograph_span(*rows, row_scale), _photograph_span(c0, c1, row_scale), _keep_text(box)), [box])


def check_clean(line, keep_mask=None, row_scale=1.0):
    """The tool checks its own work, by a road that does not use the rules the finder found: any straight line left across the paper, at any row
    and at any angle within 6 degrees of level. The finished picture's thin ink (darker than RESIDUE_INK, with paper RESIDUE_REACH rows above and below:
    a rule's trace, a stroke of the drawing; not the broad edge of the page or a shadow) is sheared along each slope in turn and counted by the
    columns it covers in each 3-row band of the page's middle 80%; a band with more than RESIDUE_COVER of the columns is a line across the paper. What the
    recipe's `keep` marks is the drawing's own: not judged. Raises PortraitError naming the rows (of the photograph, `row_scale` times the
    working rows), the angle, and the `keep` that would hold it if it is a stroke of the drawing."""
    h, w = line.shape
    ink = line > RESIDUE_INK
    if keep_mask is not None:
        ink &= ~keep_mask
    reach = RESIDUE_REACH
    above = np.ones_like(line)
    below = np.ones_like(line)
    above[reach:] = line[:-reach]
    below[:-reach] = line[reach:]
    ys, xs = np.nonzero(ink & (above < RESIDUE_INK) & (below < RESIDUE_INK))
    inside = (xs >= int(0.1 * w)) & (xs < int(0.9 * w))
    ys, xs = ys[inside], xs[inside]
    if len(ys) == 0:
        return
    xc = xs - w / 2.0
    n = int(0.9 * w) - int(0.1 * w)
    top = int(LATTICE_SLOPE * w / 2.0) + 4
    best = (0.0, 0.0, 0, 0)
    for slope in np.arange(-LATTICE_SLOPE, LATTICE_SLOPE + 1e-9, 0.0025):
        for shift in (0.0, 1.5):
            band = np.floor((ys - slope * xc + shift) / 3.0).astype(np.int64) + top
            keys = np.unique(band * (w + 1) + xs)
            counts = np.bincount(keys // (w + 1))
            at = int(np.argmax(counts))
            if counts[at] / n > best[0]:
                best = (counts[at] / n, float(slope), shift, at)
    cover, slope, shift, at = best
    if cover <= RESIDUE_COVER:
        return
    hit = np.floor((ys - slope * xc + shift) / 3.0).astype(np.int64) + top == at
    across = np.unique(xs[hit])
    breaks = np.nonzero(np.diff(across) > 12)[0]
    runs = np.split(across, breaks + 1)   # the columns the line covers, in stretches: the longest is the line
    longest = max(runs, key=len)
    on = hit & (xs >= longest[0]) & (xs <= longest[-1])
    cols, rows = (int(longest[0]), int(longest[-1])), (int(ys[on].min()), int(ys[on].max()))
    raise PortraitError("clean", "rules remain: a straight line runs across %.0f%% of the picture at rows %s, columns %s of the photograph, tilted %.1f degrees "
                        "(the rules may be too close together or too faint to take out; plain paper, or a photograph with the page filling the frame, helps); "
                        "if that is a stroke of the drawing, mark it in the recipe's `keep`, e.g. %s" % (
                            100 * cover, _photograph_span(*rows, row_scale), _photograph_span(*cols, row_scale), float(np.degrees(np.arctan(slope))),
                            _keep_text(_keep_box(cols, rows, line.shape))), [_keep_box(cols, rows, line.shape)])


def erase_weight(shape, rects):
    """How much of each pixel the recipe's `erase` wipes, 0..1: all of it inside a rectangle, fading to nothing over
    ERASE_FEATHER pixels outside it (a straight edge cut through pencil reads as a pale slit)."""
    h, w = shape
    weight = np.zeros(shape, dtype=np.float32)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    for x0, y0, x1, y1 in rects:
        left, right = max(int(x0 * w), 0), int(np.ceil(x1 * w))
        top, bottom = max(int(y0 * h), 0), int(np.ceil(y1 * h))
        dx = np.maximum(np.maximum(left - xs, xs - (right - 1)), 0.0)
        dy = np.maximum(np.maximum(top - ys, ys - (bottom - 1)), 0.0)
        weight = np.maximum(weight, np.clip(1.0 - np.hypot(dx, dy) / ERASE_FEATHER, 0.0, 1.0))
    return weight


def clean_page(grey, recipe, row_scale=1.0, tolerant=False, lattice=None):
    """The whole of the page's work: returns a dict of the stages' arrays at the working size: flat, dark (before the rules go), rules (the
    coefficients of each rule taken out), spacing, taken, bands (rows each side), band_mask, cleaned (dark after the rules go and the erase), line
    (cleaned, levelled), line_before (dark levelled the same way), problems (what the checks refused, as PortraitErrors). Raises the first
    PortraitError for a page it cannot handle, unless `tolerant` (--init-recipe: it wants the pictures and the problems both). `lattice` is the page's
    lattice when the caller has just looked for it."""
    flat = check_page(grey, recipe["paper"])
    dark = 1.0 - flat
    keep_mask = _rect_mask(dark.shape, recipe["keep"])
    rules, taken, problems = [], [], []
    spacing = 0.0
    band_mask, bands = np.zeros(dark.shape, dtype=bool), []
    cleaned = dark.copy()
    if recipe["paper"] == "ruled":
        lattice = lattice if lattice is not None else find_lattice(dark)
        if lattice is None:
            raise PortraitError("rules", "none found (is the paper plain? then the recipe's paper is \"plain\")")
        spacing = lattice.spacing
        scale = RuleScale(spacing)
        rules = lattice.rules
        if spacing < RULE_SPACING_LEAST:
            problems.append(PortraitError("rules", "only %.1f pixels apart: the rules are too close together to take out without taking the pencil with them "
                                                   "(photograph the page from nearer, or use plain paper)" % spacing))
        contrasts = [rule_contrast(dark, coef, dark.shape[1], scale, keep_mask) for coef in rules]
        contrasts = [c if c > 0.0 else float(np.median([v for v in contrasts if v > 0.0] or [0.0])) for c in contrasts]   # a rule marked all over: like the others
        floor = float(np.median(dark)) + 0.03
        ceiling = max(float(np.percentile(dark, 99.7)), floor + 0.05)
        # rules too faint to survive the levels (below the noise cut) are not in the picture: taking them out could only cost the strokes near them
        if (float(np.median(contrasts)) - floor) / (ceiling - floor) > FAINT_RULE * LEVEL_NOISE:
            _note(problems, check_rules_alike, rules, contrasts, dark.shape, keep_mask, row_scale)
            cleaned, band_mask, bands, taken = remove_rules(dark, rules, keep_mask, scale)
    if recipe["erase"]:
        cleaned = cleaned * (1.0 - erase_weight(dark.shape, recipe["erase"]))
    line, used = levels(cleaned)
    if taken:
        _note(problems, check_ink, taken, dark.shape, row_scale)
    _note(problems, check_clean, line, keep_mask, row_scale)
    if problems and not tolerant:
        raise problems[0]
    before = np.clip((np.clip((dark - used[0]) / (used[1] - used[0]), 0.0, 1.0) - LEVEL_NOISE) / (1.0 - LEVEL_NOISE), 0.0, 1.0).astype(np.float32)
    return {"flat": flat, "dark": dark, "rules": rules, "spacing": spacing, "taken": taken, "bands": bands, "band_mask": band_mask,
            "cleaned": cleaned, "line": line, "line_before": before, "problems": problems}


def _note(problems, check, *args):
    try:
        check(*args)
    except PortraitError as error:
        problems.append(error)


# -------------------------------------------------------------------------------------------------------------- the card

def card_box(shape, crop):
    """The card's rectangle on the page in working pixels (x0, y0, x1, y1, floats), the crop padded with paper to the
    card's shape."""
    h, w = shape
    x0, y0, x1, y1 = crop[0] * w, crop[1] * h, crop[2] * w, crop[3] * h
    aim = CARD_PICTURE[0] / CARD_PICTURE[1]
    cw, ch = x1 - x0, y1 - y0
    if cw / ch < aim:
        pad = (ch * aim - cw) / 2.0
        x0, x1 = x0 - pad, x1 + pad
    else:
        pad = (cw / aim - ch) / 2.0
        y0, y1 = y0 - pad, y1 + pad
    return x0, y0, x1, y1


def crop_card(line, crop):
    """The line, cropped (and padded with paper) to the card's shape and made the card's size: float 0..1, 640 x 464."""
    x0, y0, x1, y1 = card_box(line.shape, crop)
    margin = int(max(-x0, -y0, x1 - line.shape[1], y1 - line.shape[0], 0)) + 4
    padded = np.pad(line, margin)
    image = Image.fromarray(padded, mode="F")
    box = (x0 + margin, y0 + margin, x1 + margin, y1 + margin)
    out = image.resize(CARD_PICTURE, Image.LANCZOS, box=box)
    return np.clip(np.asarray(out, dtype=np.float32), 0.0, 1.0)


def parse_colour(text, where):
    if not (isinstance(text, str) and len(text) == 7 and text[0] == "#"):
        raise PortraitError("recipe", "%s: a colour is '#rrggbb', not %r" % (where, text))
    try:
        return np.array([int(text[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32) / 255.0
    except ValueError:
        raise PortraitError("recipe", "%s: a colour is '#rrggbb', not %r" % (where, text))


def tint_masks(recipe):
    """[(name, colour, mask 0..1 at the card's size)]: each polygon feathered a little."""
    w, h = CARD_PICTURE
    out = []
    for tint in recipe["tints"]:
        picture = Image.new("L", (w * 2, h * 2), 0)
        ImageDraw.Draw(picture).polygon([(x * w * 2, y * h * 2) for x, y in tint["polygon"]], fill=255)
        picture = picture.filter(ImageFilter.GaussianBlur(10)).resize((w, h), Image.LANCZOS)
        out.append((tint["name"], parse_colour(tint["colour"], "tint '%s'" % tint["name"]),
                    np.asarray(picture, dtype=np.float32) / 255.0))
    return out


def wash_layer(recipe):
    """The card's paper with the washes on it, float RGB 0..1, 640 x 464 x 3."""
    w, h = CARD_PICTURE
    base = np.ones((h, w, 3), dtype=np.float32) * parse_colour(recipe["card"]["paper"], "card paper")
    for _name, colour, mask in tint_masks(recipe):
        base = base * (1.0 - mask[..., None]) + colour * mask[..., None]
    return base


def compose(line_card, recipe):
    """The washes with the line over them in the card's ink: uint8 RGB, 640 x 464 x 3."""
    base = wash_layer(recipe)
    ink = parse_colour(recipe["card"]["ink"], "card ink")
    d = (np.clip(line_card, 0.0, 1.0) ** recipe["line_gain"])[..., None]
    rgb = base * (1.0 - d) + ink * d
    return (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


# ---------------------------------------------------------------------------------------------------------------- recipe

def _rect(value, where):
    if not (isinstance(value, list) and len(value) == 4 and all(isinstance(v, (int, float)) for v in value)):
        raise PortraitError("recipe", "%s: a rectangle is [x0, y0, x1, y1]" % where)
    if not (0 <= value[0] < value[2] <= 1 and 0 <= value[1] < value[3] <= 1):
        raise PortraitError("recipe", "%s: a rectangle lies inside the page, x0 < x1 and y0 < y1, as fractions" % where)
    return [float(v) for v in value]


def load_recipe(path):
    """The recipe, checked: a dict with every key present. Raises PortraitError for what it does not know, and for any
    key that is missing: a recipe is never completed with a guess (no `paper` must not quietly mean "ruled")."""
    try:
        with open(path, encoding="utf-8") as handle:
            recipe = json.load(handle)
    except (OSError, ValueError) as error:
        raise PortraitError("recipe", "cannot read %s (%s)" % (path, error))
    return check_recipe(recipe)


def check_recipe(recipe):
    """`load_recipe` for a recipe already read (a dict)."""
    if not isinstance(recipe, dict):
        raise PortraitError("recipe", "the recipe is an object")
    for key in recipe:
        if key not in RECIPE_KEYS:
            raise PortraitError("recipe", "a key this tool does not know: '%s'" % key)
    for key in sorted(RECIPE_KEYS - {"notes"}):
        if key not in recipe:
            raise PortraitError("recipe", "no '%s' (every key of the recipe is written out; --init-recipe writes a first one)" % key)
    out = {"paper": recipe["paper"], "erase": [], "keep": [], "tints": [], "notes": recipe.get("notes", "")}
    if out["paper"] not in ("ruled", "plain"):
        raise PortraitError("recipe", "paper is \"ruled\" or \"plain\", not %r" % (out["paper"],))
    crop = recipe["crop"]
    if not (isinstance(crop, list) and len(crop) == 4 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in crop)):
        raise PortraitError("recipe", "crop is [x0, y0, x1, y1]")
    if not (0 <= crop[0] < crop[2] <= 1 and 0 <= crop[1] < crop[3] <= 1):
        raise PortraitError("crop", "outside the page: %s (fractions of the page, x0 < x1, y0 < y1, all 0 to 1)" % (crop,))
    if crop[2] - crop[0] < CROP_LEAST or crop[3] - crop[1] < CROP_LEAST:
        raise PortraitError("crop", "smaller than a tenth of the page: %s (it is %.0f%% wide and %.0f%% tall)" % (
            crop, 100 * (crop[2] - crop[0]), 100 * (crop[3] - crop[1])))
    out["crop"] = [float(v) for v in crop]
    for key in ("erase", "keep"):
        if not isinstance(recipe[key], list):
            raise PortraitError("recipe", "%s is a list of rectangles" % key)
        for i, rect in enumerate(recipe[key]):
            out[key].append(_rect(rect, "%s[%d]" % (key, i)))
    if not isinstance(recipe["tints"], list):
        raise PortraitError("recipe", "tints is a list")
    for i, tint in enumerate(recipe["tints"]):
        if not isinstance(tint, dict):
            raise PortraitError("recipe", "tints[%d] is an object" % i)
        for key in tint:
            if key not in TINT_KEYS:
                raise PortraitError("recipe", "tints[%d]: a key this tool does not know: '%s'" % (i, key))
        for key in sorted(TINT_KEYS):
            if key not in tint:
                raise PortraitError("recipe", "tints[%d] has no '%s'" % (i, key))
        polygon = tint["polygon"]
        if not (isinstance(polygon, list) and len(polygon) >= 3 and all(
                isinstance(p, list) and len(p) == 2 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in p) for p in polygon)):
            raise PortraitError("recipe", "tints[%d]: a polygon is a list of at least three [x, y]" % i)
        for point in polygon:
            if not (0 <= point[0] <= 1 and 0 <= point[1] <= 1):
                raise PortraitError("recipe", "tints[%d] ('%s'): the point %s lies outside the card (a polygon is in fractions, 0 to 1, of the card's picture)" % (
                    i, tint["name"], point))
        parse_colour(tint["colour"], "tints[%d]" % i)
        out["tints"].append({"name": str(tint["name"]), "colour": tint["colour"], "polygon": polygon})
    card = recipe["card"]
    if not isinstance(card, dict) or set(card) != CARD_KEYS:
        raise PortraitError("recipe", "card is {paper, ink}")
    parse_colour(card["paper"], "card paper")
    parse_colour(card["ink"], "card ink")
    out["card"] = {"paper": card["paper"], "ink": card["ink"]}
    gain = recipe["line_gain"]
    if isinstance(gain, bool) or not isinstance(gain, (int, float)) or not (0.0 < gain <= 4.0):
        raise PortraitError("recipe", "line_gain is a number above 0 and at most 4 (1.0 is the line as drawn), not %r" % (gain,))
    out["line_gain"] = float(gain)
    expressions = recipe["expressions"]
    if not isinstance(expressions, dict) or not expressions:
        raise PortraitError("recipe", "expressions is {name: {}}")
    for name, spec in expressions.items():
        if spec != {}:
            raise PortraitError("recipe", "expression '%s': this tool makes the drawing as it is, so far (an empty object)" % name)
    out["expressions"] = {str(k): {} for k in expressions}
    return out


# ------------------------------------------------------------------------------------------------------------------ main

def _save_grey(array, path):
    Image.fromarray((np.clip(array, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode="L").save(path)


def _rules_picture(stages):
    flat = stages["flat"]
    rgb = np.stack([flat, flat, flat], axis=-1)
    rgb[stages["band_mask"]] = [1.0, 0.1, 0.1]
    return (rgb * 255.0 + 0.5).astype(np.uint8)


def _row_scale(sketch, grey):
    """How many rows of the photograph one working row is."""
    with Image.open(sketch) as image:
        return image.height / float(grey.shape[0])


def make(sketch, recipe, out, only=None, stages_folder=None):
    """Makes the pictures. Returns the names written. Raises PortraitError."""
    recipe = load_recipe(recipe) if isinstance(recipe, str) else recipe
    if only is not None and only not in recipe["expressions"]:
        raise PortraitError("recipe", "--only %s: no such expression in the recipe (%s)" % (only, ", ".join(recipe["expressions"])))
    grey = load_page(sketch)
    stages = clean_page(grey, recipe, _row_scale(sketch, grey))
    card_line = crop_card(stages["line"], recipe["crop"])
    picture = compose(card_line, recipe)
    os.makedirs(out, exist_ok=True)
    written = []
    for name in recipe["expressions"]:
        if only is not None and name != only:
            continue
        Image.fromarray(picture, mode="RGB").save(os.path.join(out, name + ".png"), optimize=False)
        written.append(name)
    if stages_folder is not None:
        os.makedirs(stages_folder, exist_ok=True)
        _save_grey(stages["flat"], os.path.join(stages_folder, "flat.png"))
        Image.fromarray(_rules_picture(stages), mode="RGB").save(os.path.join(stages_folder, "rules.png"))
        _save_grey(1.0 - stages["line"], os.path.join(stages_folder, "clean.png"))
        _save_grey(1.0 - card_line, os.path.join(stages_folder, "crop.png"))
        wash = (np.clip(wash_layer(recipe), 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
        Image.fromarray(wash, mode="RGB").save(os.path.join(stages_folder, "tint.png"))
    return written


def _drawing_bounds(line):
    """(x0, y0, x1, y1) as fractions of the page: where the pencil is. The page is cut in cells; a cell holds pencil when enough
    of it is dark. Cells that touch each other make a piece; a piece that reaches the page's edge (the notebook's edge, the
    desk beside it) is not the drawing, and a piece of fewer than INIT_CELLS_LEAST cells is a speck. The drawing is what is left; when
    that is nothing (the drawing runs to the page's edge) every piece counts. None when there is no pencil at all."""
    h, w = line.shape
    cell = 12
    rows, cols = h // cell, w // cell
    blocks = (line[: rows * cell, : cols * cell] > INIT_PENCIL).reshape(rows, cell, cols, cell).sum(axis=(1, 3))
    active = blocks >= INIT_CELL_INK
    seen = np.zeros_like(active)
    inside, edge = [], []
    for y0 in range(rows):
        for x0 in range(cols):
            if not active[y0, x0] or seen[y0, x0]:
                continue
            piece, queue, touches = [], [(y0, x0)], False
            seen[y0, x0] = True
            while queue:
                y, x = queue.pop()
                piece.append((y, x))
                touches = touches or y <= 0 or x <= 0 or y >= rows - 1 or x >= cols - 1
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < rows and 0 <= xx < cols and active[yy, xx] and not seen[yy, xx]:
                            seen[yy, xx] = True
                            queue.append((yy, xx))
            if len(piece) >= INIT_CELLS_LEAST:
                (edge if touches else inside).extend(piece)
    kept = inside or edge
    if not kept:
        return None
    ys, xs = np.array([c[0] for c in kept]), np.array([c[1] for c in kept])
    return xs.min() * cell / w, ys.min() * cell / h, (xs.max() + 1) * cell / w, (ys.max() + 1) * cell / h


def expression_from_name(path):
    """(the expression a drawing's file name gives, None) for `zara-smile-2026-12-02.jpg`; ("neutral", what to tell the owner) for a
    name that does not follow <speaker>-<expression>-<date> and for an expression the game does not know."""
    stem = os.path.splitext(os.path.basename(path))[0]
    match = FILE_NAME.match(stem)
    if match is None:
        return "neutral", ("the file name '%s' does not follow <speaker>-<expression>-<date>, so the expression is 'neutral' "
                           "(change it in the recipe if you drew another)" % os.path.basename(path))
    if match.group("expression") not in EXPRESSIONS:
        return "neutral", ("'%s' is not an expression of the game (%s) in <speaker>-<expression>-<date>, so the expression is 'neutral' "
                           "(change it in the recipe if you drew another)" % (match.group("expression"), ", ".join(EXPRESSIONS)))
    return match.group("expression"), None


def first_recipe(sketch, expression="neutral"):
    """(a first recipe for a drawing, what the tool would still refuse about it as PortraitErrors): the paper found (ruled or plain), the crop at the
    drawing's own bounds with a margin (the card pads it to its shape, and it is never under a tenth of the page), no erase, no tints, the card's colours
    and line as Abarax's, `neutral`, and a `keep` for each stroke the rule removal would take out. The page is cleaned to find where the pencil is; a page
    that is not a drawing at all is refused here, in one line, with what would help; a drawing is always given its recipe, even when the tool would
    refuse it as it stands (the problems say what to do)."""
    grey = load_page(sketch)
    flat = check_page(grey, "plain")
    lattice = find_lattice(1.0 - flat)
    paper = "ruled" if lattice is not None else "plain"
    recipe = {"notes": "", "paper": paper, "crop": [0.0, 0.0, 1.0, 1.0], "erase": [], "keep": [], "tints": [], "card": dict(INIT_CARD), "line_gain": 1.0,
              "expressions": {expression: {}}}
    row_scale = _row_scale(sketch, grey)
    stages = clean_page(grey, recipe, row_scale, True, lattice)
    keeps = [box for problem in stages["problems"] for box in problem.keeps]
    if keeps:
        recipe["keep"] = keeps
        stages = clean_page(grey, recipe, row_scale, True, lattice)
    bounds = _drawing_bounds(stages["line"])
    if bounds is None:
        raise PortraitError("page", "no pencil found on it (the photograph shows paper and nothing drawn; draw darker, or photograph from nearer with even light)")
    x0, y0, x1, y1 = bounds
    mx, my = INIT_MARGIN * (x1 - x0), INIT_MARGIN * (y1 - y0)
    crop = [max(x0 - mx, 0.0), max(y0 - my, 0.0), min(x1 + mx, 1.0), min(y1 + my, 1.0)]
    for lo, hi in ((0, 2), (1, 3)):   # never under a tenth of the page each way
        if crop[hi] - crop[lo] < CROP_LEAST:
            middle = (crop[lo] + crop[hi]) / 2.0
            crop[lo], crop[hi] = min(max(middle - CROP_LEAST / 2.0, 0.0), 1.0 - CROP_LEAST), min(max(middle - CROP_LEAST / 2.0, 0.0), 1.0 - CROP_LEAST) + CROP_LEAST
    recipe["crop"] = [round(float(v), 4) for v in crop]
    recipe["notes"] = ("A first recipe written by --init-recipe: the paper found, the crop at the drawing's own bounds, no erase, no tints%s. "
                       "Look at the picture, then add tints, keep and erase by hand." % (", and a keep where a stroke lies on a rule" if keeps else ""))
    check_recipe(recipe)
    return recipe, stages["problems"]


def init_recipe(sketch, out_path, expression="neutral"):
    """Writes `first_recipe`'s recipe for a drawing to `out_path`; returns (the recipe, the problems the tool would still refuse it for)."""
    recipe, problems = first_recipe(sketch, expression)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(recipe, handle, indent=1)
        handle.write("\n")
    return recipe, problems


def main(argv=None):
    parser = argparse.ArgumentParser(description="Makes the game's portrait pictures from a photographed pencil drawing.")
    parser.add_argument("--sketch")
    parser.add_argument("--recipe")
    parser.add_argument("--out", required=True, help="the folder the pictures go in (with --init-recipe: the recipe file to write)")
    parser.add_argument("--only")
    parser.add_argument("--stages")
    parser.add_argument("--init-recipe", metavar="DRAWING", help="write a first recipe for this drawing into --out, and stop")
    args = parser.parse_args(argv)
    try:
        if args.init_recipe:
            expression, note = expression_from_name(args.init_recipe)
            recipe, problems = init_recipe(args.init_recipe, args.out, expression)
            print("sketch_to_portrait: wrote %s (paper and crop found; the expression is '%s'%s); now: %s -I tools/portraits/sketch_to_portrait.py --sketch %s --recipe %s --out <folder>" % (
                args.out, expression, " from the file name" if note is None else "", sys.executable, args.init_recipe, args.out))
            if recipe["keep"]:
                print("sketch_to_portrait: note: a stroke of the drawing lies along a rule, so the recipe has a `keep` for it (%d); look at the picture to see it is a stroke" % len(recipe["keep"]))
            if note is not None:
                print("sketch_to_portrait: note: %s" % note)
            for problem in problems:
                print("sketch_to_portrait: note: the tool would still refuse this page as it stands: %s" % problem)
            return 0
        if not (args.sketch and args.recipe):
            parser.error("--sketch and --recipe are needed (or --init-recipe <drawing> --out <recipe.json>)")
        make(args.sketch, args.recipe, args.out, args.only, args.stages)
    except PortraitError as error:
        print("sketch_to_portrait: %s" % error, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
