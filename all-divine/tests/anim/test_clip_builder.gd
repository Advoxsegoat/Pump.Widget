extends TestCase
## ClipBuilder: the pieces that turn the Quaternius clips into Abarax's clips (tools/anim/clip_builder.gd).
## The first group works on animations built in memory, the second on tiny glTF files written to
## user://, so none of it needs the Quaternius pack. The committed clips are checked by test_library.gd.

const MODEL := "res://assets/characters/abarax/abarax.glb"
const SKEL := NodePath("Armature/Skeleton3D")
const BONES: PackedStringArray = ["root", "pelvis", "hand_l"]
const DIR := "user://clip_builder_fixture"
# Tracks as the builder writes them, under Model.
const ROOT_PATH := NodePath("Model/Armature/Skeleton3D:root")
const PELVIS_PATH := NodePath("Model/Armature/Skeleton3D:pelvis")
const HAND_PATH := NodePath("Model/Armature/Skeleton3D:hand_l")

# The hip height of the mannequin the fixture clips were authored on.
const SOURCE_HIP := 0.9
# A mannequin skeleton: three of Abarax's bones and one he does not have.
const JOINTS: Array = [["root", -1], ["pelvis", 0, Vector3(0.0, SOURCE_HIP, 0.0)], ["hand_l", 1], ["mannequin_extra", 1]]


func after_each() -> void:
	GltfFixture.wipe(DIR)


# --- retime ---

func test_retime_scales_key_times() -> void:
	var a := Animation.new()
	a.length = 1.0
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, "Armature/Skeleton3D:pelvis")
	a.position_track_insert_key(t, 0.0, Vector3.ZERO)
	a.position_track_insert_key(t, 0.5, Vector3.RIGHT)
	a.position_track_insert_key(t, 1.0, Vector3.UP)
	var shorter := ClipBuilder.retime(a, 0.5)
	assert_near(shorter.length, 0.5, 1e-6)
	assert_near(shorter.track_get_key_time(t, 0), 0.0, 1e-6)
	assert_near(shorter.track_get_key_time(t, 1), 0.25, 1e-6)
	assert_near(shorter.track_get_key_time(t, 2), 0.5, 1e-6)
	assert_eq(shorter.track_get_key_value(t, 1), Vector3.RIGHT, "values are untouched")
	assert_near(a.length, 1.0, 1e-6, "the input is left alone")
	assert_near(a.track_get_key_time(t, 1), 0.5, 1e-6, "the input is left alone")


func test_retime_can_stretch_and_scales_every_kind_of_track() -> void:
	var a := Animation.new()
	a.length = 1.0
	a.loop_mode = Animation.LOOP_LINEAR
	var r := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(r, "Armature/Skeleton3D:pelvis")
	a.rotation_track_insert_key(r, 0.0, Quaternion.IDENTITY)
	a.rotation_track_insert_key(r, 0.25, Quaternion(Vector3.UP, 1.0))
	var m := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(m, "Marks")
	a.track_insert_key(m, 0.1, {"method": "sfx", "args": []})
	var longer := ClipBuilder.retime(a, 2.0)
	assert_near(longer.length, 2.0, 1e-6)
	assert_near(longer.track_get_key_time(r, 1), 0.5, 1e-6)
	assert_near(longer.track_get_key_time(m, 0), 0.2, 1e-6, "method keys scale too")
	assert_eq(longer.loop_mode, Animation.LOOP_LINEAR)
	assert_eq(longer.track_get_path(m), NodePath("Marks"))


# --- rewrite_paths ---

func test_rewrite_paths_prefixes_model_and_the_skeleton_path() -> void:
	var a := _anim()
	_rotation(a, "pelvis")
	var out := ClipBuilder.rewrite_paths(a, SKEL, BONES)
	assert_eq(out.get_track_count(), 1)
	assert_eq(out.track_get_type(0), Animation.TYPE_ROTATION_3D)
	assert_eq(out.track_get_path(0), NodePath("Model/Armature/Skeleton3D:pelvis"))
	assert_eq(out.track_get_key_count(0), 2)
	assert_eq(out.track_get_key_value(0, 1), Quaternion(Vector3.UP, 1.0))


func test_rewrite_paths_drops_unknown_bones() -> void:
	var a := _anim()
	_rotation(a, "pelvis")
	_rotation(a, "mannequin_extra")
	_position(a, "mannequin_extra")
	var out := ClipBuilder.rewrite_paths(a, SKEL, BONES)
	assert_eq(_paths(out), PackedStringArray(["Model/Armature/Skeleton3D:pelvis"]))


func test_rewrite_paths_keeps_every_rotation_but_positions_only_for_root_and_pelvis() -> void:
	# Ruling R4: the clips were authored on another mannequin, whose bone lengths a position track
	# would impose on Abarax.
	var a := _anim()
	for bone in BONES:
		_rotation(a, bone)
		_position(a, bone)
	var out := ClipBuilder.rewrite_paths(a, SKEL, BONES)
	var rotations := PackedStringArray()
	var positions := PackedStringArray()
	for i in out.get_track_count():
		var bone := str(out.track_get_path(i).get_concatenated_subnames())
		if out.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			rotations.append(bone)
		elif out.track_get_type(i) == Animation.TYPE_POSITION_3D:
			positions.append(bone)
	rotations.sort()
	positions.sort()
	assert_eq(rotations, PackedStringArray(["hand_l", "pelvis", "root"]))
	assert_eq(positions, PackedStringArray(["pelvis", "root"]), "hand_l loses its position track, pelvis keeps its")


func test_rewrite_paths_drops_scale_tracks_that_stay_at_identity() -> void:
	var a := _anim()
	var flat := a.add_track(Animation.TYPE_SCALE_3D)
	a.track_set_path(flat, "Armature/Skeleton3D:pelvis")
	a.scale_track_insert_key(flat, 0.0, Vector3.ONE)
	a.scale_track_insert_key(flat, 1.0, Vector3.ONE + Vector3(5e-5, -5e-5, 0.0))  # within 1e-4
	var squash := a.add_track(Animation.TYPE_SCALE_3D)
	a.track_set_path(squash, "Armature/Skeleton3D:hand_l")
	a.scale_track_insert_key(squash, 0.0, Vector3.ONE)
	a.scale_track_insert_key(squash, 1.0, Vector3(1.0, 1.5, 1.0))
	var out := ClipBuilder.rewrite_paths(a, SKEL, BONES)
	assert_eq(_paths(out), PackedStringArray(["Model/Armature/Skeleton3D:hand_l"]))
	assert_eq(out.track_get_type(0), Animation.TYPE_SCALE_3D)


func test_rewrite_paths_drops_tracks_that_are_not_bone_tracks() -> void:
	var a := _anim()
	_rotation(a, "pelvis")
	var other := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(other, "Armature/Skeleton3D:motion_scale")  # a bone name does not make it a bone track
	a.track_insert_key(other, 0.0, 1.0)
	var method := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(method, "Marks")
	a.track_insert_key(method, 0.1, {"method": "sfx", "args": []})
	var out := ClipBuilder.rewrite_paths(a, SKEL, BONES)
	assert_eq(_paths(out), PackedStringArray(["Model/Armature/Skeleton3D:pelvis"]))


func test_rewrite_paths_copies_the_clip_and_leaves_the_input_alone() -> void:
	var a := _anim()
	a.length = 1.25
	a.loop_mode = Animation.LOOP_LINEAR
	var t := _rotation(a, "pelvis")
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_NEAREST)
	var before := a.track_get_path(t)
	var out := ClipBuilder.rewrite_paths(a, SKEL, BONES)
	assert_near(out.length, 1.25, 1e-6)
	assert_eq(out.loop_mode, Animation.LOOP_LINEAR)
	assert_eq(out.track_get_interpolation_type(0), Animation.INTERPOLATION_NEAREST)
	assert_eq(a.track_get_path(t), before, "the input keeps its paths")
	assert_eq(a.get_track_count(), 1)


func test_rewrite_paths_scales_root_and_pelvis_positions_by_the_hip_ratio() -> void:
	# Ruling R5: a mannequin hip at 0.9 m moved onto a skeleton whose hip is at 1.0 m.
	var a := _anim()
	for bone in ["root", "pelvis"]:
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, "Armature/Skeleton3D:" + bone)
		a.position_track_insert_key(t, 0.0, Vector3(0.0, 0.9, 0.0))
		a.position_track_insert_key(t, 1.0, Vector3(0.45, 0.9, 1.8))
	_rotation(a, "pelvis")
	var out := ClipBuilder.rewrite_paths(a, SKEL, BONES, 1.0 / SOURCE_HIP)
	for bone in ["root", "pelvis"]:
		var t := out.find_track(NodePath("Model/Armature/Skeleton3D:" + bone), Animation.TYPE_POSITION_3D)
		assert_true(t >= 0, bone)
		assert_vec_near(out.track_get_key_value(t, 0), Vector3(0.0, 1.0, 0.0), 1e-5)
		assert_vec_near(out.track_get_key_value(t, 1), Vector3(0.5, 1.0, 2.0), 1e-5)
	var r := out.find_track(NodePath("Model/Armature/Skeleton3D:pelvis"), Animation.TYPE_ROTATION_3D)
	assert_eq(out.track_get_key_value(r, 1), Quaternion(Vector3.UP, 1.0), "rotations are not scaled")
	assert_vec_near(a.track_get_key_value(0, 1), Vector3(0.45, 0.9, 1.8), 1e-6)  # the input is left alone
	var plain := ClipBuilder.rewrite_paths(a, SKEL, BONES)
	assert_vec_near(plain.track_get_key_value(0, 1), Vector3(0.45, 0.9, 1.8), 1e-6)  # the ratio defaults to 1


