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


def scribble(w, h, shift=0.0):
    """Polylines (list of point lists, width) of a face-sized scribble in the middle of a w x h page. Strokes of many
    angles; none is a straight horizontal line (a rule's own direction), the mouth is a shallow curve."""
    cx, cy = w * (0.5 + shift), h * 0.5
    s = w / 900.0
    strokes = []
    strokes.append((polyline_ellipse(cx, cy, 150 * s, 200 * s, 20, 340), 3))        # the head, open at the right foot
    strokes.append((polyline_ellipse(cx + 20 * s, cy - 270 * s, 50 * s, 38 * s), 3))  # a knot above it
    strokes.append(([(cx - 100 * s, cy - 60 * s), (cx - 60 * s, cy - 78 * s), (cx - 20 * s, cy - 66 * s)], 6))  # brows
    strokes.append(([(cx + 30 * s, cy - 66 * s), (cx + 70 * s, cy - 80 * s), (cx + 108 * s, cy - 62 * s)], 6))
    strokes.append(([(cx - 92 * s, cy - 28 * s), (cx - 58 * s, cy - 14 * s), (cx - 24 * s, cy - 30 * s)], 4))  # lash lines
    strokes.append(([(cx + 30 * s, cy - 30 * s), (cx + 64 * s, cy - 12 * s), (cx + 98 * s, cy - 28 * s)], 4))
    strokes.append(([(cx + 4 * s, cy - 40 * s), (cx - 6 * s, cy + 20 * s), (cx - 24 * s, cy + 40 * s), (cx + 14 * s, cy + 42 * s)], 3))  # nose
    strokes.append(([(cx - 56 * s, cy + 96 * s), (cx - 10 * s, cy + 108 * s), (cx + 52 * s, cy + 94 * s)], 4))  # mouth
    strokes.append(([(cx + 84 * s, cy + 10 * s), (cx + 88 * s, cy + 14 * s)], 8))     # a mole
    for k in range(6):                                                                  # hatching at the jaw
        x = cx - 110 * s + 22 * s * k
        strokes.append(([(x, cy + 150 * s), (x + 16 * s, cy + 180 * s)], 3))
    strokes.append(([(cx - 60 * s, cy + 200 * s), (cx - 70 * s, cy + 280 * s), (cx - 130 * s, cy + 340 * s)], 3))  # neck and shoulder
    strokes.append(([(cx + 60 * s, cy + 200 * s), (cx + 70 * s, cy + 280 * s), (cx + 130 * s, cy + 340 * s)], 3))
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
              shift=0.0, grain=0.003):
    """Returns a dict: grey (the page 0..1, float32), strokes (polylines), stroke_mask, rule_mask, rule_lines (row functions)."""
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
        for row, slope in rule_rows(w, h, spacing, degrees):
            lines.append((row, slope))
            for x in range(int(0.06 * w), int(0.98 * w)):
                y = int(round(row + slope * (x - w / 2.0)))
                if 1 <= y < h - 1:
                    rule_mask[y - 1: y + 2, x] = True
    layer = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(layer)
    strokes = scribble(w, h, shift) if face else []
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
