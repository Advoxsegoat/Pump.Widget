"""The spacing of a page's rules is found (not a half, a third or a double of it), at any spacing a photograph of a notebook has.

A sweep of the lattice finder over made pages (spacings from 10 to 130 working pixels, at three tilts and two contrasts) and the whole
tool on made pages at the spacings that used to land on a harmonic. (Whole-page photographs of notebooks are in test_reviewer_pages.)

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
from measures import parallel  # noqa: E402


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


def recipe(paper="ruled"):
    return {"paper": paper, "crop": [0.2, 0.1, 0.8, 0.9], "erase": [], "keep": [], "tints": [], "line_gain": 1.0,
            "card": {"paper": "#ece2c8", "ink": "#2a2830"}, "expressions": {"neutral": {}}}


def found_spacing(job):
    spacing, degrees, contrast = job
    # a page of eight rules at the least, so that the longest spacing is seen often enough
    page = pages.ruled_darkness(240, max(500, int(8 * spacing)), float(spacing), degrees, contrast)
    lattice = tool.find_lattice(page)
    return None if lattice is None else lattice.spacing


class SpacingEstimateTest(unittest.TestCase):
    def test_every_spacing_from_10_to_130_is_found_within_3_percent(self):
        spacings = sorted(set(np.arange(10.0, 130.01, 3.5).tolist() + [18.8, 22.5, 25.5, 37.5]))
        jobs = [(s, degrees, contrast) for contrast in (0.28, 0.08) for degrees in (-3.0, 0.0, 3.0) for s in spacings]
        found = parallel(found_spacing, jobs)
        wrong = ["%.1f px at %g degrees, contrast %g: found %s" % (job + (None if f is None else "%.1f" % f,))
                 for job, f in zip(jobs, found) if f is None or abs(f - job[0]) > 0.03 * job[0]]
        self.assertEqual(wrong, [], "%d of %d pages gave a spacing more than 3%% out; the first: %s" % (len(wrong), len(jobs), "; ".join(wrong[:6])))

    def test_the_spacings_that_used_to_land_on_a_harmonic_make_a_portrait_with_no_rule_left(self):
        # 18.8, 22.5, 25.5 and 37.5 gave 75, 45, 51 and 75; each at a tilt and a contrast, on a 600 x 800 page with a scribble on it
        for spacing, degrees, contrast in ((18.8, 0.0, 0.28), (22.5, 3.0, 0.28), (25.5, -3.0, 0.2), (37.5, 1.0, 0.28)):
            page = pages.make_page(w=600, h=800, spacing=spacing, degrees=degrees, contrast=contrast)
            try:
                stages = tool.clean_page(page["grey"], tool.check_recipe(recipe()))
            except tool.PortraitError as error:
                self.fail("a clean page ruled %.1f px apart was refused: %s" % (spacing, error))
            self.assertAlmostEqual(stages["spacing"], spacing, delta=0.03 * spacing)
            line = stages["line"]
            rule = page["rule_mask"] & ~dilate(page["stroke_mask"], 4)
            self.assertGreaterEqual(float((line[rule] < 0.05).mean()), 0.97, "rules left at spacing %.1f" % spacing)
            kept = float(np.mean([line[int(round(y)), int(round(x))] > 0.2 for x, y in pages.stroke_samples(page)]))
            self.assertGreaterEqual(kept, 0.9, "strokes gone at spacing %.1f (%.0f%% kept)" % (spacing, 100 * kept))


if __name__ == "__main__":
    unittest.main()
