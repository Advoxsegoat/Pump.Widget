"""The pages a review of the tool found it failing on, kept as tests: made pages (doodles of ovals, strokes and hatching; nothing of ours draws
a face) of the kind the owner will really send, put through the whole flow a person runs (`--init-recipe`, then the tool on that recipe),
each judged by what is in the portrait (see measures.py) and not by what the tool says of itself.

  critical     tilted pages with strong rules: made right, or refused; never exit 0 with a rule left across the portrait
  init         pages `--init-recipe` used to call "no pencil found" and pages it gave a crop 3% of the page tall: it writes a recipe the tool
               accepts, and the portrait is right; a stroke on a rule still gets its recipe, with the proposed `keep` in it
  kept         a stroke on a rule inside a `keep` keeps its ink (no slit down its middle, no ghost of the rule past its end), two thirds of the
               page's width with its exact `keep` is made, and a 30 px stroke on a rule is refused with the `keep` that holds it, then made right
  whole page   photographs of a whole notebook page with a dark desk round it: the desk is not the page, the page's edge is not a rule, a share
               is said to one decimal

The flows run on as many processes as there are cores (the tool is deterministic): the whole file takes a few tens of seconds.

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
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import measures  # noqa: E402
import pages  # noqa: E402
import sketch_to_portrait as tool  # noqa: E402

JOBS = pages.reviewer_jobs()
PRESENT = 0.92      # of the drawing's pixels, pencil within 2 pixels (a stroke that crosses a rule at a shallow angle has a small kink: Minor 8)
LINE_LEFT = 0.15    # more of the width inked along some straight row than the drawing alone has
CRITICAL = ("sp90_t52_c28", "sp37.5_t52_c28", "sp90_t-52_c28", "sp100_t-52_c28", "sp12_t-52_c28")
NO_PENCIL = ("sp14_t-52_c28", "sp20_t52_c28", "sp22.5_t52_c28", "sp22.5_t-52_c28", "sp25.5_t52_c28", "sp42_t52_c28")
CROP_3_PERCENT = ("sp42_t-52_c28", "sp47_t52_c28", "sp47_t-52_c28", "sp78_t52_c28")
ON_A_RULE = ("sp25.5_t-52_c28", "sp28_t-52_c28", "sp53_t-52_c28", "sp110_t-52_c28")
Y = 530   # a rule of the long-stroke pages (spacing 100, phase 30: rows 130, 230, ...)
WHOLE_PAGES = ((216, 7.1), (216, 6.35), (148, 8.7), (148, 6.35))
BLANK = {"paper": "ruled", "crop": [0.0, 0.1, 1.0, 0.95], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
         "card": {"paper": "#efe6cc", "ink": "#2b2a30"}, "expressions": {"neutral": {}}}


def run_main(args):
    err, out = io.StringIO(), io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
        code = tool.main(args)
    return code, err.getvalue().strip(), out.getvalue()


def stroke_page(length, rules=True):
    x0 = 300 - length // 2

    def extra(draw, w, h):
        draw.line([(x0, Y), (x0 + length, Y)], fill=30, width=5)
    image, _rows = pages.reviewer_page(spacing=100.0, phase=30.0, contrast=0.28, seed=4, extra=extra, rules=rules)
    return image, x0


def whole_page(page_mm, rule_mm):
    grey, _rules, strokes = pages.whole_page_photo(2, page_mm, rule_mm, degrees=1.0, contrast=0.2, desk=0.22, rule_thick_mm=0.7, shade_from_left=False)
    return Image.fromarray((np.clip(grey, 0, 1) * 255.0 + 0.5).astype(np.uint8), mode="L"), strokes


class Result:
    """What one run of the README's flow gave (plain data, so that it comes back from another process)."""

    def __init__(self, **kept):
        self.init_code = self.init_err = self.init_out = self.make_code = self.make_err = self.recipe = None
        self.present = self.extra = self.kept = self.slit = self.ghost = self.beyond = self.rect = None
        self.again_code = self.again_err = None
        self.__dict__.update(kept)


