#!/usr/bin/env python3
"""Makes the dialogue box's voice blip: assets/audio/sfx/voice_blip.wav.

    python3 -I tools/audio/make_blips.py [--out assets/audio/sfx]

The blip is the one sound a player hears thirty times a second (the box types 30 characters a second and blips
on every second one), so it is the quietest and shortest sound in the game: a 12 ms pulse wave of 0.5 duty
near 990 Hz, like the text blip of the earlier Tactics game, peaking at PEAK_DB. The cue
(data/sounds/voice_blip.tres) plays it on the Voice bus, and each speaker's `blip_pitch` makes it theirs.

Standard library only. The file is the same bytes on every run: the sound is a pure function of the numbers
below (it draws nothing from any random generator, so there is no seed to keep), and nothing is stamped with a time.
"""
import argparse
import io
import math
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
SECONDS = 0.012
FREQUENCY = 990.0
#: The pulse's share of each cycle that it is high.
DUTY = 0.5
#: Quiet on purpose: well under the fight's sounds (the palm's impact peaks at -1.5 dBFS).
PEAK_DB = -16.0
#: The rise and the fall (seconds), so that the blip starts and ends without a click.
ATTACK = 0.001
RELEASE = 0.003
NAME = "voice_blip"
DEFAULT_OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"


def render():
    """The blip as the bytes of a WAV file."""
    n = int(round(SECONDS * RATE))
    rise = int(round(ATTACK * RATE))
    fall = int(round(RELEASE * RATE))
    ints = []
    for i in range(n):
        cycle = (i * FREQUENCY / RATE) % 1.0
        s = 1.0 if cycle < DUTY else -1.0
        env = min(1.0, math.sin(math.pi / 2.0 * i / rise) if i < rise else 1.0)
        if i >= n - fall:
            env *= math.sin(math.pi / 2.0 * (n - 1 - i) / fall)
        ints.append(int(round(s * env * (10.0 ** (PEAK_DB / 20.0)) * 32767.0)))
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack("<%dh" % len(ints), *ints))
    return out.getvalue()


def main(argv=None):
    parser = argparse.ArgumentParser(description="Writes the dialogue box's voice blip as a WAV file.")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="the folder to write to (default: assets/audio/sfx)")
    args = parser.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / (NAME + ".wav")).write_bytes(render())
    print("make_blips: wrote %s.wav to %s" % (NAME, out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
