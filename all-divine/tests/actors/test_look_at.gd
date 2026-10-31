extends TestCase
## Look-at: the two LookAtModifier3Ds (neck_01 at influence 0.4, then Head) that turn Abarax's head toward
## the point Rig.look_at_point gives them, no further than 70° either side of his facing and 35° up or
## down, easing in and out over 0.3 s; and the actor's choice of what to look at (the intent's look_target,
## else the nearest `poi` in view). Head yaw is the way the Head bone faces (its +Z), in degrees about up
## from the rig's facing, positive toward his left (+X).

const RIG := "res://actors/abarax/abarax_rig.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const DT := 1.0 / 60


func rig() -> Rig: return track(load(RIG).instantiate())


func _ticks(rigs: Array, n: int) -> void:
	for i in n:
		for r: Rig in rigs:
			r.tick(DT)


static func _yaw(r: Rig, bone: StringName) -> float:
	var forward := r.global_basis.inverse() * r.shown_pose(bone).basis.z
	return rad_to_deg(atan2(forward.x, forward.z))


static func _pitch(r: Rig, bone: StringName) -> float:
	var forward := (r.global_basis.inverse() * r.shown_pose(bone).basis.z).normalized()
	return rad_to_deg(asin(forward.y))


# A point `deg` degrees to the left of the rig's facing, `distance` metres from its head and `rise` metres
# above it.
static func _around(r: Rig, deg: float, distance := 3.0, rise := 0.0) -> Vector3:
	var a := deg_to_rad(deg)
	return r.bone_global(&"Head") + r.global_basis * Vector3(sin(a) * distance, rise, cos(a) * distance)


func test_rig_has_both_look_modifiers() -> void:
	var r := rig()
	var looks := r.skeleton.find_children("*", "LookAtModifier3D", false, false)
	assert_eq(looks.size(), 2)
	assert_true(r.get_node_or_null("LookTarget") is Marker3D, "the point looked at is a Marker3D under the rig")
	# Looking at nothing, both are faded out; looking at something, the neck has 0.4 and the head all of it.
	_ticks([r], 2)
	var expected := [[&"neck_01", 0.4], [&"Head", 1.0]]
	for look: LookAtModifier3D in looks:
		assert_near(look.influence, 0.0, 1e-6, "%s, looking at nothing" % look.bone_name)
	r.look_at_point(_around(r, 20.0))
	_ticks([r], 20)
	for i in looks.size():
		var look := looks[i] as LookAtModifier3D
		assert_eq(look.bone_name, String(expected[i][0]))
		assert_near(look.influence, expected[i][1], 1e-6)
		assert_eq(look.get_node(look.target_node), r.get_node("LookTarget"), "it aims at LookTarget")
		assert_near(look.duration, 0.3, 1e-6)
		assert_eq(look.transition_type, Tween.TRANS_SINE)
		assert_eq(look.ease_type, Tween.EASE_OUT)
		assert_true(look.use_angle_limitation)
		assert_true(look.symmetry_limitation)
		assert_near(rad_to_deg(look.primary_limit_angle), 140.0, 1e-3, "70° either way of yaw")
		assert_near(rad_to_deg(look.secondary_limit_angle), 70.0, 1e-3, "35° up or down")


func test_head_turns_to_target_left() -> void:
	# The rig is turned, so the look is shown to work in its own space.
	var r := rig()
	r.rotation.y = 1.0
	_ticks([r], 30)
	var point := _around(r, 45.0)
	r.look_at_point(point)
	_ticks([r], 36)
	assert_near(_yaw(r, &"Head"), 45.0, 6.0, "the head faces the target")
	assert_near(_pitch(r, &"Head"), 0.0, 6.0, "level, as the target is at head height")
	assert_eq(r.looking_at(), point, "the rig says what it looks at")


func test_head_eases_toward_the_target() -> void:
	# It turns over 0.3 s (SINE, OUT): on its way after a tick, there by 0.3 s.
	var r := rig(); var plain := clip_rig()
	_ticks([r, plain], 30)
	r.look_at_point(_around(r, 45.0))
	_ticks([r, plain], 2)
	var early := _yaw(r, &"Head") - _yaw(plain, &"Head")
	assert_true(early > 2.0 and early < 35.0, "two ticks in, the head is on its way (%.1f°)" % early)
	_ticks([r, plain], 17)
	assert_near(_yaw(r, &"Head"), 45.0, 6.0, "there by 0.3 s")