def flow(folder, image, name, truth, recipe=None, jpeg=False):
    """`--init-recipe` (unless a recipe is given) and then the tool on the page, in `folder`; the portrait is judged against the working-size
    mask `truth` of the drawing."""
    out = Result()
    sketch = os.path.join(folder, name + (".jpg" if jpeg else ".png"))
    image.save(sketch, quality=88) if jpeg else image.save(sketch)
    recipe_path = os.path.join(folder, name + ".json")
    if recipe is None:
        out.init_code, out.init_err, out.init_out = run_main(["--init-recipe", sketch, "--out", recipe_path])
        if out.init_code != 0:
            return out
        with open(recipe_path) as handle:
            recipe = json.load(handle)
    else:
        with open(recipe_path, "w") as handle:
            json.dump(recipe, handle)
    out.recipe = recipe
    code, err, _ = run_main(["--sketch", sketch, "--recipe", recipe_path, "--out", os.path.join(folder, "out_" + name)])
    out.make_code, out.make_err = code, err
    picture = os.path.join(folder, "out_" + name, "neutral.png")
    if code == 0 and os.path.exists(picture) and truth is not None:
        with Image.open(picture) as shown:
            rgb = np.asarray(shown.convert("RGB"))
        out.present, _stray, out.extra = measures.against_truth(rgb, tool.crop_card(truth.astype(np.float32), recipe["crop"]) > 0.3)
    return out


def ink_in(folder, recipe, window, plain_image):
    """(the levelled line of the page `k.png` in `window`, its sum there as a share of the same window of the page drawn with no rules)."""
    line = tool.clean_page(tool.load_page(os.path.join(folder, "k.png")), tool.check_recipe(recipe))["line"]
    plain_path = os.path.join(folder, "k_plain.png")
    plain_image.save(plain_path)
    reference = tool.clean_page(tool.load_page(plain_path), tool.check_recipe(dict(recipe, paper="plain")))["line"]
    return line, float(line[window].sum() / reference[window].sum())


def do(spec):
    """One job of the file, run in a folder of its own; returns a Result."""
    kind, *args = spec
    with tempfile.TemporaryDirectory() as folder:
        truth = pages.reviewer_truth()
        if kind == "page":
            image, _rows = pages.reviewer_page(**JOBS[args[0]])
            return flow(folder, image, args[0], truth)
        if kind == "hand":
            image, _rows = pages.reviewer_page(**JOBS["sp47_t52_c28"])
            return flow(folder, image, "hand", truth, dict(BLANK, crop=[0.18, 0.06, 0.82, 0.94]))
        if kind == "photo":
            image, strokes = whole_page(*args)
            small = np.asarray(Image.fromarray(strokes).resize((900, 1200), Image.BILINEAR)) > 100
            return flow(folder, image, "photo", small, jpeg=True)
        length = args[0]
        image, x0 = stroke_page(length)
        plain, _ = stroke_page(length, rules=False)
        if kind == "kept":     # a stroke in a keep round it
            keep = [(x0 - 12) / 600.0, (Y - 8) / 800.0, (x0 + length + 12) / 600.0, (Y + 8) / 800.0]
        elif kind == "exact":   # the exact rectangle of a stroke of two thirds of the page
            keep = [(x0 - 3) / 600.0, (Y - 5) / 800.0, (x0 + length + 3) / 600.0, (Y + 5) / 800.0]
        else:                   # "short": no keep at first
            keep = None
        recipe = dict(BLANK, keep=[keep] if keep else [])
        out = flow(folder, image, "k", None, recipe)
        if kind == "short":
            found = re.search(r'"keep": \[\[([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\]\]', out.make_err)
            out.rect = [float(v) for v in found.groups()] if found else None
            if out.make_code == 2 and out.rect:
                recipe = dict(BLANK, keep=[out.rect])
                again = flow(folder, image, "k", None, recipe)
                out.again_code, out.again_err = again.make_code, again.make_err
                if again.make_code == 0:
                    _line, out.kept = ink_in(folder, recipe, (slice(Y - 3, Y + 4), slice(x0 + 3, x0 + length - 2)), plain)
            return out
        if out.make_code == 0:
            line, out.kept = ink_in(folder, recipe, (slice(Y - 3, Y + 4), slice(x0 + 4, x0 + length - 3)), plain)
            middle = float(line[Y, x0 + 4: x0 + length - 3].mean())
            sides = float((line[Y - 2, x0 + 4: x0 + length - 3].mean() + line[Y + 2, x0 + 4: x0 + length - 3].mean()) / 2.0)
            out.slit = (middle, sides)
            out.ghost = float(line[Y - 2: Y + 3, max(x0 - 11, 0): x0 - 3].max())   # the keep reaches 12 px past the stroke's end
            out.beyond = float(line[Y - 2: Y + 3, max(x0 - 70, 5): x0 - 20].max())
        return out


