extends TestCase
## The region builder's commands for the Bilibara stretch (tools/world/build_region.gd and region_blocks.gd): `ground`,
## `block`, `water`, `vat`, `fill`, the `world` option of `lamps` and the five stones a `curb` can be made of, each on a
## small layout; and that the two older regions still build the scenes they were built as.

const BUILDER := preload("res://tools/world/build_region.gd")
const KENNEY_DIR := "res://assets/env/kenney_town/"
const KENNEY := KENNEY_DIR + "%s.glb"
const MATERIALS := "res://world/materials/%s.tres"
const TILE := 2.5


## Builds `text`; returns {root, problems}. The root is tracked, so it is in the tree and freed after the test.
func _build(text: String) -> Dictionary:
	var builder := BUILDER.Builder.new()
	builder.layout = "T.txt"
	var root := builder.build(text, "T")
	track(root)
	return {root = root, problems = builder.problems}


# Every StaticBody3D under `node`.
func _bodies(node: Node) -> Array[StaticBody3D]:
	var found: Array[StaticBody3D] = []
	for body in node.find_children("*", "StaticBody3D", true, false):
		found.append(body as StaticBody3D)
	return found


# Every Kenney piece instance under `node`, by the piece's name.
func _pieces(node: Node, piece := "") -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in node.find_children("*", "Node3D", true, false):
		if child.scene_file_path.begins_with(KENNEY_DIR) and (piece == "" or child.scene_file_path == KENNEY % piece):
			found.append(child as Node3D)
	return found


# The bounds of the meshes under `node` in world space.
func _world_box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _material(material_name: String) -> Material:
	return load(MATERIALS % material_name) as Material


func test_ground_is_a_box_with_its_top_at_zero_on_world_and_feet_and_walkable() -> void:
	var built := _build("ground 0 0 10 10 cobble")
	assert_eq(built.problems, PackedStringArray())
	var plate := (built.root as Node).get_node_or_null("Walkable/Ground") as StaticBody3D
	assert_true(plate != null, "a body called Ground under Walkable")
	if plate == null:
		return
	assert_eq(plate.collision_layer, Layers.WORLD | Layers.IK_SURFACE, "on world and ik_surface")
	var shape := plate.get_node("Shape") as CollisionShape3D
	var size := (shape.shape as BoxShape3D).size
	assert_vec_near(size, Vector3(10, 1.0, 10), 1e-6, "10 x 10 and 1 m thick")
	assert_near(plate.global_position.y + shape.position.y + size.y / 2, 0.0, 1e-6, "the top is at y = 0")
	assert_vec_near(plate.global_position + shape.position, Vector3(5, -0.5, 5), 1e-6, "over the rectangle")
	var mesh := plate.get_node("Mesh") as MeshInstance3D
	assert_eq(mesh.material_override, _material("cobble"), "in cobble")
	assert_true((mesh.material_override as ShaderMaterial).get_shader_parameter(&"world_uv"), "laid by the world's metres")
	assert_eq((mesh.material_override as ShaderMaterial).get_shader_parameter(&"texels_per_metre"), 32.0)


func test_ground_takes_each_of_the_five_stones_and_curb_does_too() -> void:
	for stone in ["flagstone", "slate", "cobble", "tan_earth", "snow"]:
		var built := _build("ground 0 0 5 5 %s\ncurb 0 5 5 5.5 0.3 %s" % [stone, stone])
		assert_eq(built.problems, PackedStringArray(), stone)
		var plate := (built.root as Node).get_node("Walkable/Ground/Mesh") as MeshInstance3D
		var curb := (built.root as Node).get_node("Curb/Mesh") as MeshInstance3D
		assert_eq(plate.material_override, _material(stone), "ground in %s" % stone)
		assert_eq(curb.material_override, _material(stone), "curb in %s" % stone)
	var bad := _build("ground 0 0 5 5 marble")
	assert_eq(bad.problems.size(), 1, "an unknown stone is a problem: %s" % [bad.problems])


