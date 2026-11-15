"""The spacing of a page's rules is found (not a half, a third or a double of it), at any spacing a photograph of a notebook has.

A sweep of the estimate over made pages (every spacing from 10 to 130 working pixels in steps of 0.5, at three tilts and two
contrasts), the whole tool on made pages at the spacings that used to land on a harmonic, and whole-page photographs of notebooks
ruled at 7.1 mm (college), 8.7 mm (wide) and 6.35 mm (narrow) on a 216 mm and a 148 mm page, at 12 megapixels and at 2.

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


def recipe(paper="ruled"):
    return {"paper": paper, "crop": [0.2, 0.1, 0.8, 0.9], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
            "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}}


class SpacingEstimateTest(unittest.TestCase):
    def test_every_spacing_from_10_to_130_is_found_within_3_percent(self):
        wrong = []
        total = 0
        for contrast in (0.28, 0.08):
            for degrees in (-3.0, 0.0, 3.0):
                for spacing in np.arange(10.0, 130.01, 0.5):
                    # a page of nine rules at the least, so that the longest spacing is seen often enough
                    page = pages.ruled_darkness(400, max(800, int(9 * spacing)), float(spacing), degrees, contrast)
                    found, _strength = tool.estimate_spacing(page)
                    total += 1
                    if abs(found - spacing) > 0.03 * spacing:
                        wrong.append("%.1f px at %g degrees, contrast %g: found %.1f" % (spacing, degrees, contrast, found))
        self.assertEqual(total, 1446)
        self.assertEqual(wrong, [], "%d of %d pages gave a spacing more than 3%% out; the first: %s" % (len(wrong), total, "; ".join(wrong[:6])))

    def test_the_spacings_that_used_to_land_on_a_harmonic_make_a_portrait_with_no_rule_left(self):
        # 18.8, 22.5, 25.5 and 37.5 gave 75, 45, 51 and 75; each at a tilt and a contrast, on a 600 x 800 page with a scribble on it
        for spacing, degrees, contrast in ((18.8, 0.0, 0.28), (22.5, 3.0, 0.28), (25.5, -3.0, 0.2), (37.5, 1.0, 0.28)):
            page = pages.make_page(w=600, h=800, spacing=spacing, degrees=degrees, contrast=contrast)
            try:
                stages = tool.clean_page(page["grey"], tool.check_recipe(recipe()))
            except tool.PortraitError as error:
                self.fail("a clean page ruled %.1f px apart was refused: %s" % (spacing, error))
            self.assertAlmostEqual(stages["spacing"], spacing, delta=0.03 * spacing)
            line = stages["line"]
            rule = page["rule_mask"] & ~dilate(page["stroke_mask"], 4)
            self.assertGreaterEqual(float((line[rule] < 0.05).mean()), 0.97, "rules left at spacing %.1f" % spacing)
            kept = float(np.mean([line[int(round(y)), int(round(x))] > 0.2 for x, y in pages.stroke_samples(page)]))
            self.assertGreaterEqual(kept, 0.9, "strokes gone at spacing %.1f (%.0f%% kept)" % (spacing, 100 * kept))


# A whole page photographed: the page is 0.9 of the picture's width, so a rule `rule_mm` apart is this many pixels of the
# 900-wide working picture apart: 7.1 mm on a 216 mm page 26.6, 8.7 mm 32.6, 6.35 mm 23.8; on a 148 mm page 38.8, 47.6, 34.8.
PHOTOGRAPHS = [(megapixels, page_mm, rule_mm) for page_mm in (216, 148) for rule_mm in (7.1, 8.7, 6.35) for megapixels in (12, 2)]


class WholePageTest(unittest.TestCase):
    def test_a_whole_page_photograph_of_a_notebook_is_made(self):
        for megapixels, page_mm, rule_mm in PHOTOGRAPHS:
            name = "%d MP, a %d mm page ruled %g mm" % (megapixels, page_mm, rule_mm)
            grey, rule_mask, stroke_mask = pages.whole_page_photo(megapixels, page_mm, rule_mm)
            with tempfile.TemporaryDirectory() as folder:
                sketch = os.path.join(folder, "photo.jpg")
                Image.fromarray((grey * 255.0 + 0.5).astype(np.uint8), mode="L").save(sketch, quality=90)
                try:
                    written, stages = tool.first_recipe(sketch)
                except tool.PortraitError as error:
                    self.fail("%s was refused: %s" % (name, error))
            self.assertEqual(written["paper"], "ruled", name)
            true = rule_mm * 0.9 * tool.WORK_WIDTH / page_mm
            self.assertAlmostEqual(stages["spacing"], true, delta=0.03 * true, msg="%s: the spacing" % name)
            h, w = stages["line"].shape
            shrink = lambda mask: np.asarray(Image.fromarray(mask).resize((w, h), Image.BILINEAR), dtype=np.float32) / 255.0
            rules, strokes = shrink(rule_mask), shrink(stroke_mask)
            line = stages["line"]
            bare = (rules > 0.4) & ~dilate(strokes > 0.1, 4)
            self.assertGreater(int(bare.sum()), 2000, name)
            self.assertGreaterEqual(float((line[bare] < 0.05).mean()), 0.97, "%s: rules left in the portrait" % name)
            core = (strokes > 0.8) & ~dilate(rules > 0.1, 4)
            self.assertGreater(int(core.sum()), 500, name)
            self.assertGreaterEqual(float((line[core] > 0.2).mean()), 0.9, "%s: strokes gone" % name)


if __name__ == "__main__":
    unittest.main()
