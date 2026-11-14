#!/usr/bin/env python3
"""Turns a photographed pencil drawing and a small recipe into the game's portrait pictures.

    python3 -I tools/portraits/sketch_to_portrait.py --sketch <jpg> --recipe <json> --out <folder> [--only <expr>] [--stages <folder>]

It writes `<expr>.png` (464 x 640, RGB, no alpha) for each expression of the recipe. With `--stages` it also writes each
stage's picture for a person to look at: `flat.png` (the paper evened out), `rules.png` (the notebook's rules the tool
found, in red over the evened page), `clean.png` (the pencil alone, the rules gone), `crop.png` (the card's shape, the
line alone) and `tint.png` (the soft washes alone on the paper).

The stages, in the order they run:

  flat     the page's own brightness (the brightest thing near each pixel, smoothed) is divided out, so the shadow down one
           side and the grey cast go and the paper is white, the pencil dark.
  rules    (paper "ruled" only) every rule is found as a rule and not as "a horizontal dark thing": a rule is a thin dark
           line with paper above and below it for most of the page's width. The pixels that have paper above and below
           them are the evidence; a Hough vote over (tilt, height) finds each rule among them, and a fit that is bent
           by nothing but those pixels (the drawing's own lines have pencil next to them and are never evidence) follows
           it across the page, curve and all. The page's rules are evenly spaced, so a rule that is missing between two
           that were found is put in at the spacing. Nothing found is an error: "rules: none found".
  clean    a narrow band along each rule is filled from the pencil above and below it, along every direction a stroke
           could cross it, so a stroke that crosses a rule is still one line; what is not on a rule is not touched. A
           rectangle of the recipe's `keep` is not touched at all (a stroke that lies along a rule); a rectangle of
           `erase` is wiped to paper (what is left over). The levels then make paper nothing and the pencil's darkest
           full.
  crop     the recipe's `crop` of the page, padded with paper (never squashed) to the card's shape, 116 x 160, and
           made 464 x 640.
  tint     soft washes under the line, then the line over them in the card's ink.

The recipe (JSON), whose keys are exactly these (an unknown key is an error, "recipe: ..."):

  paper        "ruled" or "plain"
  crop         [x0, y0, x1, y1], fractions of the page
  erase, keep  lists of [x0, y0, x1, y1], fractions of the page
  tints        a list of {name, colour ("#rrggbb"), polygon [[x, y], ...]}: polygons in fractions of the card's picture
               (what `crop.png` shows). The colour is the wash at its full strength; its edge is feathered
  card         {paper, ink}: colours, "#rrggbb"
  expressions  {name: {}}; "neutral" is the drawing as it is
  notes        free text, ignored

The tool is deterministic: the same drawing and recipe give the same bytes. Exit status 0 when it is done, 2 with one line
on stderr ("sketch_to_portrait: <stage>: <what>") when it cannot do its work.
"""
import argparse
import json
import os
import sys

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from PIL import Image, ImageDraw, ImageFilter

# The card's picture, in pixels: four times the card's 116 x 160 picture pixels.
CARD_PICTURE = (464, 640)
# The page is worked on at this width (a larger photograph is brought down to it; a smaller one is not made larger).
WORK_WIDTH = 900

RECIPE_KEYS = {"paper", "crop", "erase", "keep", "tints", "card", "line_gain", "expressions", "notes"}
TINT_KEYS = {"name", "colour", "polygon"}
CARD_KEYS = {"paper", "ink"}
# A crop is at least this share of the page each way.
CROP_LEAST = 0.1

# The rule finder: how far above and below a pixel paper must lie for the pixel to be evidence of a rule, how dark a rule
# is at the least above that paper, the tilts looked for (rise per column), and how much of the page's width a rule must
# be seen across.
RULE_REACH = 9
RULE_MIN_RIDGE = 0.03
RULE_TILT = 0.07
RULE_TILT_STEP = 0.005
RULE_MIN_SPAN = 0.25
# No two rules are nearer than this many rows.
RULE_APART = 30.0
# A rule missing between two found is put in at the spacing when the gap is this many spacings or more.
RULE_GAP = 1.6
# Levelled darkness under this is not pencil.
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
# ... plus this much (the paper's grain).
HALO_SLACK = 0.03
# How far along the rule a stroke may cross it, in columns per row of the band.
BRIDGE_SLANT = 2.75
BRIDGE_STEP = 0.25
# Fainter than this (darkness, paper 0) is not a stroke across the band.
BRIDGE_FLOOR = 0.08


class PortraitError(Exception):
    """The tool cannot do its work: `stage` says where, `message` what is wrong."""

    def __init__(self, stage, message):
        super().__init__("%s: %s" % (stage, message))
        self.stage = stage
        self.message = message


# ---------------------------------------------------------------------------------------------------------------- the page

def load_page(path):
    """The sketch as grey 0..1 at the working size."""
    try:
        image = Image.open(path).convert("L")
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


