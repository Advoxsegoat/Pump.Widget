extends TestCase
## What a saved game holds (core/save/save_data.gd): the defaults, and that a file with a missing, mistyped or odd
## field gives the default of that field and never a crash. The file itself is tests/core/test_save_store.gd.


func _sample() -> SaveData:
	var data := SaveData.new()
	data.rest_shrine = &"rose_b"
	data.petals = 120
	data.pile = {"x": 27.5, "y": 0.0, "z": -30.0, "amount": 80, "frames": 600}
	data.items = {&"rose_bell": 1}
	data.memory.set_flag(&"shortcut_open")
	data.memory.set_flag(&"collector_down")
	data.deaths = 3
	data.play_frames = 7200
	data.at = {"x": 12.25, "y": 0.0, "z": -3.5, "yaw": 90.0}
	data.bars = {"hp": 0.5, "stamina": 0.75, "posture": 1.0}
	data.fallen = [&"a", &"b"] as Array[StringName]
	return data


func test_a_new_game_is_empty() -> void:
	var data := SaveData.new_game()
	assert_eq(data.rest_shrine, &"", "rests nowhere: the start")
	assert_eq(data.petals, 0, "no petals")
	assert_eq(data.pile, {}, "no pile")
	assert_eq(data.items, {}, "no items")
	assert_eq(data.memory.names().size(), 0, "no flags")
	assert_eq(data.deaths, 0, "no deaths")
	assert_eq(data.play_frames, 0, "no time played")
	assert_eq(data.at, {}, "no place")
	assert_eq(data.bars, {}, "no bars")
	assert_eq(data.fallen.size(), 0, "nobody fallen")


func test_to_dict_names_every_field_and_neither_version_nor_check() -> void:
	var d := _sample().to_dict()
	assert_false(d.has("version"), "the version is the file's, not the data's")
	assert_false(d.has("check"), "and so is the check")
	var keys := d.keys()
	keys.sort()
	assert_eq(keys, ["at", "bars", "deaths", "fallen", "flags", "items", "petals", "pile", "play_frames", "rest_shrine"],
			"one key for each field")
	assert_eq(d["items"], {"rose_bell": 1}, "items go by their names as text")
	assert_eq(d["flags"], {"collector_down": true, "shortcut_open": true}, "flags as the memory writes them")


func test_a_dictionary_round_trips_every_field() -> void:
	var back := SaveData.from_dict(_sample().to_dict())
	assert_eq(back.to_dict(), _sample().to_dict(), "the same dictionary comes out")
	assert_eq(back.rest_shrine, &"rose_b", "shrine")
	assert_eq(back.petals, 120, "petals")
	assert_eq(back.items.get(&"rose_bell"), 1, "an item is found by its StringName")
	assert_true(back.memory.has(&"shortcut_open"), "flags")
	assert_eq(back.fallen, [&"a", &"b"] as Array[StringName], "fallen")


func test_a_missing_or_mistyped_field_is_its_default_and_unknown_fields_are_ignored() -> void:
	var got := SaveData.from_dict({
		"petals": "many", "deaths": -4, "mood": "grim", "play_frames": 2.5, "rest_shrine": 7,
		"flags": {"x": true, "y": 3}, "pile": {"x": 1.0, "y": 0.0, "z": 2.0, "frames": 3},
		"items": {"rose_bell": 2, "bad": "one", "half": 1.5, "gone": -1, 3: 4},
	})
	assert_eq(got.petals, 0, "petals: text is 0")
	assert_eq(got.deaths, 0, "deaths: negative is 0")
	assert_eq(got.play_frames, 0, "play_frames: a fraction is mistyped, so 0")
	assert_eq(got.rest_shrine, &"", "a shrine that is not text is the start")
	assert_eq(got.memory.names(), [&"x"] as Array[StringName], "flags: only the true one")
	assert_eq(got.pile, {}, "a pile lacking a part is empty")
	assert_eq(got.items, {&"rose_bell": 2}, "items: only whole counts above nothing, under a text name")
	assert_false(got.to_dict().has("mood"), "an unknown key is not carried")


