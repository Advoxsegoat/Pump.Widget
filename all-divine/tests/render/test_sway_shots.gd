extends TestCase
## What the sways, ducks and dash-steps look like in the game's picture (640x360, the gameplay camera): at each clip's peak
## against the guard stance, with Abarax facing down, up, left and right of the screen, how far the head moves in game
## pixels and how many pixels of the silhouette change. The camera is about 32 px to the metre across the screen and 20 in
## depth, so a lean along the line of sight all but vanishes; the floors are what a player can see in every facing.
## (ClipShots does the drawing.)

## Per tempo: the head moves at least this far in every facing, and at least `best` in one of them, in game pixels.
const HEAD_ALL := {&"slip": 5.0, &"quick": 4.0, &"flurry": 3.5}
const HEAD_BEST := {&"slip": 9.0, &"quick": 7.0, &"flurry": 6.0}
## The silhouette changes by at least this many pixels in every facing.
const SILHOUETTE := {&"slip": 200, &"quick": 150, &"flurry": 150}
## A dash-step's head moves at least this far on screen in every facing.
const DASH_HEAD := 5.0

var _shots: ClipShots


func before_each() -> void:
	_shots = ClipShots.new()
	await _shots.open(self)


func after_each() -> void:
	_shots.close()


func test_every_sway_is_seen_in_every_facing() -> void:
	for tempo: StringName in HEAD_ALL:
		for side in [&"left", &"right", &"back"]:
			var clip := StringName("sway_%s_%s" % [side, tempo])
			var best := 0.0
			for facing in ClipShots.FACINGS:
				var m := await _shots.measure(clip, facing)
				best = maxf(best, m["head"])
				assert_true(m["head"] >= HEAD_ALL[tempo], "%s facing %s: the head moves %.1f px (at least %.1f)" % [clip, facing, m["head"], HEAD_ALL[tempo]])
				assert_true(m["silhouette"] >= SILHOUETTE[tempo], "%s facing %s: %d silhouette pixels change (at least %d)" % [clip, facing, m["silhouette"], SILHOUETTE[tempo]])
			assert_true(best >= HEAD_BEST[tempo], "%s: the head moves %.1f px in its best facing (at least %.1f)" % [clip, best, HEAD_BEST[tempo]])


func test_every_dash_step_is_seen_in_every_facing() -> void:
	for clip in [&"dash_step", &"dash_step_left", &"dash_step_right", &"dash_step_back"]:
		for facing in ClipShots.FACINGS:
			var m := await _shots.measure(clip, facing)
			assert_true(m["head"] >= DASH_HEAD, "%s facing %s: the head moves %.1f px (at least %.1f)" % [clip, facing, m["head"], DASH_HEAD])