func test_neck_carries_part_of_the_turn() -> void:
	var r := rig(); var plain := clip_rig()
	_ticks([r, plain], 30)
	r.look_at_point(_around(r, 45.0))
	_ticks([r, plain], 36)
	var neck := _yaw(r, &"neck_01") - _yaw(plain, &"neck_01")
	assert_true(neck > 8.0 and neck < 35.0, "the neck turns some of the way (%.1f°)" % neck)


func test_target_behind_is_limited() -> void:
	for deg: float in [180.0, 135.0, -135.0]:
		var r := rig()
		_ticks([r], 30)
		r.look_at_point(_around(r, deg))
		var worst := 0.0
		for i in 60:
			r.tick(DT)
			worst = maxf(worst, absf(_yaw(r, &"Head")))
		assert_true(worst <= 72.0, "a target at %d°: the head turns at most 72° (%.1f°)" % [deg, worst])
		assert_true(absf(_yaw(r, &"Head")) > 55.0, "and turns as far as it may (%.1f°)" % _yaw(r, &"Head"))
		if deg != 180.0:
			assert_true(signf(_yaw(r, &"Head")) == signf(deg), "toward the side the target is on")


func test_pitch_is_limited() -> void:
	var r := rig()
	_ticks([r], 30)
	r.look_at_point(_around(r, 0.0, 1.0, -3.0))  # at his feet
	_ticks([r], 36)
	assert_true(_pitch(r, &"Head") >= -37.0, "it looks down 35° at most (%.1f°)" % _pitch(r, &"Head"))
	assert_true(_pitch(r, &"Head") < -25.0, "but does look down (%.1f°)" % _pitch(r, &"Head"))


# A rig whose look modifiers are switched off: the clips' neck and head.
func clip_rig() -> Rig:
	var r := rig()
	for look in r.skeleton.find_children("*", "LookAtModifier3D", false, false):
		(look as LookAtModifier3D).active = false
	return r


static func _turn_between(a: Rig, b: Rig, bone: StringName) -> float:
	return rad_to_deg(a.shown_pose(bone).basis.get_rotation_quaternion().angle_to(b.shown_pose(bone).basis.get_rotation_quaternion()))


func test_nothing_to_look_at_leaves_the_clip_alone() -> void:
	# Looking at nothing, the neck and head are exactly the clip's, in every clip.
	var r := rig(); var plain := clip_rig()
	for clip in [&"idle", &"jog", &"dodge_roll", &"palm_jab"]:
		for rr: Rig in [r, plain]:
			rr.play_move(clip, 0.0)
		for f in 20:
			for rr: Rig in [r, plain]:
				rr.set_move_time(f / 60.0)
				rr.tick(DT)
			for bone in [&"neck_01", &"Head"]:
				var off := _turn_between(r, plain, bone)
				if off > 0.5:
					fail("%s f%d: %s is turned %.1f° from the clip's" % [clip, f, bone, off])
					return


func test_cleared_target_returns_head() -> void:
	var r := rig(); var plain := clip_rig()
	_ticks([r, plain], 30)
	r.look_at_point(_around(r, 45.0))
	_ticks([r, plain], 36)
	assert_true(absf(_yaw(r, &"Head") - _yaw(plain, &"Head")) > 30.0, "looking away first")
	r.look_at_point(null)
	assert_eq(r.looking_at(), null)
	_ticks([r, plain], 36)
	assert_near(_yaw(r, &"Head"), _yaw(plain, &"Head"), 3.0, "back to the clip's yaw within 0.6 s")
	assert_near(_pitch(r, &"Head"), _pitch(plain, &"Head"), 3.0, "and its pitch")
	assert_true(_turn_between(r, plain, &"neck_01") < 0.5, "the neck is the clip's again (%.1f°)" % _turn_between(r, plain, &"neck_01"))
	assert_true(_turn_between(r, plain, &"Head") < 0.5, "and so is the head (%.1f°)" % _turn_between(r, plain, &"Head"))


