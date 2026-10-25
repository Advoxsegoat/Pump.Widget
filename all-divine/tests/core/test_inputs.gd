extends TestCase

const FILE := "user://test_input.cfg"

func after_each() -> void:
	Bindings.apply(Bindings.defaults())
	for key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key_event(key, false)
	_stick(0, 0.0, 0.0)
	Input.action_release(&"palm")
	DirAccess.remove_absolute(FILE)
	await frames(1)

# --- helpers ---

func _key(physical_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	return event

func _key_event(physical_keycode: Key, pressed: bool) -> void:
	var event := _key(physical_keycode)
	event.keycode = physical_keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _stick(device: int, x: float, y: float) -> void:
	for pair in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
		var event := InputEventJoypadMotion.new()
		event.device = device
		event.axis = pair[0]
		event.axis_value = pair[1]
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _describe_all(action: StringName) -> Array:
	return InputMap.action_get_events(action).map(func(e): return Bindings.event_to_data(e))

func _same_map(a: Dictionary, b: Dictionary) -> bool:
	if a.keys() != b.keys():
		return false
	for action in a:
		var left: Array = a[action]
		var right: Array = b[action]
		if left.size() != right.size():
			return false
		for i in left.size():
			if not Bindings.same_event(left[i], right[i]):
				return false
	return true

func _write(text: String) -> void:
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	file.store_string(text)
	file.close()

# --- the stick ---

func test_stick_drift_below_deadzone_is_still() -> void:
	for v in [Vector2(0.1, 0), Vector2(0.12, -0.1), Vector2(0, 0.19), Vector2(-0.14, 0.14), Vector2.ZERO]:
		assert_eq(Inputs.shape_stick(v), Vector2.ZERO, str(v))

func test_stick_exactly_at_the_deadzone_is_still() -> void:
	assert_eq(Inputs.shape_stick(Vector2(Inputs.DEADZONE, 0)), Vector2.ZERO)

func test_stick_remaps_past_deadzone() -> void:
	assert_vec_near(Vector3(Inputs.shape_stick(Vector2(0.6, 0)).x, 0, 0), Vector3(0.5, 0, 0), 1e-4)
	assert_eq(Inputs.shape_stick(Vector2(1, 0)), Vector2(1, 0))

func test_stick_remap_is_radial_and_keeps_direction() -> void:
	var shaped := Inputs.shape_stick(Vector2(-0.3, 0.4))   # length 0.5 -> (0.5 - 0.2) / 0.8 = 0.375
	assert_near(shaped.length(), 0.375, 1e-5)
	assert_near(shaped.angle_to(Vector2(-0.3, 0.4)), 0.0, 1e-5)

func test_stick_is_clamped_to_one() -> void:
	assert_near(Inputs.shape_stick(Vector2(0.9, 0.9)).length(), 1.0, 1e-5)
	assert_near(Inputs.shape_stick(Vector2(5, 0)).length(), 1.0, 1e-5)

func test_stick_and_keys_combine_to_the_longer() -> void:
	assert_eq(Inputs.combine(Vector2(0.3, 0), Vector2(0, -1)), Vector2(0, -1))
	assert_eq(Inputs.combine(Vector2(0.9, 0), Vector2.ZERO), Vector2(0.9, 0))
	assert_eq(Inputs.combine(Vector2.ZERO, Vector2.ZERO), Vector2.ZERO)

func test_combined_keys_are_normalized() -> void:
	var v := Inputs.combine(Vector2(0.2, 0), Vector2(1, -1))
	assert_vec_near(Vector3(v.x, v.y, 0), Vector3(0.70710678, -0.70710678, 0), 1e-5)
	assert_near(v.length(), 1.0, 1e-5)

# --- move_vector reads the devices ---

func test_move_vector_is_still_with_nothing_pressed() -> void:
	assert_eq(Inputs.move_vector(), Vector2.ZERO)

func test_move_vector_up_is_negative_y_in_screen_space() -> void:
	_key_event(KEY_W, true)
	assert_eq(Inputs.move_vector(), Vector2(0, -1))
	_key_event(KEY_W, false)
	_key_event(KEY_S, true)
	assert_eq(Inputs.move_vector(), Vector2(0, 1))
	_key_event(KEY_S, false)
	_key_event(KEY_A, true)
	assert_eq(Inputs.move_vector(), Vector2(-1, 0))
	_key_event(KEY_A, false)
	_key_event(KEY_D, true)
	assert_eq(Inputs.move_vector(), Vector2(1, 0))

func test_move_vector_diagonal_keys_are_not_faster() -> void:
	_key_event(KEY_W, true)
	_key_event(KEY_D, true)
	var v := Inputs.move_vector()
	assert_near(v.length(), 1.0, 1e-5)
	assert_vec_near(Vector3(v.x, v.y, 0), Vector3(0.70710678, -0.70710678, 0), 1e-5)

func test_move_vector_opposite_keys_cancel() -> void:
	_key_event(KEY_A, true)
	_key_event(KEY_D, true)
	assert_eq(Inputs.move_vector(), Vector2.ZERO)

func test_move_vector_follows_rebound_keys() -> void:
	Inputs.rebind(&"move_up", _key(KEY_I))
	_key_event(KEY_W, true)
	assert_eq(Inputs.move_vector(), Vector2.ZERO, "W no longer moves")
	_key_event(KEY_I, true)
	assert_eq(Inputs.move_vector(), Vector2(0, -1))
	_key_event(KEY_I, false)

func test_move_vector_reads_a_stick_through_the_deadzone() -> void:
	_stick(0, 0.1, -0.1)
	assert_eq(Inputs.move_vector([0] as Array[int]), Vector2.ZERO, "drift is ignored")
	_stick(0, 0.6, 0.0)
	assert_vec_near(Vector3(Inputs.move_vector([0] as Array[int]).x, 0, 0), Vector3(0.5, 0, 0), 1e-4)
	_stick(0, 0.0, -1.0)
	assert_eq(Inputs.move_vector([0] as Array[int]), Vector2(0, -1), "stick up is negative y")

func test_move_vector_takes_the_key_over_a_weaker_stick() -> void:
	_stick(0, 0.5, 0.0)
	_key_event(KEY_A, true)
	assert_eq(Inputs.move_vector([0] as Array[int]), Vector2(-1, 0))

func test_move_vector_takes_the_stick_over_no_key() -> void:
	_stick(0, -1.0, 0.0)
	assert_eq(Inputs.move_vector([0] as Array[int]), Vector2(-1, 0))

func test_move_vector_uses_the_strongest_of_several_pads() -> void:
	_stick(0, 0.4, 0.0)
	_stick(1, 0.0, 1.0)
	assert_eq(Inputs.move_vector([0, 1] as Array[int]), Vector2(0, 1))
	_stick(1, 0.0, 0.0)

# --- buttons ---

func test_pressed_this_frame_reports_action_press() -> void:
	Input.action_press(&"palm")
	await frames(1)
	assert_true(Inputs.pressed_this_frame().has(&"palm"))
	await frames(1)
	assert_false(Inputs.pressed_this_frame().has(&"palm"), "only on the frame of the press")

func test_pressed_this_frame_ignores_movement_actions() -> void:
	Input.action_press(&"move_left")
	await frames(1)
	assert_false(Inputs.pressed_this_frame().has(&"move_left"))
	Input.action_release(&"move_left")

func test_held_follows_the_action() -> void:
	assert_false(Inputs.held(&"palm"))
	Input.action_press(&"palm")
	await frames(1)
	assert_true(Inputs.held(&"palm"))
	Input.action_release(&"palm")
	await frames(1)
	assert_false(Inputs.held(&"palm"))

func test_gameplay_actions_are_bound_actions_and_leave_out_movement() -> void:
	for action in Inputs.GAMEPLAY:
		assert_true(Bindings.ACTIONS.has(action), str(action))
		assert_false(str(action).begins_with("move_"), str(action))
	assert_eq(Inputs.GAMEPLAY.size(), Bindings.ACTIONS.size() - 4)

# --- rebinding ---

func test_rebind_conflict_swaps() -> void:
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	assert_eq(Inputs.rebind(&"palm", q), &"guard")
	assert_true(InputMap.action_get_events(&"guard").any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT))
	assert_false(InputMap.action_get_events(&"palm").any(func(e): return e is InputEventMouseButton), "palm let go of the mouse")
	assert_true(InputMap.action_get_events(&"palm").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_Q))
	assert_false(InputMap.action_get_events(&"guard").any(func(e): return e is InputEventKey), "guard lost Q")

