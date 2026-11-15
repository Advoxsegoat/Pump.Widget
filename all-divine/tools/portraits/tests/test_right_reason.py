"""A refusal says the right reason: graph paper says it is squared paper (and what would help: plain or ruled), an under-exposed
photograph says it needs more light (not "plain paper"), a photograph of no drawing still says it is not a pencil drawing on paper.
The made pages are the same page of ruled paper with a scribble, 600 x 800 at the least.

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


def graph_paper(spacing, vertical=0.28, w=700, h=900):
    """A ruled page with the same rules running up and down (squared paper), and a scribble on it."""
    grey = pages.make_page(w=w, h=h, spacing=spacing, face=True)["grey"].copy()
    for x in range(int(spacing), w - 10, int(spacing)):
        grey[:, x - 1: x + 2] *= (1.0 - vertical)
    return grey


def run_main(args):
    err = io.StringIO()
    out = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
        code = tool.main(args)
    return code, err.getvalue()


def save(grey, folder, name="page.png"):
    path = os.path.join(folder, name)
    Image.fromarray((np.clip(grey, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode="L").save(path)
    return path


def recipe_file(folder, paper):
    path = os.path.join(folder, "r.json")
    with open(path, "w") as handle:
        json.dump({"paper": paper, "crop": [0.2, 0.1, 0.8, 0.9], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
                   "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}}, handle)
    return path


class RightReasonTest(unittest.TestCase):
    def test_graph_paper_says_it_is_squared_paper_and_what_would_help(self):
        for spacing in (40, 80):
            with tempfile.TemporaryDirectory() as folder:
                sketch = save(graph_paper(spacing), folder)
                code, err = run_main(["--init-recipe", sketch, "--out", os.path.join(folder, "recipe.json")])
                self.assertEqual(code, 2, "graph paper (%d px) was taken: %s" % (spacing, err))
                self.assertEqual(len(err.strip().splitlines()), 1, err)
                self.assertIn("squared", err, "graph paper (%d px) is refused for the wrong reason: %s" % (spacing, err))
                self.assertIn("plain", err)
                self.assertIn("ruled", err)
                self.assertNotIn("no pencil found", err)
                for paper in ("ruled", "plain"):
                    code, err = run_main(["--sketch", sketch, "--recipe", recipe_file(folder, paper), "--out", os.path.join(folder, "out")])
                    self.assertEqual(code, 2, "graph paper read as %s was made into a portrait" % paper)
                    self.assertIn("squared", err)

    def test_an_underexposed_photograph_says_it_needs_more_light(self):
        grey = np.clip(pages.make_page(w=700, h=900, rules=False)["grey"] * 0.25, 0.0, 1.0)
        with tempfile.TemporaryDirectory() as folder:
            sketch = save(grey, folder)
            code, err = run_main(["--init-recipe", sketch, "--out", os.path.join(folder, "recipe.json")])
        self.assertEqual(code, 2)
        self.assertEqual(len(err.strip().splitlines()), 1, err)
        self.assertIn("more light", err)
        self.assertNotIn("plain paper", err, "a dark photograph of a page is told to use plain paper: %s" % err)

    def test_a_photograph_of_no_drawing_still_says_it_is_not_one(self):
        with tempfile.TemporaryDirectory() as folder:
            sketch = save(pages.photograph(), folder)
            code, err = run_main(["--init-recipe", sketch, "--out", os.path.join(folder, "recipe.json")])
        self.assertEqual(code, 2)
        self.assertIn("not a pencil drawing on paper", err)
        self.assertNotIn("squared", err)
        self.assertNotIn("more light", err)

    def test_a_ruled_page_is_not_called_squared(self):
        grey = pages.make_page(w=700, h=900, spacing=80)["grey"]
        flat = tool.check_page(grey, "ruled")   # must not raise
        self.assertEqual(flat.shape, grey.shape)


if __name__ == "__main__":
    unittest.main()
