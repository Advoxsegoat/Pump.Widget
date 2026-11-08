class_name ClipMotion
extends RefCounted
## How a clip moves a body, measured on a rig standing at the origin facing +Z, in the clips' pose (Rig.animated_pose:
## the clip without the modifiers over it, and without the root's travel, which the move runner takes as root motion).
## For the checks the owner's first priority asks of every clip (F1 Task 10's staging criteria, carried to the Knuckle):
##   pops   the pelvis, the head and the feet move POP_STEP at most from one 12 fps step to the next of a stepped clip
##          (POP_FRAME a frame, in a smooth one); the hands only across a join (the clip's `joins` metadata), since a
##          strike is a fast hand by design
##   reach  the frame a striking bone reaches furthest forward (along +Z): the first step at which it comes within
##          REACH_TIE of its furthest, so a held extension counts from where it arrives

const POP_STEP := 0.25
const POP_FRAME := 0.15
const REACH_TIE := 0.01
const BODY: Array[StringName] = [&"pelvis", &"Head", &"foot_l", &"foot_r"]
const HANDS: Array[StringName] = [&"hand_l", &"hand_r"]


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


## The worst move of a joint the pop rule holds `clip` to: [metres, joint, the frame it moves to, the most allowed].
static func worst_pop(rig: Rig, clip: StringName) -> Array:
	var anim := rig.tree.get_animation(clip)
	var step := step_of(anim)
	var joins: PackedFloat32Array = anim.get_meta(&"joins", PackedFloat32Array())
	var joints: Array[StringName] = BODY + HANDS
	var at := poses(rig, clip, joints)
	var worst := [0.0, &"", -1, POP_STEP if step > 1 else POP_FRAME]
	for frame: int in at:
		if not at.has(frame - step):
			continue
		var across := Array(joins).any(func(t: float) -> bool: return t * 60.0 >= frame - step - 1e-3 and t * 60.0 <= frame + 1e-3)
		for joint in joints:
			if HANDS.has(joint) and not across:
				continue
			var moved: float = (at[frame][joint] as Vector3).distance_to(at[frame - step][joint])
			if moved > worst[0]:
				worst = [moved, joint, frame, worst[3]]
	return worst


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
