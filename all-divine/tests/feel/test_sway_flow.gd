extends TestCase
## Feel: the chain as it is played. A string of blows that gathers speed (gaps of 30, 26, 22, 18, 14 and 12 frames) is
## climbed from Slip to Flurry by a player who stands his ground, a real tier I Knuckle's jab, cross and hooks are answered
## by a parry, sways and a duck, and mashing the sway or duck button covers at most half of any stretch at every tempo and
## builds nothing.
##
## `a` is Abarax (a PLAYER) at the origin facing +Z, `b` an attacker a metre in front. Blows are posted to Melee by hand
## from `b` (Blows) on exact frames of `a`: a blow for frame F is judged at the end of F against how `a` stood when F began.
## A dodge pressed on frame P starts on P (its f0); its window is open for blows on P+3 to P+2+window, and the next dodge
## can start from P+window+2 when the blow was evaded.

const T := DodgeChain.Tempo
const ROUND := HitProfile.Line.ROUND
const KNUCKLE := "res://data/actors/knuckle_1.tres"
## The seven blows, as [frame, line]: S is a straight blow (the perfect dodge is a sway), R a round one (a duck).
const STRING := [[40, "S"], [70, "S"], [96, "R"], [118, "S"], [136, "R"], [150, "S"], [162, "R"]]
## How many frames before each blow its dodge is pressed.
const LEAD := 4


# A ScriptBrain's steps for `presses`, each [frame, action]: the action is pressed on that actor frame.
static func _script(presses: Array) -> Array:
	var steps := []
	var at := 0
	for press: Array in presses:
		if press[0] - at - 1 > 0:
			steps.append({"frames": press[0] - at - 1})
		steps.append({"frames": 1, "press": [press[1]]})
		at = press[0]
	return steps


func test_seven_blows_gathering_speed_are_climbed_to_flurry_without_a_scratch() -> void:
	var presses := []
	for blow: Array in STRING:
		presses.append([blow[0] - LEAD, &"sway" if blow[1] == "S" else &"duck"])
	var attacker := load(KNUCKLE) as ActorDef  # a tier I Knuckle's posture: 60
	var run := Duel.without_slow(Duel.make(self, _script(presses), [], 1.0, attacker))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	a.stats.spend_stamina(50.0)
	var started := []
	a.runner.move_started.connect(func(move: MoveData) -> void: started.append([a.frame, move.id]))
	# the trace: one row per blow, read after the frame it lands on
	var trace := []
	var index := 0
	while a.frame < 170:
		if index < STRING.size() and STRING[index][0] == a.frame + 1:
			Blows.post(b, a, {"line": ROUND} if STRING[index][1] == "R" else {})
		await frames(1)
		if index < STRING.size() and STRING[index][0] == a.frame:
			trace.append([a.frame, STRING[index][1], a.chain.count, a.chain.tempo(), a.stats.stamina, b.stats.posture])
			index += 1
	assert_eq(started.map(func(s: Array) -> StringName: return s[1]),
			[&"sway_left_slip", &"sway_left_slip", &"duck_quick", &"sway_left_quick", &"duck_flurry", &"sway_left_flurry", &"duck_flurry"],
			"each dodge is the tempo the chain had when it was pressed: %s" % [started])
	assert_eq(started.map(func(s: Array) -> int: return s[0]), presses.map(func(p: Array) -> int: return p[0]),
			"and each starts on the frame it was pressed, the one before not in its way")
	assert_eq(trace.map(func(t: Array) -> int: return t[2]), [2, 4, 6, 8, 10, 12, 14], "a perfect dodge each time: two links a blow: %s" % [trace])
	assert_eq(trace.map(func(t: Array) -> int: return t[3]), [T.SLIP, T.QUICK, T.QUICK, T.FLURRY, T.FLURRY, T.FLURRY, T.FLURRY])
	assert_eq(a.stats.hp, 100.0, "not a scratch")
	assert_true(a.stats.stamina >= 50.0, "every perfect dodge paid for itself")
	assert_true(b.stats.posture_broken or b.stats.posture <= 12.0, "the attacker is broken or one counter from it: posture %s" % [b.stats.posture])
	assert_eq(a.chain.tempo(), T.FLURRY)