func test_rebind_leaves_the_other_device_kind_alone() -> void:
	var before := _describe_all(&"palm").filter(func(d): return d.type == "button")
	Inputs.rebind(&"palm", _key(KEY_X))
	assert_eq(_describe_all(&"palm").filter(func(d): return d.type == "button"), before)
	assert_eq(InputMap.action_get_events(&"palm").size(), 2)

func test_rebind_without_a_conflict_returns_nothing() -> void:
	assert_eq(Inputs.rebind(&"palm", _key(KEY_X)), &"")
	assert_eq(_describe_all(&"palm").filter(func(d): return d.type == "key"), [{"type": "key", "code": int(KEY_X)}])
	assert_eq(_describe_all(&"guard"), Bindings.defaults()[&"guard"].map(Bindings.event_to_data), "no one else changed")

func test_rebind_to_what_the_action_already_has_changes_nothing() -> void:
	var before := Bindings.current()
	assert_eq(Inputs.rebind(&"guard", _key(KEY_Q)), &"")
	assert_true(_same_map(Bindings.current(), before))

func test_rebind_swaps_gamepad_buttons_too() -> void:
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	assert_eq(Inputs.rebind(&"dodge", y), &"interact")
	assert_eq(_describe_all(&"dodge").filter(func(d): return d.type == "button"), [{"type": "button", "button": int(JOY_BUTTON_Y)}])
	assert_eq(_describe_all(&"interact").filter(func(d): return d.type == "button"), [{"type": "button", "button": int(JOY_BUTTON_A)}])

