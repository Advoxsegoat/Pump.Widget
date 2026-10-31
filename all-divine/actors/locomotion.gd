class_name Locomotion
extends RefCounted
## Souls-feel ground movement, as numbers only (no nodes), so it can be checked frame by frame.
##
## The stick gives a direction and how far it is pushed. The body heads that way at once; its speed
## ramps toward the wanted speed, up by `accel` and down by `decel`; its facing turns toward the heading
## at `turn_rate_deg`. Let go and it slows to a stop along the way it was going, still facing where it
## faced. Directions are world (x, z) Vector2s, and a yaw of 0 faces +Z (Vector3.MODEL_FRONT).

var tuning: LocomotionTuning
## Metres per second along the heading.
var speed := 0.0
## Radians about +Y, within -PI to PI; 0 faces +Z.
var facing_yaw := 0.0
## Whether the last tick sprinted: sprint asked for, with the stick past walk_threshold.
var sprinting := false

var _heading := Vector2.ZERO  # the way the body goes, world (x, z), unit length; zero before any input


func _init(with_tuning: LocomotionTuning = null) -> void:
	tuning = with_tuning


## The speed a stick pushed `m` (0 to 1) asks for: past walk_threshold, a jog, or a sprint if `sprint`;
## below it, a walk that grows with the push, reaching walk_speed at walk_threshold.
func target_speed(m: float, sprint: bool) -> float:
	if m > tuning.walk_threshold:
		return tuning.sprint_speed if sprint else tuning.jog_speed
	return tuning.walk_speed * m / tuning.walk_threshold


## One frame of movement with the stick at `move` (world (x, z), length 0 to 1), sprinting if `sprint`
## and the stick is past walk_threshold. Returns the velocity, in m/s, on the ground plane.
func tick(move: Vector2, sprint: bool, delta: float) -> Vector3:
	var m := minf(move.length(), 1.0)
	sprinting = sprint and m > tuning.walk_threshold
	var target := 0.0
	if m > 0.0:
		_heading = move.normalized()
		target = target_speed(m, sprint)
		facing_yaw = turn_toward(facing_yaw, yaw_of(_heading), deg_to_rad(tuning.turn_rate_deg) * delta)
	speed = move_toward(speed, target, (tuning.accel if target > speed else tuning.decel) * delta)
	# Ten steps of 0.4 leave a few 1e-16 m/s of a 4 m/s jog: that is a stop.
	if is_zero_approx(speed):
		speed = 0.0
	return Vector3(_heading.x, 0.0, _heading.y) * speed


## Takes over a velocity something else gave the body (a move's root motion), so that when locomotion
## runs again it carries on from it: the horizontal speed and its direction. Not a sprint.
func carry(velocity: Vector3) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	speed = flat.length()
	if speed > 0.0:
		_heading = flat / speed
	sprinting = false


## The yaw that faces `dir`, a world (x, z) direction: atan2(x, z), so +Z is 0 and +X is PI / 2.
static func yaw_of(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


## `from` turned toward `to` (radians) the short way, by at most `max_step`, wrapped to -PI to PI.
static func turn_toward(from: float, to: float, max_step: float) -> float:
	return wrapf(from + clampf(angle_difference(from, to), -max_step, max_step), -PI, PI)
