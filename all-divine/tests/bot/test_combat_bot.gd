extends TestCase
## The combat bot (tools/bot/combat_bot.gd): what it does against each tell, in a fight of two (Abarax with the bot's hands on a
## PlayerBrain, and a tier I Knuckle that throws what the test says), how a policy plays, that a seed plays the same fight each
## time, and that over whole seeds of the real game it finds no problem. A soft-lock it is shown is reported and its replay saved.

const KNUCKLE := "res://data/actors/knuckle_1.tres"
const REPLAYS := "res://out/replays"
const OUTCOME := HitResult.Outcome


func after_each() -> void:
	InputFeed.release()
	for seed_number in [9001, 9002]:
		for suffix in ["", "_counter"]:
			DirAccess.remove_absolute("%s/seed_%d%s.tres" % [REPLAYS, seed_number, suffix])
	Game.reset()
	await frames(1)


# Abarax (a PlayerBrain, the bot on it) and a Knuckle `gap` metres off that throws nothing by itself.
func _duel(policy: CombatBot.Policy, gap := 1.0, seed_number := 1) -> Dictionary:
	var run := Duel.make(self, [], [], gap, load(KNUCKLE) as ActorDef)
	var a: Actor = run["a"]
	a.set_brain(PlayerBrain.new())
	var bot := track(CombatBot.new()) as CombatBot
	bot.begin(a, null, seed_number, policy)
	run["bot"] = bot
	run["got"] = []
	run["started"] = []
	a.got_hit.connect(func(r: HitResult, e: HitEvent) -> void: run["got"].append([a.frame, OUTCOME.keys()[r.outcome], e.move.id if e.move != null else &"", r.perfect]))
	a.runner.move_started.connect(func(move: MoveData) -> void: run["started"].append([a.frame, move.id]))
	return run


# Lets the bot settle (it locks on), has the Knuckle throw `move_id`, and plays on for `after` frames.
func _throw(run: Dictionary, move_id: StringName, after := 120) -> void:
	await frames(30)
	var b: Actor = run["b"]
	b.runner.start(Registry.fetch(&"moves", move_id) as MoveData)
	await frames(after)


func _ids(run: Dictionary) -> Array:
	return run["started"].map(func(s: Array) -> StringName: return s[1])


func test_a_straight_blow_is_swayed_and_a_perfect_dodge() -> void:
	var run := _duel(CombatBot.Policy.COUNTER)
	await _throw(run, &"knuckle_jab")
	assert_eq(run["got"].map(func(g: Array) -> String: return g[1]), ["EVADED"], "evaded: %s started %s" % [run["got"], run["started"]])
	assert_true(run["got"][0][3], "perfect: the jab is straight and he swayed")
	assert_true(String(_ids(run)[0]).begins_with("sway_"), "%s" % [_ids(run)])
	assert_eq((run["a"] as Actor).stats.hp, 100.0)


func test_a_round_blow_is_ducked() -> void:
	var run := _duel(CombatBot.Policy.COUNTER, 1.2)  # the hook reaches a little further than the jab
	await _throw(run, &"knuckle_hook")
	assert_eq(run["got"].map(func(g: Array) -> String: return g[1]), ["EVADED"], "evaded: %s started %s" % [run["got"], run["started"]])
	assert_true(run["got"][0][3], "perfect: the hook is round and he ducked")
	assert_true(String(_ids(run)[0]).begins_with("duck_"), "%s" % [_ids(run)])


func test_a_sweep_is_hopped() -> void:
	var run := _duel(CombatBot.Policy.COUNTER, 1.0, 2)
	await _throw(run, &"knuckle_sweep", 140)
	assert_false(run["got"].any(func(g: Array) -> bool: return g[1] == "HIT"), "not hit: %s" % [run["got"]])
	assert_eq((run["a"] as Actor).stats.hp, 100.0)
	assert_true(_ids(run).has(&"hop") or _ids(run).any(func(i: StringName) -> bool: return String(i).begins_with("dash_step")), "he hopped or stepped out: %s" % [_ids(run)])


func test_a_thrust_is_caught() -> void:
	var run := _duel(CombatBot.Policy.COUNTER)
	await _throw(run, &"knuckle_thrust")
	assert_eq(run["got"].map(func(g: Array) -> String: return g[1]), ["CAUGHT"], "caught: %s" % [run["got"]])
	assert_eq((run["a"] as Actor).stats.hp, 100.0)


func test_a_grab_is_slipped_with_a_sway_or_duck() -> void:
	var run := _duel(CombatBot.Policy.COUNTER)
	await _throw(run, &"knuckle_grab")
	assert_eq(run["got"].map(func(g: Array) -> String: return g[1]), ["EVADED"], "evaded: %s" % [run["got"]])
	assert_true(run["got"][0][3], "a perfect dodge, whichever it was")
	assert_eq((run["a"] as Actor).paired_with, null, "and not grabbed")


