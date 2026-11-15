"""`--init-recipe` names the expression from the file's name: `zara-smile-2026-12-02.jpg` gives `smile`; an unknown expression,
or a name that does not follow `<speaker>-<expression>-<date>`, gives `neutral` and says so.

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


def run_main(args):
    err = io.StringIO()
    out = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
        code = tool.main(args)
    return code, out.getvalue(), err.getvalue()


class ExpressionNameTest(unittest.TestCase):
    def test_the_name_gives_the_expression(self):
        for name, want in (("zara-smile-2026-12-02.jpg", "smile"), ("kesra-neutral-2026-12-02.jpg", "neutral"),
                           ("abarax-surprise-2026-11-14.jpeg", "surprise"), ("a/b/noella-angry-2027-01-31.png", "angry"),
                           ("fixture_knuckle-sad-2026-12-02.jpg", "sad"), ("zara-serious-2026-12-02.jpg", "serious")):
            expression, note = tool.expression_from_name(name)
            self.assertEqual((expression, note), (want, None), name)

    def test_an_unknown_expression_or_another_name_gives_neutral_and_says_so(self):
        for name, mention in (("zara-grumpy-2026-12-02.jpg", "grumpy"), ("zara-smile.jpg", "zara-smile.jpg"),
                              ("IMG_4021.jpg", "IMG_4021.jpg"), ("zara-smile-2026-12.jpg", "zara-smile-2026-12.jpg"),
                              ("zara-smile-2026-12-02-copy.jpg", "zara-smile-2026-12-02-copy.jpg")):
            expression, note = tool.expression_from_name(name)
            self.assertEqual(expression, "neutral", name)
            self.assertIsNotNone(note, name)
            self.assertIn("neutral", note)
            self.assertIn(mention, note)
            self.assertIn("<speaker>-<expression>-<date>", note)
            self.assertNotIn("\n", note)

    def test_init_recipe_writes_it_and_says_what_it_did(self):
        grey = pages.make_page(w=600, h=800, rules=False)["grey"]
        with tempfile.TemporaryDirectory() as folder:
            for name, want, said in (("zara-smile-2026-12-02.jpg", "smile", "smile"), ("page.jpg", "neutral", "does not follow")):
                sketch = os.path.join(folder, name)
                Image.fromarray((np.clip(grey, 0, 1) * 255.0 + 0.5).astype(np.uint8), mode="L").save(sketch)
                recipe = os.path.join(folder, name + ".recipe.json")
                code, out, err = run_main(["--init-recipe", sketch, "--out", recipe])
                self.assertEqual(code, 0, err)
                with open(recipe) as handle:
                    written = json.load(handle)
                self.assertEqual(list(written["expressions"]), [want], name)
                self.assertIn(said, out, "%s: stdout does not say it: %r" % (name, out))
                if want == "neutral":
                    self.assertIn("neutral", out)
                    self.assertIn("<speaker>-<expression>-<date>", out)


if __name__ == "__main__":
    unittest.main()
