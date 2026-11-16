extends TestCase
## Timing pays more (Task 17, the owner's "4.A"): a foe whose blow Abarax just turned (parried or caught) or perfectly dodged (a sway
## against a straight blow, a duck against a round one) is OPEN for CombatTuning.punish_frames (40) of Abarax's own clock (a frozen frame
## does not count), until he starts a move of his own; a blow of Abarax's that lands on him meanwhile is worth CombatTuning.punish_scale
## (1.5) times, in its HP and posture damage and in its hit-stop. Only the one who turned or dodged the blow punishes (nobody else's
## blows are scaled), and the foes' own tuning has a scale of 1: they get no such bonus against him.
##
## `a` is Abarax (PLAYER) at the origin facing +Z, `b` an ENEMY copy of him a metre in front (Duel). b's blows are posted by hand
## (Blows) so that they land on an exact frame; a's palms are pressed, and what each came to is read off the result a hears of it
## (hit_landed): its HP damage over the profile's, its posture damage, the scale its event carries.

const O := HitResult.Outcome
const ROUND := HitProfile.Line.ROUND
const WINDOW := 40
const ABARAX := "res://data/actors/abarax.tres"


# A ScriptBrain's steps for `presses`, each [frame, [actions]] with the evade direction `dir` (any hold is given as a third entry).
static func _script(presses: Array) -> Array:
	var steps := []
	var at := 0
	for press: Array in presses:
		var gap: int = press[0] - at - 1
		if gap > 0:
			steps.append({"frames": gap})
		var step := {"frames": 1, "press": press[1]}
		if press.size() > 2:
			step["hold"] = press[2]
		steps.append(step)
		at = press[0]
	steps.append({"frames": 200})
	return steps


# {arena, a, b, opened: [a.buffer_frame when a first heard of a blow turned or dodged], landed: [{scale, hp, posture, buffer_frame, outcome}]}
# for a's blows. `a_steps` is what a presses; `b_def` is b's def.
func _world(a_steps: Array, b_def: ActorDef = null) -> Dictionary:
	var run := Duel.without_slow(Duel.make(self, a_steps, [], 1.0, b_def))
	var a: Actor = run["a"]
	run["opened"] = []
	run["landed"] = []
	var opened: Array = run["opened"]
	var landed: Array = run["landed"]
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
		if r.outcome == O.PARRIED or r.outcome == O.CAUGHT or (r.outcome == O.EVADED and r.perfect):
			opened.append(a.buffer_frame))
	a.hit_landed.connect(func(r: HitResult, e: HitEvent) -> void:
		if r.outcome == O.HIT:
			landed.append({"scale": r.hp_damage / e.profile.damage, "posture": r.posture_damage / e.profile.posture_damage,
					"punish": e.punish, "frame": a.buffer_frame, "move": e.move.id}))
	return run


# Plays until `a` has lived `last` frames, posting b's `blows` ([a.frame to post on, profile fields]) on a on the way.
func _play(run: Dictionary, blows: Array, last: int) -> void:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	while a.frame < last:
		for blow: Array in blows:
			if blow[0] == a.frame + 1:
				Blows.post(b, a, blow[1])
		await frames(1)


func _free(run: Dictionary) -> void:
	(run["arena"] as Node).queue_free()
	await frames(2)


# A parry at frame 6 against a blow judged on frame 11 (a tap of guard, the blow posted on 10): a hears of it at once.
const PARRY := [[6, [&"guard"], [&"guard"]]]
const PARRY_BLOW := [[10, {}]]
# A sway at frame 6 against a straight blow judged on frame 10 (its evade window is f3 to f12 of the move: frames 9 to 18).
const SWAY_STEP := [[6, [&"sway"]]]
const SWAY_BLOW := [[10, {}]]
const DUCK_STEP := [[6, [&"duck"]]]


# The scales a palm pressed `after` frames on from the parry or dodge (and its blow) lands with, for each of `presses`
# (a's buffer-frame offsets from when it heard of the blow), one world each: [{offset, landed: [...]}].
func _landings(steps_of: Callable, blows: Array, presses: Array) -> Array:
	var out := []
	for press: int in presses:
		var run := _world(steps_of.call(press))
		await _play(run, blows, 110)
		out.append({"press": press, "opened": (run["opened"] as Array).duplicate(), "landed": (run["landed"] as Array).duplicate()})
		await _free(run)
	return out


# The offsets (from the buffer frame a heard the blow turned, the one the window counts from) at which a's palms landed, with their scale.
static func _offsets(results: Array) -> Array:
	var rows := []
	for r: Dictionary in results:
		if r["opened"].is_empty():
			continue
		for l: Dictionary in r["landed"]:
			rows.append([l["frame"] - r["opened"][0], l["scale"], l["posture"], l["move"]])
	return rows