# Frees a fight of _duel (and its bot) so that the next one stands where it stood.
func _end(run: Dictionary) -> void:
	InputFeed.release()
	for key in ["bot", "arena"]:
		if is_instance_valid(run[key]):
			(run[key] as Node).free()
	await frames(1)


func test_every_lead_the_bot_may_choose_is_inside_the_window_at_every_tempo() -> void:
	# Seeds roll different leads (and sides); a sway or a duck at the chain's first and last tempos, whose windows are 10 and 6 and 12 and 7
	# frames, must evade all of them, with the slow-down on as it ships.
	var misses := []
	# [chain, seed, blow, gap]: the seeds roll different leads and sides
	for row: Array in [[0, 1, &"knuckle_jab", 1.0], [0, 2, &"knuckle_hook", 1.2], [7, 1, &"knuckle_hook", 1.2], [7, 2, &"knuckle_jab", 1.0], [7, 3, &"knuckle_jab", 1.0]]:
		var run := _duel(CombatBot.Policy.COUNTER, row[3], row[1])
		for i in int(row[0]):
			(run["a"] as Actor).chain.link(false, 0)
		await _throw(run, row[2], 60)
		var outcomes: Array = run["got"].map(func(g: Array) -> String: return g[1])
		if outcomes != ["EVADED"]:
			misses.append("chain %d seed %d %s: %s" % [row[0], row[1], row[2], run["got"]])
		await _end(run)
	assert_true(misses.is_empty(), "every blow evaded: %s" % [misses])


func test_mash_holds_guard_and_presses_a_direction_every_fourth_frame() -> void:
	var run := _duel(CombatBot.Policy.MASH, 8.0)
	await frames(41)
	var rec := (run["bot"] as CombatBot).recorder.recording()
	var presses := []
	for i in rec.frames.size():
		var entry: Dictionary = rec.frames[i]
		if entry["direction"] != Vector2.ZERO:
			presses.append(i)
		assert_true((entry["held"] as PackedStringArray).has("guard") or i == 0, "guard is held on frame %d" % i)
		assert_true(entry["direction"] == Vector2.ZERO or [Vector2.LEFT, Vector2.RIGHT].has(entry["direction"]), "a sway to a side")
	assert_true(presses.size() >= 9, "a press every 4th frame: %s" % [presses])
	for i in range(1, presses.size()):
		assert_eq(presses[i] - presses[i - 1], 4, "four frames apart")
	assert_true(_ids(run).any(func(i: StringName) -> bool: return String(i).begins_with("sway_")), "and he sways: %s" % [_ids(run)])
	await _end(run)


func test_mash_also_presses_palm_every_seventh_frame_with_a_foe_close() -> void:
	var run := _duel(CombatBot.Policy.MASH, 1.2)
	await frames(60)
	var rec := (run["bot"] as CombatBot).recorder.recording()
	var palms := []
	for i in rec.frames.size():
		if (rec.frames[i]["pressed"] as PackedStringArray).has("palm"):
			palms.append(i)
	assert_true(palms.size() >= 6, "palm pressed: %s" % [palms])
	for i in range(1, palms.size()):
		assert_eq(palms[i] - palms[i - 1], 7, "seven frames apart")
	assert_true(_ids(run).has(&"palm_jab"), "and a jab starts: %s" % [_ids(run)])
	await _end(run)


func test_aggress_guards_an_ordinary_blow() -> void:
	var run := _duel(CombatBot.Policy.AGGRESS)
	await _throw(run, &"knuckle_jab")
	var outcomes: Array = run["got"].map(func(g: Array) -> String: return g[1])
	assert_false(outcomes.has("HIT"), "not hit: %s" % [run["got"]])
	assert_true(outcomes.has("PARRIED") or outcomes.has("GUARDED"), "guarded or parried: %s" % [run["got"]])
	assert_eq((run["a"] as Actor).stats.hp, 100.0)
	await _end(run)


