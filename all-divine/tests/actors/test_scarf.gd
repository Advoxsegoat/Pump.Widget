extends TestCase
## The scarf: a SpringBoneSimulator3D on scarf_01 to scarf_04 (its end extended by scarf_04's length), with
## collision capsules on spine_03 and the pelvis. It hangs behind Abarax, trails when he runs, settles when
## he stops, and stays out of his torso. The tip is the end of scarf_04: the bone's origin plus its length
## along its +Y.
##
## Two measures of "out of the torso". The tip's distance from the spine_02-spine_03 segment (the chest)
## catches the scarf flying up into the chest. The other catches what the clips did before the spring
## (Task 7's sheet): every joint of the scarf (scarf_02 to scarf_04 and the tip) against the torso's centre
## line, pelvis to neck_01. In the bind pose, where the scarf lies on the back, they are 0.143 m from it or
## more; with the scarf stiff on the neck, the clips sank them to 0.002-0.08 m.

const ABARAX := "res://data/actors/abarax.tres"
const RIG := "res://actors/abarax/abarax_rig.tscn"
## Each scarf bone's length (Task 5's build).
const SCARF_BONE := 0.175
## How near the spine_02-spine_03 segment the tip may come, and the torso's centre line any joint may.
const CLEARANCE := 0.14
const TORSO: Array[StringName] = [&"pelvis", &"spine_01", &"spine_02", &"spine_03", &"neck_01"]
const JOINTS: Array[StringName] = [&"scarf_02", &"scarf_03", &"scarf_04"]


func _def() -> ActorDef:
	return load(ABARAX) as ActorDef


static func _tip(r: Rig) -> Vector3:
	var end := r.shown_pose(&"scarf_04")
	return end.origin + end.basis.y.normalized() * SCARF_BONE


# The tip from the neck, in the actor's own space (+Z is the way he faces, +X his left).
static func _offset(actor: Actor) -> Vector3:
	return actor.global_basis.inverse() * (_tip(actor.rig) - actor.rig.bone_global(&"neck_01"))


static func _to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# The tip's distance from the spine_02-spine_03 segment.
static func _clearance(r: Rig) -> float:
	return _to_segment(_tip(r), r.bone_global(&"spine_02"), r.bone_global(&"spine_03"))


# The least distance of any scarf joint (and the tip) from the torso's centre line.
static func _torso_clearance(r: Rig) -> float:
	var points: Array[Vector3] = [_tip(r)]
	for joint in JOINTS:
		points.append(r.bone_global(joint))
	var least := INF
	for p in points:
		for i in TORSO.size() - 1:
			least = minf(least, _to_segment(p, r.bone_global(TORSO[i]), r.bone_global(TORSO[i + 1])))
	return least


static func _scarf_finite(r: Rig) -> bool:
	for bone in [&"scarf_01", &"scarf_02", &"scarf_03", &"scarf_04"]:
		var pose := r.shown_pose(bone)
		if not (pose.origin.is_finite() and pose.basis.x.is_finite() and pose.basis.y.is_finite() and pose.basis.z.is_finite()):
			return false
	return true


func test_rig_has_the_scarf_spring() -> void:
	var r: Rig = track(load(RIG).instantiate())
	var springs := r.skeleton.find_children("*", "SpringBoneSimulator3D", false, false)
	assert_eq(springs.size(), 1)
	var spring := springs[0] as SpringBoneSimulator3D
	assert_eq(spring.get_setting_count(), 1)
	assert_eq(spring.get_root_bone_name(0), "scarf_01")
	assert_eq(spring.get_end_bone_name(0), "scarf_04")
	assert_true(spring.is_end_bone_extended(0), "its end extended")
	assert_near(spring.get_end_bone_length(0), SCARF_BONE, 1e-6)
	var capsules := {}
	for capsule: SpringBoneCollisionCapsule3D in spring.find_children("*", "SpringBoneCollisionCapsule3D", false, false):
		capsules[capsule.bone_name] = capsule
	assert_true(capsules.has(&"spine_03"), "a collision capsule on spine_03")
	if capsules.has(&"spine_03"):
		assert_near((capsules[&"spine_03"] as SpringBoneCollisionCapsule3D).radius, 0.16, 1e-6)
	assert_true(capsules.has(&"pelvis"), "and one on the pelvis, for the lower back")


func test_spring_moves_only_the_scarf() -> void:
	var r: Rig = track(load(RIG).instantiate())
	var plain: Rig = track(load(RIG).instantiate())
	for spring in plain.skeleton.find_children("*", "SpringBoneSimulator3D", false, false):
		(spring as SkeletonModifier3D).active = false
	for rr: Rig in [r, plain]:
		rr.set_locomotion(5.546, false)
	var worst := 0.0
	for i in 60:
		r.tick(1.0 / 60); plain.tick(1.0 / 60)
		for bone in r.skeleton.get_bone_count():
			var bone_name := StringName(r.skeleton.get_bone_name(bone))
			if not String(bone_name).begins_with("scarf_"):
				worst = maxf(worst, (r.bone_global(bone_name) - plain.bone_global(bone_name)).length())
	assert_true(worst < 1e-4, "every other bone is where it would be without it (%.5f m)" % worst)


func test_scarf_hangs_behind_at_rest() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, _def(), Brain.new())
	await frames(60)
	var rest := _offset(actor)
	assert_true(rest.z < -0.1, "the tip is behind the neck (%.3f m)" % rest.z)
	assert_true(rest.y < -0.4, "and below it (%.3f m)" % rest.y)
	assert_true(_clearance(actor.rig) >= CLEARANCE, "clear of the chest (%.3f m)" % _clearance(actor.rig))
	assert_true(_torso_clearance(actor.rig) >= CLEARANCE, "and of the back (%.3f m)" % _torso_clearance(actor.rig))