func test_a_palm_landed_within_forty_frames_of_a_parry_is_worth_one_and_a_half_times_and_one_a_frame_later_is_not() -> void:
	# presses after the parry's own move is over, so that the palm starts at once; it lands about 10 frames after it starts, and the
	# presses are spread so that some land on the window's last frame and some a frame after it
	var results := await _landings(func(p: int) -> Array: return _script(PARRY + [[p, [&"palm"]]]), PARRY_BLOW, range(36, 48))
	var rows := _offsets(results)
	assert_true(rows.size() >= 8, "the palms landed: %s" % [rows])
	var at_forty := rows.filter(func(r: Array) -> bool: return r[0] == WINDOW)
	var at_forty_one := rows.filter(func(r: Array) -> bool: return r[0] == WINDOW + 1)
	assert_false(at_forty.is_empty(), "one landed on the last frame of the window: %s" % [rows])
	assert_false(at_forty_one.is_empty(), "one landed a frame after it: %s" % [rows])
	for r: Array in rows:
		var want := 1.5 if r[0] <= WINDOW else 1.0
		assert_near(r[1], want, 1e-4, "a palm landing %d frames after the parry deals %.1f times its HP (%s)" % [r[0], want, r])
		assert_near(r[2], want, 1e-4, "and %.1f times its posture damage" % want)


func test_a_palm_landed_after_a_perfect_sway_is_worth_one_and_a_half_times_until_the_window_ends() -> void:
	var results := await _landings(func(p: int) -> Array: return _script(SWAY_STEP + [[p, [&"palm"]]]), SWAY_BLOW, range(30, 48))
	var rows := _offsets(results)
	assert_true(rows.size() >= 8, "the palms landed: %s" % [rows])
	assert_false(rows.filter(func(r: Array) -> bool: return r[0] == WINDOW).is_empty(), "one landed on the window's last frame: %s" % [rows])
	assert_false(rows.filter(func(r: Array) -> bool: return r[0] == WINDOW + 1).is_empty(), "one a frame after it: %s" % [rows])
	for r: Array in rows:
		var want := 1.5 if r[0] <= WINDOW else 1.0
		assert_near(r[1], want, 1e-4, "a blow %d frames after the sway deals %.1f times its HP (%s)" % [r[0], want, r])


func test_a_counter_cashed_in_stacks_with_it_by_multiplication() -> void:
	# a palm pressed in the sway's cancel window is the sway's counter (counter_hook, 12 HP, cashed at the Slip tempo x1): x1.5
	var run := _world(_script(SWAY_STEP + [[24, [&"palm"]]]))
	await _play(run, SWAY_BLOW, 80)
	var landed: Array = run["landed"]
	assert_eq(landed.size(), 1, "the counter landed: %s" % [landed])
	if landed.size() == 1:
		assert_eq(landed[0]["move"], &"counter_hook", "it is the counter")
		assert_near(landed[0]["scale"], 1.5, 1e-4, "worth the punish alone at the Slip tempo")
	var chain: ChainTuning = (load(ABARAX) as ActorDef).chain
	assert_eq(chain.cash_scale[2] * 1.5, 3.0, "a Flurry counter is cash 2 x punish 1.5")
	await _free(run)


func test_an_ordinary_evade_opens_nothing() -> void:
	# a duck against a straight blow evades it, but is not the perfect dodge (a sway is): no one is open
	var run := _world(_script(DUCK_STEP + [[30, [&"palm"]]]))
	await _play(run, [[10, {}]], 90)
	var landed: Array = run["landed"]
	assert_true((run["opened"] as Array).is_empty(), "no perfect dodge")
	assert_eq(landed.size(), 1, "the palm landed")
	if landed.size() == 1:
		assert_near(landed[0]["scale"], 1.0, 1e-4, "at its own worth")
	await _free(run)
	# and a sway against a round blow
	run = _world(_script(SWAY_STEP + [[30, [&"palm"]]]))
	await _play(run, [[10, {"line": ROUND}]], 90)
	assert_true((run["opened"] as Array).is_empty(), "a sway against a round blow is not perfect either")
	landed = run["landed"]
	if landed.size() == 1:
		assert_near(landed[0]["scale"], 1.0, 1e-4, "at its own worth")
	await _free(run)


func test_a_duck_against_a_round_blow_is_perfect_and_opens_him() -> void:
	var run := _world(_script(DUCK_STEP + [[30, [&"palm"]]]))
	await _play(run, [[10, {"line": ROUND}]], 90)
	assert_eq((run["opened"] as Array).size(), 1, "a perfect dodge")
	var landed: Array = run["landed"]
	assert_eq(landed.size(), 1, "the palm landed")
	if landed.size() == 1:
		assert_near(landed[0]["scale"], 1.5, 1e-4, "worth one and a half times")
	await _free(run)


