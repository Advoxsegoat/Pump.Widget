"""The pages a review of the tool found it failing on, kept as tests: made pages (doodles of ovals, strokes and hatching; nothing of ours draws
a face) of the kind the owner will really send, put through the whole flow a person runs (`--init-recipe`, then the tool on that recipe),
each judged by what is in the portrait (see measures.py) and not by what the tool says of itself.

  critical     tilted pages with strong rules: made right, or refused; never exit 0 with a rule left across the portrait
  init         pages `--init-recipe` used to call "no pencil found" and pages it gave a crop 3% of the page tall: it writes a recipe the tool
               accepts, and the portrait is right
  kept         a stroke on a rule inside a `keep` keeps its ink (no slit down its middle, no ghost of the rule past its end), two thirds of the
               page's width with its exact `keep` is made, and a 30 px stroke on a rule is refused with the `keep` that holds it, then made right
  whole page   photographs of a whole notebook page with a dark desk round it: the desk is not the page, the page's edge is not a rule, a share
               is said to one decimal

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
import measures  # noqa: E402
import pages  # noqa: E402
import sketch_to_portrait as tool  # noqa: E402

JOBS = pages.reviewer_jobs()
PRESENT = 0.95      # of the drawing's pixels, pencil within 2 pixels
LINE_LEFT = 0.15    # more of the width inked along some straight row than the drawing alone has


def run_main(args):
    err, out = io.StringIO(), io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
        code = tool.main(args)
    return code, err.getvalue().strip(), out.getvalue()


class Flow:
    """The README's two commands on one page. `.init_code`, `.init_err`; `.make_code`, `.make_err`; `.rgb` (the portrait or None); `.recipe`."""

    def __init__(self, test, image, name="page"):
        self.folder = tempfile.mkdtemp()
        test.addCleanup(lambda: __import__("shutil").rmtree(self.folder, ignore_errors=True))
        self.sketch = os.path.join(self.folder, name + ".png")
        image.save(self.sketch)
        self.recipe_path = os.path.join(self.folder, name + ".json")
        self.init_code, self.init_err, self.init_out = run_main(["--init-recipe", self.sketch, "--out", self.recipe_path])
        self.make_code, self.make_err, self.rgb, self.recipe = None, "", None, None
        if self.init_code == 0:
            with open(self.recipe_path) as handle:
                self.recipe = json.load(handle)
            self.make()

    def make(self, recipe=None):
        if recipe is not None:
            self.recipe = recipe
            with open(self.recipe_path, "w") as handle:
                json.dump(recipe, handle)
        out = os.path.join(self.folder, "out")
        self.make_code, self.make_err, _ = run_main(["--sketch", self.sketch, "--recipe", self.recipe_path, "--out", out])
        self.rgb = None
        picture = os.path.join(out, "neutral.png")
        if self.make_code == 0 and os.path.exists(picture):
            with Image.open(picture) as shown:
                self.rgb = np.asarray(shown.convert("RGB"))

    def judge(self, truth):
        """(present, stray, extra line) of the portrait against `truth` (a boolean mask of the drawing on the working page)."""
        card = tool.crop_card(truth.astype(np.float32), self.recipe["crop"]) > 0.3
        return measures.against_truth(self.rgb, card)


class CriticalTest(unittest.TestCase):
    def test_tilted_pages_with_strong_rules_are_made_right_or_refused_never_made_with_a_rule_left(self):
        for name in ("sp90_t52_c28", "sp37.5_t52_c28", "sp90_t-52_c28", "sp100_t-52_c28", "sp12_t-52_c28"):
            image, _rows = pages.reviewer_page(**JOBS[name])
            flow = Flow(self, image, name)
            if flow.rgb is None:
                continue
            present, _stray, extra = flow.judge(pages.reviewer_truth())
            self.assertLess(extra, LINE_LEFT, "%s: exit 0 and a line left across the portrait (%.0f%% of its width more than the drawing's own)" % (name, 100 * extra))
            self.assertGreaterEqual(present, PRESENT, "%s: exit 0 and only %.1f%% of the drawing is in the portrait" % (name, 100 * present))

    def test_a_hand_cropped_page_is_made_right_or_refused(self):
        """sp47_t52_c28 with a crop set by hand (the drawing whole): the rules are not left across it."""
        image, _rows = pages.reviewer_page(**JOBS["sp47_t52_c28"])
        flow = Flow(self, image, "hand")
        recipe = {"paper": "ruled", "crop": [0.18, 0.06, 0.82, 0.94], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
                  "card": {"paper": "#efe6cc", "ink": "#2b2a30"}, "expressions": {"neutral": {}}}
        flow.make(recipe)
        if flow.rgb is not None:
            present, _stray, extra = flow.judge(pages.reviewer_truth())
            self.assertLess(extra, LINE_LEFT, "exit 0 and a line left across the portrait (%.0f%%)" % (100 * extra))
            self.assertGreaterEqual(present, PRESENT, "exit 0 and only %.1f%% of the drawing is in the portrait" % (100 * present))


