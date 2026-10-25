extends TestCase
## The F0 content: the moves, Abarax's definition and his locomotion tuning, as committed under data/.
## The marks are checked against the table the clips were authored from; the rules they must keep are
## ClipChecker's (test_clip_checker.gd).

const LIB := "res://assets/anim/abarax/library.tres"
const MODEL := "res://assets/characters/abarax/abarax.glb"

# Marks as [frame, kind, args], in the order they are meant to read.
const TABLE := {
	&"palm_jab": [
		[5, &"sfx", {"name": &"palm_whoosh"}],
		[10, &"hitbox_on", {"id": &"palm_l"}],
		[10, &"fx", {"name": &"palm_trail"}],
		[10, &"hitstop", {"frames": 3}],
		[15, &"hitbox_off", {"id": &"palm_l"}],
		[15, &"cancel_open", {"into": {&"palm": &"palm_cross"}}],
		[20, &"recovery", {}],
		[20, &"cancel_open", {"into": {&"palm": &"palm_cross", &"dodge": &"dodge_roll"}}],
	],
	&"palm_cross": [
		[5, &"sfx", {"name": &"palm_whoosh"}],
		[15, &"hitbox_on", {"id": &"palm_r"}],
		[15, &"fx", {"name": &"palm_trail"}],
		[15, &"hitstop", {"frames": 4}],
		[20, &"hitbox_off", {"id": &"palm_r"}],
		[20, &"cancel_open", {"into": {&"palm": &"palm_jab"}}],
		[25, &"recovery", {}],
		[25, &"cancel_open", {"into": {&"palm": &"palm_jab", &"dodge": &"dodge_roll"}}],
	],
	&"dodge_roll": [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[3, &"iframes_on", {}],
		[14, &"fx", {"name": &"roll_dust"}],
		[14, &"sfx", {"name": &"roll_land"}],
		[16, &"iframes_off", {}],
		[20, &"recovery", {}],
		[22, &"cancel_open", {"into": {&"palm": &"palm_jab", &"dodge": &"dodge_roll"}}],
	],
}
const LENGTHS := {&"palm_jab": 35, &"palm_cross": 40, &"dodge_roll": 30}
const STEPS := {&"palm_jab": 12, &"palm_cross": 12, &"dodge_roll": 0}


func _clip(n: StringName) -> Animation:
	return (load(LIB) as AnimationLibrary).get_animation(n)


func test_moves_are_registered_with_their_kinds_and_clips() -> void:
	var want := {&"palm_jab": MoveData.Kind.ATTACK, &"palm_cross": MoveData.Kind.ATTACK, &"dodge_roll": MoveData.Kind.DODGE}
	for id: StringName in want:
		var move := Registry.fetch(&"moves", id) as MoveData
		assert_ne(move, null, str(id))
		if move == null:
			continue
		assert_eq(move.id, id)
		assert_eq(move.kind, want[id], str(id))
		assert_eq(move.clip, id, "%s plays the clip of its own name" % id)
		assert_true((load(LIB) as AnimationLibrary).has_animation(move.clip), "the library has %s" % move.clip)


func test_move_data_defaults() -> void:
	var m := MoveData.new()
	assert_true(m.root_motion)
	assert_eq(m.root_motion_scale, 1.0)
	assert_eq(m.stamina_cost, 0.0); assert_eq(m.posture_damage, 0.0); assert_eq(m.poise_damage, 0.0)
	assert_eq(m.blend_in, 0.05); assert_eq(m.blend_out, 0.15)
	assert_eq(m.kind, MoveData.Kind.ATTACK, "ATTACK is the first kind")
	assert_eq(MoveData.Kind.DODGE, 1); assert_eq(MoveData.Kind.OTHER, 2)


func test_the_clips_have_the_lengths_and_steps_the_marks_were_placed_for() -> void:
	for id: StringName in TABLE:
		assert_eq(Marks.frame_of(_clip(id).length), LENGTHS[id], "%s is %d frames long" % [id, LENGTHS[id]])
		assert_eq(_clip(id).get_meta("step_fps"), STEPS[id], "%s step" % id)


func test_marks_are_the_f0_table() -> void:
	for id: StringName in TABLE:
		var want: Array = TABLE[id]
		var read := Marks.read(_clip(id))
		assert_eq(read.size(), want.size(), "%s: number of marks" % id)
		for i in mini(read.size(), want.size()):
			var label := "%s mark %d (%s)" % [id, i, want[i][1]]
			assert_eq(Marks.frame_of(read[i]["time"]), want[i][0], label + " frame")
			assert_eq(read[i]["kind"], want[i][1], label + " kind")
			assert_eq(read[i]["args"], want[i][2], label + " args")


