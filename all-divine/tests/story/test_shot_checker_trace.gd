extends TestCase
## "Finished" covers every function of the checker at any depth: a script error aborts a function silently, so each one
## enters and leaves through `_enter`/`_leave`, and this test reads the checker's own source and fails for any that does not.

const SOURCE := "res://story/shot_checker.gd"
const FOLDER := "res://scenes/story/fixture_yard_entrance"
## Not part of the pattern: the mechanism itself, and the constructor.
const EXEMPT: PackedStringArray = ["_enter", "_leave", "_init"]


func _fixture() -> SceneShots:
	return (load(FOLDER + "/shots.tres") as SceneShots).duplicate_deep()


# The functions of the source: {name, header line, body lines (with their numbers)}; static ones are pure sums and out.
func _functions() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var lines := FileAccess.get_file_as_string(SOURCE).split("\n")
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


func test_every_function_of_the_checker_enters_first_and_leaves_on_every_way_out() -> void:
	var functions := _functions()
	assert_true(functions.size() > 30, "found %d functions" % functions.size())
	for function in functions:
		if EXEMPT.has(function.name):
			continue
		var where := "%s (line %d)" % [function.name, function.header]
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
