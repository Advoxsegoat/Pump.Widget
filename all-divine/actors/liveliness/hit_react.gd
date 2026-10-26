class_name HitReact
extends SkeletonModifier3D
## The body gives under a blow. react() kicks the upper body away from the hit: a blow from in front
## tips it back, one from the left rolls it to the right. A spring-damper (stiffness 180, damping 14 per
## unit of lean) brings it back: it peaks about 0.09 s after the kick, sways a little past upright, and has
## settled by 0.6 s. The lean is shared up the spine (spine_01 0.3, spine_02 0.3, spine_03 0.2, neck_01 0.1,
## Head 0.1), each bone turning about the same axis across the lean, so the head carries all of it and the
## hips none. Kicks add up, so a flurry stacks.
##
## It runs as part of the rig's tick (Rig.hit_react starts one).

const STIFFNESS := 180.0
const DAMPING := 14.0
## Radians per second of lean speed for a kick of strength 1.
const KICK := 6.0
const BONES: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03", &"neck_01", &"Head"]
const SHARES: Array[float] = [0.3, 0.3, 0.2, 0.1, 0.1]
## The spring's longest integration step, in seconds: a longer tick is cut into steps no longer than this.
const MAX_STEP := 1.0 / 60.0
## A lean and lean speed both below this (radians, radians per second) are at rest.
const REST := 1e-5

## Which way the upper body leans and how far, in radians, on the ground plane of the skeleton's space:
## x toward the body's left (+X), y toward its front (+Z).
var tilt := Vector2.ZERO
## How fast the lean is changing, in radians per second, in the same axes.
var tilt_velocity := Vector2.ZERO

var _skeleton: Skeleton3D  # the skeleton the bones below were found in
var _bones := PackedInt32Array()


## A blow travelling along `dir_world` (a world direction: from the striker through the body) with
## `strength` (1 is an ordinary hit): adds a lean speed of KICK × strength along the direction's part across
## the ground, in the body's own space. A direction with nothing across the ground (none, or straight
## down) does nothing.
func react(dir_world: Vector3, strength: float) -> void:
	var skeleton := get_skeleton()
	var to_body := Quaternion.IDENTITY
	if skeleton != null and skeleton.is_inside_tree():
		to_body = skeleton.global_basis.get_rotation_quaternion().inverse()
	var dir_local := to_body * dir_world
	var kick := Vector2(dir_local.x, dir_local.z) * strength * KICK
	if kick.is_finite():
		tilt_velocity += kick


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if skeleton != _skeleton:
		_skeleton = skeleton
		_bones = BoneTurn.find(skeleton, BONES)
	_spring(delta)
	var lean := tilt.length()
	if lean < REST:
		return
	# Turning about this axis tips a bone's top toward (tilt.x, 0, tilt.y).
	var axis := Vector3(tilt.y, 0.0, -tilt.x) / lean
	for i in _bones.size():
		BoneTurn.about_skeleton_axis(skeleton, _bones[i], axis, lean * SHARES[i])


# Moves the spring on by `delta` seconds (semi-implicit Euler, in steps of at most MAX_STEP).
func _spring(delta: float) -> void:
	if delta <= 0.0:
		return
	var steps := maxi(ceili(delta / MAX_STEP - 1e-6), 1)
	var h := delta / steps
	for i in steps:
		tilt_velocity += (-STIFFNESS * tilt - DAMPING * tilt_velocity) * h
		tilt += tilt_velocity * h
	if tilt.length() < REST and tilt_velocity.length() < REST:
		tilt = Vector2.ZERO
		tilt_velocity = Vector2.ZERO
