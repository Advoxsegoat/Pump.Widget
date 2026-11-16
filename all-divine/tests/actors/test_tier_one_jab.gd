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
## The least a bone of the body turns between two drawn poses of the wind-up for it to count as moving (degrees). The jab's own wind-up
## moves 1.1, 2.5 and 2.5 degrees on its three steps.
const MOVES_AT_LEAST := 0.6


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


func test_the_long_jabs_windup_moves_on_every_drawn_pose() -> void:
	# The clip is shown stepped at 12 fps: the poses drawn before the blow are those at 0, 1/12, 2/12, ... of its seconds, and no two of
	# them in a row may be the same (not a pose held for two steps: that is a sticky wind-up).
	var anim := _clip(&"knuckle_jab_long")
	assert_eq(int(anim.get_meta(&"step_fps", 0)), 12, "it is a stepped clip like the jab")
	var blow := _frame_of(&"knuckle_jab_long", &"hitbox_on")
	var steps := blow / 5
	assert_eq(steps, 5, "five drawn poses to the blow")
	var previous := {}
	for k in steps:
		var pose := {}
		for i in anim.get_track_count():
			if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				pose[i] = anim.rotation_track_interpolate(i, k / 12.0)
		if not previous.is_empty():
			var turned := 0.0
			for i: int in pose:
				turned = maxf(turned, rad_to_deg((pose[i] as Quaternion).angle_to(previous[i])))
			assert_true(turned >= MOVES_AT_LEAST, "pose %d is not the one before it: the most any bone turns is %.2f degrees (at least %.2f)" % [k, turned, MOVES_AT_LEAST])
		previous = pose


func test_there_are_sixty_eight_moves_and_the_checker_passes_them_all() -> void:
	assert_eq(Registry.ids(&"moves").size(), 68, "the library's moves")
	var problems := ClipChecker.new().check_all()
	assert_eq(problems, PackedStringArray(), "the clip checker is clean: %s" % "\n".join(problems))


func test_tier_one_has_no_brain_that_imitates_the_jab() -> void:
	# The feint imitates the jab (`knuckle_feint`, imitates knuckle_jab): tier I's brain does not feint today, so the long jab has no
	# imitation to keep in step. If it ever does, its feint must show the long jab's tell.
	var brain: BrainDef = (load(TIER_ONE) as ActorDef).brain
	assert_eq(brain.feint_chance, 0.0, "tier I does not feint")
