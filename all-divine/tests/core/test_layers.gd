extends TestCase
## Layers (core/layers.gd): the physics layers by name, and the render layers. The constants are what project.godot's
## layer names give, so a layer renamed or moved there shows up here rather than as a mask that hits nothing.


func test_constants_match_project_layer_names() -> void:
	for pair in [["world", Layers.WORLD], ["ik_surface", Layers.IK_SURFACE], ["actor", Layers.ACTOR],
			["hurtbox", Layers.HURTBOX], ["hitbox", Layers.HITBOX], ["interact", Layers.INTERACT]]:
		assert_eq(Layers.bit(pair[0]), pair[1], pair[0])


func test_unknown_layer_is_zero() -> void:
	assert_eq(Layers.bit("nope"), 0)


func test_render_layers_match_the_project_too() -> void:
	for pair in [["lanterns", Layers.RENDER_LANTERNS], ["bodies", Layers.RENDER_BODIES]]:
		assert_eq(Layers.render_bit(pair[0]), pair[1], pair[0])
	assert_eq(Layers.render_bit("nope"), 0)
	assert_eq(Layers.RENDER_WORLD, 1, "what has no layer of its own is on the first")
