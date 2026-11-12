extends TestCase
## The menu as a person sees it (xvfb, gl_compatibility): every page, as the Hud's own 640x360 picture (out/menu/<page>_640.png)
## and as the whole stage at 1920x1080, the world frozen mid-fight behind it (out/menu/<page>_1080.png), saved for a person to
## look at. The fight behind the panel is not dimmed: outside the panel the picture is the one the paused world shows without it.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(1920, 1080)
const DIR := "out/menu"


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func _settle() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw


func _save(img: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(DIR).path_join(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(img.save_png(path), OK, "saved %s" % path)


func test_every_page_is_shot_at_640_and_at_1080() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	# Long enough for the Knuckle to have walked into view and the shadows to be drawn.
	await frames(90)
	Game.change(Game.State.PAUSE)
	await frames(2)
	var k := PixelStage.scale_for(SIZE)
	var origin := PixelStage.layout(SIZE).position
	assert_eq(k, 3, "x3 at 1080p")
	for id in MenuPages.ids():
		main.menu.show_page(id)
		main.menu.visible = false
		await _settle()
		var without := get_viewport().get_texture().get_image()
		main.menu.visible = true
		await _settle()
		var picture := main.stage.hud.get_texture().get_image()
		var stage := get_viewport().get_texture().get_image()
		assert_eq(picture.get_size(), Vector2i(640, 360))
		assert_eq(stage.get_size(), SIZE, "the test needs a 1920x1080 window")
		_save(picture, "%s_640.png" % id)
		_save(stage, "%s_1080.png" % id)
		var panel := main.menu.panel()
		# The panel's gold border is crisp at x3: a solid three pixel line at its top edge, ungraded.
		var edge := origin + (panel.position + Vector2i(40, 0)) * k
		for dy in 3:
			var c := stage.get_pixelv(edge + Vector2i(0, dy))
			assert_true(absf(c.r - Hud.GOLD.r) < 0.03 and absf(c.g - Hud.GOLD.g) < 0.03 and absf(c.b - Hud.GOLD.b) < 0.03, "%s: the border is gold, 3 px at x3 (%s)" % [id, c.to_html(false)])
		# Outside the panel the stage is what the paused world shows without the menu: nothing is dimmed or tinted.
		var differs := 0
		var area := Rect2i(origin + panel.position * k, panel.size * k).grow(k)
		for y in range(0, SIZE.y, 2):
			for x in range(0, SIZE.x, 2):
				if not area.has_point(Vector2i(x, y)) and stage.get_pixel(x, y) != without.get_pixel(x, y):
					differs += 1
		assert_eq(differs, 0, "%s: the fight outside the panel is untouched" % id)
