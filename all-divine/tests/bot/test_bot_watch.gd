extends TestCase
## What the combat bot calls a problem (BotWatch): a move that does not end, a player who can do nothing, an actor out of the
## yard or through the floor, a foe that never engages, and a fight that goes nowhere. Each is a fixture here that does it.

const KNUCKLE := "res://data/actors/knuckle_1.tres"


func after_each() -> void:
	Game.reset()


func test_a_move_that_outlasts_its_clip_by_a_second_is_a_soft_lock_on_the_actors_own_clock() -> void:
	var run := Duel.make(self, [], [{"frames": 100000, "hold": [&"heavy"]}], 3.0)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var watch := BotWatch.new()
	b.runner.start(EndlessMove.make(b, &"palm_heavy")["move"])
	var clip_frames := ceili(b.rig.tree.get_animation(&"endless_palm_heavy").length * 60.0)
	var problems := PackedStringArray()
	var frames_seen := 0
	while problems.is_empty() and frames_seen < clip_frames + 200:
		await frames(1)
		frames_seen += 1
		problems.append_array(watch.check(frames_seen, a, [a, b]))
	assert_eq(problems.size(), 1, "one problem: %s" % [problems])
	assert_true(String(problems[0]).contains("endless_palm_heavy"), "it names the move: %s" % [problems])
	assert_true(frames_seen > clip_frames + 55 and frames_seen < clip_frames + 80, "after the clip and a second: %d against a clip of %d" % [frames_seen, clip_frames])
	for i in 100:
		await frames(1)
		frames_seen += 1
		problems.append_array(watch.check(frames_seen, a, [a, b]))
	assert_eq(problems.size(), 1, "and it is said once")


func test_frozen_frames_do_not_count_toward_a_moves_length() -> void:
	var run := Duel.make(self, [], [], 3.0)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var watch := BotWatch.new()
	b.runner.start(Registry.fetch(&"moves", &"palm_heavy") as MoveData)
	b.runner.charging = false
	var problems := PackedStringArray()
	b.freeze(300)  # five seconds of hit-stop in the middle of the move
	for i in 150:
		await frames(1)
		problems.append_array(watch.check(i + 1, a, [a, b]))
	assert_true(problems.is_empty(), "a frozen foe is not stuck: %s" % [problems])


func test_an_actor_outside_the_yard_or_through_the_floor_is_a_broken_encounter() -> void:
	var run := Duel.make(self, [], [], 3.0)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var watch := BotWatch.new()
	assert_true(watch.check(1, a, [a, b]).is_empty(), "inside the yard is fine")
	b.global_position = Vector3(20.0, 0.0, 0.0)
	var out := watch.check(2, a, [a, b])
	assert_eq(out.size(), 1, "outside the walls: %s" % [out])
	assert_true(String(out[0]).contains("outside"), str(out))
	b.global_position = Vector3(0.0, -6.0, 0.0)
	var under := watch.check(3, a, [a, b])
	assert_eq(under.size(), 1, "below y = -5: %s" % [under])
	assert_true(watch.check(4, a, [a, b]).is_empty(), "and each is said once")


func test_the_player_who_can_do_nothing_for_ten_seconds_is_a_soft_lock() -> void:
	var run := Duel.make(self, [], [], 3.0)
	var a: Actor = run["a"]
	var watch := BotWatch.new()
	watch.stuck_frames = 40  # the real limit is 600
	var problems := PackedStringArray()
	for i in 60:
		await frames(1)
		problems.append_array(watch.check(i + 1, a, [a]))
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(String(problems[0]).contains("player"), str(problems))
	# one who starts a move is not stuck
	var other := Duel.make(self, [{"frames": 20}, {"frames": 1, "press": [&"palm"]}, {"frames": 25}, {"frames": 1, "press": [&"palm"]}, {"frames": 25}], [], 5.0)
	var watch2 := BotWatch.new()
	watch2.stuck_frames = 40
	var more := PackedStringArray()
	for i in 60:
		await frames(1)
		more.append_array(watch2.check(i + 1, other["a"], [other["a"]]))
	assert_true(more.is_empty(), "moves count as acting: %s" % [more])


func test_a_foe_that_never_engages_is_a_broken_encounter() -> void:
	var arena := TestArena.make(self)
	var player := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), Brain.new(), Vector3.ZERO, "A")
	var deaf := (load(KNUCKLE) as ActorDef).duplicate() as ActorDef
	deaf.brain = deaf.brain.duplicate() as BrainDef
	deaf.brain.sight_range = 0.0
	deaf.brain.hearing_range = 0.0
	var foe := (load(TestArena.ACTOR) as PackedScene).instantiate() as Actor
	foe.name = "Deaf"
	foe.def = deaf
	foe.position = Vector3(8.0, 0.0, 0.0)
	arena.add_child(foe)
	var watch := BotWatch.new()
	watch.engage_frames = 60  # the real limit is 900
	watch.stuck_frames = 100000
	var problems := PackedStringArray()
	for i in 90:
		await frames(1)
		problems.append_array(watch.check(i + 1, player, [player, foe]))
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(String(problems[0]).contains("never engages"), str(problems))


func test_no_wave_progress_for_ninety_seconds_is_a_soft_lock() -> void:
	var run := Duel.make(self, [], [], 3.0)
	var a: Actor = run["a"]
	var watch := BotWatch.new()
	watch.stuck_frames = 100000
	watch.note_progress(0)
	assert_true(watch.check(5399, a, [a]).is_empty(), "89.98 seconds is not yet")
	var out := watch.check(5401, a, [a])
	assert_eq(out.size(), 1, "%s" % [out])
	assert_true(String(out[0]).contains("wave"), str(out))
	watch.note_progress(6000)
	assert_true(watch.check(6100, a, [a]).is_empty(), "progress starts the count again")


func test_a_wave_not_cleared_in_five_deaths_is_a_finding_and_a_clear_starts_the_count_again() -> void:
	var watch := BotWatch.new()
	for i in 4:
		assert_eq(watch.note_death(3), "", "death %d in wave 3 is only a death" % (i + 1))
	var finding := watch.note_death(3)
	assert_true(finding.contains("wave 3") and finding.contains("five deaths"), "the fifth is a finding: %s" % finding)
	assert_eq(watch.note_death(3), "", "and it is said once")
	assert_eq(watch.note_death(4), "", "another wave counts for itself")
	watch.note_cleared(4)
	for i in 3:
		watch.note_death(4)
	assert_eq(watch.note_death(4), "", "a wave cleared in between starts its count again: four deaths since is not five")
	assert_true(watch.note_death(4).contains("five deaths"), "and the fifth since is a finding")


func test_the_bounds_are_the_walkable_ground_of_the_arena() -> void:
	var yard := track((load("res://world/training_yard/training_yard.tscn") as PackedScene).instantiate()) as Node3D
	await frames(2)
	var bounds := BotWatch.bounds_of(yard)
	assert_true(bounds.position.x < -12.0 and bounds.position.x > -14.0, "the west wall: %s" % [bounds])
	assert_true(bounds.end.x > 12.0 and bounds.end.x < 14.0, "the east wall: %s" % [bounds])
	assert_true(bounds.position.y < -12.0 and bounds.position.y > -14.0, "the north wall: %s" % [bounds])
	assert_true(bounds.end.y > 12.0 and bounds.end.y < 14.0, "the south kerb, a low one the ray still finds: %s" % [bounds])
