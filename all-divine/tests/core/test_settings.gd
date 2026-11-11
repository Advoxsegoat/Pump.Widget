extends TestCase
## The settings store (core/settings.gd): its table of keys, what each setting changes, and the file it is kept in.
## Each test makes its own Settings, with a file of its own (never the player's), and removes the file after.

const SETTINGS := "res://core/settings.gd"
const TUNING := "res://data/tuning/readability.tres"
const PATH := "user://settings_test.cfg"
const LOOK_KEYS: Array[String] = ["outline", "dof", "bloom", "fog", "grade", "vignette"]
const SOUND_KEYS: Array[String] = ["master", "music", "sfx", "voice", "ui"]

var _made: Node = null
var _was_active := false
var _buses := []


func before_each() -> void:
	_was_active = SelfTest.active
	_buses = []
	for i in AudioServer.bus_count:
		_buses.append([AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)])
	_remove_files()


# Puts everything a Settings changes back as it was, and removes the files.
func after_each() -> void:
	SelfTest.active = _was_active
	if _made != null:
		SelfTest.active = true  # writes no file while it puts the shared tuning back
		_made.reset_all()
		SelfTest.active = _was_active
		_made = null
	for i in _buses.size():
		AudioServer.set_bus_volume_db(i, _buses[i][0])
		AudioServer.set_bus_mute(i, _buses[i][1])
	_remove_files()


# The tuning the effects share, through a variable (a property read straight off a const resource is folded at compile
# time and would not see a change).
func _effects() -> ReadabilityTuning:
	var tuning: ReadabilityTuning = ActorFx.TUNING
	return tuning


func _remove_files() -> void:
	for file in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	if DirAccess.dir_exists_absolute(PATH + ".tmp"):
		DirAccess.remove_absolute(PATH + ".tmp")


# A Settings in the tree (so its _ready ran) that keeps its file at `where`.
func _make(where := PATH) -> Node:
	var settings := (load(SETTINGS) as GDScript).new() as Node
	settings.path = where
	track(settings)
	return settings


