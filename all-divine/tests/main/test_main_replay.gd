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
