extends TestCase
## What the menu really draws (xvfb, gl_compatibility): the Hud viewport's own picture (640x360, transparent) is read back with
## the Hud itself hidden, so that every pixel in it is the menu's. The panel is the Hud's ink at 0.9 with a one pixel gold border and
## nothing is drawn right of it; the selected row has a rose chevron and rose text and the others do not; and the text sits on
## whole pixels.

const MAIN := "res://main/main.tscn"
const TOLERANCE := 0.03
const SETTINGS_PATH := "user://settings_test.cfg"


func before_each() -> void:
	Settings.path = SETTINGS_PATH


func after_each() -> void:
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


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
	assert_true(_count_tone(img, other_text, &"white") > 5, "Settings' text is the Hud's white")
	assert_eq(_count_tone(img, other_text, &"rose"), 0, "and not rose")
	var heading := Rect2i(main.menu.layout().heading_at.x, main.menu.layout().heading_at.y - 8, 80, 10)
	assert_true(_count_tone(img, heading, &"gold") > 10, "the heading is gold")
	assert_eq(_count_tone(img, heading, &"rose"), 0, "and not rose")
	main.menu.press(MenuNav.Cmd.DOWN)
	var moved := await _picture(main)
	assert_true(_count(moved, rows[1].chevron, Hud.ROSE) == 5, "after Down the chevron is on Settings")
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


# A page of the menu shown, with the row called `label` the first selected.
func _page(main: Main, id: StringName, label := "") -> void:
	main.menu.show_page(id)
	for i in 14:
		if label.is_empty() or main.menu.rows()[main.menu.index].label == label:
			return
		main.menu.press(MenuNav.Cmd.DOWN)


func _row(main: Main, label: String) -> Dictionary:
	for r in main.menu.rows():
		if r.label == label:
			return r
	return {}


func test_a_slider_is_drawn_with_a_gold_fill_of_its_percent() -> void:
	var main := await _paused()
	# Camera shake at each of its steps; the selection stays on Back, so that the row is drawn as any other.
	for percent in [100, 75, 50, 25, 0]:
		Settings.set_value("camera/shake", percent)
		_page(main, &"camera", "Back")
		var img := await _picture(main)
		var row := _row(main, "Camera shake")
		var bar: Rect2i = row.bar
		assert_eq(bar.size, Vector2i(42, 5), "a 40 px bar with a 1 px outline")
		assert_eq(row.fill, percent * 40 / 100, "%d%% fills %d px" % [percent, percent * 40 / 100])
		var mid := bar.position.y + 2
		var gold := 0
		for x in 40:
			var lit := _is(img.get_pixel(bar.position.x + 1 + x, mid), Hud.GOLD)
			assert_eq(lit, x < row.fill, "%d%%: pixel %d of the bar is %s" % [percent, x, "gold" if x < row.fill else "not gold"])
			gold += 1 if lit else 0
		assert_eq(gold, percent * 40 / 100, "%d%%: gold pixels in the bar's middle line" % percent)
		for dx in [0, 41]:
			for dy in 5:
				var edge := img.get_pixel(bar.position.x + dx, bar.position.y + dy)
				assert_true(edge.a > Hud.INK.a + 0.05, "%d%%: the outline pixel (%d,%d) is the ink over the panel's ink: %s" % [percent, dx, dy, edge])
		for dx in range(1, 41, 8):
			for dy in [0, 4]:
				assert_true(img.get_pixel(bar.position.x + dx, bar.position.y + dy).a > Hud.INK.a + 0.05, "%d%%: and so is the outline above and below" % percent)
		# The percent is in gold text to the right of it, ending at the panel's right padding.
		var text := Rect2i(row.value_at.x, row.rect.position.y, 30, 10)
		assert_true(_count_tone(img, text, &"gold") > 6, "%d%%: the percent is gold text" % percent)
		assert_true(bar.end.x < row.value_at.x, "and the bar is left of it")
		assert_eq(bar.end.y <= row.rect.end.y and bar.position.y >= row.rect.position.y, true, "the bar is inside its row")


