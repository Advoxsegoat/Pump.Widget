class_name DirectorBrain
extends Brain
## The brain a scene gives each actor of its cast: it walks, faces and looks where the scene says and presses nothing, so
## that the actor's own body (its locomotion, its feet, its head) does the acting and a scene never moves anyone by any
## other means. The Director sets its fields as the timeline's beats arrive.
##
## A walk (`walk_to`) pushes the stick toward the mark at `push` and lets go at `release` metres from it; the body then
## coasts to rest, and `arrived` is true once it has (StoryWalk says how far from the mark to let go, so that the body
## rests on it). A brain with no `move_to` leaves the stick alone.

## The mark being walked to (a Vector3 on the floor), or null.
var move_to: Variant = null
## How hard the stick is pushed, 0 to 1 (StoryWalk.push_of).
var push := 0.0
## The metres from the mark at which the stick is let go.
var release := StoryWalk.ARRIVAL
## A world point (Vector3) the body keeps facing, or null (it faces the way it goes).
var face: Variant = null
## A world point (Vector3) the head follows, or null.
var look: Variant = null
## True once the walk has been let go and the body is at rest.
var arrived := false

var _released := false


## Starts walking to `point` at `stick` (0 to 1), letting go `release_metres` short of it.
func walk_to(point: Vector3, stick: float, release_metres := StoryWalk.ARRIVAL) -> void:
	move_to = point
	push = stick
	release = release_metres
	arrived = false
	_released = false


## Stops walking and forgets the mark.
func halt() -> void:
	move_to = null
	push = 0.0
	arrived = false
	_released = false


func think(actor: Actor, _delta: float) -> Intent:
	var intent := Intent.new()
	if move_to is Vector3:
		var flat := Vector2((move_to as Vector3).x - actor.global_position.x, (move_to as Vector3).z - actor.global_position.z)
		if not _released and flat.length() <= release:
			_released = true
			push = 0.0
		if _released:
			arrived = actor.locomotion.speed == 0.0
		elif not flat.is_zero_approx():
			intent.move = flat.normalized() * push
	intent.face_target = face
	intent.look_target = look
	return intent
