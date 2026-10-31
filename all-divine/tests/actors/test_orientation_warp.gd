extends TestCase
## Orientation warping (actors/liveliness/orientation_warp.gd). Abarax has only forward locomotion clips,
## so when he moves at an angle to the way he faces, his hips turn toward the way he goes and his spine
## turns back, which keeps his chest on his facing. Past 110° the cycle plays in reverse and his hips turn
## toward the opposite of his path. Headless: Rig.tick runs the skeleton's modifiers itself, so the
## pose a tick shows (Rig.shown_pose) is read straight after it.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const DT := 1.0 / 60


func rig() -> Rig: return track(load(RIG).instantiate())


func test_solve_table() -> void:
	var m := deg_to_rad(70.0)
	assert_near(OrientationWarp.solve(0.0, m).warp, 0.0, 1e-6)
	assert_false(OrientationWarp.solve(0.0, m).backward)
	assert_near(OrientationWarp.solve(deg_to_rad(45), m).warp, deg_to_rad(45), 1e-6)
	assert_near(OrientationWarp.solve(deg_to_rad(-45), m).warp, deg_to_rad(-45), 1e-6)
	assert_near(OrientationWarp.solve(deg_to_rad(90), m).warp, m, 1e-6)
	var b := OrientationWarp.solve(PI, m); assert_true(b.backward); assert_near(b.warp, 0.0, 1e-6)
	var c := OrientationWarp.solve(deg_to_rad(150), m); assert_true(c.backward); assert_near(c.warp, deg_to_rad(-30), 1e-5)
	# The edges and the other side.
	var edge := OrientationWarp.solve(deg_to_rad(110), m)
	assert_false(edge.backward, "110° is still forward"); assert_near(edge.warp, m, 1e-6)
	var past := OrientationWarp.solve(deg_to_rad(115), m)
	assert_true(past.backward); assert_near(past.warp, deg_to_rad(-65), 1e-5)
	var d := OrientationWarp.solve(deg_to_rad(-150), m); assert_true(d.backward); assert_near(d.warp, deg_to_rad(30), 1e-5)
	var e := OrientationWarp.solve(-PI, m); assert_true(e.backward); assert_near(e.warp, 0.0, 1e-6)
	var wrapped := OrientationWarp.solve(deg_to_rad(270), m)
	assert_false(wrapped.backward, "270° is -90°"); assert_near(wrapped.warp, -m, 1e-5)


func test_pose_turns_hips_and_keeps_chest() -> void:
	# The idle clip stands a little turned (about -13° at the hips), so each bone's yaw is read against
	# the same bone on a rig with no warp, ticked alike. The warped rig is turned itself, so the warp is
	# shown to act in the rig's own space.
	var warped := rig(); var plain := rig()
	warped.rotation.y = 1.0
	assert_false(warped.set_strafe(deg_to_rad(45)))
	for i in 20:
		warped.tick(DT); plain.tick(DT)
	assert_near(_turn(warped, plain, &"pelvis"), 45.0, 2.0, "the hips turn toward the path")
	assert_near(_turn(warped, plain, &"spine_01"), 27.0, 2.0, "the spine turns back 40% of it...")
	assert_near(_turn(warped, plain, &"spine_02"), 13.5, 2.0, "...30%...")
	assert_near(_turn(warped, plain, &"spine_03"), 0.0, 3.0, "...and 30%: the chest stays on the facing")
	assert_near(_turn(warped, plain, &"Head"), 0.0, 3.0)


func test_warp_is_clamped_and_turns_either_way() -> void:
	var warped := rig(); var plain := rig()
	warped.set_strafe(deg_to_rad(-90))
	for i in 20:
		warped.tick(DT); plain.tick(DT)
	assert_near(_turn(warped, plain, &"pelvis"), -70.0, 2.0, "clamped to max_angle_deg")
	assert_near(_turn(warped, plain, &"spine_03"), 0.0, 3.0)
	warped.set_strafe(deg_to_rad(150))
	for i in 20:
		warped.tick(DT); plain.tick(DT)
	assert_near(_turn(warped, plain, &"pelvis"), -30.0, 2.0, "backward at 150°: the hips face 150° - 180°")


func test_warp_eases_rather_than_snapping() -> void:
	var warped := rig(); var plain := rig()
	warped.set_strafe(deg_to_rad(45))
	warped.tick(DT); plain.tick(DT)
	var first := _turn(warped, plain, &"pelvis")
	assert_true(first > 5.0 and first < 30.0, "one tick in, the hips are on their way (%.1f°)" % first)
	for i in 4:
		warped.tick(DT); plain.tick(DT)
	assert_true(_turn(warped, plain, &"pelvis") > first, "and still turning")
	assert_near(warped.warp.current, deg_to_rad(45), deg_to_rad(10), "the warp being shown")


