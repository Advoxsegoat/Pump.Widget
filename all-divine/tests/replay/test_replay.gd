extends TestCase
## Input recording and replay: what a recording holds and how it is saved, that played back through the real input path
## it makes the same fight (the same moves on the same frames, the same state hash at the end, with the slow-down on and
## wherever the physics frame count stood when it began), and that it goes through the PlayerBrain.

const MAIN := "res://main/main.tscn"
const FILE := "user://test_recording.tres"
const ROUND := HitProfile.Line.ROUND
const KNUCKLE := "res://data/actors/knuckle_1.tres"
## The frames the fixtures run.
const FRAMES := 125
## A screen direction: left, and down the screen (a duck).
const LEFT := Vector2(-1, 0)
const DOWN := Vector2(0, 1)
## A seed whose fight, played by the counter policy, has a perfect dodge in its first 125 frames (the slow-down).
const SLOW_SEED := 2

## The fixture's blows, [frame of the player's clock it lands on, line]: a straight one (parried), a straight one (swayed), a round one
## (ducked).
const BLOWS := [[26, &"straight"], [66, &"straight"], [126, &"round"]]


func after_each() -> void:
	InputFeed.release()
	DirAccess.remove_absolute(FILE)
	Game.reset()
	await frames(1)


# A recording of `n` idle frames, then `pressed` on the frame after them.
func _recording(frames_before: int, pressed: Array[StringName]) -> InputRecording:
	var rec := InputRecording.new()
	for i in frames_before:
		rec.frames.append(InputRecording.idle())
	var press := InputRecording.idle()
	press["pressed"] = PackedStringArray(pressed)
	press["held"] = PackedStringArray(pressed)
	rec.frames.append(press)
	rec.frames.append(InputRecording.idle())
	return rec


# The fixture's hands: a parry, a sway and its counter, a duck and its clear-out, a dash-step, as ScriptedHands steps. The
# blows they answer are posted by _fight, on the frames BLOWS says.
func _hands() -> Array:
	var steps := []
	var at := 0
	var plan := [
		[20, {"press": [&"guard"], "hold": [&"guard"], "frames": 2}],
		[60, {"press": [&"guard"], "hold": [&"guard"], "direction": LEFT, "move": LEFT, "frames": 1}],
		[74, {"press": [&"palm"], "hold": [&"palm"], "frames": 1}],
		[120, {"press": [&"guard"], "hold": [&"guard"], "direction": DOWN, "move": DOWN, "frames": 1}],
		[136, {"press": [&"heavy"], "hold": [&"heavy"], "frames": 1}],
		[200, {"press": [&"dodge"], "hold": [&"dodge"], "move": LEFT, "frames": 1}],
	]
	for row: Array in plan:
		steps.append({"frames": int(row[0]) - at - 1})
		steps.append(row[1])
		at = int(row[0]) - 1 + int(row[1]["frames"])
	return steps


# Abarax, with a PlayerBrain, and a tier I Knuckle a metre from him that stands still, on a flat floor.
func _duel() -> Dictionary:
	var run := Duel.make(self, [], [], 1.0, load(KNUCKLE) as ActorDef)
	(run["a"] as Actor).set_brain(PlayerBrain.new())
	return run


# Plays `frames_to_play` frames of the fixture's fight: BLOWS are posted from the Knuckle, each so that it lands on its frame of
# Abarax's clock. Returns [[frame, move id], ...] for his moves, and the world.
func _fight(run: Dictionary, frames_to_play: int) -> Array:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var started := []
	a.runner.move_started.connect(func(move: MoveData) -> void: started.append([a.frame, move.id]))
	while a.frame < frames_to_play:
		for blow: Array in BLOWS:
			if int(blow[0]) == a.frame + 1:
				Blows.post(b, a, {"line": ROUND} if blow[1] == &"round" else {})
		await frames(1)
	return started


