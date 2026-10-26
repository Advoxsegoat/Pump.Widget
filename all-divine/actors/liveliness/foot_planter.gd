class_name FootPlanter
extends SkeletonModifier3D
## Feet on uneven ground: slopes, steps, the edge of a ledge. Over the clips' pose, each foot is moved up or
## down to the ground found below it, the hips drop as far as the lower foot needs, and the two TwoBoneIK3Ds
## that run next bend each leg to put its foot there. This modifier only says where: it drops the hips and
## places the IK targets (and the poles, ahead of the knees).
##
## `ground` holds what the actor's foot probes found under each foot (Rig.set_foot_ground): {position,
## normal} in the world, or null where the ray found nothing. In the skeleton's space, whose y = 0 is the
## floor the actor stands on:
##   - a foot the clip has planted (its ankle no higher than ankle_height) is offset by
##     ground.y + ankle_height - its animated y, which stands it on the ground;
##   - a foot the clip lifts higher is stepping, and keeps its lift over the ground below it: its offset
##     is ground.y. So on flat ground nothing moves, and a stride is the clip's own.
## The hips drop by min(offsets, 0), no further than max_drop. Each IK target is the animated foot plus
## that foot's offset; the drop is what lets the lower foot reach it. A foot with no ground blends its
## offset to 0, and so do both while `planting` is off (the rig turns it off while the body is airborne).
## Every offset is smoothed: each tick it closes 1 - e^(-blend_speed * delta) of its gap.
##
## The IK bends a leg at the hip and knee and carries the foot with the calf, which would tip the toes
## down on a step. So each foot is turned back by the turn the IK gave its calf on the tick before, which
## keeps the angle the clip gave it, and a planted foot is tilted to the ground's normal (at most
## MAX_TILT_DEG). The calf's turn changes little from one tick to the next, so a tick late is near enough.

const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const CALVES: Array[StringName] = [&"calf_l", &"calf_r"]
const HIPS := &"pelvis"
## How far ahead of each knee its pole is placed, along the knee's forward (its calf's -Z).
const POLE_DISTANCE := 0.5
## The most a foot is tilted to the ground under it, in degrees.
const MAX_TILT_DEG := 30.0
## Over how much lift above ankle_height a foot's tilt to the ground fades out, in metres.
const TILT_FADE := 0.1

## What is under each foot: {position: Vector3, normal: Vector3} in the world, or null.
var ground := {&"foot_l": null, &"foot_r": null}
## The furthest the hips drop, in metres.
@export var max_drop := 0.45
## How quickly offsets follow the ground: per second.
@export var blend_speed := 12.0
## How high the ankle (the foot bone) stands over the ground when the foot is flat on it, in metres.
@export var ankle_height := 0.08
## The TwoBoneIK3Ds' targets and poles, which this places every tick.
@export var target_l: Node3D
@export var target_r: Node3D
@export var pole_l: Node3D
@export var pole_r: Node3D

## False while the body is in the air: the offsets fade to 0, as for a foot with no ground.
var planting := true
## Each foot's offset, in metres up (smoothed).
var offsets := {&"foot_l": 0.0, &"foot_r": 0.0}
## How far the hips are dropped, in metres up (0 or less).
var pelvis_offset := 0.0
## Where each foot was in the pose this modifier was given on its last run (the clips' and the modifiers'
## before it), in the skeleton's space: the actor's probes look below it.
var animated := {}

