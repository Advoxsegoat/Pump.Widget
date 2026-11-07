extends TestCase
## The assertions of TestCase itself. Each case runs an assertion on a separate probe TestCase and looks
## at what the probe recorded, so a failing assertion here is a finding, not a failure of this test.
##
## The engine hands out two kinds of null. `null` written in a script is TYPE_NIL, and so is a cast
## `x as T` of an object that is not a T. A method or property typed as an Object that has nothing to
## give (get_node_or_null on a missing node, Image.load_from_file on a missing file, an unset mesh or
## skin) gives TYPE_OBJECT with no object in it, and stays so through a cast or a typed variable. A freed
## object is TYPE_OBJECT too. All of them must count as null.


func test_an_engine_null_object_equals_null() -> void:
	var holder := Node.new()
	var mesh_instance := MeshInstance3D.new()
	var typed: Node3D = holder.get_node_or_null("missing")
	var nulls := {
		"get_node_or_null": holder.get_node_or_null("missing"),
		"a cast of a missing node": holder.get_node_or_null("missing") as Node3D,
		"a typed variable given a missing node": typed,
		"an unset mesh": mesh_instance.mesh,
		"an unset skin": mesh_instance.skin,
	}
	for what: String in nulls:
		var value: Variant = nulls[what]
		assert_eq(typeof(value), TYPE_OBJECT, "%s is an Object-typed null, the case under test" % what)
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(value, null)).size(), 0, "assert_eq(%s, null) passes" % what)
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(null, value)).size(), 0, "assert_eq(null, %s) passes" % what)
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(value, null)).size(), 1, "assert_ne(%s, null) fails" % what)
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(null, value)).size(), 1, "assert_ne(null, %s) fails" % what)
	mesh_instance.free()
	holder.free()


func test_a_missing_image_file_equals_null() -> void:
	# Joined at run time, so the path check (test_paths.gd) does not take it for a broken reference.
	var missing := "res://tests/fixtures/".path_join("no_such_picture.png")
	var image: Variant = quietly(func() -> Variant: return Image.load_from_file(missing))
	assert_eq(typeof(image), TYPE_OBJECT)
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(image, null)).size(), 0, "assert_eq passes")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(image, null)).size(), 1, "assert_ne fails")


func test_a_freed_object_equals_null() -> void:
	var node := Node.new()
	var kept: Variant = node
	node.free()
	assert_false(is_instance_valid(kept))
	# Called straight on a probe: a lambda would not carry a freed object, it passes null in its place.
	var probe := TestCase.new()
	probe._begin()
	probe.assert_eq(kept, null)
	probe.assert_eq(null, kept)
	assert_eq(probe._failures.size(), 0, "assert_eq(freed, null) passes: %s" % [probe._failures])
	probe._begin()
	probe.assert_ne(kept, null)
	probe.assert_ne(null, kept)
	assert_eq(probe._failures.size(), 2, "assert_ne(freed, null) fails")
	probe.free()


func test_a_real_object_is_not_null() -> void:
	var node := Node.new()
	var resource := Resource.new()
	for value: Object in [node, resource]:
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(value, null)).size(), 1, "assert_eq(%s, null) fails" % value.get_class())
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(null, value)).size(), 1, "assert_eq(null, %s) fails" % value.get_class())
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(value, null)).size(), 0, "assert_ne(%s, null) passes" % value.get_class())
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(null, value)).size(), 0, "assert_ne(null, %s) passes" % value.get_class())
	node.free()


func test_plain_null_and_other_values() -> void:
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(null, null)).size(), 0, "null is null")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(null, null)).size(), 1)
	var not_a_node: Object = RefCounted.new()
	var wrong_cast: Variant = not_a_node as Node
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(wrong_cast, null)).size(), 0, "a cast that does not fit is null")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(wrong_cast, null)).size(), 1)
	# Values that are not objects are never null, even when they are empty or zero.
	for value: Variant in [0, 0.0, false, "", &"", [], {}, Vector3.ZERO, NodePath(), PackedByteArray()]:
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_eq(value, null)).size(), 1, "%s (%s) is not null" % [value, type_string(typeof(value))])
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(value, null)).size(), 0, "%s (%s) is anything but null" % [value, type_string(typeof(value))])


