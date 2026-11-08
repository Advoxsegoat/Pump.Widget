extends TestCase
## The content so far: the moves, Abarax's definition and his locomotion tuning, as committed under data/.
## The marks are checked against the table the clips were authored from; the rules they must keep are
## ClipChecker's (test_clip_checker.gd).

const LIB := "res://assets/anim/abarax/library.tres"
const MODEL := "res://assets/characters/abarax/abarax.glb"

# Marks as [frame, kind, args], in the order they are meant to read. (F0's table, less the hit-stop marks,
# which are the hit profiles' hitstop_frames now, and with the profile each hitbox carries.)
const TABLE := {
	&"palm_jab": [
		[5, &"sfx", {"name": &"palm_whoosh"}],
		[10, &"hitbox_on", {"id": &"palm_l", "profile": &"palm"}],
		[10, &"fx", {"name": &"palm_trail"}],
		[15, &"hitbox_off", {"id": &"palm_l"}],
		[15, &"cancel_open", {"into": {&"palm": &"palm_cross"}}],
		[20, &"recovery", {}],
		[20, &"cancel_open", {"into": {&"palm": &"palm_cross", &"dodge": &"dodge_roll"}}],
	],
	&"palm_cross": [
		[5, &"sfx", {"name": &"palm_whoosh"}],
		[15, &"hitbox_on", {"id": &"palm_r", "profile": &"palm"}],
		[15, &"fx", {"name": &"palm_trail", "bone": &"hand_r"}],
		[20, &"hitbox_off", {"id": &"palm_r"}],
		[20, &"cancel_open", {"into": {&"palm": &"palm_hook"}}],
		[25, &"recovery", {}],
		[25, &"cancel_open", {"into": {&"palm": &"palm_hook", &"dodge": &"dodge_roll"}}],
	],
	# The hook and the heavy palm's contact frames are where their clips show full extension (F1 Task 7's sheet).
	&"palm_hook": [
		[5, &"sfx", {"name": &"palm_whoosh"}],
		[15, &"hitbox_on", {"id": &"palm_r", "profile": &"hook"}],
		[15, &"fx", {"name": &"palm_trail", "bone": &"hand_r"}],
		[20, &"hitbox_off", {"id": &"palm_r"}],
		[30, &"recovery", {}],
		[30, &"cancel_open", {"into": {&"palm": &"palm_jab", &"dodge": &"dodge_roll"}}],
	],
	&"palm_heavy": [
		[10, &"hyperarmour_on", {}],
		[10, &"charge_hold", {"action": &"heavy", "frames": 40, "profile": &"charged"}],
		[15, &"sfx", {"name": &"whoosh_heavy"}],
		[15, &"hitbox_on", {"id": &"palm_r", "profile": &"heavy"}],
		[15, &"fx", {"name": &"palm_trail", "bone": &"hand_r"}],
		[20, &"hitbox_off", {"id": &"palm_r"}],
		[20, &"hyperarmour_off", {}],
		[40, &"recovery", {}],
		[45, &"cancel_open", {"into": {&"palm": &"palm_jab", &"dodge": &"dodge_roll"}}],
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
const LENGTHS := {&"palm_jab": 35, &"palm_cross": 40, &"palm_hook": 45, &"palm_heavy": 57, &"dodge_roll": 30}
const STEPS := {&"palm_jab": 12, &"palm_cross": 12, &"palm_hook": 12, &"palm_heavy": 12, &"dodge_roll": 0}
# The reactions every actor shares (F1 Tasks 5 and 8): [length in frames, whether the move takes the clip's root
# motion, then its marks as in TABLE]. Each is smooth. The death's thud and dust are on the frame its hips
# meet the ground. A reaction's own sound is cloth moving (roll_cloth): the blow that caused it already plays
# the target's surface (ActorFx).
const REACTIONS := {
	&"flinch": [27, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[0, &"fx", {"name": &"roll_dust"}],
		[20, &"recovery", {}],
		[22, &"cancel_open", {"into": {&"dodge": &"dodge_roll"}}],
	]],
	&"stagger": [48, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[0, &"fx", {"name": &"roll_dust"}],
		[40, &"recovery", {}],
		[42, &"cancel_open", {"into": {&"dodge": &"dodge_roll"}}],
	]],
	&"death": [144, false, [
		[56, &"sfx", {"name": &"body_fall"}],
		[56, &"fx", {"name": &"roll_dust"}],
	]],
	&"guard_hit": [21, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[0, &"fx", {"name": &"roll_dust"}],
		[12, &"recovery", {}],
		[14, &"cancel_open", {"into": {&"palm": &"palm_jab", &"dodge": &"dodge_roll"}}],
	]],
	&"guard_break": [60, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[0, &"fx", {"name": &"roll_dust"}],
		[50, &"recovery", {}],
	]],
	&"parried": [36, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[0, &"fx", {"name": &"roll_dust"}],
		[36, &"recovery", {}],
	]],
	&"caught": [54, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[0, &"fx", {"name": &"roll_dust"}],
		[45, &"recovery", {}],
	]],
}
# The guard and its answers to a blow (F1 Task 8), OTHER moves without root motion, as REACTIONS has them. The
# raise's parry window is f0 to f9 (10 frames, 167 ms); its guard is up from f4 to its end. The parry and the
# catch open the riposte: palm or heavy at f8 and f14.
const GUARD_MOVES := {
	&"guard_raise": [14, false, [
		[0, &"parry_on", {}],
		[0, &"sfx", {"name": &"whoosh_light"}],
		[2, &"fx", {"name": &"glint"}],
		[4, &"guard_on", {}],
		[10, &"parry_off", {}],
		[10, &"recovery", {}],
		[10, &"cancel_open", {"into": {&"palm": &"palm_jab", &"heavy": &"palm_heavy", &"dodge": &"dodge_roll"}}],
		[14, &"guard_off", {}],
	]],
	&"parry": [24, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[0, &"fx", {"name": &"glint"}],
		[8, &"cancel_open", {"into": {&"palm": &"palm_jab", &"heavy": &"palm_heavy"}}],
	]],
	&"catch": [30, false, [
		[0, &"sfx", {"name": &"roll_cloth"}],
		[4, &"fx", {"name": &"palm_trail", "bone": &"hand_r"}],
		[14, &"cancel_open", {"into": {&"palm": &"palm_jab", &"heavy": &"palm_heavy"}}],
	]],
}


