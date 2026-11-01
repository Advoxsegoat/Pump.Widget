extends TestCase
## Hit reactions (actors/liveliness/hit_react.gd): a blow kicks the upper body away from it, and a
## spring-damper brings it back. Each rig here is turned, so the blow's world direction has to be taken
## into the body's own space. Leans are read against a rig that was not hit, ticked alike. Headless:
## Rig.tick runs the skeleton's modifiers itself, so the pose a tick shows (Rig.shown_pose) is read straight
## after it.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const DT := 1.0 / 60
const TURN := 0.7  # radians: how far both rigs are turned


func rig() -> Rig:
	var r: Rig = track(load(RIG).instantiate())
	r.rotation.y = TURN
	return r


func test_front_hit_tilts_back_then_settles() -> void:
	var r := rig(); var calm := rig()
	r.hit_react(-r.global_basis.z, 1.0)  # a blow from in front, travelling back along his facing
	var leans := _leans(r, calm, &"spine_02", 60)
	var back := leans.map(func(l: Vector2) -> float: return -l.y)
	var peak: float = back.max()
	var at := (back.find(peak) + 1) * DT
	assert_true(peak > 3.0, "spine_02 pitches back (%.2f°)" % peak)
	assert_true(at <= 0.12, "and peaks within 0.12 s (at %.3f s)" % at)
	for l: Vector2 in leans:
		assert_true(absf(l.x) < 0.05 * peak, "straight back, not sideways (%.3f°)" % l.x)
	for i in range(35, 60):  # tick i ends at (i + 1) / 60 s, so these are 0.6 s and on
		assert_true(absf(back[i]) < 0.05 * peak, "settled by 0.6 s: %.3f° at %.3f s" % [back[i], (i + 1) * DT])
	assert_true(back.min() < 0.0, "with a little sway forward on the way back")


func test_left_hit_tilts_right() -> void:
	var r := rig(); var calm := rig()
	r.hit_react(-r.global_basis.x, 1.0)  # from his left (+X), travelling toward his right (-X)
	var leans := _leans(r, calm, &"spine_02", 10)
	var right: float = leans.map(func(l: Vector2) -> float: return -l.x).max()
	assert_true(right > 3.0, "spine_02 rolls to his right (%.2f°)" % right)
	for l: Vector2 in leans:
		assert_true(absf(l.y) < 0.05 * right, "not forward or back (%.3f°)" % l.y)


func test_lean_is_shared_up_the_spine() -> void:
	# spine_01 0.3, spine_02 0.3, spine_03 0.2, neck_01 0.1, Head 0.1 of the lean, each on top of the bones
	# below it; the hips stay put.
	var r := rig(); var calm := rig()
	r.hit_react(-r.global_basis.z, 1.0)
	for i in 5:
		r.tick(DT); calm.tick(DT)
	var whole := -_lean(r, calm, &"Head").y
	assert_true(whole > 5.0, "the head carries the whole lean (%.2f°)" % whole)
	assert_near(-_lean(r, calm, &"pelvis").y, 0.0, 1e-3)
	var want := {&"spine_01": 0.3, &"spine_02": 0.6, &"spine_03": 0.8, &"neck_01": 0.9}
	for bone: StringName in want:
		assert_near(-_lean(r, calm, bone).y / whole, want[bone], 0.03, bone)


func test_strength_scales_the_kick() -> void:
	# Below the cap: a blow of strength 2 would lean past MAX_TILT, where the scaling stops.
	var soft := rig(); var hard := rig(); var calm := rig()
	soft.hit_react(-soft.global_basis.z, 0.5)
	hard.hit_react(-hard.global_basis.z, 1.0)
	for i in 5:
		soft.tick(DT); hard.tick(DT); calm.tick(DT)
	assert_near(_lean(hard, calm, &"spine_02").y / _lean(soft, calm, &"spine_02").y, 2.0, 0.1)


func test_lean_is_capped_and_direction_length_does_not_matter() -> void:
	# A flurry of ten blows, one a tick, piles up lean speed far past what the spring could hold; the lean
	# never goes past MAX_TILT, and then settles.
	var r := rig()
	var dir := -r.global_basis.z
	var peak := 0.0
	for i in 70:
		if i < 10:
			r.hit_react(dir, 1.0)
		r.tick(DT)
		var lean := r.hit_reaction.tilt.length()
		peak = maxf(peak, lean)
		assert_true(lean <= HitReact.MAX_TILT + 1e-6, "lean %.4f rad at tick %d is past the cap" % [lean, i])
	assert_near(HitReact.MAX_TILT, 0.35, 1e-9)
	assert_near(peak, HitReact.MAX_TILT, 1e-6, "the flurry does reach the cap")
	assert_true(r.hit_reaction.tilt.length() < 0.01, "and it settles: %.4f rad after a second" % r.hit_reaction.tilt.length())
	# How long the direction is says nothing about how hard the blow is: that is the strength.
	var near := rig(); var far := rig()
	near.hit_react(dir, 1.0)
	far.hit_react(dir * 5.0, 1.0)
	assert_vec_near(Vector3(far.hit_reaction.tilt_velocity.x, 0, far.hit_reaction.tilt_velocity.y),
			Vector3(near.hit_reaction.tilt_velocity.x, 0, near.hit_reaction.tilt_velocity.y), 1e-6)
	assert_true(near.hit_reaction.tilt_velocity.length() > 1.0, "and the blow did kick him")


func test_zero_direction_is_safe() -> void:
	var r := rig(); var calm := rig()
	r.hit_react(Vector3.ZERO, 1.0)
	r.hit_react(Vector3.UP, 1.0)  # straight down onto him: nothing across the ground to lean with
	for i in 10:
		r.tick(DT); calm.tick(DT)
	for b in r.skeleton.get_bone_count():
		var bone := StringName(r.skeleton.get_bone_name(b))
		var pose := r.shown_pose(bone)
		assert_true(pose.is_finite(), "%s has no NaN" % bone)
		assert_true(pose.is_equal_approx(calm.shown_pose(bone)), "%s is as if unhit" % bone)


# The lean of `bone` on `r` against `ref` after each of `ticks` ticks of both.
func _leans(r: Rig, ref: Rig, bone: StringName, ticks: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in ticks:
		r.tick(DT); ref.tick(DT)
		out.append(_lean(r, ref, bone))
	return out


# How many degrees further `bone`'s up (+Y) leans on `r` than on `ref`, in each rig's own space: x toward
# the rig's left (+X), y toward its front (+Z).
func _lean(r: Rig, ref: Rig, bone: StringName) -> Vector2:
	var u := r.global_basis.inverse() * r.shown_pose(bone).basis.y
	var c := ref.global_basis.inverse() * ref.shown_pose(bone).basis.y
	return Vector2(rad_to_deg(atan2(u.x, u.y) - atan2(c.x, c.y)), rad_to_deg(atan2(u.z, u.y) - atan2(c.z, c.y)))