func test_assert_ne() -> void:
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(1, 2)).size(), 0, "1 is not 2")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne("a", "b")).size(), 0, "\"a\" is not \"b\"")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(Vector3.ONE, Vector3.ZERO)).size(), 0)
	var failures := _recorded(func(t: TestCase) -> void: t.assert_ne(3, 3, "why"))
	assert_eq(failures.size(), 1, "3 is 3")
	if failures.size() == 1:
		assert_true(failures[0].begins_with("expected anything but 3 (why) @ "), failures[0])
	# Ints and floats, and Strings and StringNames, are one kind each, as for assert_eq.
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(1, 1.0)).size(), 1, "1 is 1.0")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne("a", &"a")).size(), 1, "\"a\" is &\"a\"")
	# Other kinds never match, and comparing them raises no engine error.
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne([1], PackedInt32Array([1]))).size(), 0)
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(1, "1")).size(), 0)
	# NaN is equal to nothing, itself included.
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_ne(NAN, NAN)).size(), 0, "NaN is not NaN")


func test_assert_near() -> void:
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(1.0, 1.05, 0.1)).size(), 0, "within")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(1.05, 1.0, 0.1)).size(), 0, "either order")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(-1.0, -1.0, 0.0)).size(), 0, "equal, with no tolerance")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(0.0, 0.5, 0.5)).size(), 0, "the tolerance is inclusive")
	var failures := _recorded(func(t: TestCase) -> void: t.assert_near(1.0, 1.2, 0.1, "why"))
	assert_eq(failures.size(), 1, "beyond the tolerance")
	if failures.size() == 1:
		assert_true(failures[0].begins_with("1.0 is not within 0.1 of 1.2 (why) @ "), failures[0])
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(-1.0, 1.0, 1.0)).size(), 1, "on either side of zero")
	# NaN is near nothing, whatever the tolerance.
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(NAN, 0.0, 1.0)).size(), 1, "NaN against a number")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(0.0, NAN, 1.0)).size(), 1, "a number against NaN")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(NAN, NAN, 1.0)).size(), 1, "NaN against NaN")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(NAN, 0.0, INF)).size(), 1, "NaN with an infinite tolerance")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(0.0, 1.0, NAN)).size(), 1, "a NaN tolerance")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_near(INF, 0.0, 1e9)).size(), 1, "infinity is far from everything finite")


func test_assert_vec_near() -> void:
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_vec_near(Vector3(1, 2, 3), Vector3(1, 2, 3.05), 0.1)).size(), 0, "within")
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_vec_near(Vector3.ZERO, Vector3(3, 4, 0), 5.0)).size(), 0, "the distance, inclusive")
	# Each axis is within 0.1, but the distance is 0.15: the tolerance is on the distance.
	assert_eq(_recorded(func(t: TestCase) -> void: t.assert_vec_near(Vector3.ZERO, Vector3(0.09, 0.09, 0.09), 0.1)).size(), 1, "on the distance, not per axis")
	var failures := _recorded(func(t: TestCase) -> void: t.assert_vec_near(Vector3.ZERO, Vector3(0, 1, 0), 0.5, "why"))
	assert_eq(failures.size(), 1, "beyond the tolerance")
	if failures.size() == 1:
		assert_true(failures[0].begins_with("(0.0, 0.0, 0.0) is not within 0.5 of (0.0, 1.0, 0.0) (why) @ "), failures[0])
	# A NaN on any axis is near nothing.
	for axis in 3:
		var bad := Vector3.ZERO
		bad[axis] = NAN
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_vec_near(bad, Vector3.ZERO, 1.0)).size(), 1, "NaN on axis %d" % axis)
		assert_eq(_recorded(func(t: TestCase) -> void: t.assert_vec_near(Vector3.ZERO, bad, INF)).size(), 1, "NaN on axis %d, infinite tolerance" % axis)


# What `check` records when it runs its assertions on a separate TestCase.
func _recorded(check: Callable) -> PackedStringArray:
	var probe := TestCase.new()
	probe._begin()
	check.call(probe)
	var failures := probe._failures.duplicate()
	probe.free()
	return failures
