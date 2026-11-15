"""The test that counts: the owner's own photograph (the one real page we have: real paper, real rules, real pencil), turned by 1, 2, 3 and
5 degrees either way, scaled to 0.75 and 0.5, exposed at 0.6, 0.8 and 1.2, and tipped (a 3% keystone), each put through the whole tool
with his recipe mapped through the same change. Each is either made RIGHT (mapped back to the drawing's own frame, at least 97% of the
committed portrait's stroke pixels are present within 2 card pixels, and no straight line is left across the paper) or REFUSED with one
line; a wrong portrait with exit 0 is never allowed. The photographs turned up to 3 degrees must be made, not refused. The owner's file is
read, never written (the variants are made in memory). A table of what happened is printed with `-v`.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import sketch_to_portrait as tool  # noqa: E402
import variants  # noqa: E402
from measures import ink_of, lines_left  # noqa: E402

COMMITTED = os.path.join(HERE, "..", "..", "..", "assets", "portraits", "abarax", "neutral.png")
STROKES_PRESENT = 0.97


class OwnerVariantsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recipe = tool.load_recipe(variants.RECIPE)
        with Image.open(COMMITTED) as image:
            cls.reference = ink_of(np.asarray(image.convert("RGB")))
        cls.rows = {}
        with tempfile.TemporaryDirectory() as folder:
            for v in variants.every_variant():
                cls.rows[v.name] = cls.judge(v, folder)
        print("\n%-16s %-8s %s" % ("variant", "result", "what"))
        for name, (result, what) in cls.rows.items():
            print("%-16s %-8s %s" % (name, result, what))

    @classmethod
    def judge(cls, v, folder):
        path = os.path.join(folder, "v.png")
        v.image.save(path)
        try:
            recipe = tool.check_recipe(v.recipe(cls.recipe))
            stages = tool.clean_page(tool.load_page(path), recipe)
        except tool.PortraitError as error:
            return "refused", str(error)[:150]
        back = variants.unwarp(v, stages["line"])
        card = tool.crop_card(back, cls.recipe["crop"])
        ink = ink_of(tool.compose(card, cls.recipe))
        near = np.asarray(Image.fromarray((ink * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
        share = float(near[cls.reference].mean())
        cover, slope, _row = lines_left(stages["line"])
        if share >= STROKES_PRESENT and cover < 0.6:
            return "right", "strokes present %.1f%%, most inked row %.0f%%" % (100 * share, 100 * cover)
        return "WRONG", "strokes present %.1f%% (need %.0f%%), a line across %.0f%% of the page at slope %+.3f" % (
            100 * share, 100 * STROKES_PRESENT, 100 * cover, slope)

    def test_the_committed_portrait_itself_passes_our_measures(self):
        """The yardstick: the untouched photograph is right by the same measures (so the variants are judged by something that can say yes)."""
        with tempfile.TemporaryDirectory() as folder:
            result, what = self.judge(variants.turned(0), folder)
        self.assertEqual(result, "right", what)

    def test_no_variant_is_a_wrong_portrait_made_with_exit_0(self):
        wrong = {name: what for name, (result, what) in self.rows.items() if result == "WRONG"}
        self.assertEqual(wrong, {}, "wrong portraits made (and the tool exited 0): %s" % wrong)

    def test_the_photograph_turned_up_to_3_degrees_is_made(self):
        for degrees in (-3, -2, -1, 1, 2, 3):
            result, what = self.rows["turned %+g" % degrees]
            self.assertEqual(result, "right", "turned %+g: %s: %s" % (degrees, result, what))

    def test_every_variant_that_is_refused_is_refused_in_one_line(self):
        for name, (result, what) in self.rows.items():
            if result == "refused":
                self.assertNotIn("\n", what, name)


if __name__ == "__main__":
    unittest.main()
