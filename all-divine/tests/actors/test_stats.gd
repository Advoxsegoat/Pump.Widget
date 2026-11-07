extends TestCase
## Stats on their own, with no scene: stamina waits after a spend and then comes back (slower under a guard),
## running out makes the actor exhausted until it has climbed back, posture breaks once and mends only
## after its delay, and HP reports the blow that empties it. Abarax's numbers (data/tuning/combat_abarax.tres):
## regen 45 a second after 0.6 s, guard scale 0.4, exhausted until 20, posture regen 20 a second after 1.5 s.
## One tick per 60 Hz frame.

const DT := 1.0 / 60


func _stats() -> Stats:
	var def := ActorDef.new()
	def.combat = CombatTuning.new()
	return Stats.from_def(def)


# Ticks `stats` for `seconds`, in 60 Hz frames.
func _tick(stats: Stats, seconds: float, guarding := false) -> void:
	for i in roundi(seconds / DT):
		stats.tick(DT, guarding)


func test_from_def_keeps_the_full_bars_and_the_maxima() -> void:
	var def := ActorDef.new()
	def.max_hp = 120.0
	def.max_stamina = 80.0
	def.max_posture = 60.0
	def.poise = 15.0
	var stats := Stats.from_def(def)
	assert_eq([stats.hp, stats.stamina, stats.posture, stats.poise], [120.0, 80.0, 60.0, 15.0])
	assert_eq([stats.max_hp, stats.max_stamina, stats.max_posture], [120.0, 80.0, 60.0])
	assert_false(stats.exhausted)
	assert_false(stats.posture_broken)
	assert_true(stats.can_act())


func test_a_def_without_combat_tuning_gets_the_defaults() -> void:
	var stats := Stats.from_def(ActorDef.new())
	assert_true(stats.tuning is CombatTuning, "never null")
	assert_eq(stats.tuning.stamina_regen_rate, CombatTuning.new().stamina_regen_rate)


func test_a_def_with_combat_tuning_shares_it() -> void:
	var def := ActorDef.new()
	def.combat = CombatTuning.new()
	assert_eq(Stats.from_def(def).tuning, def.combat)


func test_stamina_waits_point_six_seconds_then_regenerates() -> void:
	var stats := _stats()
	stats.spend_stamina(50.0)
	assert_eq(stats.stamina, 50.0)
	_tick(stats, 0.59)
	assert_eq(stats.stamina, 50.0, "still waiting at 0.59 s")
	_tick(stats, 1.6 - 0.59)
	assert_near(stats.stamina, 50.0 + 45.0 * (1.6 - 0.6), 1.0, "45 a second from 0.6 s on")


func test_regen_does_not_depend_on_the_step() -> void:
	var fine := _stats()
	var coarse := _stats()
	fine.spend_stamina(50.0)
	coarse.spend_stamina(50.0)
	for i in 96:
		fine.tick(DT, false)
	for i in 8:
		coarse.tick(0.2, false)
	assert_near(fine.stamina, coarse.stamina, 1e-3, "1.6 s is 1.6 s in 96 steps or in 8")


func test_stamina_stops_at_the_maximum() -> void:
	var stats := _stats()
	stats.spend_stamina(10.0)
	_tick(stats, 3.0)
	assert_eq(stats.stamina, stats.max_stamina)


func test_a_spend_restarts_the_wait() -> void:
	var stats := _stats()
	stats.spend_stamina(50.0)
	_tick(stats, 0.5)
	stats.spend_stamina(10.0)
	_tick(stats, 0.5)
	assert_eq(stats.stamina, 40.0, "0.5 s after the second spend is still waiting")
	_tick(stats, 0.6)
	assert_true(stats.stamina > 40.0, "and 1.1 s after it, back")


func test_a_spend_of_nothing_does_not_restart_the_wait() -> void:
	# A guard that pays nothing for a blow (a guard_stamina of 0) must not hold its stamina back.
	var stats := _stats()
	stats.spend_stamina(50.0)
	_tick(stats, 0.5)
	stats.spend_stamina(0.0)
	stats.spend_stamina(-3.0)
	_tick(stats, 0.2)
	assert_near(stats.stamina, 50.0 + 45.0 * 0.1, 1e-6, "the wait ran on from the first spend: 0.1 s of regen")
	var exhausted := _stats()
	exhausted.spend_stamina(100.0)
	exhausted.spend_stamina(0.0)
	assert_true(exhausted.exhausted, "and nothing changes on an empty bar")


func test_a_drain_restarts_the_wait_and_takes_stamina_by_the_second() -> void:
	var stats := _stats()
	for i in 60:
		stats.drain_stamina(12.0, DT)
		stats.tick(DT, false)
	assert_near(stats.stamina, 88.0, 1e-6, "12 a second for a second, with no regen between")
	_tick(stats, 0.5)
	assert_near(stats.stamina, 88.0, 1e-6, "and the wait starts when the drain stops")


