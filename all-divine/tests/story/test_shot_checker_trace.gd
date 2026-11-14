extends TestCase
## "Finished" covers every function of the checker at any depth: a script error aborts a function silently, so each one
## enters and leaves through `_enter`/`_leave`, and this test reads the checker's own source and fails for any that does not.

## The checking path: the checker, the job the tool hands each scene to, and the tool.
const SOURCES: PackedStringArray = ["res://story/shot_checker.gd", "res://story/story_check_job.gd", "res://tools/story_check.gd"]
const FOLDER := "res://scenes/story/fixture_yard_entrance"
## Not part of the pattern: the mechanism itself, and the constructor.
const EXEMPT: PackedStringArray = ["_enter", "_leave", "_init", "_initialize"]


# The fixture with Knuckle's line said by Abarax: the fixture's own speaker has no drawing yet, and the stand-in that lists is the
# portrait tests' business (tests/hud/test_portrait_card.gd), not this file's.
func _fixture() -> SceneShots:
	var scene := (load(FOLDER + "/shots.tres") as SceneShots).duplicate_deep()
	for shot in scene.shots:
		for line in shot.lines:
			if line.speaker == &"fixture_knuckle":
				line.speaker = &"abarax"
	return scene


# The functions of the source: {name, header line, body lines (with their numbers)}; static ones are pure sums and out.
func _functions(source: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var lines := FileAccess.get_file_as_string(source).split("\n")
	var i := 0
	while i < lines.size():
		var header := RegEx.create_from_string("^func (\\w+)\\(").search(lines[i])
		if header == null:
			i += 1
			continue
		var body: Array[Dictionary] = []
		var j := i + 1
		while j < lines.size() and (lines[j].begins_with("\t") or lines[j].strip_edges() == ""):
			if lines[j].strip_edges() != "":
				body.append({text = lines[j], number = j + 1})
			j += 1
		found.append({name = header.get_string(1), header = i + 1, body = body})
		i = j
	return found


func test_no_static_function_and_no_lambda_is_on_the_checking_path() -> void:
	for source in SOURCES:
		var number := 0
		for line in FileAccess.get_file_as_string(source).split("\n"):
			number += 1
			assert_false(line.begins_with("static func"), "%s line %d is a static function: %s" % [source, number, line])
			assert_false(not line.strip_edges().begins_with("#") and line.contains("func("), "%s line %d is a lambda: %s" % [source, number, line])


func test_every_function_of_the_checking_path_enters_first_and_leaves_on_every_way_out() -> void:
	for source in SOURCES:
		_pattern(source)


func _pattern(source: String) -> void:
	var functions := _functions(source)
	assert_true(functions.size() >= 3, "found %d functions in %s" % [functions.size(), source])
	for function in functions:
		if EXEMPT.has(function.name):
			continue
		var where := "%s %s (line %d)" % [source.get_file(), function.name, function.header]
		var body: Array = function.body
		assert_false(body.is_empty(), where + " has no body")
		if body.is_empty():
			continue
		assert_eq(body[0].text.strip_edges(), '_enter(&"%s")' % function.name, where + ": the first statement is _enter")
		var previous := ""
		for line in body:
			var text: String = line.text.strip_edges()
			if text == "return":   # a void function: the line before it leaves
				assert_eq(previous, '_leave(&"%s")' % function.name, "%s: line %d returns without _leave" % [where, line.number])
			elif text.begins_with("return ") and not text.contains("func("):
				assert_true(text.begins_with('return _leave(&"%s"' % function.name), "%s: line %d returns without _leave: %s" % [where, line.number, text])
			previous = text
		var last: String = body[-1].text.strip_edges()
		assert_true(last.begins_with('_leave(&"%s"' % function.name) or last.begins_with('return _leave(&"%s"' % function.name),
				"%s: the last statement is a _leave" % where)


class ErrorInVoidHelper extends ShotChecker:
	func _check_target(_where: String, _field: String, _target: StringName, _what := "") -> void:
		_enter(&"_check_target")
		var nothing: Array = []
		var index := 3
		nothing[index] = 1   # a script error: the function ends here and says nothing


class ErrorInNestedHelper extends ShotChecker:
	func _check_line_overlaps(_shot: Shot) -> bool:
		_enter(&"_check_line_overlaps")
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return _leave(&"_check_line_overlaps", true)


func test_a_script_error_in_a_void_helper_is_reported_as_stopped() -> void:
	var checker := ErrorInVoidHelper.new()
	var lines: PackedStringArray = quietly(func() -> PackedStringArray: return checker.check(_fixture()))
	assert_false(checker.finished)
	assert_eq(lines.size(), 1, "\n".join(lines))
	assert_true("\n".join(lines).contains("the checker stopped before it finished: in the helper _check_target"), "\n".join(lines))


func test_a_script_error_in_a_nested_helper_is_reported_as_stopped() -> void:
	var checker := ErrorInNestedHelper.new()
	var lines: PackedStringArray = quietly(func() -> PackedStringArray: return checker.check(_fixture()))
	assert_false(checker.finished)
	assert_true("\n".join(lines).contains("the checker stopped before it finished: in the helper _check_line_overlaps"), "\n".join(lines))


func test_the_next_run_of_a_checker_that_stopped_is_not_poisoned() -> void:
	var checker := ErrorInVoidHelper.new()
	quietly(func() -> PackedStringArray: return checker.check(_fixture()))
	var good := ShotChecker.new()
	good.check(_fixture())
	assert_true(good.finished)


# --- the entry points and the file-reading helpers ---

class ErrorInLoad extends ShotChecker:
	func _load(_path: String, _name: String) -> Dictionary:
		_enter(&"_load")
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return _leave(&"_load", {})


class ErrorInFileProblems extends ShotChecker:
	func _file_problems(_path: String, _name: String) -> Dictionary:
		_enter(&"_file_problems")
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return _leave(&"_file_problems", {})


class ErrorInElements extends ShotChecker:
	func _elements(_text: String) -> PackedStringArray:
		_enter(&"_elements")
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return _leave(&"_elements", PackedStringArray())


class ErrorInDroppedElements extends ShotChecker:
	func _dropped_elements(_block: Dictionary, _scripts: Dictionary, _by_id: Dictionary, _name: String) -> PackedStringArray:
		_enter(&"_dropped_elements")
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return _leave(&"_dropped_elements", PackedStringArray())


class ErrorInKeys extends ShotChecker:
	func _keys_unknown_to(_script_path: String, _keys: Array, _name: String) -> PackedStringArray:
		_enter(&"_keys_unknown_to")
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return _leave(&"_keys_unknown_to", PackedStringArray())


func test_a_script_error_in_a_file_reading_helper_is_reported_as_stopped_by_check_folder_and_check_file() -> void:
	for checker: ShotChecker in [ErrorInLoad.new(), ErrorInFileProblems.new(), ErrorInElements.new(), ErrorInDroppedElements.new(), ErrorInKeys.new()]:
		for use_folder in [true, false]:
			var lines: PackedStringArray = quietly(func() -> PackedStringArray:
				return checker.check_folder(FOLDER) if use_folder else checker.check_file(FOLDER + "/shots.tres"))
			var where := "%s %s" % [checker.get_script().resource_name, "folder" if use_folder else "file"]
			assert_false(checker.finished, where)
			assert_true("\n".join(lines).contains("the checker stopped before it finished: in the helper _"), "%s: %s" % [where, "\n".join(lines)])


# A checker whose whole entry point is a script error: nothing of it enters or leaves, so only the caller can know.
class ErrorInCheckFolder extends ShotChecker:
	func check_folder(_folder: String) -> PackedStringArray:
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return PackedStringArray()


class ErrorInCheckFile extends ShotChecker:
	func check_file(_path: String) -> PackedStringArray:
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return PackedStringArray()


class ErrorInCheckPlace extends ShotChecker:
	func check_place(_scene: SceneShots, _space: PhysicsDirectSpaceState3D, _spawn: Variant = null) -> PackedStringArray:
		var nothing: Array = []
		var index := 3
		nothing[index] = 1
		return PackedStringArray()


func test_the_job_never_trusts_an_entry_point_that_did_not_finish() -> void:
	var job := StoryCheckJob.new()
	var lines: PackedStringArray = quietly(func() -> PackedStringArray: return job.folder_lines(ErrorInCheckFolder.new(), FOLDER))
	assert_true("\n".join(lines).contains("the checker stopped before it finished"), "folder: " + "\n".join(lines))
	lines = quietly(func() -> PackedStringArray: return job.file_lines(ErrorInCheckFile.new(), FOLDER + "/shots.tres"))
	assert_true("\n".join(lines).contains("the checker stopped before it finished"), "file: " + "\n".join(lines))
	lines = quietly(func() -> PackedStringArray: return job.place_lines(ErrorInCheckPlace.new(), _fixture(), null, null))
	assert_true("\n".join(lines).contains("the checker stopped before it finished"), "place: " + "\n".join(lines))
	var trusted := job.folder_lines(ShotChecker.new(), FOLDER)
	var problems := PackedStringArray()
	for line in trusted:
		if not line.contains("is a stand-in"):  # the fixture's own speaker has no drawing yet: listed, not a problem
			problems.append(line)
	assert_eq(problems, PackedStringArray(), "a checker that finishes is trusted")
