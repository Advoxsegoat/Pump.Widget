class_name HitScanner
extends RefCounted
## Finds what an actor's hitboxes strike. One per actor (Actor.scanner): its move runner says when a hitbox
## comes on and goes off (begin and end, from the hitbox_on and hitbox_off marks), and once a physics frame,
## after the rig has posed the body, the actor scans and posts what was found to Melee.
##
## A hand at full swing moves further in a tick than it is wide, so a hitbox is not looked for only where it
## is: each scan sweeps its shape from where it was at the last scan to where it is now, in steps no longer
## than half the shape's radius (by how far its centre moves: a sphere, as every hitbox is, turning in place
## covers nothing new), and asks the physics space at each step which hurtboxes the shape overlaps.
## The first scan of an activation looks only where the hitbox is, so it hits nothing along the way it came
## while it was off; and an activation that ends before it was ever scanned (on and off between two ticks) is
## still looked for once, where the hitbox is, so no blow falls between ticks.
##
## Each body is struck at most once per activation: the same blow does not land again on the way back, and a new
## begin is a new blow. A blow that came to nothing does not count: Melee hands a WHIFF's target back (forget),
## so a swing still live when a body's iframes end can land on the body it passed through. The actor's own hurtbox is left out of the queries (its hands pass through its body),
## and so is every body of its own team (ActorDef.team): blows land only on the other side. A hurtbox is mapped
## to its actor by its meta `actor`, which Actor._ready sets.
##
## The hurtboxes are where the physics space has them, which is where they stood when the frame began: the
## engine hands a moved node's transform to the physics server once every node has run its frame. So every
## actor's scan in a frame finds the others where they stood at its start, whatever order the actors run in.

## Results asked of one query: far more bodies than a hand can touch at once.
const MAX_RESULTS := 32
## The step for a shape that has no radius to go by (none of ours): 5 cm.
const DEFAULT_STEP := 0.05


# One activation of one hitbox: from a begin to its end.
class Activation:
	var hitbox: StringName
	var move: MoveData
	var profile: HitProfile
	var hit := {}  # the actors this activation has hit -> true
	var scanned := false
	var last := Transform3D()  # the hitbox's transform at the last scan


var _active := {}  # hitbox id -> its Activation, while it is on
var _unscanned_ended: Array[Activation] = []  # activations that ended before any scan, for the next scan
var _found := {}  # each HitEvent of the last scan -> the Activation that made it (see forget)


## Starts a new activation of `hitbox` (a hitbox of the actor's rig) carrying `profile`, one of the `hits` of
## `move`, the move whose mark turned it on. The move is kept with it, so an activation that ends with its move
## inside one tick (a cancel, the clip's end) is still scanned as that move's. A hitbox already on starts afresh:
## a new blow, which may hit what the last one hit. A profile the move does not have is an error, and nothing
## comes on.
func begin(hitbox: StringName, profile: StringName, move: MoveData) -> void:
	var hit_profile: HitProfile = (move.hits.get(profile) as HitProfile) if move != null else null
	if hit_profile == null:
		push_error("HitScanner: %s has no hit profile '%s' for hitbox '%s'" % [move.id if move != null else &"no move", profile, hitbox])
		return
	var activation := Activation.new()
	activation.hitbox = hitbox
	activation.move = move
	activation.profile = hit_profile
	_active[hitbox] = activation


## Ends the activation of `hitbox`, if it is on. One that no scan has seen yet is looked for once more, at the
## next scan.
func end(hitbox: StringName) -> void:
	var activation: Activation = _active.get(hitbox)
	if activation == null:
		return
	_active.erase(hitbox)
	if not activation.scanned:
		_unscanned_ended.append(activation)


## Hands the target of `e`, an event of the last scan, back to the activation that struck it, which may then
## strike it again on a later tick. Melee does this with every blow that came to nothing (a WHIFF: the target
## was invulnerable, or in the air under a LOW blow). An event of an earlier scan, or not of this scanner, is
## left alone.
func forget(e: HitEvent) -> void:
	var activation: Activation = _found.get(e)
	if activation != null:
		activation.hit.erase(e.target)


## The blows `actor`'s hitboxes strike this tick, one HitEvent per body per activation: those of activations
## that ended before any scan first, then those of the live ones, in the order they began. Call it once per
## physics frame, after the rig has posed the body.
func scan(actor: Actor) -> Array[HitEvent]:
	var events: Array[HitEvent] = []
	_found.clear()
	var space := actor.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Layers.HURTBOX
	query.exclude = [actor.rig.hurtbox.get_rid()]
	for activation in _unscanned_ended:
		_sweep(actor, activation, space, query, events)
	_unscanned_ended.clear()
	for activation: Activation in _active.values():
		_sweep(actor, activation, space, query, events)
	return events


# Sweeps `activation`'s hitbox from its last scan to where it is now (or looks only where it is, the first
# time), adding an event for each body it reaches that it has not hit before.
func _sweep(actor: Actor, activation: Activation, space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D,
		events: Array[HitEvent]) -> void:
	var holder := actor.rig.hitbox_shape(activation.hitbox)
	if holder == null or holder.shape == null:
		return
	query.shape = holder.shape
	var to := holder.global_transform
	var from := activation.last if activation.scanned else to
	var steps := 1
	if activation.scanned:
		steps = maxi(ceili(from.origin.distance_to(to.origin) / _step(holder.shape)), 1)
	activation.scanned = true
	activation.last = to
	for i in range(1, steps + 1):
		query.transform = from.interpolate_with(to, float(i) / steps)
		for found in space.intersect_shape(query, MAX_RESULTS):
			var area := found.get("collider") as Area3D
			var target: Actor = (area.get_meta(&"actor", null) as Actor) if area != null else null
			if target == null or target == actor or target.def.team == actor.def.team or activation.hit.has(target):
				continue
			activation.hit[target] = true
			var e := _event(actor, target, activation, query.transform.origin)
			_found[e] = activation
			events.append(e)


func _event(actor: Actor, target: Actor, activation: Activation, point: Vector3) -> HitEvent:
	var e := HitEvent.new()
	e.attacker = actor
	e.target = target
	e.move = activation.move
	e.profile = activation.profile
	e.hitbox = activation.hitbox
	e.point = point
	var flat := target.global_position - actor.global_position
	flat.y = 0.0
	if flat.is_zero_approx():
		flat = Vector3(actor.facing().x, 0.0, actor.facing().z)
	e.direction = flat.normalized()
	return e


# How far apart the steps of a sweep may be for `shape`: half its radius (the half-width of a box).
static func _step(shape: Shape3D) -> float:
	var radius := 0.0
	if shape is SphereShape3D:
		radius = (shape as SphereShape3D).radius
	elif shape is CapsuleShape3D:
		radius = (shape as CapsuleShape3D).radius
	elif shape is CylinderShape3D:
		radius = (shape as CylinderShape3D).radius
	elif shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		radius = minf(size.x, minf(size.y, size.z)) / 2.0
	return radius / 2.0 if radius > 0.0 else DEFAULT_STEP