func test_a_toggle_shows_On_in_gold_and_Off_in_gold() -> void:
	var main := await _paused()
	Settings.set_value("effects/heavy_wave_on", false)
	_page(main, &"effects", "Back")
	var img := await _picture(main)
	var on := _row(main, "Perilous rim")
	var off := _row(main, "Heavy-attack wave")
	assert_eq([on.value, off.value], ["On", "Off"])
	for row in [on, off]:
		var text := Rect2i(row.value_at.x - 1, row.rect.position.y, 24, 10)
		assert_true(_count_tone(img, text, &"gold") > 6, "%s: %s is drawn in gold" % [row.label, row.value])
		assert_eq(_count_tone(img, text, &"white") + _count_tone(img, text, &"rose"), 0, "%s: and in no other colour" % row.label)
		var label := Rect2i(row.text_at.x, row.rect.position.y, 60, 10)
		assert_true(_count_tone(img, label, &"white") > 6, "%s: the label is white" % row.label)
	# Selected, the value takes the row's rose with the label.
	_page(main, &"effects", "Perilous rim")
	var picked := await _picture(main)
	var row := _row(main, "Perilous rim")
	assert_true(_count_tone(picked, Rect2i(row.value_at.x - 1, row.rect.position.y, 24, 10), &"rose") > 4, "a selected row's value is rose")


func test_a_dim_row_is_drawn_in_the_dim_colour_label_and_value() -> void:
	var main := await _paused()
	Settings.set_value("window/mode", "fullscreen")
	_page(main, &"window")
	var img := await _picture(main)
	var size := _row(main, "Size")
	assert_false(size.enabled)
	var label := Rect2i(size.text_at.x, size.rect.position.y, 24, 10)
	var value := Rect2i(size.value_at.x - 1, size.rect.position.y, main.menu.panel().end.x - Menu.PADDING - size.value_at.x + 1, 10)
	var live := _row(main, "Back")
	var live_peak := _peak(img, Rect2i(live.text_at.x, live.rect.position.y, 24, 10))
	for area in [label, value]:
		assert_eq(_count_tone(img, area, &"gold") + _count_tone(img, area, &"rose") + _count(img, area, Hud.WHITE), 0, "no gold, rose or warm white text in the dim row")
		var peak := _peak(img, area)
		assert_true(peak.get_luminance() > 0.25, "the dim row can be read (%s)" % peak.to_html(false))
		assert_true(peak.get_luminance() < 0.8 * live_peak.get_luminance(), "and is plainly dimmer than a live row's text: %.2f against %.2f" % [peak.get_luminance(), live_peak.get_luminance()])
		assert_true(peak.b >= peak.r * 0.95, "in Hud.POSTURE's cool white, not the live rows' warm one (%s)" % peak.to_html(false))


# The brightest pixel of `area`.
func _peak(img: Image, area: Rect2i) -> Color:
	var best := Color.BLACK
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.get_luminance() > best.get_luminance():
				best = c
	return best


# The picture of the world (not the menu) now: the menu hidden for the capture, the tree paused throughout.
func _world(main: Main) -> Image:
	main.menu.visible = false
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	main.menu.visible = true
	return img


func _differing(a: Image, b: Image) -> int:
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func test_each_look_slider_changes_the_picture_at_once_while_paused() -> void:
	var main := await _paused()
	await frames(60)
	for item: Array in SettingsPages.LOOK_ROWS:
		Settings.set_value("look/" + item[1], 100)
		_page(main, &"look", item[0])
		var full := await _world(main)
		var again := await _world(main)
		assert_eq(_differing(full, again), 0, "%s: the paused picture is steady, so a difference is the slider's" % item[0])
		for i in 4:
			main.menu.press(MenuNav.Cmd.LEFT)
		assert_eq(Settings.get_value("look/" + item[1]), 0, "%s: moved to 0 in the menu" % item[0])
		assert_true(get_tree().paused, "still paused")
		var none := await _world(main)
		var changed := _differing(full, none)
		assert_true(changed > 40, "%s: 0 and 100 differ in %d sampled pixels of the world's picture, with the game paused" % [item[0], changed])
		for i in 4:
			main.menu.press(MenuNav.Cmd.RIGHT)
		var back := await _world(main)
		assert_eq(_differing(full, back), 0, "%s: and back at 100 it is the first picture again" % item[0])
