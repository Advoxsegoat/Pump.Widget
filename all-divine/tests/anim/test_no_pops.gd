extends TestCase
## No clip of the library pops (ClipMotion): from one step of a clip to the next (a 12 fps step of a stepped clip, a
## frame of a smooth one) the pelvis and the head move POP_STEP (0.25 m) at most, or POP_FRAME (0.15 m) a frame, and
## across a join or a crossfade the hands and feet move POP_STEP at most too. The rule is for discontinuities, the owner's
## first priority; a strike or a kick away from a join is a fast limb by design.
##
## REPORTED holds the steps the rule flags that are confirmed artifacts of the source, each at the one frame it was
## measured on (frame -> the most any joint may move to it): a second pop anywhere else in the clip is still caught.
##   palm_heavy  UAL2 OverhandThrow's throw swings the head 0.79 m in the 12 fps step that lands the blow (f15)

const RIG := "res://actors/abarax/abarax_rig.tscn"
const REPORTED := {
	&"palm_heavy": {15: 0.787},
}


func test_no_clip_of_the_library_pops() -> void:
	var rig: Rig = track((load(RIG) as PackedScene).instantiate())
	var clips := Array(rig.tree.get_animation_list()).filter(func(c: StringName) -> bool: return c != Rig.SNAPSHOT_CLIP)
	assert_true(clips.size() >= 35, "the library (%d clips)" % clips.size())
	for clip: StringName in clips:
		var excepted: Dictionary = REPORTED.get(clip, {})
		for v: Array in ClipMotion.violations(rig, clip):
			var frame: int = v[0]
			if excepted.has(frame) and v[2] <= excepted[frame]:
				continue
			var at_join := ClipMotion.LIMBS.has(v[1])
			fail("%s: %sthe %s moves %.3f m to f%d (at most %.3f)" % [clip, "across a join " if at_join else "", v[1], v[2], frame,
					excepted.get(frame, v[3])])


func test_each_reported_step_is_still_there() -> void:
	# An exception that no longer fires (the source re-cut, the clip re-timed) is dropped from REPORTED, not left to excuse
	# a pop that may come back on its frame.
	var rig: Rig = track((load(RIG) as PackedScene).instantiate())
	for clip: StringName in REPORTED:
		var flagged := {}
		for v: Array in ClipMotion.violations(rig, clip):
			flagged[v[0]] = true
		for frame: int in REPORTED[clip]:
			assert_true(flagged.has(frame), "%s: the step to f%d still breaks the rule, so it is still an exception" % [clip, frame])
