"""Tests for tools/audio/make_blips.py (the dialogue box's voice blip). Standard library only.

Run from the project folder (all-divine/):
    python3 -I -m unittest discover -s tools/audio/tests -v
"""
import math
import os
import subprocess
import sys
import tempfile
import unittest
import wave
import io
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
import make_blips  # noqa: E402

SHIPPED = Path(__file__).resolve().parents[3] / "assets" / "audio" / "sfx" / "voice_blip.wav"


def read(data):
    with wave.open(io.BytesIO(data), "rb") as w:
        raw = w.readframes(w.getnframes())
        samples = [int.from_bytes(raw[i:i + 2], "little", signed=True) / 32768.0 for i in range(0, len(raw), 2)]
        return w.getframerate(), w.getnchannels(), w.getsampwidth(), samples


class MakeBlips(unittest.TestCase):
    def test_the_blip_is_12_ms_16_bit_mono_and_the_same_bytes_every_run(self):
        data = make_blips.render()
        rate, channels, width, samples = read(data)
        self.assertEqual((rate, channels, width), (44100, 1, 2))
        self.assertAlmostEqual(len(samples) / rate, 0.012, delta=0.0005)
        with tempfile.TemporaryDirectory() as one, tempfile.TemporaryDirectory() as two:
            for out, hash_seed in ((one, "1"), (two, "2")):
                env = dict(os.environ, PYTHONHASHSEED=hash_seed)
                done = subprocess.run([sys.executable, "-I", str(TOOL / "make_blips.py"), "--out", out],
                                      env=env, capture_output=True, text=True)
                self.assertEqual(done.returncode, 0, done.stderr)
            a = (Path(one) / "voice_blip.wav").read_bytes()
            b = (Path(two) / "voice_blip.wav").read_bytes()
            self.assertEqual(a, b)
            self.assertEqual(a, data)

    def test_it_is_a_pulse_near_990_hz_that_starts_and_ends_quietly_and_sits_low(self):
        samples = read(make_blips.render())[3]
        crossings = sum(1 for a, b in zip(samples, samples[1:]) if (a < 0.0) != (b < 0.0))
        hz = crossings / 2.0 / (len(samples) / 44100.0)
        self.assertTrue(900.0 <= hz <= 1080.0, "%.0f Hz" % hz)
        peak = max(abs(s) for s in samples)
        self.assertLessEqual(20 * math.log10(peak), -12.0, "heard thirty times a second: well under the fight's sounds")
        self.assertGreaterEqual(20 * math.log10(peak), -24.0, "but heard")
        self.assertLess(abs(samples[0]), 0.1 * peak)
        self.assertLess(abs(samples[-1]), 0.1 * peak)

    def test_the_shipped_file_is_what_the_tool_makes(self):
        self.assertTrue(SHIPPED.exists(), "run tools/audio/make_blips.py")
        self.assertEqual(SHIPPED.read_bytes(), make_blips.render())


if __name__ == "__main__":
    unittest.main()
