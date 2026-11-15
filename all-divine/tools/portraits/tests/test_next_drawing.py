"""The owner's next drawing is in the game within minutes: `--init-recipe <drawing> --out <recipe.json>` writes a first recipe by
itself (the paper found, ruled or plain; the crop set to the drawing's own bounds; no erase, no keep, no tints), and the tool
run with that recipe gives an untinted portrait that is the drawing, cleaned. Made drawings that are not Abarax's: another
face-sized scribble, on ruled paper at another spacing and tilt, and on plain paper. No value is set by hand.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import pages  # noqa: E402
import sketch_to_portrait as tool  # noqa: E402


def run_main(args):
    err = io.StringIO()
    out = io.StringIO()
    code = 0
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
        try:
            code = tool.main(args)
        except SystemExit as exit_:
            code = exit_.code
    return code, err.getvalue(), out.getvalue()


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


class NextDrawingTest(unittest.TestCase):
    def go(self, name, page, paper):
        with tempfile.TemporaryDirectory() as folder:
            sketch = os.path.join(folder, name + ".png")
            Image.fromarray((np.clip(page["grey"], 0, 1) * 255.0 + 0.5).astype(np.uint8), mode="L").save(sketch)
            recipe = os.path.join(folder, "recipe.json")
            code, err, out = run_main(["--init-recipe", sketch, "--out", recipe])
            self.assertEqual(code, 0, "%s: --init-recipe failed: %s" % (name, err))
            self.assertEqual(err, "")
            with open(recipe) as handle:
                written = json.load(handle)
            self.assertEqual(written["paper"], paper, "%s: the paper found is %s" % (name, written["paper"]))
            self.assertEqual((written["erase"], written["keep"], written["tints"]), ([], [], []), "%s: a first recipe has no erase, keep or tints" % name)
            self.assertEqual(written["line_gain"], 1.0)
            # the crop holds every stroke, and is the drawing's bounds rather than the page
            w, h = page["w"], page["h"]
            x0, y0, x1, y1 = written["crop"]
            samples = pages.stroke_samples(page, min_gap=0.0)
            inside = np.mean([x0 * w <= x <= x1 * w and y0 * h <= y <= y1 * h for x, y in samples])
            self.assertEqual(float(inside), 1.0, "%s: the crop %s leaves strokes out" % (name, written["crop"]))
            self.assertLess((x1 - x0) * (y1 - y0), 0.6, "%s: the crop is nearly the whole page: %s" % (name, written["crop"]))
            made = os.path.join(folder, "made")
            code, err, out = run_main(["--sketch", sketch, "--recipe", recipe, "--out", made])
            self.assertEqual(code, 0, "%s: the tool failed on its own first recipe: %s" % (name, err))
            image = Image.open(os.path.join(made, "neutral.png"))
            self.assertEqual(image.size, (464, 640))
            # untinted: every pixel lies between the card's paper and its ink (no wash)
            rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
            paper = np.array([int(written["card"]["paper"][i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)
            ink = np.array([int(written["card"]["ink"][i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)
            t = (paper - rgb) / (paper - ink)
            self.assertLessEqual(float(np.abs(t - t.mean(axis=-1, keepdims=True)).max()), 0.02, "%s: the portrait is tinted" % name)
            # no rule left, strokes kept, at the working size
            stages = tool.clean_page(page["grey"], tool.check_recipe(written))
            line = stages["line"]
            rule = page["rule_mask"] & ~dilate(page["stroke_mask"], 4)
            if rule.any():
                share = float((line[rule] < 0.05).mean())
                self.assertGreaterEqual(share, 0.97, "%s: rules left (%.1f%% of rule pixels are paper)" % (name, 100 * share))
            kept = float(np.mean([line[int(round(y)), int(round(x))] > 0.2 for x, y in pages.stroke_samples(page)]))
            self.assertGreaterEqual(kept, 0.9, "%s: strokes gone (%.0f%% kept)" % (name, 100 * kept))

    def test_a_scribble_on_ruled_paper_at_another_spacing(self):
        self.go("ruled", pages.make_page(spacing=70, degrees=1.5, shadow="right", shift=-0.08, seed=11), "ruled")

    def test_a_scribble_on_plain_paper(self):
        self.go("plain", pages.make_page(rules=False, shadow="top", shift=0.1, seed=12), "plain")

    def test_a_page_it_cannot_handle_is_said_in_one_line_with_what_would_help(self):
        with tempfile.TemporaryDirectory() as folder:
            sketch = os.path.join(folder, "photo.png")
            Image.fromarray((pages.photograph() * 255.0 + 0.5).astype(np.uint8), mode="L").save(sketch)
            recipe = os.path.join(folder, "recipe.json")
            code, err, out = run_main(["--init-recipe", sketch, "--out", recipe])
            self.assertEqual(code, 2)
            self.assertEqual(len(err.strip().splitlines()), 1, err)
            self.assertIn("plain paper", err)
            self.assertIn("whole page", err)
            self.assertIn("even light", err)
            self.assertFalse(os.path.exists(recipe), "a recipe was written for a page that cannot be handled")

    def test_a_blank_page_has_no_drawing_to_find(self):
        with tempfile.TemporaryDirectory() as folder:
            sketch = os.path.join(folder, "blank.png")
            Image.fromarray(np.full((1200, 900), 220, dtype=np.uint8), mode="L").save(sketch)
            recipe = os.path.join(folder, "recipe.json")
            code, err, out = run_main(["--init-recipe", sketch, "--out", recipe])
            self.assertEqual(code, 2)
            self.assertIn("no pencil", err)
            self.assertEqual(len(err.strip().splitlines()), 1, err)


if __name__ == "__main__":
    unittest.main()
