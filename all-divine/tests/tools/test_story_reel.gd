extends TestCase
## The storyboard's reel plays the scene undrawn and draws only what a key frame needs (headless, pure: which ticks are drawn).

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"


func test_only_the_key_frames_and_their_neighbours_are_drawn() -> void:
	var scene := load(FIXTURE) as SceneShots
	var targets := StoryboardPage.ShotText.key_frames(scene)
	var drawn := 0
	for frame in scene.length():
		if StoryReel.is_drawn(frame, targets):
			drawn += 1
	assert_eq(drawn, targets.size() * (StoryReel.DRAW_BEFORE + StoryReel.DRAW_AFTER + 1), "%d of the scene's %d ticks are drawn" % [drawn, scene.length()])
	assert_true(drawn * 10 < scene.length(), "a tenth of the scene or less is drawn: %d of %d" % [drawn, scene.length()])
	for target in targets:
		for frame in range(target - StoryReel.DRAW_BEFORE, target + StoryReel.DRAW_AFTER + 1):
			assert_true(StoryReel.is_drawn(frame, targets), "tick %d, round the key frame %d, is drawn" % [frame, target])
		assert_false(StoryReel.is_drawn(target - StoryReel.DRAW_BEFORE - 1, targets), "the one before the neighbours is not")
		assert_false(StoryReel.is_drawn(target + StoryReel.DRAW_AFTER + 1, targets), "nor the one after")


func test_with_no_key_frame_nothing_is_drawn() -> void:
	assert_false(StoryReel.is_drawn(10, PackedInt32Array()))