func test_a_recording_is_saved_as_text_and_comes_back_whole() -> void:
	var rec := InputRecording.new()
	rec.region = "res://world/training_yard/training_yard.tscn"
	rec.seed = 7
	rec.start_frame = 3
	rec.frames.append({"move": Vector2(0.5, -1.0), "pressed": PackedStringArray(["guard"]), "held": PackedStringArray(["guard", "palm"]), "direction": LEFT})
	rec.frames.append(InputRecording.idle())
	assert_eq(ResourceSaver.save(rec, FILE), OK)
	var back := ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	assert_true(back != null, "it loads as an InputRecording")
	assert_eq([back.region, back.seed, back.start_frame, back.frames.size()], [rec.region, 7, 3, 2])
	assert_eq(back.frames[0]["move"], Vector2(0.5, -1.0))
	assert_eq(back.frames[0]["pressed"], PackedStringArray(["guard"]))
	assert_eq(back.frames[0]["held"], PackedStringArray(["guard", "palm"]))
	assert_eq(back.frames[0]["direction"], LEFT, "the direction pressed that frame is kept, for the sways and ducks")
	assert_true(FileAccess.get_file_as_string(FILE).begins_with("[gd_resource"), "and the file is text")


func test_the_recorder_writes_what_inputs_reports_each_physics_frame() -> void:
	var recorder := track(InputRecorder.new()) as InputRecorder
	assert_eq(recorder.process_physics_priority, -110, "before Melee's snapshot and the actors")
	var hands := track(ScriptedHands.new([
		{"frames": 1},
		{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "direction": LEFT, "move": LEFT},
		{"frames": 1, "hold": [&"guard"], "move": LEFT},
		{"frames": 1},
	]))
	await frames(6)
	hands.queue_free()
	var rec := recorder.recording()
	assert_true(rec.frames.size() >= 4, "a frame each, from the frame after the one it began on")
	assert_eq(rec.frames[0], InputRecording.idle(), "an idle frame is idle")
	assert_eq(rec.frames[1]["pressed"], PackedStringArray(["guard"]))
	assert_eq(rec.frames[1]["held"], PackedStringArray(["guard"]))
	assert_eq(rec.frames[1]["direction"], LEFT)
	assert_eq(rec.frames[1]["move"], LEFT)
	assert_eq(rec.frames[2]["pressed"], PackedStringArray(), "held is not pressed again")
	assert_eq(rec.frames[2]["direction"], Vector2.ZERO)
	assert_eq(rec.frames[3], InputRecording.idle())


func test_replay_goes_through_the_player_brain() -> void:
	var run := _duel()
	var a: Actor = run["a"]
	assert_true(a.brain is PlayerBrain)
	var started := []
	a.runner.move_started.connect(func(move: MoveData) -> void: started.append([a.frame, move.id]))
	var replayer := track(InputReplayer.new()) as InputReplayer
	assert_eq(replayer.process_physics_priority, InputFeed.PRIORITY, "it gives the next frame its input at the end of this one")
	replayer.play(_recording(10, [&"palm"]))
	await frames(20)
	assert_eq(started.size(), 1, "one move: %s" % [started])
	assert_eq(started[0][1], &"palm_jab", "a recorded palm press starts the jab, read by the PlayerBrain from the real action")
	assert_eq(started[0][0], 12, "on the frame it was recorded for: the first entry is read on the second frame the replayer lives")


func test_the_replayer_says_when_it_has_finished_and_lets_go() -> void:
	var replayer := track(InputReplayer.new()) as InputReplayer
	var done := [false]
	replayer.finished.connect(func() -> void: done[0] = true)
	var rec := _recording(2, [&"guard"])
	replayer.play(rec)
	await frames(2)
	assert_false(done[0], "not before the last frame")
	await frames(3)
	assert_true(done[0], "after it")
	assert_false(Input.is_action_pressed(&"guard"), "nothing is left held")
	assert_eq(Inputs.move_vector(), Vector2.ZERO)


func test_a_recorded_parry_sway_duck_counter_clearout_and_dash_step_replay_to_the_same_moves_on_the_same_frames() -> void:
	var first := _duel()
	var recorder := track(InputRecorder.new()) as InputRecorder
	track(ScriptedHands.new(_hands()))
	var played := await _fight(first, 260)
	var rec := recorder.recording()
	var ids := played.map(func(m: Array) -> StringName: return m[1])
	assert_true(ids.has(&"guard_raise"), "the parry was played: %s" % [ids])
	assert_true(ids.any(func(i: StringName) -> bool: return String(i).begins_with("sway_")), "a sway: %s" % [ids])
	assert_true(ids.any(func(i: StringName) -> bool: return String(i).begins_with("duck_")), "a duck: %s" % [ids])
	assert_true(ids.has(&"counter_hook"), "the sway's counter: %s" % [ids])
	assert_true(ids.any(func(i: StringName) -> bool: return String(i).begins_with("clear_")), "the duck's clear-out: %s" % [ids])
	assert_true(ids.any(func(i: StringName) -> bool: return String(i).begins_with("dash_step")), "a dash-step: %s" % [ids])
	var hp_first := (first["a"] as Actor).stats.hp
	# the same recording, in a new fight
	for node in [first["arena"], recorder]:
		(node as Node).queue_free()
	for node in get_children():
		if node is ScriptedHands:
			node.queue_free()
	await frames(2)
	InputFeed.release()
	var second := _duel()
	var replayer := track(InputReplayer.new()) as InputReplayer
	replayer.play(rec)
	var replayed := await _fight(second, 260)
	assert_eq(replayed, played, "the same moves on the same frames")
	assert_eq((second["a"] as Actor).stats.hp, hp_first, "and the same damage taken")