func test_the_dodge_is_invulnerable_for_13_frames_out_of_30() -> void:
	var marks := Marks.read(_clip(&"dodge_roll"))
	var on := -1
	var off := -1
	for m in marks:
		if m["kind"] == &"iframes_on":
			on = Marks.frame_of(m["time"])
		elif m["kind"] == &"iframes_off":
			off = Marks.frame_of(m["time"])
	assert_eq(off - on, 13, "frames [%d, %d)" % [on, off])


func test_roll_root_motion_scale_makes_the_roll_cover_three_metres() -> void:
	var roll := Registry.fetch(&"moves", &"dodge_roll") as MoveData
	var travelled := _root_travel(_clip(&"dodge_roll"))
	assert_true(travelled > 4.0, "the clip itself travels %s m" % travelled)
	assert_near(roll.root_motion_scale * travelled, 3.0, 0.05, "scale %s x %s m" % [roll.root_motion_scale, travelled])
	assert_eq(snappedf(roll.root_motion_scale, 0.01), roll.root_motion_scale, "two decimals")
	assert_true(roll.root_motion)


func test_attacks_keep_the_clips_own_root_motion_scale() -> void:
	for id in [&"palm_jab", &"palm_cross"]:
		assert_eq((Registry.fetch(&"moves", id) as MoveData).root_motion_scale, 1.0, str(id))


func test_locomotion_tuning_defaults_are_the_measured_ground_speeds_to_a_tenth() -> void:
	var tuning := load("res://data/tuning/abarax_locomotion.tres") as LocomotionTuning
	assert_ne(tuning, null)
	assert_eq(tuning.walk_speed, snappedf(float(_clip(&"walk").get_meta("ground_speed")), 0.1))
	assert_eq(tuning.jog_speed, snappedf(float(_clip(&"jog").get_meta("ground_speed")), 0.1))
	assert_eq(tuning.sprint_speed, snappedf(float(_clip(&"sprint").get_meta("ground_speed")), 0.1))
	assert_eq([tuning.walk_speed, tuning.jog_speed, tuning.sprint_speed], [1.0, 5.5, 8.5])
	assert_eq(tuning.accel, 18.0); assert_eq(tuning.decel, 24.0)
	assert_eq(tuning.turn_rate_deg, 720.0); assert_eq(tuning.walk_threshold, 0.5)
	var plain := LocomotionTuning.new()
	assert_eq([plain.walk_speed, plain.jog_speed, plain.sprint_speed], [1.0, 5.5, 8.5], "the class defaults agree")


func test_abarax_is_defined_by_data() -> void:
	var def := Registry.fetch(&"actors", &"abarax") as ActorDef
	assert_ne(def, null)
	if def == null:
		return
	assert_eq(def.id, &"abarax")
	assert_eq(def.moveset, {&"palm": &"palm_jab", &"dodge": &"dodge_roll"})
	assert_eq(def.max_hp, 100.0); assert_eq(def.max_stamina, 100.0); assert_eq(def.max_posture, 100.0); assert_eq(def.poise, 10.0)
	assert_eq(def.required_clips, PackedStringArray(["idle", "walk", "jog", "sprint"]))
	assert_eq(def.locomotion, load("res://data/tuning/abarax_locomotion.tres"))
	var rig := def.rig_scene.instantiate()
	assert_true(rig is Rig)
	rig.free()
	assert_eq(def.rig_scene.resource_path, "res://actors/abarax/abarax_rig.tscn")


func test_actor_def_defaults() -> void:
	var def := ActorDef.new()
	assert_eq([def.max_hp, def.max_stamina, def.max_posture, def.poise], [100.0, 100.0, 100.0, 10.0])
	assert_eq(def.required_clips, PackedStringArray(["idle", "walk", "jog", "sprint"]))
	assert_eq(def.moveset, {})


func test_every_moveset_move_of_abarax_is_a_registered_move() -> void:
	var def := Registry.fetch(&"actors", &"abarax") as ActorDef
	for action in def.moveset:
		assert_true(Registry.ids(&"moves").has(String(def.moveset[action])), "%s -> %s" % [action, def.moveset[action]])


# The horizontal distance the clip's root bone travels between its first and last key.
func _root_travel(anim: Animation) -> float:
	var root := NodePath("Model/%s:root" % ClipBuilder.skeleton_path(load(MODEL)))
	var t := anim.find_track(root, Animation.TYPE_POSITION_3D)
	if t < 0:
		return 0.0
	var first: Vector3 = anim.track_get_key_value(t, 0)
	var last: Vector3 = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
	return Vector2(last.x - first.x, last.z - first.z).length()
