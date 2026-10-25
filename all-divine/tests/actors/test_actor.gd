extends TestCase
## The Actor (actors/actor.tscn) and its brains: the body, swapping brains, walking where a brain says,
## the stick's deadzone keeping a drifting pad still, and what each brain hands the actor. The actor
## tests stand Abarax in a TestArena.

const ABARAX := "res://data/actors/abarax.tres"
const ACTOR := "res://actors/actor.tscn"
const DT := 1.0 / 60


## A PlayerBrain whose pad drifts: the stick rests a little off centre (0.15, inside the deadzone).
class DriftBrain extends PlayerBrain:
	func screen_move() -> Vector2:
		return Inputs.shape_stick(Vector2(0.15, 0))


## A PlayerBrain whose stick is held at `screen`.
class HeldStickBrain extends PlayerBrain:
	var screen := Vector2.ZERO

	func screen_move() -> Vector2:
		return screen


func after_each() -> void:
	Input.action_release(&"palm")


func _def() -> ActorDef:
	return load(ABARAX) as ActorDef


func test_actor_scene_is_a_capsule_on_the_actor_layer() -> void:
	# Looked at outside the tree: an actor needs its def before it is ready.
	var scene_root: Node = load(ACTOR).instantiate()
	var actor := scene_root as Actor
	assert_ne(actor, null, "the scene's root is an Actor")
	if actor != null:
		assert_eq(actor.collision_layer, TestArena.layer_bit("actor"))
		assert_eq(actor.collision_mask, TestArena.layer_bit("world"))
		var shapes := actor.find_children("*", "CollisionShape3D", false, false)
		assert_eq(shapes.size(), 1)
		var capsule := (shapes[0] as CollisionShape3D).shape as CapsuleShape3D
		assert_ne(capsule, null, "a capsule")
		if capsule != null:
			assert_near(capsule.radius, 0.35, 1e-6)
			assert_near(capsule.height, 1.8, 1e-6)
		assert_vec_near((shapes[0] as Node3D).position, Vector3(0, 0.9, 0), 1e-6, "standing on the actor's origin")
		assert_true(actor.get_node_or_null("MoveRunner") is MoveRunner)
	scene_root.free()


func test_an_actor_without_a_def_stays_still() -> void:
	var actor := load(ACTOR).instantiate() as Actor
	quietly(func() -> void: track(actor))
	assert_false(actor.is_physics_processing(), "it reports the missing def and does not tick")
	assert_eq(actor.rig, null)


func test_ready_builds_the_rig_and_the_parts() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, _def(), Brain.new())
	assert_true(actor.rig is Rig)
	assert_eq(actor.rig, actor.get_node_or_null("Rig"), "the def's rig_scene, as the child Rig")
	assert_eq(actor.runner.actor, actor)
	assert_eq(actor.locomotion.tuning, _def().locomotion)
	assert_near(actor.stats.hp, _def().max_hp, 0.0)
	assert_vec_near(actor.facing(), Vector3(0, 0, 1), 1e-6, "yaw 0 faces +Z")
	assert_false(actor.is_invulnerable())


func test_brain_swap_emits() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, _def(), Brain.new())
	var got: Array = []
	actor.brain_changed.connect(func(b: Brain) -> void: got.append(b))
	var next := ScriptBrain.new([])
	actor.set_brain(next)
	assert_eq(got, [next])
	assert_true(actor.brain == next)


func test_script_brain_walks_and_faces_east() -> void:
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 60, "move": Vector2(1, 0)}])
	var actor := TestArena.spawn(arena, _def(), brain)
	while not brain.done():
		await frames(1)
	assert_eq(actor.frame, 60)
	assert_true(actor.global_position.x >= 1.5, "walked %s m east" % actor.global_position.x)
	assert_near(actor.global_position.z, 0.0, 0.01, "and only east")
	assert_near(angle_difference(actor.locomotion.facing_yaw, PI / 2), 0.0, 0.05)
	assert_vec_near(actor.facing(), Vector3(1, 0, 0), 0.05, "the body turned with it")
	assert_true(actor.is_on_floor(), "standing on the arena floor")


