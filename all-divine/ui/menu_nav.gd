class_name MenuNav
extends RefCounted
## What the player's hands mean in a menu: an input event, or the time a direction has been held, turned into one command.
##
## The menu's own controls are fixed, not read from the InputMap, so that rebinding the game's actions can never lock the
## player out of the menu: Up/W, Down/S, Left/A, Right/D move and adjust; Enter, Space and KP Enter choose; Esc and Backspace
## go back; the pad's D-pad and left stick move and adjust, A chooses and B goes back. Whatever the `menu` action is bound to
## goes back too (it is the one button the game itself asks of the menu). The mouse does nothing.
##
## A key's echo and every release give NONE. The left stick gives one command when it is pushed past Bindings.FLICK_DEADZONE
## and none again until it falls below Bindings.DIRECTION_RELEASE. A held direction (key, D-pad or stick) repeats from tick():
## after REPEAT_DELAY, then every REPEAT_EVERY.

enum Cmd { NONE, UP, DOWN, LEFT, RIGHT, CHOOSE, BACK }

## Seconds a direction is held before it repeats, and between repeats after that.
const REPEAT_DELAY := 0.4
const REPEAT_EVERY := 0.1

const _KEYS := {
	KEY_UP: Cmd.UP, KEY_W: Cmd.UP,
	KEY_DOWN: Cmd.DOWN, KEY_S: Cmd.DOWN,
	KEY_LEFT: Cmd.LEFT, KEY_A: Cmd.LEFT,
	KEY_RIGHT: Cmd.RIGHT, KEY_D: Cmd.RIGHT,
	KEY_ENTER: Cmd.CHOOSE, KEY_KP_ENTER: Cmd.CHOOSE, KEY_SPACE: Cmd.CHOOSE,
	KEY_ESCAPE: Cmd.BACK, KEY_BACKSPACE: Cmd.BACK,
}
const _BUTTONS := {
	JOY_BUTTON_DPAD_UP: Cmd.UP,
	JOY_BUTTON_DPAD_DOWN: Cmd.DOWN,
	JOY_BUTTON_DPAD_LEFT: Cmd.LEFT,
	JOY_BUTTON_DPAD_RIGHT: Cmd.RIGHT,
	JOY_BUTTON_A: Cmd.CHOOSE,
	JOY_BUTTON_B: Cmd.BACK,
}
# The left stick's two axes, and the command a push in each direction gives: [axis, sign] -> Cmd.
const _STICK := {
	[JOY_AXIS_LEFT_X, -1]: Cmd.LEFT, [JOY_AXIS_LEFT_X, 1]: Cmd.RIGHT,
	[JOY_AXIS_LEFT_Y, -1]: Cmd.UP, [JOY_AXIS_LEFT_Y, 1]: Cmd.DOWN,
}

var _stick_latched: Dictionary = {}  # [axis, sign] -> true while that direction is pushed past its flick
var _held := Cmd.NONE  # the direction held now, which repeats
var _held_by := ""  # what holds it: a key, a button or a stick direction
var _held_for := 0.0
var _repeat_at := REPEAT_DELAY


## The command `event` is, or NONE.
func command(event: InputEvent) -> Cmd:
	var key := event as InputEventKey
	if key != null:
		var code: Key = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		if _KEYS.has(code):
			if not key.pressed:
				_let_go("key %d" % code)
				return Cmd.NONE
			if key.echo:
				return Cmd.NONE
			return _pressed(_KEYS[code], "key %d" % code)
	var button := event as InputEventJoypadButton
	if button != null and _BUTTONS.has(button.button_index):
		if not button.pressed:
			_let_go("button %d" % button.button_index)
			return Cmd.NONE
		return _pressed(_BUTTONS[button.button_index], "button %d" % button.button_index)
	var motion := event as InputEventJoypadMotion
	if motion != null and (motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y):
		return _stick(motion.axis, motion.axis_value)
	# The menu button, whatever it is bound to (a key that is also in the table above has meant that already).
	if event.is_action_pressed(&"menu"):
		return Cmd.BACK
	return Cmd.NONE


## Starts over as a menu opens: nothing is held, and every stick direction already pushed past its flick is latched, so a
## stick held when the menu opens moves nothing until it is let go and pushed again.
func begin() -> void:
	_held = Cmd.NONE
	_held_by = ""
	_stick_latched.clear()
	var devices: Array[int] = [0]
	for device in Input.get_connected_joypads():
		if not devices.has(device):
			devices.append(device)
	for direction: Array in _STICK:
		for device in devices:
			if Input.get_joy_axis(device, direction[0]) * direction[1] >= Bindings.FLICK_DEADZONE:
				_stick_latched[direction] = true


## The repeat of a held direction: call it every frame with the seconds since the last. Returns the direction again when it
## is due (REPEAT_DELAY after it went down, then every REPEAT_EVERY), else NONE.
func tick(delta: float) -> Cmd:
	if _held == Cmd.NONE:
		return Cmd.NONE
	_held_for += delta
	if _held_for < _repeat_at - 1e-6:
		return Cmd.NONE
	while _repeat_at <= _held_for + 1e-6:
		_repeat_at += REPEAT_EVERY
	return _held


# A press of `cmd` by `by`: a direction starts to be held (and repeats from tick), and is the command now.
func _pressed(cmd: Cmd, by: String) -> Cmd:
	if cmd in [Cmd.UP, Cmd.DOWN, Cmd.LEFT, Cmd.RIGHT]:
		_held = cmd
		_held_by = by
		_held_for = 0.0
		_repeat_at = REPEAT_DELAY
	return cmd


# What was holding a direction is let go of.
func _let_go(by: String) -> void:
	if _held_by == by:
		_held = Cmd.NONE
		_held_by = ""


# The left stick's axis moved to `value`: a direction goes down once past the flick, and is ready again below the release.
func _stick(axis: JoyAxis, value: float) -> Cmd:
	var result := Cmd.NONE
	for sign in [-1, 1]:
		var direction := [axis, sign]
		var strength: float = value * sign
		if _stick_latched.get(direction, false):
			if strength < Bindings.DIRECTION_RELEASE:
				_stick_latched[direction] = false
				_let_go("stick %d %d" % direction)
		elif strength >= Bindings.FLICK_DEADZONE:
			_stick_latched[direction] = true
			result = _pressed(_STICK[direction], "stick %d %d" % direction)
	return result