func test_a_ground_wider_than_12_5_m_is_a_problem() -> void:
	assert_eq(_build("ground 0 0 12.5 10 slate").problems, PackedStringArray(), "12.5 m is fine")
	var built := _build("# a comment\nground 0 0 15 10 slate")
	assert_eq(built.problems.size(), 1, "one problem: %s" % [built.problems])
	if built.problems.size() == 1:
		assert_true((built.problems[0] as String).begins_with("T.txt:2:"), "it names the line: %s" % built.problems[0])
	assert_eq(_build("ground 0 0 10 12.6 slate").problems.size(), 1, "the other side too")


func test_visual_ground_has_no_collider_and_is_backdrop() -> void:
	var built := _build("ground 0 0 5 5 snow visual")
	var root := built.root as Node
	assert_eq(built.problems, PackedStringArray())
	assert_true(root.get_node_or_null("Backdrop") != null and root.get_node_or_null("Walkable") == null, "under Backdrop, not Walkable")
	assert_eq(root.find_children("*", "CollisionObject3D", true, false).size(), 0, "no collider")
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1, "one box to see")
	for mesh: MeshInstance3D in meshes:
		assert_eq(mesh.material_override, _material("snow"), "in snow")
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "it casts no shadow")
		assert_near((mesh.global_transform * mesh.get_aabb()).end.y, 0.0, 1e-6, "its top is at y = 0")


func test_a_block_stacks_its_front_by_storeys_and_roofs_its_footprint() -> void:
	var built := _build("block 0 0 10 5 3 frontage flat")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	var roofs := _pieces(root, "roof-flat")
	var front := _pieces(root).filter(func(n: Node3D) -> bool: return n.scene_file_path != KENNEY % "roof-flat")
	assert_eq(front.size(), 12, "4 tiles x 3 storeys of front")
	assert_eq(roofs.size(), 8, "4 x 2 tiles of roof")
	var storeys := {}
	for piece: Node3D in front:
		storeys[snappedf(piece.global_position.y, 0.001)] = true
		assert_vec_near(piece.global_basis.get_scale(), Vector3.ONE * 2.5, 1e-4, "%s at x2.5" % piece.name)
		assert_near(_world_box(piece).end.z, 5.0, 1e-3, "%s: the face is on z = 5" % piece.name)
	assert_eq(storeys.keys(), [0.0, 2.5, 5.0], "at y = 0, 2.5 and 5")
	for roof: Node3D in roofs:
		assert_near(roof.global_position.y, 7.5, 1e-6, "roofs at y = 7.5")
		assert_vec_near(roof.global_basis.get_scale(), Vector3.ONE * 2.5, 1e-4)
	var centres := {}
	for roof: Node3D in roofs:
		centres[Vector2(snappedf(roof.global_position.x, 0.01), snappedf(roof.global_position.z, 0.01))] = true
	assert_eq(centres.size(), 8, "one to a tile")
	for x in [1.25, 3.75, 6.25, 8.75]:
		for z in [1.25, 3.75]:
			assert_true(centres.has(Vector2(x, z)), "a roof tile at (%s, %s)" % [x, z])
	# Their material is the kit's colormap.
	for piece: Node3D in front + roofs:
		for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			assert_eq(mesh.get_active_material(0), _material("kenney_town"), "%s is in the kit's material" % piece.name)


