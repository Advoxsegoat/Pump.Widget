extends TestCase
## A combat moment: the finisher's camera dip. The camera leans in toward the middle of the two fighters for a second and a half
## through the Director's cine layer and gives the picture back, and nothing else changes: no brain, no state, no Hud, no
## frame of the fight (Review Focus 4: the dip never touches a freeze). The dip is on when the player's setting `camera/dips` and
## the tuning's `moment_dip_on` both are.
##
## The stage is StoryStage's (a camera on Abarax and the Hud) with a Knuckle a metre in front of him whose posture is broken on
## frame 1 (PostureBreaker) and a palm pressed on frame 10: the finisher of tests/combat/test_finisher.gd.

const FINISHER := "res://data/story/moments/finisher.tres"
const SETTINGS_PATH := "user://settings_moment_test.cfg"
const MIDDLE := Vector2(320, 180)  # the middle of the 640x360 picture


func before_each() -> void:
	RenderingServer.render_loop_enabled = false  # these tests look at no picture: a render run need not draw their frames
	Settings.path = SETTINGS_PATH
	Game.reset()
	Game.change(Game.State.PLAY)
	Melee.slow(0, 1.0)


func after_each() -> void:
	RenderingServer.render_loop_enabled = true
	Melee.slow(0, 1.0)
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


# A finisher's stage: {stage, rig, hud, player, foe, ...}. Abarax palms on frame 10; the Knuckle's posture breaks on frame 1.
func _stage() -> Dictionary:
	var parts := StoryStage.make(self)
	var player: Actor = parts.player
	player.set_brain(ScriptBrain.new([{frames = 9}, {frames = 1, press = [&"palm"]}, {frames = 600}]))
	parts["foe"] = StoryStage.knuckle(parts.region, Vector3(0, 0, 1.0), PI, "Foe")
	track(PostureBreaker.make(player, parts.foe))
	return parts


# A stage where nothing happens (Abarax stands, a Knuckle a metre away, another far off): the moments are asked for by hand.
func _quiet_stage() -> Dictionary:
	var parts := StoryStage.make(self)
	parts["foe"] = StoryStage.knuckle(parts.region, Vector3(0, 0, 1.0), PI, "Foe")
	parts["far"] = StoryStage.knuckle(parts.region, Vector3(4.5, 0, 3.0), PI, "Far")
	return parts


# The fight on one frame, to the figures that matter: where each fighter is, its bars, its move, how long it is frozen, whether
# the slow-down is on.
func _snap(parts: Dictionary) -> Array:
	var out: Array = [Melee.slowed()]
	for actor: Actor in [parts.player, parts.foe]:
		var at := actor.global_position
		out.append([roundi(at.x * 1000.0), roundi(at.y * 1000.0), roundi(at.z * 1000.0), roundi(actor.stats.hp * 10.0),
				roundi(actor.stats.posture * 10.0), roundi(actor.stats.stamina * 10.0), actor.frozen, actor.frame, actor.dead,
				String(actor.runner.current.id) if actor.runner.current != null else &"", actor.paired_with != null])
	return out


# Plays `count` frames of `parts`' fight, noting the fight as it stands on each and, from the frame the finisher is announced, the
# camera: {trace, rows: [{weight, size, mid: where the pair's middle is in the picture}], began: the frame it began on or -1}.
func _play(parts: Dictionary, count: int) -> Dictionary:
	var player: Actor = parts.player
	var foe: Actor = parts.foe
	var seen := {began = -1}
	player.combat_moment.connect(func(kind: StringName) -> void:
		if kind == &"finisher" and seen.began < 0:
			seen.began = Engine.get_physics_frames())
	var trace := []
	var rows := []
	for i in count:
		await frames(1)
		trace.append(_snap(parts))
		if seen.began >= 0:
			rows.append({weight = parts.rig.cine_weight, size = parts.rig.camera.size,
					mid = StoryStage.screen_of(parts, (player.chest_point() + foe.chest_point()) / 2.0)})
	return {trace = trace, rows = rows, began = seen.began}


func _weights(run: Dictionary) -> Array:
	return run.rows.map(func(r: Dictionary) -> float: return r.weight)


