class_name GateDef
extends Resource
## One gate as data (data/stretch/, the Registry kind `stretch`): a low board that a world flag takes away, and, if it has one, the
## latch that sets the flag from one side.

@export var id: StringName
## The world flag that opens it.
@export var opens_on: StringName
## Nodes of the region it lowers, by name.
@export var nodes := PackedStringArray()
## (x, z, width, depth): when not empty the gate builds its own slate board here, 0.6 m high.
@export var board := Rect2()
## Metres a board sinks.
@export var drop := 1.3
## The latch's place, and how near he must be to reach it; a radius of 0 means no latch.
@export var latch_centre := Vector3.ZERO
@export var latch_radius := 3.0
## The flat unit direction (x, z) from the gate toward the side it can be lifted from.
@export var open_side := Vector2.ZERO
@export var latch_prompt := "Lift the bar"
@export var barred_prompt := "Barred from the other side"
