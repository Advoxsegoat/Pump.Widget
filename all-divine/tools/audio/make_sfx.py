#!/usr/bin/env python3
"""Makes the game's sound effects: a seeded synthesiser that writes assets/audio/sfx/*.wav.

    python3 -I tools/audio/make_sfx.py [--out assets/audio/sfx]

Why we make them: no free sound pack the project could fetch is in it (the Kenney impact-sound page no longer
has a download link tools/assets/fetch.py can read), and every sound is data anyway (data/sounds/*.tres): a
recorded sound can replace any of these by changing the cue's streams.

Standard library only (wave, math, random, struct, zlib). The files are the same bytes on every run: each sound
draws its noise from its own random.Random, seeded from the sound's name, and nothing is stamped with a time.
Every file is 44.1 kHz, 16-bit, mono, at most MAX_SECONDS long, and peaks at -1 dBFS or lower.

The recipes (what the owner hears is judged by ear in the F1 checklist; tune the numbers here, run the tool, and
commit the new files, which tools/audio/tests checks are what this makes):
  impacts     a low sine thump that drops in pitch, a band-passed noise crack, and a little body between
  whooshes    noise through a band-pass filter whose centre sweeps, under a bell-shaped swell
  guard       a wooden thock with a short metallic tick
  parry       inharmonic partials with a fast decay, like struck metal
  catch       a snap of noise and a short grip thump, twice
  perilous    a low dissonant stab with a falling filter, and a high bell
  tell        a high glint: a few bright partials gliding up a little
  cloth/fall  soft noise bursts and low thuds
  charge      a low hum with a slow vibrato that swells and fades
"""
import argparse
import io
import math
import random
import struct
import sys
import wave
import zlib
from pathlib import Path

RATE = 44100
MAX_SECONDS = 1.5
#: Peaks are normalised to this unless a sound says otherwise; the files must stay at -1 dBFS or lower.
PEAK_DB = -1.5
DEFAULT_OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"
TAU = 2.0 * math.pi


# --- building blocks: a sound is a list of floats, about -1 to 1, one per sample ---

def samples_in(seconds):
    return int(round(seconds * RATE))


def noise(rng, n):
    return [rng.random() * 2.0 - 1.0 for _ in range(n)]


def peak_of(x):
    return max(abs(s) for s in x) or 1.0


def layer(x, gain=1.0):
    """`x` scaled to a peak of `gain`, so that layers mix by how loud they are, not by how they were made."""
    scale = gain / peak_of(x)
    return [s * scale for s in x]


def mix(layers, n):
    """The sum of `layers`, each (samples, delay in seconds), cut or padded to `n` samples."""
    out = [0.0] * n
    for x, delay in layers:
        start = samples_in(delay)
        for i, s in enumerate(x):
            if start + i >= n:
                break
            out[start + i] += s
    return out


def decay(n, tau, attack=0.001):
    """An envelope: a rise over `attack` seconds (a quarter sine, so no click), then an exponential fall."""
    out = []
    for i in range(n):
        t = i / RATE
        rise = math.sin(math.pi / 2.0 * t / attack) if t < attack else 1.0
        out.append(rise * math.exp(-t / tau))
    return out


def swell(n, peak_at):
    """An envelope that rises to 1 a fraction `peak_at` of the way through and falls to 0 at the end, smoothly."""
    out = []
    for i in range(n):
        u = i / (n - 1)
        if u < peak_at:
            out.append(math.sin(math.pi / 2.0 * u / peak_at) ** 2)
        else:
            out.append(math.cos(math.pi / 2.0 * (u - peak_at) / (1.0 - peak_at)) ** 2)
    return out


def times(x, env):
    return [a * b for a, b in zip(x, env)]


def saturate(x, drive):
    """Soft clipping of `x` (first scaled to a peak of 1, so that the drive means the same for every mix): a
    harder drive gives a heavier, rounder sound."""
    scale = 1.0 / peak_of(x)
    norm = math.tanh(drive)
    return [math.tanh(drive * s * scale) / norm for s in x]


def fade_out(x, seconds):
    """The last `seconds` of `x` fall to 0, so that no sound ends in a click."""
    n = samples_in(seconds)
    out = list(x)
    for i in range(min(n, len(out))):
        out[-1 - i] *= math.sin(math.pi / 2.0 * i / n)
    return out


