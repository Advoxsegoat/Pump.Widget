class_name Bindings
extends RefCounted
## The input table: which events drive which action, on a gamepad and on keyboard and mouse.
##
## The table is data, applied to the InputMap with apply(). Keys are bound by physical position
## (the key in the same place on any layout). Events are made for every device, so they match
## whichever pad or keyboard the player uses.

## Every action the game defines, in the order of the spec's table.
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"palm", &"heavy", &"guard", &"gift", &"dodge", &"item", &"interact",
	&"slot_up", &"slot_right", &"slot_down", &"slot_left", &"slot_next", &"slot_prev",
	&"lock_on", &"menu",
]

## The actions driven by an analog trigger, which count as pressed past half way.
const TRIGGER_ACTIONS: Array[StringName] = [&"heavy", &"gift"]
const TRIGGER_DEADZONE := 0.5
## Every other action keeps the engine's default deadzone.
const ACTION_DEADZONE := 0.2
## The device id of an event that matches input from any device.
const ALL_DEVICES := -1


## Each action's default events, fresh on every call.
static func defaults() -> Dictionary:
	return {
		&"move_left": _list([_axis(JOY_AXIS_LEFT_X, -1), _key(KEY_A)]),
		&"move_right": _list([_axis(JOY_AXIS_LEFT_X, 1), _key(KEY_D)]),
		&"move_up": _list([_axis(JOY_AXIS_LEFT_Y, -1), _key(KEY_W)]),
		&"move_down": _list([_axis(JOY_AXIS_LEFT_Y, 1), _key(KEY_S)]),
		&"palm": _list([_button(JOY_BUTTON_RIGHT_SHOULDER), _mouse(MOUSE_BUTTON_LEFT)]),
		&"heavy": _list([_axis(JOY_AXIS_TRIGGER_RIGHT, 1), _mouse(MOUSE_BUTTON_RIGHT)]),
		&"guard": _list([_button(JOY_BUTTON_LEFT_SHOULDER), _key(KEY_Q)]),
		&"gift": _list([_axis(JOY_AXIS_TRIGGER_LEFT, 1), _key(KEY_E)]),
		&"dodge": _list([_button(JOY_BUTTON_A), _key(KEY_SHIFT), _key(KEY_SPACE)]),
		&"item": _list([_button(JOY_BUTTON_X), _key(KEY_R)]),
		&"interact": _list([_button(JOY_BUTTON_Y), _key(KEY_F)]),
		&"slot_up": _list([_button(JOY_BUTTON_DPAD_UP), _key(KEY_1)]),
		&"slot_right": _list([_button(JOY_BUTTON_DPAD_RIGHT), _key(KEY_2)]),
		&"slot_down": _list([_button(JOY_BUTTON_DPAD_DOWN), _key(KEY_3)]),
		&"slot_left": _list([_button(JOY_BUTTON_DPAD_LEFT), _key(KEY_4)]),
		&"slot_next": _list([_mouse(MOUSE_BUTTON_WHEEL_DOWN)]),
		&"slot_prev": _list([_mouse(MOUSE_BUTTON_WHEEL_UP)]),
		&"lock_on": _list([_button(JOY_BUTTON_RIGHT_STICK), _key(KEY_TAB)]),
		&"menu": _list([_button(JOY_BUTTON_START), _key(KEY_ESCAPE)]),
	}


## Writes `map` (action -> Array[InputEvent]) to the InputMap, creating each action if needed and
## replacing its events. Actions that `map` leaves out are untouched.
static func apply(map: Dictionary) -> void:
	for action: StringName in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_set_deadzone(action, TRIGGER_DEADZONE if TRIGGER_ACTIONS.has(action) else ACTION_DEADZONE)
		InputMap.action_erase_events(action)
		for event: InputEvent in map[action]:
			InputMap.action_add_event(action, event)


## What the InputMap holds now for every action: a copy, in the shape defaults() returns.
static func current() -> Dictionary:
	var map := {}
	for action in ACTIONS:
		var events: Array[InputEvent] = []
		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action):
				events.append(event.duplicate())
		map[action] = events
	return map


## True for a gamepad event, false for a keyboard or mouse one.
static func is_gamepad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## The event as plain data, for the bindings file. Only the input itself is kept (no modifiers, no
## device, no strength), so two events that mean the same input give equal data. An event of a
## kind that cannot be bound gives an empty Dictionary.
static func event_to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.physical_keycode != KEY_NONE:
		return {"type": "key", "code": int(event.physical_keycode)}
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_NONE:
		return {"type": "mouse", "button": int(event.button_index)}
	if event is InputEventJoypadButton and event.button_index != JOY_BUTTON_INVALID:
		return {"type": "button", "button": int(event.button_index)}
	if event is InputEventJoypadMotion and event.axis != JOY_AXIS_INVALID and event.axis_value != 0.0:
		return {"type": "axis", "axis": int(event.axis), "dir": 1 if event.axis_value > 0.0 else -1}
	return {}


## The event that event_to_data() described, made for every device, or null if `data` is not
## something event_to_data() could have written.
static func event_from_data(data: Variant) -> InputEvent:
	if not data is Dictionary:
		return null
	match data.get("type"):
		"key":
			if _is_int(data.get("code"), 1):
				return _key(data.code)
		"mouse":
			if _is_int(data.get("button"), 1):
				return _mouse(data.button)
		"button":
			if _is_int(data.get("button"), 0):
				return _button(data.button)
		"axis":
			var direction: Variant = data.get("dir")
			if _is_int(data.get("axis"), 0) and typeof(direction) == TYPE_INT and (direction == 1 or direction == -1):
				return _axis(data.axis, direction)
	return null


## True if both events are the same input, whatever their device, modifiers or strength.
static func same_event(a: InputEvent, b: InputEvent) -> bool:
	var data := event_to_data(a)
	return not data.is_empty() and data == event_to_data(b)


static func _is_int(value: Variant, minimum: int) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum


static func _list(events: Array[InputEvent]) -> Array[InputEvent]:
	return events


static func _key(physical_keycode: int) -> InputEvent:
	var event := InputEventKey.new()
	event.device = ALL_DEVICES
	event.physical_keycode = physical_keycode as Key
	return event


static func _mouse(button: int) -> InputEvent:
	var event := InputEventMouseButton.new()
	event.device = ALL_DEVICES
	event.button_index = button as MouseButton
	return event


static func _button(button: int) -> InputEvent:
	var event := InputEventJoypadButton.new()
	event.device = ALL_DEVICES
	event.button_index = button as JoyButton
	return event


static func _axis(axis: int, direction: int) -> InputEvent:
	var event := InputEventJoypadMotion.new()
	event.device = ALL_DEVICES
	event.axis = axis as JoyAxis
	event.axis_value = float(direction)
	return event
