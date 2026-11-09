class_name BodySpacing
extends RefCounted
## Bodies do not pass through each other. An actor's body is a capsule on the `actor` layer that collides only with the
## world, so on its own a move's root motion, a walk or a knockback would carry it straight through another actor: the
## Knuckle's thrust out the far side of the body it struck. So before each move_and_slide the actor has its BodySpacing
## cut its motion on the ground against every other actor's capsule (keep_apart):
##   - the part of the motion that would take the two capsules closer than their radii together is taken away, so the
##     body stops at the other's capsule and slides along it (a clamp at contact): a thrust stops at the body it hits,
##     and a lunge or a roll at the body in its way
##   - two capsules already pressed into each other (a spawn, a teleport) are eased apart: each moves itself out at up
##     to SEPARATE_SPEED
## Bodies that are not solid to each other are left alone: the dead; the two fighters of one paired move, which Pairing
## stages by its own spacing (each goes by its own root motion from an aligned start); and any two while either of them
## is airborne (MoveRunner.airborne: the hop), so that a low slide passes beneath a hopping body, which is how the hop
## counters the sweep. Two that came to be inside each other that way are passing: they go on through each other,
## whoever lands first, until they are apart again.
##
## Each actor is checked against the others where they stand now, so whatever order the actors run in, none moves
## itself into another.
##
## The actor owns one (Actor.spacing). It works on the ground plane only, and only between capsules that share some
## height.

## How fast a body pressed into another moves itself out, in m/s.
const SEPARATE_SPEED := 2.0
## Below this the two axes count as one point, and the body is pushed out backward (against its facing).
const SAME_POINT := 0.001

var _actor: Actor
var _radius := 0.0
var _height := 0.0
var _passing := {}  # Actor -> true: the bodies this one is passing through (see the top)


func _init(actor: Actor, body: CollisionShape3D) -> void:
	_actor = actor
	var capsule := body.shape as CapsuleShape3D if body != null else null
	if capsule != null:
		_radius = capsule.radius
		_height = capsule.height


## The radius of the actor's body capsule.
func radius() -> float:
	return _radius


## The height of the actor's body capsule.
func height() -> float:
	return _height


## `velocity` (m/s; its vertical part is kept) with the part of its ground motion over `delta` that would take the
## actor's capsule into another actor's taken away, and a push out of any it is already inside (see the top).
func keep_apart(velocity: Vector3, delta: float) -> Vector3:
	if delta <= 0.0 or _radius <= 0.0 or not _solid(_actor):
		return velocity
	var motion := Vector2(velocity.x, velocity.z) * delta
	var here := Vector2(_actor.global_position.x, _actor.global_position.z)
	for node in _actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == _actor or not _solid(other) or other.spacing == null:
			continue
		if absf(other.global_position.y - _actor.global_position.y) >= (_height + other.spacing.height()) * 0.5:
			continue
		var apart := Vector2(other.global_position.x, other.global_position.z) - here
		var distance := apart.length()
		var reach := _radius + other.spacing.radius()
		if _passing.has(other) or _actor.runner.airborne or other.runner.airborne:
			if distance < reach:
				_passing[other] = true  # through each other, while one is off the ground: let them pass
			else:
				_passing.erase(other)
			continue
		if _paired_together(_actor, other) or distance >= reach + motion.length():
			continue
		var toward := apart / distance if distance > SAME_POINT else -Vector2(_actor.facing().x, _actor.facing().z).normalized()
		var closing := motion.dot(toward)
		var room := maxf(distance - reach, 0.0)
		if closing > room:
			motion -= toward * (closing - room)
		if distance < reach:
			motion -= toward * minf(reach - distance, SEPARATE_SPEED * delta)
	return Vector3(motion.x / delta, velocity.y, motion.y / delta)


# Whether `actor`'s body stands in the way of others: alive and in the game.
static func _solid(actor: Actor) -> bool:
	return actor.is_inside_tree() and not actor.dead


# Whether `a` and `b` are the two fighters of one paired move (either still has the other as its paired_with: the lead
# is free once its move ends, while its follower plays on).
static func _paired_together(a: Actor, b: Actor) -> bool:
	return a.paired_with == b or b.paired_with == a
