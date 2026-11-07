class_name LocomotionTuning
extends Resource
## How an actor moves on the ground. The speeds are the ground speeds of its walk, jog and sprint clips
## (the clips' `ground_speed` metadata) to a tenth of a metre per second, so a foot does not slide at
## those speeds.

## Metres per second.
@export var walk_speed := 1.0
@export var jog_speed := 5.5
@export var sprint_speed := 8.5
## Metres per second squared, speeding up toward the wanted speed and slowing down toward it.
@export var accel := 18.0
@export var decel := 24.0
## Degrees per second the body turns toward its heading.
@export var turn_rate_deg := 720.0
## Stick deflection (0 to 1) below which the actor walks rather than jogs.
@export var walk_threshold := 0.5