func test_a_whole_float_is_a_whole_number() -> void:
	var got := SaveData.from_dict({"petals": 120.0, "pile": {"x": 1, "y": 0, "z": 2, "amount": 5.0, "frames": 6.0}})
	assert_eq(got.petals, 120, "json gives floats; a whole one is the number")
	assert_eq(got.pile.get("amount"), 5, "also inside the pile")


func test_a_place_is_empty_or_four_finite_numbers() -> void:
	var good := SaveData.from_dict({"at": {"x": 1.5, "y": 0.0, "z": -2.0, "yaw": 270.0}})
	assert_eq(good.at, {"x": 1.5, "y": 0.0, "z": -2.0, "yaw": 270.0}, "a whole place is kept")
	var whole_numbers := SaveData.from_dict({"at": {"x": 1, "y": 0, "z": -2, "yaw": 90}})
	assert_eq(whole_numbers.at.get("yaw"), 90.0, "whole numbers are numbers")
	assert_true(typeof(whole_numbers.at.get("yaw")) == TYPE_FLOAT, "and are held as floats")
	var bad: Array = [
		{"x": 1.0, "y": 0.0, "z": 2.0},
		{"x": 1.0, "y": 0.0, "yaw": 2.0},
		{"x": "1", "y": 0.0, "z": 2.0, "yaw": 0.0},
		{"x": 1.0, "y": 0.0, "z": 2.0, "yaw": null},
		{"x": NAN, "y": 0.0, "z": 2.0, "yaw": 0.0},
		{"x": 1.0, "y": INF, "z": 2.0, "yaw": 0.0},
		{"x": 1.0, "y": 0.0, "z": 2.0, "yaw": -INF},
		{"x": true, "y": 0.0, "z": 2.0, "yaw": 0.0},
		[1.0, 0.0, 2.0, 0.0],
		"here",
		3,
	]
	for form: Variant in bad:
		assert_eq(SaveData.from_dict({"at": form}).at, {}, "empty for %s" % [form])


func test_bars_are_empty_or_three_shares_clamped_to_0_to_1() -> void:
	var good := SaveData.from_dict({"bars": {"hp": 0.25, "stamina": 1.0, "posture": 0.0}})
	assert_eq(good.bars, {"hp": 0.25, "stamina": 1.0, "posture": 0.0}, "whole bars are kept")
	var clamped := SaveData.from_dict({"bars": {"hp": 1.5, "stamina": -0.2, "posture": 7}})
	assert_eq(clamped.bars, {"hp": 1.0, "stamina": 0.0, "posture": 1.0}, "a share outside 0 to 1 is clamped")
	var bad: Array = [
		{"hp": 0.5, "stamina": 0.5},
		{"hp": 0.5, "stamina": "full", "posture": 0.5},
		{"hp": null, "stamina": 0.5, "posture": 0.5},
		{"hp": NAN, "stamina": 0.5, "posture": 0.5},
		{"hp": 0.5, "stamina": INF, "posture": 0.5},
		{"hp": false, "stamina": 0.5, "posture": 0.5},
		[0.5, 0.5, 0.5],
		"full",
	]
	for form: Variant in bad:
		assert_eq(SaveData.from_dict({"bars": form}).bars, {}, "empty for %s" % [form])


func test_fallen_keeps_strings_only_sorted_without_doubles() -> void:
	var got := SaveData.from_dict({"fallen": ["b", "a", "b", 3, null]})
	assert_eq(got.fallen, [&"a", &"b"] as Array[StringName], "strings only, sorted, no doubles")
	assert_eq(got.to_dict()["fallen"], ["a", "b"], "and written the same way")
	for form: Variant in ["a", 3, {"a": 1}, null]:
		assert_eq(SaveData.from_dict({"fallen": form}).fallen.size(), 0, "empty for %s" % [form])
	var with_empty := SaveData.from_dict({"fallen": ["", "z", &"y"]})
	assert_eq(with_empty.fallen, [&"y", &"z"] as Array[StringName], "an empty id is not an id; a StringName is a string")