# --- hip_height ---

func test_hip_height_is_the_rest_height_of_the_pelvis() -> void:
	var model := track((load(MODEL) as PackedScene).instantiate()) as Node
	var skeleton := model.get_node(ClipBuilder.skeleton_path(load(MODEL))) as Skeleton3D
	assert_near(ClipBuilder.hip_height(skeleton), 0.9491, 0.001, "Abarax")
	var pack := ClipBuilder.load_gltf(_write_gltf("hip.gltf", {"Idle": [_channel("hand_l", "rotation", [0.0, 1.0], [Quaternion.IDENTITY, Quaternion.IDENTITY])]}))
	assert_near(pack["hip_height"], SOURCE_HIP, 1e-4, "read from a glTF skeleton")
	var bare := Skeleton3D.new()
	bare.add_bone("root")
	assert_eq(ClipBuilder.hip_height(bare), 0.0, "no pelvis")
	bare.free()


# --- ground_speed ---

func test_ground_speed_is_the_horizontal_displacement_of_root_over_the_length() -> void:
	var a := _anim()
	a.length = 2.0
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, "Model/Armature/Skeleton3D:root")
	a.position_track_insert_key(t, 0.0, Vector3(1.0, 0.0, 1.0))
	a.position_track_insert_key(t, 1.0, Vector3(2.0, 4.0, 3.0))
	a.position_track_insert_key(t, 2.0, Vector3(4.0, 9.0, 5.0))  # (3, 4) across the ground: 5 m in 2 s
	assert_near(ClipBuilder.ground_speed(a, SKEL), 2.5, 1e-6, "height does not count")


func test_ground_speed_reads_a_clip_that_has_not_been_rewritten_too() -> void:
	var a := _anim()
	a.length = 1.0
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, "Armature/Skeleton3D:root")
	a.position_track_insert_key(t, 0.0, Vector3.ZERO)
	a.position_track_insert_key(t, 1.0, Vector3(0.0, 0.0, 3.0))
	assert_near(ClipBuilder.ground_speed(a, SKEL), 3.0, 1e-6)


func test_ground_speed_is_zero_when_root_does_not_move() -> void:
	var a := _anim()
	_position(a, "pelvis")  # the pelvis moves, but it is not the root bone
	assert_eq(ClipBuilder.ground_speed(a, SKEL), 0.0)
	var b := _anim()
	var t := b.add_track(Animation.TYPE_POSITION_3D)
	b.track_set_path(t, "Armature/Skeleton3D:root")
	b.position_track_insert_key(t, 0.0, Vector3(1.0, 2.0, 3.0))
	b.position_track_insert_key(t, 1.0, Vector3(1.0, 5.0, 3.0))  # only up
	assert_near(ClipBuilder.ground_speed(b, SKEL), 0.0, 1e-6)


# --- merge_kept_tracks ---

func test_merge_keeps_marks_track() -> void:
	var old := Animation.new()
	var t := old.add_track(Animation.TYPE_METHOD)
	old.track_set_path(t, "Marks")
	old.track_insert_key(t, 0.1, {"method": "sfx", "args": [{"name": "x"}]})
	var fresh := Animation.new()
	ClipBuilder.merge_kept_tracks(fresh, old)
	assert_eq(fresh.track_get_path(0), NodePath("Marks"))
	assert_eq(fresh.track_get_key_count(0), 1)
	assert_eq(fresh.track_get_type(0), Animation.TYPE_METHOD)
	assert_near(fresh.track_get_key_time(0, 0), 0.1, 1e-6)
	var call: Dictionary = fresh.track_get_key_value(0, 0)
	assert_eq(str(call["method"]), "sfx")  # the animation stores the method name as a StringName
	assert_eq(call["args"], [{"name": "x"}])


func test_merge_copies_non_bone_tracks_marks_first_and_never_bone_tracks() -> void:
	var old := _anim()
	_rotation(old, "pelvis")
	var sound := old.add_track(Animation.TYPE_VALUE)
	old.track_set_path(sound, "Hand:visible")
	old.track_insert_key(sound, 0.2, true)
	_position(old, "root")
	var marks := old.add_track(Animation.TYPE_METHOD)
	old.track_set_path(marks, "Marks")
	old.track_insert_key(marks, 0.3, {"method": "hit", "args": []})
	var fresh := _anim()
	_rotation(fresh, "hand_l")
	ClipBuilder.merge_kept_tracks(fresh, old)
	assert_eq(fresh.get_track_count(), 3, "the fresh bone track, then the kept Marks and Hand:visible")
	assert_eq(fresh.track_get_path(0), NodePath("Armature/Skeleton3D:hand_l"), "the fresh bone track stays")
	assert_eq(fresh.track_get_path(1), NodePath("Marks"))
	assert_eq(fresh.track_get_path(2), NodePath("Hand:visible"))
	assert_eq(fresh.track_get_key_value(2, 0), true)


# --- time warps ---

func test_warp_time_is_piecewise_linear() -> void:
	assert_near(ClipBuilder.warp_time(PackedFloat32Array([0, 0, 1, 2]), 0.5), 1.0, 1e-6)
	var bent := PackedFloat32Array([0, 0, 1, 2, 3, 3])
	assert_near(ClipBuilder.warp_time(bent, 0.0), 0.0, 1e-6, "the first point")
	assert_near(ClipBuilder.warp_time(bent, 1.0), 2.0, 1e-6, "a corner")
	assert_near(ClipBuilder.warp_time(bent, 2.0), 2.5, 1e-6, "halfway along the slower second segment")
	assert_near(ClipBuilder.warp_time(bent, 3.0), 3.0, 1e-6, "the last point")
	assert_near(ClipBuilder.warp_time(bent, 9.0), 3.0, 1e-6, "past the end it stays at the last source time")
	assert_near(ClipBuilder.warp_time(bent, -1.0), 0.0, 1e-6, "before the start it stays at the first")
	assert_near(ClipBuilder.warp_time(PackedFloat32Array([0, 0, 0.1, 0.1, 0.3, 0.1]), 0.2), 0.1, 1e-6, "a hold")
	assert_near(ClipBuilder.warp_time(PackedFloat32Array([0, 0, 0.2, 0.2, 0.4, 0.0]), 0.3), 0.1, 1e-6, "a reverse")
	assert_eq(ClipBuilder.warp_time(PackedFloat32Array(), 0.3), 0.0, "no warp, no map")


func test_warp_hold_keeps_the_pose() -> void:
	var source := _moving(0.5)
	var out := ClipBuilder.apply_warp(source, PackedFloat32Array([0, 0, 0.1, 0.1, 0.3, 0.1]))
	assert_near(out.length, 0.3, 1e-6, "the clip is as long as the last output time")
	_assert_same_pose(out, 0.2, source, 0.1, 1e-4, "held")
	_assert_same_pose(out, 0.3, source, 0.1, 1e-4, "still held at the end")
	_assert_same_pose(out, 0.05, source, 0.05, 1e-4, "before the hold the clip plays at its own speed")


func test_warp_can_play_backward() -> void:
	var source := _moving(0.5)
	var out := ClipBuilder.apply_warp(source, PackedFloat32Array([0, 0, 0.2, 0.2, 0.4, 0.0]))
	assert_near(out.length, 0.4, 1e-6)
	_assert_same_pose(out, 0.3, source, 0.1, 1e-4, "backward")
	_assert_same_pose(out, 0.2, source, 0.2, 1e-4, "where it turns")
	_assert_same_pose(out, 0.4, source, 0.0, 1e-4, "back at the start")


func test_warp_resamples_every_track_at_60_hz() -> void:
	var source := _moving(1.0)  # keys every 1/30 s
	var out := ClipBuilder.apply_warp(source, PackedFloat32Array([0, 0, 0.5, 1.0]))  # twice as fast
	assert_eq(out.get_track_count(), source.get_track_count())
	for i in out.get_track_count():
		var name := str(out.track_get_path(i))
		assert_eq(out.track_get_key_count(i), 31, name)
		assert_near(out.track_get_key_time(i, 1), 1.0 / 60.0, 1e-6, name)
		assert_near(out.track_get_key_time(i, 30), 0.5, 1e-6, name)
	_assert_same_pose(out, 0.25, source, 0.5, 1e-4, "twice as fast")


func test_warp_ends_with_a_key_at_the_length_even_between_frames() -> void:
	var source := _moving(1.0)
	var out := ClipBuilder.apply_warp(source, PackedFloat32Array([0, 0, 0.26, 0.52]))
	assert_near(out.length, 0.26, 1e-6)
	for i in out.get_track_count():
		var last := out.track_get_key_count(i) - 1
		assert_eq(last, 16, "keys at 0 to 15/60 and one at the length")
		assert_near(out.track_get_key_time(i, last), 0.26, 1e-6)
	_assert_same_pose(out, 0.26, source, 0.52, 1e-4, "the last pose")


