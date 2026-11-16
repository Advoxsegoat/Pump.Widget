class_name RouteBrain
extends Brain
## A brain that walks a route, for tests and demos: the stick all the way toward the first waypoint, straight at it, and on to
## the next within REACH of it; `done` once the last is reached. It looks at nothing in between: a route that crosses a wall
## stops at the wall, and the test that walked it says so.

## How near a waypoint counts as reaching it, in metres.
const REACH := 0.6

## Whether every waypoint has been reached, and how many have (the one being walked to).
var done := false
var index := 0

var _waypoints: Array[Vector3] = []


func _init(waypoints: Array[Vector3]) -> void:
	_waypoints.assign(waypoints)
	done = _waypoints.is_empty()


func think(actor: Actor, _delta: float) -> Intent:
	var intent := Intent.new()
	var here := Vector2(actor.global_position.x, actor.global_position.z)
	while index < _waypoints.size() and here.distance_to(Vector2(_waypoints[index].x, _waypoints[index].z)) < REACH:
		index += 1
	done = index >= _waypoints.size()
	if not done:
		intent.move = (Vector2(_waypoints[index].x, _waypoints[index].z) - here).normalized()
	return intent