def flatten(grey):
    """The page with its own brightness divided out: paper 1.0 (within the paper's own grain), pencil darker."""
    as_bytes = Image.fromarray((np.clip(grey, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8))
    brightest = as_bytes.filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.GaussianBlur(30))
    paper = np.asarray(brightest, dtype=np.float32) / 255.0
    flat = grey / np.maximum(paper, 1e-3)
    # The brightest neighbour overestimates the paper a little where the page's brightness slopes: what is left of the
    # slope is the paper's own average, taken over the pixels that are paper (not pencil, not a rule) and divided out too.
    is_paper = (flat > 0.88).astype(np.float32)
    average = _blur(flat * is_paper, 50) / np.maximum(_blur(is_paper, 50), 1e-3)
    return np.clip(flat / np.maximum(average, 0.5), 0.0, 1.0)


# --------------------------------------------------------------------------------------------------------------- the rules

def _smooth_columns(a, n):
    """`a` averaged over n neighbouring columns."""
    pad = n // 2
    padded = np.pad(a, [(0, 0), (pad, n - 1 - pad)], mode="edge")
    csum = np.cumsum(np.pad(padded, [(0, 0), (1, 0)]), axis=1, dtype=np.float64)
    return ((csum[:, n:] - csum[:, :-n]) / n).astype(np.float32)


def rule_evidence(dark):
    """The pixels that look like part of a thin long line with paper above and below: (ys, xs, ridge)."""
    h, w = dark.shape
    c = _smooth_columns(dark, 9)
    above = np.empty_like(c)
    below = np.empty_like(c)
    above[RULE_REACH:] = c[:-RULE_REACH]
    above[:RULE_REACH] = c[:1]
    below[:-RULE_REACH] = c[RULE_REACH:]
    below[-RULE_REACH:] = c[-1:]
    ridge = c - np.maximum(above, below)
    ys, xs = np.nonzero(ridge > RULE_MIN_RIDGE)
    return ys, xs, ridge[ys, xs]


def _fit_rule(ys, xs, weight, w, start):
    """Follows one rule across the page from (slope, height at the middle) by fitting the middle of its evidence in each
    column, with a tolerance that closes in; the fit is a straight line first, then a curve (a cubic: a photographed
    page bends). Returns (cubic coefficients, columns seen)."""
    xc = xs.astype(np.float64) - w / 2.0
    coef = np.array([0.0, 0.0, start[0], start[1]])
    seen = 0
    for degree, tol in ((1, 6.0), (2, 4.0), (3, 3.0), (3, 2.5)):
        pred = np.polyval(coef, xc)
        near = np.abs(ys - pred) <= tol
        if near.sum() < 20:
            break
        # one sample a column: the evidence's weighted middle
        cols = xs[near]
        order = np.argsort(cols, kind="stable")
        cols, rows, wts = cols[order], ys[near][order].astype(np.float64), weight[near][order].astype(np.float64)
        uniq, first = np.unique(cols, return_index=True)
        bounds = list(first) + [len(cols)]
        mids = np.array([np.average(rows[a:b], weights=wts[a:b]) for a, b in zip(bounds[:-1], bounds[1:])])
        seen = len(uniq)
        if seen < 20:
            break
        fit = np.polyfit(uniq - w / 2.0, mids, degree)
        coef = np.concatenate([np.zeros(4 - len(fit)), fit])
    return coef, seen


def find_rules(dark):
    """Every rule of the page as polynomial coefficients (rows as a quadratic of the column minus the page's middle),
    top to bottom. Empty when there is none."""
    h, w = dark.shape
    ys, xs, ridge = rule_evidence(dark)
    if len(ys) == 0:
        return []
    ys = ys.astype(np.float64)
    xc = xs.astype(np.float64) - w / 2.0
    slopes = np.arange(-RULE_TILT, RULE_TILT + 1e-9, RULE_TILT_STEP)
    alive = np.ones(len(ys), dtype=bool)
    found = []
    for _ in range(60):
        best = (0.0, 0.0, 0.0)
        for s in slopes:
            inter = ys[alive] - s * xc[alive]
            bins = np.round(inter / 3.0).astype(np.int64)
            lo = bins.min() if len(bins) else 0
            if len(bins) == 0:
                break
            count = np.bincount(bins - lo).astype(np.float64)
            smooth = count + np.concatenate([[0.0], count[:-1]]) + np.concatenate([count[1:], [0.0]])
            at = int(np.argmax(smooth))
            if smooth[at] > best[0]:
                best = (float(smooth[at]), float(s), float((at + lo) * 3.0))
        if best[0] < RULE_MIN_SPAN * w * 1.5:
            break
        coef, seen = _fit_rule(ys[alive], xs[alive], ridge[alive], w, (best[1], best[2]))
        pred = np.polyval(coef, xc)
        gone = np.abs(ys - pred) <= 6.0
        alive &= ~gone
        if seen >= RULE_MIN_SPAN * w and not _crowds(coef, found, w):
            found.append(coef)
    found.sort(key=lambda c: float(np.polyval(c, 0.0)))
    return _fill_gaps(found, h)


