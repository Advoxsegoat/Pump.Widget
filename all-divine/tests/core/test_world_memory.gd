extends TestCase
## The world's memory (core/save/world_memory.gd): the flags the player's deeds have set, and how they are saved.

var _announced: Array[StringName] = []


func _note(flag: StringName) -> void:
	_announced.append(flag)


func before_each() -> void:
	_announced = []


func test_a_flag_is_new_once_and_announced_once() -> void:
	var memory := WorldMemory.new()
	memory.flagged.connect(_note)
	assert_false(memory.has(&"shortcut_open"), "nothing is set at the start")
	assert_true(memory.set_flag(&"shortcut_open"), "the first time it is news")
	assert_false(memory.set_flag(&"shortcut_open"), "the second time it is not")
	assert_true(memory.has(&"shortcut_open"), "and it stays set")
	assert_eq(_announced, [&"shortcut_open"] as Array[StringName], "announced once, by name")


func test_names_are_sorted_and_to_dict_round_trips() -> void:
	var memory := WorldMemory.new()
	memory.set_flag(&"b")
	memory.set_flag(&"a")
	assert_eq(memory.names(), [&"a", &"b"] as Array[StringName], "sorted whatever the order they were set in")
	assert_eq(memory.to_dict(), {"a": true, "b": true}, "a name and true each")
	assert_eq(WorldMemory.from_dict(memory.to_dict()).names(), [&"a", &"b"] as Array[StringName], "and back")


func test_from_dict_takes_only_true_values_and_survives_junk() -> void:
	var got := WorldMemory.from_dict({"a": true, "b": false, "c": "yes", "d": 1})
	assert_eq(got.names(), [&"a"] as Array[StringName], "only a true is a flag")
	for junk: Variant in [null, [1], "x", 3, 2.5]:
		assert_eq(WorldMemory.from_dict(junk).names().size(), 0, "no flags from %s" % [junk])
