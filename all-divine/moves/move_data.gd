class_name MoveData
extends Resource
## One move: which clip it plays and what it costs and does. The timeline (hitboxes, invulnerability,
## cancel windows, effects) is not here but in the clip's marks (see marks.gd); the clip checker
## (tools/clip_checker.gd) keeps the two consistent.

enum Kind { ATTACK, DODGE, OTHER }

@export var id: StringName
@export var kind: Kind = Kind.ATTACK
## The clip in the actor's rig that plays the move.
@export var clip: StringName
## Whether the clip's root bone drives the actor's travel while the move plays.
@export var root_motion := true
## What the root motion is multiplied by: the clip's own travel times this is how far the actor goes.
## Keeps a move's distance tunable without re-authoring its clip.
@export var root_motion_scale := 1.0
@export var stamina_cost := 0.0
@export var posture_damage := 0.0
@export var poise_damage := 0.0
## Seconds over which the move fades in over what the actor was doing, and out to locomotion.
@export var blend_in := 0.05
@export var blend_out := 0.15
