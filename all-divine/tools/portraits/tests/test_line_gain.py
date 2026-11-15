"""`line_gain`: the recipe's one number for how heavy the pencil is drawn. 1.0 is the line as drawn; the darkness is raised
to the power `line_gain`, so 0.7 lifts the faint strokes more than the dark ones (the pencil reads better when the card is
drawn small) without thickening anything.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
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

PAPER = np.array([0xec, 0xe2, 0xc8], dtype=np.float64)
INK = np.array([0x2a, 0x28, 0x30], dtype=np.float64)


def recipe_with(gain):
    return {"paper": "plain", "crop": [0.2, 0.1, 0.8, 0.9], "erase": [], "keep": [], "tints": [],
            "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "line_gain": gain, "expressions": {"neutral": {}}}


def darkness_of(path):
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    return ((PAPER - rgb) / (PAPER - INK)).mean(axis=-1)


class LineGainTest(unittest.TestCase):
    def test_a_gain_raises_the_darkness_to_that_power(self):
        page = pages.make_page(rules=False)
        with tempfile.TemporaryDirectory() as folder:
            sketch = os.path.join(folder, "page.png")
            Image.fromarray((page["grey"] * 255.0 + 0.5).astype(np.uint8), mode="L").save(sketch)
            made = {}
            for gain in (1.0, 0.7):
                recipe = os.path.join(folder, "r%s.json" % gain)
                with open(recipe, "w") as handle:
                    json.dump(recipe_with(gain), handle)
                tool.make(sketch, recipe, os.path.join(folder, "o%s" % gain))
                made[gain] = darkness_of(os.path.join(folder, "o%s" % gain, "neutral.png"))
        d1, d7 = made[1.0], made[0.7]
        self.assertGreater(float(d1.max()), 0.5, "the made page has no line to measure")
        self.assertGreater(float(d7.sum()), 1.1 * float(d1.sum()), "gain 0.7 did not make the pencil heavier")
        # where the line is faint the 8-bit picture's own rounding is multiplied by the power's steep start: judge from 0.1 up
        solid = d1 >= 0.1
        self.assertGreater(int(solid.sum()), 500)
        worst = float(np.abs(d7[solid] - np.clip(d1[solid], 0.0, 1.0) ** 0.7).max())
        self.assertLessEqual(worst, 3.0 / 255.0, "gain 0.7 is not the darkness to the power 0.7 (off by %.3f)" % worst)


if __name__ == "__main__":
    unittest.main()
