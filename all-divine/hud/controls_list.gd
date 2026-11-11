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
}
const JOY_AXES := {
	JOY_AXIS_LEFT_X: "L stick", JOY_AXIS_LEFT_Y: "L stick", JOY_AXIS_RIGHT_X: "R stick", JOY_AXIS_RIGHT_Y: "R stick",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}
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