var _skeleton: Skeleton3D  # the skeleton the bones below were found in
var _feet := PackedInt32Array()
var _calves := PackedInt32Array()
var _hips := -1
var _normals: Array[Vector3] = [Vector3.UP, Vector3.UP]  # each foot's ground normal, smoothed, skeleton space
var _calf_before: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]  # this tick, before the IK
var _calf_turn: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]  # what the IK did, last tick
var _ran := false  # whether this ran since the skeleton last finished an update


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if skeleton != _skeleton:
		_find_bones(skeleton)
	if _hips < 0 or _feet.has(-1) or _calves.has(-1):
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var keep := exp(-blend_speed * maxf(delta, 0.0))
	var poses: Array[Transform3D] = []
	for i in 2:
		var foot := FEET[i]
		var pose := skeleton.get_bone_global_pose(_feet[i])
		poses.append(pose)
		animated[foot] = pose.origin
		var goal := 0.0
		var lowest := -INF  # the least offset that keeps the ankle out of the ground
		var normal_goal := Vector3.UP
		var hit: Variant = ground[foot]
		if planting and hit is Dictionary:
			var under: Vector3 = to_skeleton * (hit.position as Vector3)
			lowest = under.y + ankle_height - pose.origin.y
			goal = under.y + ankle_height - minf(pose.origin.y, ankle_height)
			normal_goal = (to_skeleton.basis * (hit.normal as Vector3)).normalized()
		offsets[foot] = maxf(goal + (float(offsets[foot]) - goal) * keep, lowest)
		_normals[i] = normal_goal.lerp(_normals[i], keep).normalized()
	pelvis_offset = clampf(minf(minf(offsets[FEET[0]], offsets[FEET[1]]), 0.0), -max_drop, 0.0)
	_drop_hips(skeleton)
	var targets: Array[Node3D] = [target_l, target_r]
	var poles: Array[Node3D] = [pole_l, pole_r]
	for i in 2:
		var lifted := (poses[i].origin.y - ankle_height) / TILT_FADE
		_turn_foot(skeleton, i, poses[i], clampf(1.0 - lifted, 0.0, 1.0))
		if targets[i] != null:
			targets[i].global_position = skeleton.global_transform * (poses[i].origin + Vector3.UP * float(offsets[FEET[i]]))
		if poles[i] != null:
			var knee := skeleton.get_bone_global_pose(_calves[i])
			poles[i].global_position = skeleton.global_transform * (knee.origin - knee.basis.z.normalized() * POLE_DISTANCE)
	_ran = true


# Moves the hips down by pelvis_offset, in the skeleton's up.
func _drop_hips(skeleton: Skeleton3D) -> void:
	if is_zero_approx(pelvis_offset):
		return
	var parent := skeleton.get_bone_parent(_hips)
	var to_parent := Basis.IDENTITY
	if parent >= 0:
		to_parent = skeleton.get_bone_global_pose(parent).basis.inverse()
	skeleton.set_bone_pose_position(_hips, skeleton.get_bone_pose_position(_hips) + to_parent * Vector3(0, pelvis_offset, 0))


# Gives foot `i` the local rotation that, once the IK has turned its calf as it did last tick, shows it at
# the angle the clip gave it (`pose`), tilted to its ground by `planted` (0 to 1) of the ground's slope.
func _turn_foot(skeleton: Skeleton3D, i: int, pose: Transform3D, planted: float) -> void:
	var tilt := Quaternion.IDENTITY
	if _normals[i].y > 0.1:  # ground facing up at all (rays cast down only find such)
		tilt = Quaternion(Vector3.UP, _normals[i])
	var most := deg_to_rad(MAX_TILT_DEG)
	if tilt.get_angle() > most:
		tilt = Quaternion.IDENTITY.slerp(tilt, most / tilt.get_angle())
	var wanted := Quaternion.IDENTITY.slerp(tilt, planted) * pose.basis.get_rotation_quaternion()
	var calf := skeleton.get_bone_global_pose(_calves[i]).basis.get_rotation_quaternion()
	_calf_before[i] = calf
	var shown_calf := _calf_turn[i] * calf
	skeleton.set_bone_pose_rotation(_feet[i], (shown_calf.inverse() * wanted).normalized())


# Once the skeleton has run every modifier: how the IK turned each calf, for the next tick.
func _on_skeleton_updated() -> void:
	if not _ran or _skeleton == null:
		return
	_ran = false
	for i in 2:
		var after := _skeleton.get_bone_global_pose(_calves[i]).basis.get_rotation_quaternion()
		_calf_turn[i] = (after * _calf_before[i].inverse()).normalized()


func _find_bones(skeleton: Skeleton3D) -> void:
	if _skeleton != null and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
	_skeleton = skeleton
	_feet = BoneTurn.find(skeleton, FEET)
	_calves = BoneTurn.find(skeleton, CALVES)
	_hips = skeleton.find_bone(HIPS)
	_calf_turn = [Quaternion.IDENTITY, Quaternion.IDENTITY]
	skeleton.skeleton_updated.connect(_on_skeleton_updated)
