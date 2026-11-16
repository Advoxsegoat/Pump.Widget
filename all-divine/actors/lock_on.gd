class_name LockOn
extends RefCounted
## Which foe the player has locked on to, and how it is chosen, switched and lost.
##
## pick chooses along a direction (where the camera looks, or where the stick points): the foe with the smallest
## "angle off that direction in degrees plus four per metre", so a straight-ahead foe a little further off beats a
## nearer one off to the side, but a foe far to the side does not. A foe more than 90 degrees behind is chosen only when
## nothing is in front. next switches to the foe to the right (or left) of the current one on the screen: the camera is
## fixed, so "right" is the picture's right, whichever way the foes lie round the player. Given the camera rig, pick and
## next only take foes in the picture. update lets go of a foe that has died, left the tree or gone too far. It never
## decides anything else: what a lock does to aiming and the camera is the player's brain's business.

## The furthest a foe can be picked from (metres, on the ground).
const PICK_RANGE := 15.0
## The furthest a foe is held from: past this the lock lets go.
const LOSE_RANGE := 20.0
## Degrees of angle that a metre of distance counts for.
const DEGREES_PER_METRE := 4.0
## Metres on the screen that count as no step at all.
const TIE := 0.01

## The foe locked on to, or null.
var target: Actor


## The foe of `candidates` (Actors, in whatever order) to lock on to from `from`, looking along `view_dir` (its height
## is ignored): the live ones within PICK_RANGE (and in the picture, when there is a `rig`), by the smallest
## angle_deg(view_dir, foe) + 4 x distance. A foe more than 90 degrees from view_dir counts only when none is in front.
## Null if there is none (or no list).
static func pick(from: Actor, candidates: Array, view_dir: Vector3, rig: CameraRig = null) -> Actor:
	var view := Vector2(view_dir.x, view_dir.z)
	var best: Actor = null
	var best_behind: Actor = null
	var best_score := INF
	var best_behind_score := INF
	for node: Variant in candidates:
		var foe := _usable(from, node, rig)
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


## The foe to switch to from `current`: of `candidates` (live, within LOSE_RANGE, in the picture when there is a `rig`),
## the nearest to the right of it on the screen (or to the left, if not `right`), by the smallest step along the
## screen's x, the nearer to the player of two the same step off. `current` itself when there is none that way (the
## ends do not wrap round). Without a rig the screen's right is the world's +X, which is what the fixed camera gives.
static func next(from: Actor, current: Actor, candidates: Array, right: bool, rig: CameraRig = null) -> Actor:
	if not is_instance_valid(current):
		return current
	var here := _screen_x(current, rig)
	var way := 1.0 if right else -1.0
	var best: Actor = current
	var best_step := INF
	var best_distance := INF
	for node: Variant in candidates:
		var foe := _usable(from, node, rig)
		if foe == null or foe == current:
			continue
		var distance := _flat(from, foe).length()
		if distance > LOSE_RANGE:
			continue
		var step := (_screen_x(foe, rig) - here) * way
		if step <= TIE:
			continue
		if step < best_step - TIE or (absf(step - best_step) <= TIE and distance < best_distance):
			best = foe
			best_step = step
			best_distance = distance
	return best


## Lets go of the target if it has died, left the tree (or been freed), or is further than LOSE_RANGE from `from`.
func update(from: Actor) -> void:
	if not is_instance_valid(target):
		target = null
		return
	if not target.is_inside_tree() or target.dead \
			or _flat(from, target).length() > LOSE_RANGE:
		target = null


# `node` as a live Actor in the tree that is not `from` (and, with a `rig`, in the picture), else null.
static func _usable(from: Actor, node: Variant, rig: CameraRig) -> Actor:
	if not is_instance_valid(node):
		return null
	var foe := node as Actor
	if foe == null or foe == from or foe.dead or not foe.is_inside_tree():
		return null
	if rig != null and not rig.on_screen(foe.global_position + Vector3.UP):
		return null
	return foe


# The way from `from` to `foe` on the ground, world (x, z).
static func _flat(from: Actor, foe: Actor) -> Vector2:
	return Vector2(foe.global_position.x - from.global_position.x, foe.global_position.z - from.global_position.z)


# How far right of the picture's centre `foe` is, in metres.
static func _screen_x(foe: Actor, rig: CameraRig) -> float:
	return rig.screen_offset(foe.global_position).x if rig != null else foe.global_position.x
