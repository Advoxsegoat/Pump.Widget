extends TestCase
## A session in the stretch is recorded and replayed as the yard's fight is: the recorder and the replayer take the run's own hash
## (StretchRun.state_hash) where the yard gives theirs, so a recording made in the stretch replays "as recorded"; and a recording
## and a replay are of a new game, which never reads or writes the player's save.

const MAIN := "res://main/main.tscn"
const DIR := "user://save_test/replay"
const FILE := "user://stretch_recording.tres"
const SETTINGS_PATH := "user://settings_test.cfg"

var _was_scripted := false


func before_each() -> void:
	Settings.path = SETTINGS_PATH
	_was_scripted = Settings.scripted_run
	_clean()


func after_each() -> void:
	InputFeed.release()
	Settings.scripted_run = _was_scripted
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	DirAccess.remove_absolute(FILE)
	_clean()
	await frames(1)


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)


func _main() -> Main:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.save_dir = DIR
	main.stretch_start = "new"
	return track(main) as Main


func _bytes() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for name in DirAccess.get_files_at(DIR):
		out[name] = FileAccess.get_file_as_bytes(DIR.path_join(name))
	return out


# The hands: stand, walk toward the first shrine's plinth, press interact (a rest, if he is in reach), walk on.
func _hands() -> Array:
	return [{"frames": 10}, {"frames": 20, "move": Vector2(0, -1)}, {"frames": 1, "press": [&"interact"]}, {"frames": 20},
			{"frames": 60, "move": Vector2(1, 0.4)}, {"frames": 1, "press": [&"interact"]}, {"frames": 60, "move": Vector2(0, 1)}, {"frames": 30}]


func test_a_stretch_session_replays_as_recorded_and_leaves_the_players_save_alone() -> void:
	var store := SaveStore.new(DIR)
	var saved := SaveData.new_game()
	saved.petals = 9
	saved.rest_shrine = &"rose_b"
	assert_eq(store.write(saved), OK)
	assert_eq(store.write(saved), OK)  # a second write: the folder holds the file and its backup
	var before := _bytes()
	var recorded := _main()
	recorded.start_recording(FILE)
	var hands := track(ScriptedHands.new(_hands()))
	await frames(260)
	hands.queue_free()
	assert_eq(recorded.save_recording(), OK)
	var rested := recorded.stretch.flag(&"shrine:rose_a") or recorded.stretch.flag(&"shrine:rose_b")
	assert_true(rested, "(the session rested at a shrine, so the hash holds a deed)")
	var rec := ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	assert_true(rec != null, "the recording was saved")
	recorded.queue_free()  # (a game that ends saves its recording again, there no longer is a hash to give it: this one is kept)
	await frames(3)
	InputFeed.release()
	ResourceSaver.save(rec, FILE)
	assert_eq(rec.region, "res://world/bilibara/bilibara.tscn", "it is of the stretch")
	assert_eq(Main.replay_refusal(FILE), "", "and a replay of it is not refused")
	var played := _main()
	var result := {done = false, diverged = false}
	played.start_replay(rec)
	played._replayer.finished.connect(func() -> void: result["done"] = true)
	played._replayer.diverged.connect(func(_at: int, _recorded: int, _got: int) -> void: result["diverged"] = true)
	while not result["done"] and not result["diverged"]:
		await frames(1)
	assert_false(result["diverged"], "the replay did not diverge")
	assert_true(result["done"], "it finished")
	assert_true(Main.end_is_compared(rec), "with a hash at its end to agree with: 'as recorded'")
	assert_eq(_bytes(), before, "the player's save is byte for byte as it was")


func test_a_recording_made_in_the_stretch_is_refused_without_its_hash() -> void:
	var main := _main()
	main.start_recording(FILE)
	await frames(20)
	assert_eq(main.save_recording(), OK)
	var rec := ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	assert_true(rec.hashes.has(rec.frames.size()), "the stretch recording has its hash at the end")
	rec.hashes.clear()
	ResourceSaver.save(rec, FILE)
	assert_true(Main.replay_refusal(FILE).contains("hash"), "emptied of its hashes it is refused: %s" % Main.replay_refusal(FILE))