func _write(text: String, where := PATH) -> void:
	var file := FileAccess.open(where, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# The shared tuning resource, which every test leaves as the file has it.
func _file_tuning() -> ReadabilityTuning:
	return load(TUNING) as ReadabilityTuning


# A value of `key` that is not its default.
func _other(settings: Node, key: String) -> Variant:
	var value: Variant = settings.default_of(key)
	match typeof(value):
		TYPE_BOOL:
			return not value
		TYPE_STRING:
			return "windowed" if value == "fullscreen" else "fullscreen"
	return 50 if key == "camera/shake" or key.begins_with("look/") else (60 if key.begins_with("sound/") else 3)


func test_defaults_match_the_tuning_resource_and_the_table() -> void:
	_made = _make()
	var tuning := _file_tuning()
	for name in ReadabilityTuning.SWITCHES:
		assert_eq(_made.default_of("effects/%s" % name), tuning.get(name), "effects/%s is the resource's value" % name)
		assert_eq(_made.get_value("effects/%s" % name), tuning.get(name), "and is what it holds")
	assert_eq(_made.get_value("camera/shake"), 100)
	assert_eq(_made.get_value("camera/dips"), true)
	for key in LOOK_KEYS:
		assert_eq(_made.get_value("look/" + key), 100, "look/" + key)
	for key in SOUND_KEYS:
		assert_eq(_made.get_value("sound/" + key), 100, "sound/" + key)
	assert_eq(_made.get_value("window/mode"), "fullscreen")
	assert_eq(_made.get_value("window/scale"), 2)
	assert_eq(_made.get_value("no/such_key"), null)
	assert_eq(_made.default_of("no/such_key"), null)


func test_every_switch_in_the_tuning_is_listed_and_has_a_key() -> void:
	_made = _make()
	var keys: Array = _made.keys()
	for property in (load(TUNING) as ReadabilityTuning).get_property_list():
		var name := str(property.name)
		if name.ends_with("_on"):
			assert_true(ReadabilityTuning.SWITCHES.has(StringName(name)), "%s is in ReadabilityTuning.SWITCHES" % name)
			assert_true(keys.has("effects/" + name), "and has the key effects/%s" % name)


func test_keys_are_the_tables_keys_in_order() -> void:
	_made = _make()
	var expected: Array[String] = []
	for name in ReadabilityTuning.SWITCHES:
		expected.append("effects/%s" % name)
	expected.append_array(["camera/shake", "camera/dips"])
	for key in LOOK_KEYS:
		expected.append("look/" + key)
	for key in SOUND_KEYS:
		expected.append("sound/" + key)
	expected.append_array(["window/mode", "window/scale"])
	assert_eq(_made.keys(), expected)
	assert_eq(_made.keys().size(), 24)
	assert_eq(ReadabilityTuning.SWITCHES.size(), 9)


func test_a_switch_takes_effect_at_once_on_the_shared_tuning() -> void:
	_made = _make()
	var heard: Array[String] = []
	_made.changed.connect(func(key: String) -> void: heard.append(key))
	var chain := ChainSlow.new(DodgeChain.new(load("res://data/tuning/chain_open_hand.tres") as ChainTuning))
	assert_true(_made.set_value("effects/afterimage_on", false))
	assert_false(_effects().afterimage_on, "the effects' tuning")
	assert_false(chain.tuning.afterimage_on, "and the chain slow's is the same one")
	assert_eq(heard, ["effects/afterimage_on"] as Array[String], "changed said once")
	assert_true(_made.set_value("effects/afterimage_on", true))
	assert_true(_effects().afterimage_on, "on again")
	assert_true(chain.tuning.afterimage_on)


func test_a_value_of_the_wrong_type_or_an_unknown_key_is_refused() -> void:
	_made = _make()
	var heard: Array[String] = []
	_made.changed.connect(func(key: String) -> void: heard.append(key))
	assert_true(_made.set_value("camera/shake", 50))
	var before := FileAccess.get_file_as_string(PATH)
	assert_false(_made.set_value("camera/shake", "loud"), "a word for a number")
	assert_false(_made.set_value("camera/shake", 50.5), "a fraction for a number")
	assert_false(_made.set_value("camera/shake", true), "a bool for a number")
	assert_false(_made.set_value("effects/afterimage_on", 1), "a number for a switch")
	assert_false(_made.set_value("window/mode", "sideways"), "a word that is no choice")
	assert_false(_made.set_value("window/mode", 3), "a number for a choice")
	assert_false(_made.set_value("no/such_key", true), "a key there is none of")
	assert_eq(_made.get_value("camera/shake"), 50, "unchanged")
	assert_eq(_made.get_value("effects/afterimage_on"), true)
	assert_eq(_made.get_value("window/mode"), "fullscreen")
	assert_eq(FileAccess.get_file_as_string(PATH), before, "the file is as it was")
	assert_eq(heard, ["camera/shake"] as Array[String], "nothing said for the refused")


func test_numbers_are_clamped_and_snapped_to_their_step() -> void:
	_made = _make()
	for pair in [["camera/shake", 130, 100], ["camera/shake", -5, 0], ["camera/shake", 60, 50], ["camera/shake", 63, 75],
			["look/bloom", 13, 25], ["sound/music", 64, 60], ["sound/voice", 65, 70], ["window/scale", 9, 6], ["window/scale", 0, 1]]:
		assert_true(_made.set_value(pair[0], pair[1]), "%s to %d" % [pair[0], pair[1]])
		assert_eq(_made.get_value(pair[0]), pair[2], "%s %d is held as %d" % [pair[0], pair[1], pair[2]])


func test_shake_scales_the_camera_now_and_a_shake_in_progress() -> void:
	Settings.path = PATH
	var rig := track(CameraRig.new()) as CameraRig
	rig.set_physics_process(false)
	rig.shake(1.0)
	var full := rig.shake_offset()
	assert_true(full.length() > 0.0, "a shake at full")
	assert_true(Settings.set_value("camera/shake", 50))
	assert_near(rig.shake_offset().x, full.x * 0.5, 1e-6, "half, on the same noise")
	assert_near(rig.shake_offset().y, full.y * 0.5, 1e-6)
	assert_true(Settings.set_value("camera/shake", 0))
	assert_eq(rig.shake_offset(), Vector2.ZERO, "none at 0")
	assert_eq(rig.trauma, 1.0, "the trauma is not touched")
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	assert_eq(rig.shake_offset(), full, "100 again")


func test_sound_levels_set_the_buses() -> void:
	_made = _make()
	var buses := {"master": "Master", "music": "Music", "sfx": "SFX", "voice": "Voice", "ui": "UI"}
	for key in buses:
		var bus := AudioServer.get_bus_index(buses[key])
		assert_true(bus >= 0, "a bus named %s" % buses[key])
		assert_true(_made.set_value("sound/" + key, 50))
		assert_near(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5), 1e-4, "%s at 50" % key)
		assert_false(AudioServer.is_bus_mute(bus), "and not muted")
		assert_true(_made.set_value("sound/" + key, 0))
		assert_true(AudioServer.is_bus_mute(bus), "%s at 0 is muted" % key)
		assert_true(_made.set_value("sound/" + key, 100))
		assert_near(AudioServer.get_bus_volume_db(bus), 0.0, 1e-6, "%s at 100" % key)
		assert_false(AudioServer.is_bus_mute(bus))


