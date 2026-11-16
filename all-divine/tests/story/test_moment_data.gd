extends TestCase
## The combat moment as data: the tuning's defaults (data/tuning/story.tres) and the finisher's one-shot scene
## (data/story/moments/finisher.tres), which the shot checker finds no fault with and which is the spec's 1.5 s in all.

const TUNING := "res://data/tuning/story.tres"
const FINISHER := "res://data/story/moments/finisher.tres"


func test_the_tuning_holds_the_defaults() -> void:
	var tuning := load(TUNING) as StoryTuning
	assert_true(tuning != null, "data/tuning/story.tres is a StoryTuning")
	if tuning == null:
		return
	assert_eq(tuning.moment_dip_on, true, "the dip is on")
	assert_eq(tuning.moment_zoom, 2, "it leans in to zoom 2")
	assert_eq(tuning.moment_frames, 60, "for 60 frames of shot")
	assert_eq(tuning.moment_slow_frames, 0, "with no slow-motion beat until the owner asks")
	assert_eq(tuning.moment_hold_share, 0.4, "and holds at full for 0.4 of them")


func test_the_finisher_moment_is_one_medium_shot_on_the_pair_in_ninety_frames() -> void:
	var scene := load(FINISHER) as SceneShots
	assert_true(scene != null, "data/story/moments/finisher.tres is a SceneShots")
	if scene == null:
		return
	assert_eq(scene.kind, SceneShots.Kind.MOMENT)
	assert_eq(scene.shots.size(), 1, "one shot")
	assert_eq(scene.shots[0].framing, Shot.Framing.MEDIUM)
	assert_eq(scene.shots[0].aim, &"@pair", "on the middle of the pair")
	assert_eq(scene.shots[0].length, 60)
	assert_eq([scene.lead_in, scene.lead_out], [15, 15], "15 frames in and 15 out")
	assert_eq(scene.total_frames(), 90, "1.5 s in all")
	assert_true(scene.cast.is_empty() and not scene.letterbox, "no cast and no bars")


func test_the_checker_finds_no_fault_with_the_finisher_moment() -> void:
	var checker := ShotChecker.new()
	var lines := checker.check_file(FINISHER)
	assert_eq(Array(lines), [], "story_check on it is clean")
	assert_true(checker.finished, "and it ran to its end")
