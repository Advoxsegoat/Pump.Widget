class_name BoneTurn
extends RefCounted
## Small turns of a bone on top of the pose it already has, for the liveliness modifiers. Each turn is
## made about the bone's own joint, and the bone's children turn with it. The skeleton's space is the
## model's: +Y up, facing +Z (Vector3.MODEL_FRONT), its left +X.


## Turns `bone` by `angle` radians about `axis`, a unit direction in the skeleton's space (up, say), as the
## pose stands now: so two bones in a chain turned about the same axis add up, whatever the clip did.
static func about_skeleton_axis(skeleton: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or is_zero_approx(angle):
		return
	var parent := skeleton.get_bone_parent(bone)
	var frame := Quaternion.IDENTITY
	if parent >= 0:
		frame = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var turn := Quaternion((frame.inverse() * axis).normalized(), angle)
	skeleton.set_bone_pose_rotation(bone, (turn * skeleton.get_bone_pose_rotation(bone)).normalized())


## Turns `bone` by `angle` radians about `axis`, a unit direction in the bone's own space (see rest_axis).
static func about_own_axis(skeleton: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or is_zero_approx(angle):
		return
	skeleton.set_bone_pose_rotation(bone, (skeleton.get_bone_pose_rotation(bone) * Quaternion(axis, angle)).normalized())


## `axis`, a direction in the skeleton's space, as `bone` sees it in its rest pose: the bone's own axis that
## lies along it when the body stands at rest (Vector3.MODEL_RIGHT gives the axis across the body).
static func rest_axis(skeleton: Skeleton3D, bone: int, axis: Vector3) -> Vector3:
	return (skeleton.get_bone_global_rest(bone).basis.get_rotation_quaternion().inverse() * axis).normalized()


## The indices of `names` in `skeleton`, in order; -1 for a bone it does not have.
static func find(skeleton: Skeleton3D, names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in names:
		out.append(skeleton.find_bone(n))
	return out
