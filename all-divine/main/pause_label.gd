class_name PauseLabel
extends CanvasLayer
## "Paused" across the middle of the screen while the game is paused (Game.state is PAUSE), so the menu
## button's pause does not look like a freeze. It follows Game.state_changed and runs while the tree is
## paused. Drawn over the picture at the window's own resolution, under the debug overlay.

var label: Label


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	label = Label.new()
	label.name = "Label"
	label.text = "Paused"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 48)
	label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override(&"outline_size", 8)
	add_child(label)


func _ready() -> void:
	Game.state_changed.connect(_on_state_changed)
	_on_state_changed(Game.state, Game.state)


func _on_state_changed(_from: Game.State, _to: Game.State) -> void:
	visible = Game.state == Game.State.PAUSE
