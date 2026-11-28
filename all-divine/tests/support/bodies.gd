class_name Bodies
extends RefCounted
## A rough model of an actor's body for tests that check how two bodies meet (a paired move's blows, and that neither
## passes through the other): a capsule along each bone of the torso, head and limbs, in the pose the rig shows
## (Rig.shown_pose). The torso is 0.13 m in radius, the head 0.10 m, the limbs thinner. A capsule is
## [name, from, to, radius], named after the bone it starts at.

## [from bone, to bone (or "" to run `length` along the bone's +Y), radius, length].
const CAPSULES := [
	["pelvis", "spine_01", 0.13, 0.0], ["spine_01", "spine_02", 0.13, 0.0], ["spine_02", "spine_03", 0.13, 0.0],
	["spine_03", "neck_01", 0.12, 0.0], ["Head", "", 0.10, 0.2],
	["upperarm_l", "lowerarm_l", 0.055, 0.0], ["lowerarm_l", "hand_l", 0.045, 0.0], ["hand_l", "middle_04_leaf_l", 0.04, 0.0],
	["upperarm_r", "lowerarm_r", 0.055, 0.0], ["lowerarm_r", "hand_r", 0.045, 0.0], ["hand_r", "middle_04_leaf_r", 0.04, 0.0],
	["thigh_l", "calf_l", 0.075, 0.0], ["calf_l", "foot_l", 0.055, 0.0], ["foot_l", "ball_leaf_l", 0.045, 0.0],
	["thigh_r", "calf_r", 0.075, 0.0], ["calf_r", "foot_r", 0.055, 0.0], ["foot_r", "ball_leaf_r", 0.045, 0.0],
]
## Where a blow lands: the head and the torso above the pelvis (the chest, the spine, the upper abdomen).
const TARGETS: Array[String] = ["spine_01", "spine_02", "spine_03", "Head"]


## The capsules of `rig` in the pose its last tick showed.
static func of(rig: Rig) -> Array:
	var out := []
	for c: Array in CAPSULES:
		var start := rig.shown_pose(StringName(c[0]))
		var end: Vector3 = rig.bone_global(StringName(c[1])) if c[1] != "" else start.origin + start.basis.y.normalized() * float(c[3])
		out.append([c[0], start.origin, end, float(c[2])])
	return out


## How deep the deepest overlap between a capsule of `a` and one of `b` is, in metres (negative: the nearest two are
## that far apart): [depth, a's capsule, b's capsule].
static func overlap(a: Array, b: Array) -> Array:
	var worst := [-INF, "", ""]
	for p: Array in a:
		for q: Array in b:
			var depth: float = p[3] + q[3] - segment_distance(p[1], p[2], q[1], q[2])
			if depth > worst[0]:
				worst = [depth, p[0], q[0]]
	return worst


## The gap from the capsule `hand` of `striker` (hand_l or hand_r: the hand to the fingertips) to the nearest of
## `target`'s TARGETS, in metres; negative is how far inside it the hand is: [gap, the target capsule].
static func strike_gap(striker: Array, target: Array, hand: String) -> Array:
	var fist: Array = striker.filter(func(c: Array) -> bool: return c[0] == hand)[0]
	var best := [INF, ""]
	for q: Array in target:
		if not TARGETS.has(q[0]):
			continue
		var gap: float = segment_distance(fist[1], fist[2], q[1], q[2]) - fist[3] - q[3]
		if gap < best[0]:
			best = [gap, q[0]]
	return best


## The least distance between the segments p0-p1 and q0-q1.
static func segment_distance(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> float:
	var d1 := p1 - p0
	var d2 := q1 - q0
	var r := p0 - q0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return p0.distance_to(q0)
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-12 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p0 + d1 * s).distance_to(q0 + d2 * t)
