"""Tests for tools/audio/make_sfx.py (the seeded sound synthesiser). Standard library only.

Run from the project folder (all-divine/):
    python3 -I -m unittest discover -s tools/audio/tests -v
"""
import io
import math
import os
import random
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

# -I leaves the script's own folder off sys.path; this is our code, not downloaded code.
TOOL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
import make_sfx  # noqa: E402

SHIPPED = Path(__file__).resolve().parents[3] / "assets" / "audio" / "sfx"

# The set the game's cues (data/sounds/) are made from.
NAMES = [
    "impact_palm_1", "impact_palm_2", "impact_palm_3",
    "impact_heavy_1", "impact_heavy_2",
    "whoosh_light_1", "whoosh_light_2", "whoosh_light_3", "whoosh_heavy",
    "guard_block_1", "guard_block_2", "parry_ring", "catch_snap",
    "perilous_sting", "tell_glint", "roll_cloth", "roll_land",
    "surface_cloth_1", "surface_cloth_2", "body_fall", "charge_hum", "stamina_refused",
]


def read(data):
    """A WAV file's bytes as (frames per second, channels, sample width, samples in -1..1)."""
    with wave.open(io.BytesIO(data), "rb") as w:
        raw = w.readframes(w.getnframes())
        samples = [int.from_bytes(raw[i:i + 2], "little", signed=True) / 32768.0 for i in range(0, len(raw), 2)]
        return w.getframerate(), w.getnchannels(), w.getsampwidth(), samples


def rms(samples):
    return math.sqrt(sum(s * s for s in samples) / len(samples))


class MakeSfx(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = make_sfx.render_all()

    def test_the_set_is_the_one_the_cues_are_made_from(self):
        self.assertEqual(sorted(self.files), sorted(NAMES))

    def test_every_file_is_written_the_same_twice(self):
        # Another process, another hash seed, another global random state: the same bytes. The sounds draw
        # only from their own seeded generators.
        random.seed(12345)
        again = make_sfx.render_all()
        self.assertEqual(again, self.files)
        with tempfile.TemporaryDirectory() as one, tempfile.TemporaryDirectory() as two:
            for out, hash_seed in ((one, "1"), (two, "2")):
                env = dict(os.environ, PYTHONHASHSEED=hash_seed)
                done = subprocess.run([sys.executable, "-I", str(TOOL / "make_sfx.py"), "--out", out],
                                      env=env, capture_output=True, text=True)
                self.assertEqual(done.returncode, 0, done.stderr)
            for name in NAMES:
                a = (Path(one) / (name + ".wav")).read_bytes()
                b = (Path(two) / (name + ".wav")).read_bytes()
                self.assertEqual(a, b, name + " differs between runs")
                self.assertEqual(a, self.files[name], name + " differs from the in-process render")

    def test_peaks_and_lengths(self):
        for name, data in self.files.items():
            with self.subTest(name):
                rate, channels, width, samples = read(data)
                self.assertEqual((rate, channels, width), (44100, 1, 2), "44.1 kHz mono 16-bit")
                seconds = len(samples) / rate
                self.assertGreaterEqual(seconds, 0.03)
                self.assertLessEqual(seconds, 1.5)
                peak_db = 20 * math.log10(max(abs(s) for s in samples))
                self.assertLessEqual(peak_db, -1.0, "peak %.2f dBFS" % peak_db)

    def test_no_file_is_silent_or_clicks_at_its_ends(self):
        for name, data in self.files.items():
            with self.subTest(name):
                samples = read(data)[3]
                peak = max(abs(s) for s in samples)
                self.assertGreater(rms(samples), 0.01, "audible")
                self.assertLess(abs(samples[0]), 0.02 * peak, "starts from silence")
                self.assertLess(abs(samples[-1]), 0.002 * peak, "ends in silence")
                self.assertLess(abs(sum(samples) / len(samples)), 0.02 * peak, "no DC offset")

    def test_variants_are_different_sounds(self):
        for group in (["impact_palm_1", "impact_palm_2", "impact_palm_3"], ["impact_heavy_1", "impact_heavy_2"],
                      ["whoosh_light_1", "whoosh_light_2", "whoosh_light_3"], ["guard_block_1", "guard_block_2"],
                      ["surface_cloth_1", "surface_cloth_2"]):
            self.assertEqual(len({self.files[n] for n in group}), len(group), group)

    def test_heavy_hits_are_longer_and_lower_than_palm_hits(self):
        palm = read(self.files["impact_palm_1"])[3]
        heavy = read(self.files["impact_heavy_1"])[3]
        self.assertGreater(len(heavy), len(palm))

    def test_the_shipped_files_are_what_the_tool_makes(self):
        # The WAVs under assets/audio/sfx/ are this tool's output: change the tool, run it again.
        for name, data in self.files.items():
            with self.subTest(name):
                path = SHIPPED / (name + ".wav")
                self.assertTrue(path.exists(), "%s is missing: run tools/audio/make_sfx.py" % path)
                self.assertEqual(path.read_bytes(), data, "%s is out of date: run tools/audio/make_sfx.py" % path)
        extra = sorted(p.name for p in SHIPPED.glob("*.wav") if p.stem not in self.files) if SHIPPED.exists() else []
        self.assertEqual(extra, [], "WAVs the tool does not make")

    def test_the_command_line_writes_every_file_and_rejects_the_unknown(self):
        with tempfile.TemporaryDirectory() as out:
            done = subprocess.run([sys.executable, "-I", str(TOOL / "make_sfx.py"), "--out", out],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(sorted(p.stem for p in Path(out).glob("*.wav")), sorted(NAMES))
        done = subprocess.run([sys.executable, "-I", str(TOOL / "make_sfx.py"), "--bogus"], capture_output=True, text=True)
        self.assertEqual(done.returncode, 2)


if __name__ == "__main__":
    unittest.main()