func test_the_look_scales_each_strength_and_nothing_else() -> void:
	_made = _make()
	var base := load("res://data/render/default_settings.tres") as RenderSettings
	var bloom := base.bloom_strength
	assert_true(_made.set_value("look/bloom", 50))
	var look: RenderSettings = _made.look_of(base)
	assert_near(look.bloom_strength, bloom * 0.5, 1e-6, "bloom is half")
	for strength in [&"outline", &"dof_strength", &"fog_strength", &"grade_strength", &"vignette_strength", &"focus_band", &"bloom_threshold"]:
		assert_eq(look.get(strength), base.get(strength), "%s is the base's" % strength)
	assert_eq(base.bloom_strength, bloom, "the base is untouched")
	assert_true(look != base, "a copy")
	assert_true(_made.set_value("look/outline", 0))
	assert_eq(_made.look_of(base).outline, 0.0)


func test_the_window_target_is_fullscreen_or_a_whole_multiple_of_the_picture() -> void:
	_made = _make()
	_made.set_value("window/mode", "windowed")
	_made.set_value("window/scale", 3)
	assert_eq(_made.window_target(Vector2i(2560, 1440)), {"mode": Window.MODE_WINDOWED, "size": Vector2i(1920, 1080)})
	_made.set_value("window/mode", "fullscreen")
	assert_eq(_made.window_target(Vector2i(2560, 1440)), {"mode": Window.MODE_FULLSCREEN, "size": Vector2i.ZERO})


func test_a_scale_that_does_not_fit_the_screen_is_cut_to_the_largest_that_does() -> void:
	_made = _make()
	_made.set_value("window/scale", 6)
	assert_eq(_made.windowed_size(Vector2i(1920, 1080)), Vector2i(1920, 1080), "6 on 1080p is 3")
	assert_eq(_made.get_value("window/scale"), 6, "the stored value stays")
	assert_eq(_made.windowed_size(Vector2i(500, 300)), Vector2i(640, 360), "a screen under the picture: 1")
	assert_eq(_made.windowed_size(Vector2i(3840, 2160)), Vector2i(3840, 2160), "it fits at 4K")


func test_fitting_scales() -> void:
	_made = _make()
	assert_eq(_made.fitting_scales(Vector2i(1920, 1080)), [1, 2, 3] as Array[int])
	assert_eq(_made.fitting_scales(Vector2i(3840, 2160)), [1, 2, 3, 4, 5, 6] as Array[int])
	assert_eq(_made.fitting_scales(Vector2i(500, 300)), [1] as Array[int])


func test_the_file_round_trips_every_key() -> void:
	_made = _make()
	for key in _made.keys():
		assert_true(_made.set_value(key, _other(_made, key)), "set " + key)
	var again := _make()
	assert_true(again.load_file())
	for key in _made.keys():
		assert_eq(again.get_value(key), _made.get_value(key), key)
		assert_ne(again.get_value(key), _made.default_of(key), "%s is not its default" % key)
	var config := ConfigFile.new()
	assert_eq(config.load(PATH), OK)
	assert_eq(config.get_sections(), PackedStringArray(["meta", "effects", "camera", "look", "sound", "window"]))
	assert_eq(config.get_value("meta", "version"), 1)
	assert_eq(config.get_value("camera", "shake"), 50)
	assert_eq(config.get_value("window", "mode"), "windowed")
	assert_true(config.has_section_key("effects", "parry_aura_on"))
	assert_true(config.has_section_key("look", "vignette"))
	assert_true(config.has_section_key("sound", "ui"))
	again.free()


func test_a_missing_file_gives_the_defaults_without_an_error_line() -> void:
	_made = _make()
	assert_false(_made.load_file(), "no file: false")
	for key in _made.keys():
		assert_eq(_made.get_value(key), _made.default_of(key), key)
	assert_false(FileAccess.file_exists(PATH), "and none is made by loading")