def biquad(x, b0, b1, b2, a1, a2):
    out = []
    x1 = x2 = y1 = y2 = 0.0
    for s in x:
        y = b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out.append(y)
        x2, x1 = x1, s
        y2, y1 = y1, y
    return out


def _rbj(f0, q):
    w0 = TAU * f0 / RATE
    return math.cos(w0), math.sin(w0) / (2.0 * q)


def bandpass(x, f0, q):
    """A band-pass filter (RBJ cookbook, 0 dB at the centre) of centre `f0` Hz and quality `q`."""
    c, alpha = _rbj(f0, q)
    a0 = 1.0 + alpha
    return biquad(x, alpha / a0, 0.0, -alpha / a0, -2.0 * c / a0, (1.0 - alpha) / a0)


def lowpass(x, f0, q=0.707):
    c, alpha = _rbj(f0, q)
    a0 = 1.0 + alpha
    return biquad(x, (1.0 - c) / 2.0 / a0, (1.0 - c) / a0, (1.0 - c) / 2.0 / a0, -2.0 * c / a0, (1.0 - alpha) / a0)


def highpass(x, f0, q=0.707):
    c, alpha = _rbj(f0, q)
    a0 = 1.0 + alpha
    return biquad(x, (1.0 + c) / 2.0 / a0, -(1.0 + c) / a0, (1.0 + c) / 2.0 / a0, -2.0 * c / a0, (1.0 - alpha) / a0)


def swept(x, freqs, q, mode="band"):
    """`x` through a state-variable filter whose centre (or cutoff) follows `freqs`, one Hz value per sample.
    `mode` is the output: "band" or "low". Stable for centres below about 7 kHz."""
    low = band = 0.0
    out = []
    for s, f in zip(x, freqs):
        k = 2.0 * math.sin(math.pi * f / RATE)
        low += k * band
        high = s - low - band / q
        band += k * high
        out.append(band if mode == "band" else low)
    return out


def sweep_path(n, f_start, f_end, curve=1.0):
    """Hz values from `f_start` to `f_end` over `n` samples, even in pitch (a log sweep); `curve` above 1 holds
    back at the start and rushes at the end."""
    out = []
    for i in range(n):
        u = (i / (n - 1)) ** curve
        out.append(f_start * (f_end / f_start) ** u)
    return out


def gliding_sine(n, f_start, f_end, pitch_tau):
    """A sine whose pitch falls (or rises) from `f_start` to `f_end` Hz, closing the gap with time constant
    `pitch_tau` seconds. The phase is summed, so the pitch glides without a jump."""
    out = []
    phase = 0.0
    for i in range(n):
        f = f_end + (f_start - f_end) * math.exp(-i / RATE / pitch_tau)
        out.append(math.sin(phase))
        phase += TAU * f / RATE
    return out


def partials(n, base, ratios, amps, taus, glide=0.0, glide_tau=0.01):
    """A sum of decaying sines at `base` x each of `ratios`, each with its own amplitude and decay time. `glide` is
    how far the pitch starts above the note, as a fraction (0.1 starts 10% high), settling over `glide_tau`."""
    out = [0.0] * n
    for ratio, amp, tau in zip(ratios, amps, taus):
        phase = 0.0
        for i in range(n):
            t = i / RATE
            out[i] += amp * math.sin(phase) * math.exp(-t / tau)
            phase += TAU * base * ratio * (1.0 + glide * math.exp(-t / glide_tau)) / RATE
    return out


def thump(n, f_start, f_end, pitch_tau, amp_tau):
    """The low body of an impact: a sine that drops in pitch, with a quick attack and an exponential fall."""
    return times(gliding_sine(n, f_start, f_end, pitch_tau), decay(n, amp_tau, 0.0015))


def burst(rng, n, centre, q, tau, attack=0.0005):
    """Band-passed noise with a decay of `tau` seconds: a crack, a slap, a rustle, by where the centre is."""
    return times(bandpass(noise(rng, n), centre, q), decay(n, tau, attack))


# --- the recipes ---

