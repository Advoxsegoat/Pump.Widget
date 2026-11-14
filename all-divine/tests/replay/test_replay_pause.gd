extends TestCase
## A recording agrees with the real pause menu and its quarantine (Inputs.quarantine): what a recording holds is what the fight was
## given, the input as the game read it after the quarantine, so a button pressed during a pause and still held when it closes is
## dead in the recorded fight until it is let go, a hold from before the pause stays a hold, one pressed and let go in the pause was
## never there, and a replay that never pauses and has no quarantine is the same fight.
##
## Main is the game, with the real menu: the pause is opened and closed by real events (Input.parse_input_event), as the menus' tests do.
## Which counter is which: Game.play_frames counts the frames the tree ran, as the recorder's frames do (it pauses with the tree) and the
## arena's frame counter (Arena.state_hash) does, so a pause moves none of them.

const MAIN := "res://main/main.tscn"
const YARD := "res://world/training_yard/training_yard.tscn"


func after_each() -> void:
	for code in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		_key(code, false)
	for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]:
		_pad(button, false)
	for action in [&"palm", &"heavy", &"guard", &"dodge"]:
		Input.action_release(action)
	InputFeed.release()
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
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


# A new game of seed 1 (the foes left as they come: the fight is theirs and the player's).
func _game() -> Main:
	Game.reset()
	Arena.start_seed(1)
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	return main


# Plays the fight through the real pause: guard held from before it; in it, palm pressed and held across the close, and heavy pressed
# and let go; closed by `close_down` (let go by `close_up`), opened by Esc. Returns {rec, hash}, the recording (closed) and the arena's
# hash at its end. The game is freed.
func _play_through_a_pause(close_down: Callable, close_up: Callable, pause_for := 5) -> Dictionary:
	var main := _game()
	main.start_recording(ProjectSettings.globalize_path("user://pause_recording.tres"))
	var recorder: InputRecorder = main._recorder
	recorder.hash_every = 15
	await frames(4)
	Input.action_press(&"guard")  # held from before the pause
	await frames(4)
	_key(KEY_ESCAPE)  # Esc opens the menu
	_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PAUSE, "the menu is open")
	await frames(2)
	Input.action_press(&"palm")  # pressed in the pause and held across the close
	Input.action_press(&"heavy")  # pressed and let go in it
	await frames(2)
	Input.action_release(&"heavy")
	await frames(pause_for)
	close_down.call()
	assert_eq(Game.state, Game.State.PLAY, "the menu is closed")
	await frames(10)  # palm is held across the close: dead
	Input.action_release(&"palm")
	close_up.call()
	await frames(8)
	Input.action_release(&"guard")
	await frames(3)
	var rec := recorder.recording()
	recorder.close()
	var result := {"rec": rec, "hash": main.arena().state_hash()}
	recorder.set_physics_process(false)
	main.free()
	await frames(2)
	return result


# Plays `rec` into a new game of its seed, unpaused: [the checkpoint it diverged at or -1, whether it finished].
func _replay(rec: InputRecording) -> Array:
	var main := _game()
	main.start_replay(rec)
	var replayer: InputReplayer = main._replayer
	var result := [-1, false]
	replayer.diverged.connect(func(at: int, _recorded: int, _got: int) -> void: result[0] = at)
	replayer.finished.connect(func(_agreed: bool = false) -> void: result[1] = true)
	while replayer.playing():
		await frames(1)
	main.free()
	await frames(2)
	InputFeed.release()
	return result


func test_a_fight_recorded_through_the_real_pause_replays_unpaused_however_the_menu_was_closed() -> void:
	var cases := [
		{name = "Esc", down = func() -> void: _key(KEY_ESCAPE), up = func() -> void: _key(KEY_ESCAPE, false)},
		{name = "pad Start", down = func() -> void: _pad(JOY_BUTTON_START), up = func() -> void: _pad(JOY_BUTTON_START, false)},
		{name = "Resume chosen with pad A", down = func() -> void: _pad(JOY_BUTTON_A), up = func() -> void: _pad(JOY_BUTTON_A, false)},
		{name = "Back with pad B", down = func() -> void: _pad(JOY_BUTTON_B), up = func() -> void: _pad(JOY_BUTTON_B, false)},
	]
	for one: Dictionary in cases:
		var played := await _play_through_a_pause(one.down, one.up)
		var rec: InputRecording = played["rec"]
		for entry: Dictionary in rec.frames:
			assert_false((entry["pressed"] as PackedStringArray).has("heavy") or (entry["held"] as PackedStringArray).has("heavy"), "%s: a heavy pressed and let go in the pause was never there" % one.name)
			assert_false((entry["pressed"] as PackedStringArray).has("menu"), "%s: nor is the menu button" % one.name)
		var guarded := rec.frames.filter(func(e: Dictionary) -> bool: return (e["held"] as PackedStringArray).has("guard")).size()
		assert_true(guarded >= 8, "%s: the guard held from before the pause stays held (%d frames)" % [one.name, guarded])
		var palm_frames := rec.frames.filter(func(e: Dictionary) -> bool: return (e["held"] as PackedStringArray).has("palm") or (e["pressed"] as PackedStringArray).has("palm"))
		assert_true(palm_frames.is_empty(), "%s: palm, pressed in the pause and held across the close, is dead in the fight (%d frames of it)" % [one.name, palm_frames.size()])
		var again := await _replay(rec)
		assert_eq(again[0], -1, "%s: the replay, with no pause and no quarantine, agrees with the hashes" % one.name)
		assert_true(again[1], "%s: and finishes" % one.name)


func test_the_play_clock_the_recorders_frames_and_the_arenas_frame_counter_move_together_and_stop_in_a_pause() -> void:
	# Game.play_frames: the frames the tree ran (Game is pausable). InputRecorder: one entry for each frame it ran (pausable). Arena
	# (state_hash's counter, _wave_frames): the physics frames since the wave was sent (pausable). A pause moves none of them, and play
	# moves each by the frames played.
	var main := _game()
	main.start_recording(ProjectSettings.globalize_path("user://pause_recording.tres"))
	var recorder: InputRecorder = main._recorder
	var arena := main.arena()
	var counters := func() -> Array: return [Game.play_frames, recorder.recording().frames.size(), arena._wave_frames]
	await frames(10)
	var before: Array = counters.call()
	Game.change(Game.State.PAUSE)
	await frames(60)
	assert_eq(counters.call(), before, "60 paused frames: none of the three moved")
	Game.change(Game.State.PLAY)
	await frames(1)
	var resumed: Array = counters.call()
	await frames(20)
	var after: Array = counters.call()
	var played := [after[0] - resumed[0], after[1] - resumed[1], after[2] - resumed[2]]
	assert_eq(played, [20, 20, 20], "20 frames of play moved each by 20: %s" % [played])
	recorder.set_physics_process(false)
	main.free()
	await frames(2)
