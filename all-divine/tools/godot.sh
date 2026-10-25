#!/usr/bin/env bash
# Runs Godot on the all-divine project.
#   tools/godot.sh [--render|--forward-plus] <godot args...>
# Uses $GODOT if set, else the binary that tools/setup.sh installs.
#   (default)       --headless
#   --render        xvfb, gl_compatibility, dummy audio
#   --forward-plus  xvfb, forward_plus on Vulkan, dummy audio
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT:-$ROOT/.tools/godot/Godot_v4.7.2-stable_linux.x86_64}"

[ -x "$GODOT_BIN" ] || { echo "godot.sh: no Godot at $GODOT_BIN; run tools/setup.sh first" >&2; exit 1; }

XVFB=(xvfb-run -a -s "-screen 0 1920x1080x24")

case "${1:-}" in
	--render)
		shift
		exec "${XVFB[@]}" "$GODOT_BIN" --path "$ROOT" --rendering-method gl_compatibility --audio-driver Dummy "$@"
		;;
	--forward-plus)
		shift
		exec "${XVFB[@]}" "$GODOT_BIN" --path "$ROOT" --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy "$@"
		;;
	*)
		exec "$GODOT_BIN" --headless --path "$ROOT" "$@"
		;;
esac