def _crowds(coef, found, w):
    """Whether `coef` runs closer than RULE_APART rows to a rule already found, anywhere across the page: a rule has no
    second rule on top of it, so this is the drawing's own line that the vote found along a real rule."""
    xs = np.array([0.1, 0.5, 0.9]) * w - w / 2.0
    for other in found:
        if np.abs(np.polyval(coef, xs) - np.polyval(other, xs)).min() < RULE_APART:
            return True
    return False


def _fill_gaps(rules, h):
    """Puts in a rule that the spacing says is missing between two found ones."""
    if len(rules) < 3:
        return rules
    mids = np.array([float(np.polyval(c, 0.0)) for c in rules])
    spacing = float(np.median(np.diff(mids)))
    out = [rules[0]]
    for i in range(1, len(rules)):
        gap = mids[i] - mids[i - 1]
        missing = int(round(gap / spacing)) - 1
        if gap >= RULE_GAP * spacing and missing > 0:
            for k in range(1, missing + 1):
                t = k / (missing + 1)
                out.append(rules[i - 1] * (1 - t) + rules[i] * t)
        out.append(rules[i])
    return out


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


def rule_centre(dark, coef, w):
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
    for reach in CENTRE_REACHES:  # a wide window first, then closer in: a stroke near the rule must not pull it
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


def _take_off_halo(clean, dark, mid, alone, peak, half, keep_mask):
    """A rule is blurred, so its darkness trails off beyond the band as a faint streak, wider in one place than in
    another. At each row's distance from the rule's middle, how dark the paper is there beside the rule is measured in
    the columns where the rule stands alone, smoothed along the rule and carried across the columns where it does not,
    and that is taken off the rows beyond the band."""
    h, w = dark.shape
    xs = np.arange(w)
    offs = np.arange(-HALO_REACH, HALO_REACH + 1)
    rows = np.clip(mid[:, None] + offs[None, :], 0, h - 1)
    profile = dark[rows, xs[:, None]]
    # only the columns where the rule stands alone out to the halo's reach tell what its halo is
    quiet = alone & (profile[:, 0] < 0.08) & (profile[:, -1] < 0.08)
    good = np.nonzero(quiet)[0]
    if len(good) < 20:
        return
    profile = profile[good]
    base = np.minimum(profile[:, 0], profile[:, -1])
    lifted = np.clip(profile - base[:, None], 0.0, None)
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


def remove_rules(dark, rules, keep_mask):
    """`dark` with a band along each rule filled from above and below. Returns (cleaned, band mask, bands)."""
    h, w = dark.shape
    clean = dark.copy()
    band_mask = np.zeros(dark.shape, dtype=bool)
    xs = np.arange(w)
    bands = []
    for coef in rules:
        centre, alone, peak = rule_centre(dark, coef, w)
        half = rule_half_width(dark, centre)
        bands.append(half)
        mid = np.round(centre).astype(int)
        _take_off_halo(clean, dark, mid, alone, peak, half, keep_mask)
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
    return clean, band_mask, bands


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


def clean_page(grey, recipe):
    """The whole of the page's work: returns a dict of the stages' arrays at the working size:
    flat, dark (before the rules go), rules (the coefficients), bands (rows each side), band_mask, cleaned (dark after
    the rules go and the erase), line (cleaned, levelled), line_before (dark levelled the same way)."""
    flat = flatten(grey)
    dark = 1.0 - flat
    keep_mask = _rect_mask(dark.shape, recipe["keep"])
    rules, band_mask, bands = [], np.zeros(dark.shape, dtype=bool), []
    cleaned = dark.copy()
    if recipe["paper"] == "ruled":
        rules = find_rules(dark)
        if not rules:
            raise PortraitError("rules", "none found")
        cleaned, band_mask, bands = remove_rules(dark, rules, keep_mask)
    erase_mask = _rect_mask(dark.shape, recipe["erase"])
    cleaned[erase_mask] = 0.0
    line, used = levels(cleaned)
    before = np.clip((np.clip((dark - used[0]) / (used[1] - used[0]), 0.0, 1.0) - LEVEL_NOISE) / (1.0 - LEVEL_NOISE), 0.0, 1.0).astype(np.float32)
    return {"flat": flat, "dark": dark, "rules": rules, "bands": bands, "band_mask": band_mask, "cleaned": cleaned,
            "line": line, "line_before": before}


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


def make(sketch, recipe, out, only=None, stages_folder=None):
    """Makes the pictures. Returns the names written. Raises PortraitError."""
    recipe = load_recipe(recipe) if isinstance(recipe, str) else recipe
    if only is not None and only not in recipe["expressions"]:
        raise PortraitError("recipe", "--only %s: no such expression in the recipe (%s)" % (only, ", ".join(recipe["expressions"])))
    grey = load_page(sketch)
    stages = clean_page(grey, recipe)
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


def main(argv=None):
    parser = argparse.ArgumentParser(description="Makes the game's portrait pictures from a photographed pencil drawing.")
    parser.add_argument("--sketch", required=True)
    parser.add_argument("--recipe", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--only")
    parser.add_argument("--stages")
    args = parser.parse_args(argv)
    try:
        make(args.sketch, args.recipe, args.out, args.only, args.stages)
    except PortraitError as error:
        print("sketch_to_portrait: %s" % error, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
