#!/usr/bin/env bash
# Makes the animatic of a scene: a silent video of the scene as the game plays it, with the shot's facts burnt in at the top
# left (the shot, its framing and move, the frame and time; a sound or music cue when it comes; a clip not made yet; a stand-in
# portrait), so that what a silent run cannot say is written on it.
#   tools/animatic.sh <scene> [out dir]          (default out/story/<scene>, which is git-ignored)
# Writes <out>/animatic.mp4 (H.264, yuv420p, 1280x720, nearest-neighbour x2, 30 fps) and prints its path and length. It
#   1. runs the shot checker and stops with the checker's lines on an error (exit 1);
#   2. plays the scene (tools/story/story_reel.gd) under Godot's Movie Maker and the virtual display, with the dummy audio
#      driver (the video has no sound), and cuts the 30 ticks the reel waits before the scene begins;
#   3. encodes it with ffmpeg ($FFMPEG, default ffmpeg).
# Exit 0 when the video is made; 1 for a checker refusal or a failed step; 2 for a wrong command line (no scene, or one that
# does not exist); 3 when ffmpeg is not installed (one line says so; tools/storyboard.sh needs no ffmpeg).
# The window is the 640x360 picture by a temporary override.cfg (see record_reel.sh), on the default settings. The file says which
# run wrote it (tools/override_cfg.sh): a killed run's is removed by the next run of tools/godot.sh; an override.cfg of the owner's
# own, or another run in this folder, makes this refuse (exit 4, one line) and nothing of the owner's is ever deleted.
# The video is whole or absent: it is encoded to a name of its own beside the output and moved into place at the end, so a run
# that is stopped leaves the earlier animatic.mp4 as it was.
# Exit codes: 0 the video is made; 1 the checker refuses the scene or a step failed; 2 a wrong command line; 3 no ffmpeg; 4 an
# override.cfg that is not this run's is in the way.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tools/override_cfg.sh"
FFMPEG="${FFMPEG:-ffmpeg}"
SCENE="${1:-}"
[ -n "$SCENE" ] || { echo "usage: tools/animatic.sh <scene> [out dir]" >&2; exit 2; }
case "$SCENE" in *[!a-z0-9_]*) echo "animatic.sh: '$SCENE' is not a scene's name (lower case, digits and _)" >&2; exit 2 ;; esac
SHOTS="$ROOT/scenes/story/$SCENE/shots.tres"
[ -f "$SHOTS" ] || { echo "animatic.sh: no scene '$SCENE' (a folder with a shots.tres under scenes/story)" >&2; exit 2; }
OUT="${2:-$ROOT/out/story/$SCENE}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac

work="$(mktemp -d)"
video=""
trap 'override_release; rm -rf "$work"; [ -z "$video" ] || rm -f "$video"' EXIT
log="$work/log.txt"

override_claim animatic.sh || exit $?

"$ROOT/tools/godot.sh" -s res://tools/story_check.gd -- --scene="$SCENE" >"$log" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
	grep '^story_check: ' "$log" >&2 || cat "$log" >&2
	exit 1
fi
command -v "$FFMPEG" >/dev/null 2>&1 || { echo "animatic.sh: ffmpeg is not installed, so no video can be made (tools/storyboard.sh $SCENE needs none)" >&2; exit 3; }

# A cap for the recording, in video frames: the wait, the glides and the shots in ticks (the reel quits by itself well before it).
cap="$(awk '/^lead_in = /{a=$3} /^lead_out = /{b=$3} /^length = /{n+=$3} END{printf "%d", (30 + a + n + 90 + 60) / 2 + 60}' "$SHOTS")"
mkdir -p "$OUT"
"$ROOT/tools/godot.sh" --render --write-movie "$work/frame.png" --fixed-fps 30 --quit-after "$cap" res://tools/story/story_reel.tscn -- --no-player-settings --scene="$SCENE" >"$log" 2>&1
status=$?
override_release
if [ "$status" -ne 0 ]; then
	grep -v -e '^WARNING: Could not set V-Sync mode' "$log" >&2
	echo "animatic.sh: the scene could not be played (see above)" >&2
	exit 1
fi
# the reel waits 30 ticks (15 video frames at 30 a second) before the scene begins: the video starts with the scene
video="$(mktemp "$OUT/.animatic-XXXXXX.mp4")"
"$FFMPEG" -y -loglevel error -framerate 30 -start_number 15 -i "$work/frame%08d.png" \
	-vf "scale=1280:720:flags=neighbor,format=yuv420p" -c:v libx264 -crf 20 -preset slow -movflags +faststart \
	"$video" || { echo "animatic.sh: ffmpeg could not encode the video" >&2; exit 1; }
mv -f "$video" "$OUT/animatic.mp4" && video=""
seconds="n/a"
if command -v ffprobe >/dev/null 2>&1; then
	seconds="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/animatic.mp4" | awk '{printf "%.2f s", $1}')"
fi
echo "animatic.sh: wrote $OUT/animatic.mp4 ($seconds)"
