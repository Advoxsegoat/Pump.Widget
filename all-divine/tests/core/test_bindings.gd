extends TestCase

func after_each() -> void:
	Bindings.apply(Bindings.defaults())

# The spec's table, written independently of Bindings: action -> {pad, kbm} as event descriptions.
func _table() -> Dictionary:
	return {
		&"move_left": {"pad": ["axis %d -" % JOY_AXIS_LEFT_X], "kbm": ["key %d" % KEY_A]},
		&"move_right": {"pad": ["axis %d +" % JOY_AXIS_LEFT_X], "kbm": ["key %d" % KEY_D]},
		&"move_up": {"pad": ["axis %d -" % JOY_AXIS_LEFT_Y], "kbm": ["key %d" % KEY_W]},
		&"move_down": {"pad": ["axis %d +" % JOY_AXIS_LEFT_Y], "kbm": ["key %d" % KEY_S]},
		&"palm": {"pad": ["button %d" % JOY_BUTTON_RIGHT_SHOULDER], "kbm": ["mouse %d" % MOUSE_BUTTON_LEFT]},
		&"heavy": {"pad": ["axis %d +" % JOY_AXIS_TRIGGER_RIGHT], "kbm": ["mouse %d" % MOUSE_BUTTON_RIGHT]},
		&"guard": {"pad": ["button %d" % JOY_BUTTON_LEFT_SHOULDER], "kbm": ["key %d" % KEY_Q]},
		&"gift": {"pad": ["axis %d +" % JOY_AXIS_TRIGGER_LEFT], "kbm": ["key %d" % KEY_E]},
		&"dodge": {"pad": ["button %d" % JOY_BUTTON_A], "kbm": ["key %d" % KEY_SHIFT, "key %d" % KEY_SPACE]},
		&"item": {"pad": ["button %d" % JOY_BUTTON_X], "kbm": ["key %d" % KEY_R]},
		&"interact": {"pad": ["button %d" % JOY_BUTTON_Y], "kbm": ["key %d" % KEY_F]},
		&"slot_up": {"pad": ["button %d" % JOY_BUTTON_DPAD_UP], "kbm": ["key %d" % KEY_1]},
		&"slot_right": {"pad": ["button %d" % JOY_BUTTON_DPAD_RIGHT], "kbm": ["key %d" % KEY_2]},
		&"slot_down": {"pad": ["button %d" % JOY_BUTTON_DPAD_DOWN], "kbm": ["key %d" % KEY_3]},
		&"slot_left": {"pad": ["button %d" % JOY_BUTTON_DPAD_LEFT], "kbm": ["key %d" % KEY_4]},
		&"slot_next": {"pad": [], "kbm": ["mouse %d" % MOUSE_BUTTON_WHEEL_DOWN]},
		&"slot_prev": {"pad": [], "kbm": ["mouse %d" % MOUSE_BUTTON_WHEEL_UP]},
		&"lock_on": {"pad": ["button %d" % JOY_BUTTON_RIGHT_STICK], "kbm": ["key %d" % KEY_TAB]},
		&"menu": {"pad": ["button %d" % JOY_BUTTON_START], "kbm": ["key %d" % KEY_ESCAPE]},
	}

# "key 4194325", "mouse 1", "button 10", "axis 0 -": what an event is, in a form that compares.
func _describe(e: InputEvent) -> String:
	if e is InputEventKey:
		return "key %d" % e.physical_keycode
	if e is InputEventMouseButton:
		return "mouse %d" % e.button_index
	if e is InputEventJoypadButton:
		return "button %d" % e.button_index
	if e is InputEventJoypadMotion:
		return "axis %d %s" % [e.axis, "-" if e.axis_value < 0.0 else "+"]
	return "?"

func _is_pad(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion

func _described(events: Array, pad: bool) -> Array:
	return events.filter(func(e): return _is_pad(e) == pad).map(_describe)

func test_actions_are_the_spec_list_in_order() -> void:
	assert_eq(Array(Bindings.ACTIONS), _table().keys())

func test_defaults_cover_exactly_the_actions() -> void:
	assert_eq(Bindings.defaults().keys(), Array(Bindings.ACTIONS))

func test_defaults_match_the_spec_table() -> void:
	var defaults := Bindings.defaults()
	var table := _table()
	for action in table:
		var events: Array = defaults[action]
		assert_eq(_described(events, true), table[action].pad, "%s on a gamepad" % action)
		assert_eq(_described(events, false), table[action].kbm, "%s on keyboard and mouse" % action)
		assert_eq(events.size(), table[action].pad.size() + table[action].kbm.size(), "%s has no other events" % action)

func test_palm_binds_rb_and_left_mouse() -> void:
	var ev: Array = Bindings.defaults()[&"palm"]
	assert_true(ev.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER))
	assert_true(ev.any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT))

func test_every_action_but_wheel_slots_has_pad_and_kbm() -> void:
	var defaults := Bindings.defaults()
	for action in Bindings.ACTIONS:
		var events: Array = defaults[action]
		var has_kbm := events.any(func(e): return not _is_pad(e))
		var has_pad := events.any(_is_pad)
		assert_true(has_kbm, "%s has keyboard or mouse" % action)
		if action == &"slot_next" or action == &"slot_prev":
			assert_false(has_pad, "%s is wheel-only" % action)
		else:
			assert_true(has_pad, "%s has a gamepad binding" % action)

func test_defaults_are_typed_input_events_made_for_every_device() -> void:
	for action in Bindings.ACTIONS:
		var events: Array = Bindings.defaults()[action]
		assert_true(events is Array[InputEvent], "%s is an Array[InputEvent]" % action)
		for e in events:
			assert_eq(e.device, -1, "%s: %s is for all devices" % [action, _describe(e)])

