extends TestCase
## F1's combat frame budget, headless: the physics step of the real game (Main: the training yard, the HUD, the arena, the enemy
## brains, Abarax played by the combat bot) in two fights of 1,200 frames each.
##
##   four Knuckles   two of tier I, one of II and one of III (the debug keys' foes: F6, F6, F7, F8), all in the yard at once
##   the worst wave  the yard's last wave, the heavy and a tier I (wave 12), with a Drummer added: a slam's ring, the Drummer's
##                   string and a chain's rim run together
##
## Each holds the brief's bounds: the mean step at most 4 ms and the 99th percentile at most 8 ms. They are measured in the thread's own
## processor time (FrameMeter), not by the wall clock, so that a test run on a machine that has other work does not fail with nothing
## the matter with the game: see tests/support/frame_meter.gd for why and tests/perf/test_frame_meter.gd for what it holds. The mean is
## the quietest two seconds' (FrameMeter.WINDOW steps); the 99th is over every step.
##
## To see the numbers: PERF_REPORT=1 tools/test.sh --filter=test_combat_perf prints each fight's steps on both clocks.

const FRAMES := 1200
const MEAN_BUDGET_MS := 4.0
const P99_BUDGET_MS := 8.0
const SEED := 1
## The debug keys that send a Knuckle of tier I, I, II and III.
const FOUR: Array[Key] = [KEY_F6, KEY_F6, KEY_F7, KEY_F8]
## The index of the yard's last wave (the heavy and a tier I).
const LAST_WAVE := 11
const DRUMMER := "res://data/actors/knuckle_drummer.tres"

var _main: Node


func after_each() -> void:
	InputFeed.release()
	if is_instance_valid(_main):
		_main.queue_free()
	Game.reset()
	await frames(1)


# The yard with the bot playing Abarax. `arena.automatic` is off so that the fight is what the test sent: no next wave, no reset.
func _yard() -> Arena:
	Game.reset()
	var game := BotWorld.make(self, SEED)
	_main = game
	var arena := game.arena()
	arena.automatic = false
	var bot := track(CombatBot.new()) as CombatBot
	bot.begin(game.player, arena, SEED, CombatBot.Policy.MIXED)
	return arena


func _foes_alive(arena: Arena) -> int:
	var count := 0
	for child in arena.get_children():
		var actor := child as Actor
		if actor != null and actor.def.team == ActorDef.Team.ENEMY and not actor.dead:
			count += 1
	return count


# Plays FRAMES frames timed. Returns the meter and the number of foes alive at the end.
func _play(arena: Arena) -> Array:
	await frames(2)  # the frames that made the scene are not the fight's to pay for
	var meter := FrameMeter.new()
	meter.attach(get_tree())
	await frames(FRAMES)
	await get_tree().process_frame
	meter.detach()
	return [meter, _foes_alive(arena)]


func _hold(label: String, meter: FrameMeter, alive: int, least_alive: int) -> void:
	var held := meter.held()
	if OS.get_environment("PERF_REPORT") != "":
		print("PERF %s: %d steps, %d foes alive at the end; %s" % [label, held["count"], alive, meter.both()])
	assert_true(held["count"] >= FRAMES, "%s: timed %d physics steps" % [label, held["count"]])
	assert_true(alive >= least_alive, "%s: the foes were still there at the end (%d alive): a fight with them gone costs less" % [label, alive])
	assert_true(held["mean"] <= MEAN_BUDGET_MS, "%s: a physics step takes %.2f ms in the quietest stretch (%s, budget %.1f ms); %s" % [label, held["mean"], held["basis"], MEAN_BUDGET_MS, meter.both()])
	assert_true(held["p99"] <= P99_BUDGET_MS, "%s: the 99th percentile of a physics step is %.2f ms (%s, budget %.1f ms); %s" % [label, held["p99"], held["basis"], P99_BUDGET_MS, meter.both()])


func test_four_knuckles_fight_abarax_within_the_budget() -> void:
	var arena := _yard()
	arena.clear_foes()
	for key in FOUR:
		arena.debug_key(key)
	assert_eq(_foes_alive(arena), 4, "four Knuckles are in the yard")
	var done := await _play(arena)
	_hold("four Knuckles", done[0], done[1], 3)


func test_the_yards_worst_wave_with_a_drummer_within_the_budget() -> void:
	var arena := _yard()
	arena.clear_foes()  # the first wave the game began with
	arena.start_wave(LAST_WAVE)
	# There is no debug key for the Drummer: it is sent as the arena sends a foe, at the next spawn.
	var drummer := Arena.ACTOR.instantiate() as Actor
	drummer.name = "Drummer"
	drummer.def = load(DRUMMER) as ActorDef
	drummer.spawn_count = 99
	arena.add_child(drummer)
	var spawns := arena.enemy_spawns()
	drummer.place(Transform3D(Basis(Vector3.UP, PI), spawns[2 % spawns.size()].global_position))
	assert_eq(_foes_alive(arena), 3, "the heavy, a tier I and a Drummer are in the yard")
	var done := await _play(arena)
	_hold("the worst wave and a Drummer", done[0], done[1], 2)