func test_warp_gives_way_to_a_move() -> void:
	# The move layer shows a clip's whole body; the warp is for locomotion and fades out under a move.
	var warped := rig(); var plain := rig()
	warped.set_strafe(deg_to_rad(60))
	for i in 20:
		warped.tick(DT); plain.tick(DT)
	for r: Rig in [warped, plain]:
		r.play_move(&"palm_jab", 0.0); r.set_move_time(0.2); r.tick(DT)
	assert_near(_turn(warped, plain, &"pelvis"), 0.0, 0.5, "no warp over a move")
	for r: Rig in [warped, plain]:
		r.stop_move(0.0); r.tick(DT)
	assert_near(_turn(warped, plain, &"pelvis"), 60.0, 2.0, "back when it is done")


func test_backward_plays_locomotion_in_reverse() -> void:
	var r := rig()
	assert_true(r.set_strafe(PI))
	assert_near(r.warp.angle, PI, 1e-6)
	r.set_locomotion(5.546, true); r.tick(DT)
	assert_near(float(r.tree.get(&"parameters/loco_scale/scale")), -1.0, 1e-6)
	assert_false(r.set_strafe(deg_to_rad(45)))
	r.set_locomotion(5.546, false); r.tick(DT)
	assert_near(float(r.tree.get(&"parameters/loco_scale/scale")), 1.0, 1e-6)
	assert_true(r.set_strafe(deg_to_rad(-150)))


func test_forward_holds_until_past_the_band() -> void:
	# The switch at 110° has a band either way: forward turns backward only past 115°.
	var r := rig()
	for deg in [109.0, 111.0, 109.5, 114.9]:
		assert_false(r.set_strafe(deg_to_rad(deg)), "%s° stays forward" % deg)
	assert_true(r.set_strafe(deg_to_rad(116)), "116° goes backward")
	var l := rig()
	for deg in [-109.0, -111.0, -109.5]:
		assert_false(l.set_strafe(deg_to_rad(deg)), "%s° stays forward" % deg)
	assert_true(l.set_strafe(deg_to_rad(-116)), "and so on the other side")


func test_backward_holds_until_back_inside_the_band() -> void:
	# Backward turns forward again only inside 105°, and in between the hips keep the backward warp.
	var warped := rig(); var plain := rig()
	assert_true(warped.set_strafe(deg_to_rad(116)))
	assert_true(warped.set_strafe(deg_to_rad(108)), "108° stays backward")
	for i in 20:
		warped.tick(DT); plain.tick(DT)
	assert_near(_turn(warped, plain, &"pelvis"), -70.0, 2.0, "the hips face away from the path: wrap(108° - 180°), clamped")
	assert_true(warped.set_strafe(deg_to_rad(105.5)), "105.5° still backward")
	assert_false(warped.set_strafe(deg_to_rad(104)), "104° returns forward")
	for i in 20:
		warped.tick(DT); plain.tick(DT)
	assert_near(_turn(warped, plain, &"pelvis"), 70.0, 2.0, "and the hips turn toward the path again")
	var l := rig()
	assert_true(l.set_strafe(deg_to_rad(-116)))
	assert_true(l.set_strafe(deg_to_rad(-108)), "-108° stays backward")
	assert_false(l.set_strafe(deg_to_rad(-104)), "-104° returns forward")


func test_noise_at_the_threshold_does_not_chatter() -> void:
	# A path held at 110° with a degree of noise either way, at a jog: the cycle never reverses, and the
	# hips settle rather than shaking.
	var warped := rig(); var plain := rig()
	var yaws: Array[float] = []
	for i in 60:
		var noise := (1.0 if i % 2 == 0 else -1.0) * (0.3 + 0.7 * fposmod(i * 0.618, 1.0))
		var back := warped.set_strafe(deg_to_rad(110.0 + noise))
		assert_false(back, "tick %d at %.2f° stays forward" % [i, 110.0 + noise])
		warped.set_locomotion(5.546, back); plain.set_locomotion(5.546, false)
		warped.tick(DT); plain.tick(DT)
		assert_near(float(warped.tree.get(&"parameters/loco_scale/scale")), 1.0, 1e-6, "tick %d" % i)
		yaws.append(_turn(warped, plain, &"pelvis"))
	for i in range(1, yaws.size()):
		assert_true(yaws[i] >= yaws[i - 1] - 0.05, "the hips only turn one way: %.2f° then %.2f° at tick %d" % [yaws[i - 1], yaws[i], i])
	assert_near(yaws[-1], 70.0, 1.0, "and settle at the clamp")