func test_a_finisher_dips_the_camera_and_gives_it_back_in_ninety_frames() -> void:
	var parts := _stage()
	Director.watch_moments(parts.player, parts.rig, parts.hud)
	var run := await _play(parts, 150)
	assert_true(run.began >= 0, "the finisher began")
	var weights := _weights(run)
	assert_eq(weights.max() if not weights.is_empty() else -1.0, 1.0, "the camera is wholly in the dip at the top")
	var turns := 0
	var heading := 0.0
	for i in range(1, weights.size()):
		var step := signf(weights[i] - weights[i - 1])
		if step != 0.0 and heading != 0.0 and step != heading:
			turns += 1
		if step != 0.0:
			heading = step
	assert_eq(turns, 1, "it rises, holds and falls: the weight turns once")
	assert_eq(weights.filter(func(w: float) -> bool: return w > 0.0).size(), 89,
			"above 0 from the dip's frame 1 to its frame 89, and its frame 90 is the picture given back")
	assert_eq(weights.back() if not weights.is_empty() else -1.0, 0.0, "and exactly 0 at the end")
	var tops: Array = run.rows.filter(func(r: Dictionary) -> bool: return r.weight == 1.0)
	assert_true(not tops.is_empty(), "there are frames at the top")
	if tops.is_empty():
		return
	assert_near(tops[0].size, CameraRig.ORTHO_SIZE / 2.0, 1e-3, "at the top the picture is a medium shot: zoom 2")
	for row in tops:
		assert_true((row.mid as Vector2).distance_to(MIDDLE) <= 6.0, "the pair's middle is the picture's middle at the top (%s)" % row.mid)


func test_the_dip_changes_nothing_of_the_finisher() -> void:
	var traces := []
	var weights_seen := []
	for how in [&"on", &"setting_off", &"tuning_off"]:
		var parts := _stage()
		var cam := Director.watch_moments(parts.player, parts.rig, parts.hud)
		if how == &"setting_off":
			Settings.set_value("camera/dips", false)
		elif how == &"tuning_off":
			cam.tuning = cam.tuning.duplicate() as StoryTuning
			cam.tuning.moment_dip_on = false
		var run := await _play(parts, 150)
		assert_true(run.began >= 0, "%s: the finisher began" % how)
		traces.append(run.trace)
		weights_seen.append((_weights(run).max() if not _weights(run).is_empty() else -1.0))
		var frozen: int = run.trace.filter(func(row: Array) -> bool: return row[1][6] > 0 or row[2][6] > 0).size()
		assert_true(frozen >= 10, "%s: the blows' hit-stop is in the trace (%d frames of it)" % [how, frozen])
		parts.stage.queue_free()
		await frames(2)
		Settings.set_value("camera/dips", true)
	assert_eq(weights_seen, [1.0, 0.0, 0.0], "the dip was on in the first run and off in the others")
	assert_eq(traces[1].size(), 150)
	assert_true(traces[0] == traces[1], "dip on and dip off (the player's switch): every frame of both fighters is the same, hit-stop and all")
	assert_true(traces[0] == traces[2], "and with the tuning's switch off")


func test_a_moment_takes_no_brain_no_state_and_no_hud() -> void:
	var parts := _stage()
	Director.watch_moments(parts.player, parts.rig, parts.hud)
	var player: Actor = parts.player
	var foe: Actor = parts.foe
	var brains := [player.brain, foe.brain]
	var worst_alpha := 1.0
	var seen := {dipped = 0, state = Game.State.PLAY, held = false, bars = 0, current = false, brains = true}
	for i in 150:
		await frames(1)
		if parts.rig.cine_weight > 0.0:
			seen.dipped += 1
			if Game.state != Game.State.PLAY:
				seen.state = Game.state
			seen.held = seen.held or parts.hud.suppressed
			worst_alpha = minf(worst_alpha, parts.hud.shown_alpha())
			seen.bars += parts.stage.hud.get_children().filter(func(n: Node) -> bool: return n is CineOverlay).size()
			seen.current = seen.current or Director.current() != null
			seen.brains = seen.brains and player.brain == brains[0] and foe.brain == brains[1]
	assert_true(seen.dipped > 80, "the dip played (%d frames)" % seen.dipped)
	assert_eq(seen.state, Game.State.PLAY, "the game stays in PLAY")
	assert_false(seen.held, "the Hud is not suppressed")
	assert_eq(worst_alpha, 1.0, "and its alpha is 1 on every frame of the dip")
	assert_eq(seen.bars, 0, "no bars (no overlay) over the picture")
	assert_false(seen.current, "a moment is not a scene: Director.current() has none")
	assert_true(seen.brains, "both fighters keep their brains, the player his own hands")
	assert_true(player.brain is ScriptBrain and not (foe.brain is DirectorBrain), "and neither is a Director's")


