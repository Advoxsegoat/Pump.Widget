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


# Every kit piece placed under `node` (of the piece named `piece`, or any), whether it is a scene instance (`piece`, `edge`,
# `lantern`) or one instance of a block's MultiMeshes: {piece, xf (the piece's own transform), meshes: [{mesh, xf, material}]},
# the material being the one the piece is drawn in as things stand. The MultiMeshInstance3Ds of one piece are the sub-meshes
# of it, named alike, in the same order of instances, and carry the piece's name and the sub-mesh's own transform as meta.
func _placed(node: Node, piece := "") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var by_key := {}
	for child in node.find_children("*", "Node3D", true, false):
		if child is KitRun:
			var run := child as KitRun
			var material: Material = run.material_override if run.material_override != null else run.part.surface_get_material(0)
			for i in run.places.size():
				var key := "%s|%s|%s" % [run.get_parent().get_path(), run.piece, run.places[i].origin]
				if not by_key.has(key):
					by_key[key] = {piece = String(run.piece), xf = run.global_transform * run.places[i], meshes = []}
					found.append(by_key[key])
				by_key[key].meshes.append({mesh = run.part, xf = run.global_transform * run.places[i] * run.local, material = material})
		elif child.scene_file_path.begins_with(KENNEY_DIR):
			var record := {piece = child.scene_file_path.get_file().get_basename(), xf = child.global_transform, meshes = []}
			for mesh: MeshInstance3D in child.find_children("*", "MeshInstance3D", true, false):
				record.meshes.append({mesh = mesh.mesh, xf = mesh.global_transform, material = mesh.get_active_material(0)})
			found.append(record)
	return found.filter(func(r: Dictionary) -> bool: return piece == "" or r.piece == piece)


# The bounds of a placed piece's meshes in world space.
func _box(placed: Dictionary) -> AABB:
	var box := AABB()
	var first := true
	for m: Dictionary in placed.meshes:
		var b: AABB = m.xf * m.mesh.get_aabb()
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
	var roofs := _placed(root, "roof-flat")
	var front := _placed(root).filter(func(p: Dictionary) -> bool: return p.piece != "roof-flat")
	assert_eq(front.size(), 12, "4 tiles x 3 storeys of front")
	assert_eq(roofs.size(), 8, "4 x 2 tiles of roof")
	var storeys := {}
	for piece: Dictionary in front:
		storeys[snappedf(piece.xf.origin.y, 0.001)] = true
		assert_vec_near(piece.xf.basis.get_scale(), Vector3.ONE * 2.5, 1e-4, "%s at x2.5" % piece.piece)
		assert_near(_box(piece).end.z, 5.0, 1e-3, "%s: the face is on z = 5" % piece.piece)
	assert_eq(storeys.keys(), [0.0, 2.5, 5.0], "at y = 0, 2.5 and 5")
	for roof: Dictionary in roofs:
		assert_near(roof.xf.origin.y, 7.5, 1e-6, "roofs at y = 7.5")
		assert_vec_near(roof.xf.basis.get_scale(), Vector3.ONE * 2.5, 1e-4)
	var centres := {}
	for roof: Dictionary in roofs:
		centres[Vector2(snappedf(roof.xf.origin.x, 0.01), snappedf(roof.xf.origin.z, 0.01))] = true
	assert_eq(centres.size(), 8, "one to a tile")
	for x in [1.25, 3.75, 6.25, 8.75]:
		for z in [1.25, 3.75]:
			assert_true(centres.has(Vector2(x, z)), "a roof tile at (%s, %s)" % [x, z])
	# Their material is the kit's colormap.
	for piece: Dictionary in front + roofs:
		for m: Dictionary in piece.meshes:
			assert_eq(m.material, _material("kenney_town"), "%s is in the kit's material" % piece.piece)


# A block's pieces are drawn a kind at a time: one MultiMesh to each mesh of each piece kind in the block, and no
# MeshInstance3D for any of them (a wall tile or a roof tile each would be a draw of its own).
func test_a_blocks_pieces_are_a_few_multimeshes_and_not_a_mesh_each() -> void:
	var built := _build("block 0 0 10 5 3 frontage flat solid\nblock 12.5 0 22.5 5 3 frontage flat")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.map(func(m: Node) -> String: return m.name), ["Interior", "Interior"], "no mesh to a tile: one dark interior to a block")
	var multimeshes := root.find_children("*", "MultiMeshInstance3D", true, false)
	var instances := 0
	for mm: MultiMeshInstance3D in multimeshes:
		assert_true(mm is KitRun, "%s is a KitRun" % mm.name)
		instances += (mm as KitRun).places.size()
		assert_true(mm.is_in_group(&"kit_multimesh"), "%s is in the group kit_multimesh" % mm.name)
		assert_eq(mm.multimesh.instance_count, (mm as KitRun).places.size(), "%s draws its places" % mm.name)
	assert_true(instances >= 40, "the 40 pieces of two blocks are instances (%d in all)" % instances)
	assert_true(multimeshes.size() <= 2 * 14, "a few multimeshes: %d for 2 blocks of 5 kinds of wall and a roof" % multimeshes.size())
	assert_true(multimeshes.size() < instances / 2.0, "far fewer than the pieces")
	assert_eq(_placed(root).size(), 40, "every piece is still a placed piece")


