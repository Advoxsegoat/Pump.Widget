extends TestCase
## Mashing costs stamina (Task 17, the owner's "4.B"), by the stamina stat: two rules for an actor whose tuning turns them on (Abarax's;
## every foe's stays off), each times 100 / max_stamina (1 today; a stamina of 150 pays two thirds).
##   Hammering: a press of palm, heavy, sway or duck made while the same action's last press still waits in the buffer, or while the move
##   it started has not yet reached its first cancel window, is redundant. The first one in a move is free (a double tap); each after it
##   costs CombatTuning.hammer_tax (2.0), spent like any spend. The press itself is taken as ever.
##   Strain: a sway or duck that evades nothing makes the next one cost half its base cost more (x1.5, x2, x2.5, at most x3; the added part
##   times the factor), until one evades something or 60 frames pass with no sway or duck.
## A player who presses once for each blow, and a chain of clean sways, pay what they paid before: the same script against the same
## actor with the rules switched off must cost the same.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_TUNING := "res://data/tuning/combat_knuckle.tres"
const JAB := 12.0
const SWAY := 6.0
const DUCK := 8.0


# A copy of Abarax's def of `team` whose tuning has the rules `on` or off, and whose stamina bar is `stamina` large.
func _def(on: bool, stamina := 100.0, team := ActorDef.Team.PLAYER) -> ActorDef:
	var def := Duel.def(team, 5.0)
	def.combat = def.combat.duplicate() as CombatTuning
	if not on:
		def.combat.hammer_tax = 0.0
		def.combat.strain_step = 0.0
	def.max_stamina = stamina
	return def


# ScriptBrain steps for `presses`, each [frame, [actions]].
static func _script(presses: Array) -> Array:
	var steps := []
	var at := 0
	for press: Array in presses:
		var gap: int = press[0] - at - 1
		if gap > 0:
			steps.append({"frames": gap})
		steps.append({"frames": 1, "press": press[1]})
		at = press[0]
	steps.append({"frames": 300})
	return steps


# {arena, a, b, log: stamina at the end of each frame of a (index: a's frame), started: [[frame, id]]}.
func _world(def: ActorDef, steps: Array) -> Dictionary:
	var arena := TestArena.make(self)
	var a := TestArena.spawn(arena, def, ScriptBrain.new(steps), Vector3.ZERO, "A")
	a.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var run := {"arena": arena, "a": a, "log": [def.max_stamina], "started": []}
	var log: Array = run["log"]
	var started: Array = run["started"]
	a.runner.move_started.connect(func(m: MoveData) -> void: started.append([a.frame, m.id]))
	return run


# Plays `a` to frame `last`, noting its stamina after each frame, and posting `blows` (frames) on a from a foe standing a metre off
# (so that a sway meets a blow on its evade window).
func _play(run: Dictionary, last: int, blows := [], foe: Actor = null) -> void:
	var a: Actor = run["a"]
	var log: Array = run["log"]
	while a.frame < last:
		for frame: int in blows:
			if frame == a.frame + 1:
				Blows.post(foe, a, {})
		await frames(1)
		log.append(a.stats.stamina)


func _spent(run: Dictionary, from_frame: int, to_frame: int) -> float:
	var log: Array = run["log"]
	return log[from_frame] - log[to_frame]


func _free(run: Dictionary) -> void:
	(run["arena"] as Node).queue_free()
	await frames(2)


# --- hammering ---

func test_one_palm_press_costs_the_moves_cost_and_no_more() -> void:
	var run := _world(_def(true), _script([[1, [&"palm"]]]))
	await _play(run, 20)
	assert_near((run["a"] as Actor).stats.stamina, 100.0 - JAB, 1e-4, "a jab")
	await _free(run)


func test_two_presses_in_one_move_cost_no_more() -> void:
	# the second is redundant (the jab has not reached its cancel window) and free: a double tap
	var run := _world(_def(true), _script([[1, [&"palm"]], [3, [&"palm"]]]))
	await _play(run, 20)
	assert_near((run["a"] as Actor).stats.stamina, 100.0 - JAB, 1e-4, "a jab and a free double tap")
	await _free(run)


