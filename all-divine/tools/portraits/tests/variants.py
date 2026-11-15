"""The owner's own photograph, turned, scaled, dimmed and tipped, in memory: the one real page we have, put through what a phone held
a little askew does to a page. The owner's file is read, never written. Used by test_owner_variants.py.

A variant is (grey picture at the tool's working size, the recipe mapped through the same change, the function that maps a point of
the original page to the variant's, as (x, y) fractions, and back).
"""
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
SKETCH = os.path.join(REPO, "docs", "art", "owner", "abarax-portrait-sketch-2026-11-14.jpg")
RECIPE = os.path.join(REPO, "docs", "art", "owner", "abarax-portrait-sketch-2026-11-14.recipe.json")

_BASE = {}


def base_page():
    """The owner's photograph as a grey picture, 900 wide (the tool's working width: the tool brings a larger one down to it)."""
    if "grey" not in _BASE:
        with Image.open(SKETCH) as opened:
            image = opened.convert("L")
        image = image.resize((900, round(image.height * 900 / image.width)), Image.LANCZOS)
        _BASE["grey"] = image
    return _BASE["grey"]


def paper_tone(image):
    """The page's own paper tone: the bright end of the picture."""
    return int(np.percentile(np.asarray(image), 90))


def _homography(src, dst):
    """The 3 x 3 matrix that takes the four points `src` to `dst`."""
    rows = []
    for (x, y), (u, v) in zip(src, dst):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    rhs = [c for p in dst for c in p]
    h = np.linalg.solve(np.array(rows, dtype=np.float64), np.array(rhs, dtype=np.float64))
    return np.append(h, 1.0).reshape(3, 3)


def _apply(matrix, x, y):
    p = matrix @ np.array([x, y, 1.0])
    return p[0] / p[2], p[1] / p[2]


class Variant:
    def __init__(self, name, image, forward):
        self.name, self.image, self.forward = name, image, forward   # forward: (x, y) in pixels of the base -> of the variant

    def grey(self):
        return np.asarray(self.image, dtype=np.float32) / 255.0

    def rect(self, rect):
        """A rectangle of the base page (fractions), as the bounding rectangle of its corners in the variant (fractions)."""
        base = base_page()
        w, h = base.size
        pts = [self.forward(x * w, y * h) for x in (rect[0], rect[2]) for y in (rect[1], rect[3])]
        vw, vh = self.image.size
        xs, ys = [p[0] / vw for p in pts], [p[1] / vh for p in pts]
        return [max(min(xs), 0.0), max(min(ys), 0.0), min(max(xs), 1.0), min(max(ys), 1.0)]

    def recipe(self, recipe):
        """The recipe mapped through the same change: the crop, `erase` and `keep` are the bounding rectangles of the turned ones; the
        tints are left out (they lie in the crop's own fractions, which the change moves; the strokes are what is looked at)."""
        out = dict(recipe)
        out["crop"] = self.rect(recipe["crop"])
        out["erase"] = [self.rect(r) for r in recipe["erase"]]
        out["keep"] = [self.rect(r) for r in recipe["keep"]]
        out["tints"] = []
        return out


def turned(degrees):
    base = base_page()
    w, h = base.size
    image = base.rotate(degrees, resample=Image.BICUBIC, fillcolor=paper_tone(base))
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)

    def forward(x, y):   # PIL turns counter-clockwise on the screen (y down)
        dx, dy = x - w / 2.0, y - h / 2.0
        return w / 2.0 + c * dx + s * dy, h / 2.0 - s * dx + c * dy
    return Variant("turned %+g" % degrees, image, forward)


def scaled(factor):
    """The photograph at `factor` of its own size (1800 wide: 0.75 and 0.5 are still at least the tool's working width)."""
    with Image.open(SKETCH) as opened:
        full = opened.convert("L")
    image = full.resize((round(full.width * factor), round(full.height * factor)), Image.LANCZOS)
    k = image.width / float(base_page().width)
    return Variant("scaled %g" % factor, image, lambda x, y: (x * k, y * k))


def exposed(factor):
    base = base_page()
    grey = np.clip(np.asarray(base, dtype=np.float32) * factor, 0, 255).astype(np.uint8)
    return Variant("exposed %g" % factor, Image.fromarray(grey, mode="L"), lambda x, y: (x, y))


def keystoned(share):
    """The phone tipped: the top of the page `share` narrower than its foot (a trapezoid), the picture as large as before."""
    base = base_page()
    w, h = base.size
    inset = share * w / 2.0
    corners = [(0, 0), (w, 0), (w, h), (0, h)]
    moved = [(inset, 0), (w - inset, 0), (w, h), (0, h)]
    forward_matrix = _homography(corners, moved)
    inverse = np.linalg.inv(forward_matrix)
    inverse = inverse / inverse[2, 2]
    image = base.transform((w, h), Image.PERSPECTIVE, tuple(inverse.flatten()[:8]), Image.BICUBIC, fillcolor=paper_tone(base))
    return Variant("keystone %g%%" % (100 * share), image, lambda x, y: _apply(forward_matrix, x, y))


def unwarp(variant, line):
    """A picture made of the variant's page (float 0..1, the variant's size) taken back to the original page's frame."""
    w, h = base_page().size
    image = Image.fromarray(np.ascontiguousarray(line, dtype=np.float32), mode="F")
    if variant.name.startswith("turned"):
        degrees = float(variant.name.split()[1])
        out = image.rotate(-degrees, resample=Image.BILINEAR, fillcolor=0.0)
    elif variant.name.startswith("keystone"):
        share = float(variant.name.split()[1].rstrip("%")) / 100.0
        inset = share * w / 2.0
        corners = [(0, 0), (w, 0), (w, h), (0, h)]
        moved = [(inset, 0), (w - inset, 0), (w, h), (0, h)]
        back = _homography(moved, corners)
        back = back / back[2, 2]
        out = image.transform((w, h), Image.PERSPECTIVE, tuple(np.linalg.inv(back).flatten()[:8]), Image.BILINEAR, fillcolor=0.0)
    else:
        out = image
        if out.size != (w, h):
            out = out.resize((w, h), Image.BILINEAR)
    return np.clip(np.asarray(out, dtype=np.float32), 0.0, 1.0)


def every_variant():
    out = [turned(d) for d in (-5, -3, -2, -1, 1, 2, 3, 5)]
    out += [scaled(0.75), scaled(0.5), exposed(0.6), exposed(0.8), exposed(1.2), keystoned(0.03)]
    return out
