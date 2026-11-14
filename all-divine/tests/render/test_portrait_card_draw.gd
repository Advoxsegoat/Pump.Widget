extends TestCase
## The portrait card as the window shows it (xvfb, gl_compatibility): the one thing in the game that is not on the 640x360
## grid. A stage with a checker ground and the overlay (bars in, a line up) is drawn twice from the same frozen frame, once with
## the card and once with it hidden, so that the two windows differ by the card and nothing else:
##   - at x3 the card's picture is drawn at the window's resolution (not as 3x3 blocks), and everywhere outside its rectangle the
##     window is exactly what it was without it (the exact upscale of the picture)
##   - at x1, x2 and a window that does not divide evenly the card's rectangle is whole picture pixels (116x160 of them, at
##     the box's left, rising above it)
## The pictures a person looks at are saved to out/story/: card_abarax_640.png (a 640x360 window, one picture pixel to a pixel)
## and card_abarax_1080.png (1920x1080, three to one), the close shot and the over-the-shoulder shot of the fixture's framing.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const OUT := "out/story"
const ABARAX_AT := Vector3(0.0, 0.0, 5.0)

var stage: PixelStage
var overlay: CineOverlay
var rig: CameraRig
var target: Node3D


func after_each() -> void:
	get_tree().paused = false
	get_window().size = Vector2i(1920, 1080)


# A ground with a fine checker (8 px cells), so that the picture has detail everywhere, and the overlay with a line up.
func _scene(window: Vector2i, line := "Fixture line two.") -> void:
	get_window().size = window
	await get_tree().process_frame
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			image.set_pixel(x, y, Color(0.85, 0.8, 0.2) if ((x / 8) + (y / 8)) % 2 == 1 else Color(0.15, 0.2, 0.55))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.uv1_scale = Vector3(40, 40, 1)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground.material_override = material
	stage.world.add_child(ground)
	target = Node3D.new()
	stage.world.add_child(target)
	target.position = ABARAX_AT
	rig = CameraRig.new()
	rig.target = target
	rig.stage = stage
	stage.world.add_child(rig)
	rig.snap_now()
	overlay = CineOverlay.new()
	overlay.auto = false
	stage.hud.add_child(overlay)
	overlay.letterbox = 1.0
	overlay.show_line(Registry.fetch(&"speakers", &"abarax") as Speaker, line, &"neutral", 600)
	overlay.advance(line.length() * 2 + 4)
	await frames(6)


func _card() -> PortraitCard:
	var found := stage.find_children("*", "PortraitCard", true, false)
	assert_eq(found.size(), 1, "one card in the stage")
	return found[0] as PortraitCard if not found.is_empty() else null


func _window() -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# The window as it is, and without the card, from the same frozen frame.
func _pair() -> Array[Image]:
	get_tree().paused = true
	var with_card := await _window()
	var card := _card()
	card.visible = false
	var without := await _window()
	card.visible = true
	get_tree().paused = false
	return [with_card, without]


func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) > 0.004 or absf(a.g - b.g) > 0.004 or absf(a.b - b.b) > 0.004


# Where the two windows differ: the bounding box of it, and how many pixels.
func _difference(a: Image, b: Image) -> Dictionary:
	var low := Vector2i(a.get_width(), a.get_height())
	var high := Vector2i(-1, -1)
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if _differs(a.get_pixel(x, y), b.get_pixel(x, y)):
				count += 1
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	return {box = Rect2i(low, high - low + Vector2i.ONE) if count > 0 else Rect2i(), count = count}


# Where the card's rectangle is in a window of this size: the picture's place and scale, the card's rectangle in picture pixels.
func _expected(window: Vector2i) -> Rect2i:
	var layout := PixelStage.layout(window)
	var k := PixelStage.scale_for(window)
	var at := overlay.portrait_rect()
	return Rect2i(layout.position + at.position * k, at.size * k)


