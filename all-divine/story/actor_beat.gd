class_name ActorBeat
extends Resource
## What one actor does from a frame of a shot: play a clip, walk to a place, face something, look at something.

## How hard the stick is pushed for a `move_to`: a walk is 0.45 (0.9 m/s for the Knuckle), a jog 1.0.
enum Pace { WALK, JOG }

## A cast name.
@export var actor: StringName
## Frames into the shot.
@export var at := 0
## A clip of the actor's rig; held at its last frame unless `loop`. Empty: no clip.
@export var clip: StringName
@export var loop := false
## Seconds the clip fades in.
@export var blend := 0.1
## An actor or mark to walk to. How long that takes comes from the locomotion numbers, not from the shot.
@export var move_to: StringName
@export var pace: Pace = Pace.WALK
## An actor or mark to turn to face.
@export var face: StringName
## An actor or mark the head follows.
@export var look: StringName
## True when `clip` is not made yet: the checker lists it instead of failing a draft, and the animatic holds idle.
@export var placeholder := false