func test_defaults_returns_fresh_events_each_call() -> void:
	var a: InputEvent = Bindings.defaults()[&"palm"][0]
	var b: InputEvent = Bindings.defaults()[&"palm"][0]
	assert_true(a != b)

func test_apply_writes_the_input_map() -> void:
	Bindings.apply(Bindings.defaults())
	var table := _table()
	for action in table:
		assert_true(InputMap.has_action(action), str(action))
		var events := InputMap.action_get_events(action)
		assert_eq(_described(events, true), table[action].pad, "%s on a gamepad" % action)
		assert_eq(_described(events, false), table[action].kbm, "%s on keyboard and mouse" % action)

func test_apply_replaces_instead_of_accumulating() -> void:
	Bindings.apply(Bindings.defaults())
	Bindings.apply(Bindings.defaults())
	assert_eq(InputMap.action_get_events(&"dodge").size(), 3)
	var q := InputEventKey.new()
	q.physical_keycode = KEY_X
	Bindings.apply({&"palm": [q] as Array[InputEvent]})
	assert_eq(InputMap.action_get_events(&"palm").size(), 1)
	assert_eq(InputMap.action_get_events(&"guard").size(), 2, "actions left out of the map are untouched")

func test_applied_events_match_input_from_any_device() -> void:
	Bindings.apply(Bindings.defaults())
	for device in [0, 1, 16]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_Q
		key.shift_pressed = true
		key.pressed = true
		key.device = device
		assert_true(InputMap.event_is_action(key, &"guard"), "Q from device %d, with shift held" % device)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_A
		pad.pressed = true
		pad.device = device
		assert_true(InputMap.event_is_action(pad, &"dodge"), "A from device %d" % device)

func test_trigger_actions_use_a_deadzone_of_half() -> void:
	Bindings.apply(Bindings.defaults())
	assert_near(InputMap.action_get_deadzone(&"heavy"), 0.5, 1e-6)
	assert_near(InputMap.action_get_deadzone(&"gift"), 0.5, 1e-6)
	assert_near(InputMap.action_get_deadzone(&"palm"), 0.2, 1e-6)

func test_current_reads_back_what_apply_wrote() -> void:
	var q := InputEventKey.new()
	q.physical_keycode = KEY_X
	Bindings.apply({&"palm": [q] as Array[InputEvent]})
	var now := Bindings.current()
	assert_eq(now.keys(), Array(Bindings.ACTIONS))
	assert_eq(now[&"palm"].map(_describe), ["key %d" % KEY_X])

func test_event_data_round_trips_every_kind() -> void:
	for action in Bindings.ACTIONS:
		for e in Bindings.defaults()[action]:
			var back: InputEvent = Bindings.event_from_data(Bindings.event_to_data(e))
			assert_true(back != null, "%s: %s" % [action, _describe(e)])
			if back != null:
				assert_true(Bindings.same_event(e, back), "%s: %s" % [action, _describe(e)])
				assert_eq(back.device, e.device)

func test_event_from_data_refuses_junk() -> void:
	for junk in [null, 5, "key", [], {}, {"type": "bogus"}, {"type": "key"}, {"type": "key", "code": "A"}, {"type": "key", "code": 0},
			{"type": "key", "code": 65.0}, {"type": "mouse", "button": 0}, {"type": "button", "button": -1},
			{"type": "axis", "axis": 0}, {"type": "axis", "axis": 0, "dir": 0}, {"type": "axis", "axis": 0, "dir": 2},
			{"type": "axis", "axis": 0, "dir": 1.0}, {"type": "axis", "axis": -1, "dir": 1}]:
		assert_eq(Bindings.event_from_data(junk), null, str(junk))

func test_event_to_data_is_empty_for_events_that_cannot_be_bound() -> void:
	assert_eq(Bindings.event_to_data(InputEventKey.new()), {}, "a key with no key")
	assert_eq(Bindings.event_to_data(InputEventMouseMotion.new()), {})
	assert_eq(Bindings.event_to_data(InputEventJoypadMotion.new()), {}, "an axis at rest")

func test_same_event_compares_the_input_not_the_object() -> void:
	var a := InputEventKey.new()
	a.physical_keycode = KEY_Q
	var b := InputEventKey.new()
	b.physical_keycode = KEY_Q
	var c := InputEventKey.new()
	c.physical_keycode = KEY_E
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	assert_true(Bindings.same_event(a, b))
	assert_false(Bindings.same_event(a, c))
	assert_false(Bindings.same_event(a, mouse))
	var left := InputEventJoypadMotion.new()
	left.axis = JOY_AXIS_LEFT_X
	left.axis_value = -1.0
	var right := InputEventJoypadMotion.new()
	right.axis = JOY_AXIS_LEFT_X
	right.axis_value = 1.0
	assert_false(Bindings.same_event(left, right), "the two directions of one axis are two inputs")

func test_same_event_ignores_device_modifiers_and_strength() -> void:
	var bare := InputEventKey.new()
	bare.physical_keycode = KEY_SHIFT
	bare.device = -1
	var pressed := InputEventKey.new()
	pressed.physical_keycode = KEY_SHIFT
	pressed.shift_pressed = true
	pressed.pressed = true
	pressed.device = 0
	assert_true(Bindings.same_event(bare, pressed))
	var gentle := InputEventJoypadMotion.new()
	gentle.axis = JOY_AXIS_TRIGGER_LEFT
	gentle.axis_value = 0.3
	var full := InputEventJoypadMotion.new()
	full.axis = JOY_AXIS_TRIGGER_LEFT
	full.axis_value = 1.0
	assert_true(Bindings.same_event(gentle, full))
	assert_false(Bindings.same_event(InputEventKey.new(), InputEventKey.new()), "events that cannot be bound are never the same")
