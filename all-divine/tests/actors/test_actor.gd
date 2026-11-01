extends TestCase
## The Actor (actors/actor.tscn) and its brains: the body, swapping brains, walking where a brain says,
## the stick's deadzone keeping a drifting pad still, and what each brain hands the actor. The actor
## tests stand Abarax in a TestArena.

const ABARAX := "res://data/actors/abarax.tres"
const ACTOR := "res://actors/actor.tscn"
const DT := 1.0 / 60


## A PlayerBrain whose stick reads `raw`, with the deadzone taken out as Inputs takes it out. A pad
## that drifts rests a little off centre, up to 0.19 on both axes at once.
class DriftBrain extends PlayerBrain:
	var raw := Vector2.ZERO

	func _init(reading: Vector2) -> void:
		raw = reading

	func screen_move() -> Vector2:
		return Inputs.shape_stick(raw)


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
	if actor == null:
		fail("the scene's root is an Actor")
	else:
		assert_eq(actor.collision_layer, TestArena.layer_bit("actor"))
		assert_eq(actor.collision_mask, TestArena.layer_bit("world"))
		var shapes := actor.find_children("*", "CollisionShape3D", false, false)
		assert_eq(shapes.size(), 1)
		var capsule := (shapes[0] as CollisionShape3D).shape as CapsuleShape3D
		if capsule == null:
			fail("a capsule")
		else:
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


# place() is a spawn or a teleport: the actor is there at once, facing the transform's +Z (and keeps facing it,
# wanting nothing), at rest, and physics interpolation does not draw him sliding over from where he was.
func test_place_stands_the_actor_there_at_rest_facing_its_way() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, _def(), ScriptBrain.new([{frames = 30, move = Vector2(1, 0)}]))
	await frames(30)
	assert_true(actor.locomotion.speed > 1.0, "he is jogging before he is placed")
	var at := Transform3D(Basis(Vector3.UP, deg_to_rad(-120)), Vector3(3, 0, -4))
	actor.set_brain(Brain.new())
	actor.place(at)
	assert_vec_near(actor.global_position, at.origin, 1e-6, "he is there")
	assert_vec_near(actor.get_global_transform_interpolated().origin, at.origin, 1e-6, "and drawn there, not on the way")
	assert_near(actor.locomotion.facing_yaw, deg_to_rad(-120), 1e-5, "facing the transform's +Z")
	assert_near(actor.locomotion.speed, 0.0, 1e-9, "at rest")
	assert_vec_near(actor.velocity, Vector3.ZERO, 1e-9, "not moving")
	await frames(10)
	assert_vec_near(actor.global_position, at.origin, 0.01, "he stays there")
	assert_near(actor.rotation.y, deg_to_rad(-120), 1e-4, "still facing that way")


# snap_facing turns the body and locomotion's facing at once, with no turn rate in it: what a roll does to face the
# stick, and what an aim assist does to face a foe.
func test_snap_facing_turns_the_body_and_locomotion_at_once() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, _def(), Brain.new())
	actor.snap_facing(2.0)
	assert_near(actor.locomotion.facing_yaw, 2.0, 1e-9)
	assert_near(actor.rotation.y, 2.0, 1e-9)
	await frames(3)
	assert_near(actor.rotation.y, 2.0, 1e-6, "and he keeps facing it, wanting nothing")
	assert_vec_near(actor.facing(), Vector3(sin(2.0), 0, cos(2.0)), 1e-6)


# head_point is where others look at an actor: look_height above his feet, wherever he stands.
func test_head_point_is_look_height_above_the_feet() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, _def(), Brain.new(), Vector3(2, 0, -1))
	assert_near(_def().look_height, 1.6, 1e-9, "the default")
	assert_vec_near(actor.head_point(), Vector3(2, 1.6, -1), 1e-6)
	var tall := _def().duplicate() as ActorDef
	tall.look_height = 2.4
	var giant := TestArena.spawn(arena, tall, Brain.new(), Vector3(-3, 0, 0))
	assert_vec_near(giant.head_point(), Vector3(-3, 2.4, 0), 1e-6, "a taller def, a higher point")


