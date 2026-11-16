extends TestCase
## The saved game's file (core/save/save_store.gd): one JSON file with a check and a version, a backup, a write that
## always leaves a usable file, a newer game's file moved aside, and the player's own folder never touched by a test.
## Every folder here is under user://save_test/ and removed after each test.

const ROOT := "user://save_test"

var _was_scripted := true
var _was_active := false
var _was_args: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_was_scripted = Settings.scripted_run
	_was_active = SelfTest.active
	_was_args = Settings.user_args
	_remove_tree(ROOT)


func after_each() -> void:
	Settings.scripted_run = _was_scripted
	SelfTest.active = _was_active
	Settings.user_args = _was_args
	_remove_tree(ROOT)


func _store(folder: String) -> SaveStore:
	return SaveStore.new(ROOT.path_join(folder))


func _sample() -> SaveData:
	var data := SaveData.new()
	data.rest_shrine = &"rose_b"
	data.petals = 120
	data.pile = {"x": 27.5, "y": 0.0, "z": -30.0, "amount": 80, "frames": 600}
	data.items = {&"rose_bell": 1}
	data.memory.set_flag(&"shortcut_open")
	data.memory.set_flag(&"collector_down")
	data.deaths = 3
	data.play_frames = 7200
	data.at = {"x": 12.25, "y": 0.0, "z": -3.5, "yaw": 123.456}
	data.bars = {"hp": 0.5, "stamina": 0.75, "posture": 1.0}
	data.fallen = [&"a", &"b"] as Array[StringName]
	return data


func _with_petals(n: int) -> SaveData:
	var data := SaveData.new()
	data.petals = n
	return data


func _path(store: SaveStore, file: String) -> String:
	return store.dir.path_join(file)


func _put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _put_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<absent>"


func _petals_in(path: String) -> int:
	var got: Variant = SaveStore.decode(_text(path))
	return -1 if got == null else (got as SaveData).petals


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func test_a_save_round_trips_every_field() -> void:
	var store := _store("round")
	assert_eq(store.write(_sample()), OK, "written")
	var back := store.read()
	assert_true(back != null, "read")
	if back == null:
		return
	assert_eq(back.to_dict(), _sample().to_dict(), "every field comes back the same")
	assert_eq(back.rest_shrine, &"rose_b", "shrine")
	assert_eq(back.petals, 120, "petals")
	assert_eq(back.pile, _sample().pile, "pile")
	assert_eq(back.items, {&"rose_bell": 1}, "items")
	assert_eq(back.memory.names(), [&"collector_down", &"shortcut_open"] as Array[StringName], "flags")
	assert_eq(back.deaths, 3, "deaths")
	assert_eq(back.play_frames, 7200, "play frames")
	assert_eq(store.last_source, SaveStore.Source.MAIN, "from the main file")
	assert_eq(store.last_problem, "", "with nothing wrong")


func test_where_he_stood_his_bars_and_the_fallen_round_trip_through_the_file() -> void:
	var store := _store("stood")
	store.write(_sample())
	var back := store.read()
	assert_true(back != null, "read")
	if back == null:
		return
	assert_eq(back.at, {"x": 12.25, "y": 0.0, "z": -3.5, "yaw": 123.456}, "the exact place, to the last digit")
	assert_eq(back.bars, {"hp": 0.5, "stamina": 0.75, "posture": 1.0}, "the bars")
	assert_eq(back.fallen, [&"a", &"b"] as Array[StringName], "the fallen")
	var bare := SaveData.new()
	store.write(bare)
	var empty_back := store.read()
	assert_eq(empty_back.at, {}, "no place stays no place")
	assert_eq(empty_back.bars, {}, "no bars stay no bars")
	assert_eq(empty_back.fallen.size(), 0, "nobody fallen stays nobody")


func test_the_text_is_the_same_every_time_and_says_its_version_and_check() -> void:
	var first := SaveStore.encode(_sample())
	assert_eq(SaveStore.encode(_sample()), first, "the same game is the same text")
	var parsed: Variant = JSON.parse_string(first)
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "it is a JSON object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	assert_eq(int(d.get("version", 0)), 1, "it says its version")
	var check := String(d.get("check", ""))
	assert_eq(check.length(), 64, "the check is 64 characters")
	assert_true(check.is_valid_hex_number(false), "of hex")
	var again := SaveStore.encode(_with_petals(5))
	assert_ne(JSON.parse_string(again)["check"], check, "another game, another check")


