#!/usr/bin/env bash
# Makes the storyboard sheet of a scene: its shots on paper, from the scene's own data, by the game itself.
#   tools/storyboard.sh <scene> [out dir]        (default out/story/<scene>, which is git-ignored)
# <scene> is a folder of scenes/story (tools/story_check.gd lists them). It
#   1. runs the shot checker on the scene and stops, printing the checker's lines, when it finds an error (exit 1);
#   2. plays the scene in the game under the virtual display, 60 physics ticks a second so that a frame is a tick, and saves
#      the picture of each shot's key frame at 640x360 to <out>/frames/shot-NN.png (tools/story/story_reel.gd);
#   3. lays the frames and the shot's words out in <out>/storyboard-1.png, -2.png ... (tools/story/storyboard_page.gd).
# Prints the pages' paths. Exit 0 when the pages are made; 1 when the checker refuses the scene or a step fails; 2 for a wrong
# command line (no scene, or one that does not exist).
# Like record_reel.sh it gives the run a temporary override.cfg (removed at the end) that makes the window the 640x360 picture
# itself, and runs on the default settings (--no-player-settings), never the player's.
# Run `tools/godot.sh --import` first when classes or data have been added.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="${1:-}"
[ -n "$SCENE" ] || { echo "usage: tools/storyboard.sh <scene> [out dir]" >&2; exit 2; }
case "$SCENE" in *[!a-z0-9_]*) echo "storyboard.sh: '$SCENE' is not a scene's name (lower case, digits and _)" >&2; exit 2 ;; esac
[ -f "$ROOT/scenes/story/$SCENE/shots.tres" ] || { echo "storyboard.sh: no scene '$SCENE' (a folder with a shots.tres under scenes/story)" >&2; exit 2; }
OUT="${2:-$ROOT/out/story/$SCENE}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac

log="$(mktemp)"
trap 'rm -f "$log" "$ROOT/override.cfg"' EXIT

# Godot's own lines are shown only when a step fails (xvfb's V-Sync warning and the banner are no news).
quiet() {
	"$@" >"$log" 2>&1
	local status=$?
	if [ "$status" -ne 0 ]; then
		grep -v -e '^WARNING: Could not set V-Sync mode' -e '^[[:space:]]*at: .*(display_server_x11' "$log" >&2
	fi
	return "$status"
}

"$ROOT/tools/godot.sh" -s res://tools/story_check.gd -- --scene="$SCENE" >"$log" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
	grep '^story_check: ' "$log" >&2 || cat "$log" >&2
	exit 1
fi
grep '^story_check: ' "$log" | tail -1

rm -rf "$OUT/frames" "$OUT"/storyboard-*.png
mkdir -p "$OUT"
printf '[display]\nwindow/size/viewport_width=640\nwindow/size/viewport_height=360\nwindow/size/mode=0\n' > "$ROOT/override.cfg"

extra=()
# STORY_EMPTY=1 also saves each frame without Abarax (frames/empty-NN.png): the tests use it to measure his silhouette.
[ -z "${STORY_EMPTY:-}" ] || extra=(--empty-too)
quiet "$ROOT/tools/godot.sh" --render --fixed-fps 60 res://tools/story/story_reel.tscn -- --no-player-settings --scene="$SCENE" --capture --out="$OUT" ${extra[@]+"${extra[@]}"} || { echo "storyboard.sh: the scene could not be played (see above)" >&2; exit 1; }
rm -f "$ROOT/override.cfg"
quiet "$ROOT/tools/godot.sh" --render -s res://tools/story/storyboard_page.gd -- --scene="$SCENE" --out="$OUT" || { echo "storyboard.sh: the sheet could not be made (see above)" >&2; exit 1; }

for page in "$OUT"/storyboard-*.png; do
	echo "storyboard.sh: wrote $page"
done
