class_name DebugOverlay
extends CanvasLayer
## F3's overlay (main.gd): frames per second, the longest physics step of the last second, the move the
## actor plays and how fast it goes over the ground. Drawn over the picture at the window's own resolution.
## It starts hidden; main.gd sets `actor`.

var actor: Actor
var label: Label


func _init() -> void:
	layer = 100
	label = Label.new()
	label.name = "Label"
	label.position = Vector2(12, 8)
	label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)


func _process(_delta: float) -> void:
	if visible:
		label.text = text()


## What the overlay shows, a line each.
func text() -> String:
	var move := "-"
	var speed := 0.0
	if is_instance_valid(actor):
		if actor.runner != null and actor.runner.current != null:
			move = String(actor.runner.current.id)
		speed = Vector2(actor.velocity.x, actor.velocity.z).length()
	return "\n".join([
		"fps %d" % Engine.get_frames_per_second(),
		"physics %.2f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"move %s" % move,
		"speed %.2f m/s" % speed,
	])