func test_parry_sway_sway_duck_takes_no_damage_from_jab_cross_hook() -> void:
	# A real tier I Knuckle on a ScriptBrain. Its first jab (on frame 1) is parried; it reels, and once it is free again (frame 60)
	# it throws its string: jab, cross, hook, pressed so each cancels into the next as soon as it can. Abarax sways the jab,
	# sways the cross and ducks the hook, each pressed four frames before its blow lands (the jab lands on frame 80, the cross
	# on 110, the hook on 155: the Knuckle's own timing; the slow-down is off here, as it would move the blows against the presses). The chain
	# climbs 1, 3, 5, 7, and the whole of it fits inside sixty frames without a defence that succeeds.
	var knuckle := load(KNUCKLE) as ActorDef
	var a_steps := []
	var at := 0
	for press: Array in [[14, &"guard"], [76, &"sway"], [106, &"sway"], [151, &"duck"]]:
		a_steps.append({"frames": press[0] - at - 1})
		a_steps.append({"frames": 1, "press": [press[1]]})
		at = press[0]
	var b_steps := []
	at = 0
	for frame: int in [1, 60, 80, 110]:
		b_steps.append({"frames": frame - at - 1})
		b_steps.append({"frames": 1, "press": [&"palm"]})
		at = frame
	var run := Duel.without_slow(Duel.make(self, a_steps, b_steps, 1.0, knuckle))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var outcomes := []
	a.got_hit.connect(func(r: HitResult, e: HitEvent) -> void: outcomes.append([a.frame, HitResult.Outcome.keys()[r.outcome], e.move.id]))
	var started := []
	a.runner.move_started.connect(func(move: MoveData) -> void: started.append(move.id))
	while a.frame < 170:
		await frames(1)
	assert_eq(outcomes, [[21, "PARRIED", &"knuckle_jab"], [80, "EVADED", &"knuckle_jab"], [110, "EVADED", &"knuckle_cross"],
			[155, "EVADED", &"knuckle_hook"]], "the jab parried, then each blow of the string evaded")
	assert_eq(a.stats.hp, 100.0, "no damage")
	assert_eq(started, [&"guard_raise", &"parry", &"sway_left_slip", &"sway_left_quick", &"duck_quick"], "the tempo of each dodge is the chain's at the time")
	assert_eq([a.chain.count, a.chain.tempo()], [7, T.FLURRY], "the parry, two perfect sways and a perfect duck: 1 + 2 + 2 + 2")
	assert_eq(b.stats.posture, 32.0, "60, less the parry's 12, less 8 for each of the cross and the hook (Quick), none for the jab (Slip)")


func test_mashed_sways_evade_at_most_half_the_frames_at_every_tempo() -> void:   # Review Focus 2
	# [action, the chain it starts with, how many frames are two of its redodge waits]; the chain is never fed, so no tempo changes
	var rows := [[&"sway", 0, 40], [&"sway", 3, 32], [&"sway", 7, 24], [&"duck", 0, 48], [&"duck", 3, 36], [&"duck", 7, 28]]
	for row: Array in rows:
		var steps := []
		for i in int(row[2]):
			steps.append({"frames": 1, "press": [row[0]]})
		var run := Duel.without_slow(Duel.make(self, steps))
		var a: Actor = run["a"]
		for i in int(row[1]):
			a.chain.link(false, 0)
		var open := 0
		while a.frame < int(row[2]):
			await frames(1)
			if a.runner.evading != MoveData.Evade.NONE:
				open += 1
		assert_true(open * 2 <= int(row[2]), "%s at chain %d: the window was open %d of %d frames" % [row[0], row[1], open, row[2]])
		assert_true(open > 0, "%s at chain %d: and it did open" % [row[0], row[1]])
		assert_eq(a.chain.count, int(row[1]), "%s at chain %d: mashing builds no chain" % [row[0], row[1]])
	# a long stretch from nothing: sixty frames of window in a hundred and twenty
	for action: StringName in [&"sway", &"duck"]:
		var steps := []
		for i in 120:
			steps.append({"frames": 1, "press": [action]})
		var run := Duel.without_slow(Duel.make(self, steps))
		var a: Actor = run["a"]
		var open := 0
		while a.frame < 120:
			await frames(1)
			if a.runner.evading != MoveData.Evade.NONE:
				open += 1
		assert_true(open * 2 <= 120, "%s mashed for two seconds: %d of 120" % [action, open])
		assert_eq(a.chain.count, 0)


func test_mashing_through_the_seven_blow_string_loses_to_timing() -> void:
	# a sway pressed on every frame through the same string: windows are open half the frames, a blow that lands knocks him out
	# of any chain, so he evades fewer than half the blows and never gets as far as Quick
	var steps := []
	for i in 175:
		steps.append({"frames": 1, "press": [&"sway"]})
	var run := Duel.without_slow(Duel.make(self, steps, [], 1.0, load(KNUCKLE) as ActorDef))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var outcomes := []
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(HitResult.Outcome.keys()[r.outcome]))
	var index := 0
	var highest := 0
	while a.frame < 175:
		if index < STRING.size() and STRING[index][0] == a.frame + 1:
			Blows.post(b, a, {"line": ROUND} if STRING[index][1] == "R" else {})
			index += 1
		await frames(1)
		highest = maxi(highest, a.chain.tempo())
	var evaded := outcomes.count("EVADED")
	assert_true(evaded * 2 < STRING.size(), "%d of %d blows evaded: %s" % [evaded, STRING.size(), outcomes])
	assert_eq(highest, T.SLIP, "the chain never reached Quick")
