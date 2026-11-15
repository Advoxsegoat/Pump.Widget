# Not run by itself: sourced by tools/godot.sh, tools/storyboard.sh, tools/animatic.sh and tools/record_reel.sh.
#
# The storyboard, the animatic and the preview reel need the game's window to be the 640x360 picture, which the project's
# fullscreen setting overrides unless an override.cfg sits in the project root. They write one for the length of their run. Left
# behind (a killed run, a crash), it would make the next ordinary run of the game open a small window and say nothing; and an
# override.cfg the owner has made themselves must never be written over or deleted. So:
#
#   - an override.cfg a tool writes has a first line that says so: the tool, its process id and when that process started
#     (a `;` line, which is a comment to Godot's config files);
#   - tools/godot.sh, which every run of the game goes through, removes one whose writer is no longer running, and says so in
#     one line; one whose writer is still running is left alone;
#   - an override.cfg without that line is the owner's: the three tools refuse to run beside it (exit 4) and never delete it;
#   - a second run in the same folder while the first is going is refused the same way (exit 4, one line naming the first).
#
# The functions need $ROOT (the project root). They use no bash feature beyond what the tools already use.

OVERRIDE_REFUSED=4

# override_proc_start PID: when the process started (field 22 of /proc/PID/stat, in clock ticks), or "-" where /proc has none.
override_proc_start() {
	local started
	started="$(sed -e 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}')"
	echo "${started:--}"
}

# override_running PID START: whether that process still runs (a zombie, ended and not yet collected, does not count; and a
# process of the same number that started later is another one).
override_running() {
	local state
	if [ -d /proc/self ]; then
		[ -r "/proc/$1/stat" ] || return 1
		state="$(sed -e 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $1}')"
		case "$state" in Z | X | "") return 1 ;; esac
		[ "$2" = "-" ] || [ "$(override_proc_start "$1")" = "$2" ] || return 1
		return 0
	fi
	kill -0 "$1" 2>/dev/null
}

# override_writer FILE: "TOOL PID START" for a file one of the tools wrote (its first line says so); nothing for any other.
override_writer() {
	local first
	[ -f "$1" ] || return 0
	IFS= read -r first <"$1" || true
	printf '%s\n' "$first" | sed -n -e 's|^; written by tools/\([A-Za-z0-9_.]*\), process \([0-9][0-9]*\) (started \([0-9-][0-9]*\)).*$|\1 \2 \3|p'
}

# override_clear_stale WHO: removes the override.cfg of a tool that is gone, with one line (to stderr) naming WHO and the tool.
override_clear_stale() {
	local cfg="$ROOT/override.cfg" writer tool pid started
	writer="$(override_writer "$cfg")"
	[ -n "$writer" ] || return 0
	read -r tool pid started <<<"$writer"
	if ! override_running "$pid" "$started"; then
		rm -f "$cfg"
		echo "$1: removed an override.cfg that tools/$tool left behind (its process $pid is gone); it made the window 640x360" >&2
	fi
	return 0
}

# override_claim TOOL: writes the override.cfg for this run (TOOL is the script's name, say storyboard.sh), the mark first. It
# returns $OVERRIDE_REFUSED, with one line on stderr, when another run has the folder or the owner has an override.cfg of their own.
# The file is made only if there is none (noclobber), so two runs starting together cannot both get it.
override_claim() {
	local tool="$1" cfg="$ROOT/override.cfg" writer wtool wpid wstarted tries=0
	local mark="; written by tools/$tool, process $$ (started $(override_proc_start $$)); tools/godot.sh removes this file when that process is gone"
	while [ "$tries" -lt 5 ]; do
		tries=$((tries + 1))
		if (set -o noclobber; printf '%s\n[display]\nwindow/size/viewport_width=640\nwindow/size/viewport_height=360\nwindow/size/mode=0\n' "$mark" >"$cfg") 2>/dev/null; then
			return 0
		fi
		[ -e "$cfg" ] || continue
		writer="$(override_writer "$cfg")"
		if [ -z "$writer" ]; then
			echo "$tool: there is an override.cfg of your own in $ROOT (no tool wrote it); I will not overwrite or delete it, so I cannot run. Move it away and run me again." >&2
			return "$OVERRIDE_REFUSED"
		fi
		read -r wtool wpid wstarted <<<"$writer"
		if override_running "$wpid" "$wstarted"; then
			echo "$tool: tools/$wtool is already running in this folder (process $wpid) and has the window's settings in override.cfg; wait for it to end." >&2
			return "$OVERRIDE_REFUSED"
		fi
		override_clear_stale "$tool"
	done
	echo "$tool: could not take the override.cfg in $ROOT (it keeps changing under me); try again." >&2
	return "$OVERRIDE_REFUSED"
}

# override_release: removes the override.cfg if this run wrote it (and only then: never the owner's, never another run's).
override_release() {
	local writer tool pid started
	writer="$(override_writer "$ROOT/override.cfg")"
	[ -n "$writer" ] || return 0
	read -r tool pid started <<<"$writer"
	[ "$pid" = "$$" ] && rm -f "$ROOT/override.cfg"
	return 0
}
