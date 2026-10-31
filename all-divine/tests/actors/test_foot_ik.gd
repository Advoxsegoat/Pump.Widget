extends TestCase
## Foot IK: the FootPlanter (actors/liveliness/foot_planter.gd) with the two TwoBoneIK3Ds after it, fed by
## the actor's foot probes (rays on `ik_surface`). On uneven ground each foot stands on the ground below
## it, the hips dropping as far as the lower foot needs; where a ray finds nothing the foot goes back to
## the clip's. "On the ground" is measured at the ankle: the foot bone stands ankle_height (0.08 m, the
## idle clip's ankle height on flat ground) above the surface straight below it.

const ABARAX := "res://data/actors/abarax.tres"
const RIG := "res://actors/abarax/abarax_rig.tscn"
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const DT := 1.0 / 60
## How near the ground an ankle must stand (see the class doc).
const TOLERANCE := 0.04
## The most the hips may move in one tick going up stairs, in metres. The hips are smoothed twice with
## blend_speed 12 at 60 ticks a second (a = 1 - e^-0.2 = 0.181 a tick): a step of G in their goal moves them
## at most a^2 * max_n n(1 - a)^(n - 1) * G = 0.0738 G in a tick. Their largest swing on these stairs is a
## back foot that lifts beyond its probe's reach (0.5 m) and fades from about -0.30 m to 0 (0.022 m a tick);
## this allows a swing of 0.34 m.
const MAX_HIPS_STEP := 0.025
## Where TestTerrain.stairs(0.2, 0.35, 6) has its landing well under way (it runs from 2.1 to 4.1 m).
const STAIRS_END := 3.6


func _def() -> ActorDef:
	return load(ABARAX) as ActorDef


# Abarax standing at `at`, facing `yaw` (0 faces +Z), wanting nothing.
func _stand(arena: Node3D, at: Vector3, yaw := 0.0) -> Actor:
	var actor := TestArena.spawn(arena, _def(), Brain.new(), at)
	actor.locomotion.facing_yaw = yaw
	return actor


# The height of the `ik_surface` straight below `point` (it may be up to 1 m above it), or NAN if none.
func _surface_below(node: Node3D, point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN * 2.0,
			TestArena.layer_bit("ik_surface"))
	var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.position as Vector3).y if not hit.is_empty() else NAN


# How far `foot`'s ankle, at `at`, is from standing ankle_height above the surface below it.
func _gap(actor: Actor, at: Vector3) -> float:
	return at.y - actor.rig.foot_planter.ankle_height - _surface_below(actor, at)


func _assert_feet_on_ground(actor: Actor, where: String) -> void:
	var worst_clip := 0.0
	for foot in FEET:
		var gap := _gap(actor, actor.rig.bone_global(foot))
		assert_near(gap, 0.0, TOLERANCE, "%s %s: its ankle stands %.3f m off the ground" % [foot, where, gap])
		worst_clip = maxf(worst_clip, absf(_gap(actor, actor.rig.animated_foot(foot))))
	# The test means something only if the clip alone would leave a foot off the ground.
	assert_true(worst_clip > TOLERANCE, "%s, the clip alone is off the ground by %.3f m" % [where, worst_clip])


# How many bones of `rig` show a pose that is not finite.
func _bad_bones(rig: Rig) -> int:
	var bad := 0
	for i in rig.skeleton.get_bone_count():
		var pose := rig.shown_pose(rig.skeleton.get_bone_name(i))
		if not (pose.origin.is_finite() and pose.basis.x.is_finite() and pose.basis.y.is_finite() and pose.basis.z.is_finite()):
			bad += 1
	return bad