func test_a_damaged_file_gives_the_defaults_without_an_error_line() -> void:
	var noise := PackedByteArray()
	for i in 4096:
		noise.append((i * 131 + 7) % 256)
	var damaged := {
		"empty": "",
		"binary": noise.get_string_from_ascii(),
		"unterminated": "[effects",
		"no section": "shake=oops",
	}
	for what in damaged:
		_write(damaged[what])
		var settings := _make()
		var read: Variant = quietly(func() -> bool: return settings.load_file())
		assert_true(read is bool, "%s: load_file returned" % what)
		for key in settings.keys():
			assert_eq(settings.get_value(key), settings.default_of(key), "%s: %s" % [what, key])
		settings.free()
	# A bad value is its own default and the keys beside it are kept.
	var bad := {
		"shake=\"loud\"": ["camera", "shake=\"loud\""],
		"shake=9999": ["camera", "shake=9999"],
		"afterimage_on=3": ["effects", "afterimage_on=3"],
		"mode=\"sideways\"": ["window", "mode=\"sideways\""],
		"scale=1.5": ["window", "scale=1.5"],
	}
	for what in bad:
		var text := "[sound]\nmusic=40\n[%s]\n%s\n[look]\nbloom=25\n" % [bad[what][0], bad[what][1]]
		_write(text)
		var settings := _make()
		assert_true(quietly(func() -> bool: return settings.load_file()), what + ": read")
		assert_eq(settings.get_value("sound/music"), 40, what + ": a good key before is kept")
		assert_eq(settings.get_value("look/bloom"), 25, what + ": and one after")
		for key in ["camera/shake", "effects/afterimage_on", "window/mode", "window/scale"]:
			assert_eq(settings.get_value(key), settings.default_of(key), "%s: %s" % [what, key])
		settings.free()
	# A file of a kind that is no ConfigFile at all: a directory where it should be.
	DirAccess.remove_absolute(PATH)
	DirAccess.make_dir_absolute(PATH)
	var settings := _make()
	assert_false(quietly(func() -> bool: return settings.load_file()), "a directory: false")
	settings.free()
	DirAccess.remove_absolute(PATH)


func test_a_file_of_a_newer_version_is_read_as_far_as_it_is_understood() -> void:
	_write("[meta]\nversion=99\n[future]\nthing=\"new\"\n[camera]\nshake=50\ncolour=1\n[sound]\nmusic=30\n")
	_made = _make()
	assert_eq(_made.get_value("camera/shake"), 50)
	assert_eq(_made.get_value("sound/music"), 30)
	assert_eq(_made.get_value("camera/dips"), true)
	assert_eq(_made.keys().size(), 24, "no key was added by the unknown ones")


func test_a_failed_save_returns_an_error_and_leaves_no_half_file() -> void:
	var missing := "user://no_such_folder_for_settings/settings.cfg"
	_made = _make(missing)
	var result: Variant = quietly(func() -> int: return _made.save_file())
	assert_ne(result, OK, "a path under a missing folder")
	assert_true(quietly(func() -> bool: return _made.set_value("camera/shake", 25)), "setting still works")
	assert_eq(_made.get_value("camera/shake"), 25, "and the value is applied")
	assert_false(FileAccess.file_exists(missing))
	assert_false(FileAccess.file_exists(missing + ".tmp"))
	# An old good file, and a temporary file that cannot be written (a folder in its place).
	var settings := _make()
	settings.set_value("camera/shake", 75)
	var old := FileAccess.get_file_as_string(PATH)
	DirAccess.make_dir_absolute(PATH + ".tmp")
	assert_true(quietly(func() -> bool: return settings.set_value("camera/shake", 25)))
	assert_ne(quietly(func() -> int: return settings.save_file()), OK)
	assert_eq(FileAccess.get_file_as_string(PATH), old, "the old file is whole")
	settings.free()


func test_the_selftest_reads_and_writes_no_file() -> void:
	_write("[camera]\nshake=50\n")
	SelfTest.active = true
	var settings := _make()
	assert_eq(settings.get_value("camera/shake"), 100, "the file is not read")
	var before := FileAccess.get_file_as_string(PATH)
	assert_true(settings.set_value("camera/shake", 25))
	assert_eq(FileAccess.get_file_as_string(PATH), before, "and not written")
	DirAccess.remove_absolute(PATH)
	assert_true(settings.set_value("camera/shake", 75))
	assert_false(FileAccess.file_exists(PATH), "no file is made by set_value")
	settings.reset_all()
	settings.free()


