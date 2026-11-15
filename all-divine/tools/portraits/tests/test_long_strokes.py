"""A long stroke that lies along a rule is kept when the recipe's `keep` marks it, whatever its length (a mouth, a ground line, a
straight brow on ruled paper), and the rule is gone outside the `keep`. The same stroke with no `keep` is refused with one line
that names the rows (and the columns) it lies along and says to mark it in `keep`.

Made pages 600 x 800 (the smallest the tool takes), rules 100 apart, one pencil stroke 5 px wide laid straight along a rule.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import contextlib
import io
import json
import os
import re
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import pages  # noqa: E402
import sketch_to_portrait as tool  # noqa: E402

W, H = 600, 800
RULE = 2
STROKE_WIDTH = 5


def run_main(args):
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        code = tool.main(args)
    return code, err.getvalue()


def along(length):
    """(page, grey with the stroke, stroke mask, the x range): a straight stroke `length` px long (the page's whole rule when
    it is at least as long), centred on rule RULE."""
    page = pages.make_page(w=W, h=H, spacing=100, degrees=1.0, face=False)
    first, last = int(0.06 * W), int(0.98 * W)
    if length >= last - first:
        x0, x1 = first, last
    else:
        x0 = (W - length) // 2
        x1 = x0 + length
    layer = Image.new("L", (W, H), 0)
    ImageDraw.Draw(layer).line([(x, pages.rule_row_at(page, RULE, x)) for x in range(x0, x1 + 1)], fill=255, width=STROKE_WIDTH)
    stroke = np.asarray(layer) > 0
    return page, page["grey"] * (1.0 - 0.5 * stroke), stroke, (x0, x1)


def keep_around(page, x0, x1):
    """A `keep` rectangle (fractions of the page) round the stroke, 20 px longer at each end (not past the page)."""
    rows = [pages.rule_row_at(page, RULE, x) for x in (x0, x1)]
    return [max(x0 - 20, 0) / float(W), (min(rows) - 12) / float(H), min(x1 + 20, W) / float(W), (max(rows) + 12) / float(H)]


def recipe(keep):
    return {"paper": "ruled", "crop": [0.1, 0.2, 0.9, 0.8], "erase": [], "keep": keep, "tints": [], "line_gain": 1.0,
            "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}}


class LongStrokeTest(unittest.TestCase):
    def go(self, grey, keep):
        folder = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(folder, ignore_errors=True))
        sketch = os.path.join(folder, "page.png")
        Image.fromarray((np.clip(grey, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode="L").save(sketch)
        recipe_path = os.path.join(folder, "r.json")
        with open(recipe_path, "w") as handle:
            json.dump(recipe(keep), handle)
        code, err = run_main(["--sketch", sketch, "--recipe", recipe_path, "--out", os.path.join(folder, "out"),
                              "--stages", os.path.join(folder, "stages")])
        line = None
        stage = os.path.join(folder, "stages", "clean.png")
        if os.path.exists(stage):
            with Image.open(stage) as image:
                line = 1.0 - np.asarray(image.convert("L"), dtype=np.float32) / 255.0
        return code, err, line

    def test_a_long_stroke_along_a_rule_is_kept_inside_its_keep(self):
        for length in (60, 120, 240, 10000):
            page, grey, stroke, (x0, x1) = along(length)
            keep = keep_around(page, x0, x1)
            code, err, line = self.go(grey, [keep])
            self.assertEqual(code, 0, "a stroke of %s px along a rule, inside a `keep`, was refused: %s" % (length, err.strip()))
            ink = float(line[stroke].mean())
            self.assertGreaterEqual(ink, 0.95, "a stroke of %s px along a rule, inside a `keep`: only %.0f%% of its ink is left" % (length, 100 * ink))
            inside = np.zeros((H, W), dtype=bool)
            inside[int(keep[1] * H): int(np.ceil(keep[3] * H)), int(keep[0] * W): int(np.ceil(keep[2] * W))] = True
            rule = page["rule_mask"] & ~inside
            self.assertGreater(int(rule.sum()), 200, "the page holds no rule outside the `keep` to judge (stroke %s)" % length)
            left = float((line[rule] >= 0.05).mean())
            self.assertLessEqual(left, 0.03, "a stroke of %s px: %.0f%% of the rule outside the `keep` is left" % (length, 100 * left))

    def test_the_same_stroke_with_no_keep_is_refused_with_its_rows(self):
        for length in (60, 120, 240, 10000):
            page, grey, stroke, (x0, x1) = along(length)
            code, err, line = self.go(grey, [])
            self.assertEqual(code, 2, "a stroke of %s px along a rule with no `keep` was made into a portrait" % length)
            self.assertEqual(len(err.strip().splitlines()), 1, err)
            self.assertRegex(err, r"rows? \d+-\d+", "the line does not name the rows (stroke %s): %s" % (length, err))
            self.assertRegex(err, r"columns? \d+-\d+", "the line does not name the columns (stroke %s): %s" % (length, err))
            self.assertIn("`keep`", err)
            self.assertNotIn(" of %d" % (len(page["rule_lines"])), err, "a rule's number is no help to the owner: %s" % err)
            rows = [int(v) for v in re.search(r"rows? (\d+)-(\d+)", err).groups()]
            middle = pages.rule_row_at(page, RULE, (x0 + x1) / 2.0)
            self.assertTrue(rows[0] - 12 <= middle <= rows[1] + 12, "the rows %s are not the stroke's (%.0f): %s" % (rows, middle, err))


if __name__ == "__main__":
    unittest.main()
