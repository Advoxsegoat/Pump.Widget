class_name ClipMotion
extends RefCounted
## How a clip moves a body, measured on a rig standing at the origin facing +Z, in the clips' pose (Rig.animated_pose:
## the clip without the modifiers over it, and without the root's travel, which the move runner takes as root motion).
## For the checks the owner's first priority asks of every clip (F1 Task 10's staging criteria, carried to the Knuckle):
##   pops   the pelvis and the head move POP_STEP at most from one 12 fps step to the next of a stepped clip (POP_FRAME
##          a frame, in a smooth one); the hands and feet are held to POP_STEP only across a join or crossfade (the clip's
##          `joins` metadata), since the rule is for discontinuities, and a strike or a kick is a fast limb by design
##   reach  the frame a striking bone reaches furthest forward (along +Z): the first step at which it comes within
##          REACH_TIE of its furthest, so a held extension counts from where it arrives

const POP_STEP := 0.25
const POP_FRAME := 0.15
const REACH_TIE := 0.01
const BODY: Array[StringName] = [&"pelvis", &"Head"]
const LIMBS: Array[StringName] = [&"hand_l", &"hand_r", &"foot_l", &"foot_r"]


## The step of `anim` in frames (of 60 a second): 5 for a clip shown at 12 fps, 1 for a smooth one.
static func step_of(anim: Animation) -> int:
	var fps := int(anim.get_meta(&"step_fps", 0))
	return 60 / fps if fps > 0 else 1


## Each frame on `anim`'s step grid -> {joint: where `rig` (at the origin) shows it, in the clips' pose}.
static func poses(rig: Rig, clip: StringName, joints: Array[StringName]) -> Dictionary:
	var anim := rig.tree.get_animation(clip)
	var step := step_of(anim)
	var out := {}
	var f := 0
	while f <= Marks.frame_of(anim.length):
		rig.play_move(clip, 0.0)
		rig.set_move_time(f / 60.0)
		rig.tick(1.0 / 60.0)
		out[f] = {}
		for joint in joints:
			out[f][joint] = rig.animated_pose(joint).origin - rig.global_position
		f += step
	return out


## The worst move of the pelvis or head in `clip`, on any step: [metres, joint, the frame it moves to, the most allowed].
static func worst_pop(rig: Rig, clip: StringName) -> Array:
	return _worst(rig, clip)[0]


## The worst move of a hand or foot across a join of `clip` (none: [0, &"", -1, POP_STEP]), as worst_pop gives it.
static func worst_join(rig: Rig, clip: StringName) -> Array:
	return _worst(rig, clip)[1]


# [worst_pop, worst_join] of `clip`.
static func _worst(rig: Rig, clip: StringName) -> Array:
	var anim := rig.tree.get_animation(clip)
	var step := step_of(anim)
	var joins: PackedFloat32Array = anim.get_meta(&"joins", PackedFloat32Array())
	var at := poses(rig, clip, BODY + LIMBS)
	var body := [0.0, &"", -1, POP_STEP if step > 1 else POP_FRAME]
	var limbs := [0.0, &"", -1, POP_STEP]
	for frame: int in at:
		if not at.has(frame - step):
			continue
		var across := Array(joins).any(func(t: float) -> bool: return t * 60.0 >= frame - step - 1e-3 and t * 60.0 <= frame + 1e-3)
		for joint in BODY:
			var moved: float = (at[frame][joint] as Vector3).distance_to(at[frame - step][joint])
			if moved > body[0]:
				body = [moved, joint, frame, body[3]]
		if not across:
			continue
		for joint in LIMBS:
			var moved: float = (at[frame][joint] as Vector3).distance_to(at[frame - step][joint])
			if moved > limbs[0]:
				limbs = [moved, joint, frame, limbs[3]]
	return [body, limbs]


## The frame `bone` reaches furthest forward in `clip` (see the top of this file), and how far: [frame, metres along +Z].
static func reach_peak(rig: Rig, clip: StringName, bone: StringName) -> Array:
	var at := poses(rig, clip, [bone])
	var furthest := -INF
	for frame: int in at:
		furthest = maxf(furthest, (at[frame][bone] as Vector3).z)
	var frames := at.keys()
	frames.sort()
	for frame: int in frames:
		if (at[frame][bone] as Vector3).z >= furthest - REACH_TIE:
			return [frame, furthest]
	return [-1, furthest]