SPECS = ([("page", n) for n in CRITICAL + NO_PENCIL + CROP_3_PERCENT + ON_A_RULE] + [("hand",)] + [("kept", n) for n in (60, 120, 240)]
         + [("exact", n) for n in (400, 520)] + [("short", n) for n in (30, 40)] + [("photo", *p) for p in WHOLE_PAGES])
RESULTS = {}


def setUpModule():
    for spec, result in zip(SPECS, measures.parallel(do, SPECS)):
        RESULTS[spec] = result


class CriticalTest(unittest.TestCase):
    def check_made_right_or_refused(self, name, result):
        if result.make_code != 0 or result.present is None:
            return   # refused (one line, tested elsewhere): never a wrong portrait
        self.assertLess(result.extra, LINE_LEFT, "%s: exit 0 and a line left across the portrait (%.0f%% of its width more than the drawing's own)" % (name, 100 * result.extra))
        self.assertGreaterEqual(result.present, PRESENT, "%s: exit 0 and only %.1f%% of the drawing is in the portrait" % (name, 100 * result.present))

    def test_tilted_pages_with_strong_rules_are_made_right_or_refused_never_made_with_a_rule_left(self):
        for name in CRITICAL:
            self.check_made_right_or_refused(name, RESULTS[("page", name)])

    def test_a_hand_cropped_page_is_made_right_or_refused(self):
        self.check_made_right_or_refused("sp47_t52_c28 with a crop set by hand", RESULTS[("hand",)])


class InitTest(unittest.TestCase):
    def check(self, names):
        for name in names:
            result = RESULTS[("page", name)]
            self.assertEqual(result.init_code, 0, "%s: --init-recipe refused a page whose drawing is there: %s" % (name, result.init_err))
            self.assertNotIn("no pencil", result.init_err)
            self.assertEqual(result.make_code, 0, "%s: the tool refused the recipe --init-recipe wrote: %s" % (name, result.make_err))
            self.assertGreaterEqual(result.present, PRESENT, "%s: only %.1f%% of the drawing is in the portrait" % (name, 100 * result.present))
            self.assertLess(result.extra, LINE_LEFT, "%s: a line is left across the portrait" % name)

    def test_pages_it_called_no_pencil_get_a_recipe_and_a_right_portrait(self):
        self.check(NO_PENCIL)

    def test_pages_it_gave_a_crop_3_percent_tall_get_a_recipe_the_tool_accepts(self):
        self.check(CROP_3_PERCENT)
        for name in CROP_3_PERCENT:
            x0, y0, x1, y1 = RESULTS[("page", name)].recipe["crop"]
            self.assertGreaterEqual(min(x1 - x0, y1 - y0), tool.CROP_LEAST, name)

    def test_a_stroke_on_a_rule_still_gets_a_recipe_with_the_proposed_keep_in_it(self):
        self.check(ON_A_RULE)
        for name in ON_A_RULE:
            result = RESULTS[("page", name)]
            self.assertTrue(result.recipe["keep"], "%s: no keep in the recipe it wrote" % name)
            self.assertIn("`keep`", result.init_out + result.init_err, "%s: it does not say that it proposes a keep" % name)


