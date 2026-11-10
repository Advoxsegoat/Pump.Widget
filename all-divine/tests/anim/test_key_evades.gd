extends TestCase
## The layer files of the sway, duck and dash-step clips are what tools/anim/key_evades.gd makes of its table, within a
## rounding step (EvadeKeyer.differences, also `key_evades.gd -- --check`): a table edited and not written, or a file edited
## by hand, fails here. Not byte for byte: a value on the edge of a rounding step can fall the other way on another machine.

func test_the_committed_layers_are_what_the_table_makes() -> void:
	var made := EvadeKeyer.generate()
	var files: Dictionary = made["files"]
	assert_eq(files.size(), 16, "a layer for each of the sixteen clips")
	for clip: String in files:
		var path := "res://assets/anim/layers/%s.json" % clip
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		if FileAccess.file_exists(path):
			var found := EvadeKeyer.differences(files[clip], FileAccess.get_file_as_string(path))
			assert_true(found.is_empty(), "%s is not what key_evades.gd makes of its table (run it to write them): %s" % [path, found])


func test_every_layer_is_a_layer_the_builder_takes() -> void:
	# Each file is JSON of bone -> [[frame, x, y, z], ...] with the one entry that moves the pelvis.
	var made := EvadeKeyer.generate()
	for clip: String in made["files"]:
		var json := JSON.new()
		assert_eq(json.parse(made["files"][clip]), OK, "%s is JSON" % clip)
		var layer: Dictionary = json.data
		assert_true(layer.has("@pelvis_move"), "%s moves the pelvis" % clip)
		for bone: String in layer:
			for key: Array in layer[bone]:
				assert_eq(key.size(), 4, "%s %s: a key is [frame, x, y, z]" % [clip, bone])


func test_a_real_change_is_still_caught_and_a_rounding_step_is_not() -> void:
	var made: String = EvadeKeyer.generate(PackedStringArray(["sway_left_slip"]))["files"]["sway_left_slip"]
	assert_eq(EvadeKeyer.differences(made, made), PackedStringArray(), "the same text is the same")
	var layer: Dictionary = JSON.parse_string(made)
	# A last digit the other way: within a rounding step.
	var nudged: Dictionary = layer.duplicate(true)
	nudged["pelvis"][5][1] += EvadeKeyer.TURN_STEP
	nudged["@pelvis_move"][5][1] += EvadeKeyer.MOVE_STEP
	assert_eq(EvadeKeyer.differences(made, JSON.stringify(nudged)), PackedStringArray(), "a rounding step is not a difference")
	# A rotation moved by 0.01, the hips by 0.01 m.
	var moved: Dictionary = layer.duplicate(true)
	moved["spine_02"][8][2] += 0.01
	assert_eq(EvadeKeyer.differences(made, JSON.stringify(moved)).size(), 1, "a rotation moved by 0.01 is caught")
	moved = layer.duplicate(true)
	moved["@pelvis_move"][8][1] += 0.01
	assert_eq(EvadeKeyer.differences(made, JSON.stringify(moved)).size(), 1, "the hips moved by 0.01 are caught")
	# A frame less, a bone less.
	var short: Dictionary = layer.duplicate(true)
	short["pelvis"].pop_back()
	assert_eq(EvadeKeyer.differences(made, JSON.stringify(short)).size(), 1, "a missing frame is caught")
	var fewer: Dictionary = layer.duplicate(true)
	fewer.erase("spine_03")
	assert_eq(EvadeKeyer.differences(made, JSON.stringify(fewer)).size(), 1, "a missing bone is caught")