func test_in_an_opening_it_attacks_with_a_combo_of_one_to_three() -> void:
	var lengths := {}
	for seed_number in range(1, 5):
		var run := _duel(CombatBot.Policy.AGGRESS, 1.2, seed_number)
		await frames(30)
		var b: Actor = run["b"]
		b.runner.start(Registry.fetch(&"moves", &"stagger") as MoveData, true)  # reeling: an opening
		await frames(40)
		var palms: Array = run["started"].filter(func(s: Array) -> bool: return String(s[1]).begins_with("palm_"))
		assert_false(palms.is_empty(), "seed %d attacked the reeling foe" % seed_number)
		# a combo is the palms started with no more than a cancel window between them; one that follows a rest is another
		var length := 0
		var last: int = palms[0][0]
		for palm: Array in palms:
			if palm[0] - last > 45:
				break
			length += 1
			last = palm[0]
		lengths[length] = true
		await _end(run)
	for length in lengths:
		assert_true(length >= 1 and length <= 3, "a combo of one to three, not %d" % length)
	assert_true(lengths.size() >= 2, "and the seeds differ in how long: %s" % [lengths.keys()])


func test_it_starts_nothing_while_the_foe_is_not_open_and_the_counter_policy_never_does() -> void:
	var run := _duel(CombatBot.Policy.COUNTER, 1.2)
	await frames(30)
	(run["b"] as Actor).runner.start(Registry.fetch(&"moves", &"stagger") as MoveData, true)
	await frames(60)
	assert_false(_ids(run).any(func(i: StringName) -> bool: return String(i).begins_with("palm_")), "COUNTER starts no attack of its own: %s" % [_ids(run)])
	await _end(run)


func test_after_an_evade_the_counter_policy_counters() -> void:
	var run := _duel(CombatBot.Policy.COUNTER, 1.0, 1)
	await _throw(run, &"knuckle_jab", 100)
	assert_true(_ids(run).has(&"counter_hook"), "the sway's counter: %s" % [_ids(run)])
	await _end(run)


func test_with_two_foes_close_it_clears_out_after_an_evade() -> void:
	var cleared := 0
	for seed_number in range(1, 5):
		var run := _duel(CombatBot.Policy.COUNTER, 1.0, seed_number)
		var extra := TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(1.0, 0, 0.6), "C")
		extra.place(Transform3D(Basis(Vector3.UP, PI), Vector3(1.0, 0, 0.6)))
		await _throw(run, &"knuckle_jab", 100)
		if _ids(run).any(func(i: StringName) -> bool: return String(i).begins_with("clear_")):
			cleared += 1
		await _end(run)
	assert_true(cleared >= 1, "in a crowd it sometimes clears out: %d of 4" % cleared)


func test_out_of_stamina_it_backs_off_and_starts_nothing() -> void:
	var run := _duel(CombatBot.Policy.AGGRESS, 2.0)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	a.stats.spend_stamina(100.0)
	(b.get_node(^".") as Actor).runner.start(Registry.fetch(&"moves", &"stagger") as MoveData, true)
	var gap_before := a.global_position.distance_to(b.global_position)
	await frames(90)
	assert_true(a.global_position.distance_to(b.global_position) > gap_before + 0.5, "he walked away: %.2f to %.2f" % [gap_before, a.global_position.distance_to(b.global_position)])
	assert_false(_ids(run).any(func(i: StringName) -> bool: return String(i).begins_with("palm_")), "and swung at nothing: %s" % [_ids(run)])
	await _end(run)


func test_it_presses_the_finisher_when_the_prompt_shows() -> void:
	var run := _duel(CombatBot.Policy.AGGRESS, 1.2)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await frames(30)
	track(PostureBreaker.make(a, b))
	await frames(3)
	assert_true(b.is_in_group(Actor.FINISHABLE_GROUP), "the foe is open to a finisher")
	await frames(60)
	assert_true(_ids(run).has(&"finisher"), "he finished it: %s" % [_ids(run)])
	assert_false(_ids(run).has(&"palm_jab"), "and did not jab: %s" % [_ids(run)])
	await _end(run)


# --- the whole game: Main, its yard and its waves ---

func test_bot_reports_a_soft_lock_and_saves_its_replay() -> void:
	var game := BotWorld.make(self, 9001)
	var arena := game.arena()
	var foe := arena.enemies()[0]
	var stuck := EndlessMove.make(foe, &"knuckle_jab")
	foe.set_brain(ScriptBrain.new([{"frames": 100000, "hold": [stuck["action"]]}]))
	foe.runner.start(stuck["move"], true)
	var bot := track(CombatBot.new()) as CombatBot
	bot.watch.slack_frames = 10  # a move may last its clip and ten frames more, not sixty: the fixture need not run so long
	bot.begin(game.player, arena, 9001)
	var heard := []
	bot.problem_found.connect(func(line: String) -> void: heard.append(line))
	await frames(90)
	bot.finish()
	assert_false(bot.problems.is_empty(), "a foe whose move never ends is a problem")
	assert_true(bot.problems[0].begins_with("bot: seed 9001 frame "), bot.problems[0])
	assert_true(bot.problems[0].contains("endless_knuckle_jab"), bot.problems[0])
	assert_eq(heard.size(), bot.problems.size(), "and it was said as it was found")
	var path := "%s/seed_9001.tres" % REPLAYS
	assert_true(FileAccess.file_exists(path), "the run's recording is saved to %s" % path)
	var rec := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	assert_true(rec != null and rec.seed == 9001 and rec.frames.size() > 50, "and it is the run's")
	assert_eq(rec.region, game.region.scene_file_path)
	bot.queue_free()
	game.queue_free()
	await frames(2)