func test_the_styles_choose_pieces_by_storey_and_tile_index() -> void:
	# frontage: a ground storey of door, shutters, window, shutters, wall, window; the upper of shutters, window, wall, window.
	var built := _build("block 0 0 15 5 2 frontage flat")
	var by_tile := {}
	for piece: Dictionary in _placed(built.root):
		if piece.piece == "roof-flat":
			continue
		var tile := floori(_box(piece).get_center().x / TILE)
		var storey := roundi(piece.xf.origin.y / TILE)
		by_tile[Vector2i(tile, storey)] = piece.piece
	var ground := ["wall-door", "wall-window-shutters", "wall-window-small", "wall-window-shutters", "wall", "wall-window-small"]
	var upper := ["wall-window-shutters", "wall-window-small", "wall", "wall-window-small"]
	for k in 6:
		assert_eq(by_tile.get(Vector2i(k, 0)), ground[k], "ground storey, tile %d" % k)
		assert_eq(by_tile.get(Vector2i(k, 1)), upper[k % 4], "upper storey, tile %d" % k)
	var wood := _build("block 0 0 12.5 5 2 tannery slope")
	var names := {}
	for piece: Dictionary in _placed(wood.root):
		names[piece.piece] = true
	for expected in ["wall-wood-door", "wall-wood", "wall-wood-window-small", "wall-wood-window-shutters", "roof"]:
		assert_true(names.has(expected), "a tannery has %s" % expected)
	var shed := _build("block 0 0 10 5 1 shed high")
	var plain := _build("block 0 0 5 5 1 plain flat")
	assert_true(_placed(shed.root, "wall-wood").size() == 2 and _placed(shed.root, "wall-wood-window-small").size() == 1 and _placed(shed.root, "wall-wood-door").size() == 1 \
			and _placed(shed.root, "roof-high").size() == 8, "a shed is wall-wood with a window and a door under roof-high")
	assert_eq(_placed(_build("block 0 0 15 5 3 frontage flat").root, "balcony-wall").size(), 0, "no style uses the balcony (its frame is a hole)")
	assert_true(_placed(plain.root, "wall").size() == 2 and _placed(plain.root, "roof-flat").size() == 4, "plain is wall under roof-flat")


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
	var drawn := root.find_children("*", "GeometryInstance3D", true, false)
	assert_true(drawn.size() > 0)
	for mesh: GeometryInstance3D in drawn:
		if mesh.name != &"Interior":   # the walls and the roof cast the block's shadow; the dark box behind them adds nothing to it
			assert_ne(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts shadows" % mesh.name)
	var visual := _build("block 0 0 10 5 3 frontage flat")
	var vroot := visual.root as Node
	assert_true(vroot.get_node_or_null("Backdrop") != null and vroot.get_node_or_null("Blocks") == null, "under Backdrop")
	assert_eq(vroot.find_children("*", "CollisionObject3D", true, false).size(), 0, "no collider")
	var meshes := vroot.find_children("*", "GeometryInstance3D", true, false)
	assert_true(meshes.size() > 0)
	for mesh: GeometryInstance3D in meshes:
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


# The height at which a ray straight down at (x, z) meets the meshes of a placed piece; -INF if it misses.
func _height_at(placed: Dictionary, x: float, z: float) -> float:
	var best := -INF
	for m: Dictionary in placed.meshes:
		var triangles: TriangleMesh = m.mesh.generate_triangle_mesh()
		var to_local: Transform3D = (m.xf as Transform3D).affine_inverse()
		var from := to_local * Vector3(x, 20.0, z)
		var direction := (to_local.basis * Vector3.DOWN).normalized()
		var hit := triangles.intersect_ray(from, direction)
		if not hit.is_empty():
			best = maxf(best, (m.xf * (hit.position as Vector3)).y)
	return best


func test_a_slope_roof_is_higher_at_its_north_edge() -> void:
	for roof in ["slope", "high"]:
		var built := _build("block 0 0 5 5 1 plain %s" % roof)
		assert_eq(built.problems, PackedStringArray())
		var tiles := _placed(built.root, "roof" if roof == "slope" else "roof-high")
		assert_eq(tiles.size(), 4, "%s: four tiles" % roof)
		for tile: Dictionary in tiles:
			var north := _height_at(tile, tile.xf.origin.x, tile.xf.origin.z - 0.5)
			var south := _height_at(tile, tile.xf.origin.x, tile.xf.origin.z + 0.5)
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


# A lantern is a solid slim post (a cylinder) with its lamp up the post; `ghost` leaves out the collider, `y=` stands it on a low wall.
func test_lantern_options_ghost_and_y() -> void:
	var solid := _build("lamps #ffb98a 6 0.5 3.45 world\nlantern 2 2")
	assert_eq(solid.problems, PackedStringArray())
	assert_eq(_bodies(solid.root).size(), 1, "a lantern is solid")
	assert_true((_bodies(solid.root)[0].get_child(0) as CollisionShape3D).shape is CylinderShape3D, "a slim round post")
	var ghost := _build("lamps #ffb98a 6 0.5 3.45 world\nlantern 2 2 ghost y=0.65")
	assert_eq(ghost.problems, PackedStringArray())
	assert_eq(_bodies(ghost.root).size(), 0, "a ghost lantern has no collider")
	var lamp := (ghost.root as Node).find_children("Lamp", "OmniLight3D", true, false)[0] as OmniLight3D
	assert_near(lamp.global_position.y, 0.65 + 3.45, 1e-6, "its lamp is up the post, which stands on the wall")
	for bad in ["lantern 2 2 ghost ghost", "lantern 2 2 y=high", "lantern 2 ghost"]:
		var built := _build("lamps #ffb98a 6 0.5 3.45 world\n" + bad)
		assert_eq(built.problems.size(), 1, "%s is one problem: %s" % [bad, built.problems])
		if built.problems.size() == 1:
			assert_true((built.problems[0] as String).begins_with("T.txt:2:"), "%s names its line" % bad)


# A guard is an unseen solid on `world` only: bodies bump into it, no foot stands on it, nothing of it is drawn.
func test_guard_is_an_unseen_wall() -> void:
	var built := _build("guard 0 0 10 0.4 2.5 name=Rail")
	assert_eq(built.problems, PackedStringArray())
	var body := (built.root as Node).get_node_or_null("Rail") as StaticBody3D
	assert_true(body != null, "named Rail")
	if body != null:
		assert_eq(body.collision_layer, Layers.WORLD, "on world only")
		assert_eq(body.find_children("*", "MeshInstance3D", true, false).size(), 0, "nothing of it is drawn")
		var shape := body.get_child(0) as CollisionShape3D
		assert_vec_near((shape.shape as BoxShape3D).size, Vector3(10, 2.5, 0.4), 1e-6, "10 x 2.5 x 0.4")
		assert_vec_near(shape.position, Vector3(5, 1.25, 0.2), 1e-6, "standing on the ground")
	for bad in ["guard 0 0 10 0.4", "guard 0 0 10 0.4 0", "guard 0 0 10 0.4 x", "guard 0 0 10 0.4 2 name=A extra"]:
		var wrong := _build(bad)
		assert_eq(wrong.problems.size(), 1, "%s is one problem: %s" % [bad, wrong.problems])
		if wrong.problems.size() == 1:
			assert_true((wrong.problems[0] as String).begins_with("T.txt:1:"), "%s names its line" % bad)


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


# Every piece the kit's list names loads with the world's toon material in place of the pack's own, so a piece added to the
# list without its import setting (the importer does not write it) is caught here.
func test_every_listed_kenney_piece_is_in_the_toon_material() -> void:
	var listed := 0
	for line in FileAccess.get_file_as_string("res://tools/assets/kenney_town_pieces.txt").split("\n"):
		var name := line.strip_edges()
		if name.is_empty() or name.begins_with("#"):
			continue
		listed += 1
		var scene := (load(KENNEY % name) as PackedScene).instantiate()
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		assert_true(meshes.size() > 0, "%s has a mesh" % name)
		for mesh: MeshInstance3D in meshes:
			for i in mesh.mesh.get_surface_count():
				# The fountain's water has a material of its own.
				var expected := _material("kenney_water") if name.begins_with("fountain-round") and mesh.get_active_material(i) == _material("kenney_water") else _material("kenney_town")
				assert_eq(mesh.get_active_material(i), expected, "%s surface %d" % [name, i])
		scene.free()
	assert_true(listed >= 42, "the list was read (%d pieces)" % listed)


# --- `kit` ---

# The material of every mesh of every kit piece under `root`, as resource paths.
func _kit_materials(root: Node) -> Dictionary:
	var found := {}
	for piece: Dictionary in _placed(root):
		for m: Dictionary in piece.meshes:
			found[(m.material as Material).resource_path] = true
	return found


func test_kit_bilibara_draws_every_piece_of_the_layout_in_its_colours() -> void:
	var layout := "ground 0 5 10 15 cobble\nblock 0 0 10 5 2 frontage slope solid\nedge wall 0 7.5 5 7.5 s solid\npiece banner-red 7 7\nlamps #ffb98a 6 0.5 3.45 world\nlantern 8 8\nkit bilibara\n"
	var built := _build(layout)
	assert_eq(built.problems, PackedStringArray())
	var materials := _kit_materials(built.root)
	assert_eq(materials.keys(), [MATERIALS % "kenney_town_bilibara"], "every piece in the one material: %s" % [materials.keys()])
	assert_true(_placed(built.root).size() > 10, "and there are pieces")
	# And so the saved scene draws them: a small scene, with the dresser in it, whose pieces take the material on entering
	# the tree.
	var packed := PackedScene.new()
	assert_eq(packed.pack(built.root as Node), OK)
	var again := track(packed.instantiate()) as Node
	assert_true(again.get_node_or_null("Kit") is KitDresser, "a KitDresser called Kit")
	assert_eq(_kit_materials(again).keys(), [MATERIALS % "kenney_town_bilibara"], "the saved scene draws its pieces in the same material")
	# Wherever the line stands.
	var first := _build("kit bilibara\npiece lantern 1 1\n")
	assert_eq(_kit_materials(first.root).keys(), [MATERIALS % "kenney_town_bilibara"])
	# Without the line, the kit's own.
	var plain := _build(layout.replace("kit bilibara\n", ""))
	assert_eq(_kit_materials(plain.root).keys(), [MATERIALS % "kenney_town"], "the kit's own material without the line")


func test_a_bad_or_second_kit_line_is_a_problem() -> void:
	var unknown := _build("\nkit castle")
	assert_eq(unknown.problems.size(), 1, "an unknown kit: %s" % [unknown.problems])
	assert_true((unknown.problems[0] as String).begins_with("T.txt:2:"), "names its line")
	var twice := _build("kit bilibara\n\nkit bilibara")
	assert_eq(twice.problems.size(), 1, "a second kit line: %s" % [twice.problems])
	assert_true((twice.problems[0] as String).begins_with("T.txt:3:"), "names its line")
	assert_eq(_build("kit").problems.size(), 1, "kit needs a name")


# --- the small things: one honest problem to a bad line ---

func test_a_word_that_is_not_a_colour_is_a_problem_and_builds_nothing() -> void:
	for line in ["fill -35 25 notacolour 1.3", "moon -35 25 notacolour 1.3", "sun -50 35 #zzz 1.0", "lamps notacolour 6 0.5 3.45", "lamps nope 6 0.5 3.45 world",
			"sky notacolour", "ambient notacolour 0.4"]:
		var built := _build("\n" + line)
		assert_eq(built.problems.size(), 1, "%s is one problem: %s" % [line, built.problems])
		if built.problems.size() == 1:
			assert_true((built.problems[0] as String).begins_with("T.txt:2:"), "%s names its line" % line)
		assert_eq((built.root as Node).find_children("*", "Light3D", true, false).size(), 0, "%s builds no light" % line)
		assert_eq((built.root as Node).find_children("*", "WorldEnvironment", true, false).size(), 0, "%s builds no environment" % line)


func test_a_short_line_is_one_problem_and_not_two() -> void:
	for line in ["ground 0 0 5 cobble", "ground 0 0 5", "water 0 0 5 5", "block 0 0 5 5", "vat 5", "lamps #ffb98a 6 0.5 world", "lamps #ffb98a 6 0.5",
			"block 0 0 5 5 1 plain", "fill -35 25 1.3", "kit bilibara extra", "ground 0 0 5 5 cobble visual extra", "water 0 0 5 5 0 liquor extra"]:
		var built := _build(line)
		assert_eq(built.problems.size(), 1, "%s is one problem: %s" % [line, built.problems])


func test_a_second_light_for_the_bodies_is_a_problem() -> void:
	for text in ["fill -35 25 #ffffff 1\nfill -30 20 #ffffff 1", "moon -35 25 #ffffff 1\nfill -30 20 #ffffff 1", "fill -35 25 #ffffff 1\nmoon -30 20 #ffffff 1"]:
		var built := _build(text)
		assert_eq(built.problems.size(), 1, "%s: %s" % [text.replace("\n", " / "), built.problems])
		if built.problems.size() == 1:
			assert_true((built.problems[0] as String).begins_with("T.txt:2:"), "the second names its line")
		assert_eq((built.root as Node).find_children("*", "DirectionalLight3D", true, false).size(), 1, "only the first is built")


func test_ground_or_water_laid_twice_over_the_same_place_is_a_problem() -> void:
	var twice := _build("ground 0 0 10 10 cobble\n# a comment\nground 5 5 15 15 snow visual")
	assert_eq(twice.problems.size(), 1, "overlapping ground: %s" % [twice.problems])
	if twice.problems.size() == 1:
		assert_true((twice.problems[0] as String).begins_with("T.txt:3:") and "line 1" in twice.problems[0], "naming both lines: %s" % twice.problems[0])
	assert_eq(_build("ground 0 0 10 10 cobble\nground 10 0 20 10 snow").problems, PackedStringArray(), "plates that touch are fine")
	var wet := _build("water 0 0 10 10 -0.9\nwater 5 5 15 15 -0.9")
	assert_eq(wet.problems.size(), 1, "overlapping water at one height: %s" % [wet.problems])
	assert_eq(_build("water 0 0 10 10 -0.9\nwater 5 5 15 15 0.05 liquor").problems, PackedStringArray(), "water at another height is fine")


func test_a_block_longer_than_60_m_is_a_problem() -> void:
	assert_eq(_build("block 0 0 60 5 1 plain flat").problems, PackedStringArray(), "60 m is fine")
	assert_eq(_build("block 0 0 62.5 5 1 plain flat").problems.size(), 1, "62.5 m is a problem")
	assert_eq(_build("block 0 0 5 62.5 1 plain flat").problems.size(), 1, "the other side too")


func test_a_tab_between_words_is_white_space() -> void:
	var built := _build("ground\t0 0\t10 10  cobble\t# a comment")
	assert_eq(built.problems, PackedStringArray())
	assert_true((built.root as Node).get_node_or_null("Walkable/Ground") != null, "built")


# --- four small things added for Task 2 of the stretch ---

# The dresser is a tool script, so the editor (where the owner opens these scenes) shows Bilibara's colours too; and a
# kit piece added to the region after it is ready is dressed as it comes in.
func test_the_kit_dresser_is_a_tool_and_dresses_what_is_added_later() -> void:
	assert_true((KitDresser as GDScript).is_tool(), "KitDresser is @tool")
	var built := _build("kit bilibara\npiece lantern 1 1\n")
	var root := built.root as Node3D
	var dresser := root.get_node("Kit") as KitDresser
	var bilibara := dresser.material
	assert_true(bilibara != null and bilibara != _material("kenney_town"), "the dresser holds Bilibara's material")
	# A piece (a scene instance) added later, under a group of its own.
	var late := (load(KENNEY % "wall") as PackedScene).instantiate() as Node3D
	root.add_child(late)
	for mesh: MeshInstance3D in late.find_children("*", "MeshInstance3D", true, false):
		assert_eq(mesh.material_override, bilibara, "a piece added after the scene was ready is dressed")
	# A run added later.
	var run := KitRun.new()
	run.piece = &"wall"
	var scene := (load(KENNEY % "wall") as PackedScene).instantiate() as Node3D
	run.part = (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	scene.free()
	run.places.append(Transform3D.IDENTITY)
	run.add_to_group(&"kit_multimesh", true)
	root.add_child(run)
	assert_eq(run.material_override, bilibara, "a run added later is dressed")
	# Something that is not the kit is left alone.
	var other := MeshInstance3D.new()
	other.mesh = BoxMesh.new()
	root.add_child(other)
	assert_eq(other.material_override, null, "and a mesh that is not a kit piece is not")
	# A node somewhere else in the tree is not the dresser's business.
	var elsewhere := (load(KENNEY % "wall") as PackedScene).instantiate() as Node3D
	track(elsewhere)
	for mesh: MeshInstance3D in elsewhere.find_children("*", "MeshInstance3D", true, false):
		assert_ne(mesh.material_override, bilibara, "a piece outside the region is not dressed")


# A run says how big it is from its places and its piece's own box, which is right headless, where the MultiMesh's own box is
# empty. (The render test, tests/render/test_kit_run_bounds.gd, holds it equal to the MultiMesh's own under a display.)
func test_a_run_says_how_big_it_is_even_headless() -> void:
	var built := _build("block 0 0 10 5 2 plain slope solid")
	var runs := (built.root as Node).find_children("*", "KitRun", true, false)
	assert_true(runs.size() >= 2, "a front and a roof (%d runs)" % runs.size())
	var all := AABB()
	var first := true
	for node in runs:
		var run := node as KitRun
		var box := run.bounds()
		assert_true(box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0, "%s has a size (%s)" % [run.name, box])
		for place in run.places:
			assert_true(box.grow(1e-4).encloses(place * run.local * run.part.get_aabb()), "%s holds every place" % run.name)
		all = box if first else all.merge(box)
		first = false
	# The block: two storeys of front on z = 5 and a roof over the footprint, so x 0..10, z 0..5, y 0 up to the roof's top.
	assert_near(all.position.x, 0.0, 1e-3, "from the west edge")
	assert_near(all.end.x, 10.0, 1e-3, "to the east edge")
	assert_true(all.position.y > -1e-3 and all.position.y < 1e-3, "from the ground (%s)" % all.position.y)
	assert_true(all.end.y > 5.0 and all.end.y < 7.0, "to a roof a little over 5 m (%s)" % all.end.y)
	var empty := KitRun.new()
	assert_eq(empty.bounds(), AABB(), "a run with no places has no size")
	empty.free()


# A run is lit evenly: this renderer lights a mesh as a whole with at most eight omni lights, so a long block beside a
# street's lanterns would be lit by a few lamps in one place and dark elsewhere. No run spans more than 12.5 m (five tiles).
func test_no_run_of_a_block_is_longer_than_five_tiles() -> void:
	var built := _build("block 0 0 60 7.5 3 frontage slope solid\nblock 0 20 60 60 2 tannery flat")
	assert_eq(built.problems, PackedStringArray())
	var runs := (built.root as Node).find_children("*", "KitRun", true, false)
	var most_x := 0.0
	var most_z := 0.0
	for node in runs:
		var run := node as KitRun
		var box := run.bounds()
		most_x = maxf(most_x, box.size.x)
		most_z = maxf(most_z, box.size.z)
		assert_true(box.size.x <= 12.5 + 1e-3, "%s is %.2f m along x" % [run.get_path(), box.size.x])
		assert_true(box.size.z <= 12.5 + 1e-3, "%s is %.2f m along z" % [run.get_path(), box.size.z])
	assert_true(most_x > 10.0, "and the runs are not needlessly small (%.2f m)" % most_x)
	# Every piece is still placed once: 24 tiles x 3 storeys of front, 24 x 3 of roof; 24 x 2 of front, 24 x 16 of roof.
	assert_eq(_placed(built.root).size(), 24 * 3 + 24 * 3 + 24 * 2 + 24 * 16, "the same pieces, split into runs")
	var spots := {}
	for piece: Dictionary in _placed(built.root):
		var key := "%s|%s" % [piece.piece, piece.xf.origin]
		assert_false(spots.has(key), "%s is not placed twice at one spot" % key)
		spots[key] = true


# Two masses in one place, or a solid mass over ground a body walks on, are mistakes in the layout: each is one problem that
# names both lines, whichever comes first.
func test_overlapping_blocks_or_a_solid_block_over_walkable_ground_are_problems() -> void:
	var twice := _build("block 0 0 10 5 3 plain flat solid\n# a comment\nblock 7.5 0 17.5 5 2 plain flat")
	assert_eq(twice.problems.size(), 1, "two blocks that overlap: %s" % [twice.problems])
	if twice.problems.size() == 1:
		assert_true((twice.problems[0] as String).begins_with("T.txt:3:") and "line 1" in twice.problems[0], "naming both lines: %s" % twice.problems[0])
	var behind := _build("block 0 0 10 5 3 plain flat\nblock 5 -5 15 2.5 1 plain flat")
	assert_eq(behind.problems.size(), 1, "two backdrop blocks too: %s" % [behind.problems])
	assert_eq(_build("block 0 0 10 5 3 plain flat solid\nblock 10 0 20 5 3 plain flat solid\nblock 0 5 20 10 1 plain flat").problems, PackedStringArray(), "blocks that touch are fine")
	for text in ["ground 0 0 10 10 cobble\nblock 5 5 15 15 3 plain flat solid", "block 5 5 15 15 3 plain flat solid\nground 0 0 10 10 cobble"]:
		var over := _build(text)
		assert_eq(over.problems.size(), 1, "a solid block over walkable ground (%s): %s" % [text.replace("\n", " / "), over.problems])
		if over.problems.size() == 1:
			assert_true("line 1" in over.problems[0] and (over.problems[0] as String).begins_with("T.txt:2:"), "the later line names the earlier: %s" % over.problems[0])
	assert_eq(_build("ground 0 0 10 10 cobble\nblock 10 0 20 10 3 plain flat solid").problems, PackedStringArray(), "a block beside the ground is fine")
	assert_eq(_build("ground 0 0 10 10 cobble visual\nblock 5 5 15 15 3 plain flat solid").problems, PackedStringArray(), "a block over seen-only ground is fine")
	assert_eq(_build("ground 0 0 10 10 cobble\nblock 5 5 15 15 3 plain flat").problems, PackedStringArray(), "and a backdrop block over walkable ground is a picture, not a mass")


# A curb can be named (so a test or a later layout finds the gate and the low walls by name) and raised off the ground (a rail
# across the top of two posts).
func test_a_curb_takes_a_name_and_a_raise() -> void:
	var built := _build("curb 0 0 5 1 0.6 slate name=Gate\ncurb 0 3 5 4 0.6 name=LowWall2 moonlit\ncurb 0 6 5 7 0.3 slate\ncurb 0 9 5 10 0.12 slate name=Rail y=2.4")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	var gate := root.get_node_or_null("Gate") as StaticBody3D
	assert_true(gate != null and root.get_node_or_null("LowWall2") is StaticBody3D and root.get_node_or_null("Curb") is StaticBody3D, "named, and unnamed as before: Gate, LowWall2, Curb")
	if gate != null:
		assert_vec_near((gate.get_node("Shape") as CollisionShape3D).global_position, Vector3(2.5, 0.3, 0.5), 1e-6, "the gate stands on the ground")
	var rail := root.get_node_or_null("Rail") as StaticBody3D
	assert_true(rail != null, "a Rail")
	if rail != null:
		var shape := rail.get_node("Shape") as CollisionShape3D
		assert_near(shape.global_position.y - (shape.shape as BoxShape3D).size.y / 2.0, 2.4, 1e-6, "its underside is at 2.4 m")
		assert_near((shape.shape as BoxShape3D).size.y, 0.12, 1e-6, "0.12 m thick")
	for bad in ["curb 0 0 5 1 0.6 name=", "curb 0 0 5 1 0.6 y=up", "curb 0 0 5 1 0.6 name=A name=B"]:
		assert_eq(_build(bad).problems.size(), 1, "%s is one problem" % bad)


# A region that leaves the tree and comes back still dresses the pieces added after it returns (the dresser listens from
# _enter_tree, which runs every time, and not from _ready, which runs once).
func test_the_kit_dresser_dresses_after_the_region_leaves_the_tree_and_returns() -> void:
	var built := _build("kit bilibara\npiece lantern 1 1\n")
	var root := built.root as Node3D
	var bilibara := (root.get_node("Kit") as KitDresser).material
	var parent := root.get_parent()
	parent.remove_child(root)
	parent.add_child(root)
	var late := (load(KENNEY % "wall") as PackedScene).instantiate() as Node3D
	root.add_child(late)
	for mesh: MeshInstance3D in late.find_children("*", "MeshInstance3D", true, false):
		assert_eq(mesh.material_override, bilibara, "a piece added after the region came back is dressed")


# `row PIECE X0 Z0 X1 Z1 YAW [y=Y]`: a piece every tile along a line, both ends included, drawn as a few runs (a rack of twelve
# poles is one draw, not twelve), under Props, with no collider.
func test_a_row_is_a_piece_every_tile_along_a_line_in_runs_with_no_collider() -> void:
	var built := _build("row poles 0 0 30 0 90\nrow planks 5 5 5 12.5 0 y=1")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	var poles := _placed(root, "poles")
	assert_eq(poles.size(), 13, "13 poles: 0 to 30 m every 2.5 m")
	var xs := poles.map(func(p: Dictionary) -> float: return snappedf(p.xf.origin.x, 0.001))
	xs.sort()
	assert_eq(xs[0], 0.0, "the first at the first point")
	assert_eq(xs[12], 30.0, "the last at the second")
	for piece: Dictionary in poles:
		assert_vec_near(piece.xf.basis.get_scale(), Vector3.ONE * 2.5, 1e-4, "at x2.5")
		assert_vec_near(piece.xf.basis.x.normalized(), Vector3(0, 0, -1), 1e-4, "turned 90 degrees about +Y")
		assert_true(root.get_node("Props").is_ancestor_of(root.find_children("*", "KitRun", true, false)[0]), "under Props")
	var planks := _placed(root, "planks")
	assert_eq(planks.size(), 4, "4 planks along z")
	for piece: Dictionary in planks:
		assert_near(piece.xf.origin.y, 1.0, 1e-6, "raised 1 m")
	var runs := root.find_children("*", "KitRun", true, false)
	for node in runs:
		assert_true((node as KitRun).bounds().size.x <= 12.5 + 1e-3 + 2.5, "%s is a short run" % node.name)
	assert_true(runs.size() <= 5, "a few runs and not one to a piece (%d)" % runs.size())
	assert_eq(root.find_children("*", "CollisionObject3D", true, false).size(), 0, "nothing to collide with")
	for bad in ["row poles 0 0 30 3 90", "row poles 0 0 31 0 90", "row nothing 0 0 5 0 0", "row poles 0 0 5 0", "row poles 0 0 5 0 up", "row poles 0 0 5 0 0 backdrop backdrop"]:
		assert_eq(_build(bad).problems.size(), 1, "%s is one problem" % bad)
	# `backdrop`: the same row under Backdrop, casting no shadow (a chimney of the ring).
	var far := _build("row chimney 0 0 5 0 0 y=7.5 backdrop")
	assert_eq(far.problems, PackedStringArray())
	var far_runs := (far.root as Node).get_node("Backdrop").find_children("*", "KitRun", true, false)
	assert_eq(far_runs.size(), 1, "one run under Backdrop")
	assert_eq(((far.root as Node).get_node_or_null("Props")), null, "and none under Props")
	for run: KitRun in far_runs:
		assert_eq(run.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "casting no shadow")
		assert_eq(run.places.size(), 3, "three chimneys")


# `piece ... ghost` is a piece with no collider (a decoration a body walks through); without it a piece collides as MODELS says.
# `ground ... name=NAME` names the plate (so that one place's floor can be told from the rest: the yard's centre).
func test_a_piece_can_be_a_ghost_and_a_ground_plate_can_be_named() -> void:
	var built := _build("piece pillar-stone 1 1\npiece pillar-stone 4 1 ghost\npiece stall-bench 7 1 90 ghost y=1\nground 0 5 10 10 slate name=YardCentre\nground 10 5 20 10 slate\nground 20 5 30 10 slate visual name=Apron")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	var pillars := root.get_node("Props").find_children("PillarStone*", "Node3D", false, false)
	assert_eq(pillars.size(), 2, "two pillars")
	assert_true(pillars[0].get_node_or_null("Body") is StaticBody3D, "the first collides")
	assert_true(pillars[1].get_node_or_null("Body") == null, "the ghost does not")
	assert_true(pillars[1].find_child("Model", false, false) != null, "but is seen")
	assert_true(root.get_node("Props").get_node("StallBench").get_node_or_null("Body") == null, "a ghost with a turn and a height is still a ghost")
	assert_true(root.get_node("Walkable/YardCentre") is StaticBody3D, "a named plate is a body of that name")
	assert_true(root.get_node("Walkable/Ground") is StaticBody3D, "and an unnamed one is Ground")
	assert_true(root.get_node("Backdrop/Apron") is MeshInstance3D, "a named visual plate too")
	for bad in ["piece pillar-stone 1 1 ghost ghost", "ground 0 0 5 5 slate name=", "ground 0 0 5 5 slate name=A name=B"]:
		assert_eq(_build(bad).problems.size(), 1, "%s is one problem" % bad)


# `sun ... ortho`: the sun's shadow is one orthogonal map and not four splits, which in this renderer draws every shadow-casting mesh once
# and not up to four times (the stretch's views are drawn in a third fewer calls); without it the sun is as before.
func test_a_sun_can_cast_one_orthogonal_shadow() -> void:
	var plain := _build("sun -60 30 #f4f7ff 0.25")
	var ortho := _build("sun -60 30 #f4f7ff 0.25 ortho")
	assert_eq(plain.problems, PackedStringArray())
	assert_eq(ortho.problems, PackedStringArray())
	assert_eq(((plain.root as Node).get_node("Sun") as DirectionalLight3D).directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "four splits as before")
	assert_eq(((ortho.root as Node).get_node("Sun") as DirectionalLight3D).directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL, "one orthogonal map")
	for bad in ["sun -60 30 #f4f7ff 0.25 round", "sun -60 30 #f4f7ff ortho"]:
		assert_eq(_build(bad).problems.size(), 1, "%s is one problem" % bad)


# A window in the kit's wall is a hole through it, and the builder's blocks have no inside: a ray through a window met nothing and
# showed the background. Each block holds one dark box behind its front (the slab's back to the block's north edge, up to the roof), which
# casts no shadow and is no collider, so that a window is dark glass.
func test_a_block_has_a_dark_interior_behind_its_windows() -> void:
	var built := _build("block 0 0 10 5 2 frontage flat solid\nblock 12.5 0 22.5 7.5 3 tannery slope")
	assert_eq(built.problems, PackedStringArray())
	var blocks := (built.root as Node).get_node("Blocks").get_children() + (built.root as Node).get_node("Backdrop").get_children()
	assert_eq(blocks.size(), 2, "two blocks")
	for block in blocks:
		var interior := block.get_node_or_null("Interior") as MeshInstance3D
		assert_true(interior != null, "%s has an Interior" % block.name)
		if interior == null:
			continue
		var size := (interior.mesh as BoxMesh).size
		var storeys := 2 if block.name == &"Block" else 3
		assert_true(block.name == &"Block" or block.name == &"Block2", "%s" % block.name)
		assert_near(size.y, storeys * TILE + 1.0, 1e-6, "%s: up to the roof and 1 m below the ground (%.2f)" % [block.name, size.y])
		assert_eq(interior.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: casting no shadow" % block.name)
		assert_eq(interior.material_override, load("res://world/materials/interior.tres"), "%s: in the interior's material" % block.name)
		var box := interior.global_transform * interior.get_aabb()
		var depth := 5.0 if storeys == 2 else 7.5
		assert_near(box.position.y, -1.0, 1e-6, "%s: from 1 m under the ground (a gap at the foot of a window piece shows it)" % block.name)
		assert_near(box.end.z, depth - 0.25, 1e-6, "%s: to the back of the front's slab" % block.name)
		assert_near(box.size.z, depth - 0.25, 1e-6, "%s: to the block's north edge" % block.name)
		assert_eq(block.find_children("*", "CollisionObject3D", true, false).size(), 1 if storeys == 2 else 0, "%s: no collider of its own" % block.name)


# `gable`: a roof of two planes meeting in a ridge along the middle of the block's longer side (the ridge runs along x when the block is
# wider than it is deep), the tiles of one half turned to slope the other way: from the camera the two planes are lit differently and
# the block reads as a roof and not a slab. The tile count across the ridge must be even (else the other way, else a problem).
func test_a_gable_roof_has_two_planes_and_a_ridge_along_the_longer_side() -> void:
	var wide := _build("block 0 0 10 5 2 plain gable")
	assert_eq(wide.problems, PackedStringArray())
	var tiles := _placed(wide.root, "roof")
	assert_eq(tiles.size(), 8, "four by two roof tiles")
	for tile: Dictionary in tiles:
		var z: float = tile.xf.origin.z
		var toward_ridge := 1.0 if z < 2.5 else -1.0   # the north row's ridge is on its south edge, the south row's on its north edge
		var at_ridge := _height_at(tile, tile.xf.origin.x, z + toward_ridge * 1.0)
		var at_eave := _height_at(tile, tile.xf.origin.x, z - toward_ridge * 1.0)
		assert_true(at_ridge >= at_eave + 0.3, "tile at z %.2f: higher toward the middle (%.2f against %.2f)" % [z, at_ridge, at_eave])
	var deep := _build("block 0 0 5 20 2 plain gable")
	assert_eq(deep.problems, PackedStringArray())
	for tile: Dictionary in _placed(deep.root, "roof"):
		var x: float = tile.xf.origin.x
		var toward := 1.0 if x < 2.5 else -1.0
		assert_true(_height_at(tile, x + toward * 1.0, tile.xf.origin.z) >= _height_at(tile, x - toward * 1.0, tile.xf.origin.z) + 0.3, "tile at x %.2f: higher toward the middle (ridge along z)" % x)
	var odd := _build("block 0 0 10 7.5 1 plain gable")   # 4 by 3 tiles: the long side is even, the ridge runs along z
	assert_eq(odd.problems, PackedStringArray())
	assert_eq(_build("block 0 0 7.5 7.5 1 plain gable").problems.size(), 1, "3 by 3 tiles has no middle: one problem")
	assert_eq(_build("block 0 0 2.5 5 1 plain gable").problems.size(), 0, "1 by 2: the rows split")


# `drift X Z W D [y=Y] [seed=N]`: a low mound of snow of three to five overlapping rounded lumps with an outline of the seed's own (no
# straight edge over a metre: a polygon of many short sides), highest near its middle and feathering to nothing at the rim, seen only
# (Backdrop, no collider, no shadow), on the ground or raised Y.
func test_a_drift_is_a_rounded_mound_that_feathers_to_nothing() -> void:
	var built := _build("drift 5 5 4 3 y=1 seed=3\ndrift 5 5 4 3 y=1 seed=4")
	assert_eq(built.problems, PackedStringArray())
	var root := built.root as Node
	var drifts := root.get_node("Backdrop").find_children("Drift*", "MeshInstance3D", false, false) as Array
	assert_eq(drifts.size(), 2, "two drifts")
	assert_eq(root.find_children("*", "CollisionObject3D", true, false).size(), 0, "no collider")
	var shapes := []
	for d: MeshInstance3D in drifts:
		assert_eq(d.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow")
		assert_eq(d.material_override, load("res://world/materials/snow.tres"), "in the snow's material")
		var arrays := d.mesh.surface_get_arrays(0)
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var peak := 0.0
		var peak_at := Vector3.ZERO
		var rim := 0.0
		for v in verts:
			if v.y > peak:
				peak = v.y
				peak_at = v
		for v in verts:
			if Vector2(v.x, v.z).length() > 1.2 and absf(v.y) < 1e-6:
				rim += 1
		var box := d.global_transform * d.get_aabb()
		assert_near(box.position.y, 1.0, 1e-3, "%s lies on y = 1" % d.name)
		assert_true(peak > 0.12 and peak < 0.4, "%s is %.2f m at the most" % [d.name, peak])
		assert_true(Vector2(peak_at.x, peak_at.z).length() < 1.4, "%s peaks near its middle (%s)" % [d.name, peak_at])
		assert_true(box.size.x < 5.2 and box.size.z < 4.0 and box.size.x > 1.5, "%s is about 4 x 3 m (%s)" % [d.name, box.size])
		assert_true(rim > 5, "%s ends at zero height (%d rim vertices)" % [d.name, rim])
		# Seen from above it is a front face: the normals of the lumps point up (a mound wound the wrong way is culled from above).
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var down := 0
		for i in verts.size():
			if verts[i].y > 0.05 and normals[i].y <= 0.0:
				down += 1
		assert_eq(down, 0, "%s: no normal on its back faces up" % d.name)
		# The rim is the vertices of height zero that touch a triangle with height: it is a ring of short sides.
		var tri_count := {}
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var edges := {}
		for i in range(0, indices.size(), 3):
			for k in 3:
				var a := indices[i + k]
				var b := indices[i + (k + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				edges[key] = edges.get(key, 0) + 1
		var longest := 0.0
		var count := 0
		for key: Vector2i in edges:
			if edges[key] == 1:
				count += 1
				longest = maxf(longest, (verts[key.x] - verts[key.y]).length())
		assert_true(count >= 24 and longest < 1.0, "%s: an outline of %d sides, the longest %.2f m" % [d.name, count, longest])
		shapes.append(verts)
	assert_ne(shapes[0], shapes[1], "another seed, another outline")
	var again := _build("drift 5 5 4 3 y=1 seed=3")
	var first := (again.root as Node).get_node("Backdrop").find_children("Drift*", "MeshInstance3D", false, false)[0] as MeshInstance3D
	assert_eq(first.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], shapes[0], "the same seed, the same drift")
	for bad in ["drift 5 5 4", "drift 5 5 0 3", "drift 5 5 4 3 seed=x", "drift 5 5 4 3 y=up", "drift 5 5 40 3"]:
		assert_eq(_build(bad).problems.size(), 1, "%s is one problem" % bad)
