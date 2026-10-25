class_name CameraRig
extends Node3D
## The game camera: a fixed three-quarter orthographic view that follows a target, rounded to the
## texel grid so the picture moves in whole pixels, with the rounding handed to the PixelStage.
##
## Put it inside the PixelStage's World viewport. The node itself sits at the smoothed follow point
## (not snapped); its Camera3D child is at DISTANCE behind it and is the snapped one.
## Physics interpolation is off here: the rig moves in _process and follows the target's
## interpolated transform, so the picture is smooth at any frame rate.

const PITCH_DEG := -40.0
const YAW_DEG := 0.0
const DISTANCE := 20.0
## Orthographic size in metres: the height of the World image (360 px plus the margin on both sides)
## at 32 texels per metre, which is 11.3125. That makes one texel exactly one pixel. The 11.25 m of
## the 360 px picture alone would make a texel 1.0056 px on the 362 px image, and the snap grid
## and the pixel grid would drift apart.
const ORTHO_SIZE := (PixelSnap.INTERNAL.y + 2 * PixelSnap.MARGIN) * PixelSnap.TEXEL
## Spring rate: the follow closes `1 - exp(-delta * SPRING_RATE / smooth_time)` of the gap each frame.
## Close enough to a critically damped spring; tune later.
const SPRING_RATE := 4.0
## A target moving at this speed (m/s) or faster gets the whole `look_ahead`.
const LOOK_AHEAD_FULL_SPEED := 4.0

@export var target: Node3D
## Seconds the follow takes to settle, roughly.
@export var smooth_time := 0.15
## Metres the camera leans along the target's velocity at full speed.
@export var look_ahead := 0.8

## Receives the sub-pixel offset each frame.
var stage: PixelStage
var camera: Camera3D

var _follow := Vector3.ZERO
var _has_follow := false


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHO_SIZE
	camera.near = 0.1
	camera.far = 100.0
	add_child(camera)


func _ready() -> void:
	# Set here, not in _init, so a transform stored in a scene cannot change the view.
	rotation = Vector3(deg_to_rad(PITCH_DEG), deg_to_rad(YAW_DEG), 0.0)
	camera.make_current()


## The camera's turn about the vertical axis, in radians. Movement input is rotated by this to
## be relative to the screen.
func yaw() -> float:
	return global_rotation.y


## Goes straight to the target with no easing, for spawns and tests. If the target was just
## moved there, call its reset_physics_interpolation() first.
func snap_now() -> void:
	if target == null or not target.is_inside_tree() or not is_inside_tree():
		return
	_follow = _goal()
	_has_follow = true
	_apply()


func _process(delta: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var goal := _goal()
	if _has_follow:
		_follow += (goal - _follow) * _spring_factor(delta)
	else:
		_follow = goal
		_has_follow = true
	_apply()


func _spring_factor(delta: float) -> float:
	if smooth_time <= 0.0:
		return 1.0
	return 1.0 - exp(-delta * SPRING_RATE / smooth_time)


# Where the camera wants to look: the target's interpolated position, leaning along its velocity.
func _goal() -> Vector3:
	var goal := target.get_global_transform_interpolated().origin
	var velocity: Variant = target.get(&"velocity")
	if velocity is Vector3:
		var speed := (velocity as Vector3).length()
		if speed > 0.0:
			goal += (velocity as Vector3) / speed * look_ahead * clampf(speed / LOOK_AHEAD_FULL_SPEED, 0.0, 1.0)
	return goal


func _apply() -> void:
	global_position = _follow
	var b := global_basis
	var wanted := _follow + b.z * DISTANCE
	camera.global_position = PixelSnap.snap(wanted, b)
	if is_instance_valid(stage):
		stage.subpixel = PixelSnap.subpixel(wanted, b)
