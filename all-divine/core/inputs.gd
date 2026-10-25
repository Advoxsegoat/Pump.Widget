extends Node
## What the player is doing with the controls, and the rebinding of them.
##
## Autoload "Inputs". The actions and their default events are in Bindings; this reads them
## (the movement stick with a deadzone, the buttons as actions), swaps them when the player
## rebinds one, and saves and loads the player's table.

## Below this much stick deflection the stick is at rest. Past it, the deflection is rescaled to
## run from 0 at the edge of the deadzone to 1 at full.
const DEADZONE := 0.2
## Where the player's bindings are kept.
const BINDINGS_PATH := "user://input.cfg"
## The actions that are pressed and let go, as opposed to movement, which is read as a vector.
const GAMEPLAY: Array[StringName] = [
	&"palm", &"heavy", &"guard", &"gift", &"dodge", &"item", &"interact", &"lock_on",
	&"slot_up", &"slot_right", &"slot_down", &"slot_left", &"slot_next", &"slot_prev", &"menu",
]

const _SECTION := "bindings"

## The file _ready loads. Only a test changes it.
var bindings_path := BINDINGS_PATH


func _ready() -> void:
	Bindings.apply(Bindings.defaults())
	# A player who never rebound anything has no file, and that is not worth a warning.
	if FileAccess.file_exists(bindings_path):
		load_bindings(bindings_path)


## A stick reading with the deadzone taken out: 0 below DEADZONE, then (length - DEADZONE) / (1 - DEADZONE),
## up to 1, in the direction of `raw`.
static func shape_stick(raw: Vector2) -> Vector2:
	var length := raw.length()
	# A Vector2 holds 32-bit floats, so a stick at exactly 0.2 is a hair above the 64-bit 0.2.
	if length <= DEADZONE or is_equal_approx(length, DEADZONE):
		return Vector2.ZERO
	return raw / length * minf((length - DEADZONE) / (1.0 - DEADZONE), 1.0)


## Whichever of the two is longer. `keys` counts as a unit vector in its direction, so
## moving diagonally on the keyboard is no faster than moving straight.
static func combine(stick: Vector2, keys: Vector2) -> Vector2:
	var unit := keys.normalized()
	return unit if unit.length_squared() > stick.length_squared() else stick


## The movement the player is asking for, in screen space (right is +x, up is -y), at most length 1.
## `devices` are the gamepads whose left stick counts (the strongest wins); by default, every one connected.
func move_vector(devices: Array[int] = Input.get_connected_joypads()) -> Vector2:
	var stick := Vector2.ZERO
	for device in devices:
		var shaped := shape_stick(Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)))
		if shaped.length_squared() > stick.length_squared():
			stick = shaped
	var keys := Vector2(_digital(&"move_right") - _digital(&"move_left"), _digital(&"move_down") - _digital(&"move_up"))
	return combine(stick, keys)


## The gameplay actions that went down this frame.
func pressed_this_frame() -> Array[StringName]:
	var pressed: Array[StringName] = []
	for action in GAMEPLAY:
		if Input.is_action_just_pressed(action):
			pressed.append(action)
	return pressed


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


# 1 while any key or mouse button bound to `action` is down, else 0. Gamepad events are left out:
# the stick is read as a vector by move_vector.
func _digital(action: StringName) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and Input.is_physical_key_pressed(event.physical_keycode):
			return 1
		if event is InputEventMouseButton and Input.is_mouse_button_pressed(event.button_index):
			return 1
	return 0
