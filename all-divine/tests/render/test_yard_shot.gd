extends TestCase
## The training yard as the game shows it (xvfb, gl_compatibility): the main scene at 1920x1080 with a tier I Knuckle in
## view, saved to out/shots/yard.png for a person to look at. It renders without errors, is a real picture, shows the HUD
## (its rose HP bar sits at the bottom left, in the HUD's own colour: no grade touches it), and the ground a lantern lights
## is brighter than the ground in the dark between the lanterns.

const MAIN := "res://main/main.tscn"
const SHOT := "out/shots/yard.png"
const SIZE := Vector2i(1920, 1080)
## A lantern's (layout.txt: (-9.5, 8)) and the ground 1.5 m from it toward the middle of the yard, and the dark ground by the
## spawn, which no lamp (range 6 m) reaches.
const LIT := Vector3(-8.0, 0.0, 7.0)
const DARK := Vector3(0.0, 0.0, 3.0)
## The box measured round a ground point, in window pixels.
const PATCH := 24


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_yard_shot() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	# Long enough for the shadows to be drawn and the Knuckle to have walked into view.
	await frames(90)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	assert_eq(img.get_size(), SIZE, "the test needs a 1920x1080 window")
	var path := ProjectSettings.globalize_path("res://").path_join(SHOT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(img.save_png(path), OK, "saved %s" % path)
	var colours := {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			colours[img.get_pixel(x, y).to_rgba32()] = true
	assert_true(colours.size() > 40, "the picture has %d colours" % colours.size())
	var foes := main.arena().enemies()
	assert_eq(foes.size(), 1, "a tier I Knuckle")
	assert_true(main.camera_rig.on_screen(foes[0].global_position), "in view")
	# The HUD's HP bar: its fill is the HUD's rose, exactly, at the bottom left (a 3x3 block of the 6x scale... 3x here).
	var k := PixelStage.scale_for(SIZE)
	var origin := PixelStage.layout(SIZE).position
	var hp := main.hud.hp_rect()
	var at := origin + (hp.position + hp.size / 2) * k
	var shown := img.get_pixelv(at)
	assert_true(absf(shown.r - Hud.ROSE.r) < 0.02 and absf(shown.g - Hud.ROSE.g) < 0.02 and absf(shown.b - Hud.ROSE.b) < 0.02,
			"the HP bar is the HUD's rose, ungraded: %s vs %s" % [shown.to_html(false), Hud.ROSE.to_html(false)])
	var lit := _brightness(img, main, LIT)
	var dark := _brightness(img, main, DARK)
	assert_true(lit > dark * 1.15, "the lantern-lit ground (%.3f) is brighter than the dark ground (%.3f)" % [lit, dark])


# The mean luma of the PATCH box round the ground point `at`, in the picture.
func _brightness(img: Image, main: Main, at: Vector3) -> float:
	var stage := main.stage
	var k := PixelStage.scale_for(SIZE)
	var corner := Vector2(PixelStage.layout(SIZE).position + PixelStage.draw_offset(stage.subpixel, k))
	var pixel := corner + main.camera_rig.camera.unproject_position(at) * k
	var total := 0.0
	var count := 0
	for y in range(int(pixel.y) - PATCH / 2, int(pixel.y) + PATCH / 2):
		for x in range(int(pixel.x) - PATCH / 2, int(pixel.x) + PATCH / 2):
			var c := img.get_pixel(clampi(x, 0, SIZE.x - 1), clampi(y, 0, SIZE.y - 1))
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			count += 1
	return total / count