class InitTest(unittest.TestCase):
    EIGHT = ("sp14_t-52_c28", "sp20_t52_c28", "sp22.5_t52_c28", "sp22.5_t-52_c28", "sp25.5_t52_c28", "sp42_t52_c28")
    CROP_3_PERCENT = ("sp42_t-52_c28", "sp47_t52_c28", "sp47_t-52_c28", "sp78_t52_c28")
    ON_A_RULE = ("sp25.5_t-52_c28", "sp28_t-52_c28", "sp53_t-52_c28", "sp110_t-52_c28")

    def check(self, names):
        for name in names:
            image, _rows = pages.reviewer_page(**JOBS[name])
            flow = Flow(self, image, name)
            self.assertEqual(flow.init_code, 0, "%s: --init-recipe refused a page whose drawing is there: %s" % (name, flow.init_err))
            self.assertNotIn("no pencil", flow.init_err)
            self.assertEqual(flow.make_code, 0, "%s: the tool refused the recipe --init-recipe wrote: %s" % (name, flow.make_err))
            present, _stray, extra = flow.judge(pages.reviewer_truth())
            self.assertGreaterEqual(present, PRESENT, "%s: only %.1f%% of the drawing is in the portrait" % (name, 100 * present))
            self.assertLess(extra, LINE_LEFT, "%s: a line is left across the portrait" % name)

    def test_pages_it_called_no_pencil_get_a_recipe_and_a_right_portrait(self):
        self.check(self.EIGHT)

    def test_pages_it_gave_a_crop_3_percent_tall_get_a_recipe_the_tool_accepts(self):
        self.check(self.CROP_3_PERCENT)

    def test_a_stroke_on_a_rule_still_gets_a_recipe_with_the_proposed_keep_in_it(self):
        self.check(self.ON_A_RULE)
        for name in self.ON_A_RULE:
            image, _rows = pages.reviewer_page(**JOBS[name])
            flow = Flow(self, image, name)
            self.assertTrue(flow.recipe["keep"], "%s: no keep in the recipe it wrote" % name)
            self.assertIn("keep", flow.init_out + flow.init_err, "%s: it does not say that it proposes a keep" % name)

    def test_a_recipe_it_writes_is_never_one_the_tool_refuses_for_its_own_content(self):
        for name in self.CROP_3_PERCENT:
            image, _rows = pages.reviewer_page(**JOBS[name])
            flow = Flow(self, image, name)
            self.assertIsNotNone(flow.recipe, "%s: no recipe written: %s" % (name, flow.init_err))
            x0, y0, x1, y1 = flow.recipe["crop"]
            self.assertGreaterEqual(min(x1 - x0, y1 - y0), tool.CROP_LEAST, name)


Y = 500   # a rule of the page below (spacing 100, phase 0)


def stroke_on_rule(length, contrast=0.28):
    x0 = 300 - length // 2

    def extra(draw, w, h):
        draw.line([(x0, Y), (x0 + length, Y)], fill=30, width=5)
    image, _rows = pages.reviewer_page(spacing=100.0, phase=0.0, contrast=contrast, seed=4, extra=extra)
    return image, x0


def plain_reference(length):
    x0 = 300 - length // 2

    def extra(draw, w, h):
        draw.line([(x0, Y), (x0 + length, Y)], fill=30, width=5)
    image, _rows = pages.reviewer_page(spacing=100.0, phase=0.0, contrast=0.28, seed=4, extra=extra, rules=False)
    return image


