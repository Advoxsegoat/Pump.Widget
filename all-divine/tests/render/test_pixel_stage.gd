extends TestCase
## The stage on a real display (xvfb, gl_compatibility). A checker ground and a box in World,
## 1920x1080: each internal pixel must be a clean 3x3 block, and the sub-pixel offset must move
## the picture the right way.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")

var stage: PixelStage
var rig: CameraRig
var target: Node3D


func before_each() -> void:
	var window := get_window()
	if window.size != Vector2i(1920, 1080):
		window.size = Vector2i(1920, 1080)
		await get_tree().process_frame
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	_fill_world(stage.world)
	target = Node3D.new()
	stage.world.add_child(target)
	rig = CameraRig.new()
	rig.target = target
	rig.stage = stage
	stage.world.add_child(rig)
	rig.snap_now()


# A ground with a fine checker (8 px cells) so that most 3x3 blocks sit on an edge, and a box.
func _fill_world(world: SubViewport) -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var odd := ((x / 8) + (y / 8)) % 2 == 1
			img.set_pixel(x, y, Color(0.85, 0.8, 0.2) if odd else Color(0.15, 0.2, 0.55))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_mat.albedo_texture = ImageTexture.create_from_image(img)
	ground_mat.uv1_scale = Vector3(40, 40, 1)
	ground_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground.material_override = ground_mat
	world.add_child(ground)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(1.5, 0.5, -1.0)
	var box_mat := StandardMaterial3D.new()
	box_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box_mat.albedo_color = Color(0.9, 0.3, 0.35)
	box.material_override = box_mat
	world.add_child(box)


func _capture() -> Image:
	await frames(5)
	return get_viewport().get_texture().get_image()


func test_upscale_is_crisp_three_by_three_blocks() -> void:
	var image: Image = await _capture()
	assert_eq(image.get_size(), Vector2i(1920, 1080), "the test needs a 1920x1080 window")
	var k := PixelStage.scale_for(image.get_size())
	var origin := PixelStage.layout(image.get_size()).position
	assert_eq(k, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var colours := {}
	var mixed := 0
	var on_an_edge := 0
	for i in 300:
		var x0 := origin.x + rng.randi_range(0, 638) * k
		var y0 := origin.y + rng.randi_range(0, 358) * k
		var first := image.get_pixel(x0, y0)
		colours[first.to_html()] = true
		# A block next to a different one is where a smoothing upscale would show.
		if image.get_pixel(x0 + k, y0) != first or image.get_pixel(x0, y0 + k) != first:
			on_an_edge += 1
		for dy in k:
			for dx in k:
				if image.get_pixel(x0 + dx, y0 + dy) != first:
					mixed += 1
	assert_eq(mixed, 0, "pixels that differ from their block's first pixel")
	assert_true(colours.size() >= 2, "both checker colours are in the picture (%d seen)" % colours.size())
	assert_true(on_an_edge >= 40, "enough sampled blocks sit on an edge for the check to mean something (%d)" % on_an_edge)


# A target a quarter texel to the right (and, separately, up the screen) must show up as a whole-pixel
# shift of the picture: content moves left when the camera is further right, down when it is further up.
func test_subpixel_offset_moves_the_picture_the_right_way() -> void:
	var base: Image = await _capture()
	assert_eq(base.get_size(), Vector2i(1920, 1080), "the test needs a 1920x1080 window")
	assert_vec_near(Vector3(stage.subpixel.x, stage.subpixel.y, 0), Vector3.ZERO, 1e-4)

	target.position = Vector3(0.25 * PixelSnap.TEXEL, 0, 0)
	target.reset_physics_interpolation()
	rig.snap_now()
	assert_near(stage.subpixel.x, 0.25, 1e-3)
	var right: Image = await _capture()
	assert_eq(_shifted_mismatches(base, right, Vector2i(1, 0)), 0, "x: right(x) == base(x + 1)")

	var up := rig.camera.global_basis.y
	# Moving away from the camera along world -Z lifts the point up the screen by |up.z| per metre.
	target.position = Vector3(0, 0, -(0.25 * PixelSnap.TEXEL) / absf(up.z))
	target.reset_physics_interpolation()
	rig.snap_now()
	assert_near(stage.subpixel.y, 0.25, 1e-3)
	assert_near(stage.subpixel.x, 0.0, 1e-3)
	var raised: Image = await _capture()
	assert_eq(_shifted_mismatches(base, raised, Vector2i(0, -1)), 0, "y: raised(y) == base(y - 1)")


# A window that does not divide evenly: the picture sits centred at a whole-number scale, the rest is
# black, and the shifted World texture (which overhangs the picture) never shows in the bars.
func test_letterbox_is_black_and_the_picture_stops_at_its_rect() -> void:
	stage.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	stage.size = Vector2(1366, 768)
	target.position = Vector3(0.5 * PixelSnap.TEXEL, 0, 0)  # a shift is active, so the texture overhangs
	target.reset_physics_interpolation()
	rig.snap_now()
	var image: Image = await _capture()
	var window := Vector2i(1366, 768)
	var rect := PixelStage.layout(window)
	assert_eq(rect, Rect2i(43, 24, 1280, 720))
	var lit_outside := 0
	var dark_inside := 0
	for y in range(0, window.y, 3):
		for x in range(0, window.x, 3):
			var inside := rect.has_point(Vector2i(x, y))
			var black := image.get_pixel(x, y) == Color.BLACK
			if not inside and not black:
				lit_outside += 1
			if inside and black:
				dark_inside += 1
	assert_eq(lit_outside, 0, "non-black pixels in the bars")
	assert_eq(dark_inside, 0, "black pixels inside the picture")
	# The rect's own edge rows and columns: the picture to the last pixel, black right outside.
	for y in range(rect.position.y, rect.end.y, 5):
		assert_ne(image.get_pixel(rect.position.x, y), Color.BLACK, "first picture column at y=%d" % y)
		assert_ne(image.get_pixel(rect.end.x - 1, y), Color.BLACK, "last picture column at y=%d" % y)
		assert_eq(image.get_pixel(rect.position.x - 1, y), Color.BLACK, "bar column left of the picture")
		assert_eq(image.get_pixel(rect.end.x, y), Color.BLACK, "bar column right of the picture")
	for x in range(rect.position.x, rect.end.x, 5):
		assert_ne(image.get_pixel(x, rect.position.y), Color.BLACK, "first picture row at x=%d" % x)
		assert_ne(image.get_pixel(x, rect.end.y - 1), Color.BLACK, "last picture row at x=%d" % x)
		assert_eq(image.get_pixel(x, rect.position.y - 1), Color.BLACK, "bar row above the picture")
		assert_eq(image.get_pixel(x, rect.end.y), Color.BLACK, "bar row below the picture")


# Counts pixels where `shifted(p) != base(p + d)`, away from the borders.
func _shifted_mismatches(base: Image, shifted: Image, d: Vector2i) -> int:
	var bad := 0
	for y in range(8, base.get_height() - 8):
		for x in range(8, base.get_width() - 8):
			if shifted.get_pixel(x, y) != base.get_pixel(x + d.x, y + d.y):
				bad += 1
	return bad
