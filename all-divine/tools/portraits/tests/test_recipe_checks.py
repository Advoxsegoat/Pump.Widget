"""The recipe is checked: a missing or misspelt key is refused by name, a crop smaller than a tenth of the page or outside
it, a tint polygon outside the card, an `erase` or `keep` outside the page, a `line_gain` that is not a positive number: each
exits 2 with one line.

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


def recipe_dict(paper="ruled"):
    return {
        "paper": paper,
        "crop": [0.2, 0.1, 0.8, 0.9],
        "erase": [],
        "keep": [],
        "tints": [],
        "card": {"paper": "#ece2c8", "ink": "#2a2830"},
        "line_gain": 1.0,
        "expressions": {"neutral": {}},
    }


def write_recipe(folder, recipe, name="r.json"):
    path = os.path.join(folder, name)
    with open(path, "w") as handle:
        json.dump(recipe, handle)
    return path


def load(recipe):
    with tempfile.TemporaryDirectory() as folder:
        return tool.load_recipe(write_recipe(folder, recipe))


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


def save_grey(grey, folder, name="page.png"):
    path = os.path.join(folder, name)
    Image.fromarray((np.clip(grey, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode="L").save(path)
    return path


class RecipeIsCheckedTest(unittest.TestCase):
    def refused(self, change=None, drop=None):
        recipe = recipe_dict()
        recipe.update(change or {})
        for key in drop or []:
            del recipe[key]
        with tempfile.TemporaryDirectory() as folder:
            path = write_recipe(folder, recipe)
            with self.assertRaises(tool.PortraitError) as caught:
                tool.load_recipe(path)
            sketch = save_grey(pages.make_page(w=600, h=800)["grey"], folder)
            code, err = run_main(["--sketch", sketch, "--recipe", path, "--out", os.path.join(folder, "o")])
        self.assertEqual(code, 2)
        self.assertEqual(len(err.strip().splitlines()), 1, err)
        return str(caught.exception)

    def test_a_missing_key_is_refused_by_name(self):
        for key in ("paper", "crop", "erase", "keep", "tints", "card", "line_gain", "expressions"):
            message = self.refused(drop=[key])
            self.assertIn("'%s'" % key, message, "a recipe with no '%s' must say so" % key)

    def test_a_misspelt_key_is_refused_by_name(self):
        message = self.refused(change={"papr": "ruled"})
        self.assertIn("'papr'", message)

    def test_a_crop_smaller_than_a_tenth_of_the_page_is_refused(self):
        message = self.refused(change={"crop": [0.4, 0.4, 0.45, 0.6]})
        self.assertIn("crop", message)
        self.assertIn("tenth", message)
        message = self.refused(change={"crop": [0.4, 0.4, 0.8, 0.45]})
        self.assertIn("tenth", message)

    def test_a_crop_outside_the_page_is_refused(self):
        self.assertIn("crop", self.refused(change={"crop": [0.5, 0.1, 1.4, 0.9]}))

    def test_a_tint_polygon_outside_the_card_is_refused(self):
        tint = {"name": "wash", "colour": "#c8a890", "polygon": [[0.1, 0.1], [1.3, 0.1], [0.5, 0.9]]}
        message = self.refused(change={"tints": [tint]})
        self.assertIn("tints[0]", message)
        self.assertIn("card", message)

    def test_an_erase_or_keep_outside_the_page_is_refused(self):
        self.assertIn("erase[0]", self.refused(change={"erase": [[0.5, 0.5, 1.2, 0.6]]}))
        self.assertIn("keep[0]", self.refused(change={"keep": [[-0.1, 0.5, 0.3, 0.6]]}))

    def test_a_line_gain_that_is_not_a_positive_number_is_refused(self):
        for bad in (0, -1.0, "dark", None):
            self.assertIn("line_gain", self.refused(change={"line_gain": bad}))



if __name__ == "__main__":
    unittest.main()