func test_the_card_is_drawn_at_the_windows_resolution() -> void:
	await _scene(Vector2i(1920, 1080))
	var shown := await _pair()
	assert_eq(shown[0].get_size(), Vector2i(1920, 1080), "the test needs a 1920x1080 window")
	var rect := _expected(Vector2i(1920, 1080))
	assert_eq(rect.size, Vector2i(348, 480), "the card is 116x160 picture pixels at x3")
	var changed := _difference(shown[0], shown[1])
	assert_eq(changed.box, rect, "the two windows differ in the card's rectangle and nowhere else: exactly the upscale outside it")
	# Inside the rectangle: the picture is not on the grid. A pixel that differs from its left neighbour where no 3x3 block
	# begins is detail finer than the picture's pixels (on the grid there is none), and there is a great deal of it.
	var card_image := shown[0].get_region(rect)
	var off_grid := 0
	var on_grid := 0
	for y in card_image.get_height():
		for x in range(1, card_image.get_width()):
			if _differs(card_image.get_pixel(x, y), card_image.get_pixel(x - 1, y)):
				if x % 3 == 0:
					on_grid += 1
				else:
					off_grid += 1
	assert_true(off_grid > 4000, "the card has detail finer than the picture's pixels: %d changes inside a block (%d at block edges)" % [off_grid, on_grid])
	assert_true(off_grid > on_grid, "most of its detail is inside the 3x3 blocks, not at their edges")
	# Without the card, the same rectangle is the picture's: blocks of 3x3 (the box's ink, the bars, the world).
	var plain := shown[1].get_region(rect)
	var broken := 0
	for y in range(0, plain.get_height() - 3, 3):
		for x in range(0, plain.get_width() - 3, 3):
			var first := plain.get_pixel(x, y)
			if _differs(plain.get_pixel(x + 1, y + 1), first) or _differs(plain.get_pixel(x + 2, y), first):
				broken += 1
	assert_true(broken < 40, "under the card the picture is 3x3 blocks (%d blocks broken)" % broken)


func test_the_card_at_x1_x2_and_an_uneven_window() -> void:
	for window in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1366, 768)]:
		await _scene(window)
		var shown := await _pair()
		assert_eq(shown[0].get_size(), window, "the window is %s" % window)
		var k := PixelStage.scale_for(window)
		var layout := PixelStage.layout(window)
		var changed := _difference(shown[0], shown[1])
		var box: Rect2i = changed.box
		assert_eq(box, _expected(window), "the card fills its rectangle at x%d in a %s window" % [k, window])
		assert_eq((box.position.x - layout.position.x) % k, 0, "it begins on a picture pixel's column")
		assert_eq((box.position.y - layout.position.y) % k, 0, "and row")
		assert_eq(box.size, PortraitCard.CARD * k, "and is 116x160 picture pixels")
		var in_picture := Rect2i((box.position - layout.position) / k, box.size / k)
		assert_eq(in_picture, Rect2i(16, 194, 116, 160), "at the box's left, rising above it, in picture pixels")
		assert_true(layout.encloses(box), "inside the picture")
		stage.queue_free()
		await frames(2)


# One of the fixture's two lines framed as the game frames it, in a window of this size.
func _shot_for_a_person(size: Vector2i, framing: Shot.Framing, line: String, file: String) -> void:
	await _scene(size, line)
	var shot := Shot.new()
	shot.framing = framing
	shot.aim = &"abarax"
	shot.aim_height = 1.5
	shot.over_shoulder = &"knuckle"
	shot.length = 60
	shot.lines.append(DialogueLine.new())
	var world := func(name: StringName) -> Variant:
		return ABARAX_AT if name == &"abarax" else (Vector3(-1.2, 0, 2.4) if name == &"knuckle" else null)
	rig.cine = CinePose.solve(shot, 0.0, world, null, true)
	rig.cine_weight = 1.0
	await frames(Rig.WARM_FRAMES + 3)
	var image := await _window()
	var path := ProjectSettings.globalize_path("res://").path_join(OUT).path_join(file)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(image.save_png(path), OK, "saved %s" % path)
	stage.queue_free()
	await frames(2)


func test_shots_for_a_person() -> void:
	for size in [Vector2i(640, 360), Vector2i(1920, 1080)]:
		var name := "card_abarax_%d.png" % (640 if size.x == 640 else 1080)
		await _shot_for_a_person(size, Shot.Framing.CLOSE, "Fixture line two.", name)
		var again := name.replace("card_abarax", "card_abarax_ots")
		await _shot_for_a_person(size, Shot.Framing.OVER_SHOULDER, "A longer line, to see two rows of text at this size: the fixture's lines are short.", again)
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join(OUT).path_join("card_abarax_640.png")), "the 640 picture is saved")
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join(OUT).path_join("card_abarax_1080.png")), "the 1080 picture is saved")
