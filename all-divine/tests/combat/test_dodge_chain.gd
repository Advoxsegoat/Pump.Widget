extends TestCase
## The dodge chain (spec 3.3, 3.6): defences that succeed in a row make a chain whose count sets the tempo of every sway and
## duck (Slip to 2, Quick 3 to 6, Flurry from 7), and each link makes the next dodge quicker, takes more posture from the
## attacker, and makes the blow that finally lands cost a stagger. What links it (an evade, a parry or a catch he took), what
## knocks him out of it (a blow that lands, a grab, a broken guard), what ends it (an attack, which cashes it, a dash-step, a
## hop, a walk, sixty frames), and the whiff rule (after a dodge that avoided nothing, the next sway, duck or dash-step waits
## for twice the window).
##
## `a` is Abarax (a PLAYER, poise 5) at the origin facing +Z, `b` an ENEMY copy of him a metre in front. Blows are posted to
## Melee by hand (Blows), so a blow lands on an exact frame of `a`: one posted for frame F is judged at the end of it against
## how `a` stood when F began. A sway pressed on frame P (its f0) has its window open for blows on frames P+3 to P+2+window
## (Slip's sway: P+3 to P+12), and its cancel window opens on frame P+window+2 (P+12).

const ABARAX := "res://data/actors/abarax.tres"
const TUNING := "res://data/tuning/chain_open_hand.tres"
const O := HitResult.Outcome
const T := DodgeChain.Tempo
const ROUND := HitProfile.Line.ROUND
const PERILOUS := HitProfile.Perilous
const SWAY := &"sway"
const DUCK := &"duck"


# A ScriptBrain's steps for `presses`, each [frame, [actions], extra step fields (move, hold)]: the actions are pressed on that
# actor frame, and nothing else happens.
static func _script(presses: Array) -> Array:
	var steps := []
	var at := 0
	for press: Array in presses:
		var gap: int = press[0] - at - 1
		if gap > 0:
			steps.append({"frames": gap})
		var step := {"frames": 1, "press": press[1]}
		if press.size() > 2:
			step.merge(press[2])
		steps.append(step)
		at = press[0]
	return steps


# {arena, a, b, log, started}: `a` plays `steps`; `log` is what its chain said ([signal, args...]) and `started` the moves it
# started ([frame, id]).
func _world(steps := [], b_def: ActorDef = null) -> Dictionary:
	var run := Duel.make(self, steps, [], 1.0, b_def)
	var a: Actor = run["a"]
	run["log"] = []
	run["started"] = []
	var log: Array = run["log"]
	a.chain.linked.connect(func(perfect: bool) -> void: log.append([&"linked", perfect]))
	a.chain.knocked_out.connect(func(from: DodgeChain.Tempo) -> void: log.append([&"knocked_out", from]))
	a.chain.cashed.connect(func(at: DodgeChain.Tempo) -> void: log.append([&"cashed", at]))
	a.chain.changed.connect(func(count: int, tempo: DodgeChain.Tempo) -> void: log.append([&"changed", count, tempo]))
	var started: Array = run["started"]
	a.runner.move_started.connect(func(move: MoveData) -> void: started.append([a.frame, move.id]))
	return run


# Gives `a` a chain of `count`, made on its frame 0 (what it said while it was made is not in the log).
func _prime(run: Dictionary, count: int) -> void:
	for i in count:
		(run["a"] as Actor).chain.link(false, 0)
	(run["log"] as Array).clear()


# Plays until `a` has lived `last` frames, posting the `blows` ([frame to land on, profile fields]) from `b` on the way.
func _play(run: Dictionary, blows: Array, last: int) -> void:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	while a.frame < last:
		for blow: Array in blows:
			if blow[0] == a.frame + 1:
				Blows.post(b, a, blow[1])
		await frames(1)


# How many frames of no success the chain lives, from the tuning.
static func _timeout() -> int:
	return (load(TUNING) as ChainTuning).timeout_frames