# --- the whole game: Main, its yard and its waves ---

# A new game (Main, with the yard's first wave sent) whose spawn dice are those of `seed`, under this test.
func _game(seed: int) -> Main:
	return BotWorld.make(self, seed)


# Plays `rec` into a new game of its seed, FRAMES frames: the state hash at the end. The game is freed.
func _replay_game(rec: InputRecording) -> int:
	var game := _game(rec.seed)
	var replayer := track(InputReplayer.new()) as InputReplayer
	var result := [0]
	replayer.finished.connect(func() -> void: result[0] = game.arena().state_hash())  # at the end of the frame that lived the last entry
	replayer.play(rec)
	while replayer.playing():
		await frames(1)
	for node: Node in [replayer, game]:
		node.queue_free()
	await frames(2)
	InputFeed.release()
	return result[0]


# --- a fight the bot plays, with the slow-down ---

# Plays `how` for the bot in a new game of `seed` until it has `count` frames recorded: [the recording, the state hash at the end, whether
# the fight was ever slowed (ChainSlow, on a perfect dodge), the problems the bot found]. The game is freed.
func _record_bot(seed: int, how: CombatBot.Policy, count: int, pause_at := -1) -> Array:
	var game := _game(seed)
	var bot := track(CombatBot.new()) as CombatBot
	bot.listen_for_errors = true
	bot.begin(game.player, game.arena(), seed, how)
	var slowed := false
	while bot.recorder.recording().frames.size() < count:
		await frames(1)
		slowed = slowed or Melee.slowed()
		if bot.recorder.recording().frames.size() == pause_at:
			Game.change(Game.State.PAUSE)  # the game is paused for 200 frames here and given back
			await frames(200)
			Game.change(Game.State.PLAY)
	bot.finish()
	var result := [bot.recorder.recording(), game.arena().state_hash(), slowed, bot.problems]
	bot.recorder.set_physics_process(false)
	bot.set_physics_process(false)
	for node: Node in [bot, game]:
		node.queue_free()
	await frames(2)
	InputFeed.release()
	return result


func test_a_fight_the_bot_played_replays_to_the_same_hash_with_the_slow_down_from_a_file_and_whenever_it_is_played() -> void:
	var recorded := await _record_bot(SLOW_SEED, CombatBot.Policy.COUNTER, FRAMES)
	var rec: InputRecording = recorded[0]
	assert_eq(rec.frames.size(), FRAMES, "a frame each")
	assert_true(rec.frames.any(func(f: Dictionary) -> bool: return (f["pressed"] as PackedStringArray).has("guard")), "and it holds the guard presses of the sways")
	assert_eq(recorded[3], PackedStringArray(), "the bot found no problem in the real game")
	assert_true(recorded[2], "the fight was slowed by a perfect dodge, so the replay has to meet the slow-down")
	assert_eq(await _replay_game(rec), recorded[1], "the same recording, seed and region give the same hash at the end")
	# The frame count the hash holds is the arena's own, from its wave's start: the same recording, read from its file and played after
	# a hundred idle frames (the engine's count a hundred higher), hashes the same.
	assert_eq(ResourceSaver.save(rec, FILE), OK)
	var from_file := ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	var at := Engine.get_physics_frames()
	await frames(100)
	assert_eq(Engine.get_physics_frames(), at + 100)
	assert_eq(await _replay_game(from_file), recorded[1], "played from the file, a hundred frames later")
	assert_eq(rec.settings, {"effects/slowdown_on": true}, "the header says what the settings that change a fight were")


