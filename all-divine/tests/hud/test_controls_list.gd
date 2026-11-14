extends TestCase
## The controls list names the sway, the duck and the dash-step, read from the bindings in force.


func test_the_list_names_guard_sway_duck_and_dash_step_and_not_the_roll() -> void:
	var text := ControlsList.text()
	assert_true(text.contains("Guard (tap to parry)"), text)
	assert_true(text.contains("Sway / duck: hold guard + a direction"), text)
	assert_true(text.contains("Dash-step (hop if still)"), text)
	assert_false(text.to_lower().contains("roll"), "the roll is gone: " + text)


func test_the_sway_row_shows_the_guard_keys() -> void:
	var line := ""
	for row in ControlsList.text().split("\n"):
		if row.begins_with("Sway / duck"):
			line = row
	assert_true(line.contains("Q") and line.contains("LB"), "hold guard (Q, LB): " + line)


# What text() said before the controls screen's additions, with the default bindings.
const BEFORE := "Controls (F1 hides)\nMove: W A S D  |  L stick\nPalm (jab, cross, hook): LMB  |  RB\nHeavy (hold to charge): RMB  |  RT\nGuard (tap to parry): Q  |  LB\nSway / duck: hold guard + a direction: Q  |  LB\nDash-step (hop if still): Shift Space  |  A\nLock on: Tab  |  R3\nPause: Escape  |  Start\nPalm on a broken foe: Open Hand"


func before_each() -> void:
	Bindings.apply(Bindings.defaults())


func after_each() -> void:
	Bindings.apply(Bindings.defaults())


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	return event


func test_text_is_unchanged_by_the_additions() -> void:
	assert_eq(ControlsList.text(), BEFORE)


func test_action_rows_are_the_twelve_in_order() -> void:
	assert_eq(ControlsList.ACTION_ROWS, [
		[&"move_up", "Move up"], [&"move_left", "Move left"], [&"move_down", "Move down"], [&"move_right", "Move right"],
		[&"palm", "Palm"], [&"heavy", "Heavy (hold: charge)"], [&"guard", "Guard (tap: parry)"], [&"dodge", "Dash-step (hold: sprint)"],
		[&"lock_on", "Lock on"], [&"target_left", "Target left"], [&"target_right", "Target right"], [&"menu", "Menu / back"],
	])
	for row: Array in ControlsList.ACTION_ROWS:
		assert_true(Bindings.ACTIONS.has(row[0]), "%s is an action" % row[0])


func test_dpad_and_back_buttons_have_names() -> void:
	for case: Array in [[JOY_BUTTON_DPAD_UP, "D-pad up"], [JOY_BUTTON_DPAD_DOWN, "D-pad down"], [JOY_BUTTON_DPAD_LEFT, "D-pad left"],
			[JOY_BUTTON_DPAD_RIGHT, "D-pad right"], [JOY_BUTTON_BACK, "Back"], [JOY_BUTTON_GUIDE, "Guide"]]:
		assert_eq(ControlsList.event_name(_pad(case[0])), case[1], "the HUD's name")
		assert_eq(ControlsList.long_name(_pad(case[0])), case[1], "the controls screen's name")
	assert_eq(ControlsList.event_name(_pad(JOY_BUTTON_MISC1)), "Pad", "a button it does not know is still just Pad")
	assert_eq(ControlsList.long_name(_pad(JOY_BUTTON_MISC1)), "Pad")
	assert_eq(ControlsList.long_name(_pad(JOY_BUTTON_A)), "A")
	assert_eq(ControlsList.long_name(_pad(JOY_BUTTON_START)), "Start")


func test_sticks_say_their_direction() -> void:
	for case: Array in [[JOY_AXIS_LEFT_X, -1.0, "L stick left"], [JOY_AXIS_LEFT_X, 1.0, "L stick right"], [JOY_AXIS_LEFT_Y, -1.0, "L stick up"],
			[JOY_AXIS_LEFT_Y, 1.0, "L stick down"], [JOY_AXIS_RIGHT_X, -1.0, "R stick left"], [JOY_AXIS_RIGHT_X, 1.0, "R stick right"],
			[JOY_AXIS_RIGHT_Y, -1.0, "R stick up"], [JOY_AXIS_RIGHT_Y, 1.0, "R stick down"], [JOY_AXIS_TRIGGER_LEFT, 1.0, "LT"],
			[JOY_AXIS_TRIGGER_RIGHT, 1.0, "RT"]]:
		assert_eq(ControlsList.long_name(_axis(case[0], case[1])), case[2])
	assert_eq(ControlsList.event_name(_axis(JOY_AXIS_LEFT_X, -1.0)), "L stick", "the HUD's list still says only the stick")


func test_keys_buttons_and_the_wheel_are_named() -> void:
	assert_eq(ControlsList.long_name(_key(KEY_F)), "F")
	assert_eq(ControlsList.long_name(_key(KEY_ESCAPE)), "Escape")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	assert_eq(ControlsList.long_name(mouse), "LMB")
	mouse.button_index = MOUSE_BUTTON_WHEEL_UP
	assert_eq(ControlsList.long_name(mouse), "Wheel up")
	mouse.button_index = MOUSE_BUTTON_WHEEL_DOWN
	assert_eq(ControlsList.long_name(mouse), "Wheel down")


func test_shown_joins_a_devices_events_and_says_not_bound_for_none() -> void:
	assert_eq(ControlsList.shown(&"dodge", false), "Shift / Space")
	assert_eq(ControlsList.shown(&"dodge", true), "A")
	assert_eq(ControlsList.shown(&"palm", false), "LMB")
	assert_eq(ControlsList.shown(&"palm", true), "RB")
	assert_eq(ControlsList.shown(&"move_up", true), "L stick up")
	assert_eq(ControlsList.shown(&"heavy", true), "RT")
	assert_eq(ControlsList.shown(&"target_left", false), "Not bound", "no key for it by default")
	assert_eq(ControlsList.shown(&"target_left", true), "R stick left")
	Bindings.apply({&"palm": [] as Array[InputEvent]})
	assert_eq(ControlsList.shown(&"palm", false), "Not bound")
	assert_eq(ControlsList.shown(&"palm", true), "Not bound")
	assert_eq(ControlsList.shown(&"no_such_action", false), "Not bound", "an action the map lacks")
