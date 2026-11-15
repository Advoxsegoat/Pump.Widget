extends TestCase
## The slow-down (spec 3.3): Melee.slow(frames, share) holds every living actor still on the frames a fixed pattern says,
## so that over `frames` physics frames each acts on `share` of them, spread evenly (ceil(frames x share) of them, the first
## of the lot among them). It is the actors' own freeze, the hit-stop's, and nothing else: a frozen frame does not age the
## input buffer, the chain's timeout, the counter window or the whiff rule's clock (they run on Actor.buffer_frame), a press
## made on one is buffered, and a fight replays to the same state from the same recorded input.
##
## `a` is Abarax (a PLAYER, poise 5) at the origin facing +Z, `b` an ENEMY copy a metre in front (Duel). An actor acted on a
## frame when its buffer_frame (its own clock, which stands still while it is frozen) rose.

const ABARAX := "res://data/actors/abarax.tres"
const TUNING := "res://data/tuning/chain_open_hand.tres"
const ROUND := HitProfile.Line.ROUND
const SWAY := &"sway"
const PALM := &"palm"
## Which of 12 frames an actor acts on at 40%: 5 of them, 2 or 3 frames apart.
const FORTY_PERCENT := [1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0]


# A ScriptBrain's steps for `presses`, each [frame, [actions]]: the actions are pressed on that actor frame.
static func _script(presses: Array) -> Array:
	var steps := []
	var at := 0
	for press: Array in presses:
		var gap: int = press[0] - at - 1
		if gap > 0:
			steps.append({"frames": gap})
		steps.append({"frames": 1, "press": press[1]})
		at = press[0]
	return steps


# Whether each of the next `n` frames was acted on by `actor`: 1 if its own clock rose on it, 0 if it stood still.
func _pattern(actor: Actor, n: int) -> Array:
	var seen := []
	for i in n:
		var before := actor.buffer_frame
		await frames(1)
		seen.append(actor.buffer_frame - before)
	return seen


func test_twelve_slowed_frames_let_actors_act_on_forty_percent_of_them() -> void:
	var run := Duel.make(self, [], [], 6.0)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await Duel.play_to(self, a, 5)
	assert_false(Melee.slowed(), "nothing is slowed to begin with")
	Melee.slow(12, 0.4)
	assert_true(Melee.slowed(), "it is slowed from the call")
	var a_acted := []
	var b_acted := []
	for i in 12:
		var a_before := a.buffer_frame
		var b_before := b.buffer_frame
		await frames(1)
		a_acted.append(a.buffer_frame - a_before)
		b_acted.append(b.buffer_frame - b_before)
	assert_eq(a_acted, FORTY_PERCENT, "Abarax acts on 5 of the 12 frames, 2 or 3 apart, the first among them")
	assert_eq(b_acted, FORTY_PERCENT, "and so does the foe: every living actor on the same frames")
	assert_false(Melee.slowed(), "and it is over after them")
	assert_eq(await _pattern(a, 6), [1, 1, 1, 1, 1, 1], "then every frame is acted on again")
	# a share of 1 slows nothing; a share of 0 holds everyone still; the dead are not frozen by it
	Melee.slow(6, 1.0)
	assert_eq(await _pattern(a, 6), [1, 1, 1, 1, 1, 1], "a share of one is no slow-down")
	Melee.slow(4, 0.0)
	assert_eq(await _pattern(a, 4), [0, 0, 0, 0], "a share of nothing holds the fight still")
	b.die()
	Melee.slow(4, 0.0)
	await frames(2)
	assert_eq(b.frozen, 0, "a dead actor is not frozen by it")


func test_a_slow_restarts_and_does_not_stack() -> void:
	var run := Duel.make(self, [], [], 6.0)
	var a: Actor = run["a"]
	await Duel.play_to(self, a, 5)
	Melee.slow(12, 0.4)
	var first := await _pattern(a, 6)
	assert_eq(first, FORTY_PERCENT.slice(0, 6), "six frames into the first")
	Melee.slow(12, 0.4)
	var second := await _pattern(a, 12)
	assert_eq(second, FORTY_PERCENT, "a second call starts the pattern over, for its own 12 frames")
	assert_false(Melee.slowed(), "and is over after them: the 6 that were left were not added to it")
	assert_eq(await _pattern(a, 3), [1, 1, 1])
	# a call with different numbers replaces the one that runs
	Melee.slow(12, 0.4)
	await frames(2)
	Melee.slow(3, 0.0)
	assert_eq(await _pattern(a, 4), [0, 0, 0, 1], "three frames held still, then free: the 12 it replaced do not go on")


