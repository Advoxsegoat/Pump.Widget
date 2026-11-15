"""An `erase` rectangle wipes to paper, and its edge is feathered into what lies outside it: a stroke cut by the rectangle
fades out over a few pixels and is not cut off by a straight edge (which reads as a pale slit, a retouch).

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import json
import os
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import pages  # noqa: E402
import sketch_to_portrait as tool  # noqa: E402


def load(erase):
    r = {"paper": "plain", "crop": [0.2, 0.1, 0.8, 0.9], "erase": erase, "keep": [], "tints": [], "line_gain": 1.0,
         "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}}
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "r.json")
        with open(path, "w") as handle:
            json.dump(r, handle)
        return tool.load_recipe(path)


class EraseTest(unittest.TestCase):
    def test_a_stroke_cut_by_an_erase_fades_and_is_not_cut_off(self):
        page = pages.make_page(rules=False, face=False)
        grey = page["grey"].copy()
        grey[300:340, 200:700] *= 0.4   # a wide pencil band across the page
        rect = [450 / 900.0, 280 / 1200.0, 800 / 900.0, 360 / 1200.0]
        line = tool.clean_page(grey, load([rect]))["line"]
        row = line[320]
        self.assertGreater(float(row[300:440].min()), 0.6, "the band outside the rectangle is gone")
        self.assertLessEqual(float(row[470:700].max()), 0.02, "the rectangle does not wipe to paper")
        step = float(np.abs(np.diff(row[400:480])).max())
        self.assertLessEqual(step, 0.2, "the erase leaves a hard edge: the line drops %.2f in one pixel" % step)
        # the fade is a few pixels, not a long smear
        self.assertLessEqual(float(row[420]), 1.0)
        self.assertGreater(float(row[440]), 0.5, "the fade reaches too far outside the rectangle")


if __name__ == "__main__":
    unittest.main()