func test_rig_has_the_planter_and_both_legs() -> void:
	var r: Rig = track(load(RIG).instantiate())
	assert_ne(r.foot_planter, null, "a FootPlanter under the skeleton")
	var names := PackedStringArray()
	for child in r.skeleton.get_children():
		if child is SkeletonModifier3D:
			names.append(child.get_class() if child.get_script() == null else (child.get_script() as Script).get_global_name())
	assert_eq(names, PackedStringArray(["OrientationWarp", "Breathing", "HitReact", "FootPlanter", "TwoBoneIK3D",
			"TwoBoneIK3D", "LookAtModifier3D", "LookAtModifier3D", "SpringBoneSimulator3D"]), "the modifiers, in the order they run")
	var legs := r.skeleton.find_children("*", "TwoBoneIK3D", false, false)
	for i in legs.size():
		var ik := legs[i] as TwoBoneIK3D
		var side := "l" if i == 0 else "r"
		assert_eq([ik.get_root_bone_name(0), ik.get_middle_bone_name(0), ik.get_end_bone_name(0)],
				["thigh_" + side, "calf_" + side, "foot_" + side])
		assert_eq(ik.get_node(ik.get_target_node(0)).name, StringName("IKTarget_" + side))
	assert_near(r.foot_planter.max_drop, 0.45, 1e-9)
	assert_near(r.foot_planter.blend_speed, 12.0, 1e-9)
	assert_near(r.foot_planter.ankle_height, 0.08, 1e-9)


func test_no_ground_leaves_the_legs_alone() -> void:
	# With nothing under the feet (a bare rig, as in a contact sheet), every clip's legs are its own. Each
	# pose is a physics frame after the last, as a contact sheet's cells are: the IK must aim at this
	# tick's targets, not the last frame's.
	var r: Rig = track(load(RIG).instantiate())
	var plain: Rig = track(load(RIG).instantiate())
	for child in plain.skeleton.get_children():
		if child is FootPlanter or child is TwoBoneIK3D:
			(child as SkeletonModifier3D).active = false
	var worst := 0.0
	for clip in r.tree.get_animation_list():
		for rr: Rig in [r, plain]:
			rr.play_move(clip, 0.0)
		for f in range(0, int(r.tree.get_animation(clip).length * 60), 3):
			await frames(1)
			for rr: Rig in [r, plain]:
				rr.set_move_time(f / 60.0)
				rr.tick(DT)
			for bone in [&"pelvis", &"thigh_l", &"calf_l", &"foot_l", &"ball_l", &"thigh_r", &"calf_r", &"foot_r", &"ball_r"]:
				worst = maxf(worst, (r.bone_global(bone) - plain.bone_global(bone)).length())
	assert_true(worst < 0.002, "the legs are the clips' (%.4f m off at worst)" % worst)


func test_offsets_follow_the_ground_given() -> void:
	# On a bare rig, with the ground handed to it: the left foot's ground 0.1 m up, the right's 0.1 m down.
	var r: Rig = track(load(RIG).instantiate())
	for i in 30:
		r.tick(DT)
	var start := {}
	for foot in FEET:
		start[foot] = r.animated_foot(foot)
	r.set_foot_ground(&"foot_l", {position = Vector3(start[&"foot_l"].x, 0.1, start[&"foot_l"].z), normal = Vector3.UP})
	r.set_foot_ground(&"foot_r", {position = Vector3(start[&"foot_r"].x, -0.1, start[&"foot_r"].z), normal = Vector3.UP})
	r.tick(DT)
	var k := 1.0 - exp(-12.0 * DT)
	assert_near(r.foot_planter.offsets[&"foot_r"], -0.1 * k, 0.002, "one tick in, an offset has moved by blend_speed's share")
	for i in 60:
		r.tick(DT)
	var planter := r.foot_planter
	assert_near(planter.offsets[&"foot_l"], 0.1, 0.005, "the higher ground lifts the left foot")
	assert_near(planter.offsets[&"foot_r"], -0.1, 0.005, "the lower ground lowers the right")
	assert_near(planter.pelvis_offset, -0.1, 0.005, "and the hips drop as far as the lower foot")
	assert_near(r.bone_global(&"foot_l").y, 0.1 + planter.ankle_height, 0.01, "the left ankle stands on its ground")
	assert_near(r.bone_global(&"foot_r").y, -0.1 + planter.ankle_height, 0.01, "and the right on its")
	assert_near(r.bone_global(&"pelvis").y - r.animated_pose(&"pelvis").origin.y, -0.1, 0.005, "the pelvis is shown lower")
	# Ground far below is reached only as far as max_drop lets the hips go.
	r.set_foot_ground(&"foot_r", {position = Vector3(start[&"foot_r"].x, -1.0, start[&"foot_r"].z), normal = Vector3.UP})
	var deepest := 0.0
	for i in 90:
		r.tick(DT)
		deepest = minf(deepest, planter.pelvis_offset)
	assert_true(deepest >= -0.45, "the hips never drop past max_drop (%.6f)" % deepest)
	assert_near(planter.pelvis_offset, -0.45, 1e-3, "they settle there")