func test_rebind_replaces_only_the_first_event_of_the_kind() -> void:
	Inputs.rebind(&"dodge", _key(KEY_X))
	assert_eq(_describe_all(&"dodge").filter(func(d): return d.type == "key"),
		[{"type": "key", "code": int(KEY_X)}, {"type": "key", "code": int(KEY_SPACE)}])

func test_rebind_swap_hands_over_the_first_event_of_the_kind() -> void:
	# item takes SPACE from dodge: dodge keeps SHIFT and receives item's R in SPACE's place.
	assert_eq(Inputs.rebind(&"item", _key(KEY_SPACE)), &"dodge")
	assert_eq(_describe_all(&"item").filter(func(d): return d.type == "key"), [{"type": "key", "code": int(KEY_SPACE)}])
	assert_eq(_describe_all(&"dodge").filter(func(d): return d.type == "key"),
		[{"type": "key", "code": int(KEY_SHIFT)}, {"type": "key", "code": int(KEY_R)}])

func test_rebind_adds_a_kind_the_action_had_none_of() -> void:
	# slot_next is wheel-only; it gains a gamepad button that no one owns.
	assert_eq(Inputs.rebind(&"slot_next", _button(JOY_BUTTON_BACK)), &"")
	assert_eq(_describe_all(&"slot_next").size(), 2)

func test_rebind_takes_from_the_owner_that_has_nothing_to_give_back() -> void:
	# slot_next has no gamepad event, so dodge simply loses A.
	assert_eq(Inputs.rebind(&"slot_next", _button(JOY_BUTTON_A)), &"dodge")
	assert_eq(_describe_all(&"dodge").filter(func(d): return d.type == "button"), [])
	assert_eq(_describe_all(&"slot_next").filter(func(d): return d.type == "button"), [{"type": "button", "button": int(JOY_BUTTON_A)}])

func test_rebind_stores_a_clean_event_for_every_device() -> void:
	var captured := InputEventKey.new()
	captured.physical_keycode = KEY_X
	captured.keycode = KEY_X
	captured.shift_pressed = true
	captured.pressed = true
	captured.device = 3
	Inputs.rebind(&"item", captured)
	var stored: InputEventKey = InputMap.action_get_events(&"item").filter(func(e): return e is InputEventKey)[0]
	assert_eq(stored.device, -1)
	assert_false(stored.shift_pressed)
	assert_false(stored.pressed)
	assert_true(stored != captured, "the InputMap does not share the caller's event")

func test_rebind_ignores_an_event_that_cannot_be_bound() -> void:
	var before := Bindings.current()
	assert_eq(quietly(func(): return Inputs.rebind(&"palm", InputEventKey.new())), &"")
	assert_eq(quietly(func(): return Inputs.rebind(&"palm", InputEventMouseMotion.new())), &"")
	assert_true(_same_map(Bindings.current(), before))

func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	return event

