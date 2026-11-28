extends TestCase
## A fight-changing setting changed in the middle of a recording (the settings screen in the pause menu does it) is part of the
## recording: the entry of the first frame of play after the change carries it, and the replay lends it before that frame. Every
## test plays a seeded fight of the combat bot in the real Main, changes the setting through the real pause menu (or Settings), and
## replays the recording in a new game, unpaused, as the game does.

const SETTINGS_PATH := "user://settings_change_test.cfg"
const C := MenuNav.Cmd
const SLOWDOWN := "effects/slowdown_on"
const FRAMES := 240


func before_each() -> void:
	Settings.path = SETTINGS_PATH
	Settings.reset_all()


func after_each() -> void:
	for code in [KEY_DOWN, KEY_UP, KEY_ENTER, KEY_ESCAPE]:
		_key(code, false)
	for button in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]:
		_pad(button, false)
	InputFeed.release()
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	for file in [SETTINGS_PATH, SETTINGS_PATH + ".tmp"]:
		DirAccess.remove_absolute(file)
	Game.reset()
	await frames(1)


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pad(button: JoyButton, pressed := true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# One press of `cmd` on the keys, or on the pad.
func _press(cmd: MenuNav.Cmd, pad: bool) -> void:
	var keys := {C.DOWN: KEY_DOWN, C.UP: KEY_UP, C.CHOOSE: KEY_ENTER, C.BACK: KEY_ESCAPE}
	var pads := {C.DOWN: JOY_BUTTON_DPAD_DOWN, C.UP: JOY_BUTTON_DPAD_UP, C.CHOOSE: JOY_BUTTON_A, C.BACK: JOY_BUTTON_B}
	if pad:
		_pad(pads[cmd])
		_pad(pads[cmd], false)
	else:
		_key(keys[cmd])
		_key(keys[cmd], false)
	await frames(1)


func _select(menu: Menu, label: String, pad: bool) -> void:
	for i in 12:
		if menu.rows()[menu.index].label == label:
			return
		await _press(C.DOWN, pad)
	fail("could not select '%s' on %s" % [label, menu.page])


# Opens the pause menu with Esc, walks to the row `path` names on each page (choosing all but the last, which is `last`: CHOOSE on a
# switch turns it over), and comes back out by Back and Resume.
func _through_the_menu(main: Main, pad: bool, path: Array, last := C.CHOOSE) -> void:
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PAUSE, "the menu is open")
	await frames(2)
	for i in path.size():
		await _select(main.menu, path[i], pad)
		await _press(C.CHOOSE if i < path.size() - 1 else last, pad)
	while main.menu.page != MenuPages.ROOT:
		await _press(C.BACK, pad)
	await _select(main.menu, "Resume", pad)
	await _press(C.CHOOSE, pad)
	assert_eq(Game.state, Game.State.PLAY, "the game goes on")


# A new Main of seed 2 with the bot (counter, reaction 0) playing and recording; `change` is awaited at frame 60 with the Main; the
# recording runs to FRAMES. Returns {rec, hash}.
func _fight(change: Callable) -> Dictionary:
	Game.reset()
	var main := BotWorld.make(self, 2)
	var bot := track(CombatBot.new()) as CombatBot
	bot.reaction_frames = 0
	bot.begin(main.player, main.arena(), 2, CombatBot.Policy.COUNTER)
	bot.recorder.hash_every = 15
	while bot.recorder.recording().frames.size() < 60:
		await frames(1)
	if change.is_valid():
		await change.call(main, bot)
	while bot.recorder.recording().frames.size() < FRAMES:
		await frames(1)
	bot.recorder.close()
	var result := {"rec": bot.recorder.recording(), "hash": main.arena().state_hash()}
	bot.finish()
	bot.recorder.set_physics_process(false)
	bot.free()
	main.free()
	await frames(2)
	InputFeed.release()
	return result


# Plays `rec` into a new Main of its seed as a replay is (the defaults lent, the recording's settings after): [the frame it diverged at or -1,
# whether it finished].
func _replay(rec: InputRecording) -> Array:
	Settings.reset_all()
	Game.reset()
	var main := BotWorld.make(self, rec.seed)
	main.lend_replay_defaults()
	main.start_replay(rec)
	var replayer: InputReplayer = main._replayer
	var result := [-1, false]
	replayer.diverged.connect(func(at: int, _recorded: int, _got: int) -> void: result[0] = at)
	replayer.finished.connect(func() -> void: result[1] = true)
	while replayer.playing():
		await frames(1)
	main.free()
	await frames(2)
	InputFeed.release()
	return result


