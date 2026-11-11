class_name Afterimage
extends Node3D
## A still copy of a body's silhouette where it stood, one flat colour, fading over `frames` physics frames and then freeing
## itself: what a perfect dodge and every dodge at Flurry leave behind (ChainFx; the sway-and-duck spec, section 5).
##
## It is the body as the rig shows it this frame (the same meshes on a skeleton of its own held in the pose the rig shows, with the
## modifiers over it), put in the world where the body stands, and it stays there. The owner's rule for effects is that nothing tints or covers a body's
## interior: the copy is drawn with render/shaders/afterimage.gdshader, which writes only where no body is (the bodies' stencil),
## so it is behind every body and over none, and the pose-for-pose copy leaves a shape only around the body that moved on from it.
##
## `spawn` makes one and adds it to the world the rig's actor is in; the group GROUP holds every one that is alive, for tests.

const SHADER := preload("res://render/shaders/afterimage.gdshader")
## The group every afterimage is in.
const GROUP := &"afterimages"
## The depth-only pass is drawn after every opaque thing and every rim (Rig.RIM_MARK_PRIORITY and the next: -1 and 0), and the colour pass after it.
const DEPTH_PRIORITY := 1
const COLOR_PRIORITY := 2

## How many frames it lives, and how many it has left.
var frames := 8
var left := 8

var _color := Color.WHITE
var _color_material: ShaderMaterial


## A copy of `rig`'s body in `color` (its alpha is how solid it starts) that lasts `frames` frames. It joins the world the rig's actor
## is in (beside the actor), or the rig's own parent when the rig stands alone. Returns it.
static func spawn(rig: Rig, color: Color, frames_: int) -> Afterimage:
	var image := Afterimage.new()
	image.name = "Afterimage"
	image.frames = maxi(frames_, 1)
	image.left = image.frames
	image._color = color
	image.add_to_group(GROUP)
	var home: Node = rig.get_parent()
	if home is Actor and home.get_parent() != null:
		home = home.get_parent()
	home.add_child(image)
	image.global_transform = Transform3D.IDENTITY
	image._copy(rig)
	return image


## How much of the copy shows now, 0 to 1: all of it when it is made, less each frame, none on its last.
func alpha() -> float:
	return clampf(float(left) / float(frames), 0.0, 1.0)


func _physics_process(_delta: float) -> void:
	left -= 1
	if left <= 0:
		queue_free()
		return
	_color_material.set_shader_parameter(&"strength", alpha())


# The body's meshes on a skeleton of their own, held in the pose the rig shows (Rig.shown_pose: the clips' pose with the modifiers
# over it, as the skin draws it), with the two passes over them. Nothing of the actor is copied but what is drawn: no hurtbox,
# hitbox or modifier comes with it, and no tree of the actor's runs in it.
func _copy(rig: Rig) -> void:
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
	var source := rig.skeleton
	if source == null:
		return
	var copy := Skeleton3D.new()
	copy.name = "Skeleton"
	for bone in source.get_bone_count():
		copy.add_bone(source.get_bone_name(bone))
	var to_skeleton := source.global_transform.affine_inverse()
	var shown: Array[Transform3D] = []  # each bone in skeleton space, as it is shown
	for bone in source.get_bone_count():
		shown.append(to_skeleton * rig.shown_pose(source.get_bone_name(bone)))
	for bone in source.get_bone_count():
		var parent := source.get_bone_parent(bone)
		copy.set_bone_parent(bone, parent)
		copy.set_bone_rest(bone, source.get_bone_rest(bone))
		var local := shown[bone] if parent < 0 else shown[parent].affine_inverse() * shown[bone]
		copy.set_bone_pose_position(bone, local.origin)
		copy.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
		copy.set_bone_pose_scale(bone, local.basis.get_scale())
	add_child(copy)
	copy.global_transform = source.global_transform
	for node in rig.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var shape := MeshInstance3D.new()
		shape.mesh = mesh.mesh
		shape.skin = mesh.skin
		shape.material_override = depth
		shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.add_child(shape)
		shape.skeleton = ^".."
		shape.transform = to_skeleton * mesh.global_transform