func test_warp_leaves_the_input_alone_and_keeps_track_settings() -> void:
	var source := _moving(0.5)
	source.track_set_interpolation_type(0, Animation.INTERPOLATION_NEAREST)
	var keys := source.track_get_key_count(0)
	var out := ClipBuilder.apply_warp(source, PackedFloat32Array([0, 0, 0.25, 0.5]))
	assert_eq(source.track_get_key_count(0), keys, "the input keeps its keys")
	assert_near(source.length, 0.5, 1e-6)
	assert_eq(out.track_get_path(0), source.track_get_path(0))
	assert_eq(out.track_get_interpolation_type(0), Animation.INTERPOLATION_NEAREST)


# --- joins ---

func test_join_continues_root_motion_without_a_jump() -> void:
	var a := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var b := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var joined := ClipBuilder.join([a, b])
	var root := joined.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_near(joined.length, 2.0, 1e-6, "the lengths add up")
	assert_vec_near(joined.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, 1.0), 1e-5, "at A's end")
	assert_vec_near(joined.position_track_interpolate(root, 2.0), Vector3(0.0, 0.0, 2.0), 1e-5, "at the end")
	assert_vec_near(joined.position_track_interpolate(root, 1.5), Vector3(0.0, 0.0, 1.5), 1e-5, "B's travel goes on from there")
	var step := joined.position_track_interpolate(root, 1.0 + 1.0 / 30.0) - joined.position_track_interpolate(root, 1.0 - 1.0 / 30.0)
	assert_vec_near(step, Vector3(0.0, 0.0, 2.0 / 30.0), 1e-5, "two frames across the join move two frames' worth")


func test_join_keeps_the_travel_of_a_clip_that_starts_away_from_zero() -> void:
	# A slide ends 4 m along; the clip after it starts its root at the origin again.
	var slide := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 4.0))
	var exit := _moving(0.5, Vector3(0.3, 0.0, 0.2), Vector3(0.3, 0.0, 0.7))
	var third := _moving(1.0, Vector3.ZERO, Vector3(1.0, 0.0, 0.0))
	var joined := ClipBuilder.join([slide, exit, third])
	var root := joined.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_near(joined.length, 2.5, 1e-6)
	assert_vec_near(joined.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, 4.0), 1e-5, "the exit starts where the slide stopped")
	assert_vec_near(joined.position_track_interpolate(root, 1.5), Vector3(0.0, 0.0, 4.5), 1e-5, "and keeps its own half metre")
	assert_vec_near(joined.position_track_interpolate(root, 2.5), Vector3(1.0, 0.0, 4.5), 1e-5, "a third clip carries on from the second")


func test_join_plays_each_clip_as_it_was_one_after_another() -> void:
	var a := _moving(1.0)
	var b := _moving(0.5)
	var joined := ClipBuilder.join([a, b])
	assert_eq(joined.get_track_count(), a.get_track_count(), "one track for each bone track, not two")
	for i in a.get_track_count():
		var path := a.track_get_path(i)
		var type := a.track_get_type(i)
		var j := joined.find_track(path, type)
		var k := b.find_track(path, type)
		assert_true(j >= 0 and k >= 0, "%s is in the join and in B" % path)
		for t in [0.0, 0.3, 0.9]:
			assert_true(_values_near(_value(joined, j, t), _value(a, i, t), 1e-5), "A at %s, %s" % [t, path])
		for t in [0.1, 0.3, 0.5]:
			assert_true(_values_near(_value(joined, j, 1.0 + t), _value(b, k, t), 1e-5), "B at %s, %s: starts when A ends" % [t, path])


func test_join_holds_the_root_through_a_clip_that_has_none() -> void:
	var a := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var b := _moving(0.5)
	b.remove_track(b.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D))
	var c := _moving(0.5, Vector3(5.0, 0.0, 5.0), Vector3(5.0, 0.0, 5.5))
	var joined := ClipBuilder.join([a, b, c])
	var root := joined.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_vec_near(joined.position_track_interpolate(root, 1.25), Vector3(0.0, 0.0, 1.0), 1e-5, "it stays where A stopped while B plays")
	assert_vec_near(joined.position_track_interpolate(root, 1.5), Vector3(0.0, 0.0, 1.0), 1e-5, "and C starts from there")
	assert_vec_near(joined.position_track_interpolate(root, 2.0), Vector3(0.0, 0.0, 1.5), 1e-5)


func test_join_of_one_clip_is_that_clip() -> void:
	var a := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var joined := ClipBuilder.join([a])
	assert_near(joined.length, 1.0, 1e-6)
	_assert_same_pose(joined, 0.4, a, 0.4, 1e-6, "alone")


func test_join_parts_crossfades_each_clip_into_the_next() -> void:
	# A, then B fading in over A's last quarter second: 1.75 s in all, A alone, then both blended (smoothstep), then B.
	var a := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var b := _moving(1.0, Vector3(5.0, 0.0, 5.0), Vector3(5.0, 0.0, 6.0))
	var joined := ClipBuilder.join_parts([{"anim": a}, {"anim": b, "fade": 0.25}])
	assert_near(joined.length, 1.75, 1e-6, "the overlap is played once")
	var hand := joined.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D)
	var root := joined.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	_assert_quat_near(joined.rotation_track_interpolate(hand, 0.5), _hand(a, 30), 1e-4, "A alone before the fade")
	_assert_quat_near(joined.rotation_track_interpolate(hand, 1.5), _hand(b, 45), 1e-4, "B alone after it")
	# Frame 54 (0.9 s) is 0.15 s into the fade: A at 0.9 s, B at 0.15 s, weighed by smoothstep(0.6).
	var a_mid := a.rotation_track_interpolate(a.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D), 0.9)
	var b_mid := b.rotation_track_interpolate(b.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D), 0.15)
	_assert_quat_near(joined.rotation_track_interpolate(hand, 0.9), a_mid.slerp(b_mid, smoothstep(0.0, 1.0, 0.6)), 1e-4,
			"a blend in the middle")
	assert_vec_near(joined.position_track_interpolate(root, 0.75), Vector3(0.0, 0.0, 0.75), 1e-4, "the root goes on from A")
	assert_vec_near(joined.position_track_interpolate(root, 1.75), Vector3(0.0, 0.0, 1.75), 1e-4, "and carries B's own travel on from there")
	var worst := 0.0
	for f in 105:
		var step := joined.position_track_interpolate(root, (f + 1) / 60.0) - joined.position_track_interpolate(root, f / 60.0)
		worst = maxf(worst, step.length())
	assert_true(worst < 1.5 / 60.0, "no jump in the root anywhere (%.4f m in a frame at most)" % worst)


func test_join_parts_plays_only_the_span_of_each_clip_it_is_given() -> void:
	# A from 0.25 to 0.75 s, then B from 0.5 s on: 1 s in all, each the piece it was cut to, the root unbroken.
	var a := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var b := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 2.0))
	var joined := ClipBuilder.join_parts([{"anim": a, "from": 0.25, "to": 0.75}, {"anim": b, "from": 0.5}])
	assert_near(joined.length, 1.0, 1e-6)
	_assert_same_pose(_without_root(a), 0.35, joined, 0.1, 1e-3, "A's piece")
	_assert_same_pose(_without_root(b), 0.8, joined, 0.8, 1e-3, "B's piece")
	var root := joined.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_vec_near(joined.position_track_interpolate(root, 0.0), Vector3.ZERO, 1e-4, "the root starts at 0")
	assert_vec_near(joined.position_track_interpolate(root, 0.5), Vector3(0.0, 0.0, 0.5), 1e-4, "where A's piece ends")
	assert_vec_near(joined.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, 1.5), 1e-4, "and B's half has its own metre")


func test_join_parts_can_keep_the_travel_of_the_span_it_cuts_away() -> void:
	# B cut from 0.5 s, its root lined up at 0 s: its root starts half a metre past A's end (B travels 1 m a second), as
	# if the cut half had played; with a fade, the root blends there from A's, without a jump.
	var a := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var b := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var kept := ClipBuilder.join_parts([{"anim": a}, {"anim": b, "from": 0.5, "root_from": 0.0}])
	var root := kept.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_vec_near(kept.position_track_interpolate(root, 1.0 + 1.0 / 60.0), Vector3(0.0, 0.0, 1.5 + 1.0 / 60.0), 1e-3, "past the cut travel")
	var faded := ClipBuilder.join_parts([{"anim": a}, {"anim": b, "from": 0.5, "root_from": 0.0, "fade": 0.25}])
	root = faded.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_vec_near(faded.position_track_interpolate(root, 0.75), Vector3(0.0, 0.0, 0.75), 1e-3, "A's root where the fade starts")
	assert_vec_near(faded.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, 0.75 + 0.5 + 0.25), 1e-3, "B's, cut travel and all, where it ends")


