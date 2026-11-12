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
## The rate the locomotion clips play at, beside the ground speeds above: 1 plays them as they are. A body larger than the clips'
## (the heavy Knuckle, 1.18) strides further with each of their steps, so it plays them slower to go the speeds it is given
## without its feet sliding: its stride at its size and cadence is the clips' ground speed at it, times model_scale times this.
## An actor with a cadence also has the blend point of its speed divided by its size (Rig.set_locomotion), so that its jog speed
## picks the jog's pose; an actor with 1 is blended exactly as before, whatever its size.
@export_range(0.3, 1.5) var cadence := 1.0
