"""The portrait in the game is the tool's output: the sketch tool is run on the owner's drawing with the committed recipe
and the decoded pixels are compared with the committed picture. It fails for a recipe that was edited without the picture
being made again, for a picture painted by hand, and for a change to the tool that moves a pixel.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import sketch_to_portrait as tool  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
SKETCH = os.path.join(REPO, "docs", "art", "owner", "abarax-portrait-sketch-2026-11-14.jpg")
RECIPE = os.path.join(REPO, "docs", "art", "owner", "abarax-portrait-sketch-2026-11-14.recipe.json")
COMMITTED = os.path.join(HERE, "..", "..", "..", "assets", "portraits", "abarax", "neutral.png")


def decode(path):
    return np.asarray(Image.open(path).convert("RGB"))


class CommittedPortraitTest(unittest.TestCase):
    def test_abarax_neutral_is_what_the_tool_makes_of_the_drawing_and_the_recipe(self):
        with tempfile.TemporaryDirectory() as folder:
            tool.make(SKETCH, RECIPE, folder, only="neutral")
            made = decode(os.path.join(folder, "neutral.png"))
        committed = decode(COMMITTED)
        self.assertEqual(made.shape, committed.shape, "the committed picture is not the tool's size")
        differ = np.any(made != committed, axis=-1)
        if differ.any():
            ys, xs = np.nonzero(differ)
            self.fail("assets/portraits/abarax/neutral.png is not what the tool makes of the drawing and the recipe: "
                      "%d pixels differ (first at x %d, y %d; the largest step is %d of 255). Make it again: "
                      "python3 -I tools/portraits/sketch_to_portrait.py --sketch %s --recipe %s --out assets/portraits/abarax"
                      % (int(differ.sum()), int(xs[0]), int(ys[0]),
                         int(np.abs(made.astype(int) - committed.astype(int)).max()),
                         "docs/art/owner/abarax-portrait-sketch-2026-11-14.jpg",
                         "docs/art/owner/abarax-portrait-sketch-2026-11-14.recipe.json"))


if __name__ == "__main__":
    unittest.main()
