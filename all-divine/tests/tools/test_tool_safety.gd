extends TestCase
## What the tools that give a run a temporary override.cfg (storyboard.sh, animatic.sh, record_reel.sh) and tools/godot.sh leave
## behind and refuse to touch (headless; no Godot is run, a stand-in is: every case works in a copy of the scripts in a folder of
## its own, so the project's own root never holds an override.cfg while the suite runs).
##
## The rule: an override.cfg a tool wrote has a first line that says so (the tool and its process id). tools/godot.sh removes one
## whose writer is gone, with one line, and leaves one whose writer is running; one without that line is the owner's, which the
## three tools refuse to run beside (exit 4) and never delete. Two runs at once in a tree: the second refuses (exit 4, one line
## naming the first). The outputs are whole or absent: a killed run leaves the earlier sheet and the earlier video as they were.

const OWNER_EXIT := 4
const WAIT_MSEC := 20000

var _roots: Array[String] = []
var _children: Array[int] = []


func after_each() -> void:
	for pid in _children:
		OS.execute("kill", ["-KILL", "-%d" % pid])
		OS.execute("kill", ["-KILL", str(pid)])
	_children.clear()
	for root in _roots:
		OS.execute("rm", ["-rf", root])
	_roots.clear()


func _project() -> String:
	return ProjectSettings.globalize_path("res://")


func _write(path: String, text: String, executable := false) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	if executable:
		OS.execute("chmod", ["+x", path])


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"


# A folder with copies of the tools that carry a project root (the scripts and the helper they share, when it exists), a scene
# folder, and a stand-in Godot. `real_godot`: the copy of tools/godot.sh is kept and is given a Godot that only says what it
# was run with ($GODOT); else tools/godot.sh is a stand-in that plays the parts the tools ask of it (the checker, the reel, the page
# script) and writes what each would, holding for as long as the files fake/hold_* say.
func _make_root(real_godot: bool) -> String:
	var root := ProjectSettings.globalize_path("user://tool_safety_%d_%d" % [OS.get_process_id(), _roots.size()])
	_roots.append(root)
	OS.execute("rm", ["-rf", root])
	DirAccess.make_dir_recursive_absolute(root.path_join("tools"))
	DirAccess.make_dir_recursive_absolute(root.path_join("fake"))
	for name in ["godot.sh", "storyboard.sh", "animatic.sh", "record_reel.sh", "override_cfg.sh"]:
		var from := _project().path_join("tools").path_join(name)
		if FileAccess.file_exists(from):
			DirAccess.copy_absolute(from, root.path_join("tools").path_join(name))
			OS.execute("chmod", ["+x", root.path_join("tools").path_join(name)])
	_write(root.path_join("scenes/story/demo/shots.tres"), "lead_in = 30\nlead_out = 30\nlength = 60\n")
	_write(root.path_join("fake/ffmpeg"), _FAKE_FFMPEG, true)
	_write(root.path_join("fake/godot_binary"), "#!/usr/bin/env bash\necho \"godot ran: $*\"\n", true)
	if not real_godot:
		_write(root.path_join("tools/godot.sh"), _FAKE_GODOT, true)
	return root


const _FAKE_GODOT := """#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fake" && pwd)"
echo "$*" >> "$here/calls.txt"
hold() { echo "$PPID" > "$here/at_$1"; [ -f "$here/hold_$1" ] && sleep "$(cat "$here/hold_$1")"; return 0; }
out=""; movie=""; prev=""
for a in "$@"; do
	case "$a" in --out=*) out="${a#--out=}" ;; esac
	[ "$prev" = "--write-movie" ] && movie="$a"
	prev="$a"
done
case "$*" in
	*story_check.gd*) echo "story_check: 1 scenes OK (0 placeholders)" ;;
	*story_reel.tscn*)
		if [ -n "$out" ]; then mkdir -p "$out/frames"; echo new > "$out/frames/shot-01.png"; fi
		if [ -n "$movie" ]; then d="$(dirname "$movie")"; echo f > "$d/frame00000015.png"; echo f > "$d/frame00000016.png"; fi
		hold reel ;;
	*storyboard_page.gd*)
		echo new > "$out/storyboard-1.png"
		hold page ;;
esac
exit 0
"""

const _FAKE_FFMPEG := """#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for last; do :; done
echo "new video" > "$last"
echo "$PPID" > "$here/at_encode"
[ -f "$here/hold_encode" ] && sleep "$(cat "$here/hold_encode")"
exit 0
"""


