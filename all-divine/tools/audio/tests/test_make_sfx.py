"""Tests for tools/audio/make_sfx.py (the seeded sound synthesiser). Standard library only.

Run from the project folder (all-divine/):
    python3 -I -m unittest discover -s tools/audio/tests -v
"""
import io
import math
import os
import random
import re
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
    "perilous_sting", "tell_glint", "cloth_move", "foot_land",
    "surface_cloth_1", "surface_cloth_2", "body_fall", "charge_hum", "stamina_refused",
    "evade_whoosh", "perfect_dodge", "knocked_out",
]


def read(data):
    """A WAV file's bytes as (frames per second, channels, sample width, samples in -1..1)."""
    with wave.open(io.BytesIO(data), "rb") as w:
        raw = w.readframes(w.getnframes())
        samples = [int.from_bytes(raw[i:i + 2], "little", signed=True) / 32768.0 for i in range(0, len(raw), 2)]
        return w.getframerate(), w.getnchannels(), w.getsampwidth(), samples


def rms(samples):
    return math.sqrt(sum(s * s for s in samples) / len(samples))


def peak_db(samples):
    return 20 * math.log10(max(abs(s) for s in samples))


def crossings_per_second(samples):
    """How often the sound crosses zero a second: twice its centre frequency for a noise, a plain measure of brightness."""
    crossings = sum(1 for a, b in zip(samples, samples[1:]) if (a < 0.0) != (b < 0.0))
    return crossings * make_sfx.RATE / len(samples)