func test_join_parts_holds_the_root_through_a_part_that_has_none() -> void:
	# A part with no root track (a clip that does not travel) stays where the root was left, before and after, even when
	# the part after it keeps the travel it cuts away.
	var a := _moving(1.0)
	a.remove_track(a.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D))
	var b := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var joined := ClipBuilder.join_parts([{"anim": a}, {"anim": b, "from": 0.5, "root_from": 0.0, "fade": 0.25}])
	var root := joined.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_vec_near(joined.position_track_interpolate(root, 0.5), Vector3.ZERO, 1e-4, "A does not travel")
	assert_vec_near(joined.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, 0.75), 1e-3, "B carries on from where A left the root")
	# B travelling, then A fading in over B's last quarter: the root slows to a stop where B ends, never drawing back.
	var stop := ClipBuilder.join_parts([{"anim": b}, {"anim": a, "fade": 0.25}])
	root = stop.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	var last := -INF
	for f in 106:
		var z := stop.position_track_interpolate(root, f / 60.0).z
		assert_true(z >= last - 1e-5, "the root goes on forward (frame %d: %.4f after %.4f)" % [f, z, last])
		last = z
	assert_vec_near(stop.position_track_interpolate(root, stop.length), Vector3(0.0, 0.0, 1.0), 1e-3, "and stops where B ends")


func test_join_parts_with_nothing_cut_or_faded_is_the_plain_join() -> void:
	var a := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	var b := _moving(0.5, Vector3(5.0, 0.0, 5.0), Vector3(5.0, 0.0, 5.5))
	var plain := ClipBuilder.join([a, b])
	var parts := ClipBuilder.join_parts([{"anim": a}, {"anim": b}])
	assert_eq(var_to_str(parts), var_to_str(plain), "the same clip, key for key")


func test_build_reads_then_entries_that_cut_and_fade() -> void:
	# Run (1 s) then Roll from 0.5 s (1.5 s left), fading in over 0.25 s: 2.25 s.
	var run := _build_setup()
	_write_text(run["cfg"], "[cut]\nsource=\"pack_rm\"\nclip=\"Run\"\nthen=[{\"clip\": \"Roll\", \"from\": 0.5, \"fade\": 0.25}]\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	assert_near((_load(run["out"] + "/cut.tres") as Animation).length, 2.25, 1e-3)


func test_then_entries_that_cut_or_fade_wrongly_are_problems() -> void:
	var run := _build_setup()
	var bad := {
		"{\"clip\": \"Roll\", \"fade\": -0.1}": "fade",
		"{\"clip\": \"Roll\", \"from\": 1.0, \"to\": 0.5}": "from",
		"{\"clip\": \"Roll\", \"speed\": 2}": "speed",
		"{\"from\": 0.5}": "clip",
		"{\"clip\": \"Roll\", \"fade\": 5.0}": "fade",
	}
	for entry: String in bad:
		_write_text(run["cfg"], "[cut]\nsource=\"pack_rm\"\nclip=\"Run\"\nthen=[%s]\n" % entry)
		var problems := ClipBuilder.check(run["cfg"], run["sources"], MODEL)
		assert_true(Array(problems).any(func(p: String) -> bool: return p.begins_with("[cut]") and p.contains(bad[entry])),
				"%s: %s" % [entry, "\n".join(problems)])


# --- layers ---

func test_layer_adds_its_rotation_between_keys_only() -> void:
	var clip := _moving(1.0)
	var out := ClipBuilder.apply_layer(clip, {"hand_l": [[10, 0, 0, 0], [20, 0, 30, 0], [30, 0, 0, 0]]})
	_assert_quat_near(_hand(out, 20), _hand(clip, 20) * _about(Vector3.UP, 30.0), 1e-4, "f20: the clip's rotation times 30 degrees about local Y")
	_assert_quat_near(_hand(out, 15), _hand(clip, 15) * _about(Vector3.UP, 15.0), 1e-4, "f15: halfway up")
	_assert_quat_near(_hand(out, 25), _hand(clip, 25) * _about(Vector3.UP, 15.0), 1e-4, "f25: halfway down")
	for frame in [0, 5, 9, 31, 35, 59]:
		_assert_quat_near(_hand(out, frame), _hand(clip, frame), 1e-4, "f%d: no layer there, so the clip's own" % frame)
	assert_eq(out.get_track_count(), clip.get_track_count())
	assert_near(out.length, clip.length, 1e-6)


func test_layer_is_zero_outside_its_keys_even_when_the_end_keys_are_not() -> void:
	# The first and last keys are turned out, so a layer that held them would show.
	var clip := _moving(1.0)
	var out := ClipBuilder.apply_layer(clip, {"hand_l": [[10, 0, 20, 0], [20, 0, 40, 0]]})
	for frame in [0, 5, 9]:
		_assert_quat_near(_hand(out, frame), _hand(clip, frame), 1e-4, "f%d is before the first key" % frame)
	for frame in [21, 30, 60]:
		_assert_quat_near(_hand(out, frame), _hand(clip, frame), 1e-4, "f%d is after the last key" % frame)
	for pair in [[10, 20.0], [15, 30.0], [20, 40.0]]:
		_assert_quat_near(_hand(out, pair[0]), _hand(clip, pair[0]) * _about(Vector3.UP, pair[1]), 1e-4, "f%d is on the layer" % pair[0])


func test_layer_leaves_other_bones_alone_and_the_input_unchanged() -> void:
	var clip := _moving(1.0)
	var hand_keys := clip.track_get_key_count(clip.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D))
	var out := ClipBuilder.apply_layer(clip, {"hand_l": [[0, 90, 0, 0], [60, 90, 0, 0]]})
	var before := clip.find_track(PELVIS_PATH, Animation.TYPE_ROTATION_3D)
	var after := out.find_track(PELVIS_PATH, Animation.TYPE_ROTATION_3D)
	assert_eq(out.track_get_key_count(after), clip.track_get_key_count(before), "the pelvis is copied as it was")
	for t in [0.0, 0.4, 1.0]:
		_assert_quat_near(out.rotation_track_interpolate(after, t), clip.rotation_track_interpolate(before, t), 1e-6, "pelvis at %s" % t)
	assert_eq(clip.track_get_key_count(clip.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D)), hand_keys, "the input keeps its keys")


func test_layer_is_euler_degrees_in_yxz_order_x_first_and_post_multiplies() -> void:
	var clip := _moving(1.0)
	var base := _hand(clip, 30)
	_assert_quat_near(_hand(ClipBuilder.apply_layer(clip, {"hand_l": [[30, 30, 0, 0]]}), 30), base * _about(Vector3.RIGHT, 30.0), 1e-4, "the first number is about X")
	_assert_quat_near(_hand(ClipBuilder.apply_layer(clip, {"hand_l": [[30, 0, 0, 30]]}), 30), base * _about(Vector3.BACK, 30.0), 1e-4, "the third is about Z")
	var angles := Vector3(deg_to_rad(10.0), deg_to_rad(20.0), deg_to_rad(30.0))
	var yxz := Basis.from_euler(angles, EULER_ORDER_YXZ).get_rotation_quaternion()
	var xyz := Basis.from_euler(angles, EULER_ORDER_XYZ).get_rotation_quaternion()
	var got := _hand(ClipBuilder.apply_layer(clip, {"hand_l": [[30, 10, 20, 30]]}), 30)
	_assert_quat_near(got, base * yxz, 1e-4, "YXZ order, laid after the clip's own rotation")
	assert_true(_quat_distance(got, base * xyz) > 1e-3, "a different Euler order would give a different pose")
	assert_true(_quat_distance(got, yxz * base) > 1e-3, "and so would laying it before the clip's rotation")


func test_layer_with_no_keys_in_range_changes_nothing() -> void:
	var clip := _moving(0.5)  # 30 frames long
	var out := ClipBuilder.apply_layer(clip, {"hand_l": [[300, 45, 0, 0], [330, 0, 0, 0]]})
	_assert_same_pose(out, 0.3, clip, 0.3, 1e-4, "untouched")


func test_layer_moves_the_pelvis_in_the_bodys_own_directions_between_keys_only() -> void:
	# The pelvis's track is in the root's frame, which stands the skeleton up: its y is the body's z (negated), its z up.
	var clip := _moving(1.0)
	var out := ClipBuilder.apply_layer(clip, {"@pelvis_move": [[10, 0, 0, 0], [20, 0.1, -0.2, 0.3], [30, 0, 0, 0]]})
	var was := clip.find_track(PELVIS_PATH, Animation.TYPE_POSITION_3D)
	var now := out.find_track(PELVIS_PATH, Animation.TYPE_POSITION_3D)
	var sway := Vector3(0.1, -0.3, -0.2)  # (left 0.1, up -0.2, ahead 0.3) as the track holds it: (x, -ahead, up)
	assert_vec_near(out.position_track_interpolate(now, _at(20)), clip.position_track_interpolate(was, _at(20)) + sway, 1e-5, "f20: the whole shift")
	assert_vec_near(out.position_track_interpolate(now, _at(15)), clip.position_track_interpolate(was, _at(15)) + sway * 0.5, 1e-5, "f15: half of it")
	for frame in [0, 9, 31, 59]:
		assert_vec_near(out.position_track_interpolate(now, _at(frame)), clip.position_track_interpolate(was, _at(frame)), 1e-5, "f%d is outside its keys" % frame)
	var root := out.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_eq(out.track_get_key_count(root), clip.track_get_key_count(clip.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)), "the root is copied")


