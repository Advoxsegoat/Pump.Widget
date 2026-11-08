extends TestCase
## No clip of the library pops (ClipMotion): from one step of a clip to the next (a 12 fps step of a stepped clip, a
## frame of a smooth one) the pelvis and the head move POP_STEP (0.25 m) at most, or POP_FRAME (0.15 m) a frame, and
## across a join or a crossfade the hands and feet move POP_STEP at most too. The rule is for discontinuities, the owner's
## first priority; a strike or a kick away from a join is a fast limb by design.
##
## REPORTED holds the clips the rule flags away from any join: fast motion in the source itself, reported to the owner
## (F1 Task 12) rather than re-timed, each held to what it measured so it cannot grow:
##   palm_hook   UAL2 Melee_Hook's lunge drops the head 0.79 m between f5 and f10 (source 0.20-0.27 s; its join with
##               Melee_Hook_Rec is at f20)
##   palm_heavy  UAL2 OverhandThrow's throw swings the head 0.79 m into f15
##   dodge_roll  UAL1 Roll at 2.9 times its speed tumbles the head 0.38 m in a frame
##   hop         its warp plays NinjaJump_Start's first 0.12 s in two frames, 0.44 m at f1 (the move fades in over it)

const RIG := "res://actors/abarax/abarax_rig.tscn"
const REPORTED := {&"palm_hook": 0.794, &"palm_heavy": 0.787, &"dodge_roll": 0.385, &"hop": 0.438}


func test_no_clip_of_the_library_pops() -> void:
	var rig: Rig = track((load(RIG) as PackedScene).instantiate())
	var clips := Array(rig.tree.get_animation_list()).filter(func(c: StringName) -> bool: return c != Rig.SNAPSHOT_CLIP)
	assert_true(clips.size() >= 35, "the library (%d clips)" % clips.size())
	for clip: StringName in clips:
		var body: Array = ClipMotion.worst_pop(rig, clip)
		var allowed: float = REPORTED.get(clip, body[3])
		assert_true(body[0] <= allowed, "%s: the %s moves %.3f m to f%d (at most %.3f)" % [clip, body[1], body[0], body[2], allowed])
		var limb: Array = ClipMotion.worst_join(rig, clip)
		assert_true(limb[0] <= limb[3], "%s: across a join the %s moves %.3f m to f%d (at most %.2f)" % [clip, limb[1], limb[0], limb[2], limb[3]])
