"""Made pages for the sketch tool's tests: a sheet of paper (a shadow from one side, grain), notebook rules at any
spacing, tilt and contrast, and a face-sized scribble in pencil whose strokes are known, so that a test can say whether the
rules are gone and the strokes are kept. Nothing here draws a face for the game: it is a test fixture, a handful of
polylines at several angles."""
import math

import numpy as np
from PIL import Image, ImageDraw


def polyline_ellipse(cx, cy, rx, ry, a0=0.0, a1=360.0, n=90):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * k / n)))
            for k in range(n + 1)]


def scribble(w, h, shift=0.0, slanted=False):
    """Polylines (list of point lists, width) of a face-sized scribble in the middle of a w x h page. Strokes of many
    angles; none is a straight horizontal line (a rule's own direction), the mouth is a shallow curve. `slanted` also tips the
    foot of the nose (a short, nearly level stroke that, at some rule phases, lies along a rule: the tool refuses that, and
    says to mark it in `keep`)."""
    cx, cy = w * (0.5 + shift), h * 0.5
    s = w / 900.0
    strokes = []
    strokes.append((polyline_ellipse(cx, cy, 150 * s, 200 * s, 20, 340), 3))        # the head, open at the right foot
    strokes.append((polyline_ellipse(cx + 20 * s, cy - 270 * s, 50 * s, 38 * s), 3))  # a knot above it
    strokes.append(([(cx - 100 * s, cy - 60 * s), (cx - 60 * s, cy - 78 * s), (cx - 20 * s, cy - 66 * s)], 6))  # brows
    strokes.append(([(cx + 30 * s, cy - 66 * s), (cx + 70 * s, cy - 80 * s), (cx + 108 * s, cy - 62 * s)], 6))
    strokes.append(([(cx - 92 * s, cy - 28 * s), (cx - 58 * s, cy - 14 * s), (cx - 24 * s, cy - 30 * s)], 4))  # lash lines
    strokes.append(([(cx + 30 * s, cy - 30 * s), (cx + 64 * s, cy - 12 * s), (cx + 98 * s, cy - 28 * s)], 4))
    strokes.append(([(cx + 4 * s, cy - 40 * s), (cx - 6 * s, cy + 20 * s), (cx - 24 * s, cy + 40 * s), (cx + 14 * s, cy + (52 if slanted else 42) * s)], 3))  # nose
    strokes.append(([(cx - 56 * s, cy + 96 * s), (cx - 10 * s, cy + 108 * s), (cx + 52 * s, cy + 94 * s)], 4))  # mouth
    strokes.append(([(cx + 84 * s, cy + 10 * s), (cx + 88 * s, cy + 14 * s)], 8))     # a mole
    for k in range(6):                                                                  # hatching at the jaw
        x = cx - 110 * s + 22 * s * k
        strokes.append(([(x, cy + 150 * s), (x + 16 * s, cy + 180 * s)], 3))
    strokes.append(([(cx - 60 * s, cy + 200 * s), (cx - 70 * s, cy + 280 * s), (cx - 130 * s, cy + 340 * s)], 3))  # neck and shoulder
    strokes.append(([(cx + 60 * s, cy + 200 * s), (cx + 70 * s, cy + 280 * s), (cx + 130 * s, cy + 340 * s)], 3))
    return strokes


def doodle(w, h):
    """Polylines (list of point lists, width) of a head-sized doodle in the middle of a w x h page that is not a face: ovals, a
    tilted oval, hatching, long gentle strokes and two straight ones. For looking at what the tool makes of a page a person might
    really send; nothing of ours draws a face."""
    cx, cy = w * 0.5, h * 0.5
    s = w / 900.0

    def tilted(ex, ey, rx, ry, tilt):
        t = math.radians(tilt)
        return [(cx + ex * s + (rx * s) * math.cos(a) * math.cos(t) - (ry * s) * math.sin(a) * math.sin(t),
                 cy + ey * s + (rx * s) * math.cos(a) * math.sin(t) + (ry * s) * math.sin(a) * math.cos(t))
                for a in [math.radians(k * 4.0) for k in range(0, 91)]]
    strokes = [(polyline_ellipse(cx, cy, 170 * s, 230 * s, 15, 330), 4),
               (polyline_ellipse(cx + 10 * s, cy - 320 * s, 60 * s, 42 * s), 4),
               (tilted(-20, 20, 90, 50, -20), 3),
               ([(cx - 150 * s, cy + 60 * s), (cx - 60 * s, cy + 30 * s), (cx + 40 * s, cy + 55 * s), (cx + 150 * s, cy + 25 * s)], 5),
               ([(cx - 120 * s, cy - 110 * s), (cx - 40 * s, cy - 125 * s), (cx + 60 * s, cy - 100 * s)], 6),
               ([(cx - 70 * s, cy + 230 * s), (cx - 85 * s, cy + 330 * s)], 4),
               ([(cx + 70 * s, cy + 230 * s), (cx + 85 * s, cy + 330 * s)], 4)]
    for k in range(9):    # hatching
        x = cx - 150 * s + 20 * s * k
        strokes.append(([(x, cy + 110 * s), (x + 28 * s, cy + 170 * s)], 3))
    return strokes