def line_of(path_sketch, recipe):
    """The tool's levelled line for a page and a recipe (a dict) at the working size."""
    return tool.clean_page(tool.load_page(path_sketch), tool.check_recipe(recipe))["line"]


class KeptStrokeTest(unittest.TestCase):
    def kept_flow(self, length, keep=None):
        image, x0 = stroke_on_rule(length)
        flow = Flow(self, image, "k%d" % length)
        recipe = {"paper": "ruled", "crop": [0.0, 0.1, 1.0, 0.95], "erase": [], "keep": [keep] if keep else [], "tints": [], "line_gain": 1.0,
                  "card": {"paper": "#efe6cc", "ink": "#2b2a30"}, "expressions": {"neutral": {}}}
        flow.make(recipe)
        return flow, x0

    def test_a_stroke_in_a_keep_keeps_its_ink_with_no_slit_and_no_ghost(self):
        for length in (60, 120, 240):
            image, x0 = stroke_on_rule(length)
            keep = [(x0 - 12) / 600.0, (Y - 8) / 800.0, (x0 + length + 12) / 600.0, (Y + 8) / 800.0]
            flow, _ = self.kept_flow(length, keep)
            self.assertEqual(flow.make_code, 0, "a stroke of %d px in its keep was refused: %s" % (length, flow.make_err))
            line = line_of(flow.sketch, flow.recipe)
            reference = tool.clean_page(tool.load_page(self._plain(length)), dict(flow.recipe, paper="plain"))["line"]
            window = (slice(Y - 3, Y + 4), slice(x0 + 4, x0 + length - 3))
            kept = float(line[window].sum() / reference[window].sum())
            self.assertGreaterEqual(kept, 0.95, "a stroke of %d px in a keep keeps only %.0f%% of its ink" % (length, 100 * kept))
            middle = float(line[Y, x0 + 4: x0 + length - 3].mean())
            sides = float((line[Y - 2, x0 + 4: x0 + length - 3].mean() + line[Y + 2, x0 + 4: x0 + length - 3].mean()) / 2.0)
            self.assertGreaterEqual(middle, 0.9 * min(sides, 1.0) if sides > 0.3 else 0.5, "a slit down the middle of a %d px stroke (%.2f against %.2f at its sides)" % (length, middle, sides))
            ghost = float(max(line[Y - 2: Y + 3, x0 + length + 4: x0 + length + 11].max(), line[Y - 2: Y + 3, max(x0 - 11, 0): x0 - 3].max()))
            self.assertLess(ghost, 0.1, "a ghost of the rule (%.2f) past the end of a %d px stroke" % (ghost, length))
            beyond = float(line[Y - 2: Y + 3, x0 + length + 20: 560].max())
            self.assertLess(beyond, 0.1, "the rule is left beyond the keep of a %d px stroke (%.2f)" % (length, beyond))

    def _plain(self, length):
        path = os.path.join(tempfile.mkdtemp(), "plain.png")
        self.addCleanup(lambda: __import__("shutil").rmtree(os.path.dirname(path), ignore_errors=True))
        plain_reference(length).save(path)
        return path

    def test_a_stroke_of_two_thirds_of_the_page_with_its_exact_keep_is_made(self):
        for length in (400, 460, 520):
            x0 = 300 - length // 2
            keep = [(x0 - 3) / 600.0, (Y - 5) / 800.0, (x0 + length + 3) / 600.0, (Y + 5) / 800.0]
            flow, _ = self.kept_flow(length, keep)
            self.assertEqual(flow.make_code, 0, "a stroke of %d px (of 600) with its exact keep was refused: %s" % (length, flow.make_err))
            line = line_of(flow.sketch, flow.recipe)
            reference = tool.clean_page(tool.load_page(self._plain(length)), dict(flow.recipe, paper="plain"))["line"]
            window = (slice(Y - 3, Y + 4), slice(x0 + 4, x0 + length - 3))
            kept = float(line[window].sum() / reference[window].sum())
            self.assertGreaterEqual(kept, 0.95, "a stroke of %d px with its exact keep keeps only %.0f%% of its ink" % (length, 100 * kept))

    def test_a_short_stroke_on_a_rule_is_refused_with_its_keep_then_made_right_with_it(self):
        for length in (30, 40):
            image, x0 = stroke_on_rule(length)
            flow = Flow(self, image, "s%d" % length)
            recipe = {"paper": "ruled", "crop": [0.0, 0.1, 1.0, 0.95], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
                      "card": {"paper": "#efe6cc", "ink": "#2b2a30"}, "expressions": {"neutral": {}}}
            flow.make(recipe)
            self.assertEqual(flow.make_code, 2, "a stroke of %d px on a rule at 28%% contrast was made without a word (exit 0)" % length)
            self.assertEqual(len(flow.make_err.splitlines()), 1, flow.make_err)
            found = re.search(r'"keep": \[\[([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\]\]', flow.make_err)
            self.assertIsNotNone(found, "the line does not give the keep rectangle: %s" % flow.make_err)
            rect = [float(v) for v in found.groups()]
            self.assertLessEqual(rect[0] * 600, x0 + 1)
            self.assertGreaterEqual(rect[2] * 600, x0 + length - 1)
            flow.make(dict(recipe, keep=[rect]))
            self.assertEqual(flow.make_code, 0, "with the keep it gave, a stroke of %d px was refused: %s" % (length, flow.make_err))
            line = line_of(flow.sketch, flow.recipe)
            reference = tool.clean_page(tool.load_page(self._plain(length)), dict(recipe, paper="plain"))["line"]
            window = (slice(Y - 3, Y + 4), slice(x0 + 3, x0 + length - 2))
            kept = float(line[window].sum() / reference[window].sum())
            self.assertGreaterEqual(kept, 0.9, "a stroke of %d px with its keep keeps only %.0f%% of its ink" % (length, 100 * kept))


