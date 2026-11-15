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
	_folder = _root().path_join("scenes/story/zz_refused_%d" % OS.get_process_id())
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


# A scene with one real error (a beat outside its shot) and two stand-ins (a portrait with no drawing, a clip that is not made yet).
func _scene_with_an_error_and_two_stand_ins() -> String:
	_folder = _root().path_join("scenes/story/zz_mixed_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_folder)
	for file in ["script.md", "notes.md"]:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE_DIR).path_join(file), _folder.path_join(file))
	var shots := FileAccess.get_file_as_string(FIXTURE_DIR.path_join("shots.tres"))
	shots = shots.replace("id = &\"fixture_yard_entrance\"", "id = &\"%s\"" % _folder.get_file())
	shots = shots.replace("clip = &\"guard_raise\"", "clip = &\"guard_roar\"\nplaceholder = true")   # a clip the rig does not have, marked not made yet
	shots = shots.replace("at = 14\n", "at = 5000\n")   # a beat far outside its shot: the real error
	var file := FileAccess.open(_folder.path_join("shots.tres"), FileAccess.WRITE)
	file.store_string(shots)
	file.close()
	return _folder.get_file()


func test_a_refusal_prints_the_errors_first_and_the_stand_in_notes_after_under_their_own_headings() -> void:
	var id := _scene_with_an_error_and_two_stand_ins()
	for script in ["storyboard.sh", "animatic.sh"]:
		var run := _run(script, PackedStringArray([id]))
		assert_eq(run.code, 1, "%s: %s" % [script, run.text])
		var lines: PackedStringArray = String(run.text).split("\n")
		var cannot := Array(lines).find("Cannot make the sheet:")
		var also := Array(lines).find("Also not final:")
		assert_true(cannot >= 0, "%s says 'Cannot make the sheet:': %s" % [script, run.text])
		assert_true(also > cannot, "%s says 'Also not final:' after it: %s" % [script, run.text])
		if cannot < 0 or also <= cannot:
			continue
		var errors := lines.slice(cannot + 1, also)
		var notes := lines.slice(also + 1)
		assert_eq(errors.size(), 1, "one real error, under the first heading: %s" % [errors])
		assert_true(errors.size() == 1 and String(errors[0]).contains("outside the shot") and not String(errors[0]).contains("placeholder"), "%s" % [errors])
		assert_eq(notes.size(), 2, "two stand-ins, under the second: %s" % [notes])
		for note in notes:
			assert_true(String(note).contains("placeholder: "), "a stand-in note: %s" % note)