func test_reset_all_restores_every_key_and_the_buses() -> void:
	_made = _make()
	for key in _made.keys():
		_made.set_value(key, _other(_made, key))
	var heard: Array[String] = []
	_made.changed.connect(func(key: String) -> void: heard.append(key))
	_made.reset_all()
	for key in _made.keys():
		assert_eq(_made.get_value(key), _made.default_of(key), key)
	assert_eq(heard.size(), 24, "changed for each that moved")
	assert_true(_effects().afterimage_on, "the tuning is back")
	var bus := AudioServer.get_bus_index("Music")
	assert_near(AudioServer.get_bus_volume_db(bus), 0.0, 1e-6)
	assert_false(AudioServer.is_bus_mute(bus))
	heard.clear()
	_made.reset_all()
	assert_eq(heard.size(), 0, "nothing moved, nothing said")
	var config := ConfigFile.new()
	assert_eq(config.load(PATH), OK, "and the file says the defaults")
	assert_eq(config.get_value("camera", "shake"), 100)


func test_the_suite_does_not_read_the_players_file() -> void:
	# The player's file stands in as a file of the test's own: a Settings whose player file is `path` is under the
	# test runner (as it would be under the self-test), so it must not read it, nor write it.
	_write("[camera]\nshake=25\n[effects]\nafterimage_on=false\n")
	var before := FileAccess.get_file_as_string(PATH)
	var settings := (load(SETTINGS) as GDScript).new() as Node
	settings.path = PATH
	settings.player_path = PATH
	track(settings)
	assert_eq(settings.get_value("camera/shake"), 100, "the file's shake is not read")
	assert_eq(settings.get_value("effects/afterimage_on"), true, "nor its switch")
	assert_true(_effects().afterimage_on, "and the shared tuning is untouched")
	assert_false(settings.load_file(), "load_file reads nothing of it")
	settings.set_value("camera/shake", 50)
	assert_eq(FileAccess.get_file_as_string(PATH), before, "and nothing is written over it")
	settings.reset_all()


func test_load_file_applies_what_it_reads_and_says_changed() -> void:
	_made = _make()
	var heard: Array[String] = []
	_made.changed.connect(func(key: String) -> void: heard.append(key))
	_write("[effects]\nafterimage_on=false\nslowdown_on=true\n[sound]\nmusic=40\n[camera]\nshake=25\n")
	assert_true(_made.load_file())
	assert_false(_effects().afterimage_on, "the shared tuning has changed")
	var bus := AudioServer.get_bus_index("Music")
	assert_near(AudioServer.get_bus_volume_db(bus), linear_to_db(0.4), 1e-4, "the Music bus has changed")
	assert_near(_made.shake_scale(), 0.25, 1e-6, "and the shake")
	heard.sort()
	assert_eq(heard, ["camera/shake", "effects/afterimage_on", "sound/music"] as Array[String], "changed for exactly those three")
	heard.clear()
	assert_true(_made.load_file())
	assert_eq(heard.size(), 0, "read again, nothing moved, nothing said")


func test_one_bad_line_costs_one_line() -> void:
	var bad_lines := {
		"an unquoted word": "shake=oops",
		"a stray word": "stray",
		"a line with no =": "shake 50",
		"an unterminated string": "shake=\"loud",
		"a bracket": "shake=[1, 2",
	}
	for what in bad_lines:
		_write("[effects]\nafterimage_on=false\n[camera]\ndips=false\n%s\nshake=50\n[sound]\nmusic=40\n" % bad_lines[what])
		var settings := _make()
		assert_eq(settings.get_value("effects/afterimage_on"), false, what + ": the section before is read")
		assert_eq(settings.get_value("camera/dips"), false, what + ": and the key before it")
		assert_eq(settings.get_value("sound/music"), 40, what + ": and the section after it")
		var shake: Variant = settings.get_value("camera/shake")
		if what == "an unquoted word" or what == "an unterminated string" or what == "a line with no =":
			assert_eq(shake, 50, what + ": the key after the bad line is read too")
		settings.free()
	# The bad line is the key's own: that key is its default, its neighbours are read.
	_write("[camera]\ndips=false\nshake=oops\n[look]\nbloom=25\n")
	var own := _make()
	assert_eq(own.get_value("camera/shake"), 100, "shake=oops is shake's default")
	assert_eq(own.get_value("camera/dips"), false)
	assert_eq(own.get_value("look/bloom"), 25)
	own.free()
	# A bad section header drops the keys under it; the sections after it are read.
	_write("[sound]\nmusic=40\n[camera\nshake=25\ndips=false\n[look]\nbloom=50\n")
	var header := _make()
	assert_eq(header.get_value("sound/music"), 40, "before the bad header")
	assert_eq(header.get_value("camera/shake"), 100, "under it: dropped")
	assert_eq(header.get_value("camera/dips"), true, "under it: dropped")
	assert_eq(header.get_value("look/bloom"), 50, "after it")
	header.free()
	# Noise around good lines, a comment, a note after a value, CRLF.
	_write("junk \u0001\u0002\r\n; a comment\r\n[sound]\r\nmusic=40 ; quieter\r\n#another\r\nvoice=50\r\n")
	var mixed := _make()
	assert_eq(mixed.get_value("sound/music"), 40, "a note after the value")
	assert_eq(mixed.get_value("sound/voice"), 50, "CRLF")
	mixed.free()


