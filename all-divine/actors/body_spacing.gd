class_name BodySpacing
extends RefCounted
## Bodies do not pass through each other. An actor's body is a capsule on the `actor` layer that collides only with the
## world, so on its own a move's root motion, a walk or a knockback would carry it straight through another actor: the
## Knuckle's thrust out the far side of the body it struck. So before each move_and_slide the actor has its BodySpacing
## cut its motion on the ground against every other actor's capsule (keep_apart):
##   - the part of the motion that would take the two capsules closer than their radii together is taken away, so the
##     body stops at the other's capsule and slides along it (a clamp at contact): a thrust stops at the body it hits,
##     and a lunge or a roll at the body in its way
##     When the other body is closing too, each takes only half the gap between them (they meet in the middle).
##   - two capsules already pressed into each other (a spawn, a teleport) are eased apart: each moves itself out at up
##     to SEPARATE_SPEED
## And after move_and_slide the actor settles (settle): a wall's slide can turn a clamped motion back into a body (a
## thrust down a wall into someone standing by it), so a body that has ended deeper inside another than it was before the
## move is put back along its own path to where it is no deeper than it was, or at contact.
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
## How much deeper than before a move a body may end inside another before settle puts it back, and how finely the
## point it is put back to is found (halvings of the path).
const SETTLE_SLACK := 0.001
const SETTLE_STEPS := 10

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
		if Vector2(other.velocity.x, other.velocity.z).dot(toward) < 0.0:
			room *= 0.5  # it is closing on us too: half the gap each
		if closing > room:
			motion -= toward * (closing - room)
		if distance < reach:
			motion -= toward * minf(reach - distance, SEPARATE_SPEED * delta)
	return Vector3(motion.x / delta, velocity.y, motion.y / delta)


## After the actor's move_and_slide (it stood at `from` before it): if the move has left it deeper inside another body
## than it was at `from` (a wall's slide carried a clamped motion into it), the actor is put back along its own path of
## this frame to the furthest point that leaves it no deeper inside anyone than it was, or at contact. The path is where
## it has just been, so no wall stands on it. Returns the share of the path it kept (1: all of it).
func settle(from: Vector3) -> float:
	if _radius <= 0.0 or not _solid(_actor):
		return 1.0
	var others := _settle_against()
	var start := Vector2(from.x, from.z)
	var path := Vector2(_actor.global_position.x, _actor.global_position.z) - start
	if others.is_empty() or path.length() <= SAME_POINT or not _deeper(start + path, start, others):
		return 1.0
	var kept := 0.0
	var lost := 1.0
	for i in SETTLE_STEPS:
		var mid := (kept + lost) * 0.5
		if _deeper(start + path * mid, start, others):
			lost = mid
		else:
			kept = mid
	var at := start + path * kept
	_actor.global_position = Vector3(at.x, _actor.global_position.y, at.y)
	return kept


# The actors a settle is checked against: solid, not passing through this one, neither airborne, not its pair partner,
# and sharing some height with it, each as [its ground point, the two radii together].
func _settle_against() -> Array:
	var out := []
	if _actor.runner.airborne:
		return out
	for node in _actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == _actor or not _solid(other) or other.spacing == null or _passing.has(other):
			continue
		if other.runner.airborne or _paired_together(_actor, other):
			continue
		if absf(other.global_position.y - _actor.global_position.y) >= (_height + other.spacing.height()) * 0.5:
			continue
		out.append([Vector2(other.global_position.x, other.global_position.z), _radius + other.spacing.radius()])
	return out


# Whether standing at `at` (ground point) is deeper inside any of `others` (_settle_against) than standing at `from`.
static func _deeper(at: Vector2, from: Vector2, others: Array) -> bool:
	for o: Array in others:
		var allowed := minf(o[1], (from - (o[0] as Vector2)).length())
		if (at - (o[0] as Vector2)).length() < allowed - SETTLE_SLACK:
			return true
	return false


# Whether `actor`'s body stands in the way of others: alive and in the game.
static func _solid(actor: Actor) -> bool:
	return actor.is_inside_tree() and not actor.dead


# Whether `a` and `b` are the two fighters of one paired move (either still has the other as its paired_with: the lead
# is free once its move ends, while its follower plays on).
static func _paired_together(a: Actor, b: Actor) -> bool:
	return a.paired_with == b or b.paired_with == a