func _clip(n: StringName) -> Animation:
	return (load(LIB) as AnimationLibrary).get_animation(n)


func test_moves_are_registered_with_their_kinds_and_clips() -> void:
	var want := {&"palm_jab": MoveData.Kind.ATTACK, &"palm_cross": MoveData.Kind.ATTACK, &"palm_hook": MoveData.Kind.ATTACK,
			&"palm_heavy": MoveData.Kind.ATTACK, &"dodge_roll": MoveData.Kind.DODGE}
	for id: StringName in want:
		var move := Registry.fetch(&"moves", id) as MoveData
		if move == null:
			fail("%s is a registered MoveData" % id)
			continue
		assert_eq(move.id, id)
		assert_eq(move.kind, want[id], str(id))
		assert_eq(move.clip, id, "%s plays the clip of its own name" % id)
		assert_true((load(LIB) as AnimationLibrary).has_animation(move.clip), "the library has %s" % move.clip)


func test_move_data_defaults() -> void:
	var m := MoveData.new()
	assert_true(m.root_motion)
	assert_eq(m.root_motion_scale, 1.0)
	assert_eq(m.stamina_cost, 0.0)
	assert_eq(m.blend_in, 0.05); assert_eq(m.blend_out, 0.15)
	assert_eq(m.kind, MoveData.Kind.ATTACK, "ATTACK is the first kind")
	assert_eq(MoveData.Kind.DODGE, 1); assert_eq(MoveData.Kind.OTHER, 2); assert_eq(MoveData.Kind.REACTION, 3)
	assert_eq(m.hits, {})
	assert_true(m.aim, "a move turns toward its target during wind-up unless told not to")
	assert_eq(m.neutral_variant, &"")