func test_decode_of_what_encode_wrote_gives_the_same_game() -> void:
	var got: Variant = SaveStore.decode(SaveStore.encode(_sample()))
	assert_true(got is SaveData, "a SaveData")
	if got is SaveData:
		assert_eq((got as SaveData).to_dict(), _sample().to_dict(), "the same fields")


func test_a_second_write_keeps_the_first_as_the_backup_and_leaves_no_temp_file() -> void:
	var store := _store("backup")
	store.write(_with_petals(1))
	assert_eq(_text(_path(store, SaveStore.MAIN)) == "<absent>", false, "the first write made the main file")
	assert_eq(_text(_path(store, SaveStore.BACKUP)), "<absent>", "and no backup yet")
	store.write(_with_petals(2))
	assert_eq(_petals_in(_path(store, SaveStore.MAIN)), 2, "main is the second")
	assert_eq(_petals_in(_path(store, SaveStore.BACKUP)), 1, "backup is the first")
	assert_false(FileAccess.file_exists(_path(store, SaveStore.TEMP)), "no temp file is left")
	assert_eq(DirAccess.get_files_at(store.dir).size(), 2, "two files in the folder, no more")


func test_a_cut_short_main_file_falls_back_to_the_backup() -> void:
	var store := _store("cut")
	store.write(_with_petals(1))
	store.write(_with_petals(2))
	var main_path := _path(store, SaveStore.MAIN)
	var bytes := FileAccess.get_file_as_bytes(main_path)
	_put_bytes(main_path, bytes.slice(0, bytes.size() / 2))
	var got := store.read()
	assert_true(got != null, "the backup is used")
	if got != null:
		assert_eq(got.petals, 1, "it is the older game")
	assert_eq(store.last_source, SaveStore.Source.BACKUP, "and says so")
	assert_ne(store.last_problem, "", "with one line on what was wrong")
	assert_false(store.last_problem.contains("\n"), "one line")


func test_an_edited_file_fails_its_check() -> void:
	var store := _store("edited")
	var data := _with_petals(120)
	store.write(data)
	var main_path := _path(store, SaveStore.MAIN)
	var text := _text(main_path)
	assert_true(text.contains("\"petals\":120"), "the text holds the number as compact JSON")
	_put(main_path, text.replace("\"petals\":120", "\"petals\":999"))
	assert_eq(store.read(), null, "an edit with no backup reads as nothing")
	assert_ne(store.last_problem, "", "and says why")
	assert_eq(store.last_source, SaveStore.Source.NONE, "from no source")
	store.write(_with_petals(7))
	store.write(_with_petals(8))
	var text2 := _text(main_path)
	_put(main_path, text2.replace("\"petals\":8", "\"petals\":9"))
	var got := store.read()
	assert_true(got != null, "with a backup the backup is read")
	if got != null:
		assert_eq(got.petals, 7, "the earlier game")
	assert_eq(store.last_source, SaveStore.Source.BACKUP, "from the backup")


func test_nothing_usable_reads_as_null_and_never_errors() -> void:
	var store := _store("none")
	assert_eq(store.read(), null, "no folder at all")
	assert_eq(store.last_problem, "", "that is not a problem: it is a first game")
	var main_path := _path(store, SaveStore.MAIN)
	_put(main_path, "")
	assert_eq(store.read(), null, "a file of 0 bytes")
	assert_ne(store.last_problem, "", "which is said")
	var junk := PackedByteArray()
	for i in 300:
		junk.append((i * 7919 + 13) % 256)
	_put_bytes(main_path, junk)
	assert_eq(store.read(), null, "random bytes")
	_put(main_path, "[1, 2, 3]")
	assert_eq(store.read(), null, "a JSON list")
	_put(main_path, "{\"version\": 1}")
	assert_eq(store.read(), null, "a dictionary with no check")
	_put(main_path, "{\"check\": 5, \"version\": 1}")
	assert_eq(store.read(), null, "a check that is not text")
	_put(main_path, "null")
	_put(_path(store, SaveStore.BACKUP), "{ not json")
	assert_eq(store.read(), null, "main and backup both bad")
	assert_eq(store.last_source, SaveStore.Source.NONE, "no source")
	assert_ne(store.last_problem, "", "and a line saying so")