static func _signals(run: Dictionary, which: StringName) -> Array:
	return (run["log"] as Array).filter(func(l: Array) -> bool: return l[0] == which)


# --- what builds it ---

func test_an_evade_and_a_parry_add_one_and_a_perfect_dodge_adds_two() -> void:
	# a sway pressed on f10: a round blow is evaded (not perfect), a straight one is the perfect dodge
	var round_evade := _world(_script([[10, [SWAY]]]))
	await _play(round_evade, [[14, {"line": ROUND}]], 20)
	assert_eq((round_evade["a"] as Actor).chain.count, 1, "an evade that is not perfect adds one")
	assert_eq(_signals(round_evade, &"linked"), [[&"linked", false]])
	var perfect := _world(_script([[10, [SWAY]]]))
	await _play(perfect, [[14, {}]], 20)
	assert_eq((perfect["a"] as Actor).chain.count, 2, "a perfect dodge adds two")
	assert_eq(_signals(perfect, &"linked"), [[&"linked", true]])
	# a parry pressed on f1 has its window open for blows on f2 to f11; a thrust is caught in it
	var parry := _world(_script([[1, [&"guard"]]]))
	await _play(parry, [[6, {}]], 12)
	assert_eq((parry["a"] as Actor).chain.count, 1, "a parry adds one, when the blow is taken")
	var catch_run := _world(_script([[1, [&"guard"]]]))
	await _play(catch_run, [[6, {"perilous": PERILOUS.THRUST}]], 12)
	assert_eq((catch_run["a"] as Actor).chain.count, 1, "a catch adds one")
	# two blows slipped by one sway are two evades
	var two := _world(_script([[10, [SWAY]]]))
	await _play(two, [[14, {"line": ROUND}], [16, {"line": ROUND}]], 20)
	assert_eq((two["a"] as Actor).chain.count, 2, "each blow a window avoids adds its own link")


func test_the_tempo_is_slip_to_two_quick_to_six_flurry_from_seven() -> void:
	assert_eq(ChainTuning.new().timeout_frames, 90, "the default timeout")
	assert_eq(_timeout(), 90, "and Abarax's")
	var chain := DodgeChain.new(load(TUNING) as ChainTuning)
	var changes := []
	chain.changed.connect(func(count: int, tempo: DodgeChain.Tempo) -> void: changes.append([count, tempo]))
	assert_eq(chain.tempo(), T.SLIP, "an empty chain is Slip")
	var seen := []
	for i in 8:
		chain.link(false, i)
		seen.append(chain.tempo())
	assert_eq(seen, [T.SLIP, T.SLIP, T.QUICK, T.QUICK, T.QUICK, T.QUICK, T.FLURRY, T.FLURRY], "counts 1 to 8")
	assert_eq(chain.count, 8)
	assert_eq(changes.size(), 8, "every link says it changed")
	assert_eq(changes[2], [3, T.QUICK])
	var fresh := DodgeChain.new(load(TUNING) as ChainTuning)
	fresh.link(true, 0)
	fresh.link(true, 1)
	assert_eq([fresh.count, fresh.tempo()], [4, T.QUICK], "perfect dodges add two each")
	for i in 2:
		fresh.link(true, 2 + i)
	assert_eq([fresh.count, fresh.tempo()], [8, T.FLURRY])
	fresh.end()
	assert_eq([fresh.count, fresh.tempo()], [0, T.SLIP], "ended: empty again")