func _changes(rec: InputRecording) -> Array:
	var found := []
	for i in rec.frames.size():
		if (rec.frames[i] as Dictionary).has("settings"):
			found.append([i, rec.frames[i]["settings"]])
	return found


func _check_replays(played: Dictionary, label: String) -> void:
	var again := await _replay(played["rec"])
	assert_eq(again[0], -1, "%s: no divergence" % label)
	assert_true(again[1], "%s: finished" % label)


func test_the_slow_down_switched_in_the_pause_menu_is_recorded_and_replays_as_recorded() -> void:
	for pad in [false, true]:
		for start in [true, false]:
			Settings.set_value(SLOWDOWN, start)
			var played := await _fight(func(main: Main, _bot: CombatBot) -> void:
				await _through_the_menu(main, pad, ["Settings", "Effects", "Slow-down on a perfect dodge"]))
			var label := "%s, %s -> %s" % ["pad" if pad else "keys", start, not start]
			assert_eq(Settings.get_value(SLOWDOWN), not start, "%s: the screen turned it" % label)
			assert_eq((played["rec"] as InputRecording).settings[SLOWDOWN], start, "%s: the header keeps the start" % label)
			var changes := _changes(played["rec"])
			assert_eq(changes.size(), 1, "%s: one change is recorded: %s" % [label, changes])
			if changes.size() == 1:
				assert_eq(changes[0][1], {SLOWDOWN: not start}, "%s: it is the new value" % label)
			await _check_replays(played, label)
			Settings.reset_all()


func test_a_fight_with_no_change_has_none_recorded_and_still_replays() -> void:
	var played := await _fight(Callable())
	assert_eq(_changes(played["rec"]), [], "nothing recorded")
	await _check_replays(played, "control")


func test_two_changes_in_one_pause_that_end_where_they_began_record_nothing() -> void:
	var played := await _fight(func(main: Main, _bot: CombatBot) -> void:
		_key(KEY_ESCAPE)
		_key(KEY_ESCAPE, false)
		await frames(2)
		Settings.set_value(SLOWDOWN, false)
		await frames(2)
		Settings.set_value(SLOWDOWN, true)
		await frames(2)
		Game.change(Game.State.PLAY))
	assert_eq(_changes(played["rec"]), [], "nothing recorded")
	await _check_replays(played, "there and back")


func test_restore_defaults_in_the_middle_of_a_recording_made_with_the_slow_down_off_replays_as_recorded() -> void:
	Settings.set_value(SLOWDOWN, false)
	var played := await _fight(func(main: Main, _bot: CombatBot) -> void:
		await _through_the_menu(main, false, ["Settings", "Restore defaults", "Restore"]))
	assert_eq(Settings.get_value(SLOWDOWN), true, "restored")
	assert_eq(_changes(played["rec"]).size(), 1, "the change is recorded: %s" % [_changes(played["rec"])])
	await _check_replays(played, "restore defaults")


func test_a_change_on_the_last_frame_of_a_recording_is_recorded() -> void:
	Game.reset()
	var main := BotWorld.make(self, 2)
	var bot := track(CombatBot.new()) as CombatBot
	bot.reaction_frames = 0
	bot.begin(main.player, main.arena(), 2, CombatBot.Policy.COUNTER)
	bot.recorder.hash_every = 15
	while bot.recorder.recording().frames.size() < FRAMES - 1:
		await frames(1)
	Settings.set_value(SLOWDOWN, false)
	await frames(1)
	bot.recorder.close()
	var rec := bot.recorder.recording()
	var changes := _changes(rec)
	assert_eq(changes.size(), 1, "recorded: %s" % [changes])
	if changes.size() == 1:
		assert_eq(changes[0][0], rec.frames.size() - 1, "on the last frame")
	bot.finish()
	bot.recorder.set_physics_process(false)
	bot.free()
	main.free()
	await frames(2)
	InputFeed.release()
	var again := await _replay(rec)
	assert_eq(again[0], -1, "and it replays as recorded")


func test_each_setting_the_header_lists_is_replayed_as_recorded_when_changed_in_the_middle_of_a_fight() -> void:
	for key in InputRecording.FIGHT_SETTINGS:
		var start: Variant = Settings.get_value(key)
		var other: Variant = (not start) if typeof(start) == TYPE_BOOL else (50 if start != 50 else 100)
		var played := await _fight(func(_main: Main, _bot: CombatBot) -> void: Settings.set_value(key, other))
		assert_eq(_changes(played["rec"]).size(), 1, "%s: the change is recorded" % key)
		await _check_replays(played, key)
		Settings.reset_all()
