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
# itself, and runs on the default settings (--no-player-settings), never the player's. The file says which run wrote it
# (tools/override_cfg.sh): a killed run's is removed by the next run of tools/godot.sh; an override.cfg of the owner's own, or
# another run in this folder, makes this refuse (exit 4, one line) and nothing of the owner's is ever deleted.
# The sheet is whole or absent: it is made in a folder of its own beside the output and swapped in at the end, so a run that is
# stopped leaves the earlier sheet as it was.
# Exit codes: 0 the pages are made; 1 the checker refuses the scene or a step failed; 2 a wrong command line; 4 an override.cfg
# that is not this run's is in the way.
# Run `tools/godot.sh --import` first when classes or data have been added.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tools/override_cfg.sh"
SCENE="${1:-}"
[ -n "$SCENE" ] || { echo "usage: tools/storyboard.sh <scene> [out dir]" >&2; exit 2; }
case "$SCENE" in *[!a-z0-9_]*) echo "storyboard.sh: '$SCENE' is not a scene's name (lower case, digits and _)" >&2; exit 2 ;; esac
[ -f "$ROOT/scenes/story/$SCENE/shots.tres" ] || { echo "storyboard.sh: no scene '$SCENE' (a folder with a shots.tres under scenes/story)" >&2; exit 2; }
OUT="${2:-$ROOT/out/story/$SCENE}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac

log="$(mktemp)"
stage=""
trap 'override_release; rm -f "$log"; [ -z "$stage" ] || rm -rf "$stage"' EXIT

# Godot's own lines are shown only when a step fails (xvfb's V-Sync warning and the banner are no news).
quiet() {
	"$@" >"$log" 2>&1
	local status=$?
	if [ "$status" -ne 0 ]; then
		grep -v -e '^WARNING: Could not set V-Sync mode' -e '^[[:space:]]*at: .*(display_server_x11' "$log" >&2
	fi
	return "$status"
}

override_claim storyboard.sh || exit $?

"$ROOT/tools/godot.sh" -s res://tools/story_check.gd -- --scene="$SCENE" >"$log" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
	grep '^story_check: ' "$log" >&2 || cat "$log" >&2
	exit 1
fi
grep '^story_check: ' "$log" | tail -1

mkdir -p "$OUT"
stage="$(mktemp -d "$OUT/.making-XXXXXX")"

extra=()
# STORY_EMPTY=1 also saves each frame without Abarax (frames/empty-NN.png): the tests use it to measure his silhouette.
[ -z "${STORY_EMPTY:-}" ] || extra=(--empty-too)
quiet "$ROOT/tools/godot.sh" --render --fixed-fps 60 res://tools/story/story_reel.tscn -- --no-player-settings --scene="$SCENE" --capture --out="$stage" ${extra[@]+"${extra[@]}"} || { echo "storyboard.sh: the scene could not be played (see above)" >&2; exit 1; }
override_release
quiet "$ROOT/tools/godot.sh" --render -s res://tools/story/storyboard_page.gd -- --scene="$SCENE" --out="$stage" || { echo "storyboard.sh: the sheet could not be made (see above)" >&2; exit 1; }

# Swap the new sheet in: the earlier one goes aside, the new one takes its place, the earlier one is thrown away.
mkdir "$stage/earlier"
mv "$OUT/frames" "$stage/earlier/" 2>/dev/null
mv "$OUT"/storyboard-*.png "$stage/earlier/" 2>/dev/null
mv "$stage/frames" "$OUT/frames"
mv "$stage"/storyboard-*.png "$OUT/"

for page in "$OUT"/storyboard-*.png; do
	echo "storyboard.sh: wrote $page"
done