# Runs `command` in `root` (a script of its tools folder) and returns {code, text}: both streams, in order.
func _run(root: String, script: String, args: PackedStringArray, env := PackedStringArray()) -> Dictionary:
	var argv := PackedStringArray(["-k", "5", "60", "env", "FFMPEG=" + root.path_join("fake/ffmpeg")])
	argv.append_array(env)
	argv.append(root.path_join("tools").path_join(script))
	argv.append_array(args)
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	return {code = code, text = "\n".join(output).strip_edges()}


# The first line of a tool's override.cfg for process `pid`, as the tools write it.
func _marker(tool: String, pid: int) -> String:
	var stat := FileAccess.get_file_as_string("/proc/%d/stat" % pid) if FileAccess.file_exists("/proc/%d/stat" % pid) else ""
	var started := "-"
	if stat != "":
		var rest := stat.substr(stat.rfind(")") + 2).split(" ")
		started = rest[19]
	return "; written by tools/%s, process %d (started %s); tools/godot.sh removes this file when that process is gone\n" % [tool, pid, started]


# The pid of a process that has just ended (a stale writer).
func _dead_pid() -> int:
	var pid := OS.create_process("true", [])
	OS.delay_msec(300)
	return pid


# Starts the tool as its own process group (so that it and everything it runs can be killed together); returns its pid.
func _start(root: String, script: String, args: PackedStringArray) -> int:
	OS.set_environment("FFMPEG", root.path_join("fake/ffmpeg"))
	var argv := PackedStringArray([root.path_join("tools").path_join(script)])
	argv.append_array(args)
	var pid := OS.create_process("setsid", argv)
	_children.append(pid)
	return pid


func _wait_for(path: String) -> bool:
	var waited := 0
	while not FileAccess.file_exists(path) and waited < WAIT_MSEC:
		OS.delay_msec(100)
		waited += 100
	return FileAccess.file_exists(path)


# The tool's own process id, which the stand-ins write to their at_ file when they begin to hold (their parent is the tool).
func _tool_pid(root: String, moment: String) -> int:
	return int(_read(root.path_join("fake/at_" + moment)).strip_edges())


# Sends the signal to the tool's whole process group (the tool is the leader of its own: it was started under setsid), then says
# whether the tool is gone (a zombie is gone).
func _kill(pid: int, signal_name: String) -> bool:
	OS.execute("kill", ["-" + signal_name, "-%d" % pid])
	var waited := 0
	while _running(pid) and waited < 5000:
		OS.delay_msec(100)
		waited += 100
	return not _running(pid)


func _running(pid: int) -> bool:
	var stat := "/proc/%d/stat" % pid
	if pid <= 0 or not FileAccess.file_exists(stat):
		return false
	var text := FileAccess.get_file_as_string(stat)
	return not text.substr(text.rfind(")") + 2).begins_with("Z")


func _seed_sheet(out: String) -> void:
	_write(out.path_join("frames/shot-01.png"), "old frame")
	_write(out.path_join("frames/shot-02.png"), "old frame two")
	_write(out.path_join("storyboard-1.png"), "old page one")
	_write(out.path_join("storyboard-2.png"), "old page two")
	_write(out.path_join("animatic.mp4"), "old video")


func _sheet_is_the_old_one(out: String) -> bool:
	return _read(out.path_join("frames/shot-01.png")) == "old frame" and _read(out.path_join("frames/shot-02.png")) == "old frame two" \
		and _read(out.path_join("storyboard-1.png")) == "old page one" and _read(out.path_join("storyboard-2.png")) == "old page two"


# ---- tools/godot.sh ----

func test_godot_sh_removes_an_override_cfg_whose_writer_is_gone_and_says_so_in_one_line() -> void:
	var root := _make_root(true)
	var pid := _dead_pid()
	_write(root.path_join("override.cfg"), _marker("storyboard.sh", pid) + "[display]\nwindow/size/viewport_width=640\n")
	var run := _run(root, "godot.sh", PackedStringArray(["--version"]), PackedStringArray(["GODOT=" + root.path_join("fake/godot_binary")]))
	assert_eq(run.code, 0, run.text)
	assert_false(FileAccess.file_exists(root.path_join("override.cfg")), "the stale file is gone")
	var lines: PackedStringArray = String(run.text).split("\n")
	var said: Array = Array(lines).filter(func(line: String) -> bool: return line.contains("override.cfg"))
	assert_eq(said.size(), 1, "one line says it did: %s" % run.text)
	if said.size() == 1:
		assert_true(String(said[0]).contains("storyboard.sh") and String(said[0]).contains(str(pid)), said[0])
	assert_true(String(run.text).contains("godot ran: "), "the game still ran: %s" % run.text)


