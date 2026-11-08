class_name LockOn
extends RefCounted
## Which foe the player has locked on to, and how it is chosen, switched and lost.
##
## pick chooses along a direction (where the camera looks, or where the stick points): the foe with the smallest
## "angle off that direction in degrees plus four per metre", so a straight-ahead foe a little further off beats a
## nearer one off to the side, but a foe far to the side does not. A foe more than 90 degrees behind is chosen only when
## nothing is in front. next switches to the neighbour round the player, seen from above. update lets go of a foe that
## has died, left the tree or gone too far. It never decides anything else: what a lock does to aiming and the camera
## is the player's brain's business.

## The furthest a foe can be picked from (metres, on the ground).
const PICK_RANGE := 15.0
## The furthest a foe is held from: past this the lock lets go.
const LOSE_RANGE := 20.0
## Degrees of angle that a metre of distance counts for.
const DEGREES_PER_METRE := 4.0

## The foe locked on to, or null.
var target: Actor


## The foe of `candidates` (Actors, in whatever order) to lock on to from `from`, looking along `view_dir` (its height
## is ignored): the live ones within PICK_RANGE, by the smallest angle_deg(view_dir, foe) + 4 x distance. A foe more
## than 90 degrees from view_dir counts only when none is in front. Null if there is none (or no list).
static func pick(from: Actor, candidates: Array, view_dir: Vector3) -> Actor:
	var view := Vector2(view_dir.x, view_dir.z)
	var best: Actor = null
	var best_behind: Actor = null
	var best_score := INF
	var best_behind_score := INF
	for node: Variant in candidates:
		var foe := _usable(from, node)
		if foe == null:
			continue
		var flat := _flat(from, foe)
		var distance := flat.length()
		if distance > PICK_RANGE:
			continue
		var angle := 0.0 if flat.is_zero_approx() or view.is_zero_approx() else rad_to_deg(absf(view.angle_to(flat)))
		var score := angle + DEGREES_PER_METRE * distance
		if angle > 90.0:
			if score < best_behind_score:
				best_behind = foe
				best_behind_score = score
		elif score < best_score:
			best = foe
			best_score = score
	return best if best != null else best_behind


## The neighbour of `current` round `from`, seen from above: the foe of `candidates` (live, within LOSE_RANGE) whose
## bearing is the next one clockwise (or counter-clockwise), the nearer of two on the same bearing. `current` itself
## when there is no other. Bearings run clockwise from -Z (the top of the screen), which is the way a stick flicked
## to the right goes.
static func next(from: Actor, current: Actor, candidates: Array, clockwise: bool) -> Actor:
	var here := _bearing(from, current) if is_instance_valid(current) else 0.0
	var best: Actor = current
	var best_turn := INF
	var best_distance := INF
	for node: Variant in candidates:
		var foe := _usable(from, node)
		if foe == null or foe == current:
			continue
		var distance := _flat(from, foe).length()
		if distance > LOSE_RANGE:
			continue
		var turn := fposmod((_bearing(from, foe) - here) * (1.0 if clockwise else -1.0), TAU)
		if turn < best_turn - 1e-4 or (absf(turn - best_turn) <= 1e-4 and distance < best_distance):
			best = foe
			best_turn = turn
			best_distance = distance
	return best


## Lets go of the target if it has died, left the tree (or been freed), or is further than LOSE_RANGE from `from`.
func update(from: Actor) -> void:
	if target == null:
		return
	if not is_instance_valid(target) or not target.is_inside_tree() or target.dead \
			or _flat(from, target).length() > LOSE_RANGE:
		target = null


# `node` as a live Actor in the tree that is not `from`, else null.
static func _usable(from: Actor, node: Variant) -> Actor:
	if not is_instance_valid(node):
		return null
	var foe := node as Actor
	if foe == null or foe == from or foe.dead or not foe.is_inside_tree():
		return null
	return foe


# The way from `from` to `foe` on the ground, world (x, z).
static func _flat(from: Actor, foe: Actor) -> Vector2:
	return Vector2(foe.global_position.x - from.global_position.x, foe.global_position.z - from.global_position.z)


# The bearing of `foe` from `from`, in radians clockwise (seen from above) from -Z.
static func _bearing(from: Actor, foe: Actor) -> float:
	var flat := _flat(from, foe)
	return atan2(flat.x, -flat.y)
