class_name PetalPile
extends Node3D
## The pile of petals he left where he fell, drawn in the world (fx/petal_pile.tscn): a slow column of pixel petals, rose and gold, rising
## from the ground and fading. No light and nothing dark in it (the rose glow of the shrines hid a head with its first try, and this is
## held to the picture rules by tests/render/test_bilibara_pile.gd); the run frees it when the pile is taken back or wilts.

## The petals it stands for.
var amount := 0:
	set(value):
		amount = value
		_fill()

@onready var _column := $Column as GPUParticles3D


func _ready() -> void:
	_fill()


# A bigger pile has a fuller column: a share of the particles, 0.5 for a handful, all of them from 300 petals.
func _fill() -> void:
	if _column != null:
		_column.amount_ratio = clampf(0.5 + float(amount) / 600.0, 0.5, 1.0)