func test_each_tempo_starts_its_own_sway_and_duck() -> void:
	var rows := [[0, &"sway_left_slip", 6.0, &"duck_slip", 8.0], [3, &"sway_left_quick", 4.0, &"duck_quick", 5.0],
			[6, &"sway_left_quick", 4.0, &"duck_quick", 5.0], [7, &"sway_left_flurry", 3.0, &"duck_flurry", 4.0]]
	for row: Array in rows:
		for pressed: Array in [[SWAY, row[1], row[2]], [DUCK, row[3], row[4]]]:
			var run := _world(_script([[1, [pressed[0]]]]))
			var a: Actor = run["a"]
			_prime(run, row[0])
			await _play(run, [], 1)
			var what := "a %s at a chain of %d" % [pressed[0], row[0]]
			assert_eq(a.runner.current.id if a.runner.current != null else &"", pressed[1], what)
			assert_eq(a.stats.stamina, 100.0 - float(pressed[2]), "%s costs %s" % [what, pressed[2]])
	# the side of a sway still comes from the press: a direction to his right is the right sway of the tempo
	var run := _world([{"frames": 1, "press": [SWAY], "evade_dir": Vector2(-1, 0)}])
	_prime(run, 3)
	await _play(run, [], 1)
	assert_eq((run["a"] as Actor).runner.current.id, &"sway_right_quick", "the tempo's own right sway")


func test_a_perfect_dodge_gives_its_cost_back_and_four_more() -> void:
	var run := _world(_script([[10, [SWAY]]]))
	var a: Actor = run["a"]
	a.stats.spend_stamina(50.0)
	await _play(run, [[14, {}]], 20)
	assert_eq(a.stats.stamina, 54.0, "50 less the sway's 6, plus 6 and 4 back")
	var other := _world(_script([[10, [SWAY]]]))
	var b_run: Actor = other["a"]
	b_run.stats.spend_stamina(50.0)
	await _play(other, [[14, {"line": ROUND}]], 20)
	assert_eq(b_run.stats.stamina, 44.0, "an evade that is not perfect gives nothing back")
	# the refund is only added: it does not make stamina wait again
	var stats := Stats.from_def(load(ABARAX) as ActorDef)
	stats.spend_stamina(50.0)
	stats.tick(0.3, false)
	stats.refund_stamina(10.0)
	assert_eq(stats.stamina, 60.0, "refunded")
	stats.tick(0.3, false)
	stats.tick(0.1, false)
	assert_near(stats.stamina, 64.5, 1e-4, "the wait of 0.6 s counts from the spend, not from the refund")
	stats.refund_stamina(500.0)
	assert_eq(stats.stamina, stats.max_stamina, "never above the maximum")
	stats.refund_stamina(-5.0)
	assert_eq(stats.stamina, stats.max_stamina, "a refund of nothing or less changes nothing")


# --- what the chain does to the attacker ---

func test_an_evade_takes_posture_from_its_attacker_from_quick_on() -> void:
	# a round blow against a sway is not perfect, a straight one is: chip 0, 4, 8, doubled when perfect
	for row: Array in [[0, 0.0, 0.0], [3, 4.0, 8.0], [7, 8.0, 16.0]]:
		for perfect: bool in [false, true]:
			var run := _world(_script([[10, [SWAY]]]))
			var a: Actor = run["a"]
			var b: Actor = run["b"]
			_prime(run, row[0])
			await _play(run, [[14, {} if perfect else {"line": ROUND}]], 18)
			var taken: float = row[2] if perfect else row[1]
			var what := "chain %d, perfect %s" % [row[0], perfect]
			assert_eq(b.stats.posture, 100.0 - taken, what)
			assert_eq(a.stats.hp, 100.0, "%s: not a scratch" % what)
			assert_true(b.runner.current == null, "%s: the attacker has no reaction of its own" % what)


func test_a_string_dodged_through_can_break_the_attacker() -> void:
	var weak := Duel.def(ActorDef.Team.ENEMY, 5.0)
	weak.max_posture = 60.0
	# four sways at Flurry, each cancelled into the next once the blow it evaded is past: 16 posture a perfect dodge
	var run := _world(_script([[10, [SWAY]], [20, [SWAY]], [30, [SWAY]], [40, [SWAY]]]), weak)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	_prime(run, 7)
	await _play(run, [[14, {}], [24, {}], [34, {}]], 38)
	assert_eq(b.stats.posture, 12.0, "three blows in: 60 less 3 times 16, one blow from breaking")
	assert_false(b.stats.posture_broken)
	await _play(run, [[44, {}]], 48)
	assert_true(b.stats.posture_broken, "the fourth breaks it")
	assert_true(b.is_in_group(Actor.FINISHABLE_GROUP), "and it is open to a finisher")
	assert_eq(b.runner.current.id if b.runner.current != null else &"", &"posture_broken", "it reels as any broken posture does")
	assert_eq(a.stats.hp, 100.0)


