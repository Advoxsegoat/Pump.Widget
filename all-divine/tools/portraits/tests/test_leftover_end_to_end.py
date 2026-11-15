"""The tool's check of its own work is on the command line's path: a page whose rules the removal leaves in goes through `main` and
exits 2 with its line (rows and columns of the photograph, and the `keep` hint), writing no portrait; the same page, its rules
taken out, is made. (A made page cannot be found whose rules the real removal fails to take out, so the removal is replaced by one
that takes nothing out: what is tested is that the check runs, and what it says, end to end.)

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import pages  # noqa: E402
import sketch_to_portrait as tool  # noqa: E402


def run_main(args):
    err = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
        code = tool.main(args)
    return code, err.getvalue()


def leaves_the_rules(dark, rules, keep_mask, scale):
    """What `remove_rules` returns when it takes nothing out."""
    return dark.copy(), np.zeros(dark.shape, dtype=bool), [1] * len(rules), [tool.Taken() for _ in rules]


class LeftoverEndToEndTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(self.folder, ignore_errors=True))
        page = pages.make_page(w=600, h=800, spacing=100)
        self.sketch = os.path.join(self.folder, "page.png")
        Image.fromarray((np.clip(page["grey"], 0, 1) * 255.0 + 0.5).astype(np.uint8), mode="L").save(self.sketch)
        self.recipe = os.path.join(self.folder, "r.json")
        with open(self.recipe, "w") as handle:
            json.dump({"paper": "ruled", "crop": [0.2, 0.1, 0.8, 0.9], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
                       "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}}, handle)
        self.out = os.path.join(self.folder, "out")

    def test_a_page_whose_rules_are_left_in_exits_2_with_its_line(self):
        with mock.patch.object(tool, "remove_rules", leaves_the_rules):
            code, err = run_main(["--sketch", self.sketch, "--recipe", self.recipe, "--out", self.out])
        self.assertEqual(code, 2, "rules were left in the portrait and the command exited %d" % code)
        self.assertEqual(len(err.strip().splitlines()), 1, err)
        self.assertRegex(err, r"rules remain: a straight line runs across \d+% of the picture at rows \d+-\d+, columns \d+-\d+ of the photograph")
        self.assertIn("`keep`", err)
        self.assertFalse(os.path.exists(os.path.join(self.out, "neutral.png")), "a portrait was written")

    def test_the_same_page_with_its_rules_taken_out_is_made(self):
        code, err = run_main(["--sketch", self.sketch, "--recipe", self.recipe, "--out", self.out])
        self.assertEqual(code, 0, err)
        self.assertTrue(os.path.exists(os.path.join(self.out, "neutral.png")))


if __name__ == "__main__":
    unittest.main()