func test_the_chains_timeout_and_the_counter_window_do_not_run_out_inside_a_slow() -> void:   # Review Focus 3
	var timeout := (load(TUNING) as ChainTuning).timeout_frames
	# The timeout: a chain linked on frame 0 times out when the actor's clock has run `timeout` frames. A slow of 12 frames at 40%
	# holds 7 of them still, so the chain lives 7 wall frames longer than it would.
	var run := Duel.make(self)
	var a: Actor = run["a"]
	a.chain.link(false, 0)
	a.chain.link(false, 0)
	a.chain.link(false, 0)
	await Duel.play_to(self, a, 5)
	Melee.slow(12, 0.4)
	await Duel.play_to(self, a, timeout + 7 - 1)
	assert_eq(a.buffer_frame, timeout - 1, "seven of the frames stood still")
	assert_eq(a.chain.count, 3, "the chain lives: the slowed frames were not counted")
	await Duel.play_to(self, a, timeout + 7)
	assert_eq(a.chain.count, 0, "and ends the live frames after its link, as ever")
	(run["arena"] as Node).queue_free()
	await frames(2)
	# The counter window: a sway on frame 10 evades a blow on frame 14; a palm pressed 24 live frames after is the counter and one
	# pressed 25 after is the jab. The press on wall frame 45 is 31 frames after the evade, 24 of the actor's own with the slow (7 held
	# frames), and 31 without it.
	var started := {}
	for slowed in [true, false]:
		var fight := Duel.make(self, _script([[10, [SWAY]], [45, [PALM]]]))
		var fighter: Actor = fight["a"]
		var ids: Array[StringName] = []
		fighter.runner.move_started.connect(func(move: MoveData) -> void: ids.append(move.id))
		while fighter.frame < 60:
			if fighter.frame + 1 == 14:
				Blows.post(fight["b"], fighter, {"line": ROUND})
			if slowed and fighter.frame == 20:
				Melee.slow(12, 0.4)
			await frames(1)
		started[slowed] = ids
		(fight["arena"] as Node).queue_free()
		await frames(2)
	assert_true((started[true] as Array).has(&"counter_hook"), "with the slow, the palm is the counter (started %s)" % [started[true]])
	assert_true((started[false] as Array).has(&"palm_jab"), "without it, the same press is the jab (started %s)" % [started[false]])


func test_a_press_made_on_a_held_frame_is_buffered_not_lost() -> void:
	# A palm pressed on frame 7 falls in the slow's held frames (the 12 slowed frames are 6 to 17: frames 7, 9, 10, 12, 14, 15, 17 are
	# held). It is buffered as a press in hit-stop is, and the jab starts on the first frame the actor acts on after it.
	var run := Duel.make(self, _script([[7, [PALM]]]), [], 6.0)
	var a: Actor = run["a"]
	var started := []
	a.runner.move_started.connect(func(move: MoveData) -> void: started.append([a.frame, move.id]))
	await Duel.play_to(self, a, 5)
	Melee.slow(12, 0.4)
	await Duel.play_to(self, a, 20)
	assert_eq(started.size(), 1, "the press came out once")
	assert_eq(started[0][1], &"palm_jab")
	assert_true(started[0][0] >= 7 and started[0][0] <= 9, "on the first frame the actor acted on after it (started on frame %d)" % started[0][0])


func test_a_slowed_fight_replays_to_the_same_state() -> void:
	var states := []
	for round in 2:
		# a trades blows with b through a slow that comes on frame 9 and another that restarts it on frame 16
		var steps := _script([[1, [PALM]], [14, [PALM]], [22, [SWAY]]])
		var fight := Duel.make(self, steps, _script([[3, [PALM]], [18, [PALM]]]))
		var a: Actor = fight["a"]
		var b: Actor = fight["b"]
		var moves := []
		for actor: Actor in [a, b]:
			actor.runner.move_started.connect(func(move: MoveData) -> void: moves.append([actor.name, actor.frame, move.id]))
		while a.frame < 70:
			if a.frame == 9 or a.frame == 16:
				Melee.slow(12, 0.4)
			await frames(1)
		states.append({
			a_at = a.global_position, b_at = b.global_position, a_hp = a.stats.hp, b_hp = b.stats.hp,
			a_posture = a.stats.posture, b_posture = b.stats.posture, moves = moves,
			a_time = a.runner.time, b_time = b.runner.time, a_buffer = a.buffer_frame,
		})
		(fight["arena"] as Node).queue_free()
		await frames(2)
	assert_true((states[0].moves as Array).size() >= 4, "the fight happened (%s)" % [states[0].moves])
	assert_eq(states[1], states[0], "the same input through the same slow-downs is the same fight")
	assert_true(states[0].b_hp < 100.0 or states[0].a_hp < 100.0, "someone was hit, so the slow-down was inside a real exchange")


func test_game_reset_ends_a_slow_down_that_was_running() -> void:
	# A slow-down is the game's: one left running when a game is freed would freeze the first frames of the next.
	Melee.slow(12, 0.4)
	assert_true(Melee.slowed(), "a slow-down is on")
	Game.reset()
	assert_false(Melee.slowed(), "and a reset of the game ends it")