# --- what a blow that lands does ---

func test_a_blow_landing_at_quick_or_flurry_staggers_whatever_its_weight() -> void:
	for count in [3, 6, 7]:
		var run := _world()
		var a: Actor = run["a"]
		_prime(run, count)
		await _play(run, [[5, {"poise_damage": 1.0}]], 5)
		assert_eq(a.stats.hp, 92.0, "chain %d: it hurts" % count)
		assert_eq(a.runner.current.id if a.runner.current != null else &"", &"stagger", "chain %d: and staggers, though 1 poise damage is under his 5" % count)
		assert_eq(a.chain.count, 0, "chain %d: knocked out" % count)
		assert_eq(_signals(run, &"knocked_out"), [[&"knocked_out", T.QUICK if count < 7 else T.FLURRY]])
		assert_eq(_signals(run, &"linked"), [])


func test_a_blow_landing_at_slip_is_an_ordinary_hit() -> void:
	for count in [0, 2]:
		var run := _world()
		var a: Actor = run["a"]
		_prime(run, count)
		await _play(run, [[5, {"poise_damage": 1.0}]], 5)
		assert_eq(a.stats.hp, 92.0)
		assert_true(a.runner.current == null, "chain %d: a blow under his poise does not even flinch him" % count)
		assert_eq(a.chain.count, 0, "chain %d: but the chain is gone" % count)
	var heavy := _world()
	await _play(heavy, [[5, {"poise_damage": 8.0}]], 5)
	assert_eq((heavy["a"] as Actor).runner.current.id, &"flinch", "and one over it is the flinch it always was")


func test_a_thrust_into_a_flurry_lands_and_staggers() -> void:   # Review Focus 5
	var run := _world(_script([[10, [SWAY]]]))
	var a: Actor = run["a"]
	_prime(run, 7)
	await _play(run, [[14, {"perilous": PERILOUS.THRUST, "poise_damage": 1.0}]], 14)
	assert_eq(a.stats.hp, 92.0, "the window does not stop a thrust")
	assert_eq(a.runner.current.id, &"stagger", "and at Flurry it staggers")
	assert_eq(a.chain.count, 0)


func test_an_evaded_jab_and_a_landed_sweep_on_one_frame_knock_him_out() -> void:   # Review Focus 1
	var run := _world(_script([[10, [SWAY]]]))
	var a: Actor = run["a"]
	_prime(run, 3)
	await _play(run, [[14, {}], [14, {"perilous": PERILOUS.SWEEP, "height": HitProfile.Height.LOW, "poise_damage": 1.0}]], 14)
	assert_eq(a.chain.count, 0, "knocked out, not linked to 4")
	assert_eq(_signals(run, &"knocked_out"), [[&"knocked_out", T.QUICK]], "once, from Quick")
	assert_eq(_signals(run, &"linked"), [], "the evade did not link on the frame a blow landed")
	assert_eq(a.stats.hp, 92.0, "the sweep's 8")
	assert_false(a.runner.evaded, "the landed blow wins")
	assert_eq(a.runner.current.id, &"stagger", "and at Quick it staggers him")
	assert_eq(a.stats.stamina, 96.0, "the dodge was not perfect enough to pay back: 100 less the Quick sway's 4")


# --- what ends it ---

