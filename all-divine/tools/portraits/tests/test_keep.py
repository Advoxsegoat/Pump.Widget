"""A `keep` rectangle is for a stroke that lies along a rule: the stroke stays, and the rule's own darkness under it goes, so
what is left is the pencil and not a grey bar of rule with the pencil in it.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import json
import os
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

RULE = 4
X0, X1 = 360, 470   # the stroke along rule 4
KEEP = [330, 470, 500, 490]  # x0, y0, x1, y1 in working pixels; rows follow the rule below


def made():
    page = pages.make_page(spacing=100, degrees=1.0, face=False)
    grey = page["grey"].copy()
    layer = Image.new("L", (page["w"], page["h"]), 0)
    draw = ImageDraw.Draw(layer)
    points = [(x, pages.rule_row_at(page, RULE, x) + 3.0 * np.sin((x - X0) / 14.0)) for x in range(X0, X1 + 1)]
    draw.line(points, fill=255, width=3)
    stroke = np.asarray(layer) > 0
    grey = grey * (1.0 - 0.45 * stroke)
    mid = pages.rule_row_at(page, RULE, (X0 + X1) / 2.0)
    keep = [[330 / 900.0, (mid - 14) / 1200.0, 500 / 900.0, (mid + 14) / 1200.0]]
    return page, grey, stroke, keep, points


def recipe(keep):
    return {"paper": "ruled", "crop": [0.2, 0.1, 0.8, 0.9], "erase": [], "keep": keep, "tints": [], "line_gain": 1.0,
            "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}}


def load(r):
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "r.json")
        with open(path, "w") as handle:
            json.dump(r, handle)
        return tool.load_recipe(path)


class KeepTest(unittest.TestCase):
    def test_a_kept_stroke_stays_and_the_rule_under_it_goes(self):
        page, grey, stroke, keep, points = made()
        line = tool.clean_page(grey, load(recipe(keep)))["line"]
        dark_share = float(np.mean([line[int(round(y)), int(round(x))] > 0.3 for x, y in points[4:-4]]))
        self.assertGreaterEqual(dark_share, 0.9, "the kept stroke is only %.0f%% dark" % (100 * dark_share))
        # the rule on either side of the stroke, inside the rectangle, is rule and nothing else: it is paper in the picture
        rule = page["rule_mask"].copy()
        rect = np.zeros_like(rule)
        y0, y1 = int(keep[0][1] * 1200), int(keep[0][3] * 1200)
        rect[y0:y1, int(keep[0][0] * 900):int(keep[0][2] * 900)] = True
        beside = rule & rect & ~((np.arange(900)[None, :] >= X0 - 6) & (np.arange(900)[None, :] <= X1 + 6)) & ~stroke
        self.assertGreater(int(beside.sum()), 40, "the rectangle holds no bare rule to judge")
        left = float((line[beside] >= 0.05).mean())
        self.assertLessEqual(left, 0.05, "%.0f%% of the bare rule inside `keep` is still a grey bar" % (100 * left))


if __name__ == "__main__":
    unittest.main()
