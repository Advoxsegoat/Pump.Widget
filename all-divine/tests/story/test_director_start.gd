extends TestCase
## The Director's start: a scene takes the fight as it is (position, facing, the move he was in the middle of) and begins
## without a pop; it waits out what must not be cut (hit-stop, the slow-down, a body in the air) for START_WAIT frames at
## most. Review Focus 1 and 4.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const MIDDLE_OF := [&"palm_jab", &"palm_cross", &"palm_hook", &"hop", &"sway_left_slip", &"duck_slip", &"dash_step",
		&"guard_raise", &"parry"]


func before_each() -> void:
	Game.reset()
	Game.change(Game.State.PLAY)
	StoryLog.forget_all()
	Melee.slow(0, 1.0)


func after_each() -> void:
	Melee.slow(0, 1.0)
	Input.action_release(&"heavy")
	Game.reset()


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# A Director that has begun the fixture (or `scene`) on the parts of StoryStage.make; null if it refused.
func _start(parts: Dictionary, scene: SceneShots = null) -> Director:
	var director := Director.new()
	if not director.begin(scene if scene != null else _fixture(), parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return null
	return director


# Plays frames until the scene's clock has started (at most `limit`); how many frames that took.
func _wait_for_start(director: Director, limit := 120) -> int:
	var waited := 0
	while director.phase == Director.Phase.WAITING and waited < limit:
		await frames(1)
		waited += 1
	return waited


func test_a_scene_starts_from_the_live_state() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	var at := player.global_position
	var yaw := player.rotation.y
	var head := StoryStage.screen_of(parts, player.head_point())
	var director := _start(parts)
	assert_true(director != null, "the scene is taken: %s" % Director.last_refusal)
	if director == null:
		return
	await _wait_for_start(director)
	assert_ne(director.phase, Director.Phase.WAITING, "it has begun")
	assert_eq(director.frame, 0, "at its first frame")
	assert_vec_near(player.global_position, at, 0.001, "he has not moved a millimetre")
	assert_near(angle_difference(player.rotation.y, yaw), 0.0, deg_to_rad(1.0), "and still faces the way he did")
	assert_true(StoryStage.screen_of(parts, player.head_point()).distance_to(head) <= 1.0,
			"the camera's first picture has his head where the game camera had it: %s against %s" % [StoryStage.screen_of(parts, player.head_point()), head])
	assert_eq(Game.state, Game.State.PLAY if director.scene.kind == SceneShots.Kind.MOMENT else Game.State.CUTSCENE)


func test_a_scene_started_mid_move_ends_the_move_cleanly() -> void:
	for id: StringName in MIDDLE_OF + [&"palm_heavy"]:
		var parts := StoryStage.make(self)
		var player: Actor = parts.player
		var foe := StoryStage.knuckle(parts.region, Vector3(0, 0, 0.9), PI, "Foe")
		foe.stats.poise = 100.0
		await frames(3)
		if id == &"palm_heavy":
			player.set_brain(ScriptBrain.new([{frames = 60, press = [&"heavy"], hold = [&"heavy"]}]))
			await frames(30)
			assert_true(player.runner.charging, "palm_heavy is charging, held")
		else:
			player.runner.start(Registry.fetch(&"moves", id) as MoveData, true)
			await frames(7)
		assert_true(player.runner.current != null, "%s: he is in it" % id)
		var hp := foe.stats.hp
		var director := _start(parts)
		assert_true(director != null, "%s: the scene is taken" % id)
		if director == null:
			continue
		var runner := player.runner
		assert_true(runner.current == null, "%s: the move is over" % id)
		assert_false(runner.iframes or runner.evading != MoveData.Evade.NONE or runner.guard_window or runner.parry_window or runner.airborne,
				"%s: no window is open" % id)
		assert_eq(player.rig.active_hitboxes(), [] as Array[StringName], "%s: no hitbox is on" % id)
		assert_false(runner.hyperarmour or runner.charging, "%s: no armour, no charge" % id)
		await frames(40)
		assert_eq(foe.stats.hp, hp, "%s: the swing he was in lands on no one" % id)
		assert_eq(foe.stats.posture, foe.stats.max_posture, "%s: and breaks no posture" % id)
		director.get_parent().free()
		Input.action_release(&"heavy")


func test_the_first_frames_do_not_pop() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var player: Actor = parts.player
	await frames(3)
	player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData, true)
	await frames(5)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var head := StoryStage.screen_of(parts, player.head_point())
	var pose := StoryStage.pose_of(player.rig)
	var worst_head := 0.0
	var worst_bone := 0.0
	for i in 70:
		await frames(1)
		var now := StoryStage.screen_of(parts, player.head_point())
		worst_head = maxf(worst_head, now.distance_to(head))
		head = now
		var posed := StoryStage.pose_of(player.rig)
		worst_bone = maxf(worst_bone, StoryStage.angle_between(pose, posed))
		pose = posed
	assert_true(worst_head <= 12.0, "his head moves at most 12 px a frame across the start, not %.1f" % worst_head)
	assert_true(worst_bone <= 25.0, "no bone turns more than 25 degrees between two frames, not %.1f" % worst_bone)


