extends TestCase
## Main's --record=<path> and --replay=<path> user arguments: what they are read as, that a recording started in Main is saved
## and is a recording of the game's own player (not of a stand-in), and that a recording started in Main plays into its player.

const MAIN := "res://main/main.tscn"
const FILE := "user://main_recording.tres"


func after_each() -> void:
	InputFeed.release()
	DirAccess.remove_absolute(FILE)
	Game.reset()
	await frames(1)


func _main() -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	return track((load(MAIN) as PackedScene).instantiate()) as Main


func test_the_arguments_are_read() -> void:
	assert_eq(Main.parse_arguments(PackedStringArray(["--record=a.tres"])), {"record": "a.tres", "replay": ""})
	assert_eq(Main.parse_arguments(PackedStringArray(["--selftest", "--replay=b.tres"])), {"record": "", "replay": "b.tres"})
	assert_eq(Main.parse_arguments(PackedStringArray()), {"record": "", "replay": ""})


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
	assert_eq(Main.replay_refusal(FILE), "", "a good file is not refused")


func test_the_lines_a_replay_ends_with() -> void:
	assert_eq(Main.diverged_line(120, 5, 6), "replay: diverged at frame 120 (recorded 5, got 6)")
	assert_eq(Main.finished_line(77, true), "replay: finished, state hash 77, as recorded")
	assert_eq(Main.EXIT_REFUSED, 2)
	assert_eq(Main.EXIT_DIVERGED, 3)


func test_main_given_a_file_it_cannot_use_says_so_and_quits_with_2_without_a_fight() -> void:
	var garbage := FileAccess.open(ProjectSettings.globalize_path("user://garbage_recording.tres"), FileAccess.WRITE)
	garbage.store_string("not a recording")
	garbage.close()
	var argv := PackedStringArray(["-k", "5", "60", OS.get_executable_path(), "--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--fixed-fps", "60", "--", "--replay=" + ProjectSettings.globalize_path("user://garbage_recording.tres")])
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	DirAccess.remove_absolute("user://garbage_recording.tres")
	assert_eq(code, 2, str(output))
	assert_true(str(output[0]).contains("replay: "), "one line saying why: %s" % str(output))
