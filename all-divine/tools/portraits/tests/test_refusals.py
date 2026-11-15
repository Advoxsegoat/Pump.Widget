"""The tool refuses what it cannot do, and never exits 0 with rules left or strokes gone.

Made pages (see pages.py): a face-sized scribble on paper with rules at many spacings, tilts and contrasts, a shadow from
each side, plain paper, a photograph that is not a drawing, a tiny image, and recipes that are wrong in each way. A page is
either made into a portrait whose rules are gone and whose strokes are kept, or refused with one line; a page the tool is
meant to handle (spacings from 30 working pixels up, tilts to 3 degrees, rules of 5% to 20% contrast, any shadow, plain
paper) must not be refused.

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


class PageClassesTest(unittest.TestCase):
    def outcome(self, page, paper="ruled"):
        """('made', stages) or ('refused', message)."""
        try:
            return "made", tool.clean_page(page["grey"], load(recipe_dict(paper)))
        except tool.PortraitError as error:
            return "refused", str(error)

    def check_page(self, name, page, paper="ruled", must_work=True):
        what, got = self.outcome(page, paper)
        if what == "refused":
            self.assertNotIn("\n", got, "%s: a refusal is one line" % name)
            self.assertFalse(must_work, "%s: a page the tool is meant to handle was refused: %s" % (name, got))
            return
        line = got["line"]
        near_strokes = dilate(page["stroke_mask"], 4)
        rule = page["rule_mask"] & ~near_strokes
        if rule.any():
            share = float((line[rule] < 0.05).mean())
            self.assertGreaterEqual(share, 0.97, "%s: the tool made a portrait with rules left (only %.1f%% of rule pixels are paper)" % (name, 100 * share))
        samples = pages.stroke_samples(page)
        kept = float(np.mean([line[int(round(y)), int(round(x))] > 0.2 for x, y in samples]))
        self.assertGreaterEqual(kept, 0.9, "%s: the tool made a portrait with strokes gone (only %.0f%% of the strokes are dark)" % (name, 100 * kept))

    def test_rule_spacings(self):
        # 600 x 800 pages (the smallest the tool takes: a rule does not need more) at spacings from 12 to 120 working pixels
        for spacing, must_work in ((12, False), (20, True), (30, True), (60, True), (120, True)):
            self.check_page("spacing %d" % spacing, pages.make_page(w=600, h=max(800, 8 * spacing), spacing=spacing), must_work=must_work)

    def test_tilts_to_three_degrees(self):
        for degrees in (-3, 3):
            self.check_page("tilt %d degrees" % degrees, pages.make_page(degrees=degrees))

    def test_rules_of_five_and_twenty_percent_contrast(self):
        for contrast in (0.05, 0.20):
            self.check_page("contrast %.2f" % contrast, pages.make_page(contrast=contrast))

    def test_a_shadow_from_each_side(self):
        for side in ("left", "right", "top", "bottom"):
            self.check_page("shadow from the %s" % side, pages.make_page(shadow=side))

    def test_plain_paper(self):
        self.check_page("plain paper", pages.make_page(rules=False), paper="plain")

    def test_a_photograph_that_is_not_a_drawing_is_refused(self):
        what, got = self.outcome({"grey": pages.photograph()})
        self.assertEqual(what, "refused", "a photograph of no drawing was made into a portrait")
        self.assertIn("pencil drawing on paper", got)
        what, got = self.outcome({"grey": pages.photograph()}, paper="plain")
        self.assertEqual(what, "refused", "a photograph read as plain paper was made into a portrait")

    def test_a_page_that_is_mostly_dark_is_refused(self):
        grey = np.clip(pages.make_page(rules=False)["grey"] * 0.25, 0.0, 1.0)
        what, got = self.outcome({"grey": grey}, paper="plain")
        self.assertEqual(what, "refused", "a dark page was made into a portrait")

    def test_a_tiny_image_is_refused_with_a_line(self):
        page = pages.make_page(w=100, h=140, spacing=14)
        what, got = self.outcome(page)
        self.assertEqual(what, "refused")
        self.assertIn("too small", got)

    def test_rules_that_remain_are_refused_by_their_rows(self):
        # a leftover rule: the cleaned picture has a grey bar along one row that the finder did not remove
        page = pages.make_page(spacing=100)
        stages = tool.clean_page(page["grey"], load(recipe_dict()))
        line = stages["line"].copy()
        line[500:503, 60:850] = 0.4
        with self.assertRaises(tool.PortraitError) as caught:
            tool.check_clean(line, stages["dark"], stages["rules"], 1.0)
        message = str(caught.exception)
        self.assertIn("rules remain", message)
        self.assertRegex(message, r"rows 50\d")
        self.assertNotIn("\n", message)

    def test_a_page_the_rules_cannot_account_for_is_refused(self):
        # for each rule, the longest run of columns with a stroke of the drawing along it (0 on a rule alone and on the owner's
        # drawing); and the line names the rows and columns of the photograph (here twice the working size), not the rule's number
        tool.check_ink([tool.Taken(0.0), tool.Taken(0.03, 10), tool.Taken(0.1, 29)], (800, 600), 2.0)
        with self.assertRaises(tool.PortraitError) as caught:
            tool.check_ink([tool.Taken(0.0), tool.Taken(0.6, 80, (100, 180), (300, 310)), tool.Taken(0.0)], (800, 600), 2.0)
        message = str(caught.exception)
        self.assertIn("ink", message)
        self.assertIn("rows 600-620", message)
        self.assertIn("columns 200-360", message)
        self.assertIn("`keep`", message)
        self.assertNotIn("rule 2 of 3", message)
        self.assertNotIn("\n", message)

    def test_a_drawing_laid_along_the_rules_is_refused_not_erased_in_silence(self):
        page = pages.make_page(spacing=100)
        grey = page["grey"].copy()
        for row, slope in page["rule_lines"][2:9]:
            for x in range(200, 700):
                y = int(round(row + slope * (x - 450.0)))
                grey[y - 2: y + 2, x] *= 0.4
        with self.assertRaises(tool.PortraitError) as caught:
            tool.clean_page(grey, load(recipe_dict()))
        self.assertIn("the drawing was being erased", str(caught.exception))
        self.assertNotIn("\n", str(caught.exception))

    def test_refusals_leave_no_portrait_and_exit_two_with_one_line(self):
        with tempfile.TemporaryDirectory() as folder:
            recipe = write_recipe(folder, recipe_dict())
            for name, grey in (("photo", pages.photograph()), ("tiny", pages.make_page(w=100, h=140, spacing=14)["grey"])):
                sketch = save_grey(grey, folder, name + ".png")
                out = os.path.join(folder, "out_" + name)
                code, err = run_main(["--sketch", sketch, "--recipe", recipe, "--out", out])
                self.assertEqual(code, 2, name)
                self.assertEqual(len(err.strip().splitlines()), 1, "%s: %r" % (name, err))
                self.assertFalse(os.path.exists(os.path.join(out, "neutral.png")), "%s: a portrait was written" % name)


if __name__ == "__main__":
    unittest.main()