func test_what_ends_the_chain() -> void:
	# an attack: cashed, and the attack's tempo is kept for whoever reads it
	var attack := _world(_script([[5, [&"palm"]], [30, [&"dodge"]]]))
	var a: Actor = attack["a"]
	_prime(attack, 5)
	await _play(attack, [], 4)
	assert_eq(a.chain.count, 5, "f4: still there")
	await _play(attack, [], 6)
	assert_eq(a.chain.count, 0, "an attack cashes it")
	assert_eq(a.cashed_tempo, T.QUICK, "at the tempo it had")
	assert_eq(_signals(attack, &"cashed"), [[&"cashed", T.QUICK]])
	await _play(attack, [], 31)
	assert_eq(a.cashed_tempo, T.SLIP, "any other move started puts it back to Slip")
	# a dash-step (the stick held) and a hop (it is not) end it, and a sway does not
	for case: Array in [["dash-step", [[5, [&"dodge"], {"move": Vector2(1, 0)}]]], ["hop", [[5, [&"dodge"]]]]]:
		var run := _world(_script(case[1]))
		_prime(run, 5)
		await _play(run, [], 6)
		assert_eq((run["a"] as Actor).chain.count, 0, "a %s ends it" % case[0])
		assert_eq(_signals(run, &"cashed"), [], "without cashing it")
		assert_eq(_signals(run, &"knocked_out"), [], "or knocking him out")
	var sway := _world(_script([[5, [SWAY]]]))
	_prime(sway, 5)
	await _play(sway, [], 20)
	assert_eq((sway["a"] as Actor).chain.count, 5, "a sway does not")
	# walking, once the legs move him
	var walk := _world([{"frames": 10}, {"frames": 30, "move": Vector2(1, 0)}])
	_prime(walk, 5)
	await _play(walk, [], 10)
	assert_eq((walk["a"] as Actor).chain.count, 5, "standing still ends nothing")
	await _play(walk, [], 14)
	assert_eq((walk["a"] as Actor).chain.count, 0, "a walk does")
	# the timeout with no success
	var late := _world()
	_prime(late, 5)
	await _play(late, [], _timeout() - 1)
	assert_eq((late["a"] as Actor).chain.count, 5, "one frame short of the timeout")
	await _play(late, [], _timeout())
	assert_eq((late["a"] as Actor).chain.count, 0, "the timeout's frames after the last link it is gone")
	# a broken guard: guard held through, with less stamina than the blow's guard cost
	var broken := _world(_script([[1, [&"guard"], {"frames": 40, "hold": [&"guard"]}]]))
	var held: Actor = broken["a"]
	held.stats.spend_stamina(97.0)
	_prime(broken, 5)
	await _play(broken, [[13, {}]], 13)
	assert_eq(held.chain.count, 0, "a broken guard ends it")
	assert_eq(_signals(broken, &"knocked_out"), [[&"knocked_out", T.QUICK]])


func test_a_guarded_blow_neither_builds_nor_ends_it() -> void:
	var run := _world(_script([[1, [&"guard"], {"frames": 40, "hold": [&"guard"]}]]))
	var a: Actor = run["a"]
	_prime(run, 3)
	await _play(run, [[13, {}]], 20)
	assert_eq(a.stats.hp, 100.0, "the guard took it")
	assert_eq(a.chain.count, 3, "the chain stands where it was")
	assert_eq(_signals(run, &"linked"), [])
	assert_eq(_signals(run, &"knocked_out"), [])


func test_frozen_frames_do_not_run_the_timeout() -> void:   # Review Focus 3
	var run := _world()
	var a: Actor = run["a"]
	_prime(run, 3)
	a.freeze(80)
	await _play(run, [], 80 + _timeout() - 1)
	assert_eq(a.buffer_frame, _timeout() - 1, "eighty of the frames were frozen")
	assert_eq(a.chain.count, 3, "a chain neither times out nor ages while the fight is held")
	await _play(run, [], 80 + _timeout())
	assert_eq(a.chain.count, 0, "it goes the timeout's live frames after its last link")
	# and the counting alone: tick takes the actor's own clock
	var chain := DodgeChain.new(load(TUNING) as ChainTuning)
	chain.link(false, 10)
	chain.tick(10 + _timeout() - 1)
	assert_eq(chain.count, 1, "one frame short")
	chain.tick(10 + _timeout())
	assert_eq(chain.count, 0, "the timeout's frames on")
	chain.tick(500)
	assert_eq(chain.count, 0, "an empty chain has nothing to time out")
	assert_eq(_signals(run, &"knocked_out"), [], "the timeout is no knock-out")