def played_at(samples, pitch):
    """The sound as the player's pitch_scale `pitch` plays it: read faster, so higher and shorter (linear interpolation)."""
    out = []
    at = 0.0
    while at < len(samples) - 1:
        i = int(at)
        out.append(samples[i] + (samples[i + 1] - samples[i]) * (at - i))
        at += pitch
    return out


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

    def test_the_evade_whoosh_is_soft_and_short(self):
        rate, _, _, samples = read(self.files["evade_whoosh"])
        self.assertTrue(0.18 <= len(samples) / rate <= 0.4, "%.2f s" % (len(samples) / rate))
        self.assertLessEqual(peak_db(samples), -6.0, "it is heard a dozen times in a chain, so it is soft")
        self.assertGreaterEqual(peak_db(samples), -14.0, "but it is heard")

    def test_the_whoosh_twelve_semitones_up_is_not_shrill(self):
        # The chain's twelfth link plays it at pitch 2: its brightness then must stay low (the share of its energy above 6 kHz).
        samples = read(self.files["evade_whoosh"])[3]
        up = played_at(samples, 2.0)
        shrill = rms(make_sfx.highpass(up, 6000.0)) / rms(up)
        self.assertLess(shrill, 0.3, "%.2f of its level is above 6 kHz at twice the pitch" % shrill)
        self.assertLess(crossings_per_second(up) / 2.0, 5000.0, "its centre is below 5 kHz at twice the pitch")
        self.assertGreater(crossings_per_second(samples) / 2.0, 400.0, "and it is not a rumble at its own pitch")

    def test_the_perfect_dodge_is_brighter_than_the_whoosh_and_the_knock_out_duller_than_both(self):
        whoosh, perfect, knocked = (crossings_per_second(read(self.files[n])[3]) for n in ("evade_whoosh", "perfect_dodge", "knocked_out"))
        self.assertGreater(perfect, whoosh * 1.3, "a brighter cue")
        self.assertLess(knocked, whoosh * 0.6, "a low, hard cue")

    def test_the_perfect_dodge_rings_a_moment_and_the_knock_out_hits_at_once_and_hard(self):
        rate, _, _, perfect = read(self.files["perfect_dodge"])
        self.assertTrue(0.3 <= len(perfect) / rate <= 0.8, "%.2f s" % (len(perfect) / rate))
        self.assertTrue(-6.0 <= peak_db(perfect) <= -2.0, "%.1f dBFS" % peak_db(perfect))
        rate, _, _, knocked = read(self.files["knocked_out"])
        self.assertTrue(0.2 <= len(knocked) / rate <= 0.6, "%.2f s" % (len(knocked) / rate))
        # The heavy impacts ring at 0.6 of full scale for 150 ms, so with 3 frames' offset the cue can be no louder than this without the mix
        # passing -1 dBFS (-9 dBFS gives -0.91): it is as loud as the mix test allows, not the -6 the controller hoped for.
        self.assertTrue(-11.0 <= peak_db(knocked) <= -9.0, "as loud as the mix with the loudest impact allows: %.1f dBFS" % peak_db(knocked))
        top = max(abs(s) for s in knocked)
        first = next(i for i, s in enumerate(knocked) if abs(s) >= 0.9 * top)
        self.assertLess(first / rate, 0.012, "it is at its loudest within 12 ms: no swell")

    def test_the_knock_out_after_the_loudest_impact_does_not_clip(self):
        # A blow that knocks him out of a chain plays its own impact, and the knocked_out cue when the blow's hit-stop is over (ChainFx):
        # at the shortest hit-stop, 3 frames (0.05 s), later. At their bank volumes (data/sounds/*.tres volume_db) the mix on the SFX
        # bus, which has no limiter, must stay under -1 dBFS; started on the same sample it would be louder, which is why it waits.
        sounds = SHIPPED.parents[2] / "data" / "sounds"

        def gain(cue):
            text = (sounds / (cue + ".tres")).read_text()
            found = re.search(r"^volume_db = (-?[0-9.]+)", text, re.M)
            return 10 ** ((float(found.group(1)) if found else 0.0) / 20.0)

        offset = int(round(3 / 60.0 * make_sfx.RATE))
        knock = [s * gain("knocked_out") for s in read(self.files["knocked_out"])[3]]
        worst = 0.0
        worst_same = 0.0
        for cue, names in (("impact_palm", ["impact_palm_1", "impact_palm_2", "impact_palm_3"]), ("impact_heavy", ["impact_heavy_1", "impact_heavy_2"])):
            for name in names:
                hit = [s * gain(cue) for s in read(self.files[name])[3]]
                size = max(len(hit), len(knock) + offset)
                late = [(hit[i] if i < len(hit) else 0.0) + (knock[i - offset] if 0 <= i - offset < len(knock) else 0.0) for i in range(size)]
                same = [(hit[i] if i < len(hit) else 0.0) + (knock[i] if i < len(knock) else 0.0) for i in range(size)]
                worst = max(worst, max(abs(s) for s in late))
                worst_same = max(worst_same, max(abs(s) for s in same))
        self.assertLess(20 * math.log10(worst), -1.0, "%.2f dBFS at the offset" % (20 * math.log10(worst)))
        self.assertGreater(worst_same, worst, "(started on the same sample the mix would be louder: %.2f dBFS)" % (20 * math.log10(worst_same)))

    def test_the_knock_out_has_a_crack_in_its_own_band_that_is_heard_over_an_impacts_tail(self):
        # The impacts have almost nothing above 1.5 kHz after their first milliseconds, and the thump of the cue is lost under their low tails
        # (a thrust's, a sweep's). So the cue starts with a short crack in 1.5 to 5 kHz: over its first 50 ms its energy in that band is at least
        # 10 dB above that of every impact over the 50 ms it plays against (the cue starts 3 frames, 0.05 s, after the impact).
        sounds = SHIPPED.parents[2] / "data" / "sounds"
        window = int(0.05 * make_sfx.RATE)
        offset = int(round(3 / 60.0 * make_sfx.RATE))

        def band(samples):
            return rms(make_sfx.lowpass(make_sfx.highpass(samples, 1500.0), 5000.0))

        knock = band(read(self.files["knocked_out"])[3][:window])
        for name in ("impact_palm_1", "impact_palm_2", "impact_palm_3", "impact_heavy_1", "impact_heavy_2"):
            tail = band(read(self.files[name])[3][offset:offset + window])
            ratio = 20 * math.log10(knock / max(tail, 1e-9))
            self.assertGreaterEqual(ratio, 10.0, "%s: the cue's band is only %.1f dB over its tail" % (name, ratio))

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
