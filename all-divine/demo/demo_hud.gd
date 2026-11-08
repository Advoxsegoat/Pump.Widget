class_name DemoHud
extends CanvasLayer
## The preview demo's heads-up display: plain Labels, a stand-in that Task 14's HUD replaces.
##
## Top-left: Abarax's HP, stamina and posture as numbers. Top-right: a line for each Knuckle (its tier, HP and posture,
## or "down"). Bottom-left: the controls, for keyboard and mouse and for a pad, read from the live InputMap
## (Bindings.current) so that they match what is bound; H shows or hides them.
##
## The labels are placed in the pixel stage's 640x360 picture and the layer is scaled and centred as the stage scales and
## centres that picture (PixelStage.layout), so a label's size is its size in the picture, and one pixel of it is a
## whole block of the screen. The font is the default one, as in the debug overlay and the pause label.

## The picture the labels are placed in.
const PICTURE := Vector2(PixelSnap.INTERNAL)
const MARGIN := 6.0
const FONT_SIZE := 10
const TIERS: Array[String] = ["I", "II", "III"]
## The rows of the controls list: what it is for, and the actions whose bindings it names.
const ROWS := [
	["Move", [&"move_up", &"move_left", &"move_down", &"move_right"]],
	["Palm (jab, cross, hook)", [&"palm"]],
	["Heavy", [&"heavy"]],
	["Guard (tap to parry)", [&"guard"]],
	["Dodge (roll; hop if still)", [&"dodge"]],
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

var player_label: Label
var foes_label: Label
var controls_label: Label

var _main: Main
var _controls_shown := ""


func _init() -> void:
	layer = 80
	player_label = _label("Player", HORIZONTAL_ALIGNMENT_LEFT)
	foes_label = _label("Foes", HORIZONTAL_ALIGNMENT_RIGHT)
	controls_label = _label("Controls", HORIZONTAL_ALIGNMENT_LEFT)
	player_label.position = Vector2(MARGIN, MARGIN)
	foes_label.size = Vector2(220, 0)
	foes_label.position = Vector2(PICTURE.x - MARGIN - foes_label.size.x, MARGIN)


func _ready() -> void:
	_main = get_parent() as Main
	_place()
	_refresh()


func _process(_delta: float) -> void:
	_place()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_H:
		controls_label.visible = not controls_label.visible
		get_viewport().set_input_as_handled()


## The controls list, one line a row: keyboard and mouse, then the pad, from the bindings in force now.
func controls_text() -> String:
	var map := Bindings.current()
	var lines := PackedStringArray(["Controls (H hides)"])
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


## Abarax's numbers, a line each.
func player_text(actor: Actor) -> String:
	return "HP %d\nSTA %d\nPOS %d" % [ceili(actor.stats.hp), ceili(actor.stats.stamina), ceili(actor.stats.posture)]


## One Knuckle's line: its tier, HP and posture, or "down".
func foe_text(actor: Actor) -> String:
	var tier := TIERS[clampi(String(actor.def.id).trim_prefix("knuckle_").to_int() - 1, 0, 2)]
	if actor.dead:
		return "%s down" % tier
	return "%s HP %d POS %d" % [tier, ceili(actor.stats.hp), ceili(actor.stats.posture)]


func _refresh() -> void:
	var text := controls_text()
	if text != _controls_shown:
		_controls_shown = text
		controls_label.text = text
	controls_label.size = Vector2.ZERO
	controls_label.position = Vector2(MARGIN, PICTURE.y - MARGIN - controls_label.get_minimum_size().y)
	if _main == null or not is_instance_valid(_main.player) or _main.player.stats == null:
		return
	player_label.text = player_text(_main.player)
	var foes: Array[Actor] = []
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor != null and actor.def.team == ActorDef.Team.ENEMY and actor.stats != null and _main.is_ancestor_of(actor):
			foes.append(actor)
	foes.sort_custom(func(a: Actor, b: Actor) -> bool: return String(a.def.id) < String(b.def.id))
	foes_label.text = "\n".join(foes.map(foe_text))


# Scales and centres the layer as the stage does its picture.
func _place() -> void:
	var window := Vector2i(get_viewport().get_visible_rect().size)
	var rect := PixelStage.layout(window)
	var k := float(PixelStage.scale_for(window))
	scale = Vector2(k, k)
	offset = Vector2(rect.position)


func _label(label_name: String, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = label_name
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override(&"outline_size", 3)
	add_child(label)
	return label