func test_a_value_out_of_range_in_the_file_is_the_keys_default_not_its_clamp() -> void:
	_write("[window]\nscale=9\n[camera]\nshake=-5\n")
	var settings := _make()
	assert_eq(settings.get_value("window/scale"), 2, "9 is not 6: it is the default")
	assert_eq(settings.get_value("camera/shake"), 100, "-5 is not 0")
	settings.free()


func test_on_the_web_the_page_owns_the_window() -> void:
	_made = _make()
	var loose := Window.new()  # outside the tree, as a window the game does not own
	loose.mode = Window.MODE_MAXIMIZED
	loose.size = Vector2i(777, 555)
	loose.position = Vector2i(31, 17)
	# Off the web a windowed setting does size it (the test has teeth).
	_made.on_web = false
	_made.set_value("window/mode", "windowed")
	_made.set_value("window/scale", 1)
	_made.apply_window(loose)
	assert_eq([loose.mode, loose.size], [Window.MODE_WINDOWED, Vector2i(640, 360)], "off the web it applies")
	_made.on_web = true
	for mode in ["fullscreen", "windowed"]:
		for scale in [1, 2, 3, 6]:
			_made.set_value("window/mode", mode)
			_made.set_value("window/scale", scale)
			loose.mode = Window.MODE_MAXIMIZED
			loose.size = Vector2i(777, 555)
			loose.position = Vector2i(31, 17)
			_made.apply_window(loose)
			assert_eq([loose.mode, loose.size, loose.position], [Window.MODE_MAXIMIZED, Vector2i(777, 555), Vector2i(31, 17)],
				"on the web, %s at %d: untouched" % [mode, scale])
	loose.free()


func test_a_whole_float_is_a_number_but_a_fraction_is_not() -> void:
	_made = _make()
	assert_true(_made.set_value("camera/shake", 50.0), "a slider hands floats")
	assert_eq(_made.get_value("camera/shake"), 50)
	assert_eq(typeof(_made.get_value("camera/shake")), TYPE_INT, "stored as an int")
	assert_false(_made.set_value("camera/shake", 75.5), "a fraction is refused")
	assert_eq(_made.get_value("camera/shake"), 50)
	assert_false(_made.set_value("camera/shake", INF), "and infinity")
	assert_false(_made.set_value("camera/shake", NAN), "and NaN")


func test_an_extreme_number_clamps_without_overflow() -> void:
	_made = _make()
	assert_true(_made.set_value("window/scale", 9223372036854775807))
	assert_eq(_made.get_value("window/scale"), 6)
	assert_true(_made.set_value("window/scale", -9223372036854775807))
	assert_eq(_made.get_value("window/scale"), 1)
	assert_true(_made.set_value("camera/shake", 9223372036854775807))
	assert_eq(_made.get_value("camera/shake"), 100)


func test_note_window_mode_stores_both_fullscreens_as_fullscreen() -> void:
	_made = _make()
	_made.note_window_mode(Window.MODE_WINDOWED)
	assert_eq(_made.get_value("window/mode"), "windowed")
	_made.note_window_mode(Window.MODE_EXCLUSIVE_FULLSCREEN)
	assert_eq(_made.get_value("window/mode"), "fullscreen", "exclusive fullscreen")
	_made.note_window_mode(Window.MODE_MAXIMIZED)
	assert_eq(_made.get_value("window/mode"), "windowed", "any other mode")
	_made.note_window_mode(Window.MODE_FULLSCREEN)
	assert_eq(_made.get_value("window/mode"), "fullscreen")