func test_started_in_a_hop_or_off_the_floor_waits_for_the_floor() -> void:
	var parts := StoryStage.make(self)
	TestTerrain.ledge(parts.region)
	var player: Actor = parts.player
	player.place(Transform3D(Basis.IDENTITY, Vector3(0.4, TestTerrain.LEDGE_TOP, 0)))
	await frames(2)
	assert_false(player.is_on_floor(), "he is in the air")
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	assert_eq(director.phase, Director.Phase.WAITING, "the scene waits")
	var waited := 0
	while director.phase == Director.Phase.WAITING and waited < 100:
		assert_eq(director.frame, 0, "the clock has not started")
		await frames(1)
		waited += 1
	assert_true(player.is_on_floor(), "it began on the floor")
	assert_true(waited <= Director.START_WAIT + 1, "after %d frames, START_WAIT at most" % waited)
	assert_true(waited > 3, "and not at once")


func test_started_during_hit_stop_waits_it_out() -> void:
	var parts := StoryStage.make(self)
	var player: Actor = parts.player
	var foe := StoryStage.knuckle(parts.region, Vector3(0, 0, 1.2), PI, "Foe")
	await frames(3)
	player.freeze(5)
	foe.freeze(5)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var waited := 0
	while director.phase == Director.Phase.WAITING and waited < 30:
		assert_eq(director.frame, 0, "the clock stands at 0 while he is frozen")
		await frames(1)
		waited += 1
	assert_eq(player.frozen, 0, "he is free when it starts")
	assert_true(waited >= 4 and waited <= 7, "it waited out the freeze: %d frames" % waited)


func test_started_during_the_slow_down_waits_it_out_and_never_stutters() -> void:
	var parts := StoryStage.make(self)
	var player: Actor = parts.player
	await frames(3)
	Melee.slow(12, 0.4)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var waited := 0
	var why: Array[bool] = []
	while director.phase == Director.Phase.WAITING and waited < 60:
		why.append(Melee.slowed() or player.frozen > 0)
		assert_eq(director.frame, 0, "the clock stands at 0")
		await frames(1)
		waited += 1
	why.pop_back()  # the last look is of the frame it was settled on
	assert_true(why.all(func(held: bool) -> bool: return held), "it waits only while the slow-down or a freeze runs")
	assert_false(Melee.slowed(), "the slow-down is over when it starts")
	assert_true(waited > 3 and waited <= Director.START_WAIT + 1, "it waited %d frames" % waited)
	var foe: Actor = director.cast.get(&"knuckle")
	assert_true(foe != null, "the Knuckle is made")
	if foe == null:
		return
	# A frame on which an actor acts is one on which its stamina's wait is a frame older (a held frame ages nothing; the actor's
	# own acting clock, buffer_frame, stands still for the whole scene, so it cannot say).
	player.stats.spend_stamina(1.0)
	foe.stats.spend_stamina(1.0)
	var before := [player.stats.save().stamina_idle, foe.stats.save().stamina_idle]
	for i in 40:
		await frames(1)
		var now := [player.stats.save().stamina_idle, foe.stats.save().stamina_idle]
		assert_near(now[0] - before[0], 1.0 / 60.0, 1e-5, "Abarax acts on scene frame %d" % i)
		assert_near(now[1] - before[1], 1.0 / 60.0, 1e-5, "and so does the Knuckle (frame %d)" % i)
		before = now


