extends TestCase
## Abarax's committed animation library (assets/anim/abarax/, built from assets/anim/clips.cfg by
## tools/anim/build_library.gd). These check the files as they are in the repository.

const LIB := "res://assets/anim/abarax/library.tres"
const MODEL := "res://assets/characters/abarax/abarax.glb"
const CLIPS: PackedStringArray = ["idle", "walk", "jog", "sprint", "dodge_roll", "palm_jab", "palm_cross", "t_pose"]
const LOCOMOTION: PackedStringArray = ["walk", "jog", "sprint"]
const MAX_CLIP_BYTES := 2 * 1024 * 1024


func test_has_all_clips() -> void:
	var lib := load(LIB) as AnimationLibrary
	assert_ne(lib, null, "library.tres loads")
	for n in CLIPS:
		assert_true(lib.has_animation(n), n)
	assert_eq(lib.get_animation_list().size(), CLIPS.size(), "and nothing else")


func test_every_clip_is_its_own_text_file_of_sane_size() -> void:
	var lib := load(LIB) as AnimationLibrary
	for n in CLIPS:
		var path := "res://assets/anim/abarax/%s.tres" % n
		assert_eq(lib.get_animation(n).resource_path, path, n)
		assert_true(FileAccess.file_exists(path), path)
		assert_true(FileAccess.get_file_as_string(path).begins_with("[gd_resource type=\"Animation\""), "%s is text" % n)
		var file := FileAccess.open(path, FileAccess.READ)
		assert_true(file.get_length() < MAX_CLIP_BYTES, "%s is %d bytes" % [n, file.get_length()])


func test_loops_and_lengths_and_steps() -> void:
	var lib := load(LIB) as AnimationLibrary
	for n in ["idle", "walk", "jog", "sprint"]:
		assert_eq(lib.get_animation(n).loop_mode, Animation.LOOP_LINEAR, "%s loops" % n)
	for n in ["dodge_roll", "palm_jab", "palm_cross", "t_pose"]:
		assert_eq(lib.get_animation(n).loop_mode, Animation.LOOP_NONE, "%s plays once" % n)
	assert_near(lib.get_animation("dodge_roll").length, 0.5, 0.001)
	assert_near(lib.get_animation("palm_jab").length, 0.5833, 0.001)
	assert_near(lib.get_animation("palm_cross").length, 0.6667, 0.001)
	assert_eq(lib.get_animation("palm_jab").get_meta("step_fps"), 12)
	assert_eq(lib.get_animation("palm_cross").get_meta("step_fps"), 12)
	assert_eq(lib.get_animation("dodge_roll").get_meta("step_fps"), 0)
	for n in CLIPS:
		assert_true(lib.get_animation(n).has_meta("step_fps"), "%s carries step_fps" % n)
		assert_eq(typeof(lib.get_animation(n).get_meta("step_fps")), TYPE_INT, "%s: step_fps is an int" % n)


func test_ground_speeds_are_plausible_and_ordered() -> void:
	var lib := load(LIB) as AnimationLibrary
	for n in CLIPS:
		assert_eq(lib.get_animation(n).has_meta("ground_speed"), LOCOMOTION.has(n), "%s: ground_speed is for walk, jog and sprint only" % n)
	var walk: float = lib.get_animation("walk").get_meta("ground_speed")
	var jog: float = lib.get_animation("jog").get_meta("ground_speed")
	var sprint: float = lib.get_animation("sprint").get_meta("ground_speed")
	# Measured on the pack's root-motion clips: walk 0.975, jog 5.357, sprint 8.25 m/s.
	assert_true(walk >= 0.9 and walk <= 2.2, "walk %s" % walk)
	assert_true(jog >= 2.5 and jog <= 5.5, "jog %s" % jog)
	assert_true(sprint >= 4.5 and sprint <= 8.5, "sprint %s" % sprint)
	assert_true(walk < jog and jog < sprint, "walk %s < jog %s < sprint %s" % [walk, jog, sprint])


func test_every_track_targets_a_real_bone() -> void:
	var lib := load(LIB) as AnimationLibrary
	var scene := load(MODEL) as PackedScene
	var model := track(scene.instantiate()) as Node
	var skel_path := ClipBuilder.skeleton_path(scene)
	var skeleton := model.get_node(skel_path) as Skeleton3D
	var tracks := 0
	for n in CLIPS:
		var a := lib.get_animation(n)
		for i in a.get_track_count():
			var path := a.track_get_path(i)
			var type := a.track_get_type(i)
			if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
				continue
			tracks += 1
			assert_eq(path.get_concatenated_names(), "Model/" + str(skel_path), "%s track %d" % [n, i])
			var bone := str(path.get_concatenated_subnames())
			assert_true(skeleton.find_bone(bone) >= 0, "%s: '%s' is a bone of abarax.glb" % [n, bone])
	assert_true(tracks > 0, "the clips have bone tracks")


func test_position_tracks_are_only_for_root_and_pelvis_and_no_scale_track_is_idle() -> void:
	# Ruling R4.
	var lib := load(LIB) as AnimationLibrary
	for n in CLIPS:
		var a := lib.get_animation(n)
		for i in a.get_track_count():
			var bone := str(a.track_get_path(i).get_concatenated_subnames())
			match a.track_get_type(i):
				Animation.TYPE_POSITION_3D:
					assert_true(bone == "root" or bone == "pelvis", "%s has a position track on %s" % [n, bone])
				Animation.TYPE_SCALE_3D:
					var changes := false
					for k in a.track_get_key_count(i):
						var v: Vector3 = a.track_get_key_value(i, k)
						changes = changes or maxf(maxf(absf(v.x - 1.0), absf(v.y - 1.0)), absf(v.z - 1.0)) > 1e-4
					assert_true(changes, "%s has a scale track on %s that never leaves 1" % [n, bone])


func test_locomotion_clips_stay_in_place_and_the_roll_carries_root_motion() -> void:
	var lib := load(LIB) as AnimationLibrary
	var root := NodePath("Model/%s:root" % ClipBuilder.skeleton_path(load(MODEL)))
	for n in ["idle", "walk", "jog", "sprint", "t_pose", "palm_jab", "palm_cross"]:
		assert_eq(lib.get_animation(n).find_track(root, Animation.TYPE_POSITION_3D), -1, "%s has no root travel" % n)
	assert_true(lib.get_animation("dodge_roll").find_track(root, Animation.TYPE_POSITION_3D) >= 0)