func test_lifted_feet_keep_their_lift() -> void:
	# A foot the clip lifts higher than ankle_height is stepping: it keeps its height over the ground below
	# it, so a jog on flat ground is the clip's own, and the hips stay where it put them.
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 90, "move": Vector2(0, 1)}])
	var actor := TestArena.spawn(arena, _def(), brain)
	var worst_foot := 0.0
	var worst_hips := 0.0
	var lifted := 0.0
	for i in 90:
		await frames(1)
		if i < 30:
			continue  # up to speed
		for foot in FEET:
			worst_foot = maxf(worst_foot, (actor.rig.bone_global(foot) - actor.rig.animated_foot(foot)).length())
			lifted = maxf(lifted, actor.rig.animated_foot(foot).y)
		worst_hips = maxf(worst_hips, absf(actor.rig.foot_planter.pelvis_offset))
	assert_true(lifted > 0.3, "the feet did lift (%.2f m)" % lifted)
	assert_true(worst_foot < 0.01, "the feet are where the clip puts them (%.4f m off at worst)" % worst_foot)
	assert_true(worst_hips < 0.01, "and so are the hips (%.4f m)" % worst_hips)


func test_flat_ground_leaves_pelvis_alone() -> void:
	var arena := TestArena.make(self)
	var actor := _stand(arena, Vector3.ZERO)
	await frames(60)
	assert_near(actor.rig.foot_planter.pelvis_offset, 0.0, 0.01)
	for foot in FEET:
		assert_near(_gap(actor, actor.rig.bone_global(foot)), 0.0, TOLERANCE, "%s on the floor" % foot)


func test_feet_on_a_twenty_degree_slope() -> void:
	# Across the slope: it rises to his left (+X), so his left foot stands higher than his right.
	var arena := TestArena.make(self)
	TestTerrain.slope(arena, 20.0)
	var x := 2.0
	var actor := _stand(arena, Vector3(x, x * tan(deg_to_rad(20.0)) + 0.03, 0))
	await frames(60)
	_assert_feet_on_ground(actor, "on the slope")
	assert_true(actor.rig.foot_planter.pelvis_offset < -0.03, "the hips drop for the downhill foot (%.3f m)" % actor.rig.foot_planter.pelvis_offset)


func test_feet_on_stairs() -> void:
	# Facing up the stairs (+X), the idle stance has the left foot ahead, on the second step, and the right
	# behind, on the first: straddling two steps.
	var arena := TestArena.make(self)
	TestTerrain.stairs(arena, 0.2, 0.35, 6)
	var actor := _stand(arena, Vector3(0.45, 0.45, 0), PI / 2)
	await frames(60)
	_assert_feet_on_ground(actor, "on the stairs")
	var left := _surface_below(actor, actor.rig.bone_global(&"foot_l"))
	var right := _surface_below(actor, actor.rig.bone_global(&"foot_r"))
	assert_near(left - right, 0.2, 1e-3, "one step apart (left on %.2f, right on %.2f)" % [left, right])


func test_walking_up_stairs_keeps_feet_out_of_the_steps() -> void:
	# Up the stairs at a walk (0.45) and a jog (0.7, 1.0). A stepping foot keeps the clip's lift over the
	# ground below it. Where it crosses onto a higher step it is lifted onto it at once (the smoothing would
	# sink it into the step for a few frames); the probe under it is a tick behind, so for that one frame
	# it may still be inside. The hips do not jump with it: they follow the smoothed offsets, so they move
	# at most MAX_HIPS_STEP in a tick.
	for stick: float in [0.45, 0.7, 1.0]:
		var arena := TestArena.make(self)
		TestTerrain.stairs(arena, 0.2, 0.35, 6)
		var actor := _stand(arena, Vector3(-1.0, 0.02, 0), PI / 2)
		await frames(30)
		actor.set_brain(ScriptBrain.new([{"frames": 150, "move": Vector2(stick, 0)}]))
		var planter: FootPlanter = actor.rig.foot_planter
		var inside_before := {&"foot_l": false, &"foot_r": false}
		var longest := 0
		var deepest := 0.0
		var hips_before := planter.pelvis_offset
		var hips_step := 0.0
		var climbed := 0.0
		for i in 150:
			await frames(1)
			if actor.global_position.x > STAIRS_END:
				break  # on the landing, short of its edge
			hips_step = maxf(hips_step, absf(planter.pelvis_offset - hips_before))
			hips_before = planter.pelvis_offset
			climbed = maxf(climbed, actor.global_position.y)
			for foot in FEET:
				var gap := _gap(actor, actor.rig.bone_global(foot))
				var inside := gap < -TOLERANCE
				if inside and inside_before[foot]:
					longest = 2
				elif inside:
					longest = maxi(longest, 1)
				inside_before[foot] = inside
				deepest = minf(deepest, gap)
		var at := "at %.2f stick" % stick
		assert_true(climbed > 0.5, "%s, he climbed (%.2f m)" % [at, climbed])
		assert_true(longest < 2, "%s, no ankle stays inside a step for two frames running (deepest %.3f m)" % [at, deepest])
		assert_true(hips_step <= MAX_HIPS_STEP, "%s, the hips move at most %.3f m in a tick (%.3f m)" % [at, MAX_HIPS_STEP, hips_step])
		arena.free()