func test_a_newer_games_file_is_not_read_and_not_lost() -> void:
	var store := _store("newer")
	var newer := SaveStore.seal({"petals": 5}, 99)
	var main_path := _path(store, SaveStore.MAIN)
	_put(main_path, newer)
	assert_eq(store.read(), null, "a newer game's file with no backup is not read")
	assert_true(store.last_problem.contains("99"), "the line names its version")
	var older := _store("newer")
	_put(_path(older, SaveStore.BACKUP), SaveStore.encode(_with_petals(4)))
	var got := store.read()
	assert_true(got != null, "a usable backup is used instead")
	if got != null:
		assert_eq(got.petals, 4, "the backup's game")
	assert_eq(store.last_source, SaveStore.Source.BACKUP, "and said to be")
	assert_eq(store.write(_with_petals(6)), OK, "then a write")
	assert_eq(_text(_path(store, "save.v99.json")), newer, "the newer game's file is kept, byte for byte, aside")
	assert_eq(_petals_in(main_path), 6, "main is the new game")
	assert_eq(_petals_in(_path(store, SaveStore.BACKUP)), 4, "the backup is still the backup it was, not the newer file")


func test_two_newer_files_are_both_kept() -> void:
	var store := _store("newer2")
	var main_path := _path(store, SaveStore.MAIN)
	var first := SaveStore.seal({"petals": 1}, 99)
	var second := SaveStore.seal({"petals": 2}, 99)
	_put(main_path, first)
	store.write(_with_petals(3))
	_put(main_path, second)
	store.write(_with_petals(4))
	var kept: Array[String] = []
	for file in DirAccess.get_files_at(store.dir):
		if file.begins_with("save.v99"):
			kept.append(_text(store.dir.path_join(file)))
	kept.sort()
	var want: Array[String] = [first, second]
	want.sort()
	assert_eq(kept, want, "both newer files are on disk, neither overwrote the other")


func test_a_newer_file_that_fails_its_check_is_still_a_newer_games() -> void:
	var store := _store("newer3")
	var main_path := _path(store, SaveStore.MAIN)
	var odd := "{\"check\": \"nothing we know\", \"version\": 7, \"x\": 1}"
	_put(main_path, odd)
	assert_eq(store.read(), null, "not read")
	store.write(_with_petals(1))
	assert_eq(_text(_path(store, "save.v7.json")), odd, "but kept: its check may be a newer kind")


func test_a_missing_or_mistyped_field_is_its_default_and_unknown_fields_are_ignored() -> void:
	var store := _store("fields")
	var fields := {
		"petals": "many", "deaths": -4, "mood": "grim", "flags": {"x": true, "y": 3},
		"pile": {"x": 1.0, "y": 0.0, "z": 2.0, "frames": 3},
		"at": {"x": 1.0}, "bars": "full", "fallen": ["b", "a", "b", 3, null],
	}
	_put(_path(store, SaveStore.MAIN), SaveStore.seal(fields))
	var got := store.read()
	assert_true(got != null, "a file with a right check and odd fields reads")
	if got == null:
		return
	assert_eq(got.petals, 0, "petals")
	assert_eq(got.deaths, 0, "deaths")
	assert_eq(got.memory.names(), [&"x"] as Array[StringName], "flags")
	assert_eq(got.pile, {}, "pile")
	assert_eq(got.at, {}, "at")
	assert_eq(got.bars, {}, "bars")
	assert_eq(got.fallen, [&"a", &"b"] as Array[StringName], "fallen")
	assert_eq(store.last_problem, "", "none of this is a problem with the file")


