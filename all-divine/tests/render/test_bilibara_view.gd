extends TestCase
## The Bilibara stretch as the camera sees it (xvfb, gl_compatibility). Two things. The picture never shows the void: from about 120
## viewpoints along the edge of the walkable ground (every 5 m or so), with the camera where the game's would be 3.8 m out from the
## edge (the lock's lean and the look-ahead at their most), a 642 x 362 picture over a magenta background has no pixel of it: a
## wall top, a gap in the ring and the end of the water all show as magenta. And nine views are saved for a person to look at, each
## with Abarax and a tier I Knuckle in it as the game draws them (out/shots/bilibara/<name>.png at 640 x 360, and <name>_x3.png at
## 1920 x 1080: the way a 1080p screen shows it), none over the plan's draw-call limit.

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const MAIN := "res://main/main.tscn"
const FOE := "res://data/actors/knuckle_1.tres"
const SHOTS := "out/shots/bilibara/"
const SIZE := Vector2i(1920, 1080)
## Where the camera looks: this far outside the edge of the ground, along its normal.
const OUT := 3.8
## The cells of the ground scan (as test_bilibara's flood fill) and how far apart the viewpoints are along the edge.
const CELL := 0.5
const GRID_X := Vector2i(-90, 90)
const GRID_Z := Vector2i(-165, 25)
const SPACING := 5.0
## The picture is 640 x 360 plus a pixel's margin all round, as the game's world image is.
const PICTURE := Vector2i(642, 362)
## Most draw calls in a view: the first review's limit for the stretch.
const MOST_DRAWS := 220
const LEAST_COLOURS := 40
const VIEWS: Array[String] = ["Spawn", "StreetEast", "LaneMid", "ShrineSite_B", "RackWest", "GateFar", "GateNear", "YardEntry", "YardCentre"]


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func _is_void(c: Color) -> bool:
	return c.r > 0.95 and c.b > 0.95 and c.g < 0.05


func test_the_picture_never_shows_the_void_from_any_walkable_point() -> void:   # Review Focus 2
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	await frames(2)
	var space := region.get_world_3d().direct_space_state
	var ground := {}
	for cx in range(GRID_X.x, GRID_X.y):
		for cz in range(GRID_Z.x, GRID_Z.y):
			var at := (Vector2(cx, cz) + Vector2(0.5, 0.5)) * CELL + Vector2(0.013, 0.007)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 0.05, at.y), Vector3(at.x, -0.5, at.y), Layers.IK_SURFACE))
			if not hit.is_empty() and absf((hit["position"] as Vector3).y) < 1e-3:
				ground[Vector2i(cx, cz)] = true
	assert_true(ground.size() > 7000, "the ground is found (%d cells)" % ground.size())
	# The edge: ground cells with a cell of no ground beside them, every SPACING metres along it (a cell in every SPACING / CELL on a
	# diagonal sum of its indices, which picks about one cell in ten along a straight edge); each with the way out.
	var views: Array[Dictionary] = []
	var step := roundi(SPACING / CELL)
	for cell: Vector2i in ground.keys():
		var way := Vector2.ZERO
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not ground.has(cell + d):
				way += Vector2(d)
		if way != Vector2.ZERO and posmod(cell.x + cell.y, step) == 0:
			views.append({at = (Vector2(cell) + Vector2(0.5, 0.5)) * CELL, way = way.normalized()})
	assert_true(views.size() >= 90 and views.size() <= 200, "about 120 viewpoints (%d)" % views.size())
	var viewport := SubViewport.new()
	viewport.size = PICTURE
	viewport.world_3d = region.get_world_3d()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("ff00ff")
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CameraRig.ORTHO_SIZE
	camera.near = 0.1
	camera.far = 100.0
	camera.environment = env
	camera.rotation = Vector3(deg_to_rad(CameraRig.PITCH_DEG), 0.0, 0.0)
	viewport.add_child(camera)
	camera.make_current()
	var worst: Array[Dictionary] = []
	var bad := 0
	for view in views:
		var target := Vector3(view.at.x + view.way.x * OUT, 0.0, view.at.y + view.way.y * OUT)
		camera.position = target + camera.basis.z * CameraRig.DISTANCE
		for i in 2:
			await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var count := 0
		for y in PICTURE.y:
			for x in PICTURE.x:
				if _is_void(picture.get_pixel(x, y)):
					count += 1
		if count > 0:
			bad += 1
			worst.append({count = count, at = view.at, picture = picture})
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count)
	var names := PackedStringArray()
	for i in mini(3, worst.size()):
		var path := ProjectSettings.globalize_path("res://").path_join(SHOTS + "void_worst_%d.png" % (i + 1))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		(worst[i].picture as Image).save_png(path)
	for i in mini(10, worst.size()):
		names.append("%s: %d px" % [worst[i].at, worst[i].count])
	print("void: %d of %d viewpoints show background; worst: %s" % [bad, views.size(), names])
	assert_eq(names, PackedStringArray(), "no viewpoint shows the void (%d of %d do; the worst three are saved as void_worst_N.png)" % [bad, views.size()])


