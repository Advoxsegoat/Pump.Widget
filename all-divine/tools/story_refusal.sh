# Not run by itself: sourced by tools/storyboard.sh and tools/animatic.sh.
#
# story_refusal LOG: prints what the shot checker said about a scene it refused (LOG holds the checker's output), so that the
# owner sees what stops the sheet first and what is only not final yet after it:
#
#   Cannot make the sheet:
#     story_check: <scene>/S2: beat at frame 5000 is outside the shot ...
#   Also not final:
#     story_check: <scene>/S2: placeholder: abarax has no clip 'guard_roar'
#
# The checker's own lines are kept as they are. "Also not final:" is left out when there is nothing to put under it. When the checker
# printed no line of its own (it stopped on a script error), the whole of its output is shown.
story_refusal() {
	local errors notes
	errors="$(grep '^story_check: ' "$1" | grep -v -e '^story_check: [^:]*: placeholder: ')"
	notes="$(grep -e '^story_check: [^:]*: placeholder: ' "$1")"
	if [ -z "$errors" ] && [ -z "$notes" ]; then
		cat "$1"
		return 0
	fi
	if [ -n "$errors" ]; then
		echo "Cannot make the sheet:"
		printf '%s\n' "$errors" | sed -e 's/^/  /'
	fi
	if [ -n "$notes" ]; then
		echo "Also not final:"
		printf '%s\n' "$notes" | sed -e 's/^/  /'
	fi
}
