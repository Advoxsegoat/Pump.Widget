class_name CameraRig
extends Node3D
## The game camera: a fixed three-quarter orthographic view that follows a target, rounded to the
## texel grid so the picture moves in whole pixels, with the rounding handed to the PixelStage.
##
## Put it inside the PixelStage's World viewport. The node itself sits at the smoothed follow point
## (not snapped); its Camera3D child is at DISTANCE behind it and is the snapped one.
## Physics interpolation is off here: the rig moves in _process and follows the target's
## interpolated transform, so the picture is smooth at any frame rate.
##
## Locked on to a foe (lock_target), it leans toward it: the follow goal moves 35% of the way to the foe, at most
## LOCK_LEAN_MAX metres, so that both of them stay well in the picture. The lean is a vector of its own, eased on its
## own critically damped spring (LEAN_RATE), so that gaining, switching and losing a lock, and a target going, glide
## instead of jumping the picture by metres.
##
## A hit shakes it (shake): the offset goes into the place the camera wants to be before that is snapped, so the
## picture shakes in whole texels like everything else it does. The rig joins the group `camera_rig`, where whoever
## shakes it, and Sfx, find it.
##
## Its PostQuad child draws the 3D half of the screen look over everything the camera sees
## (render/shaders/screen_post.gdshader), focused on the target; the PixelStage sets its strengths.

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
## How much of the way to the lock target the follow goal goes...
const LOCK_LEAN := 0.35
## ... and the furthest it goes, in metres.
const LOCK_LEAN_MAX := 3.0
## The lean's spring, in radians a second: it covers 95% of the way in about 0.4 s and settles within a pixel of a
## 3 m lean by 0.8 s (a 6 m cross switch takes a second), and its fastest step, in that switch, is under 10 px a frame.
const LEAN_RATE := 9.0
## How far in metres, along the camera's right and up, a point may be from the follow point and still be in the
## picture (the margin lets a foe's feet, or its head, be a little over the edge).
const ON_SCREEN_MARGIN := 0.75
const POST_SHADER := preload("res://render/shaders/screen_post.gdshader")
## The group the rig joins when it is ready: the one game camera, which hit feel (shake) and sound (Sfx, to find the
## world to play in) look for there.
const GROUP := &"camera_rig"
## The most the picture shakes, in metres along the camera's right and up: the offset at full trauma.
const MAX_SHAKE := 0.25
## Trauma lost a second: a full shake is over in 0.4 s.
const TRAUMA_DECAY := 2.5
## How fast the shake moves through its noise, in noise cells a second: about this many changes of direction a
## second.
const SHAKE_RATE := 16.0
## The noise's seed: the same shake every time.
const SHAKE_SEED := 7
## A ray whose downward slope is less than this (the sine of its angle to the plane) is parallel to the plane.
const PARALLEL := 1e-6

@export var target: Node3D
## The foe the player is locked on to, or null: the follow leans toward it (see the header). One that has left the
## tree or been freed leans nothing.
var lock_target: Node3D
## Seconds the follow takes to settle, roughly.
@export var smooth_time := 0.15
## Metres the camera leans along the target's velocity at full speed.
@export var look_ahead := 0.8

## How much the camera is shaking, 0 to 1 (see shake). The offset is trauma squared times MAX_SHAKE, so a light
## hit is a tremor and a heavy one a lurch.
var trauma := 0.0
## Receives the sub-pixel offset each frame.
var stage: PixelStage
var camera: Camera3D
## The full-screen quad that draws screen_post, in group `post_quad`.
var post_quad: MeshInstance3D

var _lean := Vector3.ZERO
var _lean_velocity := Vector3.ZERO
var _follow := Vector3.ZERO
var _has_follow := false
var _shake_time := 0.0  # seconds this camera has shaken in all: where the noise is
static var _noise: FastNoiseLite


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHO_SIZE
	camera.near = 0.1
	camera.far = 100.0
	add_child(camera)
	post_quad = _make_post_quad()
	add_child(post_quad)


func _ready() -> void:
	# Set here, not in _init, so a transform stored in a scene cannot change the view.
	rotation = Vector3(deg_to_rad(PITCH_DEG), deg_to_rad(YAW_DEG), 0.0)
	add_to_group(GROUP)
	camera.make_current()
	# Joining a stage that already has its look: take it.
	if is_instance_valid(stage) and stage.settings != null:
		stage.apply_settings(stage.settings, stage.grade)


## The camera's turn about the vertical axis, in radians. Movement input is rotated by this to
## be relative to the screen.
func yaw() -> float:
	return global_rotation.y


## How far in front of the camera its target is, along the view: the depth the screen look keeps in
## focus. DISTANCE when there is no target.
func focus_distance() -> float:
	if target == null or not target.is_inside_tree():
		return DISTANCE
	var to_target := target.get_global_transform_interpolated().origin - camera.global_position
	return to_target.dot(-camera.global_basis.z)


## The point of the plane y = `plane_y` that the window point `screen` (a mouse position, in the coordinates of the
## viewport the PixelStage is in) shows, or null if there is no telling: the ray through that pixel of the picture
## runs parallel to the plane (a level camera), or the rig has no stage to say how the window maps onto the picture.
## The stage shows the World image scaled up by a whole number, centred, shifted by what the camera's snap took away
## (PixelStage.world_pixel undoes all that), and the camera's ray through the pixel it comes to is run down to the
## plane. Where the player's cursor is on the ground (at the height of the feet) is where Abarax faces on the
## keyboard and mouse.
func cursor_ground(screen: Vector2, plane_y: float) -> Variant:
	if not is_instance_valid(stage) or not stage.is_inside_tree() or not camera.is_inside_tree():
		return null
	var pixel := stage.world_pixel(screen)
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	if absf(direction.y) < PARALLEL:
		return null
	return origin + direction * ((plane_y - origin.y) / direction.y)