func test_nine_views_are_saved_for_a_person_to_look_at() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	var region := main.region
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.def = load(FOE) as ActorDef
	foe.set_brain(Brain.new())
	region.add_child(foe)
	main.player.set_brain(Brain.new())
	var worst := 0
	for marker_name in VIEWS:
		var at := (region.find_child(marker_name, true, false) as Marker3D).global_transform
		main.player.place(at)
		foe.place(Transform3D(Basis(Vector3.UP, -PI / 2), at.origin + Vector3(2.0, 0.0, 0.0)))
		main.camera_rig.snap_now()
		await frames(12)
		for i in 4:
			await RenderingServer.frame_post_draw
		var full := main.stage.world.get_texture().get_image()
		var picture := full.get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
		var file := marker_name.to_snake_case()
		var base := ProjectSettings.globalize_path("res://").path_join(SHOTS + file)
		DirAccess.make_dir_recursive_absolute(base.get_base_dir())
		assert_eq(picture.save_png(base + ".png"), OK, "saved %s.png" % base)
		var big := picture.duplicate() as Image
		big.resize(1920, 1080, Image.INTERPOLATE_NEAREST)
		assert_eq(big.save_png(base + "_x3.png"), OK, "saved %s_x3.png" % base)
		assert_eq(picture.get_size(), Vector2i(640, 360), "%s is 640 x 360" % marker_name)
		var colours := {}
		for y in range(0, 360, 3):
			for x in range(0, 640, 3):
				colours[picture.get_pixel(x, y).to_rgba32()] = true
		assert_true(colours.size() > LEAST_COLOURS, "%s: a real picture (%d colours in a 3 px sample)" % [marker_name, colours.size()])
		var draws := RenderingServer.viewport_get_render_info(main.stage.world.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		worst = maxi(worst, draws)
		print("bilibara view %s: %d draw calls" % [marker_name, draws])
		assert_true(draws > 0 and draws <= MOST_DRAWS, "%s: %d draw calls (at most %d)" % [marker_name, draws, MOST_DRAWS])


## Where the tone test looks besides the nine views: the loop lane (a roof fills its left third), and the lane's north end.
const EXTRA_VIEWS := {"LoopLane": Vector3(-32.5, 0.0, -12.5), "LaneNorth": Vector3(27.5, 0.0, -48.0), "StreetMid": Vector3(0.0, 0.0, 0.0)}
## The most of the frame one flat tone of a roof may fill (the 4/255 a channel the tone may vary by, and the share).
const FLAT_TOLERANCE := 4.0 / 255.0
const MOST_FLAT := 0.06


func _green() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.0, 1.0, 0.0)
	return material