class WholePageTest(unittest.TestCase):
    CASES = ((216, 7.1), (216, 6.35), (148, 8.7), (148, 6.35))

    def photo(self, page_mm, rule_mm):
        grey, _rules, strokes = pages.whole_page_photo(2, page_mm, rule_mm, degrees=1.0, contrast=0.2, desk=0.22, rule_thick_mm=0.7, shade_from_left=False)
        image = Image.fromarray((np.clip(grey, 0, 1) * 255.0 + 0.5).astype(np.uint8), mode="L")
        return image, strokes

    def test_a_whole_page_with_a_dark_desk_round_it_is_made_right(self):
        for page_mm, rule_mm in self.CASES:
            image, strokes = self.photo(page_mm, rule_mm)
            folder = tempfile.mkdtemp()
            self.addCleanup(lambda f=folder: __import__("shutil").rmtree(f, ignore_errors=True))
            path = os.path.join(folder, "photo.jpg")
            image.save(path, quality=88)
            sketch = Image.open(path)
            sketch.load()
            sketch.close()
            flow = Flow.__new__(Flow)
            flow.folder = folder
            flow.sketch = path
            flow.recipe_path = os.path.join(folder, "photo.json")
            flow.init_code, flow.init_err, flow.init_out = run_main(["--init-recipe", path, "--out", flow.recipe_path])
            label = "%d mm page ruled %s mm" % (page_mm, rule_mm)
            self.assertEqual(flow.init_code, 0, "%s: --init-recipe: %s" % (label, flow.init_err))
            with open(flow.recipe_path) as handle:
                flow.recipe = json.load(handle)
            flow.make()
            self.assertEqual(flow.make_code, 0, "%s: %s" % (label, flow.make_err))
            small = np.asarray(Image.fromarray(strokes).resize((900, 1200), Image.BILINEAR)) > 100
            present, _stray, extra = flow.judge(small)
            self.assertGreaterEqual(present, 0.9, "%s: only %.1f%% of the drawing is in the portrait" % (label, 100 * present))
            self.assertLess(extra, LINE_LEFT, "%s: a line is left across the portrait" % label)

    def test_a_share_is_said_to_one_decimal(self):
        grey = pages.photograph(w=900, h=1200)
        with self.assertRaises(tool.PortraitError) as caught:
            tool.check_page(grey, "plain")
        text = str(caught.exception)
        self.assertRegex(text, r"\d+\.\d%", text)
        self.assertNotRegex(text, r"\b(\d+)% of [^()]*\(at least \1%", text)


if __name__ == "__main__":
    unittest.main()