# --- saving and loading ---

func test_bindings_round_trip() -> void:
	Inputs.rebind(&"palm", _key(KEY_Q))
	Inputs.rebind(&"item", _key(KEY_X))
	Inputs.rebind(&"dodge", _button(JOY_BUTTON_Y))
	var saved := Bindings.current()
	assert_eq(Inputs.save_bindings(FILE), OK)
	Bindings.apply(Bindings.defaults())
	assert_false(_same_map(Bindings.current(), saved), "the defaults differ from what was saved")
	assert_true(Inputs.load_bindings(FILE))
	assert_true(_same_map(Bindings.current(), saved))

func test_a_saved_file_holds_every_action() -> void:
	assert_eq(Inputs.save_bindings(FILE), OK)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(FILE), OK)
	assert_eq(Array(cfg.get_section_keys("bindings")).map(func(k): return StringName(k)), Array(Bindings.ACTIONS))

func test_corrupt_file_falls_back_to_defaults() -> void:
	Inputs.rebind(&"palm", _key(KEY_X))
	_write("[bindings\npalm = = [{ this is not a config")
	assert_false(quietly(func(): return Inputs.load_bindings(FILE)))
	assert_true(_same_map(Bindings.current(), Bindings.defaults()), "the defaults are back")

func test_missing_file_falls_back_to_defaults() -> void:
	Inputs.rebind(&"palm", _key(KEY_X))
	assert_false(quietly(func(): return Inputs.load_bindings("user://no_such_input.cfg")))
	assert_true(_same_map(Bindings.current(), Bindings.defaults()))

func test_unknown_action_in_the_file_falls_back_to_defaults() -> void:
	Inputs.rebind(&"palm", _key(KEY_X))
	assert_eq(Inputs.save_bindings(FILE), OK)
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	cfg.set_value("bindings", "fly", [{"type": "key", "code": int(KEY_F)}])
	cfg.save(FILE)
	assert_false(quietly(func(): return Inputs.load_bindings(FILE)))
	assert_true(_same_map(Bindings.current(), Bindings.defaults()), "even palm's valid change is dropped")

func test_a_bad_event_in_the_file_falls_back_to_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "palm", [{"type": "key", "code": int(KEY_X)}, {"type": "bogus"}])
	cfg.save(FILE)
	assert_false(quietly(func(): return Inputs.load_bindings(FILE)))
	assert_true(_same_map(Bindings.current(), Bindings.defaults()))

func test_a_file_that_is_not_a_bindings_file_falls_back_to_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", 0.5)
	cfg.save(FILE)
	assert_false(quietly(func(): return Inputs.load_bindings(FILE)))
	assert_true(_same_map(Bindings.current(), Bindings.defaults()))

func test_actions_missing_from_the_file_keep_their_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "palm", [{"type": "key", "code": int(KEY_X)}])
	cfg.save(FILE)
	assert_true(Inputs.load_bindings(FILE))
	assert_eq(_describe_all(&"palm"), [{"type": "key", "code": int(KEY_X)}])
	assert_eq(_describe_all(&"guard"), Bindings.defaults()[&"guard"].map(Bindings.event_to_data))

func test_ready_applies_the_defaults_and_loads_the_saved_file() -> void:
	Inputs.rebind(&"palm", _key(KEY_X))
	assert_eq(Inputs.save_bindings(FILE), OK)
	Bindings.apply(Bindings.defaults())
	InputMap.action_erase_events(&"guard")
	var fresh: Node = (Inputs.get_script() as GDScript).new()
	fresh.bindings_path = FILE
	track(fresh)   # entering the tree runs _ready
	assert_eq(_describe_all(&"palm"), [{"type": "button", "button": int(JOY_BUTTON_RIGHT_SHOULDER)}, {"type": "key", "code": int(KEY_X)}], "the saved change is back")
	assert_eq(_describe_all(&"guard"), Bindings.defaults()[&"guard"].map(Bindings.event_to_data), "the rest is the table")

func test_ready_without_a_saved_file_applies_the_defaults_and_does_not_warn() -> void:
	Inputs.rebind(&"palm", _key(KEY_X))
	var fresh: Node = (Inputs.get_script() as GDScript).new()
	fresh.bindings_path = "user://no_such_input.cfg"
	track(fresh)
	assert_true(_same_map(Bindings.current(), Bindings.defaults()))
