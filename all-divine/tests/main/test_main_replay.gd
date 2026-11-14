extends TestCase
## Main's --record=<path> and --replay=<path> user arguments: what they are read as, that a recording started in Main is saved
## and is a recording of the game's own player (not of a stand-in), and that a recording started in Main plays into its player.

const MAIN := "res://main/main.tscn"
const FILE := "user://main_recording.tres"
const PLAYER_FILE := "user://main_replay_player_settings.cfg"

var _was_path := ""
var _was_player_path := ""
var _was_scripted := false


func before_each() -> void:
	_was_path = Settings.path
	_was_player_path = Settings.player_path
	_was_scripted = Settings.scripted_run


func after_each() -> void:
	InputFeed.release()
	Settings.scripted_run = _was_scripted
	Settings.path = _was_path
	Settings.player_path = _was_player_path
	Settings.reset_all()  # the player's own file is out of reach here (a scripted run), so this writes nothing
	for file in [PLAYER_FILE, PLAYER_FILE + ".tmp"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(FILE)
	Game.reset()
	await frames(1)


# A scratch file standing in for the player's, as the game would use it (not a scripted run), holding master 40, shake 25 and the
# slow-down off; returns its text.
func _players_file() -> String:
	Settings.path = PLAYER_FILE
	Settings.player_path = PLAYER_FILE
	Settings.scripted_run = false
	Settings.set_value("sound/master", 40)
	Settings.set_value("camera/shake", 25)
	Settings.set_value("effects/slowdown_on", false)
	return FileAccess.get_file_as_string(PLAYER_FILE)


func _idle_recording(count: int) -> InputRecording:
	var rec := InputRecording.new()
	rec.region = "res://world/training_yard/training_yard.tscn"
	for i in count:
		rec.frames.append(InputRecording.idle())
	rec.frame_count = count
	return rec


func _main() -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	return track((load(MAIN) as PackedScene).instantiate()) as Main


func test_the_arguments_are_read() -> void:
	assert_eq(Main.parse_arguments(PackedStringArray(["--record=a.tres"])), {"record": "a.tres", "replay": "", "replaying": false})
	assert_eq(Main.parse_arguments(PackedStringArray(["--selftest", "--replay=b.tres"])), {"record": "", "replay": "b.tres", "replaying": true})
	assert_eq(Main.parse_arguments(PackedStringArray()), {"record": "", "replay": "", "replaying": false})
	assert_eq(Main.parse_arguments(PackedStringArray(["--replay="])), {"record": "", "replay": "", "replaying": true}, "given, with no path")
	assert_eq(Main.parse_arguments(PackedStringArray(["--replay"])), {"record": "", "replay": "", "replaying": true}, "given, with no =")


func test_a_recording_started_in_main_is_saved_with_what_the_player_did() -> void:
	var main := _main()
	main.start_recording(FILE)
	var palm := track(ScriptedHands.new([{"frames": 5}, {"frames": 1, "press": [&"palm"], "hold": [&"palm"]}, {"frames": 5}]))
	await frames(14)
	palm.queue_free()
	assert_eq(main.save_recording(), OK)
	var rec := ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	assert_true(rec != null, "it is saved as a recording")
	assert_eq(rec.region, "res://world/training_yard/training_yard.tscn", "of the yard")
	assert_true(rec.frames.any(func(f: Dictionary) -> bool: return (f["pressed"] as PackedStringArray).has("palm")), "with his palm in it")


func test_a_recording_started_in_main_plays_into_the_player() -> void:
	var main := _main()
	var rec := InputRecording.new()
	rec.region = "res://world/training_yard/training_yard.tscn"
	for i in 8:
		rec.frames.append(InputRecording.idle())
	var press := InputRecording.idle()
	press["pressed"] = PackedStringArray(["palm"])
	press["held"] = PackedStringArray(["palm"])
	rec.frames.append(press)
	rec.frames.append(InputRecording.idle())
	var started := []
	main.player.runner.move_started.connect(func(move: MoveData) -> void: started.append(move.id))
	main.start_replay(rec)
	await frames(20)
	assert_true(started.has(&"palm_jab"), "the recorded palm starts the jab: %s" % [started])


func test_a_debug_key_pressed_while_recording_is_said_in_the_header_and_the_replay_is_refused() -> void:
	var main := _main()
	main.start_recording(FILE)
	await frames(5)
	var event := InputEventKey.new()
	event.keycode = KEY_F6
	event.physical_keycode = KEY_F6
	event.pressed = true
	main._unhandled_input(event)
	await frames(3)
	assert_eq(main.save_recording(), OK)
	var rec := ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	assert_true(rec.debug_keys, "the header says a debug key was pressed")
	assert_true(Main.replay_refusal(FILE).contains("debug key"), "and a replay of it is refused: %s" % Main.replay_refusal(FILE))


func test_a_replay_is_refused_before_any_fight_for_a_file_that_cannot_be_used() -> void:
	assert_true(Main.replay_refusal("user://no_such_recording.tres").contains("no recording"), "none there")
	var garbage := FileAccess.open(FILE, FileAccess.WRITE)
	garbage.store_string("[gd_resource type=\"Resource\" format=3]\n[resource\nnot a recording")
	garbage.close()
	var why: String = quietly(func() -> Variant: return Main.replay_refusal(FILE))
	assert_true(why.contains("not a recording"), "garbage: %s" % why)
	var rec := InputRecording.new()
	rec.frames.append(InputRecording.idle())
	rec.frame_count = 3
	ResourceSaver.save(rec, FILE)
	assert_true(Main.replay_refusal(FILE).contains("cut short"), "cut short: %s" % Main.replay_refusal(FILE))
	rec.frame_count = 1
	rec.version = 7
	ResourceSaver.save(rec, FILE)
	assert_true(Main.replay_refusal(FILE).contains("format"), "an unknown format: %s" % Main.replay_refusal(FILE))
	rec.version = InputRecording.VERSION
	ResourceSaver.save(rec, FILE)
	assert_true(Main.replay_refusal(FILE).contains("hash"), "no hash to agree with: %s" % Main.replay_refusal(FILE))
	rec.hashes[1] = 9
	ResourceSaver.save(rec, FILE)
	assert_eq(Main.replay_refusal(FILE), "", "a good file is not refused")


func test_a_replay_says_as_recorded_only_when_the_hash_at_its_end_was_compared() -> void:
	var rec := InputRecording.new()
	rec.frames.append(InputRecording.idle())
	rec.frame_count = 1
	assert_false(Main.end_is_compared(rec), "no hashes")
	rec.hashes[0] = 3
	assert_false(Main.end_is_compared(rec), "a hash, but not at the end")
	rec.hashes[1] = 3
	assert_true(Main.end_is_compared(rec), "one at the end")


func test_the_lines_a_replay_ends_with() -> void:
	assert_eq(Main.diverged_line(120, 5, 6), "replay: diverged at frame 120 (recorded 5, got 6)")
	assert_eq(Main.finished_line(77, true), "replay: finished, state hash 77, as recorded")
	assert_eq(Main.EXIT_REFUSED, 2)
	assert_eq(Main.EXIT_DIVERGED, 3)


# Main started headless with the user argument `argument`, as the game is: [exit code, what it printed]. A fight that nothing ends is stopped
# after twenty seconds (code 124).
func _run_main(argument: String) -> Array:
	var argv := PackedStringArray(["-k", "5", "20", OS.get_executable_path(), "--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--fixed-fps", "60", "--", argument])
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	return [code, "".join(PackedStringArray(output))]


func _write_text(name: String, text: String) -> String:
	var path := ProjectSettings.globalize_path("user://" + name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func test_main_given_a_file_it_cannot_use_says_so_and_quits_with_2_without_a_fight() -> void:
	var path := _write_text("garbage_recording.tres", "not a recording")
	var ran := _run_main("--replay=" + path)
	DirAccess.remove_absolute(path)
	assert_eq(ran[0], 2, ran[1])
	assert_true(ran[1].contains("replay: "), "one line saying why: %s" % ran[1])


func test_a_file_that_does_not_parse_is_refused_with_one_line_and_no_engine_error() -> void:
	var cases := {
		"empty": "",
		"garbage": "\u0001\u0002 not a recording at all {{{",
		"cut mid-record": "[gd_resource type=\"Resource\" script_class=\"InputRecording\" load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=\"res://core/replay/input_recording.gd\" id=\"1\"]\n\n[resource]\nscript = ExtResource(\"1\")\nframes = [{\n\"move\": Vec",
	}
	for label: String in cases:
		var path := _write_text("unparsed_recording.tres", cases[label])
		var ran := _run_main("--replay=" + path)
		DirAccess.remove_absolute(path)
		assert_eq(ran[0], 2, "%s: %s" % [label, ran[1]])
		assert_false(ran[1].contains("ERROR"), "%s: no engine error block: %s" % [label, ran[1]])
		assert_eq(ran[1].count("replay: "), 1, "%s: one line of its own: %s" % [label, ran[1]])


func test_a_replay_given_no_path_is_refused_and_never_starts_a_fight() -> void:
	for argument in ["--replay=", "--replay"]:
		var ran := _run_main(argument)
		assert_eq(ran[0], 2, "%s: %s" % [argument, ran[1]])
		assert_true(ran[1].contains("replay: "), "%s says why: %s" % [argument, ran[1]])


func test_a_replay_never_writes_the_players_settings_and_gives_them_back_at_its_end() -> void:
	var players := _players_file()
	var main := _main()
	main.lend_replay_defaults()
	main.start_replay(_idle_recording(12))
	await frames(3)
	assert_eq(Settings.get_value("sound/master"), 100, "the replay runs on the defaults")
	Settings.note_window_mode(Window.MODE_WINDOWED)  # F11
	Settings.set_value("sound/music", 50)  # a slider
	Settings.set_value("camera/dips", false)  # a switch
	await frames(20)
	assert_false(main._replayer.playing(), "the replay is over")
	assert_eq(FileAccess.get_file_as_string(PLAYER_FILE), players, "the player's file is as it was")
	assert_eq(Settings.get_value("sound/master"), 40, "the player's values are in force again")
	assert_eq(Settings.get_value("camera/shake"), 25)
	assert_eq(Settings.get_value("effects/slowdown_on"), false)
	assert_eq(Settings.get_value("sound/music"), 100, "a change made during the replay is dropped")
	assert_eq(Settings.get_value("camera/dips"), true)
	assert_eq(Settings.get_value("window/mode"), Settings.default_of("window/mode"))
	Settings.set_value("sound/ui", 30)
	assert_ne(FileAccess.get_file_as_string(PLAYER_FILE), players, "a change after it is written again")


func test_a_replay_cut_short_leaves_the_file_alone_and_gives_the_settings_back() -> void:
	var players := _players_file()
	var main := _main()
	main.lend_replay_defaults()
	main.start_replay(_idle_recording(600))
	await frames(5)
	Settings.set_value("sound/music", 50)
	assert_eq(Settings.get_value("sound/master"), 100, "lent")
	main.free()  # the game quit in the middle of it
	assert_eq(FileAccess.get_file_as_string(PLAYER_FILE), players, "the file is untouched")
	assert_eq(Settings.get_value("sound/master"), 40, "the player's values are back")
	assert_eq(Settings.get_value("effects/slowdown_on"), false)


func test_a_replay_that_diverges_gives_the_settings_back() -> void:
	var players := _players_file()
	var main := _main()
	main.lend_replay_defaults()
	var rec := _idle_recording(600)
	rec.hashes[3] = 12345  # not the fight's
	var said := []
	main.start_replay(rec)
	main._replayer.diverged.connect(func(at: int, _recorded: int, _got: int) -> void: said.append(at))
	await frames(10)
	assert_eq(said, [3], "it diverged")
	assert_eq(Settings.get_value("sound/master"), 40, "the player's values are back")
	assert_eq(FileAccess.get_file_as_string(PLAYER_FILE), players, "the file is untouched")
