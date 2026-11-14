extends TestCase
## The haymaker's layer file (assets/anim/layers/heavy_haymaker.json) is what tools/anim/key_haymaker.gd makes of its table, within a
## rounding step (HaymakerKeyer.differences, also `key_haymaker.gd -- --check`), as the counters' and the sways' are held to theirs: a
## table edited and not written, or a file edited by hand, fails here. And it is a layer that begins and ends in nothing, on the
## frames of the glint and the blow, with no step between one frame and the next that a joint could pop on.

const PATH := "res://assets/anim/layers/heavy_haymaker.json"
## The most any bone's layer turns (degrees, on any of its three Euler axes) from one frame to the next, and the most the hips'
## shift moves (metres): over the first and last frames, and anywhere in the layer.
const ENDS_STEP := 8.0
const ANY_STEP := 35.0
const SHIFT_STEP := 0.05


func _layer() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


func test_the_committed_layer_is_what_the_table_makes() -> void:
	assert_true(FileAccess.file_exists(PATH), "%s exists" % PATH)
	var made: String = HaymakerKeyer.generate()["text"]
	var found := HaymakerKeyer.differences(made, FileAccess.get_file_as_string(PATH))
	assert_true(found.is_empty(), "the layer is not what key_haymaker.gd makes of its table (run it to write it): %s" % [found])


func test_a_hand_edited_layer_is_caught_and_a_rounding_step_is_not() -> void:
	var made: String = HaymakerKeyer.generate()["text"]
	assert_eq(HaymakerKeyer.differences(made, made), PackedStringArray(), "the same text is the same")
	var layer: Dictionary = JSON.parse_string(made)
	var nudged: Dictionary = layer.duplicate(true)
	nudged["spine_02"][10][1] += EvadeKeyer.TURN_STEP
	assert_eq(HaymakerKeyer.differences(made, JSON.stringify(nudged)), PackedStringArray(), "a rounding step is not a difference")
	var moved: Dictionary = layer.duplicate(true)
	moved["spine_03"][10][2] += 0.01
	assert_eq(HaymakerKeyer.differences(made, JSON.stringify(moved)).size(), 1, "a spine turned by 0.01 degrees is caught")


func test_the_layer_is_nothing_at_the_glint_and_at_the_blow() -> void:
	var layer := _layer()
	assert_true(layer.has("spine_02") and layer.has("pelvis") and layer.has("@pelvis_move"), "it turns the spine and the pelvis and moves the hips")
	for bone: String in layer:
		var keys: Array = layer[bone]
		assert_eq(int(keys[0][0]), HaymakerKeyer.START, "%s: its first key is the glint's frame" % bone)
		assert_eq(int(keys[keys.size() - 1][0]), HaymakerKeyer.END, "%s: its last key is the blow's frame: nothing after it" % bone)
		for end: Array in [keys[0], keys[keys.size() - 1]]:
			assert_true(absf(end[1]) <= 0.002 and absf(end[2]) <= 0.002 and absf(end[3]) <= 0.002, "%s: nothing at frame %d (%s)" % [bone, end[0], end])


# The turn a layer key makes of a bone, as the rotation it is (Euler angles in degrees, YXZ, as the builder reads them).
static func _rotation(key: Array) -> Quaternion:
	return Basis.from_euler(Vector3(key[1], key[2], key[3]) * (PI / 180.0), EULER_ORDER_YXZ).get_rotation_quaternion()


func test_no_joint_steps_where_the_layer_begins_and_ends_nor_anywhere_in_it() -> void:
	# Measured as the turn between one frame's rotation and the next's (not as Euler numbers, which can change a lot for a small turn).
	var layer := _layer()
	for bone: String in layer:
		var keys: Array = layer[bone]
		for i in range(1, keys.size()):
			var frame := int(keys[i][0])
			var at_end := frame <= HaymakerKeyer.START + 1 or frame >= HaymakerKeyer.END
			if bone == "@pelvis_move":
				var worst := Vector3(keys[i][1] - keys[i - 1][1], keys[i][2] - keys[i - 1][2], keys[i][3] - keys[i - 1][3]).length()
				assert_true(worst <= SHIFT_STEP, "%s: moves %.3f m from f%d to f%d (at most %.3f)" % [bone, worst, frame - 1, frame, SHIFT_STEP])
				continue
			var turn := rad_to_deg(_rotation(keys[i - 1]).angle_to(_rotation(keys[i])))
			var limit := ENDS_STEP if at_end else ANY_STEP
			assert_true(turn <= limit, "%s: turns %.1f degrees from f%d to f%d (at most %.0f)" % [bone, turn, frame - 1, frame, limit])
