extends TestCase
## What plants a fighter on pale snow is the dark under his feet, in the sun and in the shade of a front (the sun's own shadow is
## not there where a wall already shades the ground): the stretch's region script (world/bilibara/bilibara_region.gd) lays a soft
## dark ellipse (render/shaders/contact_shadow.gdshader) flat under every actor in the region's tree and takes it away with him. The
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


func _shadows(region: Node3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var holder := region.get_node_or_null(^"ContactShadows")
	if holder != null:
		for child in holder.get_children():
			if child is MeshInstance3D:
				found.append(child)
	return found


func test_every_actor_in_the_stretch_has_a_soft_ellipse_flat_under_his_feet() -> void:
	var region := _stage(REGION)
	var a := _spawn(region, Vector3(27.5, 0.0, -30.0), "res://data/actors/abarax.tres")
	var b := _spawn(region, Vector3(30.0, 0.0, -30.0))
	await frames(3)
	var shadows := _shadows(region)
	assert_eq(shadows.size(), 2, "one shadow for each of the two actors")
	if shadows.size() != 2:
		return
	for i in 2:
		var actor := [a, b][i] as Actor
		var shadow := shadows[i]
		assert_true(absf(shadow.global_position.x - actor.global_position.x) < 0.001 and absf(shadow.global_position.z - actor.global_position.z) < 0.001, "shadow %d is under its actor" % i)
		var up := shadow.global_position.y - actor.global_position.y
		assert_true(up > 0.002 and up < 0.05, "shadow %d lies %.3f m above the ground, on it and not in the feet" % [i, up])
		assert_eq(shadow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "it casts none")
		assert_eq(shadow.layers, Layers.RENDER_WORLD, "it is drawn with the world")
		var material := shadow.material_override as ShaderMaterial
		assert_true(material != null and material.shader.resource_path == SHADER, "drawn by the contact shadow shader")
		var normal := shadow.global_transform.basis * Vector3.BACK
		assert_true(shadow.get_aabb().size.y < 0.001 or absf(normal.normalized().y) > 0.99 or absf((shadow.global_transform.basis * Vector3.UP).normalized().z) > 0.99, "it lies flat")


func test_a_shadow_follows_his_actor_hides_with_him_and_goes_when_he_does() -> void:
	var region := _stage(REGION)
	var a := _spawn(region, Vector3(27.5, 0.0, -30.0))
	await frames(3)
	a.global_position = Vector3(26.0, 0.0, -28.0)
	await frames(2)
	var shadows := _shadows(region)
	assert_eq(shadows.size(), 1, "one")
	if shadows.is_empty():
		return
	assert_true(absf(shadows[0].global_position.x - 26.0) < 0.001 and absf(shadows[0].global_position.z + 28.0) < 0.001, "it moved with him")
	a.visible = false
	await frames(2)
	assert_false(shadows[0].visible, "hidden with him")
	a.visible = true
	await frames(2)
	assert_true(shadows[0].visible, "shown with him")
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
