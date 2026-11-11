extends Node
## What the player is doing with the controls, and the rebinding of them.
##
## Autoload "Inputs". The actions and their default events are in Bindings; this reads them
## (the movement stick with a deadzone, the buttons as actions), swaps them when the player
## rebinds one, and saves and loads the player's table. It also keeps which kind of device the player used last
## (last_device), since what the game asks of the player's aim depends on it: a pad aims with the stick, and the
## keyboard and mouse aim at the cursor.
##
## A pad player who bumps the mouse must not find Abarax turned to the cursor, so the mouse alone takes the aim
## from a pad only by a sweep: MOUSE_SWEEP_PX of motion within MOUSE_SWEEP_SECONDS. A key or mouse button pressed
## takes it at once, and any pad input takes it back (and forgets the mouse motion so far).

## Below this much stick deflection the stick is at rest. Past it, the deflection is rescaled to
## run from 0 at the edge of the deadzone to 1 at full. The deadzone is round (on the stick's length),
## and 0.28 holds a worn pad that rests up to 0.19 off centre on both axes at once (0.269 long).
const DEADZONE := 0.28
## Where the player's bindings are kept.
const BINDINGS_PATH := "user://input.cfg"
## The actions that are pressed and let go, as opposed to movement, which is read as a vector.
const GAMEPLAY: Array[StringName] = [
	&"palm", &"heavy", &"guard", &"gift", &"dodge", &"item", &"interact", &"lock_on",
	&"target_left", &"target_right", &"slot_up", &"slot_right", &"slot_down", &"slot_left", &"slot_next", &"slot_prev", &"menu",
]

## How far the mouse must move, added up, to count as a hand on it rather than a bump...
const MOUSE_SWEEP_PX := 8.0
## ... and within how long (the sum starts again after a pause this long).
const MOUSE_SWEEP_SECONDS := 0.25

const _SECTION := "bindings"

## The kinds of device the player aims with.
enum Device { GAMEPAD, KEYBOARD_MOUSE }

## The file _ready loads. Only a test changes it.
var bindings_path := BINDINGS_PATH

## Seconds, for timing a mouse sweep. Only a test changes it.
var clock: Callable = wall_clock

var _device := Device.KEYBOARD_MOUSE
var _latched: Dictionary = {}  # flick action -> true while it is down
var _flicks_frame := -1
var _flicks: Array[StringName] = []
var _keys_latched: Dictionary = {}  # move action -> true while its key is down
var _stick_latched := false  # true while the left stick is past its flick
var _direction_frame := -1
var _direction := Vector2.ZERO
var _sweep_px := 0.0
var _sweep_began := 0.0


func _ready() -> void:
	Bindings.apply(Bindings.defaults())
	# A player who never rebound anything has no file, and that is not worth a warning.
	if FileAccess.file_exists(bindings_path):
		load_bindings(bindings_path)
	if not Input.get_connected_joypads().is_empty():
		_device = Device.GAMEPAD


func _init() -> void:
	# The direction latch is kept fresh every physics frame, paused or not, whether or not a brain asks: a key or stick that
	# went down while the player could not think (a grab, a finisher, death, a pause) is latched by the time he can, so
	# it is not a press then.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	direction_pressed_this_frame()


# The last device is that of the last event that is a press, or a move past the deadzone. An event that lets go
# of something, or a stick that rests (or drifts inside the deadzone), is not the player's hand.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var pushed: bool = event.pressed if event is InputEventJoypadButton else absf(event.axis_value) > DEADZONE
		if pushed:
			_device = Device.GAMEPAD
			_sweep_px = 0.0
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.pressed:
			_device = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion:
		_mouse_moved(event.relative.length())


## The seconds since the game began, by the wall clock.
static func wall_clock() -> float:
	return Time.get_ticks_msec() / 1000.0


# Adds `px` of mouse motion to the sweep going on, which starts over when it is older than MOUSE_SWEEP_SECONDS. Once
# the sum is MOUSE_SWEEP_PX the mouse is in hand.
func _mouse_moved(px: float) -> void:
	if px <= 0.0 or _device == Device.KEYBOARD_MOUSE:
		return
	var now: float = clock.call()
	if _sweep_px <= 0.0 or now - _sweep_began > MOUSE_SWEEP_SECONDS:
		_sweep_px = 0.0
		_sweep_began = now
	_sweep_px += px
	if _sweep_px >= MOUSE_SWEEP_PX:
		_device = Device.KEYBOARD_MOUSE
		_sweep_px = 0.0


## Which kind of device the player used last (Device): the keyboard and mouse until a pad is touched, or from the
## start if a pad is connected.
func last_device() -> int:
	return _device


