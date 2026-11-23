extends TestCase
## Mashing costs stamina (Task 17, the owner's "4.B"), by the stamina stat: two rules for an actor whose tuning turns them on (Abarax's;
## every foe's stays off), each times 100 / max_stamina (1 today; a stamina of 150 pays two thirds).
##   Hammering: a press of palm, heavy, sway or duck made while the same action's last press still waits in the buffer, or while the move
##   it started has not yet reached its first cancel window, is redundant. The first one in a move is free (a double tap); each after it
##   costs CombatTuning.hammer_tax (1.0), spent like any spend. The press itself is taken as ever.
##   Strain: a sway or duck that evades nothing makes the next one cost a quarter of its base cost more (x1.25, x1.5, x1.75, at most x2; the added part
##   times the factor), until one evades something or 60 frames pass with no sway or duck.
## A player who presses once for each blow, and a chain of clean sways, pay what they paid before: the same script against the same
## actor with the rules switched off must cost the same.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_TUNING := "res://data/tuning/combat_knuckle.tres"
const JAB := 12.0
const SWAY := 6.0
const DUCK := 8.0
## The tuning's numbers (data/tuning/combat_abarax.tres; fix round 1 gentled them from 2.0, 0.5 and 3.0: see notes/f1-feel.md).
const TAX := 1.0
const STEP := 0.25
const CAP := 2.0


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
	assert_near((run["a"] as Actor).stats.stamina, 100.0 - JAB - 2.0 * TAX, 1e-4, "the jab and two taxes")
	await _free(run)


func test_the_tax_follows_the_stamina_stat() -> void:
	# a stamina of 150: the factor is 100 / 150, two thirds
	var run := _world(_def(true, 150.0), _script([[1, [&"palm"]], [2, [&"palm"]], [3, [&"palm"]], [4, [&"palm"]]]))
	await _play(run, 20)
	assert_near((run["a"] as Actor).stats.stamina, 150.0 - JAB - 2.0 * TAX * (100.0 / 150.0), 1e-3, "the jab and two thirds of two taxes")
	await _free(run)


func test_a_press_of_a_heavy_a_sway_and_a_duck_is_hammered_too() -> void:
	for action: StringName in [&"heavy", &"sway", &"duck"]:
		var run := _world(_def(true), _script([[1, [action]], [2, [action]], [3, [action]], [4, [action]]]))
		var a: Actor = run["a"]
		await _play(run, 3)
		var after_three := a.stats.stamina
		await _play(run, 4)
		assert_near(after_three - a.stats.stamina, TAX, 1e-4, "%s: the fourth press (the second redundant one) costs a tax" % action)
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


# The tax is stamina and nothing else (fix round 1, I2): it must not restart the wait before stamina comes back; a move still does.
func test_a_tax_does_not_restart_the_wait_before_stamina_comes_back() -> void:
	var presses := [[1, [&"palm"]], [2, [&"palm"]], [3, [&"palm"]], [4, [&"palm"]]]
	var on := _world(_def(true), _script(presses))
	var off := _world(_def(false), _script(presses))
	await _play(on, 12)
	await _play(off, 12)
	var a_on: Actor = on["a"]
	var a_off: Actor = off["a"]
	assert_near(a_off.stats.stamina - a_on.stats.stamina, 2.0 * TAX, 1e-4, "two taxes were paid")
	assert_near(a_on.stats.save().stamina_idle, a_off.stats.save().stamina_idle, 1e-6, "the wait since the jab ran on through both taxes")
	await _free(on)
	await _free(off)


func test_a_strained_sways_extra_cost_does_not_restart_the_wait_either() -> void:
	# the second sway costs a step more: the move's own spend restarts the wait as it always did, and the extra is stamina only
	var on := _world(_def(true), _script([[1, [&"sway"]], [40, [&"sway"]]]))
	await _play(on, 60)
	var started: Array = on["started"]
	assert_eq(started.size(), 2, "two sways")
	var a: Actor = on["a"]
	assert_near(a.stats.save().stamina_idle, float(60 - started[1][0]) / 60.0, 0.02, "the wait counts from the second sway's start")
	await _free(on)