def impact_palm(rng, f_start, f_end, crack_hz, body_hz):
    """An open hand landing: a thump that falls from f_start to f_end, a slap of body and a crack."""
    n = samples_in(0.28)
    return saturate(mix([
        (layer(thump(n, f_start, f_end, 0.032, 0.07), 1.0), 0.0),
        (layer(burst(rng, n, body_hz, 1.0, 0.035), 0.55), 0.0),
        (layer(burst(rng, n, crack_hz, 2.0, 0.010), 0.8), 0.0),
    ], n), 1.8)


def impact_heavy(rng, f_start, f_end, crack_hz):
    """A heavy blow: a long low thump, a sub boom, a crack and a rumble, driven hard."""
    n = samples_in(0.55)
    return saturate(mix([
        (layer(thump(n, f_start, f_end, 0.06, 0.16), 1.0), 0.0),
        (layer(thump(n, 58.0, 30.0, 0.12, 0.26), 0.6), 0.0),
        (layer(burst(rng, n, crack_hz, 1.5, 0.022), 0.9), 0.0),
        (layer(times(lowpass(noise(rng, n), 380.0), decay(n, 0.13, 0.002)), 0.6), 0.0),
    ], n), 2.6)


def whoosh(rng, seconds, f_start, f_end, q, peak_at, rumble=0.0):
    """A swing through the air: band-passed noise whose centre sweeps from f_start to f_end, swelling to its
    loudest `peak_at` of the way through. `rumble` adds a low breath under it for a heavier swing."""
    n = samples_in(seconds)
    env = swell(n, peak_at)
    body = times(lowpass(swept(noise(rng, n), sweep_path(n, f_start, f_end, 1.4), q), 4800.0), env)
    hiss = times(highpass(noise(rng, n), 3500.0), env)
    layers = [(layer(body, 1.0), 0.0), (layer(hiss, 0.07), 0.0)]
    if rumble > 0.0:
        layers.append((layer(times(lowpass(noise(rng, n), 260.0), env), rumble), 0.0))
    return mix(layers, n)


def guard_block(rng, base, thock_hz):
    """A blow met by a guard: a wooden thock with a short metallic tick on top."""
    n = samples_in(0.3)
    tick = partials(n, base, [1.0, 2.32, 4.17, 6.5], [1.0, 0.7, 0.45, 0.3], [0.05, 0.035, 0.022, 0.015])
    return saturate(mix([
        (layer(thump(n, thock_hz, thock_hz * 0.43, 0.02, 0.05), 0.9), 0.0),
        (layer(tick, 0.5), 0.0),
        (layer(burst(rng, n, 3600.0, 1.8, 0.008), 0.6), 0.0),
    ], n), 1.5)


def parry_ring(rng):
    """A blow turned back: a ring of inharmonic partials (a struck bar's ratios) that dies away quickly, a
    slightly flat twin of the note for shimmer, and the click of the strike."""
    n = samples_in(1.2)
    ring = partials(n, 880.0, [1.0, 2.756, 5.404, 8.933, 13.34], [1.0, 0.6, 0.45, 0.3, 0.18], [0.3, 0.2, 0.12, 0.08, 0.05])
    twin = partials(n, 884.5, [1.0, 2.756], [1.0, 0.4], [0.24, 0.14])
    click = times(highpass(noise(rng, n), 2000.0), decay(n, 0.004, 0.0003))
    return fade_out(mix([(layer(ring, 1.0), 0.0), (layer(twin, 0.35), 0.0), (layer(click, 0.7), 0.0)], n), 0.02)


def catch_snap(rng):
    """The open hand closing on a thrust: a snap, a short grip thump, and a softer snap just after."""
    n = samples_in(0.22)
    snap = burst(rng, n, 3000.0, 1.2, 0.01)
    return saturate(mix([
        (layer(snap, 1.0), 0.0),
        (layer(thump(n, 230.0, 90.0, 0.025, 0.045), 0.7), 0.0),
        (layer(burst(rng, n, 2200.0, 1.5, 0.008), 0.45), 0.035),
    ], n), 1.6)