func test_spend_floors_at_zero_and_exhausts() -> void:
	var stats := _stats()
	stats.spend_stamina(30.0)
	assert_false(stats.exhausted, "stamina is left")
	assert_true(stats.can_act())
	stats.spend_stamina(999.0)
	assert_eq(stats.stamina, 0.0)
	assert_true(stats.exhausted)
	assert_false(stats.can_act())


func test_draining_to_zero_exhausts() -> void:
	var stats := _stats()
	stats.drain_stamina(1000.0, 1.0)
	assert_eq(stats.stamina, 0.0)
	assert_true(stats.exhausted)


func test_exhausted_at_zero_until_twenty() -> void:
	var stats := _stats()
	stats.spend_stamina(200.0)
	_tick(stats, 0.6)
	assert_false(stats.can_act(), "the wait is not over")
	var frames_to_act := 0
	while not stats.can_act() and frames_to_act < 600:
		stats.tick(DT, false)
		frames_to_act += 1
	assert_true(stats.stamina >= 20.0, "can act again only from 20: %s" % stats.stamina)
	assert_true(stats.stamina < 20.0 + 45.0 * DT + 1e-6, "and as soon as it gets there: %s" % stats.stamina)
	assert_false(stats.exhausted)
	assert_true(absi(frames_to_act - 27) <= 1, "20 / 45 s after the wait: %d frames" % frames_to_act)


func test_exhausted_still_clears_when_the_bar_is_smaller_than_the_climb() -> void:
	var def := ActorDef.new()
	def.max_stamina = 10.0
	var stats := Stats.from_def(def)
	stats.spend_stamina(999.0)
	_tick(stats, 2.0)
	assert_eq(stats.stamina, 10.0)
	assert_true(stats.can_act(), "a full bar of 10 is as high as it gets")


func test_guarding_slows_regen() -> void:
	var stats := _stats()
	stats.spend_stamina(50.0)
	_tick(stats, 0.59, true)
	assert_eq(stats.stamina, 50.0, "the wait is the same under a guard")
	_tick(stats, 1.6 - 0.59, true)
	assert_near(stats.stamina, 50.0 + 45.0 * 0.4 * (1.6 - 0.6), 1.0, "45 x 0.4 a second from 0.6 s on")


func test_posture_breaks_once_and_recovers_after_its_delay() -> void:
	var stats := _stats()
	assert_true(stats.damage_posture(100.0), "the blow that empties it")
	assert_eq(stats.posture, 0.0)
	assert_true(stats.posture_broken)
	assert_false(stats.damage_posture(10.0), "a second blow does not break it again")
	assert_true(stats.posture_broken)
	_tick(stats, 5.0)
	assert_eq(stats.posture, 0.0, "a broken posture does not mend by itself")
	stats.restore_posture()
	assert_eq(stats.posture, stats.max_posture)
	assert_false(stats.posture_broken)


func test_posture_wears_down_waits_and_mends() -> void:
	var stats := _stats()
	assert_false(stats.damage_posture(60.0), "not empty yet")
	assert_eq(stats.posture, 40.0)
	assert_false(stats.posture_broken)
	_tick(stats, 1.49)
	assert_eq(stats.posture, 40.0, "waiting 1.5 s")
	_tick(stats, 1.0)
	assert_near(stats.posture, 40.0 + 20.0 * (2.49 - 1.5), 1.0, "20 a second from 1.5 s on")
	_tick(stats, 10.0)
	assert_eq(stats.posture, stats.max_posture, "and no further than full")


func test_more_posture_damage_restarts_the_wait() -> void:
	var stats := _stats()
	stats.damage_posture(50.0)
	_tick(stats, 1.0)
	stats.damage_posture(10.0)
	_tick(stats, 1.0)
	assert_eq(stats.posture, 40.0, "1 s after the second blow is still waiting")


func test_posture_damage_floors_at_zero() -> void:
	var stats := _stats()
	stats.damage_posture(250.0)
	assert_eq(stats.posture, 0.0)


func test_take_damage_reports_the_killing_blow_once() -> void:
	var stats := _stats()
	assert_false(stats.take_damage(40.0))
	assert_eq(stats.hp, 60.0)
	assert_true(stats.take_damage(80.0), "the blow that empties it")
	assert_eq(stats.hp, 0.0, "floored")
	assert_false(stats.take_damage(5.0), "the dead are not killed again")
	assert_eq(stats.hp, 0.0)


func test_poise_is_the_defs_threshold_and_never_moves() -> void:
	var def := ActorDef.new()
	def.poise = 15.0
	var stats := Stats.from_def(def)
	stats.damage_posture(100.0)
	stats.spend_stamina(999.0)
	stats.take_damage(999.0)
	_tick(stats, 5.0)
	stats.restore_posture()
	assert_eq(stats.poise, 15.0)