func test_four_presses_cost_two_taxes() -> void:
	var run := _world(_def(true), _script([[1, [&"palm"]], [2, [&"palm"]], [3, [&"palm"]], [4, [&"palm"]]]))
	await _play(run, 20)
	assert_near((run["a"] as Actor).stats.stamina, 100.0 - JAB - 2.0 * 2.0, 1e-4, "the jab and two taxes of 2")
	await _free(run)


func test_the_tax_follows_the_stamina_stat() -> void:
	# a stamina of 150: the factor is 100 / 150, two thirds
	var run := _world(_def(true, 150.0), _script([[1, [&"palm"]], [2, [&"palm"]], [3, [&"palm"]], [4, [&"palm"]]]))
	await _play(run, 20)
	assert_near((run["a"] as Actor).stats.stamina, 150.0 - JAB - 2.0 * 2.0 * (100.0 / 150.0), 1e-3, "the jab and two thirds of two taxes")
	await _free(run)


func test_a_press_of_a_heavy_a_sway_and_a_duck_is_hammered_too() -> void:
	for action: StringName in [&"heavy", &"sway", &"duck"]:
		var run := _world(_def(true), _script([[1, [action]], [2, [action]], [3, [action]], [4, [action]]]))
		var a: Actor = run["a"]
		await _play(run, 3)
		var after_three := a.stats.stamina
		await _play(run, 4)
		assert_near(after_three - a.stats.stamina, 2.0, 1e-4, "%s: the fourth press (the second redundant one) costs a tax" % action)
		await _free(run)


func test_a_foe_who_presses_the_same_way_pays_nothing_extra() -> void:
	var def := _def(true, 100.0, ActorDef.Team.ENEMY)
	def.combat = load(KNUCKLE_TUNING) as CombatTuning
	var run := _world(def, _script([[1, [&"palm"]], [2, [&"palm"]], [3, [&"palm"]], [4, [&"palm"]]]))
	await _play(run, 20)
	assert_near((run["a"] as Actor).stats.stamina, 100.0 - JAB, 1e-4, "only the jab")
	var tuning := load(KNUCKLE_TUNING) as CombatTuning
	assert_eq([tuning.hammer_tax, tuning.strain_step], [0.0, 0.0], "the Knuckles' tuning has both rules off")
	await _free(run)


func test_a_press_for_each_blow_of_a_combo_costs_what_it_did() -> void:
	# a jab, a cross and a hook, each pressed once, the second and third two frames before the window opens (buffered): the same
	# stamina as with the rules off
	var presses := [[1, [&"palm"]], [13, [&"palm"]], [38, [&"palm"]]]
	var on := _world(_def(true), _script(presses))
	var off := _world(_def(false), _script(presses))
	await _play(on, 80)
	await _play(off, 80)
	assert_eq((on["started"] as Array).map(func(s: Array) -> StringName: return s[1]), [&"palm_jab", &"palm_cross", &"palm_hook"], "a combo: %s" % [on["started"]])
	assert_near((on["a"] as Actor).stats.stamina, (off["a"] as Actor).stats.stamina, 1e-4, "it costs what it cost")
	await _free(on)
	await _free(off)


# --- strain ---

# a's evade window opens 3 frames after the sway, and a blow from `foe` is posted to meet it
func _sway_chain(on: bool, presses: Array, blows := []) -> Dictionary:
	var run := _world(_def(on), _script(presses))
	var foe := TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(0, 0, 1.0), "B")
	foe.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.0)))
	run["foe"] = foe
	await _play(run, 130, blows, foe)
	return run


func test_a_sway_that_evades_nothing_makes_the_next_cost_one_and_a_half_times_then_two() -> void:
	var run := _world(_def(true), _script([[1, [&"sway"]], [40, [&"sway"]], [80, [&"sway"]], [120, [&"sway"]], [160, [&"sway"]], [200, [&"sway"]]]))
	await _play(run, 230)
	var started: Array = run["started"]
	assert_eq(started.size(), 6, "six sways: %s" % [started])
	var costs := []
	for s: Array in started:
		costs.append(snappedf(_spent(run, s[0] - 1, s[0]), 0.001))
	assert_eq(costs, [SWAY, SWAY * 1.5, SWAY * 2.0, SWAY * 2.5, SWAY * 3.0, SWAY * 3.0], "x1, x1.5, x2, x2.5, x3 and no more: %s" % [costs])
	await _free(run)


