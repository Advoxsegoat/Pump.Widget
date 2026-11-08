extends TestCase
## The Knuckle's moves (data/moves/knuckle_*.tres): their numbers, their tells, and how their clips move. Each attack's
## hitbox comes on within one 12 fps step (5 frames) of the frame its striking bone (the hitbox's bone) reaches
## furthest forward, and no knuckle clip pops (ClipMotion: the pelvis and head 0.25 m a step at most, the hands and feet
## across joins), as F1 Task 10 measured its finisher: the owner's first priority is graphics that match the actions.

const RIG := "res://actors/knuckle/knuckle_rig.tscn"
const TIERS := ["res://data/actors/knuckle_1.tres", "res://data/actors/knuckle_2.tres", "res://data/actors/knuckle_3.tres"]
const MOVESET := {&"palm": &"knuckle_jab", &"heavy": &"knuckle_thrust", &"gift": &"knuckle_sweep",
		&"interact": &"knuckle_grab", &"dodge": &"knuckle_feint"}
const O := MoveData.Kind
const P := HitProfile.Perilous
## Each move: its kind, and its profiles' damage, poise, posture and guard stamina damage, hit-stop, height and peril.
const MOVES := {
	&"knuckle_jab": [O.ATTACK, [10.0, 6.0, 6.0, 10.0, 3, HitProfile.Height.MID, P.NONE]],
	&"knuckle_cross": [O.ATTACK, [12.0, 8.0, 8.0, 12.0, 4, HitProfile.Height.MID, P.NONE]],
	&"knuckle_hook": [O.ATTACK, [15.0, 12.0, 12.0, 15.0, 5, HitProfile.Height.MID, P.NONE]],
	&"knuckle_hook_2": [O.ATTACK, [15.0, 12.0, 12.0, 15.0, 5, HitProfile.Height.MID, P.NONE]],
	&"knuckle_sweep": [O.ATTACK, [20.0, 20.0, 15.0, 0.0, 5, HitProfile.Height.LOW, P.SWEEP]],
	&"knuckle_thrust": [O.ATTACK, [24.0, 20.0, 25.0, 0.0, 6, HitProfile.Height.MID, P.THRUST]],
	&"knuckle_grab": [O.ATTACK, [0.0, 0.0, 0.0, 0.0, 4, HitProfile.Height.MID, P.GRAB]],
	&"knuckle_feint": [O.OTHER, []],
}
## The step a hitbox may come on either side of its bone's furthest reach.
const CONTACT_SLACK := 5


func _rig() -> Rig:
	var rig := (load(RIG) as PackedScene).instantiate() as Rig
	track(rig)
	return rig


func test_the_knuckles_moves_have_their_numbers() -> void:
	for id: StringName in MOVES:
		var move := Registry.fetch(&"moves", id) as MoveData
		assert_ne(move, null, "%s is a move" % id)
		if move == null:
			continue
		assert_eq(move.kind, MOVES[id][0], "%s's kind" % id)
		assert_eq(move.clip, id, "%s plays its own clip" % id)
		var want: Array = MOVES[id][1]
		assert_eq(move.hits.size(), 0 if want.is_empty() else 1, "%s's profiles" % id)
		for profile: HitProfile in move.hits.values():
			assert_eq([profile.damage, profile.poise_damage, profile.posture_damage, profile.guard_stamina,
					profile.hitstop_frames, profile.height, profile.perilous], want, "%s's numbers" % id)


func test_the_tiers_share_the_moveset() -> void:
	for path: String in TIERS:
		assert_eq((load(path) as ActorDef).moveset, MOVESET, "%s's moveset" % path)


func test_every_knuckle_attack_strikes_at_its_furthest_reach() -> void:
	var rig := _rig()
	var checked := 0
	for id: StringName in MOVES:
		var move := Registry.fetch(&"moves", id) as MoveData
		if move == null or move.kind != O.ATTACK:
			continue
		for m in Marks.read(rig.tree.get_animation(move.clip)):
			if m["kind"] != &"hitbox_on":
				continue
			var hitbox := StringName(m["args"]["id"])
			var bone := StringName((rig.get_node(NodePath("Hitboxes/%s" % hitbox)) as BoneAttachment3D).bone_name)
			var peak: Array = ClipMotion.reach_peak(rig, move.clip, bone)
			var on := Marks.frame_of(m["time"])
			assert_true(absi(on - peak[0]) <= CONTACT_SLACK, "%s: %s comes on at f%d, its %s reaches furthest (%.2f m) at f%d"
					% [id, hitbox, on, bone, peak[1], peak[0]])
			checked += 1
	assert_eq(checked, 7, "every attack's hitbox was checked")


func test_no_knuckle_clip_pops() -> void:
	var rig := _rig()
	var clips := Array(rig.tree.get_animation_list()).filter(func(c: StringName) -> bool: return String(c).begins_with("knuckle_"))
	assert_true(clips.size() >= 9, "the knuckle's clips (%d)" % clips.size())
	for clip: StringName in clips:
		var worst: Array = ClipMotion.worst_pop(rig, clip)
		assert_true(worst[0] <= worst[3], "%s: the %s moves %.3f m to f%d (at most %.2f)" % [clip, worst[1], worst[0], worst[2], worst[3]])
		var limb: Array = ClipMotion.worst_join(rig, clip)
		assert_true(limb[0] <= limb[3], "%s: across a join the %s moves %.3f m to f%d (at most %.2f)" % [clip, limb[1], limb[0], limb[2], limb[3]])


func test_the_clip_checker_passes_every_tier() -> void:
	# The enemy rules among them: every attack has a tell at least 12 frames before its first hitbox_on, and a perilous
	# one a perilous tell.
	for path: String in TIERS:
		assert_eq(ClipChecker.new().check_actor(load(path) as ActorDef), PackedStringArray(), path)