func test_the_styles_choose_pieces_by_storey_and_tile_index() -> void:
	# frontage: a ground storey of door, wall, window, wall, window, wall; the upper of shutters, shutters, wall, balcony.
	var built := _build("block 0 0 15 5 2 frontage flat")
	var by_tile := {}
	for piece: Node3D in _pieces(built.root, ""):
		if piece.scene_file_path == KENNEY % "roof-flat":
			continue
		var tile := floori(_world_box(piece).get_center().x / TILE)
		var storey := roundi(piece.global_position.y / TILE)
		by_tile[Vector2i(tile, storey)] = piece.scene_file_path.get_file().get_basename()
	var ground := ["wall-door", "wall", "wall-window-small", "wall", "wall-window-small", "wall"]
	var upper := ["wall-window-shutters", "wall-window-shutters", "wall", "balcony-wall"]
	for k in 6:
		assert_eq(by_tile.get(Vector2i(k, 0)), ground[k], "ground storey, tile %d" % k)
		assert_eq(by_tile.get(Vector2i(k, 1)), upper[k % 4], "upper storey, tile %d" % k)
	var wood := _build("block 0 0 12.5 5 2 tannery slope")
	var names := {}
	for piece: Node3D in _pieces(wood.root, ""):
		names[piece.scene_file_path.get_file().get_basename()] = true
	for expected in ["wall-wood-door", "wall-wood", "wall-wood-window-small", "wall-wood-window-shutters", "roof"]:
		assert_true(names.has(expected), "a tannery has %s" % expected)
	var shed := _build("block 0 0 5 5 1 shed high")
	var plain := _build("block 0 0 5 5 1 plain flat")
	assert_true(_pieces(shed.root, "wall-wood").size() == 2 and _pieces(shed.root, "roof-high").size() == 4, "a shed is wall-wood under roof-high")
	assert_true(_pieces(plain.root, "wall").size() == 2 and _pieces(plain.root, "roof-flat").size() == 4, "plain is wall under roof-flat")


func test_a_solid_block_has_one_box_over_its_footprint_and_casts_shadows() -> void:
	var solid := _build("block 0 0 10 5 3 frontage flat solid")
	assert_eq(solid.problems, PackedStringArray())
	var root := solid.root as Node
	assert_true(root.get_node_or_null("Blocks") != null and root.get_node_or_null("Backdrop") == null, "under Blocks")
	var bodies := _bodies(root)
	assert_eq(bodies.size(), 1, "one body")
	var body := bodies[0]
	assert_eq(body.collision_layer, Layers.WORLD | Layers.IK_SURFACE, "on world and ik_surface")
	assert_eq(body.get_children().filter(func(c: Node) -> bool: return c is CollisionShape3D).size(), 1, "with one shape")
	var shape := body.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	assert_vec_near((shape.shape as BoxShape3D).size, Vector3(10, 7.5, 5), 1e-6, "10 x 7.5 x 5")
	assert_vec_near(shape.global_position, Vector3(5, 3.75, 2.5), 1e-6, "over the footprint, from the ground up")
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		assert_ne(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts shadows" % mesh.name)
	var visual := _build("block 0 0 10 5 3 frontage flat")
	var vroot := visual.root as Node
	assert_true(vroot.get_node_or_null("Backdrop") != null and vroot.get_node_or_null("Blocks") == null, "under Backdrop")
	assert_eq(vroot.find_children("*", "CollisionObject3D", true, false).size(), 0, "no collider")
	var meshes := vroot.find_children("*", "MeshInstance3D", true, false)
	assert_true(meshes.size() > 0)
	for mesh: MeshInstance3D in meshes:
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % mesh.name)


func test_a_block_that_is_not_whole_tiles_or_has_an_unknown_style_or_roof_is_a_problem() -> void:
	assert_eq(_build("block 0 0 10 5 3 frontage flat").problems, PackedStringArray(), "the good one")
	for line in ["block 0 0 11 5 3 frontage flat", "block 0 0 10 4 3 frontage flat", "block 0 0 10 5 3 castle flat",
			"block 0 0 10 5 3 frontage pointed", "block 0 0 10 5 0 frontage flat", "block 0 0 10 5 6 frontage flat",
			"block 0 0 10 5 1.5 frontage flat", "block 0 0 10 5 3 frontage flat hollow", "block 0 0 10 5 3 frontage"]:
		var built := _build("\n" + line)
		assert_eq(built.problems.size(), 1, "%s is one problem: %s" % [line, built.problems])
		if built.problems.size() == 1:
			assert_true((built.problems[0] as String).begins_with("T.txt:2:"), "%s names its line" % line)