func test_the_strain_follows_the_stamina_stat_in_its_added_part() -> void:
	var run := _world(_def(true, 150.0), _script([[1, [&"sway"]], [40, [&"sway"]]]))
	await _play(run, 60)
	var started: Array = run["started"]
	assert_eq(started.size(), 2, "two sways")
	var second := _spent(run, started[1][0] - 1, started[1][0])
	assert_near(second, SWAY + SWAY * 0.5 * (100.0 / 150.0), 1e-3, "the added half, two thirds of it")
	await _free(run)


func test_a_duck_that_evades_nothing_strains_the_next_sway_or_duck() -> void:
	var run := _world(_def(true), _script([[1, [&"duck"]], [40, [&"sway"]]]))
	await _play(run, 70)
	var started: Array = run["started"]
	assert_eq(started.size(), 2, "a duck and a sway")
	assert_near(_spent(run, started[1][0] - 1, started[1][0]), SWAY * 1.5, 1e-3, "the sway after a duck that avoided nothing costs half again")
	await _free(run)


func test_an_evade_resets_the_strain() -> void:
	# sway 1 evades nothing, sway 2 (x1.5) evades a blow (straight: a perfect dodge, which also refunds), sway 3 costs the base again
	var run := _world(_def(true), _script([[1, [&"sway"]], [40, [&"sway"]], [90, [&"sway"]]]))
	var foe := TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(0, 0, 1.0), "B")
	foe.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.0)))
	await _play(run, 140, [44], foe)
	var started: Array = run["started"]
	assert_eq(started.size(), 3, "three sways: %s" % [started])
	assert_near(_spent(run, started[1][0] - 1, started[1][0]), SWAY * 1.5, 1e-3, "the second is strained")
	assert_near(_spent(run, started[2][0] - 1, started[2][0]), SWAY, 1e-3, "the third, after an evade, is not")
	await _free(run)


func test_sixty_frames_with_no_sway_or_duck_reset_the_strain() -> void:
	var run := _world(_def(true), _script([[1, [&"sway"]], [140, [&"sway"]]]))
	await _play(run, 170)
	var started: Array = run["started"]
	assert_eq(started.size(), 2, "two sways")
	assert_near(_spent(run, started[1][0] - 1, started[1][0]), SWAY, 1e-3, "a long rest, and the base cost")
	await _free(run)


func test_the_strain_is_off_for_a_foe() -> void:
	var def := _def(true, 100.0, ActorDef.Team.ENEMY)
	def.combat = (load(KNUCKLE_TUNING) as CombatTuning).duplicate() as CombatTuning
	var run := _world(def, _script([[1, [&"sway"]], [40, [&"sway"]]]))
	await _play(run, 60)
	var started: Array = run["started"]
	assert_eq(started.size(), 2, "two sways")
	assert_near(_spent(run, started[1][0] - 1, started[1][0]), SWAY, 1e-3, "no strain")
	await _free(run)


func test_a_chain_of_clean_sways_costs_what_it_did() -> void:
	# three sways, each against a straight blow: the same stamina, frame for frame, with the rules off
	var presses := [[1, [&"sway"]], [30, [&"sway"]], [60, [&"sway"]]]
	var blows := [5, 34, 64]
	var on := await _sway_chain(true, presses, blows)
	var off := await _sway_chain(false, presses, blows)
	var log_on: Array = on["log"]
	var log_off: Array = off["log"]
	assert_eq((on["started"] as Array).size(), 3, "three sways: %s" % [on["started"]])
	for i in mini(log_on.size(), log_off.size()):
		assert_near(log_on[i], log_off[i], 1e-4, "frame %d" % i)
	await _free(on)
	await _free(off)
