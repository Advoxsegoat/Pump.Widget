extends TestCase
## The Director's cast: who must be there (and who may drop out), what a spawned actor stands as, and what each `after` leaves.
## Refusals change nothing at all. Review Focus 2.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const KNUCKLE := "res://data/actors/knuckle_1.tres"

var _finished: Array = []


func before_each() -> void:
	Game.reset()
	Game.change(Game.State.PLAY)
	StoryLog.forget_all()
	Director.reset_spawn_counts()
	Melee.slow(0, 1.0)
	_finished = []


func after_each() -> void:
	Melee.slow(0, 1.0)
	Game.reset()


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# The fixture with the Knuckle (cast entry 1) taken from the live actor named `node_name` instead of spawned.
func _with_named_knuckle(node_name: StringName, required: bool) -> SceneShots:
	var scene := _fixture()
	var entry := scene.cast[1]
	entry.source = CastEntry.Source.LIVE_NAMED
	entry.node_name = node_name
	entry.required = required
	entry.after = CastEntry.After.KEEP
	return scene


func _start(parts: Dictionary, scene: SceneShots) -> Director:
	var director := Director.new()
	if not director.begin(scene, parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return null
	director.finished.connect(func(skipped: bool) -> void: _finished.append(skipped))
	return director


# Everything a refusal must leave as it was.
func _snap(parts: Dictionary) -> Dictionary:
	var player: Actor = parts.player
	return {
		state = Game.state, brain = player.brain, region_children = parts.region.get_child_count(),
		world_children = parts.world.get_child_count(), hud_children = parts.stage.hud.get_child_count(),
		weight = parts.rig.cine_weight, suppressed = parts.hud.suppressed, cine = parts.rig.cine,
	}


# Plays frames until the scene has finished (at most `limit`).
func _play_out(limit := 600) -> void:
	var n := 0
	while _finished.is_empty() and n < limit:
		await frames(1)
		n += 1


func test_a_required_actor_who_is_absent_or_dead_refuses_the_scene() -> void:
	# absent: the Knuckle is to be found in the region and is not there
	var parts := StoryStage.make(self)
	await frames(3)
	var before := _snap(parts)
	var scene := _with_named_knuckle(&"Nobody", true)
	assert_true(_start(parts, scene) == null, "the scene is refused")
	assert_eq(Director.last_refusal, &"cast_absent:knuckle")
	assert_eq(_snap(parts), before, "and nothing changed")
	assert_true(Director.current() == null)
	# dead
	var player: Actor = parts.player
	player.die()
	await frames(2)
	assert_true(player.dead)
	before = _snap(parts)
	assert_true(_start(parts, _fixture()) == null, "a dead cast member refuses the scene")
	assert_eq(Director.last_refusal, &"cast_dead:abarax")
	assert_eq(_snap(parts), before, "and nothing changed")


func test_a_pair_that_does_not_end_gives_the_scene_up_after_pair_wait() -> void:
	var parts := StoryStage.make(self)
	var player: Actor = parts.player
	var victim := StoryStage.knuckle(parts.region, Vector3(0, 0, 1.0), PI, "Victim")
	await frames(3)
	player.paired_with = victim  # a pair nothing will end
	var before := _snap(parts)
	var director := _start(parts, _fixture())
	assert_true(director != null, "taken: it cannot know the pair's end")
	if director == null:
		return
	var refusals: Array[StringName] = []
	director.refused.connect(func(reason: StringName) -> void: refusals.append(reason))
	assert_eq(director.phase, Director.Phase.WAITING)
	var n := 0
	while refusals.is_empty() and n < 200:
		assert_eq(director.frame, 0, "the clock never started")
		await frames(1)
		n += 1
	assert_eq(refusals, [&"cast_busy:abarax"], "it gives the scene up, saying why")
	assert_eq(Director.last_refusal, &"cast_busy:abarax")
	assert_true(n >= Director.PAIR_WAIT and n <= Director.PAIR_WAIT + 2, "after PAIR_WAIT frames, not %d" % n)
	await frames(2)
	assert_eq(_snap(parts), before, "and nothing is left changed")
	assert_true(Director.current() == null)


func test_no_def_refuses_the_scene() -> void:
	var parts := StoryStage.make(self)
	await frames(3)
	var before := _snap(parts)
	var scene := _fixture()
	scene.cast[1].def = null
	assert_true(_start(parts, scene) == null)
	assert_eq(Director.last_refusal, &"no_def:knuckle")
	assert_eq(_snap(parts), before)


func test_an_optional_actor_who_is_absent_drops_out_with_its_beats() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var scene := _with_named_knuckle(&"Nobody", false)
	scene.cast[1].def = load(KNUCKLE) as ActorDef  # a named live actor that plays a clip has a def to check it against
	var rehearsal := SceneMark.new()  # and one that walks has a place to start the storyboard from
	rehearsal.name = &"rehearsal.knuckle"
	rehearsal.position = Vector3(-2.2, 0, 2.4)
	scene.marks.append(rehearsal)
	var lines: Array[String] = []
	var director := _start(parts, scene)
	assert_true(director != null, "the scene is taken without him: %s" % Director.last_refusal)
	if director == null:
		return
	director.line_shown.connect(func(_speaker: StringName, text: String) -> void: lines.append(text))
	assert_false(director.cast.has(&"knuckle"), "he is not in the cast")
	await _play_out()
	assert_eq(_finished, [false], "the scene plays to its end")
	assert_eq(lines, ["Fixture line one.", "Fixture line two."], "the lines of the absent actor still show")
	assert_eq(Game.state, Game.State.PLAY)


func test_a_paired_actor_is_waited_for_and_the_scene_then_starts() -> void:
	var results: Array = []
	for with_scene in [false, true]:
		var parts := StoryStage.make(self)
		var player: Actor = parts.player
		var victim := StoryStage.knuckle(parts.region, Vector3(0, 0, 1.0), PI, "Victim")
		await frames(3)
		assert_true(player.start_paired(victim, player.def.finisher))
		await frames(3)
		var clip := player.rig.tree.get_animation(player.runner.current.clip)
		var director: Director = null
		var begun_paired := false
		if with_scene:
			while ceili((clip.length - player.runner.time) * 60.0) > Director.PAIR_WAIT - 10:
				await frames(1)
			director = _start(parts, _fixture())
			assert_true(director != null, "the scene is taken: %s" % Director.last_refusal)
			begun_paired = player.paired_with != null
			if director == null:
				continue
			assert_eq(director.phase, Director.Phase.WAITING, "it waits for the pair")
		var guard := 0
		while (victim.paired_with != null or player.paired_with != null or player.runner.busy()) and guard < 400:
			if director != null and director.phase == Director.Phase.WAITING:
				assert_eq(director.frame, 0, "the clock has not started while he is in the pair")
			await frames(1)
			guard += 1
		if director != null:
			await frames(Director.START_WAIT + 2)
			assert_true(begun_paired, "he was still paired when it was asked for")
			assert_ne(director.phase, Director.Phase.WAITING, "and the scene has begun since")
		await frames(80)
		results.append([victim.stats.hp, victim.stats.posture, victim.dead])
	assert_eq(results[1], results[0], "the pair's result is what it is without a scene")


func test_a_spawned_actor_stands_at_its_mark_with_a_director_brain_and_is_never_the_enemy_brain_until_hand_back() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	var director := _start(parts, _fixture())
	assert_true(director != null)
	if director == null:
		return
	var foe: Actor = director.cast.get(&"knuckle")
	assert_true(foe != null, "the Knuckle is made")
	if foe == null:
		return
	var mark := Transform3D(Basis(Vector3.UP, player.rotation.y), Vector3(3, 0, 4)) * Vector3(2.2, 0, 2.6)
	assert_vec_near(foe.global_position, mark, 0.02, "at the foe_in mark, in Abarax's space as he stood")
	assert_true(foe.brain is DirectorBrain, "with a DirectorBrain")
	assert_true(foe.get_parent() == parts.region, "in the region")
	assert_true(foe.is_in_group(Actor.LOCKABLE_GROUP), "an enemy of the game's rules")
	var enemy_before := 0
	while director.phase != Director.Phase.LEAD_OUT and director.phase != Director.Phase.DONE:
		if foe.brain is EnemyBrain:
			enemy_before += 1
		await frames(1)
	assert_eq(enemy_before, 0, "it is never the EnemyBrain before the hand-back")
	assert_true(foe.brain is EnemyBrain, "and it is, at the hand-back (the fixture's `after` is ENEMY_BRAIN)")


func test_after_keep_free_and_enemy_brain() -> void:
	var seeds: Array[int] = []
	for after: CastEntry.After in [CastEntry.After.KEEP, CastEntry.After.FREE, CastEntry.After.ENEMY_BRAIN, CastEntry.After.ENEMY_BRAIN]:
		var parts := StoryStage.make(self)
		await frames(3)
		_finished = []
		var scene := _fixture()
		scene.cast[1].after = after
		var director := _start(parts, scene)
		assert_true(director != null)
		if director == null:
			return
		var foe: Actor = director.cast.get(&"knuckle")
		var seen := {}
		director.finished.connect(func(_skipped: bool) -> void:
			seen["parent"] = foe.get_parent()
			seen["brain"] = foe.brain)
		await _play_out()
		assert_eq(_finished, [false], "the scene ends")
		match after:
			CastEntry.After.KEEP:
				assert_true(seen.parent == parts.region, "KEEP: he is still there")
				assert_false(seen.brain is EnemyBrain or seen.brain is DirectorBrain, "KEEP: with no brain")
			CastEntry.After.FREE:
				assert_true(seen.parent == null, "FREE: he is gone when the camera has arrived")
			CastEntry.After.ENEMY_BRAIN:
				assert_true(seen.brain is EnemyBrain, "ENEMY_BRAIN: he fights")
				seeds.append((seen.brain as EnemyBrain).rng.seed)
		parts.stage.free()
		await frames(1)
	assert_eq(seeds.size(), 2)
	assert_ne(seeds[0], seeds[1], "a second spawn rolls other dice")


func test_a_scene_that_is_not_in_play_state_is_refused() -> void:
	var parts := StoryStage.make(self)
	await frames(3)
	Game.change(Game.State.PAUSE)
	var before := _snap(parts)
	assert_true(_start(parts, _fixture()) == null, "not while paused")
	assert_eq(Director.last_refusal, &"not_playing")
	Game.change(Game.State.PLAY)
	Game.change(Game.State.MENU)
	assert_true(_start(parts, _fixture()) == null, "not in a menu")
	assert_eq(Director.last_refusal, &"not_playing")
	Game.change(Game.State.PLAY)
	assert_eq(_snap(parts).state, Game.State.PLAY)
	assert_eq(_snap(parts).brain, before.brain, "no brain was changed")
	var director := _start(parts, _fixture())
	assert_true(director != null, "playing, it is taken")


func test_a_second_scene_while_one_plays_is_refused() -> void:
	var parts := StoryStage.make(self)
	await frames(3)
	var first := _start(parts, _fixture())
	assert_true(first != null)
	if first == null:
		return
	assert_true(Director.current() == first, "it is the scene playing")
	await frames(5)
	var before := _snap(parts)
	assert_true(_start(parts, _fixture()) == null, "a second is refused")
	assert_eq(Director.last_refusal, &"already_playing")
	assert_eq(_snap(parts), before, "and nothing changed")
	assert_true(Director.current() == first, "the first plays on")
