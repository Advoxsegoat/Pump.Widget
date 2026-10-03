#!/usr/bin/env python3
"""Build the END OF FEED teaser: robot VO + synthesized sound design + rendered frames -> MP4.

Usage: python3 brand-kit/build-teaser.py ["CHANNEL NAME"]
Needs: espeak-ng, ffmpeg, node + playwright (Chromium).
Output: brand-kit/out/teaser.mp4 (1080x1920, 30fps, ~20s, -14 LUFS)
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
NAME = sys.argv[1] if len(sys.argv) > 1 else "END OF FEED"
DURATION = 20
SR = 44100

# (file, espeak voice, speed, pitch, text, start_s, tempo)
VO = [
    ("vo1", "en-us", 165, 20, "This is a public service announcement, from OmniCorp.", 0.15, 1.25),
    ("vo2", "en-us", 140, 15, "The world, is ending.", 3.25, 1.0),
    ("vo3", "en-us", 150, 20, "Please, continue scrolling.", 6.9, 1.0),
    ("vo4", "en-us", 150, 20, f"{NAME.title()}. Season one. Follow, before it is too late.", 14.25, 1.12),
    ("vo5", "en-us+whisper", 120, 60, "skrongle.", 19.0, 1.0),
]
SCREAMS = [10.05, 12.0]
KICKS = [10.0 + 0.5 * k for k in range(8)]
PINGS = [7.5, 8.3, 8.9, 9.3, 9.6, 9.8]
GLITCHES = [3.0, 6.5, 10.0, 14.0, 18.5]


def run(cmd):
    subprocess.run(cmd, check=True)


def main():
    tmp = Path(tempfile.mkdtemp(prefix="eof-teaser-"))
    for name, voice, speed, pitch, text, _, _ in VO:
        run(["espeak-ng", "-v", voice, "-s", str(speed), "-p", str(pitch), "-w", str(tmp / f"{name}.wav"), text])
    run(["espeak-ng", "-v", "en-us+f3", "-s", "115", "-p", "99", "-a", "200", "-w", str(tmp / "skr.wav"), "SKRONGLE!"])

    inputs, chains, mix = [], [], []

    def add_input(*args):
        inputs.extend(args)
        return len([a for a in inputs if a == "-i"]) - 1

    # OmniCorp PA voice: band-limited, slight hall echo
    for name, *_, start, tempo in VO:
        i = add_input("-i", str(tmp / f"{name}.wav"))
        chains.append(
            f"[{i}:a]aresample={SR},atempo={tempo},highpass=f=150,lowpass=f=4200,"
            f"aecho=0.8:0.6:35:0.25,volume=2.6,adelay={int(start * 1000)}:all=1[{name}]"
        )
        mix.append(f"[{name}]")

    # Skrongle screams: pitched up and crushed
    i = add_input("-i", str(tmp / "skr.wav"))
    chains.append(f"[{i}:a]asetrate=22050*1.3,aresample={SR},acrusher=bits=6:mix=0.5,volume=2.6,asplit={len(SCREAMS)}" + "".join(f"[s{k}]" for k in range(len(SCREAMS))))
    for k, t in enumerate(SCREAMS):
        chains.append(f"[s{k}]adelay={int(t * 1000)}:all=1[scr{k}]")
        mix.append(f"[scr{k}]")

    def synth(label, expr, dur, start, vol=1.0):
        i = add_input("-f", "lavfi", "-i", f"aevalsrc='{expr}':s={SR}:d={dur}")
        chains.append(f"[{i}:a]volume={vol},adelay={int(start * 1000)}:all=1[{label}]")
        mix.append(f"[{label}]")

    # low radioactive hum under everything (same level at start and end so it loops)
    synth("drone", "0.11*sin(2*PI*55*t)*(0.75+0.25*sin(2*PI*0.5*t))+0.06*sin(2*PI*82.5*t)+0.02*sin(2*PI*110*t)", DURATION, 0, vol=0.45)
    # terminal typing ticks
    synth("typing", "0.25*(random(0)*2-1)*exp(-300*mod(t,0.0455))", 1.75, 0.25, vol=0.6)
    for k, t in enumerate(PINGS):
        synth(f"ping{k}", "0.35*sin(2*PI*1320*t)*exp(-30*t)", 0.2, t)
    for k, t in enumerate(KICKS):
        synth(f"kick{k}", "0.9*sin(2*PI*(45*t+6*(1-exp(-25*t))))*exp(-7*t)", 0.45, t)
    synth("drop", "0.9*sin(2*PI*(110*t-30*t*t))*exp(-1.4*t)", 2.0, 12.0)
    for k, t in enumerate(GLITCHES):
        synth(f"glitch{k}", "0.35*(random(0)*2-1)*exp(-14*t)", 0.25, max(0, t - 0.08))

    chains.append(
        "".join(mix) + f"amix=inputs={len(mix)}:normalize=0,atrim=0:{DURATION},"
        "loudnorm=I=-14:TP=-1.5:LRA=11[out]"
    )
    mix_wav = tmp / "mix.wav"
    run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(chains),
         "-map", "[out]", "-ar", str(SR), "-ac", "2", str(mix_wav)])

    frames = tmp / "frames"
    run(["node", str(HERE / "render-teaser.mjs"), str(frames), NAME])

    out = HERE / "out" / "teaser.mp4"
    run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", str(frames / "%05d.jpg"), "-i", str(mix_wav),
         "-c:v", "libx264", "-preset", "slow", "-crf", "21", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-shortest", str(out)])
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