func test_a_layer_may_move_the_pelvis_and_turn_bones_together() -> void:
	var clip := _moving(1.0)
	var out := ClipBuilder.apply_layer(clip, {"@pelvis_move": [[0, 0.1, 0, 0], [30, 0.1, 0, 0]], "hand_l": [[30, 0, 30, 0]]})
	_assert_quat_near(_hand(out, 30), _hand(clip, 30) * _about(Vector3.UP, 30.0), 1e-4, "the hand turned")
	var now := out.find_track(PELVIS_PATH, Animation.TYPE_POSITION_3D)
	var was := clip.find_track(PELVIS_PATH, Animation.TYPE_POSITION_3D)
	assert_vec_near(out.position_track_interpolate(now, _at(30)) - clip.position_track_interpolate(was, _at(30)), Vector3(0.1, 0.0, 0.0), 1e-5, "and the pelvis moved")


func test_write_root_travel_goes_the_way_asked_eased_and_stays() -> void:
	var clip := _moving(1.0, Vector3.ZERO, Vector3(0.0, 0.5, 2.0))
	var out := ClipBuilder.write_root_travel(clip, ROOT_PATH, 1.0, -2.0, 0.5)
	var root := out.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_eq(out.get_track_count(), clip.get_track_count(), "the old root track is replaced, not added to")
	assert_vec_near(out.position_track_interpolate(root, 0.0), Vector3.ZERO, 1e-6, "starts at the origin")
	assert_vec_near(out.position_track_interpolate(root, 0.25), Vector3(0.5, 0.0, -1.0), 1e-5, "halfway at the midpoint")
	assert_vec_near(out.position_track_interpolate(root, 0.5), Vector3(1.0, 0.0, -2.0), 1e-5, "there on time")
	assert_vec_near(out.position_track_interpolate(root, 1.0), Vector3(1.0, 0.0, -2.0), 1e-5, "and stays")
	var early := out.position_track_interpolate(root, 1.0 / 60.0).length()
	var middle := out.position_track_interpolate(root, 0.25 + 1.0 / 120.0).distance_to(out.position_track_interpolate(root, 0.25 - 1.0 / 120.0))
	assert_true(early < middle * 0.2, "eased in: the first frame covers %.4f against %.4f in the middle" % [early, middle])
	_assert_same_pose(_without_root(out), 0.4, _without_root(clip), 0.4, 1e-6, "the bones are as they were")
	var bare := _without_root(clip)
	var made := ClipBuilder.write_root_travel(bare, ROOT_PATH, 0.0, 1.0, 0.5)
	assert_ne(made.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D), -1, "a clip with no root gets one")
	assert_vec_near(clip.position_track_interpolate(clip.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D), 1.0), Vector3(0.0, 0.5, 2.0), 1e-6, "the input is left alone")


func test_build_writes_the_root_travel_and_checks_it() -> void:
	var run := _build_setup()
	_write_text(run["cfg"], "\n".join([
		"[left]", "source=\"pack\"", "clip=\"Idle\"", "root_travel=[1.5, 0.0, 0.25]",
		"[odd]", "source=\"pack\"", "clip=\"Idle\"", "root_travel=[1.5, 0.0]",
		"[slow]", "source=\"pack\"", "clip=\"Idle\"", "root_travel=[1.5, 0.0, 0.0]",
	]))
	var lines := ClipBuilder.check(run["cfg"], run["sources"], MODEL)
	assert_eq(lines.size(), 2, str(lines))
	for line in lines:
		assert_true(line.contains("root_travel"), line)
	_write_text(run["cfg"], "[left]\nsource=\"pack\"\nclip=\"Idle\"\nroot_travel=[1.5, 0.0, 0.25]\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var left := _load(run["out"] + "/left.tres") as Animation
	var root := left.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_vec_near(left.position_track_interpolate(root, left.length), Vector3(1.5, 0.0, 0.0), 1e-4, "it goes 1.5 m to the left")


func test_a_layer_that_moves_the_pelvis_of_a_clip_without_one_is_a_problem() -> void:
	var run := _build_setup()
	var layer: String = DIR + "/layers/move.json"
	_write_text(layer, JSON.stringify({"@pelvis_move": [[0, 0.1, 0, 0], [10, 0, 0, 0]]}))
	_write_text(run["cfg"], "[ok]\nsource=\"pack\"\nclip=\"Idle\"\nlayer=\"%s\"\n" % layer)
	assert_eq(ClipBuilder.check(run["cfg"], run["sources"], MODEL).size(), 0, "the fixture's pelvis has a position track")
	_write_text(layer, JSON.stringify({"@pelvis_move": [[0, 0.1, 0]]}))
	var lines := ClipBuilder.check(run["cfg"], run["sources"], MODEL)
	assert_eq(lines.size(), 1, str(lines))
	assert_true(lines.size() == 1 and lines[0].contains("@pelvis_move"), "keys of three numbers: %s" % [lines])


# --- skeleton_path ---

func test_skeleton_path_leads_from_the_model_root_to_its_skeleton() -> void:
	var scene := load(MODEL) as PackedScene
	var path := ClipBuilder.skeleton_path(scene)
	var model := track(scene.instantiate()) as Node
	assert_ne(path, NodePath(), "a path was found")
	assert_true(model.get_node_or_null(path) is Skeleton3D, "%s is the skeleton" % path)


func test_skeleton_path_is_empty_for_a_model_without_a_skeleton() -> void:
	var plain := Node3D.new()
	var scene := PackedScene.new()
	scene.pack(plain)
	plain.free()
	assert_eq(ClipBuilder.skeleton_path(scene), NodePath())


# --- load_gltf_animations ---

func test_load_gltf_animations_returns_the_clips_by_name() -> void:
	var path := _write_gltf("pack.gltf", {
		"Walk": [_channel("pelvis", "translation", [0.0, 1.0], [Vector3.ZERO, Vector3(0, 0, 2)])],
		"Idle": [_channel("hand_l", "rotation", [0.0, 0.5], [Quaternion.IDENTITY, Quaternion(Vector3.UP, 1.0)])],
	})
	var clips := ClipBuilder.load_gltf_animations(path)
	var names := PackedStringArray(clips.keys())
	names.sort()
	assert_eq(names, PackedStringArray(["Idle", "Walk"]))
	var walk: Animation = clips["Walk"]
	assert_near(walk.length, 1.0, 1e-3)
	var t := walk.find_track(NodePath("Armature/Skeleton3D:pelvis"), Animation.TYPE_POSITION_3D)
	assert_true(t >= 0, "the pelvis position track")
	assert_vec_near(walk.track_get_key_value(t, walk.track_get_key_count(t) - 1), Vector3(0, 0, 2), 1e-4)
	var idle: Animation = clips["Idle"]
	assert_true(idle.find_track(NodePath("Armature/Skeleton3D:hand_l"), Animation.TYPE_ROTATION_3D) >= 0)


func test_load_gltf_animations_is_empty_for_a_missing_file() -> void:
	var clips: Dictionary = quietly(func() -> Dictionary: return ClipBuilder.load_gltf_animations(DIR + "/nothing.gltf"))
	assert_eq(clips.size(), 0)


# --- build ---

func test_build_writes_every_clip_and_a_library_that_points_at_them() -> void:
	var run := _build_setup()
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	for file in ["idle", "run", "roll", "library"]:
		assert_true(FileAccess.file_exists("%s/%s.tres" % [run["out"], file]), file)
	var lib := _load(run["out"] + "/library.tres") as AnimationLibrary
	var names := PackedStringArray(lib.get_animation_list())
	names.sort()
	assert_eq(names, PackedStringArray(["idle", "roll", "run"]))
	assert_eq(lib.get_animation("idle").resource_path, run["out"] + "/idle.tres", "the library refers to the clip files")


func test_build_sets_loop_length_step_and_ground_speed_from_the_config() -> void:
	var run := _build_setup()
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var idle := _load(run["out"] + "/idle.tres") as Animation
	var running := _load(run["out"] + "/run.tres") as Animation
	var roll := _load(run["out"] + "/roll.tres") as Animation
	assert_eq(idle.loop_mode, Animation.LOOP_LINEAR)
	assert_eq(roll.loop_mode, Animation.LOOP_NONE)
	assert_near(roll.length, 0.5, 1e-6, "retimed from 2 s")
	assert_eq(idle.get_meta("step_fps"), 0, "step_fps is on every clip, 0 unless the config says")
	assert_eq(running.get_meta("step_fps"), 0)
	assert_eq(roll.get_meta("step_fps"), 12)
	assert_near(running.get_meta("ground_speed"), 3.0 * _hip_ratio(), 2e-3, "3 m of root travel in the 1 s run, scaled to Abarax")
	assert_false(idle.has_meta("ground_speed"), "only clips with ground_speed_from get one")
	assert_false(roll.has_meta("ground_speed"))
	# The roll came from the clip with root motion, the run did not.
	assert_true(roll.find_track(NodePath("Model/Armature/Skeleton3D:root"), Animation.TYPE_POSITION_3D) >= 0)
	assert_eq(running.find_track(NodePath("Model/Armature/Skeleton3D:root"), Animation.TYPE_POSITION_3D), -1)


func test_build_targets_abarax_bones_only_and_applies_the_position_rule() -> void:
	var run := _build_setup()
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var bones := PackedStringArray()
	var model := track((load(MODEL) as PackedScene).instantiate()) as Node
	var skeleton := model.get_node(ClipBuilder.skeleton_path(load(MODEL))) as Skeleton3D
	for i in skeleton.get_bone_count():
		bones.append(skeleton.get_bone_name(i))
	var idle := _load(run["out"] + "/idle.tres") as Animation
	var found := {}
	for i in idle.get_track_count():
		var path := idle.track_get_path(i)
		assert_true(str(path).begins_with("Model/Armature/Skeleton3D:"), str(path))
		assert_true(bones.has(str(path.get_concatenated_subnames())), "%s is a bone of Abarax" % path)
		found["%d:%s" % [idle.track_get_type(i), path.get_concatenated_subnames()]] = true
	assert_true(found.has("%d:pelvis" % Animation.TYPE_POSITION_3D))
	assert_true(found.has("%d:hand_l" % Animation.TYPE_ROTATION_3D))
	assert_false(found.has("%d:hand_l" % Animation.TYPE_POSITION_3D), "hand_l's position track was dropped")
	assert_false(found.has("%d:mannequin_extra" % Animation.TYPE_ROTATION_3D))


func test_build_is_repeatable() -> void:
	var run := _build_setup()
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var first := _texts(run["out"])
	assert_eq(first.size(), 4, "three clips and the library")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	assert_eq(_texts(run["out"]), first, "a second build changes nothing")


func test_build_keeps_marks_when_it_runs_again() -> void:
	var run := _build_setup()
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var path: String = run["out"] + "/roll.tres"
	var roll := _load(path) as Animation
	var bone_tracks := roll.get_track_count()
	var marks := roll.add_track(Animation.TYPE_METHOD)
	roll.track_set_path(marks, "Marks")
	roll.track_insert_key(marks, 0.2, {"method": "sfx", "args": [{"name": "whoosh"}]})
	assert_eq(ResourceSaver.save(roll, path), OK)

	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var again := _load(path) as Animation
	assert_eq(again.get_track_count(), bone_tracks + 1, "bone tracks are rebuilt, not doubled; Marks is kept")
	var kept := again.find_track(NodePath("Marks"), Animation.TYPE_METHOD)
	assert_true(kept >= 0, "the Marks track survived")
	assert_near(again.track_get_key_time(kept, 0), 0.2, 1e-6)
	var call: Dictionary = again.track_get_key_value(kept, 0)
	assert_eq(str(call["method"]), "sfx")
	assert_eq(call["args"], [{"name": "whoosh"}])
	var lib := _load(run["out"] + "/library.tres") as AnimationLibrary
	assert_ne(lib.get_animation("roll").find_track(NodePath("Marks"), Animation.TYPE_METHOD), -1, "the library sees it")


func test_build_scales_root_and_pelvis_by_the_models_hip_height_over_the_sources() -> void:
	# Ruling R5. The mannequin's hip is at 0.9 m, this model's at 1.0 m, so positions grow by 1/0.9.
	var run := _build_setup()
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], _write_model(1.0)), OK)
	var running := _load(run["out"] + "/run.tres") as Animation
	var pelvis := running.find_track(NodePath("Model/Armature/Skeleton3D:pelvis"), Animation.TYPE_POSITION_3D)
	assert_vec_near(running.track_get_key_value(pelvis, 0), Vector3(0.0, 1.0, 0.0) / SOURCE_HIP, 1e-4)
	assert_vec_near(running.track_get_key_value(pelvis, running.track_get_key_count(pelvis) - 1), Vector3(0.0, 1.1, 0.0) / SOURCE_HIP, 1e-4)
	assert_near(running.get_meta("ground_speed"), 3.0 / SOURCE_HIP, 2e-3, "the root motion that ground_speed measures is scaled too")
	var roll := _load(run["out"] + "/roll.tres") as Animation
	var root := roll.find_track(NodePath("Model/Armature/Skeleton3D:root"), Animation.TYPE_POSITION_3D)
	assert_vec_near(roll.track_get_key_value(root, roll.track_get_key_count(root) - 1), Vector3(0.0, 0.0, 5.0 / SOURCE_HIP), 1e-4)
	var turn := roll.find_track(NodePath("Model/Armature/Skeleton3D:hand_l"), Animation.TYPE_ROTATION_3D)
	assert_eq(roll.track_get_key_value(turn, roll.track_get_key_count(turn) - 1), Quaternion(Vector3.UP, 1.0), "rotations are not scaled")


