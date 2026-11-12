extends TestCase
## MenuNav: the fixed table of keys and buttons, the stick's flick, the repeat of a held direction, and that rebinding the
## game's actions changes none of it. And the selection's wrap in the Menu.

const C := MenuNav.Cmd


func after_each() -> void:
	Bindings.apply(Bindings.defaults())


func _key(code: Key, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _button(index: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _action(action: StringName, pressed := true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


# Each command, the events that give it.
func _table() -> Array:
	return [
		[C.UP, [_key(KEY_UP), _key(KEY_W), _button(JOY_BUTTON_DPAD_UP)]],
		[C.DOWN, [_key(KEY_DOWN), _key(KEY_S), _button(JOY_BUTTON_DPAD_DOWN)]],
		[C.LEFT, [_key(KEY_LEFT), _key(KEY_A), _button(JOY_BUTTON_DPAD_LEFT)]],
		[C.RIGHT, [_key(KEY_RIGHT), _key(KEY_D), _button(JOY_BUTTON_DPAD_RIGHT)]],
		[C.CHOOSE, [_key(KEY_ENTER), _key(KEY_SPACE), _key(KEY_KP_ENTER), _button(JOY_BUTTON_A)]],
		[C.BACK, [_key(KEY_ESCAPE), _key(KEY_BACKSPACE), _button(JOY_BUTTON_B)]],
	]


func _check_table(why: String) -> void:
	for row: Array in _table():
		for event: InputEvent in row[1]:
			var nav := MenuNav.new()
			assert_eq(nav.command(event), row[0], "%s: %s" % [why, event.as_text()])
			var release: InputEvent = event.duplicate()
			release.set(&"pressed", false)
			assert_eq(nav.command(release), C.NONE, "%s: the release of %s is nothing" % [why, event.as_text()])


func test_keys_and_pad_buttons_give_the_same_commands() -> void:
	_check_table("the table")
	var nav := MenuNav.new()
	assert_eq(nav.command(_key(KEY_UP, true, true)), C.NONE, "a key's echo is nothing")
	assert_eq(nav.command(_key(KEY_F)), C.NONE, "a key the menu does not use is nothing")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_eq(nav.command(click), C.NONE, "the mouse does nothing in a menu")


func test_a_stick_flicks_once_and_is_ready_again_below_the_release() -> void:
	var nav := MenuNav.new()
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, -0.7)), C.UP, "past the flick: up")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, -0.65)), C.NONE, "still pushed: nothing")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, -0.3)), C.NONE, "below the release: nothing, and ready")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, -0.7)), C.UP, "pushed again: up again")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.0)), C.NONE)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.9)), C.DOWN, "the other way: down")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.0)), C.NONE)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, -0.9)), C.LEFT)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, 0.0)), C.NONE)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, 0.9)), C.RIGHT)
	assert_eq(nav.command(_axis(JOY_AXIS_RIGHT_X, 0.9)), C.NONE, "the right stick is not the menu's")


func test_a_held_direction_repeats_after_0_4_s_every_0_1_s() -> void:
	var nav := MenuNav.new()
	assert_eq(nav.tick(0.1), C.NONE, "nothing held, nothing repeats")
	assert_eq(nav.command(_key(KEY_DOWN)), C.DOWN)
	assert_eq(nav.tick(0.39), C.NONE, "before the delay")
	assert_eq(nav.tick(0.02), C.DOWN, "at 0.41 s: the first repeat")
	assert_eq(nav.tick(0.05), C.NONE)
	assert_eq(nav.tick(0.05), C.DOWN, "0.1 s later: the next")
	assert_eq(nav.tick(0.1), C.DOWN, "and the next")
	assert_eq(nav.command(_key(KEY_DOWN, true, true)), C.NONE, "a key's echo adds none")
	assert_eq(nav.tick(0.1), C.DOWN, "the repeat is the menu's, not the keyboard's")
	assert_eq(nav.command(_key(KEY_DOWN, false)), C.NONE)
	assert_eq(nav.tick(0.5), C.NONE, "let go: it stops")
	# A held stick repeats too, and a D-pad; choosing does not.
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, -0.9)), C.UP)
	assert_eq(nav.tick(0.41), C.UP, "the stick repeats")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.0)), C.NONE)
	assert_eq(nav.tick(1.0), C.NONE, "the stick let go: it stops")
	assert_eq(nav.command(_button(JOY_BUTTON_DPAD_LEFT)), C.LEFT)
	assert_eq(nav.tick(0.41), C.LEFT, "the D-pad repeats")
	assert_eq(nav.command(_button(JOY_BUTTON_DPAD_LEFT, false)), C.NONE)
	assert_eq(nav.command(_key(KEY_ENTER)), C.CHOOSE)
	assert_eq(nav.tick(1.0), C.NONE, "a held Enter does not choose again")