func test_a_grab_has_no_dip_and_an_off_switch_has_none() -> void:
	var parts := _quiet_stage()
	var cam := Director.watch_moments(parts.player, parts.rig, parts.hud)
	await frames(3)
	parts.player.combat_moment.emit(&"grab")
	parts.player.combat_moment.emit(&"finisher")  # with no one in a pair with him there is no middle to lean toward
	for i in 10:
		await frames(1)
		assert_eq(parts.rig.cine_weight, 0.0, "a grab, or a finisher with no pair, dips nothing")
	assert_true(cam.director == null, "and no Director was made")
	# a finisher that is a pair: the control has both switches on, then each is turned off in turn
	for how in [&"control", &"setting", &"tuning"]:
		var stage := _stage()
		var each := Director.watch_moments(stage.player, stage.rig, stage.hud)
		if how == &"setting":
			Settings.set_value("camera/dips", false)
		elif how == &"tuning":
			each.tuning = each.tuning.duplicate() as StoryTuning
			each.tuning.moment_dip_on = false
		var run := await _play(stage, 120)
		assert_true(run.began >= 0, "%s: the finisher began" % how)
		assert_eq(_weights(run).max(), 1.0 if how == &"control" else 0.0, "%s: the camera %s" % [how, "dips" if how == &"control" else "never left the game's"])
		if how != &"control":
			assert_true(each.director == null and stage.rig.cine == null, "%s: no Director, no cine pose" % how)
		stage.stage.queue_free()
		await frames(2)
		Settings.set_value("camera/dips", true)


func test_a_second_finisher_during_a_dip_does_not_jump() -> void:
	var parts := _quiet_stage()
	var cam := Director.watch_moments(parts.player, parts.rig, parts.hud)
	var player: Actor = parts.player
	await frames(3)
	var head := StoryStage.screen_of(parts, player.head_point())
	var worst := 0.0
	var weight := 0.0
	var worst_weight := 0.0
	var top_second := []
	for i in 160:
		if i == 2:
			cam.moment(&"finisher", parts.foe)
		if i == 22:
			cam.moment(&"finisher", parts.far)  # a second pair, 2.7 m from the first's middle, while the first is still on the way in
		await frames(1)
		var now := StoryStage.screen_of(parts, player.head_point())
		worst = maxf(worst, now.distance_to(head))
		head = now
		worst_weight = maxf(worst_weight, absf(parts.rig.cine_weight - weight))
		weight = parts.rig.cine_weight
		if i >= 22 + 36 and i < 22 + 56:
			top_second.append(StoryStage.screen_of(parts, (player.chest_point() + parts.far.chest_point()) / 2.0))
	assert_true(worst <= 12.0, "his head moves at most 12 px a frame through the second finisher, not %.1f" % worst)
	assert_true(worst_weight <= 0.1, "the dip's weight changes by at most 0.1 a frame, not %.3f" % worst_weight)
	assert_eq(weight, 0.0, "the picture is given back, exactly")
	assert_true(not top_second.is_empty(), "the second dip has a top")
	for point: Vector2 in top_second:
		assert_true(point.distance_to(MIDDLE) <= 6.0, "at the top of the second dip it is the second pair's middle that is the picture's (%s)" % point)


