extends TestCase
## The tier I Knuckle's jab gives a longer warning (Task 17, the owner's "3.A" of Nov 16): `knuckle_jab_long` is the same jab whose
## wind-up takes 5 frames more, so from the glint to the blow it is 20 frames, not 15. Tier I only: tiers II and III and the Drummer keep
## `knuckle_jab` at 15. Everything after the blow is the jab's own (its hit profile, its cancel into the cross, its recovery), and the
## added time is in the drawing back, which moves on every drawn pose (a clip stepped at 12 fps shows a pose for 5 frames): nothing held
## still, since the owner's standing wish is that nothing looks robotic or sticky.
## These read the clips' marks and poses from the library's files; no rig is made.

const TIER_ONE := "res://data/actors/knuckle_1.tres"
const OTHERS := ["res://data/actors/knuckle_2.tres", "res://data/actors/knuckle_3.tres"]
const DRUMMER := "res://data/actors/knuckle_drummer.tres"
## What the lead arm's drawing back must do (degrees; fix round 1, I1): turn this much between every two drawn poses of the wind-up, and this
## much from the tell to the last pose before the blow. The source's quiet guard, stretched, turns 0.7 to 2.1 degrees a step.
const STEP_AT_LEAST := 5.0
const DRAWN_BACK_AT_LEAST := 20.0


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


func _clip(id: StringName) -> Animation:
	return load("res://assets/anim/abarax/%s.tres" % _move(id).clip) as Animation


# The frame of the first mark of `kind` in the clip of move `id`, or -1.
func _frame_of(id: StringName, kind: StringName) -> int:
	for m in Marks.read(_clip(id)):
		if m["kind"] == kind:
			return Marks.frame_of(m["time"])
	return -1


func _tell_to_blow(id: StringName) -> int:
	return _frame_of(id, &"hitbox_on") - _frame_of(id, &"tell")


func test_tier_one_jab_is_twenty_frames_from_the_glint_to_the_blow_and_the_others_fifteen() -> void:
	var tier_one := load(TIER_ONE) as ActorDef
	assert_eq(tier_one.moveset[&"palm"], &"knuckle_jab_long", "tier I's palm is the long jab")
	assert_eq(_tell_to_blow(&"knuckle_jab_long"), 20, "tier I's jab: 20 frames from its tell to its blow")
	for path: String in OTHERS:
		assert_eq((load(path) as ActorDef).moveset[&"palm"], &"knuckle_jab", "%s keeps the jab" % path)
	assert_eq((load(DRUMMER) as ActorDef).moveset[&"heavy"], &"knuckle_jab", "the Drummer keeps the jab")
	assert_eq(_tell_to_blow(&"knuckle_jab"), 15, "II's, III's and the Drummer's jab: 15 frames")


func test_the_long_jab_is_the_jabs_own_from_the_blow_on() -> void:
	var jab := _move(&"knuckle_jab")
	var long := _move(&"knuckle_jab_long")
	assert_ne(long, null, "the long jab is a move")
	if long == null:
		return
	assert_eq(long.clip, &"knuckle_jab_long", "with a clip of its own")
	assert_eq(long.kind, jab.kind, "kind")
	assert_eq(long.strike_distance, jab.strike_distance, "strike distance")
	assert_eq(long.stamina_cost, jab.stamina_cost, "stamina")
	assert_eq(long.hits.keys(), jab.hits.keys(), "profile names")
	for name: StringName in jab.hits:
		var a: HitProfile = jab.hits[name]
		var b: HitProfile = long.hits[name]
		assert_eq([b.damage, b.poise_damage, b.posture_damage, b.guard_stamina, b.knockback, b.hitstop_frames, b.height, b.line, b.perilous],
				[a.damage, a.poise_damage, a.posture_damage, a.guard_stamina, a.knockback, a.hitstop_frames, a.height, a.line, a.perilous], "profile %s" % name)
	var a_blow := _frame_of(&"knuckle_jab", &"hitbox_on")
	var b_blow := _frame_of(&"knuckle_jab_long", &"hitbox_on")
	assert_eq(b_blow - a_blow, 5, "the blow comes 5 frames later")
	assert_eq(Marks.frame_of(_clip(&"knuckle_jab_long").length) - Marks.frame_of(_clip(&"knuckle_jab").length), 5, "and the clip is 5 frames longer")
	# every mark from the blow on is the jab's, 5 frames on: the same kinds, arguments (the cancel into the cross) and order
	var after_a := Marks.read(_clip(&"knuckle_jab")).filter(func(m: Dictionary) -> bool: return Marks.frame_of(m["time"]) >= a_blow)
	var after_b := Marks.read(_clip(&"knuckle_jab_long")).filter(func(m: Dictionary) -> bool: return Marks.frame_of(m["time"]) >= b_blow)
	assert_eq(after_b.size(), after_a.size(), "the same marks after the blow")
	for i in mini(after_a.size(), after_b.size()):
		assert_eq(after_b[i]["kind"], after_a[i]["kind"], "mark %d's kind" % i)
		assert_eq(after_b[i]["args"], after_a[i]["args"], "mark %d's arguments" % i)
		assert_eq(Marks.frame_of(after_b[i]["time"]) - b_blow, Marks.frame_of(after_a[i]["time"]) - a_blow, "mark %d's distance from the blow" % i)