func test_move_data_has_hits_and_no_old_fields() -> void:
	# What a blow does is its HitProfile now (MoveData.hits), not two numbers on the move.
	assert_false("posture_damage" in MoveData.new())
	assert_false("poise_damage" in MoveData.new())
	assert_true("hits" in MoveData.new())


func test_abarax_jab_and_cross_have_a_palm_profile() -> void:
	# [damage, poise, posture, guard_stamina, hitstop_frames, knockback]
	var want := {&"palm_jab": [8.0, 6.0, 4.0, 8.0, 3, 1.0], &"palm_cross": [10.0, 8.0, 6.0, 10.0, 4, 1.5]}
	for id: StringName in want:
		var move := Registry.fetch(&"moves", id) as MoveData
		assert_eq(move.hits.keys(), [&"palm"], "%s has the one profile, palm" % id)
		var p := move.hits[&"palm"] as HitProfile
		if p == null:
			fail("%s: hits[palm] is a HitProfile" % id)
			continue
		assert_eq([p.damage, p.poise_damage, p.posture_damage, p.guard_stamina, p.hitstop_frames, p.knockback], want[id], str(id))
		assert_eq([p.shake, p.staggers, p.height, p.perilous, p.impact_sound],
				[0.0, false, HitProfile.Height.MID, HitProfile.Perilous.NONE, &"impact_palm"], "%s: the rest is the default" % id)
	assert_eq((Registry.fetch(&"moves", &"palm_jab") as MoveData).hits[&"palm"].hitstop_frames, 3)
	assert_eq((Registry.fetch(&"moves", &"palm_cross") as MoveData).hits[&"palm"].hitstop_frames, 4)


func test_the_hook_has_a_hook_profile() -> void:
	var move := Registry.fetch(&"moves", &"palm_hook") as MoveData
	assert_eq(move.hits.keys(), [&"hook"])
	var p := move.hits[&"hook"] as HitProfile
	assert_eq([p.damage, p.poise_damage, p.posture_damage, p.guard_stamina, p.hitstop_frames, p.shake, p.knockback],
			[13.0, 12.0, 10.0, 14.0, 5, 0.3, 2.0])
	assert_eq([p.staggers, p.height, p.perilous, p.impact_sound], [false, HitProfile.Height.MID, HitProfile.Perilous.NONE, &"impact_palm"])
	assert_eq(move.stamina_cost, 16.0)


func test_the_heavy_palm_has_a_heavy_and_a_charged_profile() -> void:
	var move := Registry.fetch(&"moves", &"palm_heavy") as MoveData
	assert_eq(Array(move.hits.keys()).size(), 2)
	# [damage, poise, posture, guard_stamina, hitstop_frames, shake, knockback]
	var want := {&"heavy": [22.0, 25.0, 22.0, 24.0, 6, 0.5, 3.0], &"charged": [34.0, 40.0, 35.0, 34.0, 6, 0.8, 5.0]}
	for name: StringName in want:
		var p := move.hits.get(name) as HitProfile
		if p == null:
			fail("hits[%s] is a HitProfile" % name)
			continue
		assert_eq([p.damage, p.poise_damage, p.posture_damage, p.guard_stamina, p.hitstop_frames, p.shake, p.knockback], want[name], str(name))
		assert_eq([p.staggers, p.impact_sound], [true, &"impact_heavy"], "%s staggers and lands heavy" % name)
	assert_eq(move.stamina_cost, 24.0)


func test_the_roll_hits_nothing() -> void:
	assert_eq((Registry.fetch(&"moves", &"dodge_roll") as MoveData).hits, {})


