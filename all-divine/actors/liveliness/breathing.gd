class_name Breathing
extends SkeletonModifier3D
## Breath. The chest rises and falls over whatever the clips are doing: spine_02 pitches back on the
## in-breath and forward on the out-breath by amplitude_deg × sin(phase), spine_03 adds 0.6 of that, and the
## clavicles lift by 0.5 of it, each about its own axis. The breath is slow at rest (idle_rate_hz) and quicker
## with exertion (max_rate_hz at 1), and exertion fades back to rest over six seconds. The actor exerts
## its body while it sprints (Rig.set_exertion).
##
## It runs as part of the rig's tick, so the phase moves on by exactly the tick's delta.

const IDLE_RATE_HZ := 0.25
const MAX_RATE_HZ := 0.6
## Seconds for exertion to fade from 1 to 0.
const RECOVERY_TIME := 6.0
const CHEST := &"spine_02"
const UPPER_CHEST := &"spine_03"
const CLAVICLES: Array[StringName] = [&"clavicle_l", &"clavicle_r"]
## spine_03's and the clavicles' share of spine_02's pitch.
const UPPER_CHEST_SHARE := 0.6
const CLAVICLE_SHARE := 0.5

## Breaths per second at rest and fully exerted.
@export var idle_rate_hz := IDLE_RATE_HZ
@export var max_rate_hz := MAX_RATE_HZ
## How far spine_02 pitches at the top and bottom of a breath, in degrees.
@export var amplitude_deg := 1.5

## 0 at rest to 1 out of breath; it falls by delta / 6 every tick.
var exertion := 0.0
## Where the breath is, in radians: 0 is mid-breath on the way in, PI / 2 the top, 3 PI / 2 the bottom.
var phase := 0.0

var _skeleton: Skeleton3D  # the skeleton the bones and axes below were found in
var _chest := -1
var _upper_chest := -1
var _clavicles := PackedInt32Array()
var _pitch_axes: Array[Vector3] = []  # chest, upper chest: each bone's own axis across the body
var _lift_axes: Array[Vector3] = []  # per clavicle: its own axis that raises its outer end


## Breaths per second at `exertion` (0 to 1): from the idle rate to the maximum, in a straight line.
static func rate(exertion: float, idle_hz := IDLE_RATE_HZ, max_hz := MAX_RATE_HZ) -> float:
	return lerpf(idle_hz, max_hz, clampf(exertion, 0.0, 1.0))


## The phase `delta` seconds after `phase`, breathing at rate(exertion): within 0 to TAU.
static func step(phase: float, exertion: float, delta: float, idle_hz := IDLE_RATE_HZ, max_hz := MAX_RATE_HZ) -> float:
	return fposmod(phase + TAU * rate(exertion, idle_hz, max_hz) * delta, TAU)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if skeleton != _skeleton:
		_find_bones(skeleton)
	phase = step(phase, exertion, delta, idle_rate_hz, max_rate_hz)
	exertion = maxf(exertion - delta / RECOVERY_TIME, 0.0)
	var pitch := deg_to_rad(amplitude_deg) * sin(phase)
	# About the body's right, a positive angle tips a bone's top back: the in-breath opens the chest.
	BoneTurn.about_own_axis(skeleton, _chest, _pitch_axes[0], pitch)
	BoneTurn.about_own_axis(skeleton, _upper_chest, _pitch_axes[1], pitch * UPPER_CHEST_SHARE)
	for i in _clavicles.size():
		BoneTurn.about_own_axis(skeleton, _clavicles[i], _lift_axes[i], pitch * CLAVICLE_SHARE)


func _find_bones(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_chest = skeleton.find_bone(CHEST)
	_upper_chest = skeleton.find_bone(UPPER_CHEST)
	_pitch_axes = [Vector3.RIGHT, Vector3.RIGHT]
	for i in 2:
		var bone := _chest if i == 0 else _upper_chest
		if bone >= 0:
			_pitch_axes[i] = BoneTurn.rest_axis(skeleton, bone, Vector3.MODEL_RIGHT)
	_clavicles = BoneTurn.find(skeleton, CLAVICLES)
	_lift_axes.clear()
	for bone in _clavicles:
		_lift_axes.append(_lift_axis(skeleton, bone))


# The clavicle's own axis that, turned about by a positive angle, raises its outer end: across its length
# and the skeleton's up (outward × up), as it lies at rest. Its length runs to its first child, the
# upper arm.
static func _lift_axis(skeleton: Skeleton3D, bone: int) -> Vector3:
	if bone < 0:
		return Vector3.RIGHT
	var rest := skeleton.get_bone_global_rest(bone)
	var children := skeleton.get_bone_children(bone)
	var outward := rest.basis.y
	if not children.is_empty():
		outward = skeleton.get_bone_global_rest(children[0]).origin - rest.origin
	var across := outward.cross(Vector3.UP)
	if across.is_zero_approx():
		return Vector3.RIGHT
	return BoneTurn.rest_axis(skeleton, bone, across.normalized())
