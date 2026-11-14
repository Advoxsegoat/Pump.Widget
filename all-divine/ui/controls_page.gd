class_name ControlsPage
extends RefCounted
## The Controls page of the pause menu: a row for each of ControlsList.ACTION_ROWS with the events bound to it on the device in the
## player's hand (the keyboard and mouse, or the pad), and the capture that rebinds one.
##
## The list follows the hand: the pad when the last thing touched was a pad that is still connected, else the keyboard and mouse.
## Choosing a binding row starts a capture for the device shown at that moment: the next press of that kind of device is bound
## with Inputs.rebind and kept in the bindings file. Esc and B (either device) cancel, so does 6 s of menu time or the pad being
## unplugged while a pad row waits. While it waits the device shown is held fixed, an event of the other device is ignored, and
## nothing else in the menu moves (Menu hands every event here first). The menu's own keys are fixed (MenuNav), so no capture can
## lock the player out of it; the one game button the menu also answers to, `menu`, is kept on at least one button of each device
## it was on (see _keep_menu_reachable).

## The least width of a binding's column, in picture pixels: a name longer than the column is cut with an ellipsis.
const COLUMN_MIN := 96
## How long a capture waits, and how long a note (a swap, a refusal) stays in the footer, in seconds of the menu's own clock.
const CAPTURE_SECONDS := 6.0
const NOTE_SECONDS := 3.0
## A stick or trigger binds once pushed this far, and must come back below RELEASE to bind again after it started past it.
const PUSH := Bindings.FLICK_DEADZONE
const RELEASE := Bindings.DIRECTION_RELEASE
## Lines the footer may take: the capture's prompt is longer than a panel is wide.
const FOOTER_LINES := 2
const LEGEND_KEYBOARD := "Enter: change   Esc: back"
const LEGEND_PAD := "A: change   B: back"
const OWN_KEY_NOTE := "That key is the game's own."
const PAD_GONE_NOTE := "Pad disconnected."
const WHEELS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]

## Whether the list shows the pad's bindings (else the keyboard and mouse's).
var pad := false

var _menu: Menu
var _action := &""
var _label := ""
var _capturing := false
var _left := 0.0
var _hot: Dictionary = {}  # [axis, direction] -> true while pushed past PUSH since before the capture, until it has rested
var _note := ""
var _note_left := 0.0


## The page for `menu`.
static func build(menu: Menu) -> MenuPage:
	var controls := ControlsPage.new()
	controls._menu = menu
	controls.pad = controls.hand_is_pad()
	var rows: Array[MenuRow] = []
	var column := controls._column()
	for item: Array in ControlsList.ACTION_ROWS:
		var action: StringName = item[0]
		var row := MenuRow.new()
		row.kind = MenuRow.Kind.BINDING
		row.label = item[1]
		row.value_width = column
		row.value_text = func() -> String: return controls.text_for(action)
		row.all_values = func() -> Array: return [ControlsList.shown(action, false), ControlsList.shown(action, true)]
		row.on_choose = func() -> void: controls.begin(action, item[1])
		rows.append(row)
	rows.append(MenuRow.text(ControlsList.ROWS[4][0]))
	rows.append(MenuRow.text(ControlsList.FINISHER_NOTE))
	rows.append(MenuRow.action("Restore default controls", controls.restore))
	rows.append(MenuRow.action("Back", menu.pop_page))
	var page := MenuPage.new()
	page.heading = controls.heading()
	page.rows = rows
	page.back = menu.pop_page
	page.controls = controls
	return page


## The pad is in hand when a pad was the last thing touched and one is still connected.
func hand_is_pad() -> bool:
	return Inputs.last_device() == Inputs.Device.GAMEPAD and _menu.pad_present.call()


func capturing() -> bool:
	return _capturing


func heading() -> String:
	return "Controls: Gamepad" if pad else "Controls: Keyboard and mouse"


## The footer: a note while there is one, else the capture's prompt while one waits, else the legend.
func footer() -> String:
	if _note_left > 0.0:
		return _note
	if _capturing:
		if pad:
			return "Press a new button for %s. B cancels." % _label
		return "Press a new key or mouse button for %s. Esc cancels." % _label
	return LEGEND_PAD if pad else LEGEND_KEYBOARD


## Whether the footer says something now (a prompt or a note) rather than the legend: it is drawn in gold, to be unmistakable.
func alert() -> bool:
	return _capturing or _note_left > 0.0


## The texts the panel's width must hold besides its rows (the heading and legend of either device).
func widest_texts() -> Array[String]:
	return ["Controls: Gamepad", "Controls: Keyboard and mouse", LEGEND_PAD, LEGEND_KEYBOARD]


## What a binding row shows: ... while it waits for its button, else what is bound on the device shown.
func text_for(action: StringName) -> String:
	if _capturing and action == _action:
		return "..."
	return ControlsList.shown(action, pad)


## Follows the hand (not while a capture holds the device fixed).
func sync() -> void:
	if not _capturing:
		pad = hand_is_pad()


## Counts the capture's time and the note's by `delta` seconds, and follows the hand.
func tick(delta: float) -> void:
	if _note_left > 0.0:
		_note_left -= delta
	if _capturing:
		_left -= delta
		if _left <= 1e-6:
			cancel()
	sync()


