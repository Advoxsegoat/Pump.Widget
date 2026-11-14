class_name StoryStage
extends RefCounted
## A stage for the Director's tests: a PixelStage whose World holds a floor (TestArena, with TestTerrain pieces when asked),
## a CameraRig following Abarax, and Abarax with the player's hands (a PlayerBrain); the Hud is in the stage's Hud picture.
## The same parts the real Main has, without Main's arena, menu and window.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE := "res://data/actors/knuckle_1.tres"


## The parts, under `t` (which frees them after the test), as {stage, world, region, rig, hud, player, brain}. The `region` is
## the floor's own node (the Director puts what it spawns there); Abarax stands in it at `at`, facing `yaw` radians (0 is +Z),
## and the camera has snapped to him.
static func make(t: TestCase, at := Vector3.ZERO, yaw := 0.0) -> Dictionary:
	var stage := t.track(STAGE_SCENE.instantiate()) as PixelStage
	var region := TestArena.make(t)
	region.get_parent().remove_child(region)  # TestArena put it under the test; it belongs in the stage's world
	stage.world.add_child(region)
	var brain := PlayerBrain.new()
	var player := TestArena.spawn(region, load(ABARAX) as ActorDef, brain, at, "Player")
	player.place(Transform3D(Basis(Vector3.UP, yaw), at))
	var rig := CameraRig.new()
	rig.target = player
	rig.stage = stage
	stage.world.add_child(rig)
	player.reset_physics_interpolation()
	rig.snap_now()
	var hud := Hud.new()
	stage.hud.add_child(hud)
	hud.bind(player, rig, stage, null)
	return {stage = stage, world = stage.world, region = region, rig = rig, hud = hud, player = player, brain = brain}


## A Knuckle (tier I) standing in `region` at `at`, with a brain that wants nothing, facing `yaw`.
static func knuckle(region: Node3D, at: Vector3, yaw := 0.0, foe_name := "Knuckle") -> Actor:
	var foe := TestArena.spawn(region, load(KNUCKLE) as ActorDef, Brain.new(), at, foe_name)
	foe.place(Transform3D(Basis(Vector3.UP, yaw), at))
	return foe


## Each bone of `rig` to its rotation relative to its parent (the root's, to the rig), in the pose the last tick showed (modifiers included).
static func pose_of(rig: Rig) -> Dictionary:
	var out := {}
	var skeleton := rig.skeleton
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		var parent := skeleton.get_bone_parent(i)
		var basis := rig.shown_pose(bone).basis
		if parent >= 0:
			basis = rig.shown_pose(skeleton.get_bone_name(parent)).basis.inverse() * basis
		else:
			basis = rig.global_basis.inverse() * basis  # the root's turn is the body's own, which is not the pose
		out[bone] = basis.orthonormalized().get_rotation_quaternion()
	return out


## The largest angle, in degrees, between the same bone in `a` and in `b` (two pose_of results).
static func angle_between(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for bone: Variant in a:
		if not b.has(bone):
			continue
		worst = maxf(worst, rad_to_deg((a[bone] as Quaternion).angle_to(b[bone] as Quaternion)))
	return worst


## Where `point` (a world point) is in the picture, in whole picture pixels, as the Hud draws things there.
static func screen_of(parts: Dictionary, point: Vector3) -> Vector2:
	return (parts.hud as Hud).picture_point(point)