# The height at which a ray straight down at (x, z) meets the meshes under `node`; -INF if it misses.
func _height_at(node: Node3D, x: float, z: float) -> float:
	var best := -INF
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var triangles := mesh.mesh.generate_triangle_mesh()
		var to_local := mesh.global_transform.affine_inverse()
		var from := to_local * Vector3(x, 20.0, z)
		var direction := (to_local.basis * Vector3.DOWN).normalized()
		var hit := triangles.intersect_ray(from, direction)
		if not hit.is_empty():
			best = maxf(best, (mesh.global_transform * (hit.position as Vector3)).y)
	return best


func test_a_slope_roof_is_higher_at_its_north_edge() -> void:
	for roof in ["slope", "high"]:
		var built := _build("block 0 0 5 5 1 plain %s" % roof)
		assert_eq(built.problems, PackedStringArray())
		var tiles := _pieces(built.root, "roof" if roof == "slope" else "roof-high")
		assert_eq(tiles.size(), 4, "%s: four tiles" % roof)
		for tile: Node3D in tiles:
			var north := _height_at(tile, tile.global_position.x, tile.global_position.z - 0.5)
			var south := _height_at(tile, tile.global_position.x, tile.global_position.z + 0.5)
			assert_true(north >= south + 0.2, "%s: 0.5 m north of the centre is at %.2f, 0.5 m south at %.2f" % [roof, north, south])
			assert_true(south > 2.5 - 0.01, "%s: the roof stands on the top storey (%.2f)" % [roof, south])


func test_a_vat_is_a_one_metre_solid_with_a_liquor_top() -> void:
	var built := _build("vat 5 7.5")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	var bodies := _bodies(root)
	assert_eq(bodies.size(), 1, "one body")
	var body := bodies[0]
	assert_eq(body.collision_layer, Layers.WORLD | Layers.IK_SURFACE, "solid")
	var shape := body.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	assert_vec_near((shape.shape as BoxShape3D).size, Vector3(2.5, 1.0, 2.5), 1e-6, "2.5 x 1 x 2.5, as seen")
	assert_vec_near(shape.global_position, Vector3(5, 0.5, 7.5), 1e-6)
	var meshes := root.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.mesh is BoxMesh)
	assert_eq(meshes.size(), 1)
	assert_eq((meshes[0] as MeshInstance3D).material_override, _material("slate"), "in slate")
	var liquor: MeshInstance3D = null
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == _material("liquor"):
			liquor = mesh
	assert_true(liquor != null, "a top in liquor")
	if liquor == null:
		return
	var top := liquor.global_transform * liquor.get_aabb()
	assert_vec_near(top.size * Vector3(1, 0, 1), Vector3(2.1, 0, 2.1), 1e-5, "2.1 x 2.1 m")
	assert_near(top.position.y, 1.01, 1e-6, "at y = 1.01")
	assert_vec_near(top.get_center() * Vector3(1, 0, 1), Vector3(5, 0, 7.5), 1e-5, "in the middle of the vat")
	assert_eq(root.find_children("*", "CollisionShape3D", true, false).size(), 1, "the liquor is not solid")


