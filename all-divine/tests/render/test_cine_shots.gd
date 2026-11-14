extends TestCase
## The cine layer as the game draws it (xvfb, gl_compatibility): the yard with Abarax and a Knuckle at the fixture scene's
## marks, framed at each of the four whole-number zooms (and over the shoulder) by the game's own camera, with the bars all the
## way in and a line and its portrait showing. Two things are checked from the HUD viewport's own picture (640x360, what the
## overlay's queries say is what is drawn): the bars are exactly 44 rows of solid ink at the top and the bottom and nothing
## else covers a row, the box sits where box_rect says with its white border, the portrait card is not in that picture (it is
## drawn in the window, above it: tests/render/test_portrait_card_draw.gd) but is in the window's, and the text is drawn. The pictures a person looks at are saved to out/story/: cine_<shot>_640.png (the
## window at 640x360, one picture pixel to a pixel) and cine_<shot>_1920.png (the window at 1920x1080, three to one).

const MAIN := "res://main/main.tscn"
const KNUCKLE := "res://data/actors/knuckle_1.tres"
const ABARAX_AT := Vector3(0.0, 0.0, 5.0)
const KNUCKLE_AT := Vector3(-1.2, 0.0, 2.4)
const OUT := "out/story"
const TOLERANCE := 0.03
const SIZES := [Vector2i(640, 360), Vector2i(1920, 1080)]

var main: Main
var foe: Actor
var overlay: CineOverlay


func after_each() -> void:
	Game.reset()
	var window := get_window()
	window.size = Vector2i(1920, 1080)


func _shot(framing: Shot.Framing, aim: StringName, height: float, zoom := 0) -> Shot:
	var shot := Shot.new()
	shot.framing = framing
	shot.aim = aim
	shot.aim_height = height
	shot.zoom = zoom
	shot.length = 60
	shot.lines.append(DialogueLine.new())  # a shot that holds a line is framed in the free band
	return shot