func test_godot_sh_leaves_an_override_cfg_whose_writer_is_still_running() -> void:
	var root := _make_root(true)
	var live := OS.create_process("sleep", ["30"])
	_children.append(live)
	OS.delay_msec(200)
	var text := _marker("animatic.sh", live) + "[display]\nwindow/size/viewport_width=640\n"
	_write(root.path_join("override.cfg"), text)
	var run := _run(root, "godot.sh", PackedStringArray(["--version"]), PackedStringArray(["GODOT=" + root.path_join("fake/godot_binary")]))
	assert_eq(run.code, 0, run.text)
	assert_eq(_read(root.path_join("override.cfg")), text, "kept as it was")
	assert_false(String(run.text).contains("override.cfg"), "and nothing said: %s" % run.text)


func test_godot_sh_leaves_the_owners_own_override_cfg_alone() -> void:
	var root := _make_root(true)
	var text := "[display]\nwindow/size/viewport_width=800\n"
	_write(root.path_join("override.cfg"), text)
	var run := _run(root, "godot.sh", PackedStringArray(["--version"]), PackedStringArray(["GODOT=" + root.path_join("fake/godot_binary")]))
	assert_eq(run.code, 0, run.text)
	assert_eq(_read(root.path_join("override.cfg")), text, "an override.cfg without the tools' line is the owner's: never deleted")
	assert_false(String(run.text).contains("override.cfg"), run.text)


# ---- the three tools ----

func test_each_tool_refuses_to_run_beside_the_owners_own_override_cfg_and_never_deletes_it() -> void:
	for script in ["storyboard.sh", "animatic.sh", "record_reel.sh"]:
		var root := _make_root(false)
		var text := "[display]\nwindow/size/viewport_width=800\n"
		_write(root.path_join("override.cfg"), text)
		var run := _run(root, script, PackedStringArray(["demo"]) if script != "record_reel.sh" else PackedStringArray([root.path_join("out")]), PackedStringArray(["PATH=%s:%s" % [root.path_join("fake"), OS.get_environment("PATH")]]))
		assert_eq(run.code, OWNER_EXIT, "%s: %s" % [script, run.text])
		assert_eq(String(run.text).split("\n").size(), 1, "%s says it in one line: %s" % [script, run.text])
		assert_true(String(run.text).contains("override.cfg"), "%s names the file: %s" % [script, run.text])
		assert_eq(_read(root.path_join("override.cfg")), text, "%s leaves the owner's file as it was" % script)
		assert_false(FileAccess.file_exists(root.path_join("fake/calls.txt")), "%s ran nothing" % script)


func test_a_second_run_in_the_same_tree_is_refused_in_one_line_naming_the_first() -> void:
	var root := _make_root(false)
	_write(root.path_join("fake/hold_reel"), "30")
	_start(root, "storyboard.sh", PackedStringArray(["demo", root.path_join("out_one")]))
	assert_true(_wait_for(root.path_join("fake/at_reel")), "the first run is in its reel")
	var first := _tool_pid(root, "reel")
	var cfg := _read(root.path_join("override.cfg"))
	assert_true(cfg.begins_with("; written by tools/storyboard.sh, process "), "the first run's mark is on the file: %s" % cfg)
	var marked := int(cfg.get_slice("process ", 1).get_slice(" ", 0))
	var second := _run(root, "animatic.sh", PackedStringArray(["demo", root.path_join("out_two")]))
	assert_eq(second.code, OWNER_EXIT, second.text)
	assert_eq(String(second.text).split("\n").size(), 1, "one line: %s" % second.text)
	assert_true(String(second.text).contains("storyboard.sh") and String(second.text).contains(str(marked)), "it names the first run: %s" % second.text)
	assert_eq(_read(root.path_join("override.cfg")), cfg, "the first run's file is as it was")
	assert_true(_kill(first, "TERM"), "the first run was stopped")
	assert_false(FileAccess.file_exists(root.path_join("override.cfg")), "a run stopped by SIGTERM takes its own file away")


