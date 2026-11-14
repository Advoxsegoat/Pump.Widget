"""Tests of the sketch tool: a page is made here (paper with a shadow down one side, eleven notebook rules tilted up to 4%,
pencil strokes of several angles, two of them lying along a rule for 40 px, one 30 px horizontal stroke between rules) and
the tool is held to what it says; the last test is the owner's own drawing and recipe.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import contextlib
import io
import json
import math
import os
import sys
import tempfile
import unittest
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import sketch_to_portrait as tool  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
SKETCH = os.path.join(REPO, "docs", "art", "owner", "abarax-portrait-sketch-2026-11-14.jpg")
OWNER_RECIPE = os.path.join(REPO, "docs", "art", "owner", "abarax-portrait-sketch-2026-11-14.recipe.json")

W, H = 900, 1200
RULES = 11


def rule_row(i, x):
    """The row of rule i at column x of the made page: spaced 100 rows, tilted from -4% to +4%."""
    return 100.0 + 100.0 * i + (-0.04 + 0.008 * i) * (x - W / 2.0)


def stroke_points(x, i, degrees, half=36):
    """Points of a stroke crossing rule i at column x at an angle, reaching `half` rows above and below it."""
    y = rule_row(i, x)
    t = math.radians(degrees)
    reach = half / math.sin(t)
    p0 = (x - reach * math.cos(t), y - half)
    p1 = (x + reach * math.cos(t), y + half)
    return [(p0[0] + (p1[0] - p0[0]) * k / 60.0, p0[1] + (p1[1] - p0[1]) * k / 60.0) for k in range(61)]


CROSSING = [(300, 2, 90), (420, 3, 60), (540, 4, 35), (660, 5, 22)]
ALONG_RULE = 7          # a stroke lies along this rule from x 400 to 440
BETWEEN = (500, 530)    # a 30 px horizontal stroke between rules 8 and 9


def along_points():
    return [(x, rule_row(ALONG_RULE, x)) for x in range(400, 441)]


def between_points():
    y = (rule_row(8, 515) + rule_row(9, 515)) / 2.0
    return [(x, y) for x in range(BETWEEN[0], BETWEEN[1] + 1)]


def make_page(rules=True, noise=0.003):
    """Returns (grey page 0..1, stroke mask, rule mask) of the made page."""
    rng = np.random.RandomState(7)
    ys, xs = np.mgrid[0:H, 0:W]
    shadow = np.clip(0.55 + (xs / 420.0) * 0.45, 0.0, 1.0)  # a shadow down the left side, gone by x 420
    paper = 0.86 * shadow
    rule_mask = np.zeros((H, W), dtype=bool)
    if rules:
        for i in range(RULES):
            for x in range(60, 880):
                y = int(round(rule_row(i, x)))
                rule_mask[y - 1: y + 2, x] = True
    strokes = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(strokes)
    for x, i, degrees in CROSSING:
        draw.line(stroke_points(x, i, degrees), fill=255, width=3)
    draw.line(along_points(), fill=255, width=3)
    draw.line(between_points(), fill=255, width=3)
    stroke_mask = np.asarray(strokes) > 0
    page = paper * (1.0 - 0.28 * rule_mask) * (1.0 - 0.6 * stroke_mask)
    page = page + rng.normal(0.0, noise * 0.86, page.shape)
    return np.clip(page, 0.0, 1.0).astype(np.float32), stroke_mask, rule_mask


def recipe_dict(paper="ruled", keep=None, tints=None):
    return {
        "paper": paper,
        "crop": [0.2, 0.1, 0.85, 0.9],
        "erase": [],
        "keep": keep or [],
        "tints": tints or [],
        "card": {"paper": "#ece2c8", "ink": "#2a2830"},
        "line_gain": 1.0,
        "expressions": {"neutral": {}},
    }


def keep_rect_for_along():
    pts = along_points()
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return [(min(xs) - 4) / W, (min(ys) - 6) / H, (max(xs) + 4) / W, (max(ys) + 6) / H]


def run_clean(page, recipe):
    parsed = write_and_load(recipe)
    return tool.clean_page(page, parsed)


def write_and_load(recipe):
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "r.json")
        with open(path, "w") as handle:
            json.dump(recipe, handle)
        return tool.load_recipe(path)


def label_reaches(mask, points):
    """Whether the 8-connected dark pixels `mask` join every one of `points` (each looked for within 2 px)."""
    h, w = mask.shape
    snapped = []
    for x, y in points:
        cx, cy = int(round(x)), int(round(y))
        found = None
        for r in range(0, 3):
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    yy, xx = cy + dy, cx + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx]:
                        found = (yy, xx)
                        break
                if found:
                    break
            if found:
                break
        if found is None:
            return False
        snapped.append(found)
    seen = {snapped[0]}
    queue = deque([snapped[0]])
    while queue:
        y, x = queue.popleft()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and (yy, xx) not in seen:
                    seen.add((yy, xx))
                    queue.append((yy, xx))
    return all(p in seen for p in snapped)


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        padded = np.pad(out, 1)
        grown = out.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                grown |= padded[1 + dy: 1 + dy + out.shape[0], 1 + dx: 1 + dx + out.shape[1]]
        out = grown
    return out


def run_main(args):
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        code = tool.main(args)
    return code, err.getvalue()


def save_page(page, folder, name="page.png"):
    path = os.path.join(folder, name)
    Image.fromarray((page * 255.0 + 0.5).astype(np.uint8), mode="L").save(path)
    return path


class SketchToPortraitTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.page, cls.strokes, cls.rules = make_page()
        cls.stages = run_clean(cls.page, recipe_dict(keep=[keep_rect_for_along()]))
        cls.stages_without_keep = run_clean(cls.page, recipe_dict())

    def test_the_paper_is_evened_out(self):
        flat = tool.flatten(self.page)
        near = dilate(self.strokes | self.rules, 6)
        paper = ~near & (np.arange(W)[None, :] > 40)
        worst = float(np.abs(flat[paper] - 1.0).max())
        self.assertLessEqual(worst, 0.03, "the made shadow is still there: paper is %.3f from white" % worst)

    def test_the_rules_are_removed(self):
        line = self.stages["line"]
        near_stroke = dilate(self.strokes, 4)
        rule = self.rules & ~near_stroke
        left = float((line[rule] < 0.05).mean())
        self.assertGreaterEqual(left, 0.97, "only %.1f%% of rule pixels end within 0.05 of paper" % (100 * left))

    def test_every_rule_is_found_once(self):
        self.assertEqual(len(self.stages["rules"]), RULES, "the tool found %d of %d rules" % (len(self.stages["rules"]), RULES))

    def test_strokes_that_cross_a_rule_are_bridged(self):
        mask = self.stages["line"] > 0.2
        for x, i, degrees in CROSSING:
            ok = label_reaches(mask, stroke_points(x, i, degrees))
            self.assertTrue(ok, "the stroke at %d degrees across rule %d is cut in two" % (degrees, i))

    def test_a_stroke_along_a_rule_is_kept(self):
        pts = along_points()
        def dark_share(stages):
            line = stages["line"]
            return float(np.mean([line[int(round(y)), int(round(x))] > 0.5 for x, y in pts]))
        kept = dark_share(self.stages)
        lost_without = dark_share(self.stages_without_keep)
        self.assertGreaterEqual(kept, 0.9, "with its rectangle in `keep` only %.0f%% of the stroke is still dark" % (100 * kept))
        self.assertLess(lost_without, kept, "without `keep` the stroke is just as dark (%.0f%%): the test does not show what `keep` is for" % (100 * lost_without))
        print("\n  a stroke along a rule: %.0f%% kept with `keep`, %.0f%% without (%.0f%% lost)" % (
            100 * kept, 100 * lost_without, 100 * (kept - lost_without)))

    def test_a_horizontal_stroke_between_rules_is_kept(self):
        line = self.stages["line"]
        share = float(np.mean([line[int(round(y)), int(round(x))] > 0.5 for x, y in between_points()]))
        self.assertGreaterEqual(share, 0.95, "only %.0f%% of the stroke between two rules is still dark" % (100 * share))

    def test_plain_paper_needs_no_rules(self):
        page, strokes, _ = make_page(rules=False)
        stages = run_clean(page, recipe_dict(paper="plain"))
        self.assertEqual(stages["rules"], [])
        self.assertTrue(np.array_equal(stages["cleaned"], stages["dark"]), "plain paper: the page was changed")
        line = stages["line"]
        for x, i, degrees in CROSSING:
            self.assertTrue(label_reaches(line > 0.2, stroke_points(x, i, degrees)), "a crossing stroke is cut on plain paper")
        # and a ruled page read as plain keeps its rules: they are the drawing's, as far as the tool is told
        ruled = run_clean(self.page, recipe_dict(paper="plain"))
        self.assertTrue(np.array_equal(ruled["cleaned"], ruled["dark"]))

    def test_ruled_paper_with_no_rules_found_fails_with_a_line(self):
        page, _, _ = make_page(rules=False)
        with tempfile.TemporaryDirectory() as folder:
            sketch = save_page(page, folder)
            recipe = os.path.join(folder, "r.json")
            with open(recipe, "w") as handle:
                json.dump(recipe_dict(), handle)
            code, err = run_main(["--sketch", sketch, "--recipe", recipe, "--out", os.path.join(folder, "out")])
        self.assertEqual(code, 2)
        self.assertIn("rules: none found", err)
        self.assertEqual(len(err.strip().splitlines()), 1, "one line, got: %r" % err)

    def test_a_recipe_key_it_does_not_know_and_a_crop_off_the_page_fail_with_a_line(self):
        with tempfile.TemporaryDirectory() as folder:
            sketch = save_page(self.page, folder)
            for name, change, expect in (("key", {"sepia": 1}, "recipe: "), ("crop", {"crop": [0.5, 0.1, 1.4, 0.9]}, "crop: ")):
                recipe = recipe_dict()
                recipe.update(change)
                path = os.path.join(folder, name + ".json")
                with open(path, "w") as handle:
                    json.dump(recipe, handle)
                code, err = run_main(["--sketch", sketch, "--recipe", path, "--out", os.path.join(folder, "out")])
                self.assertEqual(code, 2, name)
                self.assertIn(expect, err, name)
                self.assertEqual(len(err.strip().splitlines()), 1, name)

    def test_the_output_is_464_by_640_and_the_same_twice(self):
        with tempfile.TemporaryDirectory() as folder:
            sketch = save_page(self.page, folder)
            recipe = os.path.join(folder, "r.json")
            with open(recipe, "w") as handle:
                json.dump(recipe_dict(keep=[keep_rect_for_along()]), handle)
            for out in ("a", "b"):
                code, err = run_main(["--sketch", sketch, "--recipe", recipe, "--out", os.path.join(folder, out)])
                self.assertEqual(code, 0, err)
            with open(os.path.join(folder, "a", "neutral.png"), "rb") as handle:
                first = handle.read()
            with open(os.path.join(folder, "b", "neutral.png"), "rb") as handle:
                second = handle.read()
            self.assertEqual(first, second, "two runs differ")
            image = Image.open(os.path.join(folder, "a", "neutral.png"))
            self.assertEqual(image.size, (464, 640))
            self.assertEqual(image.mode, "RGB")

    def test_the_stages_pictures_are_written_for_a_person(self):
        with tempfile.TemporaryDirectory() as folder:
            sketch = save_page(self.page, folder)
            recipe = os.path.join(folder, "r.json")
            with open(recipe, "w") as handle:
                json.dump(recipe_dict(), handle)
            code, err = run_main(["--sketch", sketch, "--recipe", recipe, "--out", os.path.join(folder, "o"),
                                  "--stages", os.path.join(folder, "s")])
            self.assertEqual(code, 0, err)
            for name in ("flat", "rules", "clean", "crop", "tint"):
                self.assertTrue(os.path.exists(os.path.join(folder, "s", name + ".png")), name)

    def test_a_crop_wider_or_taller_than_the_card_is_padded_not_squashed(self):
        box = tool.card_box((H, W), [0.2, 0.1, 0.5, 0.9])  # tall and thin: padded left and right
        self.assertAlmostEqual((box[2] - box[0]) / (box[3] - box[1]), 464 / 640, places=6)
        self.assertLessEqual(box[0], 0.2 * W)
        self.assertEqual(box[1], 0.1 * H)
        box = tool.card_box((H, W), [0.1, 0.4, 0.9, 0.6])  # wide: padded above and below
        self.assertAlmostEqual((box[2] - box[0]) / (box[3] - box[1]), 464 / 640, places=6)
        self.assertEqual(box[0], 0.1 * W)
        self.assertLess(box[1], 0.4 * H)

    def test_a_tint_lies_under_the_line(self):
        tints = [{"name": "wash", "colour": "#c8a890", "polygon": [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]]}]
        with tempfile.TemporaryDirectory() as folder:
            sketch = save_page(self.page, folder)
            made = {}
            for name, tint in (("plain", []), ("tinted", tints)):
                recipe = os.path.join(folder, name + ".json")
                with open(recipe, "w") as handle:
                    json.dump(recipe_dict(keep=[keep_rect_for_along()], tints=tint), handle)
                code, err = run_main(["--sketch", sketch, "--recipe", recipe, "--out", os.path.join(folder, name)])
                self.assertEqual(code, 0, err)
                made[name] = np.asarray(Image.open(os.path.join(folder, name, "neutral.png")), dtype=np.float32) / 255.0
        plain, tinted = made["plain"], made["tinted"]
        paper = np.array([0xec, 0xe2, 0xc8]) / 255.0
        wash = np.array([0xc8, 0xa8, 0x90]) / 255.0
        lum = lambda a: a @ np.array([0.299, 0.587, 0.114])
        # a stroke's darkness is how far it is from the ground it lies on (the paper, or the wash)
        darkness_plain = (lum(paper) - lum(plain)) / lum(paper)
        darkness_tinted = (lum(wash) - lum(tinted)) / lum(wash)
        inside = np.zeros(plain.shape[:2], dtype=bool)
        inside[100:540, 90:380] = True  # well inside the polygon, away from its feathered edge
        is_paper = inside & (darkness_plain < 0.002)
        self.assertGreater(int(is_paper.sum()), 1000)
        off = np.abs(tinted[is_paper] - wash).max()
        self.assertLessEqual(off, 1.5 / 255.0, "paper inside the polygon is %.3f off the wash colour" % off)
        strokes = inside & (darkness_plain > 0.15)
        self.assertGreater(int(strokes.sum()), 200, "no stroke pixel inside the polygon to test")
        change = np.abs(darkness_tinted[strokes] - darkness_plain[strokes]).max()
        self.assertLessEqual(change, 0.10, "a stroke pixel's darkness moved by %.3f under the wash" % change)

    def test_the_owners_drawing(self):
        self.assertTrue(os.path.exists(OWNER_RECIPE), "the owner's recipe is missing: %s" % OWNER_RECIPE)
        recipe = tool.load_recipe(OWNER_RECIPE)
        stages = tool.clean_page(tool.load_page(SKETCH), recipe)
        # no rule left: the paper's row profile (the lightest fifth of each row of the crop) is flat within 0.02
        h, w = stages["line"].shape
        x0, y0, x1, y1 = [int(v) for v in (recipe["crop"][0] * w, recipe["crop"][1] * h, recipe["crop"][2] * w, recipe["crop"][3] * h)]
        crop = stages["line"][y0:y1, x0:x1]
        profile = np.percentile(crop, 20, axis=1)  # the paper beside the bust: no row of it is darker than another
        self.assertLessEqual(float(profile.max() - profile.min()), 0.02,
                             "a rule is left: the paper's row profile varies by %.3f" % float(profile.max() - profile.min()))
        # along every rule, where it crosses bare paper (left of the bust, and right of it but for the feather's rows) nothing darker than 0.08
        # is left within a row of its middle; what the drawing itself lays along a rule inside the bust is the drawing's
        margins = np.zeros(w, dtype=bool)
        margins[int(0.15 * w): int(0.26 * w)] = True
        margins[int(0.775 * w): int(0.985 * w)] = True
        worst = []
        for coef in stages["rules"]:
            centre, _alone, _ = tool.rule_centre(stages["dark"], coef, w)
            cols = np.nonzero(margins)[0]
            mids = np.round(centre[cols]).astype(int)
            in_feather = (mids > 0.43 * h) & (mids < 0.57 * h) & (cols > 0.74 * w)
            cols, mids = cols[~in_feather], mids[~in_feather]
            left = np.max([stages["line"][mids + o, cols] for o in (-1, 0, 1)], axis=0)
            worst.append(float((left > 0.08).mean()))
        self.assertLessEqual(max(worst), 0.02, "a rule is left across %.1f%% of the bare paper it crossed" % (100 * max(worst)))
        # the drawing's own lines keep their darkness; boxes are in fractions of the page
        for name, box in OWNER_BOXES.items():
            bx0, by0, bx1, by1 = [int(v) for v in (box[0] * w, box[1] * h, box[2] * w, box[3] * h)]
            before = stages["line_before"][by0:by1, bx0:bx1]
            after = stages["line"][by0:by1, bx0:bx1]
            band = stages["band_mask"][by0:by1, bx0:bx1]
            rule_level = float(np.median(stages["line_before"][stages["band_mask"]]))
            expected = np.where(band, np.maximum(before - rule_level, 0.0), before)
            retained = float(after.sum() / max(expected.sum(), 1e-6))
            self.assertGreaterEqual(retained, 0.9, "%s keeps only %.0f%% of its darkness" % (name, 100 * retained))
        mole = stages["line"][int(MOLE[1] * h): int(MOLE[3] * h), int(MOLE[0] * w): int(MOLE[2] * w)]
        self.assertEqual(count_blobs(mole > 0.3), 1, "the mole is not one dark dot")


# Boxes on the owner's page (fractions of it) round the features the portrait must keep. Set from the drawing: the
# brows, the lash lines, the earring's ring, the feather. The mole is the small dark dot under his left eye.
OWNER_BOXES = {
    "left brow": [0.380, 0.330, 0.520, 0.358],
    "right brow": [0.560, 0.330, 0.670, 0.358],
    "left lash line": [0.395, 0.364, 0.520, 0.395],
    "right lash line": [0.565, 0.364, 0.670, 0.395],
    "earring's ring": [0.685, 0.468, 0.730, 0.505],
    "feather": [0.800, 0.435, 0.985, 0.555],
}
MOLE = [0.628, 0.428, 0.655, 0.450]


def count_blobs(mask):
    seen = np.zeros(mask.shape, dtype=bool)
    count = 0
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        count += 1
        queue = deque([(y, x)])
        seen[y, x] = True
        while queue:
            cy, cx = queue.popleft()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = cy + dy, cx + dx
                    if 0 <= yy < mask.shape[0] and 0 <= xx < mask.shape[1] and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        queue.append((yy, xx))
    return count


if __name__ == "__main__":
    unittest.main()