func test_drift_does_not_move_actor() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, _def(), DriftBrain.new())
	await frames(60)
	assert_true(actor.frame >= 60)
	assert_true(actor.global_position.length() < 0.01, "moved to %s" % actor.global_position)
	assert_eq(actor.locomotion.facing_yaw, 0.0)
	assert_vec_near(actor.facing(), Vector3(0, 0, 1), 1e-6)


func test_player_brain_turns_the_stick_by_the_view_yaw() -> void:
	var brain := HeldStickBrain.new()
	brain.screen = Vector2(0, -1)  # stick up
	assert_vec_near(_flat(brain.think(null, DT).move), Vector3(0, 0, -1), 1e-6, "up is away from a yaw-0 camera, -Z")
	brain.screen = Vector2(1, 0)
	assert_vec_near(_flat(brain.think(null, DT).move), Vector3(1, 0, 0), 1e-6, "right is +X")
	brain.view_yaw = PI / 2
	brain.screen = Vector2(0, -1)
	# The camera turned a quarter left: its forward along the ground is Basis(UP, PI/2) * -Z = -X.
	assert_vec_near(_flat(brain.think(null, DT).move), Basis(Vector3.UP, PI / 2) * Vector3(0, 0, -1), 1e-6)
	brain.screen = Vector2(0.3, 0.4)
	assert_near(brain.think(null, DT).move.length(), 0.5, 1e-6, "turning keeps the length")


func test_player_brain_reads_presses_and_holds() -> void:
	var brain := HeldStickBrain.new()
	Input.action_press(&"palm")
	await frames(1)
	var first := brain.think(null, DT)
	assert_eq(first.pressed, [&"palm"] as Array[StringName])
	assert_eq(first.held, [&"palm"] as Array[StringName])
	await frames(1)
	var next := brain.think(null, DT)
	assert_eq(next.pressed, [] as Array[StringName], "a press is only on its own frame")
	assert_eq(next.held, [&"palm"] as Array[StringName], "while it stays held")
	Input.action_release(&"palm")


func test_script_brain_plays_its_steps() -> void:
	var brain := ScriptBrain.new([
		{"frames": 2, "move": Vector2(1, 0), "press": [&"palm"], "hold": [&"dodge"]},
		{"frames": 0, "press": [&"never"]},
		{"frames": 1, "face_target": Vector3(1, 2, 3), "look_target": Vector3(4, 5, 6)},
	])
	var a := brain.think(null, DT)
	assert_eq(a.move, Vector2(1, 0))
	assert_eq(a.pressed, [&"palm"] as Array[StringName], "pressed on the step's first frame")
	assert_eq(a.held, [&"dodge"] as Array[StringName])
	var b := brain.think(null, DT)
	assert_eq(b.pressed, [] as Array[StringName], "and only then")
	assert_eq(b.held, [&"dodge"] as Array[StringName])
	assert_false(brain.done())
	var c := brain.think(null, DT)
	assert_eq(c.pressed, [] as Array[StringName], "a step of 0 frames is skipped")
	assert_eq(c.move, Vector2.ZERO)
	assert_eq(c.face_target, Vector3(1, 2, 3))
	assert_eq(c.look_target, Vector3(4, 5, 6))
	assert_true(brain.done())
	var after := brain.think(null, DT)
	assert_eq(after.move, Vector2.ZERO, "after the last step it wants nothing")
	assert_eq(after.face_target, null)
	assert_true(ScriptBrain.new([]).done())


func test_brain_wants_nothing() -> void:
	var intent := Brain.new().think(null, DT)
	assert_eq(intent.move, Vector2.ZERO)
	assert_eq(intent.pressed, [] as Array[StringName])
	assert_eq(intent.held, [] as Array[StringName])
	assert_eq(intent.face_target, null)
	assert_eq(intent.look_target, null)


func test_stats_from_def() -> void:
	var def := ActorDef.new()
	def.max_hp = 120.0
	def.max_stamina = 80.0
	def.max_posture = 60.0
	def.poise = 15.0
	var stats := Stats.from_def(def)
	assert_eq(stats.hp, 120.0)
	assert_eq(stats.stamina, 80.0)
	assert_eq(stats.posture, 60.0, "posture is a bar that wears down, so it starts full")
	assert_eq(stats.poise, 15.0)
	assert_eq(stats.resistances, {})


func _flat(v: Vector2) -> Vector3:
	return Vector3(v.x, 0, v.y)
