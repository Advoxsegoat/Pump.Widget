extends TestCase
## However a scene ends, the game is as if it had been aborted (fix round 1, item 1): the bars and the box gone, the camera's weight 0,
## the Hud back, every actor of the cast with its own brain (the ones the scene made gone), nobody frozen, no scene current, no
## error line. The scene's own end, a skip and abort() are tested with the Director; here the ways it is cut off from outside: the
## Director freed, its root freed, Game reset, and the game's state moved by someone else, each at every 20th scene frame.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const STEP := 20
const LAST := 360


func before_each() -> void:
	RenderingServer.render_loop_enabled = false  # nothing here looks at a picture: a render run need not draw its thousands of frames
	Game.reset()
	Game.change(Game.State.PLAY)
	StoryLog.forget_all()
	Director.reset_spawn_counts()
	Melee.slow(0, 1.0)


func after_each() -> void:
	RenderingServer.render_loop_enabled = true
	Melee.slow(0, 1.0)
	Game.reset()


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# A stage with the player, an outsider Knuckle (held while the scene plays) and the scene begun and run to scene frame `at`.
func _scene_at(at: int) -> Dictionary:
	Game.reset()
	Game.change(Game.State.PLAY)
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var outsider := StoryStage.knuckle(parts.region, Vector3(-4, 0, 6), 0.0, "Outsider")
	var outsider_brain := outsider.brain
	await frames(3)
	var director := Director.new()
	if not director.begin(_fixture(), parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return {}
	while director.frame < at and director.phase != Director.Phase.LEAD_OUT:
		await frames(1)
	parts.director = director
	parts.outsider = outsider
	parts.outsider_brain = outsider_brain
	parts.player_brain = parts.brain
	parts.root = director.get_parent()
	return parts


func _overlays(parts: Dictionary) -> int:
	return parts.stage.hud.get_children().filter(func(c: Node) -> bool: return c is CineOverlay and not c.is_queued_for_deletion()).size()


# What must be true once the scene is gone, `label` naming the way and the frame.
func _check_given_back(parts: Dictionary, label: String, state: Game.State) -> void:
	await frames(4)
	assert_eq(_overlays(parts), 0, "%s: no overlay (bars and box)" % label)
	assert_eq(parts.rig.cine_weight, 0.0, "%s: the camera's weight is 0" % label)
	assert_false(parts.hud.suppressed, "%s: the Hud is back" % label)
	assert_true(parts.player.brain == parts.player_brain, "%s: Abarax has his own hands" % label)
	assert_true(parts.outsider.brain == parts.outsider_brain, "%s: the foe outside the scene has his own mind" % label)
	for node in parts.region.get_children():
		var actor := node as Actor
		if actor == null or actor.is_queued_for_deletion():
			continue
		assert_false(actor.brain is DirectorBrain, "%s: %s has no scene brain" % [label, actor.name])
		assert_eq(actor.frozen, 0, "%s: %s is not frozen" % [label, actor.name])
	assert_true(Director.current() == null, "%s: no scene is current" % label)
	assert_eq(Game.state, state, "%s: the game's state" % label)
	assert_false(StoryLog.seen(&"fixture_yard_entrance"), "%s: a scene cut off is not a scene seen" % label)


func _each_frame(label: String, state: Game.State, cut: Callable) -> void:
	for at in range(0, LAST + 1, STEP):
		var parts := await _scene_at(at)
		if parts.is_empty():
			fail("%s: the scene is taken at frame %d" % [label, at])
			return
		if parts.director.phase == Director.Phase.LEAD_OUT:
			parts.stage.free()
			await frames(1)
			continue  # the scene has handed back by itself: not a way of being cut off
		await cut.call(parts)
		await _check_given_back(parts, "%s at %d" % [label, at], state)
		parts.stage.free()
		await frames(1)


func test_the_director_freed_at_any_frame_gives_everything_back() -> void:
	await _each_frame("Director freed", Game.State.PLAY, func(parts: Dictionary) -> void: parts.director.free())


func test_the_root_freed_at_any_frame_gives_everything_back() -> void:
	await _each_frame("root freed", Game.State.PLAY, func(parts: Dictionary) -> void: parts.root.free())


func test_a_game_reset_at_any_frame_ends_the_scene() -> void:
	await _each_frame("Game.reset", Game.State.BOOT, func(parts: Dictionary) -> void:
		Game.reset()
		await frames(2))


func test_the_state_moved_by_someone_else_at_any_frame_ends_the_scene() -> void:
	await _each_frame("state moved to PLAY", Game.State.PLAY, func(parts: Dictionary) -> void:
		Game.change(Game.State.PLAY)
		await frames(2))


func test_abort_at_any_frame_gives_everything_back() -> void:
	await _each_frame("abort", Game.State.PLAY, func(parts: Dictionary) -> void: parts.director.abort())


func test_a_pause_in_the_scene_is_not_a_way_out() -> void:
	var parts := await _scene_at(100)
	Game.change(Game.State.PAUSE)
	await frames(5)
	assert_true(Director.current() == parts.director, "paused, the scene is still there")
	Game.change(Game.State.PLAY)
	assert_eq(Game.state, Game.State.CUTSCENE, "and Resume goes back to it")
	await frames(3)
	assert_true(Director.current() == parts.director, "and it plays on")


func test_a_region_change_at_any_frame_gives_everything_back() -> void:
	for at in range(0, LAST + 1, STEP):
		Game.reset()
		Arena.reset_spawn_counts()
		var main := track((load("res://main/main.tscn") as PackedScene).instantiate()) as Main
		for foe in main.arena().enemies():
			foe.set_brain(Brain.new())
		await frames(2)
		var brain := main.player.brain
		var director := Director.play(&"fixture_yard_entrance", main)
		if director == null:
			fail("region change at %d: the scene is taken (%s)" % [at, Director.last_refusal])
			return
		while director.frame < at and director.phase != Director.Phase.LEAD_OUT:
			await frames(1)
		if director.phase == Director.Phase.LEAD_OUT:
			main.free()
			await frames(1)
			continue
		main.switch_region()
		await frames(3)
		var label := "region change at %d" % at
		assert_true(Director.current() == null, "%s: no scene" % label)
		assert_eq(Game.state, Game.State.PLAY, "%s: the game plays" % label)
		assert_true(main.player.brain == brain, "%s: his own hands" % label)
		assert_false(main.hud.suppressed, "%s: the Hud is back" % label)
		assert_eq(main.camera_rig.cine_weight, 0.0, "%s: the camera is the game's" % label)
		assert_true(main.stage.hud.get_children().filter(func(c: Node) -> bool: return c is CineOverlay and not c.is_queued_for_deletion()).is_empty(), "%s: no overlay" % label)
		main.free()
		await frames(1)
