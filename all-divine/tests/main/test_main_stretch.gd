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
func _main(start := "") -> Main:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.save_dir = DIR
	main.stretch_start = start
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


func test_the_yards_arena_never_begins_when_the_game_starts_in_the_stretch() -> void:
	var main := _main("new")
	await frames(3)
	assert_eq(main.region.scene_file_path, "res://world/bilibara/bilibara.tscn", "the region is the stretch")
	assert_true(main.arena() == null, "no arena")
	var foes := main.find_children("*", "Actor", true, false).filter(func(a: Node) -> bool: return (a as Actor).def.team == ActorDef.Team.ENEMY)
	assert_eq(foes.size(), 0, "no foe anywhere")


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
