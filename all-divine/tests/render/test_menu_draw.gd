extends TestCase
## What the menu really draws (xvfb, gl_compatibility): the Hud viewport's own picture (640x360, transparent) is read back with
## the Hud itself hidden, so that every pixel in it is the menu's. The panel is the Hud's ink at 0.9 with a one pixel gold border and
## nothing is drawn right of it; the selected row has a rose chevron and rose text and the others do not; and the text sits on
## whole pixels.

const MAIN := "res://main/main.tscn"
const TOLERANCE := 0.03


func after_each() -> void:
	Game.reset()


# The game paused with the menu up and the Hud hidden, so that the picture is the menu alone.
func _paused() -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.hud.hints_visible = false
	main.hud.visible = false
	await frames(2)
	Game.change(Game.State.PAUSE)
	return main


func _picture(main: Main) -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	return main.stage.hud.get_texture().get_image()


func _is(c: Color, want: Color) -> bool:
	return c.a > 0.8 and absf(c.r - want.r) < TOLERANCE and absf(c.g - want.g) < TOLERANCE and absf(c.b - want.b) < TOLERANCE


# Which of the menu's text colours a lit pixel is (&"rose", &"gold", &"white"), or &"" for a pixel that is not lit text. The
# letters are anti-aliased over the panel's ink, so a pixel is told by its hue, not its exact value.
func _tone(c: Color) -> StringName:
	if c.a < 0.8 or c.r < 0.45:
		return &""
	if c.b > 0.8 * c.r:
		return &"white"
	if c.g < 0.55 * c.r:
		return &"rose"
	return &"gold"


# How many pixels in `area` of `img` are lit text of `tone`.
func _count_tone(img: Image, area: Rect2i, tone: StringName) -> int:
	var n := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if _tone(img.get_pixel(x, y)) == tone:
				n += 1
	return n


# How many pixels in `area` of `img` are `want`.
func _count(img: Image, area: Rect2i, want: Color) -> int:
	var n := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if _is(img.get_pixel(x, y), want):
				n += 1
	return n


func test_the_panel_is_ink_with_a_gold_border_and_nothing_is_drawn_right_of_it() -> void:
	var main := await _paused()
	var img := await _picture(main)
	assert_eq(img.get_size(), Vector2i(640, 360))
	var inside := img.get_pixel(10, 10)
	assert_true(absf(inside.a - Hud.INK.a) < TOLERANCE, "the panel is ink at alpha 0.9: %s" % inside)
	# The image may hold the colour as is or premultiplied by its alpha.
	var plain := absf(inside.r - Hud.INK.r) < TOLERANCE and absf(inside.g - Hud.INK.g) < TOLERANCE
	var premultiplied := absf(inside.r - Hud.INK.r * Hud.INK.a) < TOLERANCE and absf(inside.g - Hud.INK.g * Hud.INK.a) < TOLERANCE
	assert_true(plain or premultiplied, "of the Hud's ink: %s" % inside)
	var panel := main.menu.panel()
	for x in [panel.position.x, panel.position.x + 100, panel.end.x - 1]:
		assert_true(_is(img.get_pixel(x, panel.position.y), Hud.GOLD), "the top border at x %d is gold" % x)
		assert_true(_is(img.get_pixel(x, panel.end.y - 1), Hud.GOLD), "the bottom border at x %d is gold" % x)
	for y in [panel.position.y, panel.position.y + 20, panel.end.y - 1]:
		assert_true(_is(img.get_pixel(panel.position.x, y), Hud.GOLD), "the left border at y %d is gold" % y)
		assert_true(_is(img.get_pixel(panel.end.x - 1, y), Hud.GOLD), "the right border at y %d is gold" % y)
	assert_false(_is(img.get_pixel(panel.position.x + 1, panel.position.y + 1), Hud.GOLD), "the border is one pixel thick")
	assert_true(img.get_pixel(panel.end.x, panel.position.y + 20).a < 0.05, "just outside the panel is clear")
	var drawn_right := 0
	for y in img.get_height():
		for x in range(240, img.get_width()):
			if img.get_pixel(x, y).a >= 0.05:
				drawn_right += 1
	assert_eq(drawn_right, 0, "nothing is drawn at x >= 240")
	var below := 0
	for y in range(190, img.get_height()):
		for x in img.get_width():
			if img.get_pixel(x, y).a >= 0.05:
				below += 1
	assert_eq(below, 0, "nor below y 190")