class KeptStrokeTest(unittest.TestCase):
    def test_a_stroke_in_a_keep_keeps_its_ink_with_no_slit_and_no_ghost(self):
        for length in (60, 120, 240):
            result = RESULTS[("kept", length)]
            self.assertEqual(result.make_code, 0, "a stroke of %d px in its keep was refused: %s" % (length, result.make_err))
            self.assertGreaterEqual(result.kept, 0.95, "a stroke of %d px in a keep keeps only %.0f%% of its ink" % (length, 100 * result.kept))
            middle, sides = result.slit
            self.assertGreaterEqual(middle, 0.9 * min(sides, 1.0) if sides > 0.3 else 0.5, "a slit down the middle of a %d px stroke (%.2f against %.2f at its sides)" % (length, middle, sides))
            self.assertLess(result.ghost, 0.1, "a ghost of the rule (%.2f) past the end of a %d px stroke" % (result.ghost, length))
            self.assertLess(result.beyond, 0.1, "the rule is left beyond the keep of a %d px stroke (%.2f)" % (length, result.beyond))

    def test_a_stroke_of_two_thirds_of_the_page_with_its_exact_keep_is_made(self):
        for length in (400, 520):
            result = RESULTS[("exact", length)]
            self.assertEqual(result.make_code, 0, "a stroke of %d px (of 600) with its exact keep was refused: %s" % (length, result.make_err))
            self.assertGreaterEqual(result.kept, 0.95, "a stroke of %d px with its exact keep keeps only %.0f%% of its ink" % (length, 100 * result.kept))

    def test_a_short_stroke_on_a_rule_is_refused_with_its_keep_then_made_right_with_it(self):
        for length in (30, 40):
            result = RESULTS[("short", length)]
            self.assertEqual(result.make_code, 2, "a stroke of %d px on a rule at 28%% contrast was made without a word (exit 0)" % length)
            self.assertEqual(len(result.make_err.splitlines()), 1, result.make_err)
            self.assertIsNotNone(result.rect, "the line does not give the keep rectangle: %s" % result.make_err)
            x0 = 300 - length // 2
            self.assertLessEqual(result.rect[0] * 600, x0 + 1)
            self.assertGreaterEqual(result.rect[2] * 600, x0 + length - 1)
            self.assertEqual(result.again_code, 0, "with the keep it gave, a stroke of %d px was refused: %s" % (length, result.again_err))
            self.assertGreaterEqual(result.kept, 0.9, "a stroke of %d px with its keep keeps only %.0f%% of its ink" % (length, 100 * result.kept))


class WholePageTest(unittest.TestCase):
    def test_a_whole_page_with_a_dark_desk_round_it_is_made_right(self):
        for page_mm, rule_mm in WHOLE_PAGES:
            label = "%d mm page ruled %s mm" % (page_mm, rule_mm)
            result = RESULTS[("photo", page_mm, rule_mm)]
            self.assertEqual(result.init_code, 0, "%s: --init-recipe: %s" % (label, result.init_err))
            self.assertEqual(result.make_code, 0, "%s: %s" % (label, result.make_err))
            self.assertGreaterEqual(result.present, 0.9, "%s: only %.1f%% of the drawing is in the portrait" % (label, 100 * result.present))
            self.assertLess(result.extra, LINE_LEFT, "%s: a line is left across the portrait" % label)

    def test_a_share_is_said_to_one_decimal(self):
        grey = pages.photograph(w=900, h=1200)
        with self.assertRaises(tool.PortraitError) as caught:
            tool.check_page(grey, "plain")
        text = str(caught.exception)
        self.assertRegex(text, r"\d+\.\d%", text)
        self.assertNotRegex(text, r"\b(\d+)% of [^()]*\(at least \1%", text)


if __name__ == "__main__":
    unittest.main()
