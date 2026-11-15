extends TestCase
## What plants a fighter on pale snow is the dark under his feet, in the sun and in the shade of a front (the sun's own shadow is
## not there where a wall already shades the ground): the stretch's region script (world/bilibara/bilibara_region.gd) lays a soft
## dark ellipse (render/shaders/contact_shadow.gdshader) flat under every actor in the region's tree and takes it away with him: all of them one MultiMesh. The
## training yard has none. How dark it is on the picture is held by test_bilibara_readability.

const REGION := "res://world/bilibara/bilibara.tscn"
const YARD := "res://world/training_yard/training_yard.tscn"
const SHADER := "res://render/shaders/contact_shadow.gdshader"


func _stage(path: String) -> Node3D:
	var region := (load(path) as PackedScene).instantiate() as Node3D
	track(region)
	return region


func _spawn(region: Node3D, at: Vector3, def_path := "res://data/actors/knuckle_1.tres") -> Actor:
	return TestArena.spawn(region, load(def_path) as ActorDef, Brain.new(), at)


# The ellipses under the actors in the tree (the MultiMesh's visible instances, which the region keeps the points of): their ground points, in the order the actors come in the group.
func _shadows(region: Node3D) -> Array[Vector3]:
	var found: Array[Vector3] = []
	if region.has_method(&"shadow_points"):
		found.assign(region.call(&"shadow_points"))
	return found


func _is_under(shadows: Array[Vector3], actor: Actor) -> bool:
	return shadows.any(func(at: Vector3) -> bool: return absf(at.x - actor.global_position.x) < 0.001 and absf(at.z - actor.global_position.z) < 0.001)


# One MultiMeshInstance3D holds every ellipse: however many fighters there are, the shadows are one draw call.
func test_every_actor_in_the_stretch_has_a_soft_ellipse_flat_under_his_feet_in_one_draw() -> void:
	var region := _stage(REGION)
	var a := _spawn(region, Vector3(27.5, 0.0, -30.0), "res://data/actors/abarax.tres")
	var b := _spawn(region, Vector3(30.0, 0.0, -30.0))
	await frames(3)
	var holder := region.get_node(^"ContactShadows")
	assert_eq(holder.get_child_count(), 1, "one node holds them all")
	var shadows := holder.get_node(^"Shadows") as MultiMeshInstance3D
	assert_eq(shadows.multimesh.visible_instance_count, 2, "one ellipse for each of the two actors")
	var at := _shadows(region)
	for actor: Actor in [a, b]:
		assert_true(_is_under(at, actor), "an ellipse is under %s" % actor.name)
	for point in at:
		assert_true(point.y > 0.002 and point.y < 0.05, "an ellipse lies %.3f m above the ground, on it and not in the feet" % point.y)
	assert_eq(shadows.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "it casts none")
	assert_eq(shadows.layers, Layers.RENDER_WORLD, "it is drawn with the world")
	var material := shadows.material_override as ShaderMaterial
	assert_true(material != null and material.shader.resource_path == SHADER, "drawn by the contact shadow shader")
	var quad := shadows.multimesh.mesh as QuadMesh
	assert_eq(quad.orientation, PlaneMesh.FACE_Y, "it lies flat")
	# Eight bodies: still the one node, and the count grows by doubling past its first room.
	var more: Array[Actor] = []
	for i in 20:
		more.append(_spawn(region, Vector3(27.5 + 0.1 * i, 0.0, -35.0 - 0.8 * (i % 5)), "res://data/actors/knuckle_1.tres"))
	await frames(3)
	assert_eq(shadows.multimesh.visible_instance_count, 22, "an ellipse for each of 22 actors")
	assert_true(shadows.multimesh.instance_count >= 22, "the MultiMesh grew to hold them")
	assert_eq(holder.get_child_count(), 1, "still one node")


func test_a_shadow_follows_his_actor_hides_with_him_and_goes_when_he_does() -> void:
	var region := _stage(REGION)
	var a := _spawn(region, Vector3(27.5, 0.0, -30.0))
	await frames(3)
	a.global_position = Vector3(26.0, 0.0, -28.0)
	await frames(2)
	var at := _shadows(region)
	assert_eq(at.size(), 1, "one")
	if at.is_empty():
		return
	assert_true(absf(at[0].x - 26.0) < 0.001 and absf(at[0].z + 28.0) < 0.001, "it moved with him")
	a.visible = false
	await frames(2)
	assert_eq(_shadows(region).size(), 0, "hidden with him")
	a.visible = true
	await frames(2)
	assert_eq(_shadows(region).size(), 1, "shown with him")
	a.queue_free()
	await frames(3)
	assert_eq(_shadows(region).size(), 0, "gone with him")


func test_the_stretch_keeps_its_script_and_its_grade() -> void:
	# The region's script is set by the layout after the grade line's value would be lost with a script swap (the builder keeps it): the
	# whole noon grade rests on this.
	var region := _stage(REGION)
	assert_true(region.get_script() != null and (region.get_script() as Script).resource_path == "res://world/bilibara/bilibara_region.gd", "the region's script")
	var grade := region.get(&"grade") as Resource
	assert_true(grade != null and grade.resource_path == "res://data/render/grades/bilibara_noon.tres", "and the noon grade (%s)" % [grade.resource_path if grade != null else "none"])
	assert_true(region is Region, "it is still a Region")


func test_the_training_yard_has_none() -> void:
	var region := _stage(YARD)
	var a := _spawn(region, Vector3(0.0, 0.0, 3.0))
	await frames(3)
	assert_true(a != null)
	assert_true(region.get_node_or_null(^"ContactShadows") == null, "the yard has no contact shadows")