# --- the whiff rule ---

func test_after_a_miss_the_next_sway_waits_for_the_redodge_frame() -> void:
	# [action, chain, the frames from its start that bar the next one]: the spec's 20, 16, 12 and 24, 18, 14
	for row: Array in [[SWAY, 0, 20], [SWAY, 3, 16], [SWAY, 7, 12], [DUCK, 0, 24], [DUCK, 3, 18], [DUCK, 7, 14]]:
		# the second press is made as early as the buffer keeps it, and is held until its frame
		var run := _world(_script([[10, [row[0]]], [10 + row[2] - 9, [row[0]]]]))
		_prime(run, row[1])
		await _play(run, [], 10 + row[2] + 2)
		var starts: Array = run["started"]
		assert_eq(starts.size(), 2, "%s at chain %d: two moves started: %s" % [row[0], row[1], starts])
		assert_eq(starts[0][0], 10)
		assert_eq(starts[1][0], 10 + row[2], "%s at chain %d: the second starts %d frames after the first" % [row[0], row[1], row[2]])
		assert_eq(starts[1][1], starts[0][1], "and is the same tempo's move")


func test_after_an_evade_the_next_sway_starts_when_the_window_closes() -> void:
	var run := _world(_script([[10, [SWAY]], [15, [SWAY]]]))
	await _play(run, [[14, {"line": ROUND}]], 30)
	var starts: Array = run["started"]
	assert_eq(starts.map(func(s: Array) -> int: return s[0]), [10, 22], "the next sway starts the frame the evade window closes: %s" % [starts])
	assert_eq((run["a"] as Actor).chain.count, 1)


func test_a_guard_tap_between_two_missed_sways_does_not_shorten_the_wait() -> void:
	# the guard raise opens a sway window of its own at its f2: the wait is the dodge's, counted from its start
	var run := _world(_script([[10, [SWAY]], [20, [&"guard"]], [22, [SWAY]]]))
	await _play(run, [], 34)
	assert_eq(run["started"], [[10, &"sway_left_slip"], [22, &"guard_raise"], [30, &"sway_left_slip"]],
			"the second sway waits for frame 30, 20 after the first, whatever played in between")


func test_after_a_miss_a_dash_step_waits_too() -> void:
	var run := _world(_script([[10, [SWAY]], [21, [&"dodge"]]]))
	await _play(run, [], 34)
	var starts: Array = run["started"]
	assert_eq(starts.size(), 2, str(starts))
	assert_eq(starts[1][0], 30, "a dash-step or hop is left in the buffer until the sway's 20 frames are gone: %s" % [starts])


# --- fix round 1 ---

func test_one_sway_through_three_blows_is_refunded_once_and_links_three_times() -> void:
	for blows in [1, 2, 3]:
		var run := _world(_script([[10, [SWAY]]]))
		var a: Actor = run["a"]
		a.stats.spend_stamina(50.0)
		var posted := []
		for i in blows:
			posted.append([14, {}])
		await _play(run, posted, 20)
		assert_eq(a.stats.stamina, 54.0, "%d blows: one sway, paid for once: 50 less 6, plus 6 and 4 back" % blows)
		assert_eq(a.chain.count, 2 * blows, "%d blows: the chain links per blow" % blows)