func test_the_same_seed_plays_the_same_fight_and_another_plays_another() -> void:
	# In a fight of two with a real Knuckle thinking for itself (the Drummer's fixture, a tier I foe), three runs of 150 frames.
	var runs := []
	for seed_number in [4, 4, 5]:
		var arena := TestArena.make(self)
		var a := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), PlayerBrain.new(), Vector3.ZERO, "A")
		var foe := (load(TestArena.ACTOR) as PackedScene).instantiate() as Actor
		foe.name = "Foe"
		foe.def = load(KNUCKLE) as ActorDef
		foe.position = Vector3(0, 0, 2.5)
		foe.rotation.y = PI
		arena.add_child(foe)
		var bot := track(CombatBot.new()) as CombatBot
		bot.begin(a, null, seed_number, CombatBot.Policy.MIXED)
		await frames(150)
		bot.finish()
		runs.append([bot.recorder.recording().frames.duplicate(), [a.global_position, a.stats.hp, a.stats.stamina, foe.global_position, foe.stats.hp, foe.stats.posture]])
		bot.free()
		arena.free()
		await frames(2)
		InputFeed.release()
	var n := mini(runs[0][0].size(), runs[1][0].size())
	assert_eq(runs[0][0].slice(0, n), runs[1][0].slice(0, n), "a seed plays the same controls")
	assert_eq(runs[0][1], runs[1][1], "and ends in the same state")
	assert_ne(runs[0][0].slice(0, n), runs[2][0].slice(0, n), "another seed plays others")


func test_the_numbers_are_kept_by_the_foes_def() -> void:
	var run := _duel(CombatBot.Policy.COUNTER, 1.0, 1)
	var bot: CombatBot = run["bot"]
	await _throw(run, &"knuckle_jab", 100)
	bot.finish()
	var foes := bot.foes()
	assert_eq(foes.keys(), [&"knuckle_1"], "one foe def, by its id")
	assert_true(foes[&"knuckle_1"]["dealt"] > 0.0, "the counter dealt: %s" % [foes])
	assert_near(foes[&"knuckle_1"]["dealt"], bot.damage_dealt, 0.01, "the rows add up to the run's")
	assert_near(foes[&"knuckle_1"]["taken"], bot.damage_taken, 0.01)
	assert_eq(bot.foe_lines().size(), 1)
	assert_true(bot.foe_lines()[0].contains("foe knuckle_1:"), bot.foe_lines()[0])
	await _end(run)


# --- the Drummer: a seven-blow string met blow by blow, by what is on screen ---

# Abarax (the bot on a PlayerBrain) and a real Drummer, thinking for itself, three metres off. Returns {a, foe, bot, got}.
func _drummer_fight(policy: CombatBot.Policy, seed_number: int) -> Dictionary:
	var arena := TestArena.make(self)
	var a := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), PlayerBrain.new(), Vector3.ZERO, "A")
	var foe := (load(TestArena.ACTOR) as PackedScene).instantiate() as Actor
	foe.name = "Drummer"
	foe.def = load("res://data/actors/knuckle_drummer.tres") as ActorDef
	foe.position = Vector3(0, 0, 3.0)
	foe.rotation.y = PI
	arena.add_child(foe)
	var bot := track(CombatBot.new()) as CombatBot
	bot.begin(a, null, seed_number, policy)
	var run := {"a": a, "foe": foe, "bot": bot, "arena": arena, "got": {}}
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
		var key: String = OUTCOME.keys()[r.outcome]
		run["got"][key] = run["got"].get(key, 0) + 1)
	return run


func test_the_counter_policy_dodges_the_drummers_string_by_line_untouched() -> void:
	var run := _drummer_fight(CombatBot.Policy.COUNTER, 1)
	await frames(450)
	assert_eq((run["a"] as Actor).stats.hp, 100.0, "not a scratch: %s" % [run["got"]])
	assert_true(run["got"].get("EVADED", 0) >= 4, "he evaded its blows: %s" % [run["got"]])
	assert_false(run["got"].has("HIT"), "and none landed: %s" % [run["got"]])
	(run["bot"] as CombatBot).finish()