func test_build_fails_when_a_source_skeleton_has_no_pelvis() -> void:
	var run := _build_setup()
	var bare := DIR.path_join("bare.gltf")
	assert_eq(GltfFixture.write(bare, [["root", -1], ["hand_l", 0]],
		{"Idle": [_channel("hand_l", "rotation", [0.0, 1.0], [Quaternion.IDENTITY, Quaternion(Vector3.UP, 1.0)])]}), OK)
	_write_text(run["cfg"], "[idle]\nsource=\"bare\"\nclip=\"Idle\"\n")
	var err: int = quietly(func() -> int: return ClipBuilder.build(run["cfg"], {"bare": bare}, run["out"], MODEL))
	assert_ne(err, OK)


func test_build_fails_on_a_clip_the_source_does_not_have() -> void:
	var run := _build_setup()
	_write_text(run["cfg"], "[jump]\nsource=\"pack\"\nclip=\"Not_There\"\n")
	var err: int = quietly(func() -> int: return ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL))
	assert_ne(err, OK)


func test_build_fails_on_an_unknown_source_key_or_a_missing_config() -> void:
	var run := _build_setup()
	_write_text(run["cfg"], "[idle]\nsource=\"nowhere\"\nclip=\"Idle\"\n")
	var unknown: int = quietly(func() -> int: return ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL))
	assert_ne(unknown, OK)
	var missing: int = quietly(func() -> int: return ClipBuilder.build(DIR + "/none.cfg", run["sources"], run["out"], MODEL))
	assert_ne(missing, OK)


func test_build_fails_when_ground_speed_cannot_be_measured() -> void:
	var run := _build_setup()
	# "pack" has no root motion, so a ground speed measured on it is zero.
	_write_text(run["cfg"], "[run]\nsource=\"pack\"\nclip=\"Run\"\nground_speed_from=\"pack\"\n")
	var err: int = quietly(func() -> int: return ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL))
	assert_ne(err, OK)


func test_build_joins_the_then_clips_and_continues_the_root() -> void:
	var run := _build_setup()
	# Run is 3 m in 1 s, Roll 5 m in 2 s: joined, 8 m in 3 s.
	_write_text(run["cfg"], "[twice]\nsource=\"pack_rm\"\nclip=\"Run\"\nthen=[\"Roll\"]\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var twice := _load(run["out"] + "/twice.tres") as Animation
	var root := twice.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	var ratio := _hip_ratio()
	assert_near(twice.length, 3.0, 1e-3)
	assert_vec_near(twice.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, 3.0 * ratio), 2e-3, "where Run stopped")
	assert_vec_near(twice.position_track_interpolate(root, 3.0), Vector3(0.0, 0.0, 8.0 * ratio), 2e-3, "where Roll stops")


func test_build_reads_then_as_a_string_a_list_or_a_packed_array() -> void:
	for spelling in ["\"Roll\"", "[\"Roll\"]", "[\"pack_rm:Roll\"]", "PackedStringArray(\"Roll\")"]:
		var run := _build_setup()
		_write_text(run["cfg"], "[twice]\nsource=\"pack_rm\"\nclip=\"Run\"\nthen=%s\n" % spelling)
		assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK, spelling)
		assert_near((_load(run["out"] + "/twice.tres") as Animation).length, 3.0, 1e-3, spelling)


func test_build_appends_a_clip_from_another_source() -> void:
	var run := _build_setup()
	# "pack" has no root motion: the root stays where Run left it.
	_write_text(run["cfg"], "[mixed]\nsource=\"pack_rm\"\nclip=\"Run\"\nthen=[\"pack:Idle\"]\nlength=1.0\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var mixed := _load(run["out"] + "/mixed.tres") as Animation
	var root := mixed.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_near(mixed.length, 1.0, 1e-3, "length retimes the joined clip (2 s) as a whole")
	assert_vec_near(mixed.position_track_interpolate(root, 0.75), Vector3(0.0, 0.0, 3.0 * _hip_ratio()), 2e-3)
	assert_true(mixed.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D) >= 0)


func test_build_warps_the_joined_clip() -> void:
	var run := _build_setup()
	# Roll: 5 m in 2 s. Twice as fast to its middle, then held for a second.
	_write_text(run["cfg"], "[late]\nsource=\"pack_rm\"\nclip=\"Roll\"\nwarp=[0, 0, 0.5, 1.0, 1.5, 1.0]\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var late := _load(run["out"] + "/late.tres") as Animation
	var root := late.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_near(late.length, 1.5, 1e-3)
	assert_vec_near(late.position_track_interpolate(root, 0.25), Vector3(0.0, 0.0, 1.25 * _hip_ratio()), 2e-3, "a quarter of the way in, a quarter of the roll's way ahead")
	assert_vec_near(late.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, 2.5 * _hip_ratio()), 2e-3, "held at the middle")
	assert_eq(late.track_get_key_count(root), 91, "a key every 1/60 s over 1.5 s")