# The roll carries the speed he ran at (locomotion.speed), so that he runs on from it when the roll is done. The
# rig's locomotion layer, which the move layer is laid over, rests meanwhile: it would show a run under the roll.
func test_locomotion_layer_rests_while_a_move_plays() -> void:
	var arena := TestArena.make(self)
	var ahead := Vector2(0, 1)
	var brain := ScriptBrain.new([{"frames": 40, "move": ahead}, {"frames": 1, "press": [&"dodge"], "move": ahead}, {"frames": 60}])
	var actor := TestArena.spawn(arena, _def(), brain)
	await frames(30)
	assert_true(float(actor.rig.tree.get(Rig.LOCO_SPEED)) > 3.0, "running: %s" % actor.rig.tree.get(Rig.LOCO_SPEED))
	while not actor.runner.busy():
		await frames(1)
	await frames(5)
	assert_true(actor.runner.busy(), "mid-roll")
	assert_true(actor.locomotion.speed > 1.0, "the roll carries speed (%s)" % actor.locomotion.speed)
	assert_near(float(actor.rig.tree.get(Rig.LOCO_SPEED)), 0.0, 1e-9, "but the locomotion layer is at rest")
	while actor.runner.busy():
		await frames(1)
	await frames(1)
	assert_near(float(actor.rig.tree.get(Rig.LOCO_SPEED)), actor.locomotion.speed, 1e-6, "and takes the speed up again when the roll is over")


# Ten seconds on a pad resting at each reading, one actor per reading, 6 m apart.
func test_drift_does_not_move_actor() -> void:
	var drifts: Array[Vector2] = [Vector2(0.15, 0), Vector2(0.15, 0.15), Vector2(0.19, 0.19), Vector2(0.12, 0.17), Vector2(-0.19, 0.19)]
	var arena := TestArena.make(self)
	var actors: Array[Actor] = []
	for i in drifts.size():
		actors.append(TestArena.spawn(arena, _def(), DriftBrain.new(drifts[i]), Vector3(6.0 * i - 12.0, 0, 0)))
	await frames(600)
	for i in drifts.size():
		var actor := actors[i]
		var start := Vector3(6.0 * i - 12.0, 0, 0)
		assert_true(actor.frame >= 600, str(drifts[i]))
		assert_true(actor.global_position.distance_to(start) < 0.01, "at %s he moved %.3f m, to %s" % [drifts[i], actor.global_position.distance_to(start), actor.global_position])
		assert_eq(actor.locomotion.facing_yaw, 0.0, "at %s he still faces the way he started" % drifts[i])
		assert_vec_near(actor.facing(), Vector3(0, 0, 1), 1e-6, str(drifts[i]))


# A light push just past the drift, and a full one, do move him, the way the stick points (right is +X).
func test_a_real_push_moves_actor() -> void:
	var arena := TestArena.make(self)
	var light := TestArena.spawn(arena, _def(), DriftBrain.new(Vector2(0.35, 0)), Vector3(-10, 0, -6))
	var full := TestArena.spawn(arena, _def(), DriftBrain.new(Vector2(1, 0)), Vector3(-10, 0, 6))
	await frames(120)
	var light_moved := light.global_position - Vector3(-10, 0, -6)
	var full_moved := full.global_position - Vector3(-10, 0, 6)
	assert_true(light_moved.x > 0.2, "a 0.35 push moved him %s in 2 s" % light_moved)
	assert_true(full_moved.x > 4.0 * light_moved.x, "a full push moved him %s, far more" % full_moved)
	assert_vec_near(light.facing(), Vector3(1, 0, 0), 1e-3, "he turned to face +X")
	assert_vec_near(full.facing(), Vector3(1, 0, 0), 1e-3, "he turned to face +X")


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