func test_the_selected_row_has_a_rose_chevron_and_rose_text() -> void:
	var main := await _paused()
	var img := await _picture(main)
	var rows := main.menu.rows()
	assert_eq([rows[0].selected, rows[1].selected], [true, false], "Resume is selected")
	var chevron: Rect2i = rows[0].chevron
	assert_eq(chevron.size, Vector2i(3, 5), "a 3 x 5 chevron")
	var lit := 0
	var cells: Array[String] = ["X..", ".X.", "..X", ".X.", "X.."]
	for y in 5:
		for x in 3:
			var pixel := img.get_pixel(chevron.position.x + x, chevron.position.y + y)
			if cells[y][x] == "X":
				assert_true(_is(pixel, Hud.ROSE), "chevron cell %d,%d is rose: %s" % [x, y, pixel])
				lit += 1
			else:
				assert_true(pixel.a < 0.9 or not _is(pixel, Hud.ROSE), "cell %d,%d is not" % [x, y])
	assert_eq(lit, 5, "five rose cells")
	var other: Rect2i = rows[1].chevron
	assert_eq(_count(img, other, Hud.ROSE), 0, "the other row has no chevron")
	var text_area := Rect2i(rows[0].text_at.x, rows[0].rect.position.y, 60, 10)
	assert_true(_count_tone(img, text_area, &"rose") > 10, "Resume's text is rose")
	assert_eq(_count_tone(img, text_area, &"white"), 0, "and not white")
	var other_text := Rect2i(rows[1].text_at.x, rows[1].rect.position.y, 60, 10)
	assert_true(_count_tone(img, other_text, &"white") > 5, "Quit's text is the Hud's white")
	assert_eq(_count_tone(img, other_text, &"rose"), 0, "and not rose")
	var heading := Rect2i(main.menu.layout().heading_at.x, main.menu.layout().heading_at.y - 8, 80, 10)
	assert_true(_count_tone(img, heading, &"gold") > 10, "the heading is gold")
	assert_eq(_count_tone(img, heading, &"rose"), 0, "and not rose")
	main.menu.press(MenuNav.Cmd.DOWN)
	var moved := await _picture(main)
	assert_true(_count(moved, rows[1].chevron, Hud.ROSE) == 5, "after Down the chevron is on Quit")
	assert_eq(_count(moved, rows[0].chevron, Hud.ROSE), 0, "and off Resume")


# The first column of the heading with lit text in it.
func _first_column(img: Image, main: Main) -> int:
	var at: Vector2i = main.menu.layout().heading_at
	for x in range(at.x - 4, at.x + 20):
		for y in range(at.y - 9, at.y + 3):
			if _tone(img.get_pixel(x, y)) != &"":
				return x
	return -1


func test_the_text_is_drawn_at_whole_pixels() -> void:
	var main := await _paused()
	var img := await _picture(main)
	var at: Vector2i = main.menu.layout().heading_at
	var first := _first_column(img, main)
	assert_true(first >= at.x and first <= at.x + 2, "the heading's first lit column (%d) is at its text's x (%d), give or take the glyph's own bearing" % [first, at.x])
	var region := Rect2i(at.x - 2, at.y - 10, 60, 14)
	var again := await _picture(main)
	assert_eq(again.get_region(region).get_data(), img.get_region(region).get_data(), "drawn twice, the same")
	# Asked for half a pixel further right, the drawing is a whole pixel on: the text is on the pixel grid, never between
	# pixels (a half-pixel position would be a blur of the same letters, not the same letters one pixel along).
	main.menu.position = Vector2(0.5, 0.0)
	var shifted := await _picture(main)
	main.menu.position = Vector2.ZERO
	var moved := Rect2i(region.position + Vector2i(1, 0), region.size)
	assert_ne(shifted.get_region(region).get_data(), img.get_region(region).get_data(), "the half pixel is not ignored")
	assert_eq(shifted.get_region(moved).get_data(), img.get_region(region).get_data(), "it moves the text a whole pixel, with nothing blurred")