func test_the_poses_from_the_blow_on_are_the_jabs_own_five_frames_on() -> void:
	# Fix round 1 (I1): the keyed layer is nothing at the blow (f25) and after it, so every bone is where the jab has it, five frames earlier.
	var jab := _clip(&"knuckle_jab")
	var long := _clip(&"knuckle_jab_long")
	var worst := 0.0
	for i in long.get_track_count():
		if long.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var j := jab.find_track(long.track_get_path(i), Animation.TYPE_ROTATION_3D)
		if j < 0:
			continue
		for f in range(25, Marks.frame_of(long.length) + 1, 5):
			var a: Quaternion = long.rotation_track_interpolate(i, f / 60.0)
			var b: Quaternion = jab.rotation_track_interpolate(j, (f - 5) / 60.0)
			worst = maxf(worst, rad_to_deg(a.angle_to(b)))
	print("JABPOSE worst post-blow difference %.3f degrees" % worst)
	assert_true(worst < 2.0, "from the blow on no bone is more than two degrees (the warp's own, 1.1 measured) from the jab's pose five frames earlier: %.3f" % worst)


func _bone_track(anim: Animation, bone: String) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D and String(anim.track_get_path(i)).ends_with(":" + bone):
			return i
	return -1


func test_the_long_jabs_windup_is_a_drawing_back_on_every_drawn_pose() -> void:
	# The clip is shown stepped at 12 fps: a pose is held for 5 frames, so what a player sees of the wind-up is the poses drawn from the
	# tell to the blow (f5, f10, f15, f20, then the blow at f25). Fix round 1 (I1): a threshold under a degree let the source's quiet guard,
	# stretched, pass as a wind-up; the lead arm (the upper or the lower, whichever the keyed layer turns) now turns at least STEP_AT_LEAST
	# between every two drawn poses, DRAWN_BACK_AT_LEAST in all, and the hand goes AWAY from the target while it does.
	var anim := _clip(&"knuckle_jab_long")
	assert_eq(int(anim.get_meta(&"step_fps", 0)), 12, "it is a stepped clip like the jab")
	var tell := _frame_of(&"knuckle_jab_long", &"tell")
	var blow := _frame_of(&"knuckle_jab_long", &"hitbox_on")
	assert_eq([tell, blow], [5, 25], "the tell at f5 and the blow at f25")
	var drawn := range(tell, blow, 5)
	assert_eq(drawn, [5, 10, 15, 20], "four drawn poses from the tell to the blow")
	var turned_ok := []
	for bone in ["upperarm_l", "lowerarm_l"]:
		var i := _bone_track(anim, bone)
		assert_true(i >= 0, "%s has a rotation track" % bone)
		var steps := []
		for k in range(1, drawn.size()):
			var a: Quaternion = anim.rotation_track_interpolate(i, drawn[k - 1] / 60.0)
			var b: Quaternion = anim.rotation_track_interpolate(i, drawn[k] / 60.0)
			steps.append(rad_to_deg(a.angle_to(b)))
		var whole := rad_to_deg((anim.rotation_track_interpolate(i, drawn[0] / 60.0) as Quaternion).angle_to(anim.rotation_track_interpolate(i, drawn[-1] / 60.0)))
		print("JABPOSE %s steps %s whole %.1f" % [bone, steps.map(func(d: float) -> String: return "%.1f" % d), whole])
		turned_ok.append(steps.all(func(d: float) -> bool: return d >= STEP_AT_LEAST) and whole >= DRAWN_BACK_AT_LEAST)
	assert_true(turned_ok.has(true), "the lead arm turns at least %.0f degrees between every two drawn poses and %.0f in all (upper arm, lower arm: %s)" % [STEP_AT_LEAST, DRAWN_BACK_AT_LEAST, turned_ok])
	# and it is a drawing back: the lead hand's distance to a target a metre and a half ahead grows from the tell to the last pose before the blow
	var rig := (load(TIER_ONE) as ActorDef).rig_scene.instantiate() as Rig
	track(rig)
	var joints: Array[StringName] = [&"hand_l"]
	var poses := ClipMotion.poses(rig, &"knuckle_jab_long", joints)
	var target := Vector3(0.0, 1.2, 1.5)
	var from_tell := ((poses[tell] as Dictionary)[&"hand_l"] as Vector3).distance_to(target)
	var last := ((poses[drawn[-1]] as Dictionary)[&"hand_l"] as Vector3).distance_to(target)
	assert_true(last > from_tell + 0.03, "the hand is further from the target at f%d (%.3f m) than at the tell (%.3f m)" % [drawn[-1], last, from_tell])


func test_there_are_sixty_eight_moves_and_the_checker_passes_them_all() -> void:
	assert_eq(Registry.ids(&"moves").size(), 68, "the library's moves")
	var problems := ClipChecker.new().check_all()
	assert_eq(problems, PackedStringArray(), "the clip checker is clean: %s" % "\n".join(problems))


func test_tier_one_has_no_brain_that_imitates_the_jab() -> void:
	# The feint imitates the jab (`knuckle_feint`, imitates knuckle_jab): tier I's brain does not feint today, so the long jab has no
	# imitation to keep in step. If it ever does, its feint must show the long jab's tell.
	var brain: BrainDef = (load(TIER_ONE) as ActorDef).brain
	assert_eq(brain.feint_chance, 0.0, "tier I does not feint")
