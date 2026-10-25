extends TestCase
## Locomotion on its own, with no scene: how fast the body gets going, stops and turns. It uses the
## plan's reference tuning (walk 1.6, jog 4.0, sprint 6.0 m/s; accel 18 and decel 24 m/s²; 720°/s),
## not Abarax's (whose speeds are his clips' ground speeds), and one tick per 60 Hz frame.

const DT := 1.0 / 60


func _loco() -> Locomotion:
	var tuning := LocomotionTuning.new()
	tuning.walk_speed = 1.6
	tuning.jog_speed = 4.0
	tuning.sprint_speed = 6.0
	tuning.accel = 18.0
	tuning.decel = 24.0
	tuning.turn_rate_deg = 720.0
	tuning.walk_threshold = 0.5
	var loco := Locomotion.new()
	loco.tuning = tuning
	return loco


func test_reaches_jog_in_fourteen_frames() -> void:
	var loco := _loco()
	var speeds: Array[float] = []
	var first := Vector3.ZERO
	for f in 20:
		var v := loco.tick(Vector2(0, 1), false, DT)
		if f == 0:
			first = v
		speeds.append(loco.speed)
	assert_true(speeds[12] < 3.99, "frame 13 is still below jog: %s" % speeds[12])
	assert_true(speeds[13] >= 3.99, "frame 14 is at jog: %s" % speeds[13])
	assert_near(speeds[19], 4.0, 1e-9, "and stays there")
	assert_vec_near(first, Vector3(0, 0, 0.3), 1e-9, "the first frame already heads along the stick, at accel × dt")


func test_stops_in_about_ten_frames() -> void:
	var loco := _loco()
	for f in 30:
		loco.tick(Vector2(1, 0), false, DT)
	assert_near(loco.speed, 4.0, 1e-9, "jogging")
	var stopped := -1
	for f in range(1, 31):
		var v := loco.tick(Vector2.ZERO, false, DT)
		if loco.speed > 0.0:
			assert_vec_near(v.normalized(), Vector3(1, 0, 0), 1e-6, "frame %d slows along the way it went" % f)
		elif stopped < 0:
			stopped = f
	assert_true(absi(stopped - 10) <= 1, "stopped on frame %d" % stopped)
	assert_near(loco.speed, 0.0, 0.0, "and stays stopped")


func test_light_tilt_walks() -> void:
	var loco := _loco()
	var tilt := Inputs.shape_stick(Vector2(0.4, 0))
	assert_near(tilt.length(), 0.25, 1e-6, "a 0.4 push is 0.25 once the deadzone is out")
	assert_near(loco.target_speed(tilt.length(), false), 0.8, 1e-6)
	for f in 60:
		loco.tick(tilt, false, DT)
	assert_near(loco.speed, 0.8, 1e-6)
	assert_near(loco.target_speed(0.5, false), 1.6, 1e-9, "walk_speed at walk_threshold")
	assert_near(loco.target_speed(0.51, false), 4.0, 1e-9, "jog past it")


func test_turns_half_circle_in_fifteen_frames() -> void:
	var loco := _loco()
	assert_eq(loco.facing_yaw, 0.0, "starts facing +Z")
	var reached := -1
	for f in range(1, 31):
		var v := loco.tick(Vector2(0, -1), false, DT)
		if f == 1:
			assert_true(v.z < 0.0 and is_zero_approx(v.x), "the body heads the new way at once: %s" % v)
		if reached < 0 and absf(angle_difference(loco.facing_yaw, PI)) < 1e-4:
			reached = f
	assert_true(absi(reached - 15) <= 1, "faced the other way on frame %d" % reached)


func test_sprint_only_when_held_and_moving() -> void:
	var loco := _loco()
	assert_near(loco.target_speed(1.0, true), 6.0, 1e-9)
	assert_near(loco.target_speed(1.0, false), 4.0, 1e-9)
	assert_near(loco.target_speed(0.3, true), 0.96, 1e-9, "held, but a light tilt walks")
	loco.tick(Vector2.ZERO, true, DT)
	assert_false(loco.sprinting, "held while standing")
	loco.tick(Vector2(0.3, 0), true, DT)
	assert_false(loco.sprinting, "held while walking")
	for f in 40:
		loco.tick(Vector2(1, 0), true, DT)
	assert_true(loco.sprinting)
	assert_near(loco.speed, 6.0, 1e-9)
	for f in 40:
		loco.tick(Vector2(1, 0), false, DT)
	assert_false(loco.sprinting, "let go")
	assert_near(loco.speed, 4.0, 1e-9, "back down to jog")


func test_yaw_of_faces_the_direction() -> void:
	assert_near(Locomotion.yaw_of(Vector2(0, 1)), 0.0, 1e-9, "+Z is yaw 0")
	assert_near(Locomotion.yaw_of(Vector2(1, 0)), PI / 2, 1e-9)
	assert_near(absf(Locomotion.yaw_of(Vector2(0, -1))), PI, 1e-9)
	for dir in [Vector2(1, 0), Vector2(-0.6, 0.8), Vector2(0.28, -0.96)]:
		var front := Basis(Vector3.UP, Locomotion.yaw_of(dir)) * Vector3.MODEL_FRONT
		assert_vec_near(front, Vector3(dir.x, 0, dir.y), 1e-6, "a body turned to yaw_of(%s) faces it" % dir)


func test_facing_turns_only_with_input() -> void:
	var loco := _loco()
	for f in 10:
		loco.tick(Vector2(1, 0), false, DT)
	var yaw := loco.facing_yaw
	for f in 30:
		loco.tick(Vector2.ZERO, false, DT)
	assert_eq(loco.facing_yaw, yaw)


func test_carry_takes_over_a_velocity() -> void:
	# A move's root motion hands its velocity over, so locomotion carries on from it and slows along it.
	var loco := _loco()
	loco.carry(Vector3(0, -3.0, 2.0))
	assert_near(loco.speed, 2.0, 1e-9, "the horizontal part")
	assert_false(loco.sprinting)
	var v := loco.tick(Vector2.ZERO, false, DT)
	assert_vec_near(v, Vector3(0, 0, 1.6), 1e-9, "slowing by decel along +Z")
