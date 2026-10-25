class_name TestCase
extends Node
## Base class for tests. Every method named test_* is a test; a test may await.
##
## Assertions record a failure and the test carries on. The test fails if it
## recorded any failure, if the engine raised an error it did not expect_error,
## or if an expected error never came.

var _failures := PackedStringArray()
var _expected_errors := PackedStringArray()
var _tracked: Array[Node] = []


## Runs before each test.
func before_each() -> void:
	pass


## Runs after each test.
func after_each() -> void:
	pass


func assert_true(condition: bool, msg := "") -> void:
	if not condition:
		_record("expected true", msg)


func assert_false(condition: bool, msg := "") -> void:
	if condition:
		_record("expected false", msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if not _same(actual, expected):
		_record("expected %s, got %s" % [_show(expected, actual), _show(actual, expected)], msg)


func assert_ne(actual: Variant, unexpected: Variant, msg := "") -> void:
	if _same(actual, unexpected):
		_record("expected anything but %s" % _show(unexpected, actual), msg)


func assert_near(a: float, b: float, eps: float, msg := "") -> void:
	if not absf(a - b) <= eps:
		_record("%s is not within %s of %s" % [a, eps, b], msg)


func assert_vec_near(a: Vector3, b: Vector3, eps: float, msg := "") -> void:
	if not (a - b).length() <= eps:
		_record("%s is not within %s of %s" % [a, eps, b], msg)


## The test passes only if the engine raises an error containing `fragment`.
func expect_error(fragment: String) -> void:
	_expected_errors.append(fragment)


func fail(msg: String) -> void:
	_record(msg, "")


## Awaits n physics frames. Every test starts on a physics frame, so after
## `await frames(n)` Engine.get_physics_frames() has risen by exactly n.
func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Adds `node` under this test and frees it after the test.
func track(node: Node) -> Node:
	add_child(node)
	_tracked.append(node)
	return node


## True when the run was given --update-golden.
func update_golden() -> bool:
	return OS.get_cmdline_user_args().has("--update-golden")


# --- used by TestRunner ---

func _begin() -> void:
	_failures = PackedStringArray()
	_expected_errors = PackedStringArray()
	_tracked.clear()


func _free_tracked() -> void:
	for i in range(_tracked.size() - 1, -1, -1):
		if is_instance_valid(_tracked[i]):
			_tracked[i].free()
	_tracked.clear()


## Given the engine errors raised during the test, returns every reason it failed.
func _finish(raised: PackedStringArray) -> PackedStringArray:
	var reasons := _failures.duplicate()
	var seen := {}
	for error in raised:
		var expected := false
		for fragment in _expected_errors:
			if error.contains(fragment):
				seen[fragment] = true
				expected = true
		if not expected:
			reasons.append("unexpected error: " + error)
	for fragment in _expected_errors:
		if not seen.has(fragment):
			reasons.append("expected an error containing \"%s\", but none was raised" % fragment)
	return reasons


func _record(what: String, msg: String) -> void:
	var text := what if msg.is_empty() else "%s (%s)" % [what, msg]
	_failures.append(text + _where())


# Where the test called the assertion: the first stack frame outside this file.
func _where() -> String:
	var here: String = (TestCase as Script).resource_path
	for frame in get_stack():
		if frame.source != here:
			return " @ %s:%d" % [frame.source, frame.line]
	return ""


# == raises an engine error on some mixed types (an Array against a PackedInt32Array),
# so only values of the same kind are compared; ints and floats, and Strings and StringNames, count as one kind.
func _same(a: Variant, b: Variant) -> bool:
	var kind_a := _kind(typeof(a))
	if kind_a != _kind(typeof(b)):
		return false
	return a == b


func _kind(type: int) -> int:
	if type == TYPE_INT:
		return TYPE_FLOAT
	if type == TYPE_STRING_NAME:
		return TYPE_STRING
	return type


# The value as text. Its type is added when it differs from the other value's, so that
# [1] against PackedInt32Array([1]) does not read as a failure with nothing to see.
func _show(value: Variant, other: Variant) -> String:
	var text := "\"%s\"" % value if value is String or value is StringName else str(value)
	if typeof(value) != typeof(other):
		text += " (%s)" % type_string(typeof(value))
	return text
