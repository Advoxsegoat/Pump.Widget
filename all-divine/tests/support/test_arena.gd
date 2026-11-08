class_name TestArena
extends RefCounted
## A flat place to stand actors in for tests: a 40 × 40 m floor with its top at y = 0, on the `world`
## and `ik_surface` layers, and one DirectionalLight3D.

const SIZE := 40.0
const ACTOR := "res://actors/actor.tscn"


## A new arena under `t`, which frees it after the test.
static func make(t: TestCase) -> Node3D:
	var arena := Node3D.new()
	arena.name = "Arena"
	var ground := StaticBody3D.new()
	ground.name = "Floor"
	ground.collision_layer = Layers.WORLD | Layers.IK_SURFACE
	ground.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, 1.0, SIZE)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	ground.add_child(mesh)
	arena.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 30, 0)
	arena.add_child(sun)
	t.track(arena)
	return arena


## An Actor of `def`, driven by `brain`, standing at `at` in `arena` (it is ready when this returns). It is
## called `actor_name` if one is given: the name is what an actor's breath phase comes from.
static func spawn(arena: Node3D, def: ActorDef, brain: Brain, at := Vector3.ZERO, actor_name := "") -> Actor:
	var actor := (load(ACTOR) as PackedScene).instantiate() as Actor
	if not actor_name.is_empty():
		actor.name = actor_name
	actor.def = def
	actor.position = at
	actor.set_brain(brain)
	arena.add_child(actor)
	return actor


## A wall in `arena`: a box of `size` whose centre is `at`, on the `world` layer. It is put there before it is in the
## tree, so it is never anywhere else for a frame (where it would shove an actor aside).
static func wall(arena: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = at
	arena.add_child(body)
	return body


## The collision bit of the 3D physics layer named `layer_name` in project.godot (Layers.bit), reporting a
## name that is not one: in a test that is a typo, not a layer to leave out.
static func layer_bit(layer_name: String) -> int:
	var bit := Layers.bit(layer_name)
	if bit == 0:
		push_error("TestArena: no physics layer called '%s'" % layer_name)
	return bit
