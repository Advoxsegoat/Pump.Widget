"""A drawing's own lines across the rules are not rules.

The tool checks its own work after the rules are out (`check_clean`): it must count only ink that runs along a rule's row for the
length a leftover rule has, never ink that crosses the rule. Made pages 600 x 640, rules 100 apart: an ellipse and straight strokes
of 2, 3, 5 and 8 px crossing the rules at 10, 20, 30, 45 and 80 degrees, with the rules at ten phases (the rule grid moved down
in tenths of a spacing, so the ellipse meets a rule at every angle it has); all are made, with no rule left and the strokes kept.
A leftover rule of a third of the page's width is refused, with its rows (of the photograph) and the columns of its longest run,
and the line says to mark a stroke of the drawing in `keep`.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import math
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import pages  # noqa: E402
import sketch_to_portrait as tool  # noqa: E402

W, H = 600, 640
SPACING = 100
ANGLES = (10, 20, 30, 45, 80)
WIDTHS = (2, 3, 5, 8)
# where each straight stroke's middle is (x, the number of the page's rule it crosses, counting from the top: five rules a page), clear of
# the ellipse in the middle and of each other
STRAIGHT = {10: (76, 0), 80: (70, 2), 30: (90, 4), 20: (528, 1), 45: (535, 3)}


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


def recipe():
    return tool.check_recipe({"paper": "ruled", "crop": [0.1, 0.1, 0.9, 0.9], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
                              "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}})


def crossing_page(width, phase):
    """A page with the rules moved down `phase` tenths of a spacing, an ellipse and a straight stroke at each angle, all `width` px."""
    first = 60.0 + phase * SPACING / 10.0
    base = pages.make_page(w=W, h=H, spacing=SPACING, degrees=1.0, face=False, first=first)
    extra = [(pages.polyline_ellipse(300, 300, 120, 180), width)]
    for angle, (x, rule) in STRAIGHT.items():
        row = pages.rule_row_at(base, rule, x)
        t = math.radians(angle)
        dx, dy = 70.0 * math.cos(t), 70.0 * math.sin(t)
        extra.append(([(x - dx, row - dy), (x + dx, row + dy)], width))
    return pages.make_page(w=W, h=H, spacing=SPACING, degrees=1.0, face=False, first=first, extra=extra)


class CrossingTest(unittest.TestCase):
    def test_ellipses_and_straight_strokes_across_the_rules_are_made(self):
        for width in WIDTHS:
            for phase in range(10):
                page = crossing_page(width, phase)
                name = "strokes of %d px, rules at phase %d of 10" % (width, phase)
                try:
                    stages = tool.clean_page(page["grey"], recipe())
                except tool.PortraitError as error:
                    self.fail("%s: refused: %s" % (name, error))
                line = stages["line"]
                bare = page["rule_mask"] & ~dilate(page["stroke_mask"], 4)
                self.assertGreater(int(bare.sum()), 400, name)
                self.assertGreaterEqual(float((line[bare] < 0.05).mean()), 0.97, "%s: rules left" % name)
                samples = pages.stroke_samples(page, min_gap=8.0)
                near = line.copy()   # a stroke 2 px wide is not always under the sample's own pixel: the largest of its 3 x 3 pixels
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        near = np.maximum(near, np.roll(np.roll(line, dy, axis=0), dx, axis=1))
                kept = float(np.mean([near[int(round(y)), int(round(x))] > 0.2 for x, y in samples]))
                self.assertGreaterEqual(kept, 0.9, "%s: strokes gone (%.0f%% kept)" % (name, 100 * kept))

    def test_a_leftover_rule_of_a_third_of_the_page_is_refused_with_its_rows_and_columns(self):
        page = pages.make_page(w=W, h=H, spacing=SPACING, degrees=1.0, face=False)
        stages = tool.clean_page(page["grey"], recipe())
        line = stages["line"].copy()
        row = int(round(pages.rule_row_at(page, 2, 300)))
        line[row - 1: row + 2, 150:350] = 0.4   # 200 of 600 columns: a third of the page's width
        with self.assertRaises(tool.PortraitError) as caught:
            tool.check_clean(line, stages["dark"], stages["rules"], 2.0)   # a photograph twice the working size
        message = str(caught.exception)
        self.assertNotIn("\n", message)
        self.assertRegex(message, r"rows 5\d\d-6\d\d, columns 3\d\d-69\d of the photograph")
        self.assertIn("mark it in the recipe's `keep`", message)
        self.assertIn("if that is a stroke of the drawing", message)

    def test_a_short_run_along_a_rule_is_not_a_leftover_rule(self):
        # what a stroke crossing at a shallow angle leaves in a rule's row: a run of a tenth of the page
        page = pages.make_page(w=W, h=H, spacing=SPACING, degrees=1.0, face=False)
        stages = tool.clean_page(page["grey"], recipe())
        line = stages["line"].copy()
        row = int(round(pages.rule_row_at(page, 2, 300)))
        line[row - 1: row + 2, 270:330] = 0.9
        tool.check_clean(line, stages["dark"], stages["rules"], 1.0)


if __name__ == "__main__":
    unittest.main()
