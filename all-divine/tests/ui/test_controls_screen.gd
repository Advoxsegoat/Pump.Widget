extends TestCase
## The controls screen of the pause menu (ui/controls_page.gd): the bindings of the device in hand, and rebinding them through
## Inputs.rebind with a capture that takes the next press of that device.
##
## Every test that rebinds puts the table back (after_each) and keeps its file in a path of its own, never the player's input.cfg.

const MAIN := "res://main/main.tscn"
const FILE := "user://controls_screen_test.cfg"
const C := MenuNav.Cmd
const KEYBOARD_LEGEND := "Enter: change   Esc: back"
const PAD_LEGEND := "A: change   B: back"

var _pad_in := false  # whether the menus under test think a pad is connected
var _path_was := ""


func before_each() -> void:
	Game.reset()
	Bindings.apply(Bindings.defaults())
	_path_was = Inputs.bindings_path
	Inputs.bindings_path = FILE
	_remove_file()
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	_pad_in = false


func after_each() -> void:
	for code in [KEY_F, KEY_F10, KEY_ESCAPE, KEY_ENTER, KEY_G]:
		_release_key(code)
	_rest_sticks()
	Game.reset()
	Bindings.apply(Bindings.defaults())
	Inputs.bindings_path = _path_was
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	_remove_file()


