class_name Afterimage
extends Node3D
## A still copy of a body's silhouette, one flat colour, fading over `frames` frames of its owner's own clock and then freeing
## itself: what a perfect dodge and every dodge at Flurry leave behind (ChainFx; the sway-and-duck spec, section 5).
##
## It is the pose he held when the dodge began (`capture`, taken as the sway or duck starts), put in the world where he stood
## then, and it stays there: the stance he left, where the blow now passes. It ages on its owner's clock, the frames on which he
## acts: a frame on which the slow-down or a hit-stop holds him does not age it, so it hangs through the slow-down and fades
## as he comes back. Its copy is the same meshes on a skeleton of its own held in that pose.
##
## The owner's rule for effects is that nothing tints or covers a body's interior: the copy is drawn with
## render/shaders/afterimage.gdshader, which writes only where no body is (the bodies' stencil), so it is behind every body and
## over none.
##
## `spawn` makes one and adds it to the world the rig's actor is in; the group GROUP holds every one that is alive, for tests.

const SHADER := preload("res://render/shaders/afterimage.gdshader")
## The group every afterimage is in.
const GROUP := &"afterimages"
## The depth-only pass is drawn after every opaque thing and every rim (Rig.RIM_MARK_PRIORITY and the next: -1 and 0), and the colour pass after it.
const DEPTH_PRIORITY := 1
const COLOR_PRIORITY := 2

## How many frames it lives, and how many it has left (of its owner's acting frames; of wall frames, with no owner).
var frames := 12
var left := 12
## Whether it is the unseen one a region draws as it loads, to have its shader built (warm).
var warming := false

var _color := Color.WHITE
var _color_material: ShaderMaterial
var _clock: Actor  # whose acting frames it ages by (Actor.buffer_frame stands still while he is held), or null
var _clock_at := 0
var _skeleton: Skeleton3D


## The pose `rig` shows now, to be copied later: {skeleton: its transform, bones: each bone's transform in skeleton space as shown
## (Rig.shown_pose, the clips' pose with the modifiers over it), meshes: [[the MeshInstance3D, its transform in skeleton space]],
## source: the skeleton}.
static func capture(rig: Rig) -> Dictionary:
	var source := rig.skeleton
	if source == null:
		return {}
	var to_skeleton := source.global_transform.affine_inverse()
	var bones: Array[Transform3D] = []
	for bone in source.get_bone_count():
		bones.append(to_skeleton * rig.shown_pose(source.get_bone_name(bone)))
	var meshes := []
	for node in rig.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.is_visible_in_tree() and mesh.mesh != null:
			meshes.append([mesh, to_skeleton * mesh.global_transform])
	return {skeleton = source.global_transform, bones = bones, meshes = meshes, source = source}


## A copy of `rig`'s body in `color` (its alpha is how solid it starts) that lasts `frames_` frames: of `clock`'s own, if an actor is
## given (the frames it acts on), else wall frames. `pose` is a capture of the stance to copy (the rig's own as it is now, with none).
## It joins the world the rig's actor is in (beside the actor), or the rig's own parent when the rig stands alone. Returns it.
static func spawn(rig: Rig, color: Color, frames_: int, pose := {}, clock: Actor = null) -> Afterimage:
	var image := Afterimage.new()
	image.name = "Afterimage"
	image.frames = maxi(frames_, 1)
	image.left = image.frames
	image._color = color
	image._clock = clock
	if clock != null:
		image._clock_at = clock.buffer_frame
	image.add_to_group(GROUP)
	var home: Node = rig.get_parent()
	if home is Actor and home.get_parent() != null:
		home = home.get_parent()
	home.add_child(image)
	image.global_transform = Transform3D.IDENTITY
	image._copy(pose if not pose.is_empty() else capture(rig))
	return image


## An unseen copy (no opacity) for a few wall frames, drawn with the rims' warming passes as a region loads, so that the afterimage's
## shader is built then and not on the first perfect dodge.
static func warm(rig: Rig, wall_frames: int) -> Afterimage:
	var image := spawn(rig, Color(1.0, 1.0, 1.0, 0.0), wall_frames)
	image.warming = true
	return image


## Where bone `name` of the copy is in the world.
func bone_global(bone: StringName) -> Vector3:
	if _skeleton == null:
		return Vector3.ZERO
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))).origin


## How much of the copy shows now, 0 to 1: all of it when it is made, less each frame, none on its last.
func alpha() -> float:
	return clampf(float(left) / float(frames), 0.0, 1.0)


func _physics_process(_delta: float) -> void:
	if _clock != null and is_instance_valid(_clock):
		left -= _clock.buffer_frame - _clock_at
		_clock_at = _clock.buffer_frame
	else:
		left -= 1
	if left <= 0:
		queue_free()
		return
	_color_material.set_shader_parameter(&"strength", alpha())


# The captured pose's meshes on a skeleton of their own, held in that pose, with the two passes over them. Nothing of the actor is
# copied but what is drawn: no hurtbox, hitbox or modifier comes with it, and no tree of the actor's runs in it.
func _copy(pose: Dictionary) -> void:
	var depth := ShaderMaterial.new()
	depth.shader = SHADER
	depth.render_priority = DEPTH_PRIORITY
	depth.set_shader_parameter(&"depth_only", 1.0)
	_color_material = ShaderMaterial.new()
	_color_material.shader = SHADER
	_color_material.render_priority = COLOR_PRIORITY
	_color_material.set_shader_parameter(&"tint", _color)
	_color_material.set_shader_parameter(&"strength", alpha())
	depth.next_pass = _color_material
	if pose.is_empty():
		return
	var source := pose["source"] as Skeleton3D
	var shown: Array = pose["bones"]
	var copy := Skeleton3D.new()
	copy.name = "Skeleton"
	for bone in source.get_bone_count():
		copy.add_bone(source.get_bone_name(bone))
	for bone in source.get_bone_count():
		var parent := source.get_bone_parent(bone)
		copy.set_bone_parent(bone, parent)
		copy.set_bone_rest(bone, source.get_bone_rest(bone))
		var local: Transform3D = shown[bone] if parent < 0 else (shown[parent] as Transform3D).affine_inverse() * (shown[bone] as Transform3D)
		copy.set_bone_pose_position(bone, local.origin)
		copy.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
		copy.set_bone_pose_scale(bone, local.basis.get_scale())
	add_child(copy)
	copy.global_transform = pose["skeleton"]
	_skeleton = copy
	for entry: Array in pose["meshes"]:
		var mesh := entry[0] as MeshInstance3D
		var shape := MeshInstance3D.new()
		shape.mesh = mesh.mesh
		shape.skin = mesh.skin
		shape.material_override = depth
		shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.add_child(shape)
		shape.skeleton = ^".."
		shape.transform = entry[1]