func test_a_dip_in_progress_when_the_setting_is_turned_off_ends_cleanly_at_the_resume() -> void:
	var parts := _quiet_stage()
	var cam := Director.watch_moments(parts.player, parts.rig, parts.hud)
	var player: Actor = parts.player
	await frames(3)
	cam.moment(&"finisher", parts.foe)
	await frames(45)
	assert_eq(parts.rig.cine_weight, 1.0, "he is at the top of the dip")
	Game.change(Game.State.PAUSE)  # the menu: the player turns Camera dips off
	await frames(10)
	Settings.set_value("camera/dips", false)
	assert_eq(parts.rig.cine_weight, 1.0, "the picture holds while the menu is open")
	Game.change(Game.State.PLAY)
	var head := StoryStage.screen_of(parts, player.head_point())
	var weight := 1.0
	var worst := 0.0
	var worst_weight := 0.0
	var rising := false
	var ended := -1
	for i in 40:
		await frames(1)
		var now := StoryStage.screen_of(parts, player.head_point())
		worst = maxf(worst, now.distance_to(head))
		head = now
		rising = rising or parts.rig.cine_weight > weight
		worst_weight = maxf(worst_weight, absf(parts.rig.cine_weight - weight))
		weight = parts.rig.cine_weight
		if weight == 0.0 and ended < 0:
			ended = i
	assert_true(ended >= 0 and ended <= 16, "the weight is exactly 0 within the lead-out's 15 frames of the resume (at %d)" % ended)
	assert_false(rising, "it only falls")
	assert_true(worst_weight <= 0.1, "by at most 0.1 a frame, not %.3f" % worst_weight)
	assert_true(worst <= 12.0, "and his head moves at most 12 px a frame, not %.1f" % worst)
	assert_true(cam.director == null, "the moment is over")
	assert_eq(Game.state, Game.State.PLAY)


func test_the_moment_is_no_more_than_ninety_frames_and_the_checker_agrees() -> void:
	var checker := ShotChecker.new()
	assert_eq(Array(checker.check_file(FINISHER)), [], "story_check finds no fault with data/tuning's moment as it stands")
	assert_true(checker.finished)
	var scene := MomentCam.scene_for(load("res://data/tuning/story.tres") as StoryTuning)
	assert_eq(scene.total_frames(), 90, "the moment the tuning makes is the spec's 1.5 s")
	assert_eq(Array(checker.check(scene)), [], "and the checker agrees with it")
	var tuned := StoryTuning.new()
	tuned.moment_zoom = 3
	tuned.moment_frames = 30
	var other := MomentCam.scene_for(tuned)
	assert_eq([other.shots[0].zoom, other.shots[0].length, other.total_frames()], [3, 30, 60], "the tuning's zoom and frames are the shot's")
	assert_eq(Array(checker.check(other)), [], "and the checker is content with that too")
	var parts := _quiet_stage()
	var cam := Director.watch_moments(parts.player, parts.rig, parts.hud)
	await frames(2)
	cam.moment(&"finisher", parts.foe)
	assert_true(cam.director != null and cam.director.total_frames() == 90, "the Director plays it in 90 frames")


# The dip never hides a blow: at the top the picture shows half the width it does in play, so a foe that can strike must still be
# in it, whole. An attack is begun from at most the longest `max_range` of any brain (measured where the move lands), and the ring
# of 3.5 m the ruling names is beyond that; a foe past that cannot begin a blow, and the pair itself takes none for its first ~64 frames.
const STRIKE_RING := 3.5


func test_the_dip_never_hides_a_foe_that_can_strike() -> void:
	var longest := 0.0
	var dir := DirAccess.open("res://data/brains")
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		for option: AttackOption in (load("res://data/brains/%s" % file) as BrainDef).attacks:
			longest = maxf(longest, option.max_range)
	assert_true(longest <= STRIKE_RING, "no brain begins an attack from further than %.2f m, the ring the picture must hold (%.2f)" % [STRIKE_RING, longest])
	var parts := _stage()
	Director.watch_moments(parts.player, parts.rig, parts.hud)
	var ring: Array[Actor] = []
	var n := 16
	for k in n:
		var a := TAU * float(k) / float(n)
		var at := Vector3(sin(a), 0, cos(a)) * STRIKE_RING
		ring.append(StoryStage.knuckle(parts.region, at, a + PI, "Ring%d" % k))
	var guard := 0
	while parts.rig.cine_weight < 1.0 and guard < 200:
		await frames(1)
		guard += 1
	await frames(2)
	assert_eq(parts.rig.cine_weight, 1.0, "the dip is at its top")
	for foe in ring:
		for point: Vector3 in [foe.global_position, foe.chest_point(), foe.head_point()]:
			var on_picture := StoryStage.screen_of(parts, point)
			assert_true(on_picture.x >= 0.0 and on_picture.x <= 640.0 and on_picture.y >= 0.0 and on_picture.y <= 360.0,
					"%s at %.2f m is on the picture whole at the top of the dip (%s)" % [foe.name, foe.global_position.distance_to(parts.player.global_position), on_picture])