func test_water_is_a_thin_plane_in_the_water_or_the_liquor() -> void:
	var built := _build("water 0 10 20 30 -0.9\nwater 0 0 5 5 0.5 liquor")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	assert_eq(root.find_children("*", "CollisionObject3D", true, false).size(), 0, "no collider")
	var backdrop := root.get_node("Backdrop")
	var planes := backdrop.find_children("*", "MeshInstance3D", true, false)
	assert_eq(planes.size(), 2, "two planes under Backdrop")
	var first := planes[0] as MeshInstance3D
	var second := planes[1] as MeshInstance3D
	assert_eq(first.material_override, _material("kenney_water"), "water")
	assert_eq(second.material_override, _material("liquor"), "or liquor")
	var box := first.global_transform * first.get_aabb()
	assert_vec_near(box.position * Vector3(1, 0, 1), Vector3(0, 0, 10), 1e-5)
	assert_vec_near(box.size * Vector3(1, 0, 1), Vector3(20, 0, 20), 1e-5)
	assert_near(box.position.y, -0.9, 1e-6, "at its height")
	assert_true(box.size.y < 0.01, "thin")
	assert_near((second.global_transform * second.get_aabb()).position.y, 0.5, 1e-6)
	for plane: MeshInstance3D in planes:
		assert_eq(plane.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow")


func test_fill_is_a_bodies_only_light_called_fill_and_the_sun_leaves_the_bodies_to_it() -> void:
	for text in ["sun -50 35 #ffffff 1.0\nfill -35 25 #e6edff 1.3", "fill -35 25 #e6edff 1.3\nsun -50 35 #ffffff 1.0"]:
		var built := _build(text)
		assert_eq(built.problems, PackedStringArray())
		var fill := (built.root as Node).get_node_or_null("Fill") as DirectionalLight3D
		var sun := (built.root as Node).get_node("Sun") as DirectionalLight3D
		assert_true(fill != null, "a Fill")
		if fill == null:
			continue
		assert_eq(fill.light_cull_mask, Layers.RENDER_BODIES, "it lights the bodies and nothing else")
		assert_false(fill.shadow_enabled, "and casts no shadow")
		assert_near(fill.light_energy, 1.3, 1e-6)
		assert_eq(fill.light_color.to_html(false), "e6edff")
		assert_eq(sun.light_cull_mask & Layers.RENDER_BODIES, 0, "the sun leaves the bodies out (%s)" % text.split("\n")[0])
		assert_true(sun.light_cull_mask & Layers.RENDER_WORLD != 0, "and lights the world")
		assert_true(sun.shadow_enabled and sun.shadow_caster_mask & Layers.RENDER_BODIES != 0, "but still casts their shadows")
	var moonlit := _build("sun -50 35 #ffffff 1.0\nmoon -35 25 #e6edff 1.3")
	assert_eq(((moonlit.root as Node).get_node("Sun") as DirectionalLight3D).light_cull_mask & Layers.RENDER_BODIES, 0, "a moon does the same")
	var lone := _build("sun -50 35 #ffffff 1.0")
	assert_true(((lone.root as Node).get_node("Sun") as DirectionalLight3D).light_cull_mask & Layers.RENDER_BODIES != 0, "with neither, the sun lights the bodies")
	assert_eq(_build("fill 1 2 #ffffff").problems.size(), 1, "fill needs four words")


func test_lamps_world_lights_only_the_world() -> void:
	var worldly := _build("lamps #ffb98a 6 0.5 3.45 world\nlantern 2 2")
	assert_eq(worldly.problems, PackedStringArray())
	var lamp := (worldly.root as Node).find_children("Lamp", "OmniLight3D", true, false)[0] as OmniLight3D
	assert_eq(lamp.light_cull_mask, Layers.RENDER_WORLD, "the lamp lights the world only")
	assert_near(lamp.omni_range, 6.0, 1e-6)
	assert_near(lamp.light_energy, 0.5, 1e-6)
	var both := _build("lamps #ffb98a 6 0.5 3.45\nlantern 2 2")
	var lamp_both := (both.root as Node).find_children("Lamp", "OmniLight3D", true, false)[0] as OmniLight3D
	assert_true(lamp_both.light_cull_mask & Layers.RENDER_BODIES != 0 and lamp_both.light_cull_mask & Layers.RENDER_WORLD != 0, "without it a lantern lights both")
	assert_eq(_build("lamps #ffb98a 6 0.5 3.45 sky").problems.size(), 1, "a fifth word that is not `world` is a problem")


# --- the older regions ---

# What the builder makes of a node, and what a scene holds of it, as a line of text: its class, transform and the settings
# a layout can set. The insides of an instanced piece are the piece's own.
func _describe(node: Node, path: String, out: PackedStringArray) -> void:
	var instanced := not node.scene_file_path.is_empty() and path.contains("/")
	var line := "%s %s" % [path, node.get_class()]
	if node.get_script() != null:
		line += " script=%s" % (node.get_script() as Script).resource_path
	if instanced:
		line += " scene=%s" % node.scene_file_path
	if node is Node3D:
		var t := (node as Node3D).transform
		for v in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
			line += " (%.3f %.3f %.3f)" % [v.x, v.y, v.z]
	if node is Light3D:
		var light := node as Light3D
		line += " light %s %.3f cull=%d shadow=%s casters=%d" % [light.light_color.to_html(), light.light_energy, light.light_cull_mask, light.shadow_enabled, light.shadow_caster_mask]
		if light is OmniLight3D:
			line += " range=%.3f" % (light as OmniLight3D).omni_range
	if node is CollisionObject3D:
		line += " layer=%d mask=%d" % [(node as CollisionObject3D).collision_layer, (node as CollisionObject3D).collision_mask]
	if node is CollisionShape3D:
		var shape := (node as CollisionShape3D).shape
		line += " %s" % shape.get_class()
		if shape is BoxShape3D:
			line += " %s" % (shape as BoxShape3D).size
		elif shape is CylinderShape3D:
			line += " r=%.3f h=%.3f" % [(shape as CylinderShape3D).radius, (shape as CylinderShape3D).height]
		elif shape is ConvexPolygonShape3D:
			line += " %d points" % (shape as ConvexPolygonShape3D).points.size()
	if node is MeshInstance3D and not instanced:
		var mesh := node as MeshInstance3D
		line += " %s layers=%d" % [mesh.mesh.get_class(), mesh.layers]
		if mesh.mesh is BoxMesh:
			line += " %s" % (mesh.mesh as BoxMesh).size
		if mesh.material_override != null:
			line += " material=%s" % mesh.material_override.resource_path
	if node is WorldEnvironment:
		var env := (node as WorldEnvironment).environment
		line += " bg=%s ambient=%s %.3f" % [env.background_color.to_html(), env.ambient_light_color.to_html(), env.ambient_light_energy]
	if node.get(&"grade") != null:
		line += " grade=%s" % (node.get(&"grade") as Resource).resource_path
	out.append(line)
	if not instanced:
		for child in node.get_children():
			_describe(child, "%s/%s" % [path, child.name], out)


func _same_scene(layout: String, scene: String, root_name: String) -> void:
	var builder := BUILDER.Builder.new()
	builder.layout = layout
	var built := builder.build(FileAccess.get_file_as_string(layout), root_name)
	assert_eq(builder.problems, PackedStringArray(), layout)
	var committed := (load(scene) as PackedScene).instantiate()
	var made := PackedStringArray()
	var had := PackedStringArray()
	_describe(built, root_name, made)
	_describe(committed, root_name, had)
	built.free()
	committed.free()
	assert_true(made.size() > 20, "%s builds something (%d nodes)" % [layout, made.size()])
	assert_eq(made.size(), had.size(), "%s: the same number of nodes" % layout)
	var differing := PackedStringArray()
	for i in mini(made.size(), had.size()):
		if made[i] != had[i]:
			differing.append("built:  %s\n  scene:  %s" % [made[i], had[i]])
	assert_eq(differing.slice(0, 3), PackedStringArray(), "%s: nodes that differ" % layout)


func test_the_old_layouts_still_build_the_same_scenes() -> void:
	_same_scene("res://world/courtyard/layout.txt", "res://world/courtyard/courtyard.tscn", "Courtyard")
	_same_scene("res://world/training_yard/layout.txt", "res://world/training_yard/training_yard.tscn", "TrainingYard")