# The largest connected region (4-neighbours) of one flat tone (within FLAT_TOLERANCE a channel of its first pixel) among the pixels `mask`
# marks, as a count.
func _largest_flat(picture: Image, mask: PackedByteArray) -> int:
	var w := picture.get_width()
	var h := picture.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var largest := 0
	for start in w * h:
		if mask[start] == 0 or seen[start] == 1:
			continue
		var seed_colour := picture.get_pixel(start % w, start / w)
		var stack := PackedInt32Array([start])
		seen[start] = 1
		var size := 0
		while not stack.is_empty():
			var at := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			size += 1
			var x := at % w
			var y := at / w
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var next := ny * w + nx
				if mask[next] == 0 or seen[next] == 1:
					continue
				var c := picture.get_pixel(nx, ny)
				if absf(c.r - seed_colour.r) <= FLAT_TOLERANCE and absf(c.g - seed_colour.g) <= FLAT_TOLERANCE and absf(c.b - seed_colour.b) <= FLAT_TOLERANCE:
					seen[next] = 1
					stack.append(next)
		largest = maxi(largest, size)
	return largest


func test_no_flat_tone_on_a_roof_fills_more_than_six_percent_of_the_frame() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	var region := main.region
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.def = load(FOE) as ActorDef
	foe.set_brain(Brain.new())
	region.add_child(foe)
	main.player.set_brain(Brain.new())
	var env := (region.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := env.background_color
	var spots := {}
	for marker_name in VIEWS:
		spots[marker_name] = (region.find_child(marker_name, true, false) as Marker3D).global_transform
	for view_name: String in EXTRA_VIEWS:
		spots[view_name] = Transform3D(Basis(), EXTRA_VIEWS[view_name])
	var report := PackedStringArray()
	var failed := PackedStringArray()
	for view_name: String in spots:
		var at: Transform3D = spots[view_name]
		main.player.place(at)
		foe.place(Transform3D(Basis(Vector3.UP, -PI / 2), at.origin + Vector3(2.0, 0.0, 0.0)))
		main.camera_rig.snap_now()
		await frames(12)
		for i in 4:
			await RenderingServer.frame_post_draw
		var real := main.stage.world.get_texture().get_image().get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
		# The roofs among everything: every other thing in the region drawn in a flat unlit green (so that it hides what is behind it as it does
		# in the picture), the fighters hidden, the sky magenta; a roof pixel is one that is neither green nor sky.
		var greened: Array[Dictionary] = []
		for mesh: GeometryInstance3D in region.find_children("*", "GeometryInstance3D", true, false):
			var parent_name := String(mesh.get_parent().name)
			var is_roof := parent_name == "Roof" or String(mesh.name).begins_with("Drift") or (mesh.get_parent().get_parent() != null and mesh.get_parent().get_parent().name == &"Backdrop" and parent_name.begins_with("Row"))
			if not is_roof:
				greened.append({mesh = mesh, was = mesh.material_override})
				mesh.material_override = _green()
		main.player.visible = false
		foe.visible = false
		env.background_color = Color("ff00ff")
		for i in 4:
			await RenderingServer.frame_post_draw
		var roofs := main.stage.world.get_texture().get_image().get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
		env.background_color = sky
		main.player.visible = true
		foe.visible = true
		for entry in greened:
			(entry.mesh as GeometryInstance3D).material_override = entry.was
		var mask := PackedByteArray()
		mask.resize(640 * 360)
		var roof_pixels := 0
		for y in 360:
			for x in 640:
				var r := roofs.get_pixel(x, y)
				var green: bool = r.g > r.r + 0.25 and r.g > r.b + 0.25
				var sky_pixel: bool = r.r > 0.7 and r.b > 0.7 and r.g < 0.5
				if not green and not sky_pixel:
					mask[y * 640 + x] = 1
					roof_pixels += 1
		var largest := _largest_flat(roofs, mask)
		var share := float(largest) / (640.0 * 360.0)
		report.append("%s %.1f%% (roof pixels %.0f%%)" % [view_name, share * 100.0, 100.0 * roof_pixels / (640.0 * 360.0)])
		if share > MOST_FLAT:
			failed.append("%s: %.1f%% of the frame in one flat tone of a roof" % [view_name, share * 100.0])
		roofs.save_png(ProjectSettings.globalize_path("res://").path_join(SHOTS + "roofs_" + view_name.to_snake_case() + ".png"))
	print("flat roof tones, the largest region of one tone as a share of the frame: %s" % [report])
	assert_eq(failed, PackedStringArray(), "no roof shows more than %d%% of the frame in one flat tone" % [MOST_FLAT * 100])