func test_actor_strafes_around_its_face_target() -> void:
	var arena := TestArena.make(self)
	var target := Vector3(0, 0, 20)
	var brain := ScriptBrain.new([
		{"frames": 40, "move": Vector2(1, 0), "face_target": target},
		{"frames": 40, "move": Vector2(0, -1), "face_target": target},
		{"frames": 40, "move": Vector2(1, 0)},
	])
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, brain)
	await frames(35)
	# Going east while facing a target to the north: 90° (and a little more, as he passes it) off his
	# facing, so the hips turn and the cycle plays forward.
	assert_near(angle_difference(actor.locomotion.facing_yaw, _yaw_to(actor, target)), 0.0, deg_to_rad(3), "he faces the target")
	assert_true(actor.global_position.x > 1.0, "while going east (x = %.2f)" % actor.global_position.x)
	var side := rad_to_deg(actor.rig.warp.angle)
	assert_true(side > 85.0 and side < 110.0, "a strafe of %.1f°" % side)
	assert_near(float(actor.rig.tree.get(&"parameters/loco_scale/scale")), 1.0, 1e-6)
	await frames(40)
	# Going south, away from the target: a backpedal.
	assert_near(angle_difference(actor.locomotion.facing_yaw, _yaw_to(actor, target)), 0.0, deg_to_rad(3), "still facing it")
	assert_true(absf(rad_to_deg(actor.rig.warp.angle)) > 160.0, "moving away (%.1f°)" % rad_to_deg(actor.rig.warp.angle))
	assert_near(float(actor.rig.tree.get(&"parameters/loco_scale/scale")), -1.0, 1e-6, "the cycle plays in reverse")
	while not brain.done():
		await frames(1)
	await frames(1)
	# No target: he faces the way he goes, and nothing is warped.
	assert_near(actor.rig.warp.angle, 0.0, 1e-6)
	assert_near(angle_difference(actor.locomotion.facing_yaw, PI / 2), 0.0, 0.05)
	assert_near(float(actor.rig.tree.get(&"parameters/loco_scale/scale")), 1.0, 1e-6)


func test_actor_turns_to_its_face_target_standing_still() -> void:
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 30, "face_target": Vector3(-5, 0, 0)}])
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, brain)
	await frames(2)
	var early := actor.locomotion.facing_yaw
	assert_true(early < 0.0 and early > -PI / 2, "turning toward -X at the turn rate (%.2f rad)" % early)
	while not brain.done():
		await frames(1)
	assert_near(angle_difference(actor.locomotion.facing_yaw, -PI / 2), 0.0, 1e-4, "facing the target")
	assert_vec_near(actor.facing(), Vector3(-1, 0, 0), 1e-3)
	assert_near(actor.rig.warp.angle, 0.0, 1e-6, "standing still is no strafe")
	assert_true(actor.global_position.length() < 0.01, "and he did not move")


func test_sprinting_faces_the_way_it_goes() -> void:
	# A sprint is a run, not a strafe: with a face target to the north, sprinting east faces east.
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 40, "move": Vector2(1, 0), "hold": [&"dodge"], "face_target": Vector3(0, 0, 20)}])
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, brain)
	while not brain.done():
		await frames(1)
	assert_true(actor.locomotion.sprinting)
	assert_near(angle_difference(actor.locomotion.facing_yaw, PI / 2), 0.0, 0.05, "facing the way he runs")
	assert_near(actor.rig.warp.angle, 0.0, 1e-6, "no strafe")
	assert_near(float(actor.rig.tree.get(&"parameters/loco_scale/scale")), 1.0, 1e-6)


# How many degrees further `bone` has turned about up on `r` than on `ref`, each in its own rig's space:
# the yaw of the bone's +Z projected onto the ground, against the rig's facing.
func _turn(r: Rig, ref: Rig, bone: StringName) -> float:
	return rad_to_deg(angle_difference(_yaw(ref, bone), _yaw(r, bone)))


func _yaw(r: Rig, bone: StringName) -> float:
	var z := r.global_basis.inverse() * r.shown_pose(bone).basis.z
	return atan2(z.x, z.z)


func _yaw_to(actor: Actor, target: Vector3) -> float:
	return Locomotion.yaw_of(Vector2(target.x - actor.global_position.x, target.z - actor.global_position.z))