func test_the_clips_have_the_lengths_and_steps_the_marks_were_placed_for() -> void:
	for id: StringName in TABLE:
		assert_eq(Marks.frame_of(_clip(id).length), LENGTHS[id], "%s is %d frames long" % [id, LENGTHS[id]])
		assert_eq(_clip(id).get_meta("step_fps"), STEPS[id], "%s step" % id)


func test_marks_are_the_f0_table() -> void:
	for id: StringName in TABLE:
		_assert_marks(id, TABLE[id])


func test_the_reactions_are_registered_with_their_clips_and_marks() -> void:
	for id: StringName in REACTIONS:
		var want: Array = REACTIONS[id]
		var move := Registry.fetch(&"moves", id) as MoveData
		if move == null:
			fail("%s is a registered MoveData" % id)
			continue
		assert_eq([move.kind, move.clip, move.root_motion, move.stamina_cost, move.hits], [MoveData.Kind.REACTION, id, want[1], 0.0, {}], str(id))
		assert_eq(Marks.frame_of(_clip(id).length), want[0], "%s is %d frames long" % [id, want[0]])
		assert_eq(_clip(id).get_meta("step_fps"), 0, "%s is smooth" % id)
		_assert_marks(id, want[2])


func test_the_guard_moves_are_registered_with_their_clips_and_marks() -> void:
	for id: StringName in GUARD_MOVES:
		var want: Array = GUARD_MOVES[id]
		var move := Registry.fetch(&"moves", id) as MoveData
		if move == null:
			fail("%s is a registered MoveData" % id)
			continue
		assert_eq([move.kind, move.clip, move.root_motion, move.stamina_cost, move.hits], [MoveData.Kind.OTHER, id, want[1], 0.0, {}], str(id))
		assert_eq(Marks.frame_of(_clip(id).length), want[0], "%s is %d frames long" % [id, want[0]])
		assert_eq(_clip(id).get_meta("step_fps"), 0, "%s is smooth" % id)
		_assert_marks(id, want[2])


func test_the_guard_stance_is_a_looping_clip_and_not_a_move() -> void:
	assert_true((load(LIB) as AnimationLibrary).has_animation(&"guard_hold"), "the library has guard_hold")
	if (load(LIB) as AnimationLibrary).has_animation(&"guard_hold"):
		assert_eq(_clip(&"guard_hold").loop_mode, Animation.LOOP_LINEAR, "it loops under the walk")
		assert_eq(Marks.read(_clip(&"guard_hold")), [] as Array[Dictionary], "and has no marks: it is no move")
	assert_false(Registry.ids(&"moves").has("guard_hold"))


func test_the_catch_is_the_parry_with_the_right_hand_reaching_to_grip() -> void:
	# The catch plays the parry's span of Sword_Block over 30 frames, with the layer catch.json over it: the right
	# upper and lower arm turned about 30 degrees from f4 to f16, and nothing turned outside that.
	var layer: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/anim/layers/catch.json"))
	assert_true(layer is Dictionary, "catch.json is a layer")
	if not layer is Dictionary:
		return
	assert_eq((layer as Dictionary).keys(), ["upperarm_r", "lowerarm_r"])
	for bone: String in layer:
		var keys: Array = layer[bone]
		assert_eq([int(keys[0][0]), int(keys[keys.size() - 1][0])], [4, 16], "%s from f4 to f16" % bone)
		var most := 0.0
		for key: Array in keys:
			most = maxf(most, Vector3(key[1], key[2], key[3]).length())
		assert_near(most, 30.0, 5.0, "%s turns about 30 degrees" % bone)
		assert_eq([keys[0].slice(1), keys[keys.size() - 1].slice(1)], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]],
				"%s starts and ends at no turn, so nothing pops where the layer stops" % bone)


func _assert_marks(id: StringName, want: Array) -> void:
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
	for id in [&"palm_jab", &"palm_cross", &"palm_hook", &"palm_heavy"]:
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


