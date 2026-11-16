extends TestCase
## A rim's dark edge (Rig.RIM_INK_COLOR, a second hull outside the rim) is the Bilibara stretch's: its pale ground is what needs it. In the
## training yard a rim reads by its own light and the edge would only change the pictures those rims are measured by, so a body there has
## no ink pass at all. The stretch's region script hands the ink to every actor in its tree, a foe that comes later too, and takes it off
## again from a body that leaves (the player's body goes from region to region). The pictures are held by test_bilibara_cues and the yard's own
## render tests.

const STRETCH := "res://world/bilibara/bilibara.tscn"
const YARD := "res://world/training_yard/training_yard.tscn"
const FOE := "res://data/actors/knuckle_1.tres"
const ABARAX := "res://data/actors/abarax.tres"


func _stage(path: String) -> Node3D:
	var region := (load(path) as PackedScene).instantiate() as Node3D
	track(region)
	return region


func _spawn(parent: Node3D, at: Vector3, def_path := FOE) -> Actor:
	return TestArena.spawn(parent, load(def_path) as ActorDef, Brain.new(), at)


func _meshes(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		_meshes(child, found)


# How many passes the body's rim has over its meshes with the aura on: the mark, the rim, and the ink if it is on (every mesh with an overlay
# must agree). 0 when there is no overlay.
func _passes(actor: Actor) -> int:
	var meshes: Array[MeshInstance3D] = []
	_meshes(actor.rig, meshes)
	var counts := {}
	for mesh in meshes:
		var n := 0
		var pass_ := mesh.material_overlay
		while pass_ != null:
			n += 1
			pass_ = pass_.next_pass
		if n > 0:
			counts[n] = true
	assert_eq(counts.size(), 1, "every mesh of %s carries the same chain of passes (%s)" % [actor.name, counts.keys()])
	return counts.keys()[0] if counts.size() == 1 else 0


func _rim_on(actor: Actor) -> void:
	actor.rig.hold_aura(Color(0.5, 0.8, 1.0), 1.0)


func test_a_body_in_the_training_yard_has_no_ink_pass() -> void:
	var region := _stage(YARD)
	var a := _spawn(region, Vector3(0.0, 0.0, 0.0), ABARAX)
	await frames(3)
	_rim_on(a)
	await frames(3)
	assert_eq(_passes(a), 2, "the yard's rim is the mark and the hull, and no ink")


func test_a_body_in_the_stretch_has_it_a_foe_that_comes_later_too() -> void:
	var region := _stage(STRETCH)
	var a := _spawn(region, Vector3(27.5, 0.0, -30.0), ABARAX)
	await frames(3)
	_rim_on(a)
	await frames(2)
	assert_eq(_passes(a), 3, "in the stretch the rim is the mark, the hull and the ink")
	var foe := _spawn(region, Vector3(30.0, 0.0, -30.0))
	await frames(2)
	_rim_on(foe)
	await frames(2)
	assert_eq(_passes(foe), 3, "a foe that came later has the ink")
	# A rim that is lit before the region has seen the body for a frame has it by the time it is drawn.
	var late := _spawn(region, Vector3(32.0, 0.0, -30.0))
	_rim_on(late)
	await frames(2)
	assert_eq(_passes(late), 3, "a rim lit in the body's first frame has the ink by the second")


func test_a_body_that_leaves_the_stretch_has_none() -> void:
	var world := Node3D.new()
	track(world)
	var region := (load(STRETCH) as PackedScene).instantiate() as Node3D
	world.add_child(region)
	var mine := _spawn(world, Vector3(27.5, 0.0, -30.0), ABARAX)  # the player's body is not in the region: it is Main's
	await frames(3)
	_rim_on(mine)
	await frames(2)
	assert_eq(_passes(mine), 3, "in the stretch it has the ink")
	world.remove_child(region)
	region.queue_free()
	var yard := (load(YARD) as PackedScene).instantiate() as Node3D
	world.add_child(yard)
	await frames(3)
	assert_eq(_passes(mine), 2, "after the change of region to the yard the body has none")
	_rim_on(mine)
	await frames(2)
	assert_eq(_passes(mine), 2, "and a rim lit there has none")