func test_a_tool_replaces_a_stale_override_cfg_of_a_dead_run_and_says_so() -> void:
	var root := _make_root(false)
	_write(root.path_join("override.cfg"), _marker("animatic.sh", _dead_pid()) + "[display]\n")
	var run := _run(root, "storyboard.sh", PackedStringArray(["demo", root.path_join("out")]))
	assert_eq(run.code, 0, run.text)
	assert_true(String(run.text).contains("removed") and String(run.text).contains("override.cfg"), "it says so: %s" % run.text)
	assert_false(FileAccess.file_exists(root.path_join("override.cfg")), "and its own is gone at the end")
	assert_true(FileAccess.file_exists(root.path_join("out/storyboard-1.png")), "the sheet was made")


# ---- the outputs are whole or absent ----

func test_a_storyboard_run_killed_while_the_reel_plays_leaves_the_earlier_sheet_as_it_was() -> void:
	var root := _make_root(false)
	var out := root.path_join("out")
	_seed_sheet(out)
	_write(root.path_join("fake/hold_reel"), "30")
	_start(root, "storyboard.sh", PackedStringArray(["demo", out]))
	assert_true(_wait_for(root.path_join("fake/at_reel")), "the run reached its reel")
	assert_true(_kill(_tool_pid(root, "reel"), "KILL"), "the run was killed")
	assert_true(_sheet_is_the_old_one(out), "the earlier frames and pages are as they were")


func test_a_storyboard_run_killed_while_the_pages_are_made_leaves_the_earlier_sheet_as_it_was() -> void:
	var root := _make_root(false)
	var out := root.path_join("out")
	_seed_sheet(out)
	_write(root.path_join("fake/hold_page"), "30")
	_start(root, "storyboard.sh", PackedStringArray(["demo", out]))
	assert_true(_wait_for(root.path_join("fake/at_page")), "the run reached its page step")
	assert_true(_kill(_tool_pid(root, "page"), "KILL"), "the run was killed")
	assert_true(_sheet_is_the_old_one(out), "the earlier frames and pages are as they were")


func test_a_finished_storyboard_run_swaps_the_whole_sheet_in_and_leaves_no_scraps() -> void:
	var root := _make_root(false)
	var out := root.path_join("out")
	_seed_sheet(out)
	var run := _run(root, "storyboard.sh", PackedStringArray(["demo", out]))
	assert_eq(run.code, 0, run.text)
	assert_eq(_read(out.path_join("frames/shot-01.png")).strip_edges(), "new")
	assert_eq(_read(out.path_join("storyboard-1.png")).strip_edges(), "new")
	assert_false(FileAccess.file_exists(out.path_join("storyboard-2.png")), "a page the new sheet does not have is not left from the old")
	assert_false(FileAccess.file_exists(out.path_join("frames/shot-02.png")), "nor a frame")
	assert_eq(_read(out.path_join("animatic.mp4")), "old video", "the video is another tool's: untouched")
	assert_eq(Array(DirAccess.get_directories_at(out)), ["frames"], "no temporary folder is left: %s" % [DirAccess.get_directories_at(out)])
	assert_eq(Array(DirAccess.get_files_at(out)).filter(func(f: String) -> bool: return f.begins_with(".")), [], "no hidden scrap")


func test_an_animatic_run_killed_while_it_encodes_leaves_the_earlier_video_as_it_was() -> void:
	var root := _make_root(false)
	var out := root.path_join("out")
	_seed_sheet(out)
	_write(root.path_join("fake/hold_encode"), "30")
	_start(root, "animatic.sh", PackedStringArray(["demo", out]))
	assert_true(_wait_for(root.path_join("fake/at_encode")), "the run reached its encode")
	assert_true(_kill(_tool_pid(root, "encode"), "KILL"), "the run was killed")
	assert_eq(_read(out.path_join("animatic.mp4")), "old video", "a killed encode leaves the earlier video, not a short one")


func test_a_finished_animatic_run_puts_the_new_video_in_place_and_leaves_no_scraps() -> void:
	var root := _make_root(false)
	var out := root.path_join("out")
	_seed_sheet(out)
	var run := _run(root, "animatic.sh", PackedStringArray(["demo", out]))
	assert_eq(run.code, 0, run.text)
	assert_eq(_read(out.path_join("animatic.mp4")).strip_edges(), "new video")
	assert_eq(Array(DirAccess.get_files_at(out)).filter(func(f: String) -> bool: return f.begins_with(".") or f.ends_with(".tmp") or f.contains("part")), [], "no scrap beside it: %s" % [DirAccess.get_files_at(out)])