## A pad was plugged in or out: a pad row that waits for a pad that is gone gives up.
func joy_changed() -> void:
	if _capturing and pad and not _menu.pad_present.call():
		_end(PAD_GONE_NOTE)
	sync()


## Starts a capture for `action` (shown as `label`) on the device shown now. The press that chose the row is not captured: only a
## press that comes after this call is, and a key's repeat and every release are never a press.
func begin(action: StringName, label: String) -> void:
	_action = action
	_label = label
	_capturing = true
	_left = CAPTURE_SECONDS
	_note = ""
	_note_left = 0.0
	_hot.clear()
	if pad:
		var devices: Array[int] = [0]
		for device in Input.get_connected_joypads():
			if not devices.has(device):
				devices.append(device)
		for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			for device in devices:
				for way in [-1, 1]:
					if Input.get_joy_axis(device, axis) * way >= PUSH:
						_hot[[axis, way]] = true
	_menu.nav.begin()


## Gives up the capture, nothing changed.
func cancel() -> void:
	_end("")


## What a waiting capture does with `event` (Menu hands it everything, and the capture takes all of it).
func capture(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			cancel()
		elif pad:
			return
		elif _is_own(event):
			_say(OWN_KEY_NOTE)
		else:
			_bind(event)
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and not pad and not WHEELS.has(click.button_index):
			_bind(event)
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return
		if button.button_index == JOY_BUTTON_B:
			cancel()
		elif not pad:
			return
		elif _is_own(event):
			_say(OWN_KEY_NOTE)
		else:
			_bind(event)
	elif event is InputEventJoypadMotion and pad:
		var motion := event as InputEventJoypadMotion
		var strength := absf(motion.axis_value)
		if strength < RELEASE:
			_hot.erase([motion.axis, 1])
			_hot.erase([motion.axis, -1])
		elif strength >= PUSH and not _hot.has([motion.axis, 1 if motion.axis_value > 0.0 else -1]):
			_bind(event)


## Every binding back to how the game came, kept.
func restore() -> void:
	Bindings.apply(Bindings.defaults())
	Inputs.save_bindings(Inputs.bindings_path)


# The game's own keys (Main reads them first) and Alt+Enter are never bound.
func _is_own(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return Main.OWN_KEYS.has(key.keycode) or Main.OWN_KEYS.has(key.physical_keycode) or WindowToggle.is_toggle(event)
	return Main.OWN_BUTTONS.has((event as InputEventJoypadButton).button_index)


func _say(note: String) -> void:
	_note = note
	_note_left = NOTE_SECONDS


# Binds `event` to the action waiting, keeps it, and ends the capture with what happened as the note.
func _bind(event: InputEvent) -> void:
	if Bindings.event_to_data(event).is_empty():
		return  # nothing that can be bound (a key with no place on the keyboard)
	var had := _menu_devices()
	var other := Inputs.rebind(_action, event)
	var note := ""
	if other != &"":
		note = "Swapped with %s." % _name_of(other)
	var restored := _keep_menu_reachable(had)
	if not restored.is_empty():
		note += " It is on %s again." % restored if not note.is_empty() else "Menu / back is on %s again." % restored
	Inputs.save_bindings(Inputs.bindings_path)
	_end(note)


func _end(note: String) -> void:
	_capturing = false
	_hot.clear()
	_note = note
	_note_left = NOTE_SECONDS if not note.is_empty() else 0.0
	_menu.nav.begin()
	sync()


func _name_of(action: StringName) -> String:
	for item: Array in ControlsList.ACTION_ROWS:
		if item[0] == action:
			return item[1]
	return String(action)


# Whether the `menu` action has a button on the keyboard and mouse, and on the pad: [keyboard, pad].
func _menu_devices() -> Array[bool]:
	var out: Array[bool] = [false, false]
	for event in InputMap.action_get_events(&"menu"):
		out[1 if Bindings.is_gamepad(event) else 0] = true
	return out


# A capture can take the last button the menu action had on a device (binding another action to it, when that one has none of that
# kind to give back). The game could then not be paused from that device, so the menu action gets its default back there (Esc, Start).
# Returns what it was given, or "".
func _keep_menu_reachable(had: Array[bool]) -> String:
	var now := _menu_devices()
	var given := []
	for gamepad in [false, true]:
		var at := 1 if gamepad else 0
		if had[at] and not now[at]:
			for event: InputEvent in Bindings.defaults()[&"menu"]:
				if Bindings.is_gamepad(event) == gamepad:
					Inputs.rebind(&"menu", event)
					given.append(ControlsList.long_name(event))
	return " and ".join(given)


# The width of a binding's column: the widest text any row shows for either device, at least COLUMN_MIN, at most what the
# longest label leaves in the widest panel.
func _column() -> int:
	var widest_label := 0
	var widest := COLUMN_MIN
	for item: Array in ControlsList.ACTION_ROWS:
		widest_label = maxi(widest_label, Menu.measure(item[1]))
		for gamepad in [false, true]:
			widest = maxi(widest, Menu.measure(ControlsList.shown(item[0], gamepad)))
	var room := Menu.PANEL_W - 2 * Menu.PADDING - Menu.ARROW_ROOM - Menu.INDENT - widest_label - Menu.VALUE_GAP
	return clampi(widest, COLUMN_MIN, maxi(room, COLUMN_MIN))