## A stick reading with the deadzone taken out: 0 below DEADZONE, then (length - DEADZONE) / (1 - DEADZONE),
## up to 1, in the direction of `raw`.
static func shape_stick(raw: Vector2) -> Vector2:
	var length := raw.length()
	# A Vector2 holds 32-bit floats, so a stick at exactly 0.28 is a hair above the 64-bit 0.28.
	if length <= DEADZONE or is_equal_approx(length, DEADZONE):
		return Vector2.ZERO
	return raw / length * minf((length - DEADZONE) / (1.0 - DEADZONE), 1.0)


## Whichever of the two is longer. `keys` counts as a unit vector in its direction, so
## moving diagonally on the keyboard is no faster than moving straight.
static func combine(stick: Vector2, keys: Vector2) -> Vector2:
	var unit := keys.normalized()
	return unit if unit.length_squared() > stick.length_squared() else stick


## The movement the player is asking for, in screen space (right is +x, up is -y), at most length 1.
## It reads what move_left, move_right, move_up and move_down are bound to, so any of them can be
## rebound to a key, a mouse button, a gamepad button or a gamepad axis. Bound axes make the analog
## part: how far each is pushed in its bound direction gives x and y, which the radial deadzone
## shapes (see shape_stick). Bound buttons and keys make the digital part, a unit vector.
## The longer of the two wins (see combine).
## `devices` are the gamepads that count (the strongest analog push wins); by default, every one connected.
func move_vector(devices: Array[int] = Input.get_connected_joypads()) -> Vector2:
	var analog := Vector2.ZERO
	for device in devices:
		var raw := Vector2(
				_pushed(&"move_right", device) - _pushed(&"move_left", device),
				_pushed(&"move_down", device) - _pushed(&"move_up", device))
		var shaped := shape_stick(raw)
		if shaped.length_squared() > analog.length_squared():
			analog = shaped
	var digital := Vector2(
			_down(&"move_right", devices) - _down(&"move_left", devices),
			_down(&"move_down", devices) - _down(&"move_up", devices))
	return combine(analog, digital)


## The gameplay actions that went down this frame. A flick action (Bindings.FLICK_RELEASE) goes down past its deadzone
## and stays down until its strength falls below its release, so a stick dwelling at the threshold presses once.
func pressed_this_frame() -> Array[StringName]:
	var pressed: Array[StringName] = []
	var flicks := _flicks_this_frame()
	for action in GAMEPLAY:
		if Bindings.FLICK_RELEASE.has(action):
			if flicks.has(action):
				pressed.append(action)
		elif Input.is_action_just_pressed(action):
			pressed.append(action)
	return pressed


## The screen direction (x right, y down, length 1) of a move key that went down this physics frame, or of the left stick
## flicked past Bindings.FLICK_DEADZONE (it is down again only after it falls below Bindings.DIRECTION_RELEASE), or
## Vector2.ZERO if none did. A direction that was already down gives nothing: that is what makes a sway a press and
## not a hold. Two keys that go down on one frame make their diagonal; opposite ones cancel. The stick wins over the keys
## when both press. `devices` are the gamepads read, as for move_vector(). Worked out once a physics frame, however often
## it is asked, so call it every frame (a brain does).
func direction_pressed_this_frame(devices: Array[int] = Input.get_connected_joypads()) -> Vector2:
	var frame := Engine.get_physics_frames()
	if frame == _direction_frame:
		return _direction
	_direction_frame = frame
	var keys := Vector2.ZERO
	for action: StringName in Bindings.MOVE_DIRECTIONS:
		var down := _down(action, devices) == 1
		if down and not _keys_latched.get(action, false):
			keys += Bindings.MOVE_DIRECTIONS[action]
		_keys_latched[action] = down
	var stick := _flicked_stick(devices)
	if stick != Vector2.ZERO:
		_direction = stick
	else:
		_direction = keys.normalized()
	return _direction


# The direction the left stick was flicked in this frame, or zero. The stick is read raw (no deadzone taken out), as a
# whole and not axis by axis, so that a flick on the diagonal is one press, not one for each axis it passes the
# threshold on.
func _flicked_stick(devices: Array[int]) -> Vector2:
	var raw := Vector2.ZERO
	for device in devices:
		var reading := Vector2(
				_pushed(&"move_right", device) - _pushed(&"move_left", device),
				_pushed(&"move_down", device) - _pushed(&"move_up", device))
		if reading.length_squared() > raw.length_squared():
			raw = reading
	var strength := raw.length()
	if _stick_latched:
		if strength < Bindings.DIRECTION_RELEASE:
			_stick_latched = false
		return Vector2.ZERO
	if strength >= Bindings.FLICK_DEADZONE:
		_stick_latched = true
		return raw / strength
	return Vector2.ZERO


