extends TestCase
## The layer files of the sway, duck and dash-step clips are what tools/anim/key_evades.gd makes of its table, byte for byte
## (the same check as `key_evades.gd -- --check`): a table edited and not written, or a file edited by hand, fails here.

func test_the_committed_layers_are_what_the_table_makes() -> void:
	var made := EvadeKeyer.generate()
	var files: Dictionary = made["files"]
	assert_eq(files.size(), 16, "a layer for each of the sixteen clips")
	for clip: String in files:
		var path := "res://assets/anim/layers/%s.json" % clip
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		if FileAccess.file_exists(path):
			assert_true(FileAccess.get_file_as_string(path) == files[clip], "%s is not what key_evades.gd makes of its table (run it to write them)" % path)


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
