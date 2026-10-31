#!/usr/bin/env bash
# Runs the Python tests of the bpy tools (tools/anim/tests) with tools/.venv's Python, isolated (-I).
#   tools/bpy_test.sh [unittest args...]
# Needs tools/setup.sh --bpy, and for the Abarax build test the ubc and outfits packs
# (python3 -I tools/assets/fetch.py fetch ubc; ... fetch outfits).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT/tools/.venv/bin/python"

[ -x "$PYTHON" ] || { echo "bpy_test.sh: no $PYTHON; run tools/setup.sh --bpy first" >&2; exit 1; }

cd "$ROOT"
exec "$PYTHON" -I -m unittest discover -s tools/anim/tests -v "$@"
