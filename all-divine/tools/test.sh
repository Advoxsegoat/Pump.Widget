#!/usr/bin/env bash
# Runs the GDScript test suite. Exits 0 only when every test passes.
#   tools/test.sh [--render|--forward-plus] [--filter=<substring of a test id>] [--update-golden]
# A test id looks like res://tests/area/test_x.gd::test_y.
#   --render        also runs tests/**/render/, under xvfb with gl_compatibility
#   --forward-plus  the same, but requires the forward_plus renderer (needs Vulkan)
# The run is stopped after $TEST_TIMEOUT seconds (default 900).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mode=()
runner_args=()
for arg in "$@"; do
	case "$arg" in
		--render|--forward-plus)
			[ ${#mode[@]} -eq 0 ] || { echo "test.sh: give only one of --render and --forward-plus" >&2; exit 2; }
			mode=("$arg")
			runner_args+=("$arg")
			case "$arg" in
				--render) runner_args+=("--expect-method=gl_compatibility") ;;
				--forward-plus) runner_args+=("--expect-method=forward_plus") ;;
			esac
			;;
		--filter=*|--update-golden) runner_args+=("$arg") ;;
		*) echo "test.sh: unknown argument '$arg'" >&2; exit 2 ;;
	esac
done

# Import first, so new class_names and assets are known. Its log is shown only if it failed or reported an error.
import_log="$(mktemp)"
trap 'rm -f "$import_log"' EXIT
if ! "$HERE/godot.sh" --import >"$import_log" 2>&1 || grep -q 'ERROR' "$import_log"; then
	cat "$import_log"
fi

# A test that never finishes would hang the run for good, so the run is capped (TEST_TIMEOUT seconds).
status=0
timeout -k 10 "${TEST_TIMEOUT:-900}" "$HERE/godot.sh" ${mode[@]+"${mode[@]}"} --fixed-fps 60 -s res://tools/test/run.gd -- ${runner_args[@]+"${runner_args[@]}"} || status=$?
if [ "$status" -eq 124 ]; then
	echo "test.sh: the run was still going after ${TEST_TIMEOUT:-900}s and was stopped (set TEST_TIMEOUT to change this)" >&2
fi
exit "$status"
