#!/usr/bin/env bash
# Records the preview reel (res://demo/demo_reel.tscn) with Godot's Movie Maker under the virtual display, and
# encodes it with ffmpeg.
#   tools/record_reel.sh [<out dir>]        (default out/demo, which is git-ignored)
# Writes <out dir>/all-divine-preview.mp4 (H.264, yuv420p, 1280x720, 30 fps: the training yard with the HUD on),
# all-divine-preview-closeup.mp4 (the middle half of the picture, 4x: the fighters are small in the game's wide view),
# all-divine-preview-tell.mp4 (three seconds of the Knuckle's perilous sweep, from its tell to the blow, cropped round
# it at 5x: the rose rim, the red wave on the ground and the unblockable icon over its head, on the one frame the HUD
# is drawn) and a few stills.
#
# The Movie Maker records at the size the window has when the game starts, which a command-line --resolution does not
# change under the project's fullscreen setting; so the run is given a temporary override.cfg (removed at the end)
# that makes the window the 640x360 picture itself, and ffmpeg then scales that up 2x with nearest-neighbour.
# REEL_FRAMES (default 640, about 21 s at 30 fps) is how long it records; REEL_STILLS is a space-separated list of
# the seconds to save stills at.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/out/demo}"
FRAMES="${REEL_FRAMES:-640}"
STILLS="${REEL_STILLS:-2.5 4.1 6.9 11.0 14.0 15.6 18.4 20.0}"
# The tell clip: where (seconds) it starts and how long it is, and the box of the 640x360 picture it shows (the sweep is
# pressed at 10.28 s; the Knuckle then stands left of the middle of the picture and Abarax right of it).
TELL_FROM="${REEL_TELL_FROM:-10.1}"
TELL_SECONDS="${REEL_TELL_SECONDS:-3}"
TELL_CROP="${REEL_TELL_CROP:-256:144:150:88}"
command -v ffmpeg >/dev/null || { echo "record_reel.sh: ffmpeg is needed" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"; rm -f "$ROOT/override.cfg"' EXIT
mkdir -p "$OUT"
printf '[display]\nwindow/size/viewport_width=640\nwindow/size/viewport_height=360\nwindow/size/mode=0\n' > "$ROOT/override.cfg"

"$ROOT/tools/godot.sh" --render --write-movie "$work/frame.png" --fixed-fps 30 --quit-after "$FRAMES" res://demo/demo_reel.tscn

ffmpeg -y -loglevel error -framerate 30 -i "$work/frame%08d.png" \
	-vf "scale=1280:720:flags=neighbor,format=yuv420p" -c:v libx264 -crf 20 -preset slow -movflags +faststart \
	"$OUT/all-divine-preview.mp4"

ffmpeg -y -loglevel error -framerate 30 -i "$work/frame%08d.png" \
	-vf "crop=320:180:160:90,scale=1280:720:flags=neighbor,format=yuv420p" -c:v libx264 -crf 20 -preset slow -movflags +faststart \
	"$OUT/all-divine-preview-closeup.mp4"

ffmpeg -y -loglevel error -framerate 30 -start_number "$(awk -v s="$TELL_FROM" 'BEGIN { printf "%d", s * 30 }')" \
	-i "$work/frame%08d.png" -frames:v "$(awk -v s="$TELL_SECONDS" 'BEGIN { printf "%d", s * 30 }')" \
	-vf "crop=$TELL_CROP,scale=1280:720:flags=neighbor,format=yuv420p" -c:v libx264 -crf 20 -preset slow -movflags +faststart \
	"$OUT/all-divine-preview-tell.mp4"

n=0
for second in $STILLS; do
	n=$((n + 1))
	frame="$(awk -v s="$second" 'BEGIN { printf "%08d", s * 30 }')"
	ffmpeg -y -loglevel error -i "$work/frame$frame.png" -vf "scale=1280:720:flags=neighbor" -frames:v 1 \
		"$OUT/all-divine-preview-still-$n-${second}s.png"
done
echo "record_reel.sh: wrote $OUT/all-divine-preview.mp4 and $n stills"