def perilous_sting(rng):
    """The warning of an attack that cannot be blocked: a low stab on two notes a semitone apart, its filter
    closing as it falls, and a high bell over it."""
    n = samples_in(1.3)
    stab = [0.0] * n
    for note, gain in ((82.4, 1.0), (87.3, 0.7)):
        phase = 0.0
        for i in range(n):
            phase += TAU * note * (1.0 - 0.04 * (1.0 - math.exp(-i / RATE / 0.2))) / RATE
            stab[i] += gain * sum(math.sin(k * phase) / k for k in range(1, 15))
    stab = lowpass_sweep(stab, sweep_path(n, 2400.0, 200.0, 0.8))
    stab = times(stab, decay(n, 0.34, 0.003))
    bell = [0.0] * n
    carrier = 1318.5
    for i in range(n):
        t = i / RATE
        index = 3.5 * math.exp(-t / 0.22)
        bell[i] = math.sin(TAU * carrier * t + index * math.sin(TAU * carrier * 3.51 * t)) * math.exp(-t / 0.55)
    thunk = times(lowpass(noise(rng, n), 900.0), decay(n, 0.04, 0.0005))
    return fade_out(saturate(mix([
        (layer(stab, 1.0), 0.0),
        (layer(bell, 0.45), 0.0),
        (layer(thunk, 0.5), 0.0),
    ], n), 1.4), 0.03)


def lowpass_sweep(x, freqs):
    return swept(x, freqs, 0.9, "low")


def tell_glint(rng):
    """A glint: three bright partials that glide up a little as they start, and ring out quickly."""
    n = samples_in(0.35)
    ring = partials(n, 2637.0, [1.0, 1.498, 2.0], [1.0, 0.55, 0.3], [0.12, 0.09, 0.05], glide=0.12, glide_tau=0.012)
    sparkle = times(highpass(noise(rng, n), 6000.0), decay(n, 0.01, 0.0005))
    return fade_out(mix([(layer(ring, 1.0), 0.0), (layer(sparkle, 0.25), 0.0)], n), 0.02)


def roll_cloth(rng):
    """A roll's cloth: a soft swish of noise whose centre rises, in two swells, over a quieter low rustle."""
    n = samples_in(0.45)
    env = swell(n, 0.4)
    ripple = [0.75 + 0.25 * math.sin(TAU * 7.0 * i / RATE) for i in range(n)]
    swish = times(times(lowpass(swept(noise(rng, n), sweep_path(n, 1100.0, 2600.0), 1.4), 4000.0), env), ripple)
    rustle = times(lowpass(noise(rng, n), 650.0), env)
    return mix([(layer(swish, 1.0), 0.0), (layer(rustle, 0.5), 0.0)], n)


def roll_land(rng):
    """The end of a roll: a soft thud and a puff of dust."""
    n = samples_in(0.3)
    return saturate(mix([
        (layer(thump(n, 95.0, 48.0, 0.05, 0.06), 1.0), 0.0),
        (layer(times(lowpass(noise(rng, n), 900.0), decay(n, 0.05, 0.002)), 0.5), 0.0),
        (layer(burst(rng, n, 3000.0, 1.0, 0.012), 0.12), 0.0),
    ], n), 1.3)


def surface_cloth(rng, centre):
    """A blow landing on cloth: a short muffled fwup."""
    n = samples_in(0.14)
    return mix([
        (layer(burst(rng, n, centre, 0.8, 0.03, 0.002), 1.0), 0.0),
        (layer(times(lowpass(noise(rng, n), 500.0), decay(n, 0.05, 0.002)), 0.5), 0.0),
    ], n)


def body_fall(rng):
    """A body hitting the ground: a heavy thud, the cloth and dust around it, a small second bounce, and the
    settling."""
    n = samples_in(0.8)
    return saturate(mix([
        (layer(thump(n, 100.0, 38.0, 0.05, 0.12), 1.0), 0.0),
        (layer(times(lowpass(noise(rng, n), 600.0), decay(n, 0.09, 0.002)), 0.7), 0.0),
        (layer(burst(rng, n, 2000.0, 1.2, 0.02), 0.15), 0.0),
        (layer(thump(n, 75.0, 35.0, 0.04, 0.08), 0.35), 0.17),
        (layer(burst(rng, n, 900.0, 0.8, 0.15, 0.01), 0.12), 0.25),
    ], n), 1.8)


