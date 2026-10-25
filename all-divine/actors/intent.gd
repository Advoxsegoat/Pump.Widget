class_name Intent
extends RefCounted
## What a brain wants its actor to do this frame. Brains make one per physics frame; the actor acts on it.

## Where to go: world (x, z), length 0 to 1 (how far the stick is pushed, deadzone already out).
var move := Vector2.ZERO
## Actions that went down this frame. They go into the actor's input buffer.
var pressed: Array[StringName] = []
## Actions that are down this frame (holding dodge sprints).
var held: Array[StringName] = []
## A world point (Vector3) to keep facing while moving, or null to face the way the actor goes.
var face_target: Variant = null
## A world point (Vector3) for the head and eyes to look at, or null.
var look_target: Variant = null