func test_new_target_eases_rather_than_snapping() -> void:
	# From one target to another far from it, the head swings over, as it did to the first.
	var r := rig()
	_ticks([r], 30)
	r.look_at_point(_around(r, 40.0))
	_ticks([r], 36)
	r.look_at_point(_around(r, -40.0))
	r.tick(DT)
	assert_true(_yaw(r, &"Head") > 20.0, "one tick on, still near the first (%.1f°)" % _yaw(r, &"Head"))
	_ticks([r], 35)
	assert_near(_yaw(r, &"Head"), -40.0, 6.0, "then on the second")


func test_new_target_while_fading_out_eases() -> void:
	# Given a new point while the head is still easing back from the last, it swings over without a jump.
	var r := rig()
	_ticks([r], 30)
	r.look_at_point(_around(r, 40.0))
	_ticks([r], 36)
	r.look_at_point(null)
	_ticks([r], 4)
	r.look_at_point(_around(r, -40.0))
	var last := _yaw(r, &"Head")
	var fastest := 0.0
	for i in 36:
		r.tick(DT)
		fastest = maxf(fastest, absf(_yaw(r, &"Head") - last))
		last = _yaw(r, &"Head")
	assert_true(fastest < 10.0, "it turns at most %.1f° in a tick" % fastest)
	assert_near(_yaw(r, &"Head"), -40.0, 6.0, "and ends on the new point")


func test_bad_look_target_changes_nothing() -> void:
	var r := rig()
	_ticks([r], 2)
	quietly(func() -> void: r.look_at_point("over there"))
	assert_eq(r.looking_at(), null)
	r.look_at_point(_around(r, 20.0))
	var point: Variant = r.looking_at()
	quietly(func() -> void: r.look_at_point(3))
	assert_eq(r.looking_at(), point, "a bad target leaves the look as it was")


func test_moving_target_is_followed() -> void:
	# A target that moves a little each tick (someone walking past) is tracked as it goes.
	var r := rig()
	_ticks([r], 30)
	for i in 60:
		r.look_at_point(_around(r, -30.0 + i))
		r.tick(DT)
	assert_near(_yaw(r, &"Head"), 29.0, 6.0, "the head is on it at the end")


func _poi(parent: Node3D, at: Vector3) -> Node3D:
	var node := Marker3D.new()
	node.position = at
	parent.add_child(node)
	node.add_to_group(&"poi")
	return node


func test_actor_picks_nearest_poi() -> void:
	# He faces +Z. Of the points of interest, the nearest is behind him (out of view), the next is 110° to
	# his left (out of view, past 100°), one ahead is past 6 m, and of the two left in view the nearer is
	# 72° to his right.
	var arena := TestArena.make(self)
	var target := Vector3(-1.0, 1.6, 5.0)
	var brain := ScriptBrain.new([{"frames": 10}, {"frames": 10, "look_target": target}, {"frames": 10}])
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, brain)
	var behind := _poi(arena, Vector3(0.0, 1.5, -2.0))  # 2.5 m
	var too_wide := _poi(arena, Vector3(2.5, 1.5, -0.91))  # 3.05 m, 110°
	var too_far := _poi(arena, Vector3(0.0, 1.5, 6.5))  # 6.7 m
	var right := _poi(arena, Vector3(-3.0, 1.5, 1.0))  # 3.5 m, -72°
	var ahead_left := _poi(arena, Vector3(2.0, 1.5, 4.0))  # 4.7 m, 27°
	await frames(5)
	assert_eq(actor.look_target, right.global_position, "the nearest in range and in view")
	assert_eq(actor.rig.looking_at(), right.global_position, "and the rig looks there")
	await frames(10)
	assert_eq(actor.look_target, target, "the intent's look_target comes first")
	await frames(10)
	assert_eq(actor.look_target, right.global_position, "then back to the point of interest")
	right.queue_free()
	await frames(2)
	assert_eq(actor.look_target, ahead_left.global_position, "the next nearest")
	for node: Node3D in [behind, too_wide, too_far, ahead_left]:
		node.remove_from_group(&"poi")
	await frames(2)
	assert_eq(actor.look_target, null, "none left: he looks at nothing")
	assert_eq(actor.rig.looking_at(), null)


func test_actor_does_not_look_at_itself() -> void:
	# An actor can be a point of interest to others; it never picks itself.
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, Brain.new())
	actor.add_to_group(&"poi")
	await frames(3)
	assert_eq(actor.look_target, null)
