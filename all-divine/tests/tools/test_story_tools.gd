extends TestCase
## tools/storyboard.sh and tools/animatic.sh as the owner runs them, in the cases that need no display: a scene that does not exist
## (exit 2, one line), a scene the shot checker refuses (exit 1, the checker's lines, nothing shot), an animatic with no ffmpeg
## (exit 3, one line). The runs that shoot are tests/render/test_story_shots.gd.

const FIXTURE_DIR := "res://scenes/story/fixture_yard_entrance"
const LIMIT := 120
var _folder := ""


func after_each() -> void:
	if _folder != "":
		for file in DirAccess.get_files_at(_folder):
			DirAccess.remove_absolute(_folder.path_join(file))
		DirAccess.remove_absolute(_folder)
		_folder = ""


func _root() -> String:
	return ProjectSettings.globalize_path("res://")


# Runs tools/<script> with `args` (and `env` as KEY=VALUE pairs); {code, text} (the output of both streams).
func _run(script: String, args: PackedStringArray, env := PackedStringArray()) -> Dictionary:
	var argv := PackedStringArray(["-k", "5", str(LIMIT)])
	if not env.is_empty():
		argv.append("env")
		argv.append_array(env)
	argv.append(_root().path_join("tools").path_join(script))
	argv.append_array(args)
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	return {code = code, text = "\n".join(output).strip_edges()}


func test_a_scene_that_does_not_exist_is_one_line_and_exit_2_from_both_tools() -> void:
	for script in ["storyboard.sh", "animatic.sh"]:
		var run := _run(script, PackedStringArray(["no_such_scene"]))
		assert_eq(run.code, 2, "%s: %s" % [script, run.text])
		assert_eq(run.text.split("\n").size(), 1, "%s says it in one line: %s" % [script, run.text])
		assert_true(run.text.contains("no_such_scene"), run.text)


func test_no_scene_at_all_is_the_usage_line_and_exit_2() -> void:
	for script in ["storyboard.sh", "animatic.sh"]:
		var run := _run(script, PackedStringArray())
		assert_eq(run.code, 2, "%s: %s" % [script, run.text])
		assert_true(run.text.contains("usage:"), run.text)


func test_a_scene_the_checker_refuses_stops_both_tools_with_the_checkers_lines_and_exit_1() -> void:
	_folder = ProjectSettings.globalize_path("res://scenes/story/zz_refused_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_folder)
	for file in ["script.md", "notes.md"]:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE_DIR).path_join(file), _folder.path_join(file))
	var shots := FileAccess.get_file_as_string(FIXTURE_DIR.path_join("shots.tres"))
	var file := FileAccess.open(_folder.path_join("shots.tres"), FileAccess.WRITE)
	file.store_string(shots.replace("action = \"A line\"", "action = \"A line\"\nnonsense = 1"))   # a key the Shot class does not have
	file.close()
	var id := _folder.get_file()
	for script in ["storyboard.sh", "animatic.sh"]:
		var run := _run(script, PackedStringArray([id]))
		assert_eq(run.code, 1, "%s: %s" % [script, run.text])
		assert_true(run.text.contains("story_check: "), "%s prints the checker's own lines: %s" % [script, run.text])
		assert_false(run.text.contains("wrote"), "nothing is shot: %s" % run.text)


func test_an_animatic_with_no_ffmpeg_says_so_in_one_line_and_exits_3() -> void:
	var run := _run("animatic.sh", PackedStringArray(["fixture_yard_entrance"]), PackedStringArray(["FFMPEG=no-such-ffmpeg-here"]))
	assert_eq(run.code, 3, run.text)
	assert_eq(run.text.split("\n").size(), 1, run.text)
	assert_true(run.text.contains("ffmpeg"), run.text)
