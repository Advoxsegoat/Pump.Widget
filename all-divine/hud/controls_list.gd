class_name ControlsList
extends RefCounted
## The controls list the Hud shows at the start (and when F1 asks): a line for each thing the player does, with the keys and
## mouse buttons and then the pad's buttons that are bound to it now, read from the live InputMap (Bindings.current) so that it
## matches what is bound, and what each event is called on the screen.

## The rows of the controls list: what it is for, and the actions whose bindings it names.
const ROWS := [
	["Move", [&"move_up", &"move_left", &"move_down", &"move_right"]],
	["Palm (jab, cross, hook)", [&"palm"]],
	["Heavy (hold to charge)", [&"heavy"]],
	["Guard (tap to parry)", [&"guard"]],
	["Sway / duck: hold guard + a direction", [&"guard"]],
	["Dash-step (hop if still)", [&"dodge"]],
	["Lock on", [&"lock_on"]],
	["Pause", [&"menu"]],
]
const FINISHER_NOTE := "Palm on a broken foe: Open Hand"
const JOY_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide",
}
const JOY_AXES := {
	JOY_AXIS_LEFT_X: "L stick", JOY_AXIS_LEFT_Y: "L stick", JOY_AXIS_RIGHT_X: "R stick", JOY_AXIS_RIGHT_Y: "R stick",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}
## The controls screen's rows, in order: the action and the words for it (the Controls page of the pause menu).
const ACTION_ROWS := [
	[&"move_up", "Move up"], [&"move_left", "Move left"], [&"move_down", "Move down"], [&"move_right", "Move right"],
	[&"palm", "Palm"], [&"heavy", "Heavy (hold: charge)"], [&"guard", "Guard (tap: parry)"], [&"dodge", "Dash-step (hold: sprint)"],
	[&"lock_on", "Lock on"], [&"target_left", "Target left"], [&"target_right", "Target right"], [&"menu", "Menu / back"],
]
## What the controls screen says for an action with no event on the device shown.
const NOT_BOUND := "Not bound"
const MOUSE_BUTTONS := {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB"}

## The list, one line a row: keyboard and mouse, then the pad, from the bindings in force now.
static func text() -> String:
	var map := Bindings.current()
	var lines := PackedStringArray(["Controls (F1 hides)"])
	for row: Array in ROWS:
		var keys: Array[String] = []
		var pad: Array[String] = []
		for action: StringName in row[1]:
			for event: InputEvent in map.get(action, []):
				var shown := event_name(event)
				var into := pad if Bindings.is_gamepad(event) else keys
				if not shown.is_empty() and not into.has(shown):
					into.append(shown)
		lines.append("%s: %s  |  %s" % [row[0], " ".join(keys), " ".join(pad)])
	lines.append(FINISHER_NOTE)
	return "\n".join(lines)


## What an event is called on the screen: a key's letter, a mouse button, a pad button, stick or trigger.
static func event_name(event: InputEvent) -> String:
	if event is InputEventKey:
		return OS.get_keycode_string((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		var button := (event as InputEventMouseButton).button_index
		return MOUSE_BUTTONS.get(button, "Wheel")
	if event is InputEventJoypadButton:
		return JOY_BUTTONS.get((event as InputEventJoypadButton).button_index, "Pad")
	if event is InputEventJoypadMotion:
		return JOY_AXES.get((event as InputEventJoypadMotion).axis, "Pad")
	return ""




## What the controls screen says for `action` on a device kind: the events of that kind, by long_name, joined with " / ", or "Not bound".
static func shown(action: StringName, gamepad: bool) -> String:
	var names: Array[String] = []
	if InputMap.has_action(action):
		for event: InputEvent in InputMap.action_get_events(action):
			var name := long_name(event)
			if Bindings.is_gamepad(event) == gamepad and not name.is_empty() and not names.has(name):
				names.append(name)
	return " / ".join(names) if not names.is_empty() else NOT_BOUND


## What an event is called on the controls screen: as event_name, but a stick says its direction and a wheel which way.
static func long_name(event: InputEvent) -> String:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var stick: String = JOY_AXES.get(motion.axis, "Pad")
		if stick.ends_with("stick"):
			var horizontal := motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_RIGHT_X
			var way := ("right" if motion.axis_value > 0.0 else "left") if horizontal else ("down" if motion.axis_value > 0.0 else "up")
			return "%s %s" % [stick, way]
		return stick
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel down"
			MOUSE_BUTTON_WHEEL_LEFT:
				return "Wheel left"
			MOUSE_BUTTON_WHEEL_RIGHT:
				return "Wheel right"
	return event_name(event)