func test_a_stick_already_pushed_when_the_menu_opens_moves_nothing() -> void:
	var nav := MenuNav.new()
	var push := _axis(JOY_AXIS_LEFT_Y, -0.9)
	Input.parse_input_event(push)
	Input.flush_buffered_events()
	nav.begin()
	assert_eq(nav.command(push), C.NONE, "the same push gives nothing")
	assert_eq(nav.tick(1.0), C.NONE, "and does not repeat")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.0)), C.NONE)
	assert_eq(nav.command(push), C.UP, "let go and pushed again: up")
	Input.parse_input_event(_axis(JOY_AXIS_LEFT_Y, 0.0))
	Input.flush_buffered_events()


func test_the_menu_action_is_back_whatever_it_is_bound_to() -> void:
	var map := Bindings.defaults()
	map[&"menu"] = [_key(KEY_F10)] as Array[InputEvent]
	Bindings.apply(map)
	var nav := MenuNav.new()
	assert_eq(nav.command(_key(KEY_F10)), C.BACK, "F10, the menu button now")
	assert_eq(nav.command(_key(KEY_ESCAPE)), C.BACK, "Esc is still back")
	assert_eq(nav.command(_action(&"menu")), C.BACK, "so is the action itself")
	assert_eq(nav.command(_action(&"menu", false)), C.NONE, "its release is nothing")
	assert_eq(nav.command(_key(KEY_F10, true, true)), C.NONE, "an echo is nothing")


func test_rebinding_the_games_actions_never_changes_the_menus_keys() -> void:
	Inputs.rebind(&"palm", _key(KEY_ENTER))
	Inputs.rebind(&"dodge", _key(KEY_ESCAPE))
	Inputs.rebind(&"move_up", _key(KEY_DOWN))
	_check_table("after rebinding palm, dodge and move_up")


func test_selection_wraps_at_both_ends() -> void:
	var menu := track(Menu.new()) as Menu
	menu.open()
	assert_eq(menu.index, 0)
	menu.press(C.UP)
	assert_eq(menu.index, menu.rows().size() - 1, "up from the first row selects the last")
	menu.press(C.DOWN)
	assert_eq(menu.index, 0, "down from the last selects the first")
	# A TEXT row is never selected.
	var page := MenuPages.build(&"root", menu)
	page.rows.insert(1, MenuRow.text("A note"))
	menu.show_page(&"root", page)
	assert_eq(menu.index, 0)
	menu.press(C.DOWN)
	assert_eq(menu.rows()[menu.index].label, "Settings", "down skips the text row")
	menu.press(C.UP)
	assert_eq(menu.index, 0, "and so does up")
	menu.press(C.UP)
	assert_eq(menu.rows()[menu.index].label, "Quit", "wrapping lands on a real row")


func test_a_built_page_is_a_typed_page() -> void:
	var menu := track(Menu.new()) as Menu
	var page: Variant = MenuPages.build(&"root", menu)
	assert_true(page is MenuPage, "MenuPages.build gives a MenuPage")
	if page is MenuPage:
		assert_eq([page.heading, page.rows.size(), page.back.is_valid(), page.start], ["Paused", 3, true, 0])


func test_a_diagonal_flick_gives_one_command() -> void:
	var nav := MenuNav.new()
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, 0.8)), C.RIGHT, "the first axis past the flick gives its command")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.9)), C.NONE, "the second, in the same push, gives none")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, 0.0)), C.NONE)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.0)), C.NONE)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, -0.9)), C.UP, "let go, a push on the other axis gives its own")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, -0.9)), C.NONE, "and its diagonal partner none")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_Y, 0.0)), C.NONE)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, -0.9)), C.NONE, "the other axis is still pushed: nothing new until both are let go")
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, 0.0)), C.NONE)
	assert_eq(nav.command(_axis(JOY_AXIS_LEFT_X, -0.9)), C.LEFT, "all let go, pushed again")


func test_a_disabled_row_is_passed_over_and_when_none_can_be_selected_nothing_is() -> void:
	var menu := track(Menu.new()) as Menu
	var page := MenuPages.build(&"root", menu)
	var middle := MenuRow.action("Middle", func() -> void: pass)
	middle.enabled = false
	page.rows.insert(1, middle)
	menu.show_page(&"root", page)
	assert_eq(menu.rows()[0].label, "Resume")
	menu.press(C.DOWN)
	assert_eq(menu.rows()[menu.index].label, "Settings", "Down passes over the disabled row")
	menu.press(C.UP)
	assert_eq(menu.rows()[menu.index].label, "Resume", "and so does Up")
	assert_eq(menu.rows().map(func(r: Dictionary) -> bool: return r.selected), [true, false, false, false])
	for row in page.rows:
		row.enabled = false
	menu.show_page(&"root", page)
	assert_eq(menu.rows().filter(func(r: Dictionary) -> bool: return r.selected).size(), 0, "with every row disabled, none is selected")
	menu.press(C.DOWN)
	menu.press(C.CHOOSE)
	menu.press(C.LEFT)
	assert_eq(menu.rows().filter(func(r: Dictionary) -> bool: return r.selected).size(), 0, "and moving or choosing does nothing")