def charge_hum(rng):
    """A heavy blow charged to its fullest: a low hum with a slow vibrato, rising a little in pitch as it swells
    and fades."""
    n = samples_in(1.2)
    harmonics = [1.0, 2.0, 3.0, 4.0, 6.0]
    gains = [1.0, 0.6, 0.35, 0.25, 0.1]
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 98.0 * (1.0 + 0.04 * t / 1.2) * (1.0 + 0.004 * math.sin(TAU * 5.5 * t))
        phase += TAU * f / RATE
        out[i] = sum(g * math.sin(h * phase) for h, g in zip(harmonics, gains))
    breath = lowpass(highpass(noise(rng, n), 250.0), 700.0)
    return times(mix([(layer(out, 1.0), 0.0), (layer(breath, 0.15), 0.0)], n), swell(n, 0.4))


#: name -> (recipe taking the sound's random.Random, peak in dBFS). The names are the files, and the cues in
#: data/sounds/ group them (impact_palm is impact_palm_1..3). The order is the order they are made in.
SOUNDS = {
    "impact_palm_1": (lambda r: impact_palm(r, 170.0, 58.0, 2400.0, 900.0), PEAK_DB),
    "impact_palm_2": (lambda r: impact_palm(r, 150.0, 52.0, 2000.0, 800.0), PEAK_DB),
    "impact_palm_3": (lambda r: impact_palm(r, 190.0, 64.0, 2900.0, 1000.0), PEAK_DB),
    "impact_heavy_1": (lambda r: impact_heavy(r, 120.0, 36.0, 1500.0), PEAK_DB),
    "impact_heavy_2": (lambda r: impact_heavy(r, 105.0, 32.0, 1200.0), PEAK_DB),
    "whoosh_light_1": (lambda r: whoosh(r, 0.30, 700.0, 2800.0, 2.0, 0.40), -4.0),
    "whoosh_light_2": (lambda r: whoosh(r, 0.27, 900.0, 3200.0, 2.4, 0.38), -4.0),
    "whoosh_light_3": (lambda r: whoosh(r, 0.33, 600.0, 2400.0, 1.8, 0.42), -4.0),
    "whoosh_heavy": (lambda r: whoosh(r, 0.55, 250.0, 1500.0, 1.6, 0.45, rumble=0.5), -2.5),
    "guard_block_1": (lambda r: guard_block(r, 900.0, 320.0), PEAK_DB),
    "guard_block_2": (lambda r: guard_block(r, 1050.0, 280.0), PEAK_DB),
    "parry_ring": (parry_ring, PEAK_DB),
    "catch_snap": (catch_snap, PEAK_DB),
    "perilous_sting": (perilous_sting, PEAK_DB),
    "tell_glint": (tell_glint, -3.0),
    "roll_cloth": (roll_cloth, -8.0),
    "roll_land": (roll_land, -4.0),
    "surface_cloth_1": (lambda r: surface_cloth(r, 1400.0), -6.0),
    "surface_cloth_2": (lambda r: surface_cloth(r, 1100.0), -6.0),
    "body_fall": (body_fall, PEAK_DB),
    "charge_hum": (charge_hum, -4.0),
}


# --- files ---

def seed_of(name):
    """The seed of a sound's generator: a function of its name alone."""
    return zlib.crc32(name.encode("ascii"))


def render(name):
    """The sound `name` as the bytes of a WAV file."""
    recipe, peak_db = SOUNDS[name]
    x = recipe(random.Random(seed_of(name)))
    assert len(x) <= samples_in(MAX_SECONDS), "%s is longer than %s s" % (name, MAX_SECONDS)
    scale = 10.0 ** (peak_db / 20.0) / peak_of(x)
    ints = [max(-32768, min(32767, int(round(s * scale * 32767.0)))) for s in fade_out(x, 0.004)]
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack("<%dh" % len(ints), *ints))
    return out.getvalue()


def render_all():
    """Every sound: name -> the bytes of its WAV file."""
    return {name: render(name) for name in SOUNDS}


def write_all(out_dir):
    """Writes every sound to `out_dir`/<name>.wav; returns the names."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    files = render_all()
    for name, data in files.items():
        (out_dir / (name + ".wav")).write_bytes(data)
    return list(files)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Writes the game's sound effects as WAV files.")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="the folder to write to (default: assets/audio/sfx)")
    args = parser.parse_args(argv)
    names = write_all(args.out)
    print("make_sfx: wrote %d files to %s" % (len(names), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