func test_the_world_hold_does_not_shorten_a_freeze_already_on() -> void:
	var parts := StoryStage.make(self)
	var other := StoryStage.knuckle(parts.region, Vector3(-4, 0, -4), 0.0, "Other")
	await frames(3)
	other.freeze(6)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var seen: Array[int] = []
	for i in 9:
		await frames(1)
		seen.append(other.frozen)
	assert_eq(seen.slice(0, 5), [5, 4, 3, 2, 1] as Array[int], "the freeze counts down as it would have")
	assert_true(seen.slice(5).all(func(n: int) -> bool: return n > 0), "and then he is held: %s" % [seen])


func test_the_wait_gives_up_after_start_wait_unless_paired() -> void:
	var parts := StoryStage.make(self)
	var player: Actor = parts.player
	await frames(3)
	player.freeze(100)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var waited := await _wait_for_start(director, 200)
	assert_true(waited >= Director.START_WAIT and waited <= Director.START_WAIT + 1, "it began after %d frames, START_WAIT" % waited)
	assert_eq(player.frozen, 0 if waited <= Director.START_WAIT + 1 else player.frozen, "and he is free")
	await frames(10)
	assert_true(player.frame > 0)


# The reactions: a scene that starts while the body is in one of them does not snap a limb. The worst start is a reaction that has
# just cut another move short: the hit-stop holds the rig before its crossfade can finish, and the stop must fade the pose the body
# was showing (Rig.stop_move), not play the crossfade out into the reaction's own clip.
const REACTIONS := [&"flinch", &"stagger", &"posture_broken", &"guard_hit", &"guard_break", &"parried", &"caught"]


func test_a_start_in_a_reaction_snaps_no_limb() -> void:
	var worst := 0.0
	var worst_of := ""
	for reaction: StringName in REACTIONS:
		for before: StringName in [&"", &"guard_raise", &"palm_jab", &"hop"]:
			for into in [0, 3, 8]:
				var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
				var player: Actor = parts.player
				await frames(3)
				if before != &"":
					player.runner.start(Registry.fetch(&"moves", before) as MoveData, true)
					await frames(7)
				player.runner.start(Registry.fetch(&"moves", StringName(player.def.reactions[reaction])) as MoveData, true)
				player.freeze(4)  # the blow's hit-stop
				await frames(into)
				var director := _start(parts)
				assert_true(director != null, "%s: the scene is taken (%s)" % [reaction, Director.last_refusal])
				if director == null:
					return
				var pose := StoryStage.pose_of(player.rig)
				for i in 40:
					await frames(1)
					var posed := StoryStage.pose_of(player.rig)
					var turned := StoryStage.angle_between(pose, posed, "scarf")
					if turned > worst:
						worst = turned
						worst_of = "%s after %s, %d frames into the hit-stop, scene frame %d" % [reaction, before, into, i]
					pose = posed
				parts.stage.free()
				await frames(1)
	assert_true(worst <= 25.0, "no bone but the scarf's turns more than 25 degrees between two frames across the start, not %.1f (%s)" % [worst, worst_of])