func test_bad_ground_changes_nothing() -> void:
	var r: Rig = track(load(RIG).instantiate())
	quietly(func() -> void:
		r.set_foot_ground(&"knee_l", {position = Vector3.ZERO, normal = Vector3.UP})
		r.set_foot_ground(&"foot_l", 0.5)
		r.set_foot_ground(&"foot_r", {position = Vector3.ZERO}))
	assert_eq(r.foot_planter.ground, {&"foot_l": null, &"foot_r": null}, "nothing was taken")


func test_foot_ik_ray_miss_fades_without_nan() -> void:
	# He stands at the ledge's edge facing +Z, his left foot (+X) past it. For a second a block under that
	# foot (on ik_surface only, 0.15 m below the ledge) gives it ground to reach down to; then the block
	# goes, the ray finds nothing, and the foot's offset fades back to 0.
	var arena := TestArena.make(self)
	TestTerrain.ledge(arena)
	var top := TestTerrain.LEDGE_TOP
	var block := TestTerrain.ik_block(arena, Vector3(0.0, top - 1.0, -2.0), Vector3(2.0, top - 0.15, 2.0))
	var actor := _stand(arena, Vector3(-0.1, top + 0.02, 0))
	var planter: FootPlanter = actor.rig.foot_planter
	var bad := 0
	for i in 60:
		await frames(1)
		bad += _bad_bones(actor.rig)
	assert_true(actor.rig.animated_foot(&"foot_l").x > 0.05, "the left foot is past the edge")
	assert_true(actor.rig.animated_foot(&"foot_r").x < -0.05, "the right foot is on the ledge")
	assert_near(planter.offsets[&"foot_l"], -0.15, 0.01, "the block holds the left foot down")
	block.free()
	for i in 18:
		await frames(1)
		bad += _bad_bones(actor.rig)
	assert_near(planter.offsets[&"foot_l"], 0.0, 0.01, "with nothing below it, its offset is gone within 0.3 s")
	for i in 12:
		await frames(1)
		bad += _bad_bones(actor.rig)
	assert_near(planter.pelvis_offset, 0.0, 0.01, "and the hips, smoothed after it, within 0.5 s")
	for i in 18:
		await frames(1)
		bad += _bad_bones(actor.rig)
	assert_eq(bad, 0, "no bone pose has a NaN at any frame")
	assert_near(actor.global_position.y, top, 0.01, "and he still stands on the ledge")


func test_airborne_lets_the_feet_go() -> void:
	# While a move carries the body through the air (Rig.airborne), the planter fades out as if no ray hit.
	var arena := TestArena.make(self)
	TestTerrain.slope(arena, 20.0)
	var actor := _stand(arena, Vector3(2.0, 2.0 * tan(deg_to_rad(20.0)) + 0.03, 0))
	await frames(60)
	assert_true(absf(actor.rig.foot_planter.offsets[&"foot_l"]) > 0.03, "planted on the slope first")
	actor.rig.airborne = true
	await frames(18)
	for foot in FEET:
		assert_near(actor.rig.foot_planter.offsets[foot], 0.0, 0.01, "%s lets go" % foot)
	actor.rig.airborne = false
	await frames(60)
	assert_true(absf(actor.rig.foot_planter.offsets[&"foot_l"]) > 0.03, "and plants again on landing")