func test_combat_tuning_defaults_are_the_numbers_of_the_abarax_file() -> void:
	var tuning := load("res://data/tuning/combat_abarax.tres") as CombatTuning
	assert_ne(tuning, null)
	var plain := CombatTuning.new()
	for property: Dictionary in plain.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_eq(tuning.get(property["name"]), plain.get(property["name"]), "the file and the class agree on %s" % property["name"])


func test_combat_tuning_numbers() -> void:
	var t := CombatTuning.new()
	assert_eq([t.stamina_regen_rate, t.stamina_regen_delay, t.guard_regen_scale, t.exhausted_until, t.sprint_stamina], [45.0, 0.6, 0.4, 20.0, 12.0])
	assert_eq([t.posture_regen_delay, t.posture_regen_rate, t.broken_time], [1.5, 20.0, 2.0])
	assert_eq([t.guard_arc_deg, t.guard_speed_scale, t.parry_posture_scale, t.catch_posture], [75.0, 0.45, 2.0, 50.0])
	assert_eq(t.parry_refresh_frames, 20)
	assert_eq([t.finisher_range, t.finisher_arc_deg, t.finisher_facing_deg], [1.6, 60.0, 30.0])
	assert_eq([t.aim_assist_deg, t.aim_assist_range, t.aim_turn_rate_deg], [30.0, 3.5, 540.0])
	assert_eq(t.knockback_decay, 10.0)


func test_abarax_is_defined_by_data() -> void:
	var def := Registry.fetch(&"actors", &"abarax") as ActorDef
	if def == null:
		fail("abarax is a registered ActorDef")
		return
	assert_eq(def.id, &"abarax")
	assert_eq(def.moveset, {&"palm": &"palm_jab", &"heavy": &"palm_heavy", &"dodge": &"dodge_roll", &"guard": &"guard_raise"})
	assert_eq(def.max_hp, 100.0); assert_eq(def.max_stamina, 100.0); assert_eq(def.max_posture, 100.0); assert_eq(def.poise, 10.0)
	assert_eq(def.required_clips, PackedStringArray(["idle", "walk", "jog", "sprint"]))
	assert_eq(def.locomotion, load("res://data/tuning/abarax_locomotion.tres"))
	assert_eq(def.team, ActorDef.Team.PLAYER)
	assert_eq(def.combat, load("res://data/tuning/combat_abarax.tres"))
	assert_eq(def.reactions, {&"flinch": &"flinch", &"stagger": &"stagger", &"death": &"death", &"guard_hit": &"guard_hit",
			&"guard_break": &"guard_break", &"parry": &"parry", &"parried": &"parried", &"catch": &"catch", &"caught": &"caught",
			&"posture_broken": &"posture_broken", &"getup": &"getup"}, "every reaction there is a clip for")
	assert_eq(def.finisher, load("res://data/pairs/finisher_open_hand.tres"), "the Open Hand finisher")
	assert_eq(def.grab_pair, null, "and no grab")
	assert_eq(def.surface_sound, &"surface_cloth")
	assert_eq(def.hurt_voice, &"")
	var rig := def.rig_scene.instantiate()
	assert_true(rig is Rig)
	rig.free()
	assert_eq(def.rig_scene.resource_path, "res://actors/abarax/abarax_rig.tscn")


func test_actor_def_defaults() -> void:
	var def := ActorDef.new()
	assert_eq([def.max_hp, def.max_stamina, def.max_posture, def.poise], [100.0, 100.0, 100.0, 10.0])
	assert_eq(def.required_clips, PackedStringArray(["idle", "walk", "jog", "sprint"]))
	assert_eq(def.moveset, {})
	assert_eq(ActorDef.Team.PLAYER, 0); assert_eq(ActorDef.Team.ENEMY, 1)
	assert_eq(def.team, ActorDef.Team.PLAYER)
	assert_eq(def.combat, null)
	assert_eq(def.reactions, {})
	assert_eq([def.finisher, def.grab_pair], [null, null])
	assert_eq(def.surface_sound, &"surface_cloth")
	assert_eq(def.hurt_voice, &"")


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