func test_build_warps_after_joining() -> void:
	var run := _build_setup()
	# Run + Roll is 3 s; the warp plays its first half in a second and drops the rest.
	_write_text(run["cfg"], "[cut]\nsource=\"pack_rm\"\nclip=\"Run\"\nthen=[\"Roll\"]\nwarp=PackedFloat32Array(0, 0, 1, 1.5)\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var cut := _load(run["out"] + "/cut.tres") as Animation
	var root := cut.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D)
	assert_near(cut.length, 1.0, 1e-3)
	assert_vec_near(cut.position_track_interpolate(root, 1.0), Vector3(0.0, 0.0, (3.0 + 2.5 * 0.5) * _hip_ratio()), 2e-3, "source time 1.5 is Roll's 0.5 s")


func test_build_lays_the_layer_on_after_the_warp() -> void:
	var run := _build_setup()
	var layer: String = DIR + "/layers/arm.json"
	_write_text(layer, JSON.stringify({"hand_l": [[0, 0, 0, 0], [15, 0, 45, 0], [30, 0, 0, 0]]}))
	_write_text(run["cfg"], "\n".join([
		"[plain]", "source=\"pack\"", "clip=\"Idle\"", "warp=[0, 0, 1, 1]",
		"[arm]", "source=\"pack\"", "clip=\"Idle\"", "warp=[0, 0, 1, 1]", "layer=\"%s\"" % layer,
	]))
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	var plain := _load(run["out"] + "/plain.tres") as Animation
	var arm := _load(run["out"] + "/arm.tres") as Animation
	var p := plain.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D)
	var a := arm.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D)
	_assert_quat_near(arm.rotation_track_interpolate(a, 0.25), plain.rotation_track_interpolate(p, 0.25) * Quaternion(Vector3.UP, deg_to_rad(45.0)), 1e-4, "f15 is 45 degrees on")
	_assert_quat_near(arm.rotation_track_interpolate(a, 0.8), plain.rotation_track_interpolate(p, 0.8), 1e-4, "f48 is past the layer")
	assert_eq(arm.get_track_count(), plain.get_track_count())
	assert_eq(arm.get_meta("step_fps"), 0, "the layered clip still gets its metadata")


func test_build_notes_where_its_joins_fall_on_the_clip_it_plays() -> void:
	# Run (1 s) then Roll (2 s), the entry written as a dictionary or plain: the join is at 1 s; retimed to 1.5 s, at
	# 0.5 s; warped so 1 s of output plays 2 s of source, at 0.5 s; a fade of 0.25 s is a span, both of its ends noted. A
	# clip with nothing joined notes nothing.
	var cases := {
		"then=[{\"clip\": \"Roll\"}]\n": [1.0],
		"then=[\"Roll\"]\n": [1.0],
		"then=\"Roll\"\nlength=1.5\n": [0.5],
		"then=[{\"clip\": \"Roll\"}]\nlength=1.5\n": [0.5],
		"then=[{\"clip\": \"Roll\"}]\nwarp=[0, 0, 1.0, 2.0, 2.0, 3.0]\n": [0.5],
		"then=[{\"clip\": \"Roll\", \"fade\": 0.25}]\n": [0.75, 1.0],
	}
	for extra: String in cases:
		var run := _build_setup()
		_write_text(run["cfg"], "[joined]\nsource=\"pack_rm\"\nclip=\"Run\"\n" + extra)
		assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK, extra)
		var clip := _load(run["out"] + "/joined.tres") as Animation
		var joins: PackedFloat32Array = clip.get_meta("joins", PackedFloat32Array())
		assert_eq(joins.size(), (cases[extra] as Array).size(), "%s: %s" % [extra, joins])
		for i in mini(joins.size(), (cases[extra] as Array).size()):
			assert_near(joins[i], cases[extra][i], 1e-3, extra)
	var run := _build_setup()
	_write_text(run["cfg"], "[alone]\nsource=\"pack_rm\"\nclip=\"Run\"\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	assert_false((_load(run["out"] + "/alone.tres") as Animation).has_meta("joins"), "nothing joined, nothing noted")


func test_build_measures_the_ground_speed_of_the_clip_it_plays() -> void:
	var run := _build_setup()
	# Run's 3 m in 1 s, warped to last 2 s.
	_write_text(run["cfg"], "[slow]\nsource=\"pack\"\nclip=\"Run\"\nwarp=[0, 0, 2, 1]\nground_speed_from=\"pack_rm\"\n")
	assert_eq(ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL), OK)
	assert_near((_load(run["out"] + "/slow.tres") as Animation).get_meta("ground_speed"), 1.5 * _hip_ratio(), 2e-3)


func test_a_clip_list_with_no_problems_has_no_problem_lines() -> void:
	var run := _build_setup()
	assert_eq(ClipBuilder.check(run["cfg"], run["sources"], MODEL), PackedStringArray())
	for rate in [0, 12, 24]:
		_write_text(run["cfg"], "[idle]\nsource=\"pack\"\nclip=\"Idle\"\nstep_fps=%d\nlength=0.0\n" % rate)
		assert_eq(ClipBuilder.check(run["cfg"], run["sources"], MODEL), PackedStringArray(), "step_fps %d" % rate)


func test_config_problems_are_reported_not_written() -> void:
	var layer: String = DIR + "/layers/nope.json"
	_write_text(layer, JSON.stringify({"nope": [[0, 0, 0, 0], [10, 5, 0, 0]]}))
	# Each section body has exactly one thing wrong, and the line says what.
	var cases := {
		"length and warp together": ["length=1.0\nwarp=[0, 0, 1, 1]", "both length and warp"],
		"an odd-sized warp": ["warp=[0, 0, 0.5]", "pairs"],
		"a warp that does not increase": ["warp=[0, 0, 0.5, 0.5, 0.5, 0.7]", "increase"],
		"a warp that does not start at 0": ["warp=[0.1, 0, 0.5, 0.5]", "start at 0"],
		"a warp with one point": ["warp=[0, 0]", "two points"],
		"a warp of words": ["warp=\"fast\"", "numbers"],
		"a then clip that is not there": ["then=\"Nope\"", "Nope"],
		"a then clip from an unknown source": ["then=[\"nowhere:Run\"]", "nowhere"],
		"a layer bone that is not a bone": ["layer=\"%s\"" % layer, "nope"],
		"a negative length": ["length=-1", "negative"],
		"a step_fps of 10": ["step_fps=10", "step_fps"],
		"a layer file that is not there": ["layer=\"%s/missing.json\"" % DIR, "missing.json"],
	}
	for what: String in cases:
		var run := _build_setup()
		var body: String = cases[what][0]
		_write_text(run["cfg"], "[bad]\nsource=\"pack\"\nclip=\"Idle\"\n%s\n" % body)
		var lines := ClipBuilder.check(run["cfg"], run["sources"], MODEL)
		assert_eq(lines.size(), 1, "%s: one problem, not %s" % [what, lines])
		if lines.size() == 1:
			assert_true(lines[0].begins_with("[bad] "), "%s: the line names the section: %s" % [what, lines[0]])
			assert_true(lines[0].contains(cases[what][1]), "%s: '%s' is in: %s" % [what, cases[what][1], lines[0]])
		var err: int = quietly(func() -> int: return ClipBuilder.build(run["cfg"], run["sources"], run["out"], MODEL))
		assert_ne(err, OK, what)
		assert_false(FileAccess.file_exists(run["out"] + "/library.tres"), "%s: nothing is written" % what)
		assert_false(FileAccess.file_exists(run["out"] + "/bad.tres"), "%s: nothing is written" % what)


func test_every_problem_in_the_clip_list_is_reported_at_once() -> void:
	var run := _build_setup()
	_write_text(run["cfg"], "\n".join([
		"[idle]", "source=\"pack\"", "clip=\"Idle\"",
		"[one]", "source=\"pack\"", "clip=\"Idle\"", "length=-2",
		"[two]", "source=\"pack\"", "clip=\"Run\"", "then=[\"Nope\"]",
		"[three]", "source=\"pack\"", "clip=\"Run\"", "step_fps=7",
	]))
	var lines := ClipBuilder.check(run["cfg"], run["sources"], MODEL)
	assert_eq(lines.size(), 3, str(lines))
	if lines.size() == 3:
		assert_true(lines[0].begins_with("[one] ") and lines[1].begins_with("[two] ") and lines[2].begins_with("[three] "), str(lines))


func test_layer_files_that_are_not_layers_are_problems() -> void:
	var run := _build_setup()
	var cases := {
		"not JSON": ["{\"hand_l\": [", "JSON"],
		"not an object": ["[1, 2]", "object"],
		"a bone with no keys": ["{\"hand_l\": []}", "hand_l"],
		"a key with three numbers": ["{\"hand_l\": [[0, 1, 2]]}", "hand_l"],
		"a key with a word in it": ["{\"hand_l\": [[0, 1, \"x\", 3]]}", "hand_l"],
		"frames that go back": ["{\"hand_l\": [[10, 0, 0, 0], [5, 0, 0, 0]]}", "increase"],
		"a bone the clip does not move": ["{\"spine_01\": [[0, 5, 0, 0]]}", "spine_01"],
	}
	for what: String in cases:
		var layer: String = DIR + "/layers/bad.json"
		_write_text(layer, cases[what][0])
		_write_text(run["cfg"], "[bad]\nsource=\"pack\"\nclip=\"Idle\"\nlayer=\"%s\"\n" % layer)
		var lines := ClipBuilder.check(run["cfg"], run["sources"], MODEL)
		assert_eq(lines.size(), 1, "%s: %s" % [what, lines])
		if lines.size() == 1:
			assert_true(lines[0].contains(cases[what][1]), "%s: '%s' is in: %s" % [what, cases[what][1], lines[0]])


