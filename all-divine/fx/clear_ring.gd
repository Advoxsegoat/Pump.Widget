class_name ClearRing
extends Node3D
## The ring a clear-out's wave shows on the ground (data/fx/clear_ring.tres): a pale gold GroundWave from where the effect is
## shown (his feet) out to the reach of the wave. It is the shove's own tell, in the colour of his open hand, not the red of a
## danger; like every wave it lies on the ground and never over a body.

## How far the ring spreads, in metres: the wave's own radius (clear_ring in his rig).
@export var radius := 2.0
@export var seconds := 0.4
@export var color := Color("f2dea0")
@export var ring_width := 0.14
@export var fill_alpha := 0.12


func _ready() -> void:
	var wave := GroundWave.make(radius, seconds, color, ring_width, fill_alpha)
	add_child(wave)
	wave.position = Vector3.UP * GroundWave.LIFT
