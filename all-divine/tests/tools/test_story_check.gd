extends TestCase
## tools/story_check.gd run as a command: its exit codes and its lines, with its options before or after `--`.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
var _temp := ""   # a folder of this run's own: two runs at once never share one
const CHILD_LIMIT := 120


func before_each() -> void:
	_temp = "user://story_check_tool_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func after_each() -> void:
	var access := DirAccess.open(_temp)
	if access != null:
		for file in access.get_files():
			access.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_temp))


# Runs the tool in a child Godot with `args` (as they would follow `-s res://tools/story_check.gd`); returns {code, text}.
func _run(args: PackedStringArray) -> Dictionary:
	var argv := PackedStringArray(["-k", "5", str(CHILD_LIMIT), OS.get_executable_path(), "--headless",
			"--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/story_check.gd"])
	argv.append_array(args)
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	return {code = code, text = "\n".join(output)}


# A copy of the fixture's shots.tres in the temp folder under `name`, `edit` applied to its text.
func _scene_file(name: String, edit: Callable) -> String:
	DirAccess.make_dir_recursive_absolute(_temp)
	var path := _temp.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(edit.call(FileAccess.get_file_as_string(FIXTURE)))
	file.close()
	return ProjectSettings.globalize_path(path)


func _placeholder_scene() -> String:
	return _scene_file("placeholder.tres", func(text: String) -> String:
		return text.replace("clip = &\"knuckle_idle\"", "clip = &\"no_such_clip\"\nplaceholder = true"))


func test_the_repository_is_ok_and_says_how_many() -> void:
	var run := await _run(PackedStringArray())
	assert_eq(run.code, 0, run.text)
	assert_true(run.text.contains("story_check: 1 scenes OK (1 placeholders)"), run.text)  # the fixture's Knuckle has only the blank card
	assert_true(run.text.contains("fixture_knuckle's portrait 'neutral' is a stand-in"), run.text)
	assert_false(run.text.contains("ERROR") or run.text.contains("WARNING"), run.text)


func test_final_is_read_before_the_double_dash_and_after_it() -> void:
	var path := _placeholder_scene()
	var plain := await _run(PackedStringArray(["--", path]))
	assert_eq(plain.code, 0, plain.text)
	assert_true(plain.text.contains("(2 placeholders)"), plain.text)  # the clip, and the fixture's blank-card speaker
	assert_true(plain.text.contains("placeholder: knuckle has no clip 'no_such_clip'"), plain.text)
	assert_true(plain.text.contains("is a stand-in"), plain.text)
	for args in [["--final", "--", path], ["--", "--final", path], ["--", path, "--final"]]:
		var run := await _run(PackedStringArray(args))
		assert_eq(run.code, 1, "%s: %s" % [args, run.text])
		assert_true(run.text.contains("story_check: fixture_yard_entrance/S2: placeholder: knuckle has no clip 'no_such_clip'"), run.text)


func test_an_option_it_does_not_know_is_the_usage_line_and_exit_2_in_either_place() -> void:
	for args in [["--bogus"], ["--", "--bogus"], ["--scene=fixture_yard_entrance", "--", "--nope"]]:
		var run := await _run(PackedStringArray(args))
		assert_eq(run.code, 2, "%s: %s" % [args, run.text])
		assert_true(run.text.contains("usage: tools/godot.sh -s res://tools/story_check.gd"), run.text)


func test_a_scene_that_is_not_there_and_paths_that_are_not_scenes() -> void:
	var run := await _run(PackedStringArray(["--scene=nope"]))
	assert_eq(run.code, 1, run.text)
	assert_true(run.text.contains("no scene folder 'nope'"), run.text)
	run = await _run(PackedStringArray(["--", _temp + "/nothing.tres"]))
	assert_eq(run.code, 1, run.text)
	assert_true(run.text.contains("nothing.tres is missing"), run.text)
	assert_true(run.text.contains(_temp.get_slice("//", 1) + "/nothing.tres") or run.text.contains("nothing.tres)"), "the line names the path: " + run.text)
	var plain := _scene_file("plain.tres", func(_text: String) -> String: return "[gd_resource type=\"Resource\" format=3]\n\n[resource]\n")
	run = await _run(PackedStringArray(["--", plain]))
	assert_eq(run.code, 1, run.text)
	assert_true(run.text.contains("is not a SceneShots"), run.text)
	var broken := _scene_file("broken.tres", func(text: String) -> String: return text.substr(0, 300) + "\n= = [[")
	run = await _run(PackedStringArray(["--", broken]))
	assert_eq(run.code, 1, run.text)
	assert_true(run.text.contains("does not parse"), run.text)


func test_a_damaged_scene_is_a_problem_and_never_ok() -> void:
	var path := _scene_file("damaged.tres", func(text: String) -> String: return text.replace("status = 0", "status = 9"))
	var run := await _run(PackedStringArray(["--", path]))
	assert_eq(run.code, 1, run.text)
	assert_true(run.text.contains("status 9 is not one of"), run.text)
	assert_false(run.text.contains("OK ("), run.text)


func test_the_place_is_checked_for_every_scene() -> void:
	var path := _scene_file("outside.tres", func(text: String) -> String:
		return text.replace("Vector3(2.2, 0, 2.6)", "Vector3(2.2, 0, 2.6)").replace("position = Vector3(0, 0, 5)", "position = Vector3(40, 0, 5)"))
	var run := await _run(PackedStringArray(["--", path]))
	assert_eq(run.code, 1, run.text)
	assert_true(run.text.contains("mark 'rehearsal.abarax'"), run.text)


func test_a_scene_option_with_paths_is_the_usage_line() -> void:
	var run := await _run(PackedStringArray(["--scene=fixture_yard_entrance", "--", FIXTURE]))
	assert_eq(run.code, 2, run.text)
	assert_true(run.text.contains("usage: tools/godot.sh -s res://tools/story_check.gd"), run.text)


func test_an_element_the_loader_dropped_is_a_problem_and_a_bad_file_prints_its_engine_lines_once() -> void:
	var path := _scene_file("dropped.tres", func(text: String) -> String:
		var start := text.find("\nmarks = ") + 1
		var end := text.find("\n", start)
		var line := text.substr(start, end - start)
		return text.substr(0, start) + line.left(line.length() - 2) + ", \"oops\"])" + text.substr(end))
	var run := await _run(PackedStringArray(["--", path]))
	assert_eq(run.code, 1, run.text)
	assert_true(run.text.contains("'marks' has 1 element that is not a SceneMark"), run.text)
	assert_false(run.text.contains("OK ("), run.text)
	var broken := _scene_file("broken_once.tres", func(text: String) -> String: return text.substr(0, 300) + "\n= = [[")
	run = await _run(PackedStringArray(["--", broken]))
	var engine_errors := 0
	for line in run.text.split("\n"):
		if line.begins_with("ERROR:") or line.begins_with("SCRIPT ERROR:"):
			engine_errors += 1
	var once := await _run(PackedStringArray(["--", broken]))
	assert_true(engine_errors <= 3, "the engine's own lines for the file come once, not twice: %d\n%s" % [engine_errors, run.text])
	assert_true(once.text.contains("does not parse"), once.text)