# The flick actions that went down this physics frame (worked out once a frame, however often it is asked).
func _flicks_this_frame() -> Array[StringName]:
	var frame := Engine.get_physics_frames()
	if frame == _flicks_frame:
		return _flicks
	_flicks_frame = frame
	_flicks = []
	for action: StringName in Bindings.FLICK_RELEASE:
		var strength := Input.get_action_raw_strength(action)
		if _latched.get(action, false):
			if strength < Bindings.FLICK_RELEASE[action]:
				_latched[action] = false
		elif strength >= InputMap.action_get_deadzone(action) and strength > 0.0:
			_latched[action] = true
			_flicks.append(action)
	return _flicks


## True while the action is down.
func held(action: StringName) -> bool:
	return Input.is_action_pressed(action)


## Binds `event` to `action`, in place of the action's first event of the same kind (gamepad, or
## keyboard and mouse), or as an added one if it has none of that kind. If another action owns an equal
## event, that action gets the replaced event in its place and its name is returned; otherwise &"" is.
## An event that cannot be bound (no key, no button, an axis at rest, another kind) is refused with
## a warning. The change is in the InputMap now; save_bindings() keeps it.
func rebind(action: StringName, event: InputEvent) -> StringName:
	var wanted := Bindings.event_from_data(Bindings.event_to_data(event))
	if wanted == null:
		push_warning("Inputs: cannot bind %s to %s" % [action, event])
		return &""
	var map := Bindings.current()
	var mine: Array = map[action]
	if mine.any(func(e: InputEvent) -> bool: return Bindings.same_event(e, wanted)):
		return &""

	var kind_index := mine.find_custom(func(e: InputEvent) -> bool: return Bindings.is_gamepad(e) == Bindings.is_gamepad(wanted))
	var replaced: InputEvent = mine[kind_index] if kind_index >= 0 else null

	var changed := {action: mine}
	var other := &""
	for name: StringName in Bindings.ACTIONS:
		if name == action:
			continue
		var theirs: Array = map[name]
		var at := theirs.find_custom(func(e: InputEvent) -> bool: return Bindings.same_event(e, wanted))
		if at < 0:
			continue
		if replaced != null:
			theirs[at] = replaced
		else:
			theirs.remove_at(at)
		changed[name] = theirs
		other = name
		break

	if kind_index >= 0:
		mine[kind_index] = wanted
	else:
		mine.append(wanted)
	Bindings.apply(changed)
	return other


## Writes the bindings now in the InputMap to `path`.
func save_bindings(path := BINDINGS_PATH) -> Error:
	var cfg := ConfigFile.new()
	var map := Bindings.current()
	for action in Bindings.ACTIONS:
		cfg.set_value(_SECTION, action, map[action].map(Bindings.event_to_data))
	return cfg.save(path)


## Applies the bindings saved at `path`; an action the file does not mention keeps its default.
## If the file is missing, is not a bindings file, or holds an unknown action or an event that
## cannot be read, it warns, applies the defaults and returns false.
func load_bindings(path := BINDINGS_PATH) -> bool:
	var map := Bindings.defaults()
	var problem := _read(path, map)
	if not problem.is_empty():
		push_warning("Inputs: %s (%s); using the default bindings" % [problem, path])
		Bindings.apply(Bindings.defaults())
		return false
	Bindings.apply(map)
	return true


# Overwrites the entries of `map` that the file at `path` sets. Returns what is wrong with the file, or "".
func _read(path: String, map: Dictionary) -> String:
	if not FileAccess.file_exists(path):
		return "there is no bindings file"
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return "the bindings file cannot be read"
	if not cfg.has_section(_SECTION):
		return "the file has no [%s] section" % _SECTION
	for key in cfg.get_section_keys(_SECTION):
		var action := StringName(key)
		if not Bindings.ACTIONS.has(action):
			return "the file binds an unknown action '%s'" % key
		var saved: Variant = cfg.get_value(_SECTION, key)
		if not saved is Array:
			return "the binding of '%s' is not a list" % key
		var events: Array[InputEvent] = []
		for data in saved:
			var event := Bindings.event_from_data(data)
			if event == null:
				return "the binding of '%s' holds an event that cannot be read" % key
			events.append(event)
		map[action] = events
	return ""


# How far, from 0 to 1, a gamepad axis bound to `action` is pushed in the bound direction.
# The strongest of the action's axes counts.
func _pushed(action: StringName, device: int) -> float:
	var strongest := 0.0
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			strongest = maxf(strongest, Input.get_joy_axis(device, event.axis) * signf(event.axis_value))
	return strongest


# 1 while any key, mouse button or gamepad button (on one of `devices`) bound to `action` is down, else 0.
func _down(action: StringName, devices: Array[int]) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and Input.is_physical_key_pressed(event.physical_keycode):
			return 1
		if event is InputEventMouseButton and Input.is_mouse_button_pressed(event.button_index):
			return 1
		if event is InputEventJoypadButton:
			for device in devices:
				if Input.is_joy_button_pressed(device, event.button_index):
					return 1
	return 0