## Goes straight to the target with no easing, for spawns and tests. If the target was just
## moved there, call its reset_physics_interpolation() first.
func snap_now() -> void:
	if target == null or not target.is_inside_tree() or not is_inside_tree():
		return
	_lean = _lean_target(_goal())
	_lean_velocity = Vector3.ZERO
	_follow = _goal()
	_has_follow = true
	_apply()


## Shakes the picture: adds `strength` (a hit's `shake`, 0 to 1) to the trauma, up to 1. The trauma falls by
## TRAUMA_DECAY a second, and while it is above 0 the camera is moved by shake_offset before it is snapped to the
## texel grid, so the picture still moves in whole texels.
func shake(strength: float) -> void:
	trauma = clampf(trauma + maxf(strength, 0.0), 0.0, 1.0)


## How far the shake has the camera from where it would be, in metres along its right and up: shake_at for this
## rig's trauma and moment, times the player's Camera shake setting (Settings.shake_scale).
func shake_offset() -> Vector2:
	return shake_at(trauma, _shake_time) * Settings.shake_scale()


## The shake of `trauma` at `seconds` into a shaking: up to trauma squared times MAX_SHAKE (in length) along smooth
## noise, one noise for the way along the camera's right and another for up.
static func shake_at(trauma_now: float, seconds: float) -> Vector2:
	if trauma_now <= 0.0:
		return Vector2.ZERO
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.seed = SHAKE_SEED
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE  # the default adds finer and finer noise: not smooth
	var at := seconds * SHAKE_RATE
	var direction := Vector2(_noise.get_noise_2d(at, 0.0), _noise.get_noise_2d(at, 37.0))
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction * trauma_now * trauma_now * MAX_SHAKE


func _process(delta: float) -> void:
	if trauma > 0.0:
		# The noise only moves while there is a shake, and carries on where the last one left it, so that each
		# shake sets off in a different way.
		trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
		_shake_time += delta
	if target == null or not target.is_inside_tree():
		return
	_ease_lean(delta)
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


# Where the camera wants to look: the target's interpolated position, leaning along its velocity, and by the lean.
func _goal() -> Vector3:
	return _base_goal() + _lean


func _base_goal() -> Vector3:
	var goal := target.get_global_transform_interpolated().origin
	var velocity: Variant = target.get(&"velocity")
	if velocity is Vector3:
		var speed := (velocity as Vector3).length()
		if speed > 0.0:
			goal += (velocity as Vector3) / speed * look_ahead * clampf(speed / LOOK_AHEAD_FULL_SPEED, 0.0, 1.0)
	return goal


# Where the lean wants to be: LOCK_LEAN of the way from `base` to the lock target, at most LOCK_LEAN_MAX; none with no
# target, or one that has left the tree or been freed.
func _lean_target(base: Vector3) -> Vector3:
	if not is_instance_valid(lock_target) or not lock_target.is_inside_tree():
		return Vector3.ZERO
	return ((lock_target.get_global_transform_interpolated().origin - base) * LOCK_LEAN).limit_length(LOCK_LEAN_MAX)


# Moves the lean toward its target along a critically damped spring (exact for any step, so a slow frame does not
# overshoot).
func _ease_lean(delta: float) -> void:
	var wanted := _lean_target(_base_goal())
	var x := LEAN_RATE * delta
	var damping := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := _lean - wanted
	var carry := (_lean_velocity + change * LEAN_RATE) * delta
	_lean_velocity = (_lean_velocity - carry * LEAN_RATE) * damping
	_lean = wanted + (change + carry) * damping


## Where `world` is on the picture, in metres from its centre along the camera's right (x) and up (y).
func screen_offset(world: Vector3) -> Vector2:
	var rel := world - global_position
	var b := global_basis
	return Vector2(rel.dot(b.x), rel.dot(b.y))


## Whether `world` is in the picture, give or take ON_SCREEN_MARGIN: the 640x360 picture is 20 x 11.25 m.
func on_screen(world: Vector3) -> bool:
	var offset := screen_offset(world)
	var half := Vector2(PixelSnap.INTERNAL) * PixelSnap.TEXEL * 0.5 + Vector2.ONE * ON_SCREEN_MARGIN
	return absf(offset.x) <= half.x and absf(offset.y) <= half.y


func _apply() -> void:
	global_position = _follow
	var b := global_basis
	var shaken := shake_offset()
	var wanted := _follow + b.z * DISTANCE + b.x * shaken.x + b.y * shaken.y
	camera.global_position = PixelSnap.snap(wanted, b)
	if is_instance_valid(stage):
		stage.subpixel = PixelSnap.subpixel(wanted, b)
	(post_quad.material_override as ShaderMaterial).set_shader_parameter(&"focus", focus_distance())


# A 2x2 quad that screen_post's vertex shader stretches over the whole screen (its faces flipped, so that
# its front faces the camera there). It is never culled (its box is grown by the most there is), casts no
# shadow, and is drawn first among the transparent things:
# right after the opaque world, which is what the screen and depth textures hold, and before anything
# transparent, which is then drawn over the look instead of being painted out by it.
static func _make_post_quad() -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	mesh.flip_faces = true
	var material := ShaderMaterial.new()
	material.shader = POST_SHADER
	material.render_priority = Material.RENDER_PRIORITY_MIN
	PixelStage.set_uniforms(material, PixelStage.post_uniforms(RenderSettings.new().off(), GradeProfile.new()))
	var quad := MeshInstance3D.new()
	quad.name = "PostQuad"
	quad.mesh = mesh
	quad.material_override = material
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	quad.add_to_group(&"post_quad")
	return quad