# --- by hand speed (fix round 1, I3): "weaker, not worthless" ---

const TIER_ONE := "res://data/actors/knuckle_1.tres"
const TIER_ONE_BRAIN := "res://data/brains/knuckle_1.tres"


# Frames of 600 (ten seconds) in which Abarax cannot start a move (out of stamina, or exhausted), tapping palm every `period` frames beside
# a tier I (the foe at `gap` metres, driven by its own brain, seed 7). The base (the rules off) is the same script on the same fight.
func _unable_frames(period: int, on: bool, gap := 2.0) -> int:
	var presses := []
	var frame := 1
	while frame < 600:
		presses.append([frame, [&"palm"]])
		frame += period
	var run := _world(_def(on), _script(presses))
	var tier := load(TIER_ONE) as ActorDef
	var foe := TestArena.spawn(run["arena"], tier, EnemyBrain.new(load(TIER_ONE_BRAIN) as BrainDef, 7), Vector3(0, 0, gap), "Tier")
	foe.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, gap)))
	var a: Actor = run["a"]
	var unable := 0
	while a.frame < 600:
		await frames(1)
		if not a.stats.can_act():
			unable += 1
	await _free(run)
	return unable


func test_a_steady_tapper_at_two_a_second_is_barely_held_back() -> void:
	var base := await _unable_frames(30, false)
	var taxed := await _unable_frames(30, true)
	print("HANDSPEED tapper 2/s unable base=%d taxed=%d" % [base, taxed])
	assert_true(taxed <= 140, "a person tapping twice a second cannot act for at most 140 of 600 frames (base %d): %d" % [base, taxed])


func test_a_masher_at_six_a_second_can_still_act_half_the_time() -> void:
	var base := await _unable_frames(10, false)
	var taxed := await _unable_frames(10, true)
	print("HANDSPEED masher 6/s unable base=%d taxed=%d" % [base, taxed])
	assert_true(taxed <= 300, "a masher at six a second can act for at least half of 600 frames (base %d): unable %d" % [base, taxed])


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
	assert_eq(costs, [SWAY, SWAY * 1.25, SWAY * 1.5, SWAY * 1.75, SWAY * CAP, SWAY * CAP], "x1, x1.25, x1.5, x1.75, x2 and no more: %s" % [costs])
	await _free(run)


func test_the_strain_follows_the_stamina_stat_in_its_added_part() -> void:
	var run := _world(_def(true, 150.0), _script([[1, [&"sway"]], [40, [&"sway"]]]))
	await _play(run, 60)
	var started: Array = run["started"]
	assert_eq(started.size(), 2, "two sways")
	var second := _spent(run, started[1][0] - 1, started[1][0])
	assert_near(second, SWAY + SWAY * STEP * (100.0 / 150.0), 1e-3, "the added step, two thirds of it")
	await _free(run)


func test_a_duck_that_evades_nothing_strains_the_next_sway_or_duck() -> void:
	var run := _world(_def(true), _script([[1, [&"duck"]], [40, [&"sway"]]]))
	await _play(run, 70)
	var started: Array = run["started"]
	assert_eq(started.size(), 2, "a duck and a sway")
	assert_near(_spent(run, started[1][0] - 1, started[1][0]), SWAY * (1.0 + STEP), 1e-3, "the sway after a duck that avoided nothing costs a step more")
	await _free(run)


func test_an_evade_resets_the_strain() -> void:
	# sway 1 evades nothing, sway 2 (strained) evades a blow (straight: a perfect dodge, which also refunds), sway 3 costs the base again
	var run := _world(_def(true), _script([[1, [&"sway"]], [40, [&"sway"]], [90, [&"sway"]]]))
	var foe := TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(0, 0, 1.0), "B")
	foe.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.0)))
	await _play(run, 140, [44], foe)
	var started: Array = run["started"]
	assert_eq(started.size(), 3, "three sways: %s" % [started])
	assert_near(_spent(run, started[1][0] - 1, started[1][0]), SWAY * (1.0 + STEP), 1e-3, "the second is strained")
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