func test_scarf_trails_when_running_and_settles() -> void:
	# Beside him, a rig jogging on the spot, ticked alike: the same clip without the run's motion. The jog
	# leans him, which moves even a stiff scarf, so the trail is measured against it too.
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 60}, {"frames": 60, "move": Vector2(1, 0)}, {"frames": 120}])
	var actor := TestArena.spawn(arena, _def(), brain)
	var in_place: Rig = load(RIG).instantiate()
	in_place.position = Vector3(0, 0, 5)
	arena.add_child(in_place)
	var bad := 0
	for i in 60:
		await frames(1)
		in_place.tick(1.0 / 60)
		bad += 0 if _scarf_finite(actor.rig) else 1
	var rest := _offset(actor)
	var spot := 0.0
	for i in 60:
		await frames(1)
		in_place.set_locomotion(actor.locomotion.speed, false)
		in_place.tick(1.0 / 60)
		bad += 0 if _scarf_finite(actor.rig) else 1
		spot = (in_place.global_basis.inverse() * (_tip(in_place) - in_place.bone_global(&"neck_01"))).z
	assert_true(actor.locomotion.speed > 5.0, "he is jogging (%.2f m/s)" % actor.locomotion.speed)
	assert_true(actor.facing().dot(Vector3.RIGHT) > 0.99, "toward +X")
	var running := _offset(actor)
	assert_true(running.z < rest.z - 0.05, "the tip trails: %.3f m ahead of the neck, against %.3f at rest" % [running.z, rest.z])
	assert_true(running.z < spot - 0.05, "and it is the run that trails it: %.3f m, against %.3f jogging on the spot" % [running.z, spot])
	for i in 120:
		await frames(1)
		bad += 0 if _scarf_finite(actor.rig) else 1
	var settled := _offset(actor)
	assert_vec_near(settled, rest, 0.05, "stopped for 2 s, the tip is back where it hangs at rest")
	assert_eq(bad, 0, "no frame has a NaN in the scarf")


func test_scarf_stays_out_of_the_torso() -> void:
	# After half a second standing: a jog away, a turn on the spot into a jog back, and a stop. Every frame,
	# the tip clears the chest and every joint the back.
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 30}, {"frames": 60, "move": Vector2(1, 0)},
			{"frames": 60, "move": Vector2(-1, 0)}, {"frames": 60}])
	var actor := TestArena.spawn(arena, _def(), brain)
	await frames(30)
	var chest := INF
	var back := INF
	for i in 180:
		await frames(1)
		chest = minf(chest, _clearance(actor.rig))
		back = minf(back, _torso_clearance(actor.rig))
	assert_true(chest >= CLEARANCE, "the tip came within %.3f m of the spine_02-spine_03 segment" % chest)
	assert_true(back >= CLEARANCE, "a joint of the scarf came within %.3f m of the torso's centre line" % back)


func test_scarf_stays_out_of_the_torso_in_every_clip() -> void:
	# Each of the rig's clips, played through at its own pace in the physics step on a rig standing in
	# place: after half a second idle for the scarf to settle, the clip crossfades in, and every frame of
	# it, every joint of the scarf clears the torso's centre line (and the tip the chest).
	var worst := {}
	for clip in _clip_names():
		var r: Rig = track(load(RIG).instantiate())
		for i in 30:
			await frames(1)
			r.tick(1.0 / 60)
		r.play_move(clip, 0.15)
		var back := INF
		var chest := INF
		for f in int(r.tree.get_animation(clip).length * 60) + 1:
			await frames(1)
			r.set_move_time(f / 60.0)
			r.tick(1.0 / 60)
			back = minf(back, _torso_clearance(r))
			chest = minf(chest, _clearance(r))
		worst[clip] = "%.3f/%.3f" % [back, chest]
		assert_true(back >= CLEARANCE, "%s: a joint of the scarf came within %.3f m of the torso's centre line" % [clip, back])
		assert_true(chest >= CLEARANCE, "%s: the tip came within %.3f m of the spine_02-spine_03 segment" % [clip, chest])
		r.free()
	assert_eq(worst.size(), 8, "every clip of the library was played (%s)" % [worst])


# The names of the rig's clips (the actor's library).
func _clip_names() -> PackedStringArray:
	var r: Rig = track(load(RIG).instantiate())
	var names := PackedStringArray(r.tree.get_animation_list())
	r.free()
	return names


func test_scarf_clears_the_body_in_a_roll() -> void:
	# The roll tumbles the body over: the capsules keep the scarf out of it all the way.
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 30}, {"frames": 1, "move": Vector2(0, 1), "press": [&"dodge"]},
			{"frames": 60}])
	var actor := TestArena.spawn(arena, _def(), brain)
	await frames(30)
	var chest := INF
	var back := INF
	var rolled := false
	for i in 61:
		await frames(1)
		rolled = rolled or actor.runner.busy()
		chest = minf(chest, _clearance(actor.rig))
		back = minf(back, _torso_clearance(actor.rig))
	assert_true(rolled, "he rolled")
	assert_true(chest >= CLEARANCE, "the tip came within %.3f m of the spine_02-spine_03 segment" % chest)
	assert_true(back >= CLEARANCE, "a joint of the scarf came within %.3f m of the torso's centre line" % back)
