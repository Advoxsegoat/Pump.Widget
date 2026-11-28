extends TestCase
## How the game gets into the stretch and what it does there: `--stretch` and `--stretch=new` (and `stretch_start`, the seam a test or
## the bot sets), F2 (which continues the saved game), a new game that reads and writes no file, leaving the stretch, and the Hud
## that follows no arena. The run itself is tests/world/test_stretch_run.gd's.

const MAIN := "res://main/main.tscn"
const DIR := "user://save_test/main"
const SETTINGS_PATH := "user://settings_test.cfg"


func before_each() -> void:
	Settings.path = SETTINGS_PATH
	_clean()


func after_each() -> void:
	InputFeed.release()
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	_clean()


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)


# A Main with its save folder and start set before it is ready.
func _main(start := "", args := PackedStringArray()) -> Main:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.save_dir = DIR
	main.stretch_start = start
	main.user_args = args
	return track(main) as Main


# Everything in the save folder, name to bytes.
func _bytes() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for name in DirAccess.get_files_at(DIR):
		out[name] = FileAccess.get_file_as_bytes(DIR.path_join(name))
	return out


func test_parse_stretch_reads_the_three_forms() -> void:
	assert_eq(Main.parse_stretch(PackedStringArray()), "", "no flag")
	assert_eq(Main.parse_stretch(PackedStringArray(["--stretch"])), "continue")
	assert_eq(Main.parse_stretch(PackedStringArray(["--stretch=new"])), "new")
	assert_eq(Main.parse_stretch(PackedStringArray(["--stretch=old"])), "", "anything else after the = is no flag")
	assert_eq(Main.parse_stretch(PackedStringArray(["--selftest", "--record=a.tres", "--stretch=new"])), "new", "among others")
	assert_eq(Main.parse_arguments(PackedStringArray(["--stretch=new"])), {"record": "", "replay": "", "replaying": false}, "parse_arguments is as it was")


func test_f2_continues_the_saved_game_and_new_reads_and_writes_nothing() -> void:
	var store := SaveStore.new(DIR)
	var saved := SaveData.new_game()
	saved.petals = 5
	saved.rest_shrine = &"rose_b"
	assert_eq(store.write(saved), OK)
	var main := _main()
	await frames(2)
	main.enter_stretch()
	await frames(2)
	assert_true(main.stretch != null, "a run began")
	assert_eq(main.stretch.data.petals, 5, "it is the saved game")
	assert_vec_near(main.player.global_position, Vector3(31.8, 0, -35.6), 0.01, "he stands at rose_b's respawn")
	main.enter_stretch(true)
	await frames(2)
	assert_eq(main.stretch.data.petals, 0, "a new game has no petals")
	assert_eq(main.stretch.data.rest_shrine, &"", "and has rested nowhere")
	assert_eq(main.stretch.rest_shrine().id, &"rose_a", "it starts at the first shrine")
	assert_vec_near(main.player.global_position, (main.stretch.def.shrines[0] as ShrineDef).respawn, 0.01, "where it stands: the first shrine's respawn")
	var before := _bytes()
	main.stretch.set_flag(&"x")
	main.stretch.rest(main.stretch.def.shrines[0])
	await frames(60)
	assert_eq(_bytes(), before, "the files are byte for byte as they were")


# A recording made with --stretch is of a new game: it never reads the player's save (it starts at the first shrine, not where the save
# has him) and never writes it, whatever the save holds (the same bytes before and after, the run's end included).
func test_a_recording_made_with_stretch_starts_a_new_game_and_leaves_the_save_alone() -> void:
	var store := SaveStore.new(DIR)
	var saved := SaveData.new_game()
	saved.petals = 5
	saved.rest_shrine = &"rose_b"
	saved.at = {x = -15.0, y = 0.0, z = 0.0, yaw = 217.0}
	assert_eq(store.write(saved), OK)
	assert_eq(store.write(saved), OK)  # the file and its backup
	var before := _bytes()
	var file := "user://main_stretch_record_test.tres"
	var main := _main("continue", PackedStringArray(["--stretch", "--record=" + file]))
	await frames(2)
	assert_eq(main.region.scene_file_path, "res://world/bilibara/bilibara.tscn", "the region is the stretch")
	var first := Registry.fetch(&"stretch", &"rose_a") as ShrineDef
	assert_vec_near(main.player.global_position, first.respawn, 0.01, "he starts at the new game's start, not at the saved place")
	assert_eq(main.stretch.data.petals, 0, "the run is a new game, not the saved one")
	assert_eq(main.stretch.store, null, "and has no store to write to")
	await frames(1900)  # past an autosave
	main.stretch.rest(first)
	main.stretch.set_flag(&"x")
	assert_eq(_bytes().hash(), before.hash(), "the save folder is byte for byte as it was")
	main.queue_free()
	await frames(3)
	assert_eq(_bytes().hash(), before.hash(), "and as it was after the game's end")
	DirAccess.remove_absolute(file)