func test_a_bot_run_paused_for_two_hundred_frames_is_the_run_never_paused() -> void:
	var plain := await _record_bot(SLOW_SEED, CombatBot.Policy.COUNTER, FRAMES)
	var paused := await _record_bot(SLOW_SEED, CombatBot.Policy.COUNTER, FRAMES, 60)
	assert_eq(paused[1], plain[1], "the same end hash")
	assert_eq((paused[0] as InputRecording).frames, (plain[0] as InputRecording).frames, "the same controls: the pause is not in the recording")
	assert_eq(paused[3], PackedStringArray(), "and the bot found no problem in it")


# The settings that change a fight (found by running a seeded bot fight at each setting's default and at its other end: only the slow-down
# changed it, in a counter fight where a perfect dodge fires it and in an aggress fight of 500 frames where it does not), and those that do
# not. Every setting there is must be in one list: a new one fails this test until someone has run the survey for it and put it in one.
const CHANGES_A_FIGHT: Array[String] = ["effects/slowdown_on"]
const DOES_NOT: Array[String] = [
	"effects/parry_aura_on", "effects/perilous_rim_on", "effects/heavy_wave_on", "effects/perilous_wave_on", "effects/perilous_icon_on",
	"effects/parry_burst_on", "effects/afterimage_on", "effects/chain_rim_on", "camera/shake", "camera/dips",
	"look/outline", "look/dof", "look/bloom", "look/fog", "look/grade", "look/vignette",
	"sound/master", "sound/music", "sound/sfx", "sound/voice", "sound/ui", "window/mode", "window/scale",
]


func test_every_setting_is_known_to_change_a_fight_or_not_and_the_header_stores_those_that_do() -> void:
	var known := CHANGES_A_FIGHT + DOES_NOT
	var unknown := []
	for key in Settings.keys():
		if not known.has(key):
			unknown.append(key)
	assert_eq(unknown, [], "a setting that has not been surveyed: run a seeded fight with it at both ends, and list it")
	for key in known:
		assert_true(Settings.keys().has(key), "%s is a setting" % key)
	assert_eq(InputRecording.FIGHT_SETTINGS, CHANGES_A_FIGHT, "the header stores exactly the settings that change a fight")


func test_a_fight_recorded_with_the_slow_down_off_replays_as_recorded_with_it_on() -> void:
	var path := "user://settings_replay_test.cfg"
	var player_path := Settings.path
	Settings.path = path
	Settings.set_value("effects/slowdown_on", false)
	var off := await _record_bot(SLOW_SEED, CombatBot.Policy.COUNTER, FRAMES)
	Settings.reset_all()
	assert_true(Settings.get_value("effects/slowdown_on"), "the slow-down is on again, as by default")
	var written := FileAccess.get_file_as_string(path)
	var rec: InputRecording = off[0]
	assert_eq(rec.settings, {"effects/slowdown_on": false}, "the header says it was off")
	assert_false(off[2], "and the fight was never slowed")
	var again := await _replay_game(rec)
	assert_eq(again, off[1], "replayed with the slow-down on by default, it is the fight that was recorded")
	assert_true(Settings.get_value("effects/slowdown_on"), "and the player's setting is back after it")
	assert_eq(FileAccess.get_file_as_string(path), written, "the file was not written")
	DirAccess.remove_absolute(path)
	Settings.path = player_path


func test_lent_settings_are_neither_written_nor_announced_and_come_back() -> void:
	var path := "user://settings_lend_test.cfg"
	var player_path := Settings.path
	Settings.path = path
	Settings.set_value("camera/shake", 50)
	var written := FileAccess.get_file_as_string(path)
	var heard := []
	var listener := func(key: String) -> void: heard.append(key)
	Settings.changed.connect(listener)
	var before := Settings.lend({"camera/shake": 0, "effects/slowdown_on": false, "no/such_key": 1, "camera/dips": "not a switch"})
	assert_eq(Settings.get_value("camera/shake"), 0, "lent")
	assert_eq(Settings.get_value("effects/slowdown_on"), false, "lent")
	assert_eq(before, {"camera/shake": 50, "effects/slowdown_on": true}, "what they were: a key that is not one and a value that does not check are left alone")
	Settings.take_back(before)
	assert_eq([Settings.get_value("camera/shake"), Settings.get_value("effects/slowdown_on")], [50, true], "given back")
	assert_eq(heard, [], "no one was told")
	assert_eq(FileAccess.get_file_as_string(path), written, "and the file was not written")
	Settings.changed.disconnect(listener)
	Settings.reset_all()
	DirAccess.remove_absolute(path)
	Settings.path = player_path
