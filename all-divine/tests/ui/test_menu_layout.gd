extends TestCase
## The menu's panel: as wide as its page needs (no more than 224 px) and fixed while the page is open, and a page with more rows
## than fit above y 190 scrolls, the window of rows following the selection, with a gold arrow where rows are hidden.

const C := MenuNav.Cmd


# A page of `count` ACTION rows called "Row 0" and so on, with a line of words at each index in `texts`.
func _long_page(count: int, texts := [5, 15]) -> MenuPage:
	var page := MenuPage.new()
	page.heading = "A long page"
	page.back = func() -> void: pass
	for i in count:
		page.rows.append(MenuRow.text("A note %d" % i) if texts.has(i) else MenuRow.action("Row %d" % i, func() -> void: pass))
	return page


func _menu_with(page: MenuPage) -> Menu:
	var menu := track(Menu.new()) as Menu
	menu.open()
	menu.show_page(&"long", page)
	return menu


# The page-row indexes shown now.
func _shown(menu: Menu) -> Array:
	return menu.rows().map(func(r: Dictionary) -> int: return r.index)


func _selected_label(menu: Menu) -> String:
	for r in menu.rows():
		if r.selected:
			return r.label
	return ""


func test_the_root_page_is_narrower_than_140_px_and_every_text_fits_inside_it() -> void:
	var menu := track(Menu.new()) as Menu
	menu.open()
	for id in [&"root", &"quit"]:
		menu.show_page(id)
		var panel := menu.panel()
		assert_true(panel.size.x < 140, "%s: the panel is %d px wide" % [id, panel.size.x])
		assert_eq(panel.position, Vector2i(8, 8), "%s: where it was" % id)
		var font := ThemeDB.fallback_font
		var inner := panel.end.x - Menu.PADDING
		var layout := menu.layout()
		var widths: Array[int] = [layout.heading_at.x + ceili(font.get_string_size(menu.heading(), HORIZONTAL_ALIGNMENT_LEFT, -1, Menu.FONT_SIZE).x)]
		widths.append(layout.footer_at.x + ceili(font.get_string_size(menu.footer(), HORIZONTAL_ALIGNMENT_LEFT, -1, Menu.FONT_SIZE).x))
		for r in menu.rows():
			widths.append(r.text_at.x + ceili(font.get_string_size(r.label, HORIZONTAL_ALIGNMENT_LEFT, -1, Menu.FONT_SIZE).x))
		for w in widths:
			assert_true(w <= inner, "%s: a text ending at %d is inside the padding (%d)" % [id, w, inner])
	menu.show_page(&"root")
	var rows := menu.rows()
	assert_eq([rows[0].rect.position.y, rows[1].rect.position.y, menu.panel().size.y], [28, 38, 60], "heights as before")


func test_a_page_whose_row_would_pass_224_is_cut_there_and_the_width_stays_while_open() -> void:
	var page := MenuPage.new()
	page.heading = "Wide"
	page.back = func() -> void: pass
	page.rows.append(MenuRow.action("A row with a very long label that would run well past the column's edge of two hundred and twenty-four", func() -> void: pass))
	var menu := _menu_with(page)
	assert_eq(menu.panel().size.x, 224, "cut at 224")
	# A value that changes does not change the width.
	var value := ["1"]
	var slider := MenuRow.new()
	slider.kind = MenuRow.Kind.SLIDER
	slider.label = "Volume"
	slider.value_text = func() -> String: return value[0]
	var p2 := MenuPage.new()
	p2.heading = "Sound"
	p2.back = func() -> void: pass
	p2.rows.append(slider)
	menu.show_page(&"sound", p2)
	var before := menu.panel().size.x
	value[0] = "100 percent of everything"
	assert_eq(menu.panel().size.x, before, "a changing value does not resize the panel")


func test_a_long_page_scrolls_and_the_selection_is_always_shown() -> void:
	var menu := _menu_with(_long_page(20))
	var panel := menu.panel()
	assert_true(panel.end.y <= 190, "the panel ends at or above y 190 (%d)" % panel.end.y)
	assert_eq(menu.rows().size(), 14, "fourteen rows fit")
	assert_true(menu.layout().arrow_up.size == Vector2i.ZERO, "nothing hidden above at the top: no up arrow")
	assert_true(menu.layout().arrow_down.size != Vector2i.ZERO, "rows hidden below: a down arrow")
	for step in 60:
		menu.press(C.DOWN)
		var shown := _shown(menu)
		assert_true(shown.has(menu.index), "step %d: the selected row %d is among those shown" % [step, menu.index])
		assert_eq(_selected_label(menu), "Row %d" % menu.index, "step %d: and it is the one drawn selected" % step)
		assert_false([5, 15].has(menu.index), "step %d: text is never selected" % step)
		assert_eq(menu.panel(), panel, "step %d: the panel does not move or change width" % step)
		assert_eq(menu.layout().arrow_up.size != Vector2i.ZERO, shown[0] > 0, "step %d: the up arrow shows when and only when rows are hidden above" % step)
		assert_eq(menu.layout().arrow_down.size != Vector2i.ZERO, shown[-1] < 19, "step %d: the down arrow likewise below" % step)


func test_the_window_moves_one_row_at_its_edge_and_wraps_to_the_ends() -> void:
	var menu := _menu_with(_long_page(20, []))
	for i in 13:
		menu.press(C.DOWN)
	assert_eq([menu.index, _shown(menu)[0]], [13, 0], "down to the last row shown: the window has not moved")
	menu.press(C.DOWN)
	assert_eq([menu.index, _shown(menu)[0]], [14, 1], "one past its edge moves it one row")
	menu.press(C.UP)
	menu.press(C.UP)
	assert_eq([menu.index, _shown(menu)[0]], [12, 1], "going back up inside it does not")
	for i in 12:
		menu.press(C.UP)
	assert_eq([menu.index, _shown(menu)[0]], [0, 0], "up to the first row: the window is at the top")
	menu.press(C.UP)
	assert_eq([menu.index, _shown(menu)[0], _shown(menu)[-1]], [19, 6, 19], "wrapping up from the first to the last moves the window to the bottom")
	assert_true(menu.layout().arrow_down.size == Vector2i.ZERO and menu.layout().arrow_up.size != Vector2i.ZERO, "only the up arrow there")
	menu.press(C.DOWN)
	assert_eq([menu.index, _shown(menu)[0]], [0, 0], "wrapping down from the last to the first moves it to the top")


func test_a_page_that_fits_has_no_arrows_and_shows_every_row() -> void:
	var menu := _menu_with(_long_page(14, []))
	assert_eq(menu.rows().size(), 14, "fourteen fit")
	assert_true(menu.layout().arrow_up.size == Vector2i.ZERO and menu.layout().arrow_down.size == Vector2i.ZERO, "no arrows")
	assert_true(menu.panel().end.y <= 190)