func _remove_file() -> void:
	for file in [FILE, FILE + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


# --- helpers ---

# A menu, open on the root page, that knows whether a pad is connected by _pad_in.
func _menu() -> Menu:
	var menu := track(Menu.new()) as Menu
	menu.web = false
	menu.pad_present = func() -> bool: return _pad_in
	menu.open()
	return menu


# A menu on the Controls page, the hand on the pad when `pad` (and the pad connected).
func _controls(pad := false) -> Menu:
	_pad_in = pad
	Inputs._device = Inputs.Device.GAMEPAD if pad else Inputs.Device.KEYBOARD_MOUSE
	var menu := _menu()
	menu.show_page(MenuPages.CONTROLS)
	return menu


func _k(code: Key, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _b(button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _m(button: MouseButton, pressed := true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _a(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


# An event as the game gets it: the Inputs autoload sees it first (it keeps the hand), then the menu.
func _send(menu: Menu, event: InputEvent) -> bool:
	Inputs._input(event)
	return menu.handle(event)


# A press and its release.
func _tap(menu: Menu, event: InputEvent) -> void:
	_send(menu, event)
	var up := event.duplicate() as InputEvent
	if up is InputEventKey:
		(up as InputEventKey).pressed = false
	elif up is InputEventJoypadButton:
		(up as InputEventJoypadButton).pressed = false
	elif up is InputEventMouseButton:
		(up as InputEventMouseButton).pressed = false
	_send(menu, up)


func _release_key(code: Key) -> void:
	var event := _k(code, false)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _rest_sticks() -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		Input.parse_input_event(_a(axis, 0.0))
	Input.flush_buffered_events()


func _labels(menu: Menu) -> Array:
	return menu.rows().map(func(r: Dictionary) -> String: return r.label)


# Every row of the page, shown or not, by walking the selection down it: {label: row}.
func _all_rows(menu: Menu) -> Array[Dictionary]:
	var seen := {}
	for i in 40:
		for r in menu.rows():
			seen[r.index] = r
		menu.press(C.DOWN)
	var keys := seen.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for key in keys:
		out.append(seen[key])
	return out


func _row(menu: Menu, label: String) -> Dictionary:
	for r in _all_rows(menu):
		if r.label == label:
			return r
	return {}


func _value(menu: Menu, label: String) -> String:
	var row := _row(menu, label)
	return row.get("value", "<no row %s>" % label)


# The selection on the row called `label`, going down from wherever it is.
func _select(menu: Menu, label: String) -> void:
	for i in 40:
		var rows := menu.rows().filter(func(r: Dictionary) -> bool: return r.index == menu.index)
		if not rows.is_empty() and rows[0].label == label:
			return
		menu.press(C.DOWN)
	fail("could not select '%s'" % label)


# The row `label` selected and chosen with the Enter key (or the pad's A), as a player would.
func _start(menu: Menu, label: String, pad := false) -> void:
	_select(menu, label)
	if pad:
		_tap(menu, _b(JOY_BUTTON_A))
	else:
		_tap(menu, _k(KEY_ENTER))


func _table() -> Dictionary:
	var out := {}
	var map := Bindings.current()
	for action in map:
		out[action] = map[action].map(Bindings.event_to_data)
	return out


func _defaults() -> Dictionary:
	var out := {}
	var map := Bindings.defaults()
	for action in map:
		out[action] = map[action].map(Bindings.event_to_data)
	return out


# What the saved file holds for `action`.
func _saved(action: StringName) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return ["<no file>"]
	return cfg.get_value("bindings", action, ["<no entry>"])


func _key_data(code: Key) -> Dictionary:
	return {"type": "key", "code": int(code)}


func _pause() -> void:
	if Game.state != Game.State.PLAY:
		Game.reset()
		Game.change(Game.State.PLAY)
	Game.change(Game.State.PAUSE)


func _main(calm := true) -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	if calm:
		for foe in main.arena().enemies():
			foe.set_brain(Brain.new())
	await frames(2)
	return main


# A key down and up as the window delivers it (Main sees it, and the InputMap).
func _window_key(code: Key, pressed := true) -> void:
	var event := _k(code, pressed)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# --- the page ---

func test_the_root_page_lists_resume_controls_settings_quit() -> void:
	var menu := _menu()
	assert_eq(_labels(menu), ["Resume", "Controls", "Settings", "Quit"])
	menu.web = true
	menu.show_page(MenuPages.ROOT)
	assert_eq(_labels(menu), ["Resume", "Controls", "Settings"], "on the web, without Quit")
	menu.press(C.DOWN)
	menu.press(C.CHOOSE)
	assert_eq([menu.page, menu.heading()], [MenuPages.CONTROLS, "Controls: Keyboard and mouse"], "Controls opens the page")
	menu.press(C.BACK)
	assert_eq([menu.page, menu.index], [MenuPages.ROOT, 1], "and Back returns to the row it left")


func test_the_page_shows_the_bindings_of_the_device_in_hand() -> void:
	var menu := _controls()
	assert_eq(menu.heading(), "Controls: Keyboard and mouse")
	assert_eq(_value(menu, "Palm"), "LMB")
	assert_eq(_value(menu, "Guard (tap: parry)"), "Q")
	assert_eq(_value(menu, "Dash-step (hold: sprint)"), "Shift / Space")
	assert_eq(_value(menu, "Lock on"), "Tab")
	assert_eq(_value(menu, "Move up"), "W")
	assert_eq(_value(menu, "Target left"), "Not bound")
	assert_eq(_value(menu, "Menu / back"), "Escape")
	assert_eq(menu.footer(), KEYBOARD_LEGEND)
	var pad := _controls(true)
	assert_eq(pad.heading(), "Controls: Gamepad")
	assert_eq(_value(pad, "Palm"), "RB")
	assert_eq(_value(pad, "Guard (tap: parry)"), "LB")
	assert_eq(_value(pad, "Heavy (hold: charge)"), "RT")
	assert_eq(_value(pad, "Move up"), "L stick up")
	assert_eq(_value(pad, "Menu / back"), "Start")
	assert_eq(pad.footer(), PAD_LEGEND)


func test_the_page_has_twelve_bindings_two_lines_of_words_restore_and_back() -> void:
	var menu := _controls()
	var rows := _all_rows(menu)
	var want: Array = ControlsList.ACTION_ROWS.map(func(r: Array) -> String: return r[1])
	want.append_array([ControlsList.ROWS[4][0], ControlsList.FINISHER_NOTE, "Restore default controls", "Back"])
	assert_eq(rows.map(func(r: Dictionary) -> String: return r.label), want)
	var kinds := rows.map(func(r: Dictionary) -> int: return r.kind)
	assert_eq(kinds.slice(0, 12), range(12).map(func(_i: int) -> int: return MenuRow.Kind.BINDING))
	assert_eq(kinds.slice(12, 14), [MenuRow.Kind.TEXT, MenuRow.Kind.TEXT])
	var selected := []
	for i in 20:
		var shown := menu.rows().filter(func(r: Dictionary) -> bool: return r.selected)
		selected.append(shown.size())
		assert_ne(shown[0].kind if not shown.is_empty() else -1, MenuRow.Kind.TEXT, "a line of words is never selected")
		menu.press(C.DOWN)
	assert_eq(selected.filter(func(n: int) -> bool: return n != 1), [], "exactly one row selected whenever there is one")


func test_the_page_scrolls_and_stays_inside_its_limits() -> void:
	var menu := _controls()
	var width := menu.panel().size.x
	var arrows := []
	for i in 40:
		var map := menu.layout()
		assert_true(menu.panel().end.y <= 190, "step %d: the panel ends above y 190 (%s)" % [i, menu.panel()])
		assert_eq(menu.panel().size.x, width, "step %d: the width does not change" % i)
		assert_true(menu.panel().size.x <= Menu.PANEL_W)
		assert_true(map.rows.any(func(r: Dictionary) -> bool: return r.selected), "step %d: the selection is shown" % i)
		arrows.append([(map.arrow_up as Rect2i).size != Vector2i.ZERO, (map.arrow_down as Rect2i).size != Vector2i.ZERO])
		menu.press(C.DOWN)
	assert_true(arrows.has([false, true]) and arrows.has([true, false]) and arrows.has([true, true]), "the arrows show when rows are hidden: %s" % [arrows.slice(0, 4)])


func test_a_pad_that_is_gone_shows_the_keyboards_list() -> void:
	var menu := _controls(true)
	assert_eq(menu.heading(), "Controls: Gamepad")
	_pad_in = false
	Input.joy_connection_changed.emit(0, false)
	assert_eq(menu.heading(), "Controls: Keyboard and mouse", "the pad is unplugged while the page is open: it is rebuilt")
	assert_eq(_value(menu, "Palm"), "LMB")
	assert_eq(menu.footer(), KEYBOARD_LEGEND)
	assert_eq(Inputs.last_device(), Inputs.Device.GAMEPAD, "Inputs still says pad: the page does not rely on it")
	_pad_in = true
	menu.show_page(MenuPages.CONTROLS)
	assert_eq(menu.heading(), "Controls: Gamepad", "plugged in again")


func test_the_list_follows_the_hand_while_browsing() -> void:
	var menu := _controls()
	_pad_in = true
	assert_eq(menu.heading(), "Controls: Keyboard and mouse")
	_send(menu, _b(JOY_BUTTON_X))
	assert_eq(menu.heading(), "Controls: Gamepad", "a pad button")
	assert_eq(_value(menu, "Palm"), "RB")
	_send(menu, _k(KEY_G))
	assert_eq(menu.heading(), "Controls: Keyboard and mouse", "a key")
	assert_eq(_value(menu, "Palm"), "LMB")
	_send(menu, _a(JOY_AXIS_RIGHT_X, 0.9))
	assert_eq(menu.heading(), "Controls: Gamepad", "a stick")
	_send(menu, _m(MOUSE_BUTTON_LEFT))
	assert_eq(menu.heading(), "Controls: Keyboard and mouse", "a mouse button")
	assert_eq(menu.footer(), KEYBOARD_LEGEND)
	_send(menu, _a(JOY_AXIS_RIGHT_X, 0.0))
	_send(menu, _b(JOY_BUTTON_X))
	assert_eq(menu.footer(), PAD_LEGEND, "and the footer follows")
	menu._process(0.016)
	assert_eq(menu.heading(), "Controls: Gamepad", "a frame later nothing flips back")


# --- capture ---

func test_capturing_a_key_rebinds_the_first_key_and_saves() -> void:
	var menu := _controls()
	_start(menu, "Palm")
	assert_true(menu.capturing())
	assert_eq(menu.footer(), "Press a new key or mouse button for Palm. Esc cancels.")
	assert_eq(_value(menu, "Palm"), "...", "the row shows ...")
	_tap(menu, _k(KEY_F))
	assert_false(menu.capturing())
	assert_eq(ControlsList.shown(&"palm", false), "F", "the first keyboard-or-mouse event of palm (LMB) is replaced by F")
	assert_eq(ControlsList.shown(&"palm", true), "RB", "the pad's RB stays")
	assert_eq(_saved(&"palm"), [{"type": "button", "button": int(JOY_BUTTON_RIGHT_SHOULDER)}, _key_data(KEY_F)], "and the file holds it")
	assert_eq(menu.footer(), "Swapped with interact.", "F was Interact's: they swapped")
	menu._process(3.1)
	assert_eq(menu.footer(), KEYBOARD_LEGEND, "the footer is the legend again")
	assert_eq(_value(menu, "Palm"), "F")
	assert_eq(menu.page, MenuPages.CONTROLS)


func test_capturing_a_mouse_button_a_pad_button_a_trigger_and_a_stick() -> void:
	var menu := _controls()
	_start(menu, "Palm")
	_send(menu, _m(MOUSE_BUTTON_WHEEL_UP))
	_send(menu, _m(MOUSE_BUTTON_WHEEL_DOWN))
	assert_true(menu.capturing(), "the mouse wheel is ignored")
	_send(menu, _m(MOUSE_BUTTON_MIDDLE))
	assert_false(menu.capturing())
	assert_eq(ControlsList.shown(&"palm", false), "MMB")
	var pad := _controls(true)
	_start(pad, "Palm", true)
	assert_eq(pad.footer(), "Press a new button for Palm. B cancels.")
	_send(pad, _b(JOY_BUTTON_Y))
	assert_false(pad.capturing())
	assert_eq(ControlsList.shown(&"palm", true), "Y", "a pad button")
	_start(pad, "Heavy (hold: charge)", true)
	_send(pad, _a(JOY_AXIS_TRIGGER_LEFT, 0.9))
	assert_false(pad.capturing())
	assert_eq(ControlsList.shown(&"heavy", true), "LT", "a trigger")
	_start(pad, "Lock on", true)
	_send(pad, _a(JOY_AXIS_RIGHT_Y, -0.59))
	_send(pad, _a(JOY_AXIS_TRIGGER_RIGHT, 0.3))
	_send(pad, _a(JOY_AXIS_LEFT_X, 0.1))
	assert_true(pad.capturing(), "a stick or trigger below 0.6 is ignored")
	_send(pad, _a(JOY_AXIS_RIGHT_Y, -0.9))
	assert_false(pad.capturing())
	assert_eq(ControlsList.shown(&"lock_on", true), "R stick up", "a stick says its direction")
	assert_eq(_saved(&"lock_on").size(), 2, "and it is kept")


func test_a_stick_already_pushed_when_the_capture_starts_must_return_to_rest() -> void:
	var menu := _controls(true)
	var push := _a(JOY_AXIS_RIGHT_X, 0.9)
	Input.parse_input_event(push)
	Input.flush_buffered_events()
	_start(menu, "Lock on", true)
	_send(menu, push)
	_send(menu, _a(JOY_AXIS_RIGHT_X, 0.95))
	assert_true(menu.capturing(), "a stick already past 0.6 binds nothing while it stays there")
	_send(menu, _a(JOY_AXIS_RIGHT_X, 0.3))
	_send(menu, _a(JOY_AXIS_RIGHT_X, 0.9))
	assert_false(menu.capturing(), "let go and pushed again it binds")
	assert_eq(ControlsList.shown(&"lock_on", true), "R stick right")


func test_an_event_of_the_other_device_is_ignored_while_capturing() -> void:
	var menu := _controls(true)
	_start(menu, "Palm", true)
	var before := _table()
	for event: InputEvent in [_k(KEY_F), _k(KEY_SHIFT), _m(MOUSE_BUTTON_LEFT), _m(MOUSE_BUTTON_RIGHT)]:
		_send(menu, event)
	assert_true(menu.capturing(), "a key and a mouse button do not end a pad capture")
	assert_eq(_table(), before, "and bind nothing")
	assert_eq(menu.heading(), "Controls: Gamepad", "the rows still show the pad")
	assert_eq(_value(menu, "Guard (tap: parry)"), "LB")
	assert_eq(_value(menu, "Palm"), "...")
	_send(menu, _b(JOY_BUTTON_X))
	assert_false(menu.capturing())
	var keys := _controls()
	_start(keys, "Palm")
	for event: InputEvent in [_b(JOY_BUTTON_X), _b(JOY_BUTTON_A), _a(JOY_AXIS_LEFT_X, 0.9), _a(JOY_AXIS_TRIGGER_RIGHT, 1.0)]:
		_send(keys, event)
	assert_true(keys.capturing(), "a pad button, stick or trigger does not end a keyboard capture")
	assert_eq(keys.heading(), "Controls: Keyboard and mouse", "the shown device is held fixed")
	assert_eq(keys.footer(), "Press a new key or mouse button for Palm. Esc cancels.")


func test_escape_and_b_cancel_a_capture_and_nothing_changes() -> void:
	var defaults := _defaults()
	for pad in [false, true]:
		for cancel: InputEvent in [_k(KEY_ESCAPE), _b(JOY_BUTTON_B)]:
			var menu := _controls(pad)
			_start(menu, "Guard (tap: parry)", pad)
			assert_true(menu.capturing())
			_send(menu, cancel)
			assert_false(menu.capturing(), "%s capture cancelled by %s" % ["pad" if pad else "keyboard", cancel])
			assert_eq(_table(), defaults, "nothing changed, Esc and B are never bound")
			assert_false(FileAccess.file_exists(FILE), "nothing was saved")
			assert_eq(menu.page, MenuPages.CONTROLS, "and the page stays")
			assert_true([KEYBOARD_LEGEND, PAD_LEGEND].has(menu.footer()), "the legend is back: %s" % menu.footer())
			assert_eq(_value(menu, "Guard (tap: parry)"), ControlsList.shown(&"guard", menu.heading() == "Controls: Gamepad"), "the row is its binding again")


func test_a_capture_gives_up_after_six_seconds_of_menu_time() -> void:
	_pause()
	var menu := _controls()
	assert_true(get_tree().paused)
	_start(menu, "Palm")
	for i in 5:
		menu._process(1.0)
	assert_true(menu.capturing(), "5 s: still waiting")
	menu._process(0.9)
	assert_true(menu.capturing(), "5.9 s")
	menu._process(0.2)
	assert_false(menu.capturing(), "past 6 s it gives up")
	assert_eq(_table(), _defaults())
	assert_eq(menu.footer(), KEYBOARD_LEGEND)
	assert_eq(_value(menu, "Palm"), "LMB")


func test_unplugging_the_pad_during_a_pad_capture_cancels_it() -> void:
	var menu := _controls(true)
	_start(menu, "Palm", true)
	assert_true(menu.capturing())
	_pad_in = false
	Input.joy_connection_changed.emit(0, false)
	assert_false(menu.capturing())
	assert_eq(menu.footer(), "Pad disconnected.")
	assert_eq(_table(), _defaults(), "nothing bound")
	assert_eq(menu.heading(), "Controls: Keyboard and mouse", "the keyboard's list is shown")
	menu._process(3.1)
	assert_eq(menu.footer(), KEYBOARD_LEGEND, "the note goes after 3 s")
	# A pad that goes while a keyboard capture waits does not end it.
	var keys := _controls()
	_start(keys, "Palm")
	Input.joy_connection_changed.emit(1, false)
	assert_true(keys.capturing(), "a keyboard capture does not care")


func test_a_key_another_action_owns_is_swapped_and_the_footer_says_so() -> void:
	var menu := _controls()
	_start(menu, "Guard (tap: parry)")
	_send(menu, _m(MOUSE_BUTTON_LEFT))
	assert_eq(ControlsList.shown(&"guard", false), "LMB")
	assert_eq(ControlsList.shown(&"palm", false), "Q", "Palm gets Guard's old key")
	assert_eq(menu.footer(), "Swapped with Palm.")
	menu._process(2.9)
	assert_eq(menu.footer(), "Swapped with Palm.", "for 3 s")
	menu._process(0.2)
	assert_eq(menu.footer(), KEYBOARD_LEGEND)
	_start(menu, "Palm")
	_send(menu, _k(KEY_E))
	assert_eq(menu.footer(), "Swapped with gift.", "an action with no row is named by its action")
	assert_eq(ControlsList.shown(&"gift", false), "Q", "gift took the key palm left")


func test_an_action_left_without_a_binding_shows_not_bound_and_can_be_bound() -> void:
	var menu := _controls()
	assert_eq(_value(menu, "Target left"), "Not bound")
	_start(menu, "Target left")
	_send(menu, _k(KEY_Z))
	assert_eq(_value(menu, "Target left"), "Z", "it can be bound")
	assert_eq(ControlsList.shown(&"target_left", true), "R stick left", "its pad binding is untouched")
	# Take Z for another action that has a key: Target left is left without one, and says so.
	_start(menu, "Palm")
	_send(menu, _k(KEY_Z))
	assert_eq(_value(menu, "Target left"), "LMB", "it got Palm's old key in the swap")
	Bindings.apply({&"lock_on": [] as Array[InputEvent]})
	var bare := _controls()
	assert_eq(_value(bare, "Lock on"), "Not bound", "nothing bound shows Not bound")
	_start(bare, "Lock on")
	_send(bare, _k(KEY_V))
	assert_eq(_value(bare, "Lock on"), "V", "and it can be bound")


func test_the_press_that_starts_a_capture_is_not_captured() -> void:
	var menu := _controls()
	_select(menu, "Palm")
	_send(menu, _k(KEY_ENTER))
	assert_true(menu.capturing())
	_send(menu, _k(KEY_ENTER, true, true))
	_send(menu, _k(KEY_ENTER, true, true))
	_send(menu, _k(KEY_ENTER, false))
	assert_true(menu.capturing(), "neither its repeat nor its release is captured")
	assert_eq(_table(), _defaults())
	_send(menu, _k(KEY_F, true, true))
	assert_true(menu.capturing(), "a repeat is never a press")
	_send(menu, _k(KEY_F))
	assert_false(menu.capturing())
	assert_eq(ControlsList.shown(&"palm", false), "F")
	_send(menu, _k(KEY_F, false))
	var pad := _controls(true)
	_select(pad, "Palm")
	_send(pad, _b(JOY_BUTTON_A))
	_send(pad, _b(JOY_BUTTON_A, false))
	assert_true(pad.capturing(), "pad: A that chose it is not the binding, nor its release")
	assert_eq(_table().palm, [{"type": "button", "button": int(JOY_BUTTON_RIGHT_SHOULDER)}, {"type": "key", "code": int(KEY_F)}])


func test_the_press_that_ends_a_capture_is_not_also_a_menu_command() -> void:
	var menu := _controls()
	_start(menu, "Palm")
	var at := menu.index
	_send(menu, _k(KEY_ENTER))
	assert_eq(ControlsList.shown(&"palm", false), "Enter", "Enter is bound to Palm")
	assert_false(menu.capturing(), "and does not choose the row again")
	assert_eq(menu.index, at)
	_send(menu, _k(KEY_ENTER, false))
	_start(menu, "Move up")
	at = menu.index
	_send(menu, _k(KEY_DOWN))
	assert_eq(ControlsList.shown(&"move_up", false), "Down")
	assert_eq(menu.index, at, "binding Down does not move the selection")
	assert_false(menu.capturing())
	_send(menu, _k(KEY_DOWN, false))
	# Esc cancels and does not also go back.
	_start(menu, "Lock on")
	_send(menu, _k(KEY_ESCAPE))
	assert_eq(menu.page, MenuPages.CONTROLS, "Esc ended the capture and went no further")
	var pad := _controls(true)
	_start(pad, "Palm", true)
	_send(pad, _b(JOY_BUTTON_B))
	assert_eq(pad.page, MenuPages.CONTROLS, "B too")
	_start(pad, "Lock on", true)
	_send(pad, _b(JOY_BUTTON_DPAD_DOWN))
	assert_eq(ControlsList.shown(&"lock_on", true), "D-pad down")
	assert_eq(pad.rows().filter(func(r: Dictionary) -> bool: return r.selected).map(func(r: Dictionary) -> String: return r.label), ["Lock on"], "D-pad down bound, selection stays")


func test_two_keys_at_once_and_a_modifier() -> void:
	var menu := _controls()
	_start(menu, "Palm")
	var chord := _k(KEY_SHIFT)
	chord.shift_pressed = true
	_send(menu, chord)
	var then := _k(KEY_F)
	then.shift_pressed = true
	_send(menu, then)
	assert_false(menu.capturing())
	assert_eq(ControlsList.shown(&"palm", false), "Shift", "the first key that went down is the binding; a modifier is a key like any other")
	assert_eq(_saved(&"palm").slice(1), [_key_data(KEY_SHIFT)], "no chord is kept")
	assert_eq(ControlsList.shown(&"dodge", false), "LMB / Space", "dash-step's Shift went to Palm's old key in the swap")
	var again := _controls()
	_start(again, "Lock on")
	_send(again, _k(KEY_F))
	_send(again, _k(KEY_G))
	assert_eq(ControlsList.shown(&"lock_on", false), "F", "two keys on one frame: the first")


func test_the_games_own_keys_cannot_be_bound() -> void:
	var menu := _controls()
	for code in Main.OWN_KEYS:
		_start(menu, "Palm")
		_send(menu, _k(code))
		assert_true(menu.capturing(), "%s is the game's own: the capture goes on" % OS.get_keycode_string(code))
		assert_eq(menu.footer(), "That key is the game's own.")
		_send(menu, _k(KEY_ESCAPE))
	assert_eq(_table(), _defaults(), "nothing was bound")
	_start(menu, "Palm")
	_send(menu, _k(KEY_F10))
	assert_eq(ControlsList.shown(&"palm", false), "F10", "F10 is free")
	var alt_enter := _k(KEY_ENTER)
	alt_enter.alt_pressed = true
	_start(menu, "Lock on")
	_send(menu, alt_enter)
	assert_true(menu.capturing(), "Alt+Enter is the window's")
	assert_eq(menu.footer(), "That key is the game's own.")
	_send(menu, _k(KEY_ESCAPE))
	var pad := _controls(true)
	for button in Main.OWN_BUTTONS:
		_start(pad, "Palm", true)
		_send(pad, _b(button))
		assert_true(pad.capturing(), "the pad's Select is Main's")
		assert_eq(pad.footer(), "That key is the game's own.")
		_send(pad, _b(JOY_BUTTON_B))


func test_every_key_main_handles_is_refused() -> void:
	var handled := {}
	var regex := RegEx.create_from_string("KEY_F\\d+")
	for path in ["res://main/main.gd", "res://main/window_toggle.gd"]:
		for hit in regex.search_all(FileAccess.get_file_as_string(path)):
			handled[hit.get_string()] = true
	var owned := {}
	for code in Main.OWN_KEYS:
		owned["KEY_" + OS.get_keycode_string(code)] = true
	assert_eq(owned.keys().filter(func(k: String) -> bool: return not handled.has(k)), [], "every key in OWN_KEYS is one Main reads")
	assert_eq(handled.keys().filter(func(k: String) -> bool: return not owned.has(k)), [], "and Main reads no function key that is not in OWN_KEYS")
	var pad_handled := FileAccess.get_file_as_string("res://main/main.gd").contains("JOY_BUTTON_BACK")
	assert_true(pad_handled and Main.OWN_BUTTONS.has(JOY_BUTTON_BACK), "the pad's Select too")


# --- the menu button ---

func test_menu_rebound_still_opens_and_closes_the_menu() -> void:
	var main := await _main()
	Game.change(Game.State.PAUSE)
	var menu := main.menu
	menu.press(C.DOWN)
	menu.press(C.CHOOSE)
	assert_eq(menu.page, MenuPages.CONTROLS)
	_start_in_main(menu, "Menu / back")
	_window_key(KEY_F10)
	_window_key(KEY_F10, false)
	assert_eq(ControlsList.shown(&"menu", false), "F10")
	assert_false(menu.capturing())
	menu.press(C.BACK)
	menu.press(C.BACK)
	assert_eq(Game.state, Game.State.PLAY, "Back twice resumes")
	await frames(6)
	_window_key(KEY_ESCAPE)
	_window_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PLAY, "Esc no longer opens the menu")
	await frames(3)
	_window_key(KEY_F10)
	_window_key(KEY_F10, false)
	assert_eq(Game.state, Game.State.PAUSE, "F10 opens it")
	await frames(2)
	_window_key(KEY_ESCAPE)
	_window_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PLAY, "and Esc still backs out inside the menu (here, resumes)")
	await frames(6)
	_window_key(KEY_F10)
	_window_key(KEY_F10, false)
	assert_eq(Game.state, Game.State.PAUSE)
	await frames(2)
	_window_key(KEY_F10)
	_window_key(KEY_F10, false)
	assert_eq(Game.state, Game.State.PLAY, "F10 closes it")


func _start_in_main(menu: Menu, label: String) -> void:
	_select(menu, label)
	_window_key(KEY_ENTER)
	_window_key(KEY_ENTER, false)


func test_esc_and_start_always_go_back_whatever_menu_is_bound_to() -> void:
	var nav := MenuNav.new()
	Bindings.apply({&"menu": [_b(JOY_BUTTON_X), _k(KEY_F10)] as Array[InputEvent]})
	assert_eq(nav.command(_k(KEY_ESCAPE)), C.BACK)
	assert_eq(nav.command(_b(JOY_BUTTON_START)), C.BACK, "Start goes back though it is no longer the menu button")
	assert_eq(nav.command(_k(KEY_F10)), C.BACK)
	assert_eq(nav.command(_b(JOY_BUTTON_X)), C.BACK)
	Bindings.apply({&"menu": [] as Array[InputEvent]})
	assert_eq(nav.command(_k(KEY_ESCAPE)), C.BACK, "with nothing bound")
	assert_eq(nav.command(_b(JOY_BUTTON_START)), C.BACK)


func test_taking_the_last_key_of_the_menu_button_gives_it_back_its_default() -> void:
	var menu := _controls()
	_start(menu, "Menu / back")
	_send(menu, _k(KEY_F10))
	# Target left has no key: binding it to F10 takes the menu button's only key away.
	_start(menu, "Target left")
	_send(menu, _k(KEY_F10))
	assert_eq(ControlsList.shown(&"target_left", false), "F10")
	assert_eq(ControlsList.shown(&"menu", false), "Escape", "the menu button is back on Esc, so the menu can still be opened")
	assert_true(menu.footer().begins_with("Swapped with Menu / back."), menu.footer())
	assert_true(menu.footer().contains("Esc"), menu.footer())
	var pad := _controls(true)
	_start(pad, "Menu / back", true)
	_send(pad, _b(JOY_BUTTON_Y))
	assert_eq(ControlsList.shown(&"menu", true), "Y")
	Bindings.apply({&"lock_on": [_k(KEY_TAB)] as Array[InputEvent]})
	_start(pad, "Lock on", true)
	_send(pad, _b(JOY_BUTTON_Y))
	assert_eq(ControlsList.shown(&"lock_on", true), "Y")
	assert_eq(ControlsList.shown(&"menu", true), "Start", "and the pad's Start likewise")


# --- the rest of the page ---

func test_restore_default_controls_restores_and_saves() -> void:
	var menu := _controls()
	_start(menu, "Palm")
	_send(menu, _k(KEY_F))
	var pad := _controls(true)
	_start(pad, "Guard (tap: parry)", true)
	_send(pad, _b(JOY_BUTTON_Y))
	assert_ne(_table(), _defaults())
	_start(menu, "Restore default controls")
	assert_eq(_table(), _defaults(), "the table is the defaults again")
	assert_true(FileAccess.file_exists(FILE), "and the file is written")
	assert_true(Inputs.load_bindings(FILE), "it loads")
	assert_eq(_table(), _defaults(), "to the same table")
	assert_eq(menu.page, MenuPages.CONTROLS, "the page stays")
	assert_eq(_value(menu, "Palm"), "LMB")


func test_rebinding_never_changes_how_the_menu_is_moved() -> void:
	var menu := _controls()
	_start(menu, "Palm")
	_send(menu, _k(KEY_ENTER))
	_send(menu, _k(KEY_ENTER, false))
	_start(menu, "Move up")
	_send(menu, _k(KEY_DOWN))
	_send(menu, _k(KEY_DOWN, false))
	_select(menu, "Palm")
	var at := menu.index
	_tap(menu, _k(KEY_DOWN))
	assert_eq(menu.index, at + 1, "Down moves down")
	_tap(menu, _k(KEY_W))
	assert_eq(menu.index, at, "W moves up (Move up is bound to Down now)")
	_tap(menu, _k(KEY_ENTER))
	assert_true(menu.capturing(), "Enter chooses (Palm is bound to Enter now)")
	_tap(menu, _k(KEY_ESCAPE))
	_select(menu, "Back")
	_tap(menu, _k(KEY_ENTER))
	assert_eq(menu.page, MenuPages.ROOT, "and chooses Back")


func test_a_random_walk_of_two_hundred_captures_leaves_the_menu_reachable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var keys := [KEY_F, KEY_G, KEY_H, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_Q, KEY_E, KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_ENTER,
		KEY_SHIFT, KEY_TAB, KEY_F10, KEY_UP, KEY_DOWN, KEY_ESCAPE, KEY_F12, KEY_BACKSPACE]
	var pad_buttons := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]
	var axes := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
	var labels: Array = ControlsList.ACTION_ROWS.map(func(r: Array) -> String: return r[1])
	var menu := _controls()
	var pad := _controls(true)
	var problems := []
	for step in 200:
		var on_pad := rng.randi() % 2 == 0
		var m := pad if on_pad else menu
		Inputs._device = Inputs.Device.GAMEPAD if on_pad else Inputs.Device.KEYBOARD_MOUSE
		if m.page != MenuPages.CONTROLS:
			m.show_page(MenuPages.CONTROLS)
		_start(m, labels[rng.randi() % labels.size()], on_pad)
		if not m.capturing():
			problems.append("step %d: no capture began" % step)
			continue
		var event: InputEvent
		if on_pad:
			if rng.randi() % 3 == 0:
				event = _a(axes[rng.randi() % axes.size()], [-1.0, 1.0][rng.randi() % 2])
			else:
				event = _b(pad_buttons[rng.randi() % pad_buttons.size()])
		else:
			event = _k(keys[rng.randi() % keys.size()]) if rng.randi() % 4 != 0 else _m([MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE][rng.randi() % 3])
		_send(m, event)
		if m.capturing():
			_send(m, _k(KEY_ESCAPE))
		_send(m, _k(KEY_ESCAPE, false))
		for pad_kind in [false, true]:
			for row: Array in ControlsList.ACTION_ROWS:
				var text := ControlsList.shown(row[0], pad_kind)
				var events: Array = Bindings.current()[row[0]].filter(func(e: InputEvent) -> bool: return Bindings.is_gamepad(e) == pad_kind)
				if events.is_empty() != (text == "Not bound"):
					problems.append("step %d: %s says '%s' with %d events" % [step, row[0], text, events.size()])
			var menu_events: Array = Bindings.current()[&"menu"].filter(func(e: InputEvent) -> bool: return Bindings.is_gamepad(e) == pad_kind)
			if menu_events.is_empty():
				problems.append("step %d: the menu button has no %s binding" % [step, "pad" if pad_kind else "keyboard"])
		if problems.size() > 5:
			break
	assert_eq(problems, [], "a walk of 200 captures")
	var saved := _table()
	var fresh := Inputs.load_bindings(FILE)
	assert_true(fresh, "the saved file loads")
	assert_eq(_table(), saved, "to the same table")
	# The fixed menu keys still drive the menu.
	var driven := _menu()
	_tap(driven, _k(KEY_DOWN))
	assert_eq(driven.index, 1)
	_tap(driven, _k(KEY_UP))
	assert_eq(driven.index, 0)
	_tap(driven, _k(KEY_DOWN))
	_tap(driven, _k(KEY_ENTER))
	assert_eq(driven.page, MenuPages.CONTROLS, "Down and Enter open Controls")
	_start(driven, "Restore default controls")
	assert_eq(_table(), _defaults(), "Restore default controls gives back the defaults")
	Inputs.load_bindings(FILE)
	assert_eq(_table(), _defaults(), "and the file says so")


# --- width ---

func test_the_panel_never_changes_width_and_a_long_name_is_cut() -> void:
	# The engine's longest key names by width in the menu's font (found by scanning every key it names): "On-screen keyboard" is the widest.
	var widest: Array[Key] = [0x400071 as Key, 0x400056 as Key]
	assert_eq([OS.get_keycode_string(widest[0]), OS.get_keycode_string(widest[1])], ["On-screen keyboard", "MediaPrevious"])
	var menu := _controls(true)
	var width := menu.panel().size.x
	var widths := [width]
	for hand in [false, true, false]:
		_pad_in = hand
		Inputs._device = Inputs.Device.GAMEPAD if hand else Inputs.Device.KEYBOARD_MOUSE
		menu._process(0.016)
		widths.append(menu.panel().size.x)
	var two: Array[InputEvent] = [_k(widest[0]), _k(widest[1])]
	Bindings.apply({&"dodge": two, &"heavy": [_k(widest[0])] as Array[InputEvent], &"palm": [_k(KEY_F)] as Array[InputEvent]})
	_pad_in = false
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	menu._process(0.016)
	widths.append(menu.panel().size.x)
	assert_eq(widths.filter(func(w: int) -> bool: return w != width), [], "the panel's width: %s" % [widths])
	var map := menu.layout()
	var entry := {}
	for r in map.rows:
		if r.label == "Dash-step (hold: sprint)":
			entry = r
	assert_false(entry.is_empty())
	assert_true(str(entry.get("value", "")).ends_with("…"), "two long names are cut with an ellipsis: '%s'" % entry.get("value", ""))
	var text_at: Vector2i = entry.get("text_at", Vector2i.ZERO)
	var value_at: Vector2i = entry.get("value_at", Vector2i.ZERO)
	var label_end: int = text_at.x + _text_width(str(entry.get("label", "")))
	assert_true(value_at.x >= label_end + Menu.VALUE_GAP, "and the value stays clear of the label (%d vs %d)" % [value_at.x, label_end])
	assert_true(value_at.x + _text_width(str(entry.get("value", ""))) <= menu.panel().end.x - Menu.PADDING, "and inside the panel")
	var whole := _row(menu, "Heavy (hold: charge)")
	var whole_value: String = whole.get("value", "")
	assert_eq(whole_value, OS.get_keycode_string(widest[0]), "a single long name is whole (the column holds it): %s" % whole_value)
	assert_true(_text_width(whole_value) <= 96, "the column is at least 96 px")


func _text_width(text: String) -> int:
	return ceili(ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Menu.FONT_SIZE).x)


func test_the_capture_footer_fits_the_panel_and_nothing_moves() -> void:
	var menu := _controls()
	var panel := menu.panel()
	var rows_before := menu.rows().map(func(r: Dictionary) -> Rect2i: return r.rect)
	for pad in [false, true]:
		var m := _controls(pad)
		for row: Array in ControlsList.ACTION_ROWS:
			_start(m, row[1], pad)
			var map := m.layout()
			assert_eq(m.panel(), panel, "%s: the panel does not move or change size during a capture" % row[1])
			var lines: Array = map.get("footer_rows", [])
			assert_true(lines.size() >= 1 and lines.size() <= 2, "%s: the footer is up to two lines (%d)" % [row[1], lines.size()])
			for line: String in lines:
				assert_true(map.footer_at.x + _text_width(line) <= m.panel().end.x - Menu.PADDING - Menu.ARROW_ROOM + 1, "%s: '%s' fits the panel" % [row[1], line])
			assert_true(m.panel().end.y <= 190)
			_send(m, _k(KEY_ESCAPE) if not pad else _b(JOY_BUTTON_B))
	assert_eq(menu.rows().map(func(r: Dictionary) -> Rect2i: return r.rect), rows_before)


# --- in the fight ---

func test_a_rebound_button_works_in_the_fight() -> void:
	var main := await _main()
	var started := []
	main.player.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	Game.change(Game.State.PAUSE)
	var menu := main.menu
	menu.press(C.DOWN)
	menu.press(C.CHOOSE)
	_select(menu, "Palm")
	_window_key(KEY_ENTER)
	_window_key(KEY_ENTER, false)
	assert_true(menu.capturing())
	_window_key(KEY_F)
	_window_key(KEY_F, false)
	assert_eq(ControlsList.shown(&"palm", false), "F")
	assert_eq(_saved(&"palm").slice(1), [_key_data(KEY_F)], "kept in the file")
	menu.press(C.BACK)
	menu.press(C.BACK)
	assert_eq(Game.state, Game.State.PLAY)
	await frames(6)
	assert_eq(started, [], "nothing started by the capture")
	_window_key(KEY_F)
	await frames(3)
	_window_key(KEY_F, false)
	assert_eq(started.slice(0, 1), [&"palm_jab"], "F in play starts the jab: capture, InputMap and PlayerBrain")


func test_the_huds_list_follows_a_rebind_on_the_next_frame() -> void:
	var main := await _main()
	assert_true(main.hud.controls_text().contains("Palm (jab, cross, hook): LMB  |  RB"))
	Game.change(Game.State.PAUSE)
	main.menu.press(C.DOWN)
	main.menu.press(C.CHOOSE)
	_start(main.menu, "Palm")
	_send(main.menu, _k(KEY_F))
	await frames(1)
	assert_true(main.hud.controls_text().contains("Palm (jab, cross, hook): F  |  RB"), main.hud.controls_text())
	assert_true(main.hud.controls_text().contains("Move: W A S D  |  L stick"))
	_start(main.menu, "Restore default controls")
	await frames(1)
	assert_eq(main.hud.controls_text(), ControlsList.text())
	assert_true(main.hud.controls_text().contains("Palm (jab, cross, hook): LMB  |  RB"))


# A fight in progress is touched only by the bindings: pause it, rebind Palm with a capture, resume; a control that pauses and
# resumes without the menu is the same on every frame for a control that is never pressed.
func test_rebinding_in_a_pause_leaves_the_fight_as_a_control_that_never_opened_the_menu() -> void:
	var control: Array = await _fight_with_pause(false)
	var rebound: Array = await _fight_with_pause(true)
	assert_eq(rebound.size(), control.size())
	var differing := []
	for i in control.size():
		if rebound[i] != control[i]:
			differing.append([i, control[i], rebound[i]])
	assert_eq(differing.slice(0, 2), [], "every frame after the resume is the control's")
	assert_eq(_table().palm.size(), 2)


func _fight_with_pause(rebind: bool) -> Array:
	Bindings.apply(Bindings.defaults())
	Melee.slow(0, 1.0)
	var foe := (load("res://data/actors/knuckle_1.tres") as ActorDef).duplicate() as ActorDef
	foe.team = ActorDef.Team.ENEMY
	var run := Duel.make(self, [{"frames": 400}], [{"frames": 400}], 1.3, foe)
	(run["b"] as Actor).runner.start(Registry.fetch(&"moves", &"knuckle_hook") as MoveData)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await frames(6)
	_pause()
	var menu := track(Menu.new()) as Menu
	menu.open()
	await frames(3)
	if rebind:
		menu.press(C.DOWN)
		menu.press(C.CHOOSE)
		_start(menu, "Palm")
		_send(menu, _k(KEY_F))
		assert_eq(ControlsList.shown(&"palm", false), "F")
	await frames(50)
	Game.change(Game.State.PLAY)
	var frames_seen := []
	for i in 40:
		await frames(1)
		frames_seen.append([a.frame, a.global_position, a.stats.hp, a.stats.posture, b.frame, b.global_position, b.stats.hp, a.runner.time, b.runner.time])
	(run["arena"] as Node).free()
	menu.free()
	Melee.slow(0, 1.0)
	return frames_seen
