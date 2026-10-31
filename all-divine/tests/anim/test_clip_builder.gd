extends TestCase
## ClipBuilder: the pieces that turn the Quaternius clips into Abarax's clips (tools/anim/clip_builder.gd).
## The first group works on animations built in memory, the second on tiny glTF files written to
## user://, so none of it needs the Quaternius pack. The committed clips are checked by test_library.gd.

const MODEL := "res://assets/characters/abarax/abarax.glb"
const SKEL := NodePath("Armature/Skeleton3D")
const BONES: PackedStringArray = ["root", "pelvis", "hand_l"]
const DIR := "user://clip_builder_fixture"

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