func test_an_unwritable_folder_is_an_error_and_leaves_the_old_files() -> void:
	var store := _store("good")
	store.write(_with_petals(1))
	store.write(_with_petals(2))
	var blocker := ROOT.path_join("blocker")
	_put(blocker, "i am a file")
	var blocked := SaveStore.new(blocker.path_join("inside"))
	var error := quietly(func() -> Variant: return blocked.write(_with_petals(3))) as Error
	assert_ne(error, OK, "a folder under a file cannot be written")
	assert_eq(_text(blocker), "i am a file", "and the file in the way is as it was")
	var stuck := _store("stuck")
	DirAccess.make_dir_recursive_absolute(_path(stuck, SaveStore.TEMP))
	var error_temp := quietly(func() -> Variant: return stuck.write(_with_petals(3))) as Error
	assert_ne(error_temp, OK, "a temp path that is a folder cannot be written either")
	assert_eq(_petals_in(_path(store, SaveStore.MAIN)), 2, "the good folder's main file is untouched by the others")
	assert_eq(_petals_in(_path(store, SaveStore.BACKUP)), 1, "and its backup")


func test_a_write_that_fails_leaves_the_files_it_found() -> void:
	var store := _store("keep")
	store.write(_with_petals(1))
	store.write(_with_petals(2))
	DirAccess.remove_absolute(_path(store, SaveStore.TEMP))
	DirAccess.make_dir_recursive_absolute(_path(store, SaveStore.TEMP))
	var error := quietly(func() -> Variant: return store.write(_with_petals(3))) as Error
	assert_ne(error, OK, "the write fails")
	assert_eq(_petals_in(_path(store, SaveStore.MAIN)), 2, "main is as it was")
	assert_eq(_petals_in(_path(store, SaveStore.BACKUP)), 1, "backup is as it was")


func test_the_players_folder_is_left_alone_by_a_test_run_and_other_folders_are_not() -> void:
	var player := SaveStore.new()
	assert_eq(player.dir, SaveStore.PLAYER_DIR, "the default is the player's folder")
	assert_false(player.may_use(), "a test run may not use it")
	assert_eq(player.write(_with_petals(1)), OK, "a write is a quiet no-op")
	assert_false(FileAccess.file_exists(SaveStore.PLAYER_DIR.path_join(SaveStore.MAIN)), "and writes nothing")
	assert_false(DirAccess.dir_exists_absolute(SaveStore.PLAYER_DIR), "and makes no folder")
	assert_eq(player.read(), null, "a read finds nothing")
	assert_true(_store("x").may_use(), "any other folder is fine")
	Settings.scripted_run = false
	SelfTest.active = false
	Settings.user_args = PackedStringArray()
	assert_true(player.may_use(), "a game the player started may use his own")
	SelfTest.active = true
	assert_false(player.may_use(), "not the self-test")
	SelfTest.active = false
	Settings.scripted_run = true
	assert_false(player.may_use(), "not a -s script")
	Settings.scripted_run = false
	Settings.user_args = PackedStringArray([Settings.NO_PLAYER_SETTINGS])
	assert_false(player.may_use(), "not a run that says it is not the player's game")


func test_non_ascii_text_round_trips_and_a_broken_multibyte_sequence_is_just_a_bad_file() -> void:
	var store := _store("utf8")
	var data := SaveData.new()
	data.memory.set_flag(&"café_荒")
	data.items = {&"über": 2}
	store.write(data)
	var back := store.read()
	assert_true(back != null, "a file with letters outside ASCII reads")
	if back != null:
		assert_eq(back.to_dict(), data.to_dict(), "and gives the same game")
	var main_path := _path(store, SaveStore.MAIN)
	var bytes := FileAccess.get_file_as_bytes(main_path)
	var cut := bytes.slice(0, bytes.find(0xC3) + 1)
	_put_bytes(main_path, cut)
	assert_eq(store.read(), null, "a file cut in the middle of a letter is bad, quietly")
	var overlong := PackedByteArray([0xC0, 0x80, 0xED, 0xA0, 0x80, 0xF5, 0x80, 0x80, 0x80, 0xE2, 0x82])
	_put_bytes(main_path, overlong)
	assert_eq(store.read(), null, "overlong, surrogate, too-high and truncated sequences are bad")
