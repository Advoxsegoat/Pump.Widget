extends TestCase
## The layer files of the four counters and clear-outs are what tools/anim/key_counters.gd makes of its table, within a rounding
## step (CounterKeyer.differences, also `key_counters.gd -- --check`), as the sways' are held to key_evades.gd: a table edited and not
## written, or a file edited by hand, fails here.

const CLIPS := ["counter_hook", "counter_rise", "clear_backpalm", "clear_wave"]


func test_the_committed_layers_are_what_the_table_makes() -> void:
	var made := CounterKeyer.generate()
	var files: Dictionary = made["files"]
	assert_eq(files.size(), 4, "a layer for each of the four clips")
	for clip: String in CLIPS:
		var path := "res://assets/anim/layers/%s.json" % clip
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		if files.has(clip) and FileAccess.file_exists(path):
			var found := CounterKeyer.differences(files[clip], FileAccess.get_file_as_string(path))
			assert_true(found.is_empty(), "%s is not what key_counters.gd makes of its table (run it to write them): %s" % [path, found])


func test_a_hand_edited_layer_is_caught_and_a_rounding_step_is_not() -> void:
	var made: String = CounterKeyer.generate(PackedStringArray(["counter_hook"]))["files"]["counter_hook"]
	assert_eq(CounterKeyer.differences(made, made), PackedStringArray(), "the same text is the same")
	var layer: Dictionary = JSON.parse_string(made)
	var nudged: Dictionary = layer.duplicate(true)
	nudged["spine_02"][5][1] += EvadeKeyer.TURN_STEP
	assert_eq(CounterKeyer.differences(made, JSON.stringify(nudged)), PackedStringArray(), "a rounding step is not a difference")
	var moved: Dictionary = layer.duplicate(true)
	moved["upperarm_r"][8][2] += 0.01
	assert_eq(CounterKeyer.differences(made, JSON.stringify(moved)).size(), 1, "an arm moved by 0.01 degrees is caught")
