extends TestCase
## Breathing (actors/liveliness/breathing.gd): the chest rises and falls, slowly at rest and faster after
## exertion, which fades over six seconds; sprinting exerts. Headless: Rig.tick runs the skeleton's
## modifiers itself, so the pose a tick shows (Rig.shown_pose) is read straight after it.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const DT := 1.0 / 60


func rig() -> Rig: return track(load(RIG).instantiate())


func test_rate_range() -> void:
	assert_near(Breathing.rate(0.0), 0.25, 1e-9)
	assert_near(Breathing.rate(1.0), 0.6, 1e-9)
	assert_near(Breathing.rate(0.5), 0.425, 1e-9)
	assert_near(Breathing.rate(2.0), 0.6, 1e-9, "exertion past 1 is 1")
	assert_near(Breathing.rate(-1.0), 0.25, 1e-9)


func test_idle_period_is_four_seconds() -> void:
	assert_near(_period(0.0), 4.0, 0.1, "0.25 Hz at rest")
	assert_near(_period(1.0), 1.0 / 0.6, 0.1, "0.6 Hz fully exerted")


func test_exertion_decays_over_six_seconds() -> void:
	var r := rig()
	r.set_exertion(1.0)
	assert_near(r.breathing.exertion, 1.0, 1e-9)
	for i in 180:
		r.tick(DT)
	assert_near(r.breathing.exertion, 0.5, 0.01, "half gone in three seconds")
	for i in 180:
		r.tick(DT)
	assert_near(r.breathing.exertion, 0.0, 0.01, "gone in six")
	for i in 60:
		r.tick(DT)
	assert_eq(r.breathing.exertion, 0.0, "and it stays at rest")


func test_breath_lifts_the_chest_and_shoulders() -> void:
	# Against a rig that does not breathe, ticked alike. At 0.25 Hz the breath tops out one second in
	# (sin = 1) and bottoms out at three (sin = -1).
	var r := rig(); var still := rig()
	still.breathing.active = false
	for i in 60:
		r.tick(DT); still.tick(DT)
	assert_near(_tilt(r, still, &"spine_02"), 1.5, 0.1, "spine_02 pitches back by amplitude_deg")
	assert_near(_tilt(r, still, &"spine_03"), 2.4, 0.1, "spine_03 adds 0.6 of it")
	assert_near(_tilt(r, still, &"pelvis"), 0.0, 1e-3, "the hips are left alone")
	for side in [&"l", &"r"]:
		var clavicle := StringName("clavicle_" + side)
		assert_near(_own_turn(r, still, clavicle), 0.75, 0.05, "%s turns by 0.5 of it" % clavicle)
		assert_true(_shoulder_rise(r, still, side) > 0.001, "and lifts its shoulder (%s m)" % _shoulder_rise(r, still, side))
	for i in 120:
		r.tick(DT); still.tick(DT)
	assert_near(_tilt(r, still, &"spine_02"), -1.5, 0.1, "out-breath: it pitches forward")
	assert_true(_shoulder_rise(r, still, &"l") < -0.001, "and the shoulders drop")


func test_modifiers_run_once_per_tick() -> void:
	# The skeleton runs its modifiers inside Rig.tick, with the tick's delta; its own end-of-frame update
	# must not run them again. Sixty ticks spread over sixty physics frames are one second of breath.
	var r := rig()
	for i in 60:
		r.tick(DT)
		await frames(1)
	assert_near(r.breathing.phase, PI / 2, 1e-4)
	# And a tick of 0 shows the same breath without moving it on.
	var before := r.shown_pose(&"spine_03")
	r.tick(0.0)
	assert_near(r.breathing.phase, PI / 2, 1e-4)
	assert_true(r.shown_pose(&"spine_03").is_equal_approx(before), "a zero tick changes nothing")


func test_sprinting_exerts() -> void:
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 30, "move": Vector2(0, 1), "hold": [&"dodge"]}, {"frames": 60}])
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, brain)
	await frames(20)
	assert_true(actor.locomotion.sprinting, "holding dodge with the stick pushed sprints")
	assert_true(actor.rig.breathing.exertion > 0.99, "exertion is 1 while sprinting (%s)" % actor.rig.breathing.exertion)
	while not brain.done():
		await frames(1)
	assert_true(actor.rig.breathing.exertion < 0.9 and actor.rig.breathing.exertion > 0.8,
		"and fades once he stops (%s after a second)" % actor.rig.breathing.exertion)


# The breath's period at `exertion`, in seconds, from where sin(phase) crosses zero over ten seconds of
# 60 Hz steps.
func _period(exertion: float) -> float:
	var phase := 0.0
	var crossings: Array[float] = []
	for i in 600:
		var before := sin(phase)
		phase = Breathing.step(phase, exertion, DT)
		var after := sin(phase)
		if (before < 0.0) != (after < 0.0):
			crossings.append((i + before / (before - after)) * DT)
	if crossings.size() < 3:
		fail("only %d zero crossings" % crossings.size())
		return 0.0
	# Crossings are half a period apart.
	return 2.0 * (crossings[-1] - crossings[0]) / (crossings.size() - 1)


# How many degrees further back `bone` leans on `r` than on `ref`: the angle between the two bones' up
# (+Y) in their rigs' space, negative when `r`'s leans forward.
func _tilt(r: Rig, ref: Rig, bone: StringName) -> float:
	var up := r.global_basis.inverse() * r.shown_pose(bone).basis.y
	var ref_up := ref.global_basis.inverse() * ref.shown_pose(bone).basis.y
	var angle := rad_to_deg(up.angle_to(ref_up))
	return angle if up.z <= ref_up.z else -angle


# How many degrees `bone` turns against its parent on `r` more than on `ref`.
func _own_turn(r: Rig, ref: Rig, bone: StringName) -> float:
	var parent := r.skeleton.get_bone_name(r.skeleton.get_bone_parent(r.skeleton.find_bone(bone)))
	var mine := (r.shown_pose(parent).basis.inverse() * r.shown_pose(bone).basis).get_rotation_quaternion()
	var theirs := (ref.shown_pose(parent).basis.inverse() * ref.shown_pose(bone).basis).get_rotation_quaternion()
	return rad_to_deg(mine.angle_to(theirs))


# How much higher the shoulder joint (upperarm_<side>) sits on `r` than on `ref`, in metres, in the chest's
# (spine_03's) own frame, so the chest's own breath is left out.
func _shoulder_rise(r: Rig, ref: Rig, side: StringName) -> float:
	var arm := StringName("upperarm_" + side)
	var mine := r.shown_pose(&"spine_03").affine_inverse() * r.shown_pose(arm).origin
	var theirs := ref.shown_pose(&"spine_03").affine_inverse() * ref.shown_pose(arm).origin
	var up := (r.shown_pose(&"spine_03").basis.inverse() * r.global_basis.y).normalized()
	return (mine - theirs).dot(up)