func _press(main: Main, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	main._unhandled_input(key)


# The F2 key while a recording is being made: it is a key that changes the fight's place, so the recording says `debug_keys` (as F5 to
# F10 do), and it enters the stretch as a new game that reads and writes no file, whatever the save holds.
func test_f2_while_recording_marks_the_recording_and_enters_a_new_game_that_leaves_the_save_alone() -> void:
	var store := SaveStore.new(DIR)
	var saved := SaveData.new_game()
	saved.petals = 5
	saved.rest_shrine = &"rose_b"
	saved.at = {x = -15.0, y = 0.0, z = 0.0, yaw = 217.0}
	assert_eq(store.write(saved), OK)
	assert_eq(store.write(saved), OK)
	var before := _bytes()
	var file := "user://main_f2_record_test.tres"
	var main := _main("", PackedStringArray(["--record=" + file]))
	await frames(2)
	assert_true(main.arena() != null, "the recording began in the yard")
	_press(main, KEY_F2)
	await frames(2)
	assert_eq(main.region.scene_file_path, "res://world/bilibara/bilibara.tscn", "F2 went to the stretch")
	assert_true(main._recorder.recording().debug_keys, "the recording says debug_keys")
	var first := Registry.fetch(&"stretch", &"rose_a") as ShrineDef
	assert_vec_near(main.player.global_position, first.respawn, 0.01, "he stands at the new game's start")
	assert_eq(main.stretch.data.petals, 0, "the run is a new game, not the saved one")
	assert_eq(main.stretch.store, null, "with no store to write to")
	await frames(400)
	main.stretch.rest(first)
	main.stretch.set_flag(&"x")
	assert_eq(_bytes().hash(), before.hash(), "the save folder is byte for byte as it was")
	main.queue_free()
	await frames(3)
	assert_eq(_bytes().hash(), before.hash(), "and as it was after the game's end")
	DirAccess.remove_absolute(file)


# With no recorder F2 continues the saved game (a guard: it was so before).
func test_f2_with_no_recorder_continues_the_saved_game() -> void:
	var store := SaveStore.new(DIR)
	var saved := SaveData.new_game()
	saved.petals = 5
	saved.rest_shrine = &"rose_b"
	assert_eq(store.write(saved), OK)
	var main := _main()
	await frames(2)
	_press(main, KEY_F2)
	await frames(2)
	assert_eq(main.stretch.data.petals, 5, "it is the saved game")
	assert_true(main.stretch.store != null, "with its store")


func test_the_yards_arena_never_begins_when_the_game_starts_in_the_stretch() -> void:
	var main := _main("new")
	await frames(3)
	assert_eq(main.region.scene_file_path, "res://world/bilibara/bilibara.tscn", "the region is the stretch")
	assert_true(main.arena() == null, "no arena")
	var foes := main.find_children("*", "Actor", true, false).filter(func(a: Node) -> bool: return (a as Actor).def.team == ActorDef.Team.ENEMY)
	assert_eq(foes.size(), main.stretch.encounters.all_foes().size(), "the only foes are the stretch's own encounters (none of the yard's wave)")


func test_leaving_the_stretch_saves_what_changed() -> void:
	var main := _main()
	await frames(2)
	main.enter_stretch()
	await frames(2)
	main.stretch.data.petals = 7  # a change that no call of the run saved
	main.switch_region()
	await frames(2)
	assert_true(main.stretch == null or not is_instance_valid(main.stretch), "the run is gone with the region")
	var saved := SaveStore.new(DIR).read()
	assert_true(saved != null and saved.petals == 7, "the file has what changed")


func test_the_hud_follows_no_arena_and_has_a_stretch_hud_in_the_stretch_only() -> void:
	var main := _main()
	await frames(2)
	assert_true(main.hud.find_child("StretchHud", true, false) == null, "none in the yard")
	assert_true(main.hud.arena != null, "the yard's Hud follows its arena")
	main.enter_stretch(true)
	await frames(2)
	assert_true(main.hud.find_child("StretchHud", true, false) != null, "one in the stretch")
	assert_true(main.hud.arena == null, "and it follows no arena")
	main.switch_region()
	await frames(2)
	assert_true(main.hud.find_child("StretchHud", true, false) == null, "none again in the yard")
	assert_true(main.hud.arena != null, "which has its arena back")


func test_a_game_that_starts_in_the_yard_begins_its_fight_as_before() -> void:
	var main := _main()
	await frames(3)
	assert_true(main.arena() != null, "the yard's arena")
	assert_true(main.stretch == null, "no run")