func test_a_finisher_cashes_the_chain() -> void:
	var run := _world(_script([[8, [&"palm"]]]))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	track(PostureBreaker.make(a, b))
	await _play(run, [], 2)
	assert_true(b.is_in_group(Actor.FINISHABLE_GROUP), "the foe's posture is broken")
	_prime(run, 3)
	await _play(run, [], 10)
	assert_true(a.paired_with == b, "the palm started the finisher")
	assert_eq(a.chain.count, 0, "and it cashed the chain")
	assert_eq(_signals(run, &"cashed"), [[&"cashed", T.QUICK]])
	assert_eq(a.cashed_tempo, T.QUICK, "at the tempo it had")


func test_what_does_not_end_the_chain() -> void:
	# a push (knockback), body spacing (a foe 0.45 m away), a planted guard with the stick held, a turn on the spot
	var push := _world()
	_prime(push, 5)
	(push["a"] as Actor).push(Vector3(0, 0, -6))
	await _play(push, [], 30)
	assert_true((push["a"] as Actor).global_position.z < -0.05, "he was pushed")
	assert_eq((push["a"] as Actor).chain.count, 5, "a push is no walk")
	var crowd := Duel.make(self, [], [], 0.45)
	(crowd["a"] as Actor).chain.link(false, 0)
	(crowd["a"] as Actor).chain.link(false, 0)
	await _play({"a": crowd["a"], "b": crowd["b"]}, [], 30)
	assert_eq((crowd["a"] as Actor).chain.count, 2, "being kept apart from a body is no walk")
	var planted := _world([{"frames": 40, "move": Vector2(1, 0), "hold": [&"guard"], "press": [&"guard"]}])
	_prime(planted, 5)
	await _play(planted, [], 30)
	assert_eq((planted["a"] as Actor).chain.count, 5, "a stick held under a planted guard is no walk")
	var turn := _world([{"frames": 40, "face_target": Vector3(5, 0, 0)}])
	_prime(turn, 5)
	await _play(turn, [], 30)
	assert_eq((turn["a"] as Actor).chain.count, 5, "turning on the spot is no walk")


func test_a_grab_that_takes_hold_knocks_him_out() -> void:
	var run := _world([], load("res://data/actors/knuckle_1.tres") as ActorDef)
	var b: Actor = run["b"]
	b.set_brain(ScriptBrain.new([{"frames": 1, "press": [&"interact"]}, {"frames": 200}]))
	var a: Actor = run["a"]
	_prime(run, 3)
	await _play(run, [], 50)
	assert_true(a.paired_with == b, "the grab took hold")
	assert_eq(a.chain.count, 0, "and knocked him out of the chain")
	assert_eq(_signals(run, &"knocked_out"), [[&"knocked_out", T.QUICK]])


func test_his_death_ends_the_chain() -> void:
	var run := _world()
	_prime(run, 4)
	(run["a"] as Actor).die()
	assert_eq((run["a"] as Actor).chain.count, 0)
	assert_eq(_signals(run, &"knocked_out"), [], "no loss to tell of")


func test_an_actor_with_no_chain_is_as_it_was() -> void:
	var knuckle := load("res://data/actors/knuckle_1.tres") as ActorDef
	var run := Duel.make(self, [], [], 1.0, null, knuckle)
	var k: Actor = run["a"]
	assert_true(k.chain == null, "a Knuckle has no chain")
	assert_eq(k.cashed_tempo, T.SLIP)
	var d := Defense.of(k)
	assert_eq([d.chain_tempo, d.evade_chip], [0, 0.0])
	await _play(run, [[5, {"poise_damage": 1.0}]], 5)
	assert_true(k.runner.current == null, "a blow under its poise still does not flinch it")
	# a body with a sway but no chain is refunded nothing for a perfect dodge
	var plain := Duel.def(ActorDef.Team.PLAYER, 5.0)
	plain.chain = null
	var world := Duel.make(self, _script([[10, [SWAY]]]), [], 1.0, null, plain)
	var a: Actor = world["a"]
	a.stats.spend_stamina(50.0)
	await _play(world, [[14, {}]], 20)
	assert_eq(a.stats.stamina, 44.0, "50 less the sway's 6, and nothing back")