def rule_rows(w, h, spacing, degrees, first=None):
    """The rules of a page: a list of (row at the middle column, slope). A common tilt with a slight fan."""
    first = spacing if first is None else first
    out = []
    n = int((h - first - 0.5 * spacing) // spacing) + 1
    base = math.tan(math.radians(degrees))
    for i in range(n):
        out.append((first + i * spacing, base * (1.0 + 0.06 * (i - n / 2.0) / max(n, 1))))
    return out


def make_page(w=900, h=1200, spacing=100, degrees=1.0, contrast=0.28, shadow="left", rules=True, face=True, seed=7,
              shift=0.0, grain=0.003, first=None, extra=None):
    """Returns a dict: grey (the page 0..1, float32), strokes (polylines), stroke_mask, rule_mask, rule_lines (row functions).
    `first` is the row of the first rule (default one spacing down), `extra` more strokes, [(points, width)], drawn with the rest."""
    rng = np.random.RandomState(seed)
    ys, xs = np.mgrid[0:h, 0:w]
    if shadow == "left":
        ramp = xs / (0.47 * w)
    elif shadow == "right":
        ramp = (w - 1 - xs) / (0.47 * w)
    elif shadow == "top":
        ramp = ys / (0.35 * h)
    elif shadow == "bottom":
        ramp = (h - 1 - ys) / (0.35 * h)
    else:
        ramp = np.ones((h, w)) * 9.0
    paper = 0.86 * np.clip(0.55 + ramp * 0.45, 0.0, 1.0)
    rule_mask = np.zeros((h, w), dtype=bool)
    lines = []
    if rules:
        for row, slope in rule_rows(w, h, spacing, degrees, first):
            lines.append((row, slope))
            for x in range(int(0.06 * w), int(0.98 * w)):
                y = int(round(row + slope * (x - w / 2.0)))
                if 1 <= y < h - 1:
                    rule_mask[y - 1: y + 2, x] = True
    layer = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(layer)
    strokes = scribble(w, h, shift) if face else []
    strokes = strokes + list(extra or [])
    for points, width in strokes:
        draw.line(points, fill=255, width=width, joint="curve")
    stroke_mask = np.asarray(layer) > 0
    grey = paper * (1.0 - contrast * rule_mask) * (1.0 - 0.6 * stroke_mask)
    grey = grey + rng.normal(0.0, grain * 0.86, grey.shape)
    return {"grey": np.clip(grey, 0.0, 1.0).astype(np.float32), "strokes": strokes, "stroke_mask": stroke_mask,
            "rule_mask": rule_mask, "rule_lines": lines, "w": w, "h": h}


def rule_row_at(page, index, x):
    row, slope = page["rule_lines"][index]
    return row + slope * (x - page["w"] / 2.0)


def stroke_samples(page, min_gap=4.0):
    """Points along the strokes (every 3 px) that lie at least `min_gap` rows from every rule's middle: where a stroke
    cannot be told from a rule these are left out (the bridging tests cover strokes that cross)."""
    out = []
    for points, _width in page["strokes"]:
        for (x0, y0), (x1, y1) in zip(points[:-1], points[1:]):
            n = max(int(math.hypot(x1 - x0, y1 - y0) / 3.0), 1)
            for k in range(n + 1):
                x, y = x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n
                gap = min([abs(y - rule_row_at(page, i, x)) for i in range(len(page["rule_lines"]))] or [99.0])
                if gap >= min_gap and 0 <= int(round(y)) < page["h"] and 0 <= int(round(x)) < page["w"]:
                    out.append((x, y))
    return out


def photograph(w=900, h=1200, seed=3):
    """Not a drawing: a smooth, textured photograph-like field (blobs of light and shade, fine grain, no paper)."""
    rng = np.random.RandomState(seed)
    field = np.zeros((h, w), dtype=np.float64)
    for scale, amount in ((300, 0.5), (90, 0.3), (25, 0.15), (6, 0.08)):
        small = rng.normal(0.0, 1.0, (h // scale + 3, w // scale + 3))
        img = Image.fromarray(small.astype(np.float32), mode="F").resize((w, h), Image.BICUBIC)
        field += amount * np.asarray(img, dtype=np.float64)
    field = (field - field.min()) / (field.max() - field.min())
    return np.clip(field * 0.9 + 0.05, 0.0, 1.0).astype(np.float32)


_NOISE = {}


def ruled_darkness(w, h, spacing, degrees, contrast, seed=0):
    """The darkness (0 = paper) of a flat page with only rules on it, made cheaply for sweeps of the spacing estimate: rules
    `spacing` rows apart (any fraction), tilted `degrees` with the same slight fan as `make_page`, 3 rows thick, and the paper's
    grain. No shadow, no drawing."""
    key = (w, h, seed)
    if key not in _NOISE:
        _NOISE[key] = np.random.RandomState(seed).normal(0.0, 0.003, (h, w)).astype(np.float32)
    dark = np.zeros((h, w), dtype=np.float32)
    xs = np.arange(int(0.06 * w), int(0.98 * w))
    for row, slope in rule_rows(w, h, spacing, degrees):
        ys = np.round(row + slope * (xs - w / 2.0)).astype(int)
        for o in (-1, 0, 1):
            ok = (ys + o >= 0) & (ys + o < h)
            dark[ys[ok] + o, xs[ok]] = contrast
    return dark + _NOISE[key]


def whole_page_photo(megapixels, page_mm, rule_mm, seed=5, degrees=0.8, contrast=0.22, design=None):
    """A whole-page photograph of a ruled notebook (a made one): the picture is portrait, 3:4; the page is 0.9 of its width, on a
    dark desk, a shadow down one side, rules `rule_mm` apart (None: plain paper) from 30 mm down, the page `page_mm` wide (a 216 mm or 148 mm page is
    279 or 210 mm tall), and a face-sized scribble across the middle of it, its lines as wide as a soft pencil's (0.5 mm).
    `design` makes the strokes, (w, h) -> [(points, width)] (default: `scribble`).
    Returns (grey float32 H x W, rule mask uint8 0/255, stroke mask uint8 0/255), all the picture's size."""
    w = int(round(math.sqrt(megapixels * 1e6 * 3.0 / 4.0) / 8.0)) * 8
    h = w * 4 // 3
    px_mm = 0.9 * w / page_mm
    page_h = px_mm * (279.0 if page_mm > 200 else 210.0)
    x0, y0 = 0.05 * w, (h - page_h) / 2.0
    ys = np.arange(h, dtype=np.float32)[:, None]
    xs = np.arange(w, dtype=np.float32)[None, :]
    on_rows = (ys >= y0) & (ys < y0 + page_h)
    on_cols = (xs >= x0) & (xs < x0 + 0.9 * w)
    shade = np.clip(0.5 + 0.5 * (xs - x0) / (0.5 * w), 0.0, 1.0)
    grey = np.where(on_rows & on_cols, 0.82 * (0.6 + 0.4 * shade), 0.30).astype(np.float32)
    rules = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(rules)
    thick = max(1, int(round(0.25 * px_mm)))
    slope = math.tan(math.radians(degrees))
    row = y0 + 30.0 * px_mm
    while rule_mm and row < y0 + page_h - 8.0 * px_mm:
        draw.line([(x0 + 0.02 * w, row + slope * (0.02 * w - 0.45 * w)), (x0 + 0.88 * w, row + slope * (0.88 * w - 0.45 * w))], fill=255, width=thick)
        row += rule_mm * px_mm
    strokes = Image.new("L", (w, h), 0)
    sdraw = ImageDraw.Draw(strokes)
    for points, width in (design or (lambda a, b: scribble(a, b, slanted=True)))(w, h):
        sdraw.line(points, fill=255, width=max(1, int(round(width / 4.0 * 0.5 * px_mm))), joint="curve")
    rule_mask, stroke_mask = np.asarray(rules), np.asarray(strokes)
    grey *= np.float32(1.0) - np.float32(contrast) * (rule_mask > 0)
    grey *= np.float32(1.0) - np.float32(0.6) * (stroke_mask > 0)
    grey += np.random.default_rng(seed).standard_normal((h, w), dtype=np.float32) * np.float32(0.004)
    return np.clip(grey, 0.0, 1.0, out=grey), rule_mask, stroke_mask