func test_a_foe_who_starts_a_move_of_his_own_is_no_longer_open() -> void:
	# the parry on frame 11; b starts a step of his own on a's frame 16; a's palm, pressed on 26, lands within 40 frames of the parry
	var run := _world(_script(PARRY + [[26, [&"palm"]]]))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var own := Registry.fetch(&"moves", &"dash_step") as MoveData  # a move of his own that hits no one
	var blows := PARRY_BLOW
	while a.frame < 130:
		for blow: Array in blows:
			if blow[0] == a.frame + 1:
				Blows.post(b, a, blow[1])
		if a.frame == 15:
			b.runner.start(own, true)
		await frames(1)
	var landed: Array = run["landed"]
	var hit := landed.filter(func(l: Dictionary) -> bool: return l["move"] == &"palm_jab")
	assert_eq(hit.size(), 1, "the palm landed: %s" % [landed])
	if hit.size() == 1:
		assert_true(hit[0]["frame"] - (run["opened"] as Array)[0] <= WINDOW, "inside the window of the clock")
		assert_near(hit[0]["scale"], 1.0, 1e-4, "but he had started a move of his own")
	await _free(run)


func test_a_flinch_or_a_reaction_of_his_does_not_close_it() -> void:
	# b's own reactions are not moves of his own: the parried reaction plays and he is still open to the palm that follows
	var run := _world(_script(PARRY + [[28, [&"palm"]]]))
	await _play(run, PARRY_BLOW, 110)
	var landed: Array = run["landed"]
	assert_eq(landed.size(), 1, "the palm landed")
	if landed.size() == 1:
		assert_near(landed[0]["scale"], 1.5, 1e-4, "he plays his parried reaction and is open still")
	await _free(run)


func test_the_blows_of_a_second_fighter_are_not_scaled() -> void:
	# c, another PLAYER, stands behind b and jabs him inside a's window: its blow is worth its own, a's is worth the more
	var run := _world(_script(PARRY + [[34, [&"palm"]]]))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var c := TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new([{"frames": 14}, {"frames": 1, "press": [&"palm"]}, {"frames": 100}]), Vector3(0, 0, 2.0), "C")
	c.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 2.0)))
	var from_c := []
	c.hit_landed.connect(func(r: HitResult, e: HitEvent) -> void:
		if r.outcome == O.HIT:
			from_c.append(r.hp_damage / e.profile.damage))
	while a.frame < 110:
		if a.frame + 1 == 10:
			Blows.post(b, a, {})
		await frames(1)
	assert_eq(from_c.size(), 1, "c's blow landed on him: %s" % [from_c])
	if from_c.size() == 1:
		assert_near(from_c[0], 1.0, 1e-4, "at its own worth, though b was open to a")
	var landed: Array = run["landed"]
	assert_eq(landed.size(), 1, "and a's")
	if landed.size() == 1:
		assert_near(landed[0]["scale"], 1.5, 1e-4, "a's at one and a half")
	await _free(run)


func test_a_foes_blows_on_abarax_are_never_scaled() -> void:
	# The foes' tuning has a scale of 1 (the owner: no such bonus against him). A foe who is, by the rule's books, the one a blow of
	# Abarax's was turned by, deals what its profile says.
	var knuckle_tuning := load("res://data/tuning/combat_knuckle.tres") as CombatTuning
	assert_eq(knuckle_tuning.punish_scale, 1.0, "the Knuckles' tuning")
	for id: String in ["knuckle_1", "knuckle_2", "knuckle_3", "knuckle_drummer", "knuckle_blade", "knuckle_heavy"]:
		var def := load("res://data/actors/%s.tres" % id) as ActorDef
		assert_eq(def.combat.punish_scale, 1.0, "%s's tuning" % id)
	assert_eq((load(ABARAX) as ActorDef).combat.punish_scale, 1.5, "Abarax's")
	assert_eq((load(ABARAX) as ActorDef).combat.punish_frames, 40, "and its window")
	# and in a fight: a is open to b (b turned a's blow), b a Knuckle: b's palm on a lands at its own worth
	var knuckle := load("res://data/actors/knuckle_1.tres") as ActorDef
	var run := _world([], knuckle)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	a.open_to = b
	a.open_until = b.buffer_frame + 100
	assert_eq(b.punish_scale_on(a), 1.0, "a Knuckle's blow on the one open to it")
	var abarax_b := Duel.def(ActorDef.Team.ENEMY, 5.0)
	var other := _world([], abarax_b)
	var a2: Actor = other["a"]
	var b2: Actor = other["b"]
	a2.open_to = b2
	a2.open_until = b2.buffer_frame + 100
	assert_eq(b2.punish_scale_on(a2), 1.5, "the same with a body of Abarax's tuning")
	await _free(run)
	await _free(other)
