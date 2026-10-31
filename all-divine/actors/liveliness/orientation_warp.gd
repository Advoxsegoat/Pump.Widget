class_name OrientationWarp
extends SkeletonModifier3D
## Eight-way locomotion from forward-only clips. When the actor moves at an angle to the way it faces (it
## keeps facing a target while it circles it, say), the hips turn toward the way it goes and the spine turns
## back by as much, so the legs run the forward cycle along the path while the chest stays on the facing.
## Past 110° the rig plays the cycle in reverse and the hips turn toward the opposite of the path: a
## backpedal (see solve).
##
## The rig sets `angle` and `backward` (Rig.set_strafe, which holds the direction it had within a band
## either side of 110°, so noise at the threshold does not flip it) and runs this as part of its tick. The hips do not jump to the
## solved warp: they ease toward it over `ease_time`, so a flick of the stick, or the switch to a backpedal,
## swivels them rather than snapping them round. The rig fades the whole warp out while a move plays (its
## influence is 1 minus the move layer's weight), since a move's clip poses the whole body.

## How far from facing the path can be and still play the cycle forward.
const BACKWARD_FROM_DEG := 110.0
## The hips turn by the warp; these turn back by their share of it, from the bottom up, and the shares add
## up to the whole warp, so the chest ends where it started.
const HIPS := &"pelvis"
const SPINE: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
const SPINE_SHARES: Array[float] = [0.4, 0.3, 0.3]

## The most the hips turn from the facing, either way.
@export var max_angle_deg := 70.0
## Seconds for the hips to close about two thirds of the gap to a new warp; 0 turns them at once.
@export var ease_time := 0.05

## The way the actor moves relative to the way it faces, in radians about up (positive turns +Z toward
## +X); solve wraps it to -PI to PI.
var angle := 0.0
## Whether the cycle plays backward, so that the hips turn toward the opposite of the path (see warp_for).
var backward := false
## The warp the hips show now, in radians: it eases toward solve(angle, max_angle).warp.
var current := 0.0

var _skeleton: Skeleton3D  # the skeleton the bones below were found in
var _hips := -1
var _spine := PackedInt32Array()


## The hips' turn from the facing (`warp`, radians about up) and whether the cycle plays backward, for a
## path `angle` radians from the facing. Up to 110° either way it plays forward, with the hips turned
## toward the path as far as max_angle; past that it plays backward, with the hips turned toward the
## opposite of the path, again as far as max_angle.
static func solve(angle: float, max_angle: float) -> Dictionary:
	var back := absf(wrapf(angle, -PI, PI)) > deg_to_rad(BACKWARD_FROM_DEG)
	return {warp = warp_for(angle, max_angle, back), backward = back}


## The hips' turn from the facing for a path `angle` radians from it, with the cycle playing forward or
## `backward`: toward the path, or toward its opposite, as far as max_angle either way.
static func warp_for(angle: float, max_angle: float, backward: bool) -> float:
	var toward := angle - PI if backward else angle
	return clampf(wrapf(toward, -PI, PI), -max_angle, max_angle)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if skeleton != _skeleton:
		_skeleton = skeleton
		_hips = skeleton.find_bone(HIPS)
		_spine = BoneTurn.find(skeleton, SPINE)
	var goal := warp_for(angle, deg_to_rad(max_angle_deg), backward)
	current = goal if ease_time <= 0.0 else goal + (current - goal) * exp(-delta / ease_time)
	BoneTurn.about_skeleton_axis(skeleton, _hips, Vector3.UP, current)
	for i in _spine.size():
		BoneTurn.about_skeleton_axis(skeleton, _spine[i], Vector3.UP, -current * SPINE_SHARES[i])