func _scene() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	main = track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	for old in main.arena().enemies():
		old.queue_free()
	await frames(2)
	foe = (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.name = "Foe"
	foe.def = load(KNUCKLE) as ActorDef
	main.arena().add_child(foe)
	foe.set_brain(Brain.new())
	foe.place(Transform3D(Basis(Vector3.UP, atan2(1.2, 2.6)), KNUCKLE_AT))
	main.player.set_brain(Brain.new())
	main.player.place(Transform3D(Basis(Vector3.UP, PI), ABARAX_AT))
	main.camera_rig.snap_now()
	await frames(Rig.WARM_FRAMES + 3)
	main.hud.suppressed = true
	overlay = CineOverlay.new()
	main.stage.hud.add_child(overlay)


func _world() -> Callable:
	return func(name: StringName) -> Variant:
		match name:
			&"abarax":
				return main.player.global_position
			&"knuckle":
				return foe.global_position
		return null


func _frame_with(shot: Shot, speaker_id: StringName, text: String, expr: StringName) -> void:
	main.camera_rig.cine = CinePose.solve(shot, 0.0, _world(), null, true)
	main.camera_rig.cine_weight = 1.0
	overlay.letterbox = 1.0
	overlay.show_line(Registry.fetch(&"speakers", speaker_id) as Speaker, text, expr, 600)
	await frames(text.length() * 2 + 6)
	for i in 3:
		await RenderingServer.frame_post_draw


func _save(name: String, size: Vector2i) -> Image:
	get_window().size = size
	await get_tree().process_frame
	for i in 3:
		await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join(OUT).path_join(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	assert_eq(image.save_png(path), OK, "saved %s" % path)
	return image


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < TOLERANCE and absf(a.g - b.g) < TOLERANCE and absf(a.b - b.b) < TOLERANCE


func test_each_framing_is_drawn_with_the_bars_the_box_the_portrait_and_the_text() -> void:
	await _scene()
	var shots := {
		"wide": [_shot(Shot.Framing.WIDE, &"abarax", 1.0), &"abarax", "Fixture line two.", &"serious"],
		"medium": [_shot(Shot.Framing.MEDIUM, &"knuckle", 1.0), &"fixture_knuckle", "Fixture line one.", &"neutral"],
		"close": [_shot(Shot.Framing.CLOSE, &"abarax", 1.5), &"abarax", "Fixture line two.", &"smile"],
		"insert": [_shot(Shot.Framing.INSERT, &"abarax", 1.0), &"fixture_knuckle", "Fixture line one.", &"angry"],
	}
	var ots := _shot(Shot.Framing.OVER_SHOULDER, &"abarax", 1.5)
	ots.over_shoulder = &"knuckle"
	shots["over_the_shoulder"] = [ots, &"abarax", "A longer line, to see two rows of text at this size: the fixture's lines are short.", &"surprise"]
	# The close shot from four sides (the storyboard's yaw): for a person facing north, 180 shows his face.
	for yaw in [0, 45, 90, 180]:
		var turned := _shot(Shot.Framing.CLOSE, &"abarax", 1.5)
		turned.yaw_deg = yaw
		shots["close_yaw_%d" % yaw] = [turned, &"abarax", "Fixture line two.", &"smile"]
	for key in shots:
		var entry: Array = shots[key]
		overlay.close()
		await _frame_with(entry[0], entry[1], entry[2], entry[3])
		var hud := main.stage.hud.get_texture().get_image()
		assert_eq(hud.get_size(), Vector2i(640, 360))
		# The bars: 44 solid rows of ink top and bottom, and the row beside each is not covered.
		var ink := Color(Hud.INK, 1.0)
		for y in [0, 20, 43, 316, 330, 359]:
			for x in [0, 200, 639]:
				assert_true(_near(hud.get_pixel(x, y), ink) and hud.get_pixel(x, y).a > 0.99, "%s: bar pixel (%d, %d) is solid ink: %s" % [key, x, y, hud.get_pixel(x, y)])
		for y in [44, 100, 315]:
			assert_true(hud.get_pixel(3, y).a < 0.05, "%s: row %d beside a bar is clear: %s" % [key, y, hud.get_pixel(3, y)])
		# The box and its border.
		var box := overlay.box_rect()
		assert_true(_near(hud.get_pixelv(box.position), Hud.WHITE), "%s: the box's corner is the white border" % key)
		assert_true(_near(hud.get_pixelv(box.end - Vector2i.ONE), Hud.WHITE), "%s: and so is the opposite one" % key)
		assert_true(_near(hud.get_pixel(box.position.x + 4, box.end.y - 4), Color(Hud.INK, 1.0)), "%s: ink inside it" % key)
		assert_true(hud.get_pixel(box.position.x - 1, box.position.y + 20).a < 0.05, "%s: nothing 1 px outside it" % key)
		assert_eq(box.end.y, 356, "%s: its bottom is on row 356, 4 rows above the picture's bottom" % key)
		# The portrait card is not in the HUD's picture: above the box (in the world's rows) the picture is clear where the card is.
		var card := overlay.portrait_rect()
		assert_true(hud.get_pixel(card.position.x + card.size.x / 2, card.position.y + 20).a < 0.05, "%s: the HUD's own picture has no card in it" % key)
		# The text: light pixels in its area (the font is anti-aliased, so few are the white itself).
		var text := overlay.text_rect()
		var white := 0
		for y in range(text.position.y, text.end.y):
			for x in range(text.position.x, text.end.x):
				var drawn := hud.get_pixel(x, y)
				if drawn.r > 0.6 and drawn.g > 0.6 and drawn.b > 0.55:
					white += 1
		assert_true(white > 25, "%s: the text is drawn (%d light pixels)" % [key, white])
		for size in SIZES:
			var window := await _save("cine_%s_%d.png" % [key, size.x], size)
			# The window holds the card: its paper (a warm cream) fills the card's corner, where the world was.
			var scale_k := PixelStage.scale_for(size)
			var corner := PixelStage.layout(size).position + (card.position + Vector2i(3, 3)) * scale_k + Vector2i(scale_k, scale_k) / 2
			var paper := window.get_pixelv(corner)
			assert_true(paper.r > 0.82 and paper.g > 0.78 and paper.b > 0.62 and paper.r > paper.b, "%s at %d: the window shows the card's paper at its corner: %s" % [key, size.x, paper])
		get_window().size = Vector2i(1920, 1080)
		await get_tree().process_frame