# --- helpers ---

# A 1 s animation with no tracks.
func _anim() -> Animation:
	var a := Animation.new()
	a.length = 1.0
	return a


func _rotation(a: Animation, bone: String) -> int:
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, "Armature/Skeleton3D:" + bone)
	a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
	a.rotation_track_insert_key(t, 1.0, Quaternion(Vector3.UP, 1.0))
	return t


func _position(a: Animation, bone: String) -> int:
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, "Armature/Skeleton3D:" + bone)
	a.position_track_insert_key(t, 0.0, Vector3.ZERO)
	a.position_track_insert_key(t, 1.0, Vector3(0.0, 0.1, 0.2))
	return t


func _paths(a: Animation) -> PackedStringArray:
	var found := PackedStringArray()
	for i in a.get_track_count():
		found.append(str(a.track_get_path(i)))
	return found


func _channel(bone: String, path: String, times: Array, values: Array) -> Dictionary:
	return {"bone": bone, "path": path, "times": times, "values": values}


func _write_gltf(file: String, clips: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join(file)
	assert_eq(GltfFixture.write(path, JOINTS, clips), OK)
	return path


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# Abarax's hip height over the fixture mannequin's.
func _hip_ratio() -> float:
	var model := track((load(MODEL) as PackedScene).instantiate()) as Node
	return ClipBuilder.hip_height(model.get_node(ClipBuilder.skeleton_path(load(MODEL))) as Skeleton3D) / SOURCE_HIP


# A model scene (Model / Armature / Skeleton3D with root, pelvis and hand_l) whose pelvis rests `hip`
# metres up, saved to user://. Returns its path.
func _write_model(hip: float) -> String:
	var model := Node3D.new()
	model.name = "Model"
	var armature := Node3D.new()
	armature.name = "Armature"
	model.add_child(armature)
	armature.owner = model
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	armature.add_child(skeleton)
	skeleton.owner = model
	skeleton.add_bone("root")
	skeleton.add_bone("pelvis")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0.0, hip, 0.0)))
	skeleton.add_bone("hand_l")
	skeleton.set_bone_parent(2, 1)
	var scene := PackedScene.new()
	scene.pack(model)
	model.free()
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("model_hip_%s.tscn" % str(hip).replace(".", "_"))
	assert_eq(ResourceSaver.save(scene, path), OK)
	return path


# file name -> text, for every file directly in `dir`.
func _texts(dir: String) -> Dictionary:
	var found := {}
	for file in DirAccess.get_files_at(dir):
		found[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return found


func _load(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


# A moving clip as the builder has it after rewrite_paths: `seconds` long, a key every 1/30 s (what a glTF
# gives), on the bones root, pelvis and hand_l. The root travels in a line from `from` to `to`; the other
# tracks bend, so that a wrong sample time shows.
func _moving(seconds: float, from := Vector3.ZERO, to := Vector3.ZERO) -> Animation:
	var a := Animation.new()
	a.length = seconds
	var root := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(root, ROOT_PATH)
	var pelvis_move := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pelvis_move, PELVIS_PATH)
	var pelvis_turn := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(pelvis_turn, PELVIS_PATH)
	var hand_turn := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(hand_turn, HAND_PATH)
	var hand_scale := a.add_track(Animation.TYPE_SCALE_3D)
	a.track_set_path(hand_scale, HAND_PATH)
	for k in roundi(seconds * 30.0) + 1:
		var t := minf(k / 30.0, seconds)
		a.position_track_insert_key(root, t, from.lerp(to, t / seconds))
		a.position_track_insert_key(pelvis_move, t, Vector3(0.05 * sin(3.0 * t), 0.9 + 0.1 * cos(2.0 * t), 0.02 * t))
		a.rotation_track_insert_key(pelvis_turn, t, Quaternion(Vector3.UP, 1.5 * t))
		a.rotation_track_insert_key(hand_turn, t, Quaternion(Vector3.RIGHT, sin(4.0 * t)))
		a.scale_track_insert_key(hand_scale, t, Vector3(1.0, 1.0 + 0.3 * t, 1.0))
	return a


# A copy of `anim` without its root position track: the pose, without the travel a join moves on.
func _without_root(anim: Animation) -> Animation:
	var copy := anim.duplicate() as Animation
	copy.remove_track(copy.find_track(ROOT_PATH, Animation.TYPE_POSITION_3D))
	return copy


# Frame `frame` of a 60 Hz grid, in seconds.
func _at(frame: int) -> float:
	return frame / 60.0


# The rotation of hand_l in `anim` at frame `frame` of a 60 Hz grid.
func _hand(anim: Animation, frame: int) -> Quaternion:
	return anim.rotation_track_interpolate(anim.find_track(HAND_PATH, Animation.TYPE_ROTATION_3D), _at(frame))


func _about(axis: Vector3, degrees: float) -> Quaternion:
	return Quaternion(axis, deg_to_rad(degrees))


# What track `track` of `anim` holds at `time`.
func _value(anim: Animation, track: int, time: float) -> Variant:
	match anim.track_get_type(track):
		Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return anim.rotation_track_interpolate(track, time)
	return anim.scale_track_interpolate(track, time)


func _values_near(a: Variant, b: Variant, eps: float) -> bool:
	if a is Quaternion:
		return _quat_distance(a, b) < eps
	return (a - b).length() < eps


# How far apart two rotations are, as the shorter of |a - b| and |a + b| (q and -q are the same turn).
func _quat_distance(a: Quaternion, b: Quaternion) -> float:
	return minf((a - b).length(), (a + b).length())


func _assert_quat_near(a: Quaternion, b: Quaternion, eps: float, msg := "") -> void:
	assert_true(_quat_distance(a, b) < eps, "%s: %s is not %s" % [msg, a, b])


# Asserts that `a` at `time_a` and `b` at `time_b` are the same pose: every track of `a`, with the track of
# the same path and kind in `b`.
func _assert_same_pose(a: Animation, time_a: float, b: Animation, time_b: float, eps: float, msg: String) -> void:
	assert_true(a.get_track_count() > 0, "%s: there are tracks to compare" % msg)
	for i in a.get_track_count():
		var j := b.find_track(a.track_get_path(i), a.track_get_type(i))
		assert_true(j >= 0, "%s: %s is in both" % [msg, a.track_get_path(i)])
		if j >= 0:
			var x: Variant = _value(a, i, time_a)
			var y: Variant = _value(b, j, time_b)
			assert_true(_values_near(x, y, eps), "%s: %s is %s, not %s" % [msg, a.track_get_path(i), x, y])


# Two packs ("pack", and "pack_rm" with root motion), a config over them, and an output folder.
func _build_setup() -> Dictionary:
	var turn := Quaternion(Vector3.UP, 1.0)
	var pose := func(seconds: float, extra: Array) -> Array:
		var channels: Array = [
			_channel("pelvis", "rotation", [0.0, seconds], [Quaternion.IDENTITY, turn]),
			_channel("pelvis", "translation", [0.0, seconds], [Vector3(0, 1, 0), Vector3(0, 1.1, 0)]),
			_channel("hand_l", "rotation", [0.0, seconds], [Quaternion.IDENTITY, turn]),
			_channel("hand_l", "translation", [0.0, seconds], [Vector3(0.5, 0, 0), Vector3(0.6, 0, 0)]),
			_channel("mannequin_extra", "rotation", [0.0, seconds], [Quaternion.IDENTITY, turn]),
		]
		channels.append_array(extra)
		return channels
	var travel := func(metres: float, seconds: float) -> Dictionary:
		return _channel("root", "translation", [0.0, seconds], [Vector3.ZERO, Vector3(0, 0, metres)])
	var pack := _write_gltf("pack.gltf", {
		"Idle": pose.call(1.0, []),
		"Run": pose.call(1.0, []),
	})
	var pack_rm := _write_gltf("pack_rm.gltf", {
		"Run": pose.call(1.0, [travel.call(3.0, 1.0)]),    # 3 m in 1 s
		"Roll": pose.call(2.0, [travel.call(5.0, 2.0)]),   # 2 s long; the config retimes it to 0.5 s
	})
	var cfg := DIR + "/clips.cfg"
	_write_text(cfg, "\n".join([
		"[idle]", "source=\"pack\"", "clip=\"Idle\"", "loop=true",
		"[run]", "source=\"pack\"", "clip=\"Run\"", "loop=true", "ground_speed_from=\"pack_rm\"",
		"[roll]", "source=\"pack_rm\"", "clip=\"Roll\"", "length=0.5", "step_fps=12",
	]))
	return {"cfg": cfg, "sources": {"pack": pack, "pack_rm": pack_rm}, "out": DIR + "/out"}
