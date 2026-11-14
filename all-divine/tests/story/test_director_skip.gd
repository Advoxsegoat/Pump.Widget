extends TestCase
## Skipping: never on a first viewing, always smooth after it (the camera glides home from wherever it is, the cast is put where
## the scene leaves it), and harmless at any frame. The pause menu is where a player skips (the menus lane adds the row); skip() and
## is_skippable() are the Director's side of it. Review Focus 3.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"

var _finished: Array = []


func before_each() -> void:
	Game.reset()
	Game.change(Game.State.PLAY)
	StoryLog.forget_all()
	Director.reset_spawn_counts()
	Director.skip_always = false
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.GAMEPAD
	_finished = []


func after_each() -> void:
	Input.action_release(&"menu")
	Director.skip_always = false
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Game.reset()


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


func _start(parts: Dictionary, scene: SceneShots = null) -> Director:
	var director := Director.new()
	if not director.begin(scene if scene != null else _fixture(), parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return null
	director.finished.connect(func(skipped: bool) -> void: _finished.append(skipped))
	return director


func _to_frame(director: Director, target: int) -> void:
	while is_instance_valid(director) and director.frame < target:
		await frames(1)


func _overlay_of(parts: Dictionary) -> CineOverlay:
	for child in parts.stage.hud.get_children():
		if child is CineOverlay:
			return child
	return null


func test_a_first_viewing_cannot_be_skipped_and_a_later_one_can() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await frames(40)
	assert_false(director.is_skippable(), "a first viewing is not skippable")
	assert_false(director.skip(), "and skip does nothing")
	assert_ne(director.phase, Director.Phase.LEAD_OUT)
	StoryLog.mark_seen(&"fixture_yard_entrance")
	assert_true(director.is_skippable(), "once seen it is")
	Input.action_press(&"menu")
	await frames(3)
	assert_ne(director.phase, Director.Phase.LEAD_OUT, "the menu button pauses a scene, it never skips it (the menu is where Skip scene is)")
	Input.action_release(&"menu")
	assert_true(director.skip(), "skip does it")
	assert_eq(director.phase, Director.Phase.LEAD_OUT)
	assert_false(director.is_skippable(), "and only once")


func test_skip_on_the_first_frame_and_anywhere_glides_back_from_where_the_camera_is() -> void:
	for at in [0, 12, 30, 100, 200, 290, 299]:
		var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
		await frames(3)
		StoryLog.mark_seen(&"fixture_yard_entrance")
		_finished = []
		var director := _start(parts)
		assert_true(director != null)
		if director == null:
			return
		await _to_frame(director, at)
		var player: Actor = parts.player
		var head := StoryStage.screen_of(parts, player.head_point())
		assert_true(director.skip(), "frame %d: skipped" % at)
		var worst := 0.0
		var n := 0
		while _finished.is_empty() and n < 60:
			await frames(1)
			n += 1
			var now := StoryStage.screen_of(parts, player.head_point())
			worst = maxf(worst, now.distance_to(head))
			head = now
		assert_eq(_finished, [true], "frame %d: it ends, skipped" % at)
		assert_true(worst <= 12.0, "frame %d: his head moves at most 12 px a frame through the glide, not %.1f" % [at, worst])
		assert_true(n <= Director.SKIP_LEAD_OUT + 2, "frame %d: in SKIP_LEAD_OUT frames (%d)" % [at, n])
		assert_eq(Game.state, Game.State.PLAY, "frame %d: ends in PLAY" % at)
		assert_eq(parts.rig.cine_weight, 0.0, "frame %d: the camera is the game's" % at)
		parts.stage.free()
		await frames(1)


func test_skip_on_the_last_frame_and_after_the_end_is_harmless() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	StoryLog.mark_seen(&"fixture_yard_entrance")
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var player: Actor = parts.player
	await _to_frame(director, 300)  # the last frame of the shots
	assert_eq(director.phase, Director.Phase.PLAY, "the last frame of the last shot")
	assert_true(director.skip(), "it can still be skipped")
	await frames(2)
	var at := [player.global_position, player.rotation.y]
	assert_false(director.skip(), "and not again")
	await frames(1)
	assert_eq([player.global_position, player.rotation.y], at, "nothing is placed twice")
	var n := 0
	while _finished.is_empty() and n < 80:
		await frames(1)
		n += 1
	assert_eq(_finished, [true], "one finished")
	await frames(10)
	assert_eq(_finished, [true], "and never a second")
	assert_true(Director.current() == null)
	# the same without a skip: one at the hand-back, one after the end
	var parts2 := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	_finished = []
	var second := _start(parts2)
	assert_true(second != null, "a second scene can follow: %s" % Director.last_refusal)
	if second == null:
		return
	while second.phase != Director.Phase.LEAD_OUT:
		await frames(1)
	assert_false(second.skip(), "at the hand-back it is too late to skip")
	await frames(1)
	assert_false(second.skip(), "and a frame later")
	var m := 0
	while _finished.is_empty() and m < 100:
		await frames(1)
		m += 1
	assert_eq(_finished, [false], "it finishes once, played")


func test_skip_twice_and_skip_during_the_wait() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	StoryLog.mark_seen(&"fixture_yard_entrance")
	var player: Actor = parts.player
	player.freeze(20)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	assert_eq(director.phase, Director.Phase.WAITING)
	assert_false(director.skip(), "during the wait skip is refused")
	assert_false(director.is_skippable())
	while director.phase == Director.Phase.WAITING:
		await frames(1)
	await frames(3)
	assert_true(director.skip(), "after it, it works")
	assert_false(director.skip(), "the second is false")
	var n := 0
	while _finished.is_empty() and n < 80:
		await frames(1)
		n += 1
	assert_eq(_finished, [true], "and the scene that waited played, was skipped and ended")


func test_a_skipped_and_a_played_scene_end_in_the_same_state() -> void:
	var ends := []
	for skipped in [false, true]:
		for after: CastEntry.After in [CastEntry.After.ENEMY_BRAIN, CastEntry.After.FREE]:
			var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
			await frames(3)
			StoryLog.forget_all()
			if skipped:
				StoryLog.mark_seen(&"fixture_yard_entrance")
			_finished = []
			var scene := _fixture()
			scene.cast[1].after = after
			var director := _start(parts, scene)
			assert_true(director != null)
			if director == null:
				return
			var foe: Actor = director.cast[&"knuckle"]
			if skipped:
				await _to_frame(director, 50)
				assert_true(director.skip())
			var n := 0
			while _finished.is_empty() and n < 500:
				await frames(1)
				n += 1
			await frames(2)
			var player: Actor = parts.player
			var there := is_instance_valid(foe) and foe.is_inside_tree()
			ends.append({
				player_at = player.global_position, player_yaw = player.rotation.y, player_brain = player.brain == parts.brain,
				foe_at = foe.global_position if there else Vector3.ZERO, foe_yaw = foe.rotation.y if there else 0.0,
				foe_brain = foe.brain.get_class() + str(foe.brain is EnemyBrain) if there else "gone",
				state = Game.state, weight = parts.rig.cine_weight, children = parts.region.get_child_count(),
				seen = StoryLog.seen(&"fixture_yard_entrance"), hud = parts.hud.suppressed, left = Director.current() == null,
			})
			parts.stage.free()
			await frames(1)
	for i in 2:
		var played: Dictionary = ends[i]
		var cut: Dictionary = ends[i + 2]
		assert_true(played.player_at.distance_to(cut.player_at) <= 0.15, "%d: Abarax within 0.15 m" % i)
		assert_true(played.foe_at.distance_to(cut.foe_at) <= 0.15, "%d: the Knuckle within 0.15 m (%s, %s)" % [i, played.foe_at, cut.foe_at])
		assert_true(absf(rad_to_deg(angle_difference(played.player_yaw, cut.player_yaw))) <= 10.0, "%d: Abarax within 10 degrees" % i)
		assert_true(absf(rad_to_deg(angle_difference(played.foe_yaw, cut.foe_yaw))) <= 10.0 or played.foe_brain == "gone", "%d: the Knuckle within 10 degrees" % i)
		for key: String in ["player_brain", "foe_brain", "state", "weight", "children", "seen", "hud", "left"]:
			assert_eq(cut[key], played[key], "%d: %s is the same" % [i, key])
	assert_eq(ends[1].foe_brain, "gone", "FREE: the Knuckle is gone from both")
	assert_eq(ends[0].state, Game.State.PLAY)
	assert_eq(ends[0].weight, 0.0)


func test_skip_closes_the_line_and_stops_the_clips() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	StoryLog.mark_seen(&"fixture_yard_entrance")
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var lines: Array[String] = []
	director.line_shown.connect(func(_speaker: StringName, text: String) -> void: lines.append(text))
	var foe: Actor = director.cast[&"knuckle"]
	var overlay := _overlay_of(parts)
	await _to_frame(director, 30 + 150 + 10)
	assert_true(overlay.showing(), "a line is up")
	assert_true(foe.rig.move_weight() > 0.5 or director.cast[&"abarax"].rig.move_weight() > 0.5, "a clip is showing")
	assert_true(director.skip())
	assert_false(overlay.showing(), "the line is closed")
	var blips := 0
	for i in 40:
		await frames(1)
		blips += Sfx.last_played().count(&"voice_blip")
	assert_eq(blips, 0, "and nothing types on")
	assert_eq(lines, ["Fixture line one."], "no later line comes up")
	assert_true(foe.rig.move_weight() < 0.01 and director.cast.get(&"abarax", foe).rig.move_weight() < 0.01 if is_instance_valid(director) else true, "the clips are released")
	assert_true(foe.runner.current == null)


func test_a_skipped_cutscene_slides_its_bars_out_with_the_glide() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	StoryLog.mark_seen(&"fixture_yard_entrance")
	var scene := _fixture()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.letterbox = true
	var director := _start(parts, scene)
	assert_true(director != null)
	if director == null:
		return
	var overlay := _overlay_of(parts)
	await _to_frame(director, 120)
	assert_eq(overlay.bar_height(), 44, "the bars are in")
	assert_true(director.skip())
	var heights: Array[int] = []
	var n := 0
	while _finished.is_empty() and n < 60:
		await frames(1)
		n += 1
		if is_instance_valid(overlay) and not overlay.is_queued_for_deletion():
			heights.append(overlay.bar_height())
	for i in range(1, heights.size()):
		assert_true(heights[i] <= heights[i - 1], "the bars only go out (%s)" % [heights])
	assert_true(heights.size() > 10 and heights[heights.size() - 1] <= 3, "and are out by the end (%s)" % [heights])


func test_the_tools_may_skip_a_first_viewing() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	Director.skip_always = true
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await frames(5)
	assert_true(director.is_skippable(), "a tool can skip what no one has seen")
	assert_true(director.skip())


func test_a_skip_at_any_tenth_frame_never_moves_him_more_than_12_px_or_25_degrees_a_frame() -> void:
	var worst_head := 0.0
	var worst_at := -1
	var worst_bone := 0.0
	var bone_at := -1
	for at in range(0, 300, 10):
		var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
		await frames(3)
		StoryLog.mark_seen(&"fixture_yard_entrance")
		_finished = []
		var director := _start(parts)
		assert_true(director != null)
		if director == null:
			return
		await _to_frame(director, at)
		var player: Actor = parts.player
		var head := StoryStage.screen_of(parts, player.head_point())
		var pose := StoryStage.pose_of(player.rig)
		assert_true(director.skip(), "frame %d: skipped" % at)
		var n := 0
		while _finished.is_empty() and n < 60:
			await frames(1)
			n += 1
			var now := StoryStage.screen_of(parts, player.head_point())
			if now.distance_to(head) > worst_head:
				worst_head = now.distance_to(head)
				worst_at = at
			head = now
			var posed := StoryStage.pose_of(player.rig)
			var turned := StoryStage.angle_between(pose, posed, "scarf")
			if turned > worst_bone:
				worst_bone = turned
				bone_at = at
			pose = posed
		parts.stage.free()
		await frames(1)
	assert_true(worst_head <= 12.0, "his head moves at most 12 px a frame through any skip, not %.1f (skipped from frame %d)" % [worst_head, worst_at])
	assert_true(worst_bone <= 25.0, "no bone but the scarf's turns more than 25 degrees a frame, not %.1f (skipped from frame %d)" % [worst_bone, bone_at])
