extends TestCase
## The settings screen: the pages under Settings in the pause menu (ui/settings_pages.gd), each row bound to one key of the
## Settings autoload and nothing else, and what the settings do while the game is paused behind the menu: a switch turned off in
## the pause is obeyed when the game goes on, a slow-down or an afterimage already under way runs out, the shake follows its
## slider at once.
##
## Every test that changes a setting puts it back (after_each), and the settings go to a file of the test's own.

const SETTINGS_PATH := "user://settings_test.cfg"
const COPY_PATH := "user://settings_test_copy.cfg"
const C := MenuNav.Cmd
const TUNING := "res://data/tuning/readability.tres"
const SCREEN := Vector2i(1920, 1080)

## The settings pages in the order the screens are walked, and each row's key (a row not named here changes no setting).
const KEYS := {
	&"effects": {
		"Parry aura": "effects/parry_aura_on", "Perilous rim": "effects/perilous_rim_on",
		"Heavy-attack wave": "effects/heavy_wave_on", "Perilous wave": "effects/perilous_wave_on",
		"Perilous icon": "effects/perilous_icon_on", "Parry burst": "effects/parry_burst_on",
		"Dodge afterimage": "effects/afterimage_on", "Slow-down on a perfect dodge": "effects/slowdown_on",
		"Chain rim": "effects/chain_rim_on",
	},
	&"camera": {"Camera shake": "camera/shake", "Camera dips": "camera/dips"},
	&"look": {
		"Outline": "look/outline", "Depth of field": "look/dof", "Bloom": "look/bloom", "Fog": "look/fog",
		"Colour grade": "look/grade", "Vignette": "look/vignette",
	},
	&"sound": {
		"Master": "sound/master", "Music": "sound/music", "Effects": "sound/sfx", "Voice": "sound/voice", "Interface": "sound/ui",
	},
	&"window": {"Mode": "window/mode", "Size": "window/scale"},
}
const SWITCH_PAGES: Array[StringName] = [&"settings", &"effects", &"camera", &"look", &"sound", &"window", &"restore"]

var _tuning_was := {}
var _buses := []


func before_each() -> void:
	Settings.path = SETTINGS_PATH
	Settings.on_web = false
	Game.reset()
	Melee.slow(0, 1.0)
	_tuning_was = {}
	for switch in ReadabilityTuning.SWITCHES:
		_tuning_was[switch] = _shared().get(switch)
	_buses = []
	for i in AudioServer.bus_count:
		_buses.append([AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)])


func after_each() -> void:
	Game.reset()
	Melee.slow(0, 1.0)
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	Settings.on_web = OS.has_feature("web")
	for switch in _tuning_was:
		_shared().set(switch, _tuning_was[switch])
	for i in _buses.size():
		AudioServer.set_bus_volume_db(i, _buses[i][0])
		AudioServer.set_bus_mute(i, _buses[i][1])
	for file in [SETTINGS_PATH, SETTINGS_PATH + ".tmp", COPY_PATH]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


# --- helpers ---

# The tuning every effect shares, through a variable (a property read off a const resource is folded at compile time).
func _shared() -> ReadabilityTuning:
	var tuning: ReadabilityTuning = ActorFx.TUNING
	return tuning


# A menu, open, that knows a 1920x1080 screen.
func _menu() -> Menu:
	var menu := track(Menu.new()) as Menu
	menu.screen_size = func() -> Vector2i: return SCREEN
	menu.open()
	return menu


func _labels(menu: Menu) -> Array:
	return menu.rows().map(func(r: Dictionary) -> String: return r.label)


# The index of the row called `label` on the page shown.
func _at(menu: Menu, label: String) -> int:
	for r in menu.rows():
		if r.label == label:
			return r.index
	fail("no row '%s' on %s: %s" % [label, menu.page, _labels(menu)])
	return -1


# Moves the selection to the row called `label` with Up and Down presses.
func _select(menu: Menu, label: String) -> void:
	var target := _at(menu, label)
	for i in menu.rows().size() + 1:
		if menu.index == target:
			return
		menu.press(C.DOWN)
	fail("could not select '%s'" % label)


func _value(menu: Menu, label: String) -> String:
	for r in menu.rows():
		if r.label == label:
			return r.value
	return "<no row %s>" % label


func _row(menu: Menu, label: String) -> Dictionary:
	for r in menu.rows():
		if r.label == label:
			return r
	return {}


func _snapshot() -> Dictionary:
	var all := {}
	for key in Settings.keys():
		all[key] = Settings.get_value(key)
	return all


# The keys whose value is not what `before` says.
func _changed_since(before: Dictionary) -> Array:
	var moved := []
	for key in before:
		if Settings.get_value(key) != before[key]:
			moved.append(key)
	return moved


func _text_width(text: String) -> int:
	return ceili(ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Menu.FONT_SIZE).x)


func _key_event(code: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


# The game paused, as the pause menu has it.
func _pause() -> void:
	if Game.state != Game.State.PLAY:
		Game.change(Game.State.PLAY)
	Game.change(Game.State.PAUSE)


# --- the pages ---

func test_the_settings_page_lists_its_rows_in_order() -> void:
	var menu := _menu()
	assert_eq(_labels(menu), ["Resume", "Settings", "Quit"], "the root page has Settings between Resume and Quit")
	menu.show_page(&"settings")
	assert_eq(menu.heading(), "Settings")
	assert_eq(_labels(menu), ["Effects", "Camera", "Screen look", "Sound", "Window", "Restore defaults", "Back"])


func test_choosing_settings_opens_it_and_back_returns_to_the_row_left() -> void:
	var menu := _menu()
	_select(menu, "Settings")
	menu.press(C.CHOOSE)
	assert_eq([menu.page, menu.heading()], [&"settings", "Settings"])
	for id in [&"effects", &"camera", &"look", &"sound", &"window"]:
		_select(menu, {&"effects": "Effects", &"camera": "Camera", &"look": "Screen look", &"sound": "Sound", &"window": "Window"}[id])
		var left := menu.index
		menu.press(C.CHOOSE)
		assert_eq(menu.page, id, "%s opens" % id)
		menu.press(C.BACK)
		assert_eq([menu.page, menu.index], [&"settings", left], "%s: Back returns to the page it came from, on the row it left" % id)
		_select(menu, "Window" if id == &"window" else {&"effects": "Effects", &"camera": "Camera", &"look": "Screen look", &"sound": "Sound"}[id])
		menu.press(C.CHOOSE)
		_select(menu, "Back")
		menu.press(C.CHOOSE)
		assert_eq([menu.page, menu.index], [&"settings", left], "%s: the Back row does the same" % id)
	_select(menu, "Back")
	menu.press(C.CHOOSE)
	assert_eq([menu.page, menu.index], [&"root", 1], "Settings returns to the root page, on its own row")
	menu.show_page(&"effects")
	menu.press(C.BACK)
	assert_eq(menu.page, &"settings", "a page shown directly still goes back to its parent")


func test_the_effects_page_has_a_toggle_for_every_switch_with_its_label() -> void:
	var menu := _menu()
	menu.show_page(&"effects")
	assert_eq(menu.heading(), "Effects")
	assert_eq(_labels(menu), ["Parry aura", "Perilous rim", "Heavy-attack wave", "Perilous wave", "Perilous icon", "Parry burst",
			"Dodge afterimage", "Slow-down on a perfect dodge", "Chain rim", "Back"])
	assert_eq(menu.rows().size(), ReadabilityTuning.SWITCHES.size() + 1, "one row per switch, and Back")
	for r in menu.rows().slice(0, 9):
		assert_eq(r.kind, MenuRow.Kind.TOGGLE, "%s is a toggle" % r.label)
		assert_eq(r.value, "On", "%s is on as the game comes" % r.label)


func test_a_switch_without_a_label_shows_a_made_up_one() -> void:
	assert_eq(SettingsPages.label_for(&"ghost_halo_on"), "Ghost halo")
	assert_eq(SettingsPages.label_for(&"parry_aura_on"), "Parry aura", "a switch with a label shows it")
	var menu := _menu()
	var switches: Array[StringName] = [&"parry_aura_on", &"ghost_halo_on"]
	menu.show_page(&"ghost", SettingsPages.effects_page(menu, switches))
	assert_eq(_labels(menu), ["Parry aura", "Ghost halo", "Back"])
	menu.press(C.DOWN)
	menu.press(C.CHOOSE)
	assert_eq(_value(menu, "Ghost halo"), "Off", "a switch no Settings key backs is still drawn from what it holds, without an error")


func test_choosing_a_toggle_flips_the_setting_and_the_file() -> void:
	var menu := _menu()
	menu.show_page(&"effects")
	menu.press(C.CHOOSE)
	assert_eq(Settings.get_value("effects/parry_aura_on"), false, "Parry aura is off in Settings")
	assert_eq(_value(menu, "Parry aura"), "Off")
	assert_true(FileAccess.get_file_as_string(SETTINGS_PATH).contains("parry_aura_on=false"), "and in the saved file")
	_shared().parry_aura_on = true
	var fresh := (load("res://core/settings.gd") as GDScript).new() as Node
	fresh.path = SETTINGS_PATH
	track(fresh)
	assert_eq(fresh.get_value("effects/parry_aura_on"), false, "a new Settings reading the file says false")
	menu.press(C.CHOOSE)
	assert_eq(Settings.get_value("effects/parry_aura_on"), true, "chosen again it is on")
	menu.press(C.LEFT)
	assert_eq(Settings.get_value("effects/parry_aura_on"), false, "Left sets it off")
	menu.press(C.LEFT)
	assert_eq(Settings.get_value("effects/parry_aura_on"), false, "and again leaves it off")
	menu.press(C.RIGHT)
	assert_eq(Settings.get_value("effects/parry_aura_on"), true, "Right sets it on")
	menu.press(C.RIGHT)
	assert_eq(Settings.get_value("effects/parry_aura_on"), true, "and again leaves it on")


func test_a_slider_moves_one_step_and_stops_at_its_ends() -> void:
	var menu := _menu()
	menu.show_page(&"camera")
	assert_eq([_value(menu, "Camera shake"), menu.rows()[0].kind], ["100%", MenuRow.Kind.SLIDER])
	menu.press(C.RIGHT)
	assert_eq(Settings.get_value("camera/shake"), 100, "at 100 Right stays at 100")
	var seen := []
	for i in 6:
		menu.press(C.LEFT)
		seen.append(_value(menu, "Camera shake"))
	assert_eq(seen, ["75%", "50%", "25%", "0%", "0%", "0%"], "Left moves one step (25) and stops at 0")
	menu.press(C.RIGHT)
	assert_eq(_value(menu, "Camera shake"), "25%", "Right moves back one step")
	menu.show_page(&"sound")
	assert_eq(menu.rows().size(), 6)
	menu.press(C.LEFT)
	assert_eq(_value(menu, "Master"), "90%", "the sound steps are 10")
	menu.press(C.CHOOSE)
	assert_eq(_value(menu, "Master"), "90%", "choosing a slider moves nothing")
	menu.show_page(&"look")
	menu.press(C.LEFT)
	assert_eq(_value(menu, "Outline"), "75%", "the look steps are 25")


func test_each_row_changes_exactly_its_key() -> void:
	for id in SWITCH_PAGES:
		var count := MenuPages.build(id, _menu()).rows.size()
		assert_true(count > 1, "%s has rows to try" % id)
		for i in count:
			var label := ""
			var moved_by_row := {}
			for cmd in [C.LEFT, C.RIGHT, C.CHOOSE]:
				Settings.reset_all()
				if id == &"window":
					Settings.set_value("window/mode", "windowed")  # so that Size is a row that can be changed
				var menu := _menu()
				menu.show_page(id)
				var shown: Dictionary = menu.rows()[i]
				label = shown.label
				if shown.kind == MenuRow.Kind.TEXT:
					break
				_select(menu, label)
				var before := _snapshot()
				menu.press(cmd)
				var moved := _changed_since(before)
				var own := []
				if KEYS.get(id, {}).has(label):
					own.append(KEYS[id][label])
				assert_true(moved.all(func(k: String) -> bool: return own.has(k)), "%s/%s with %s changed %s, expected only %s" % [id, label, cmd, moved, own])
				for k in moved:
					moved_by_row[k] = true
			if KEYS.get(id, {}).has(label):
				assert_true(moved_by_row.has(KEYS[id][label]), "%s/%s changes its key by Left, Right or Choose" % [id, label])
	Settings.reset_all()


func test_the_pages_show_what_is_stored_when_reopened() -> void:
	Settings.set_value("effects/chain_rim_on", false)
	Settings.set_value("effects/parry_burst_on", false)
	Settings.set_value("camera/shake", 50)
	Settings.set_value("camera/dips", false)
	Settings.set_value("look/fog", 25)
	Settings.set_value("look/bloom", 0)
	Settings.set_value("sound/music", 30)
	Settings.set_value("sound/ui", 80)
	Settings.set_value("window/mode", "windowed")
	Settings.set_value("window/scale", 3)
	var expected := {
		&"effects": {"Chain rim": "Off", "Parry burst": "Off", "Parry aura": "On"},
		&"camera": {"Camera shake": "50%", "Camera dips": "Off"},
		&"look": {"Fog": "25%", "Bloom": "0%", "Outline": "100%"},
		&"sound": {"Music": "30%", "Interface": "80%", "Master": "100%"},
		&"window": {"Mode": "Window", "Size": "x3 1920x1080"},
	}
	for round in 2:
		if round == 1:
			# A restart: everything forgotten, then read back from the file the settings left.
			DirAccess.copy_absolute(SETTINGS_PATH, COPY_PATH)
			Settings.reset_all()
			assert_eq(Settings.get_value("camera/shake"), 100, "forgotten")
			Settings.path = COPY_PATH
			assert_true(Settings.load_file(), "the file is read")
		for id in expected:
			var menu := _menu()
			menu.show_page(id)
			for label: String in expected[id]:
				assert_eq(_value(menu, label), expected[id][label], "round %d, %s/%s" % [round, id, label])


func test_restore_defaults_asks_first_and_changes_nothing_until_restore() -> void:
	Settings.set_value("camera/shake", 25)
	Settings.set_value("effects/slowdown_on", false)
	Settings.set_value("sound/master", 40)
	var menu := _menu()
	menu.show_page(&"settings")
	_select(menu, "Restore defaults")
	var here := menu.index
	var stored := _snapshot()
	menu.press(C.CHOOSE)
	assert_eq([menu.page, menu.heading()], [&"restore", "Restore defaults"], "it opens a page of its own")
	assert_eq(_labels(menu), ["Every setting goes back to how the game came.", "Restore", "Back"])
	assert_eq(menu.rows()[0].kind, MenuRow.Kind.TEXT)
	assert_eq(menu.rows()[menu.index].label, "Back", "it starts on Back")
	assert_eq(_changed_since(stored), [], "nothing has changed yet")
	menu.press(C.CHOOSE)
	assert_eq([menu.page, menu.index], [&"settings", here], "Back returns to Settings on Restore defaults")
	assert_eq(_changed_since(stored), [], "and changed nothing")
	menu.press(C.CHOOSE)
	menu.press(C.BACK)
	assert_eq([menu.page, menu.index], [&"settings", here], "the menu's Back is Back too")
	assert_eq(_changed_since(stored), [])
	menu.press(C.CHOOSE)
	menu.press(C.UP)
	assert_eq(menu.rows()[menu.index].label, "Restore")
	menu.press(C.CHOOSE)
	assert_eq([menu.page, menu.index], [&"settings", here], "Restore returns to Settings with the selection on Restore defaults")
	for key in Settings.keys():
		assert_eq(Settings.get_value(key), Settings.default_of(key), "%s is its default" % key)
	assert_true(FileAccess.get_file_as_string(SETTINGS_PATH).contains("shake=100"), "and the file says so")


func test_the_window_page_and_the_quit_row_are_left_out_on_the_web() -> void:
	Settings.on_web = true
	var menu := track(Menu.new()) as Menu
	menu.open()
	assert_eq(_labels(menu), ["Resume", "Settings"], "no Quit on the web")
	menu.show_page(&"settings")
	assert_eq(_labels(menu), ["Effects", "Camera", "Screen look", "Sound", "Restore defaults", "Back"], "and no Window")
	Settings.on_web = false
	var home := _menu()
	home.show_page(&"settings")
	assert_true(_labels(home).has("Window"), "off the web it is there")


# --- the sound rows ---

func test_sound_rows_play_their_sample_on_their_bus_and_while_paused() -> void:
	var menu := _menu()
	_pause()
	assert_true(get_tree().paused)
	menu.show_page(&"sound")
	var player := menu.sample_player
	assert_true(player != null and player.can_process(), "the menu's own player runs while the tree is paused")
	var cases := [
		["Master", &"impact_palm", &"Master"], ["Effects", &"impact_palm", &"SFX"], ["Interface", &"stamina_refused", &"UI"],
	]
	for case: Array in cases:
		menu._process(1.0)  # a second of real time since the last
		_select(menu, case[0])
		var before := menu.sample_count
		menu.press(C.LEFT)
		assert_eq(menu.sample_count, before + 1, "%s: a step plays its sample" % case[0])
		assert_true(player.playing, "%s: it is playing, with the tree paused" % case[0])
		assert_eq(player.bus, case[2], "%s: on %s" % [case[0], case[2]])
		var cue := Registry.fetch(&"sounds", case[1]) as SoundCue
		assert_true(cue.streams.has(player.stream), "%s: the stream is a file of %s" % [case[0], case[1]])
		player.stop()
	for label in ["Music", "Voice"]:
		menu._process(1.0)
		_select(menu, label)
		var before := menu.sample_count
		menu.press(C.LEFT)
		assert_eq(menu.sample_count, before, "%s plays nothing" % label)
		assert_false(player.playing)
	assert_eq(Settings.get_value("sound/music"), 90, "though it steps")


func test_a_sound_sample_is_at_most_one_in_a_015_seconds_counted_while_paused() -> void:
	var menu := _menu()
	_pause()
	menu.show_page(&"sound")
	_select(menu, "Effects")
	menu._process(1.0)
	var start := menu.sample_count
	menu.press(C.LEFT)
	menu.press(C.LEFT)
	menu.press(C.LEFT)
	assert_eq(menu.sample_count - start, 1, "three steps at once: one sample")
	menu._process(0.1)
	menu.press(C.LEFT)
	assert_eq(menu.sample_count - start, 1, "0.1 s later: still one")
	menu._process(0.06)
	menu.press(C.LEFT)
	assert_eq(menu.sample_count - start, 2, "0.16 s after the first: a second")
	assert_eq(Settings.get_value("sound/sfx"), 50, "every step moved the level all the same")


func test_sound_at_zero_is_silence_and_master_at_zero_silences_every_sample() -> void:
	var menu := _menu()
	menu.show_page(&"sound")
	_select(menu, "Effects")
	Settings.set_value("sound/sfx", 10)
	menu._process(1.0)
	var before := menu.sample_count
	menu.press(C.LEFT)
	assert_eq(Settings.get_value("sound/sfx"), 0)
	assert_eq(menu.sample_count, before, "a step down to 0 plays nothing")
	menu._process(1.0)
	menu.press(C.RIGHT)
	assert_eq(menu.sample_count, before + 1, "a step up from 0 is heard (at 10)")
	assert_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(0.1), 0.01, "at the level just set")
	Settings.set_value("sound/master", 0)
	for label in ["Effects", "Interface"]:
		menu._process(1.0)
		_select(menu, label)
		var count := menu.sample_count
		menu.press(C.RIGHT)
		menu.press(C.LEFT)
		assert_eq(menu.sample_count, count, "%s: with Master at 0 nothing plays" % label)
	menu._process(1.0)
	_select(menu, "Master")
	var count := menu.sample_count
	menu.press(C.RIGHT)
	assert_eq(menu.sample_count, count + 1, "Master itself, stepped up from 0, is heard at 10")
	menu._process(1.0)
	menu.press(C.LEFT)
	assert_eq([Settings.get_value("sound/master"), menu.sample_count], [0, count + 1], "and stepped down to 0 plays nothing")


func test_a_held_direction_runs_a_slider_to_its_end_and_stops_with_a_sample_every_015() -> void:
	var menu := _menu()
	_pause()
	menu.show_page(&"sound")
	_select(menu, "Effects")
	menu._process(1.0)
	var start := menu.sample_count
	menu.handle(_key_event(KEY_LEFT))
	var seconds := 0.0
	for i in 30:
		menu._process(0.1)
		seconds += 0.1
	menu.handle(_key_event(KEY_LEFT, false))
	assert_eq(Settings.get_value("sound/sfx"), 0, "held Left runs the slider to 0")
	assert_eq(_value(menu, "Effects"), "0%", "and stops there")
	var plays := menu.sample_count - start
	assert_true(plays >= 3 and plays <= int(seconds / 0.15) + 1, "a sample at most every 0.15 s: %d in %.1f s" % [plays, seconds])
	menu.show_page(&"camera")
	menu.handle(_key_event(KEY_RIGHT))
	for i in 12:
		menu._process(0.1)
	menu.handle(_key_event(KEY_RIGHT, false))
	assert_eq(Settings.get_value("camera/shake"), 100, "held Right runs the shake to 100 and stops")


# --- the window page ---

func test_the_window_page_disables_size_in_fullscreen_and_lists_only_fitting_scales() -> void:
	var menu := _menu()
	menu.show_page(&"window")
	assert_eq(menu.heading(), "Window")
	assert_eq(_labels(menu), ["Mode", "Size", "Back"])
	assert_eq([_value(menu, "Mode"), _value(menu, "Size")], ["Fullscreen", "x2 1280x720"], "fullscreen as the game comes")
	var size := _row(menu, "Size")
	assert_false(size.enabled, "Size is off while Mode is Fullscreen")
	menu.press(C.DOWN)
	assert_eq(menu.index, 2, "the selection passes over it")
	menu.press(C.UP)
	assert_eq(menu.index, 0, "both ways")
	menu.press(C.RIGHT)
	assert_eq([_value(menu, "Mode"), Settings.get_value("window/mode")], ["Window", "windowed"], "Right moves Mode on")
	assert_true(_row(menu, "Size").enabled, "Mode Window enables Size")
	menu.press(C.CHOOSE)
	assert_eq(Settings.get_value("window/mode"), "fullscreen", "Choose cycles it")
	menu.press(C.LEFT)
	assert_eq(Settings.get_value("window/mode"), "windowed", "Left cycles it too")
	menu.press(C.DOWN)
	assert_eq(_labels(menu)[menu.index], "Size")
	var seen := [_value(menu, "Size")]
	for i in 3:
		menu.press(C.CHOOSE)
		seen.append(_value(menu, "Size"))
	assert_eq(seen, ["x2 1280x720", "x3 1920x1080", "x1 640x360", "x2 1280x720"], "x1, x2 and x3 and no more on a 1920x1080 screen, cycling")
	menu.press(C.RIGHT)
	assert_eq([Settings.get_value("window/scale"), _value(menu, "Size")], [3, "x3 1920x1080"])
	assert_eq(Settings.window_target(SCREEN), {"mode": Window.MODE_WINDOWED, "size": Vector2i(1920, 1080)}, "x3 stored gives the 1920x1080 window")
	menu.press(C.LEFT)
	menu.press(C.LEFT)
	assert_eq(Settings.get_value("window/scale"), 1, "Left goes down")
	menu.press(C.LEFT)
	assert_eq(Settings.get_value("window/scale"), 3, "and wraps")


func test_the_window_rows_apply_at_once_to_the_menus_window() -> void:
	var window := Window.new()
	var menu := _menu()
	menu.window = window
	menu.show_page(&"window")
	menu.press(C.RIGHT)
	assert_eq(window.mode, Window.MODE_WINDOWED, "Mode Window puts the window in a window at once")
	menu.press(C.LEFT)
	assert_eq(window.mode, Window.MODE_FULLSCREEN, "and Fullscreen back")
	menu.window = null
	menu.press(C.RIGHT)
	assert_eq(Settings.get_value("window/mode"), "windowed", "with no window the setting is still kept")
	window.free()


func test_the_size_choice_never_offers_less_than_x1_and_follows_the_screen() -> void:
	var menu := _menu()
	Settings.set_value("window/mode", "windowed")
	menu.screen_size = func() -> Vector2i: return Vector2i(500, 300)
	menu.show_page(&"window")
	menu.press(C.DOWN)
	var seen := []
	for i in 3:
		seen.append(_value(menu, "Size"))
		menu.press(C.CHOOSE)
	assert_eq(seen, ["x1 640x360", "x1 640x360", "x1 640x360"], "a screen smaller than the picture still gives x1, and only x1")
	menu.screen_size = func() -> Vector2i: return Vector2i(3840, 2160)
	menu.show_page(&"window")
	menu.press(C.DOWN)
	seen = []
	for i in 6:
		menu.press(C.CHOOSE)
		seen.append(_value(menu, "Size"))
	assert_eq(seen, ["x2 1280x720", "x3 1920x1080", "x4 2560x1440", "x5 3200x1800", "x6 3840x2160", "x1 640x360"], "a 4K screen: x1 to x6")


func test_the_selected_row_is_never_the_one_that_gets_disabled() -> void:
	var menu := _menu()
	Settings.set_value("window/mode", "windowed")
	menu.show_page(&"window")
	menu.press(C.DOWN)
	assert_eq(_labels(menu)[menu.index], "Size", "on Size")
	Settings.set_value("window/mode", "fullscreen")  # F11 does this, while the menu is up
	menu.refresh()
	assert_false(_row(menu, "Size").enabled)
	assert_eq(_labels(menu)[menu.index], "Mode", "the selection has moved to Mode, so that a chevron is always shown")
	assert_true(_row(menu, "Mode").selected)
	assert_false(_row(menu, "Size").selected)
	menu.press(C.RIGHT)
	assert_eq(Settings.get_value("window/mode"), "windowed")
	# Turning Mode to Fullscreen from Mode leaves the selection on Mode.
	menu.press(C.RIGHT)
	assert_eq([Settings.get_value("window/mode"), _labels(menu)[menu.index]], ["fullscreen", "Mode"])
	assert_true(_row(menu, "Mode").selected, "the chevron is on Mode")


# --- widths ---

# Every row of every settings page, at every value it can take: the value is drawn clear of its label and inside the panel, and
# the panel does not change while the page is open.
func test_no_value_of_any_row_is_drawn_over_its_label_or_outside_the_panel() -> void:
	for id in SWITCH_PAGES:
		Settings.reset_all()
		Settings.set_value("window/mode", "windowed")
		var menu := _menu()
		menu.screen_size = func() -> Vector2i: return Vector2i(3840, 2160)
		menu.show_page(id)
		var panel := menu.panel()
		assert_true(menu.rows().size() > 1, "%s has rows to check" % id)
		assert_true(panel.size.x <= 224, "%s: the panel is at most 224 (%d)" % [id, panel.size.x])
		for i in menu.rows().size():
			if menu.rows()[i].kind == MenuRow.Kind.TEXT:
				continue
			Settings.set_value("window/mode", "windowed")
			menu.refresh()
			_select(menu, menu.rows()[i].label)
			for cmd in [C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT, C.RIGHT,
					C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.LEFT, C.CHOOSE, C.CHOOSE, C.CHOOSE]:
				if menu.rows()[i].kind == MenuRow.Kind.ACTION:
					break
				menu.press(cmd)
				assert_eq(menu.panel(), panel, "%s: the panel did not change" % id)
				_check_row_fits(menu, id, menu.rows()[i])
		# And every row as shown at rest.
		for r in menu.rows():
			_check_row_fits(menu, id, r)


func _check_row_fits(menu: Menu, id: StringName, r: Dictionary) -> void:
	var panel := menu.panel()
	var inner := panel.end.x - Menu.PADDING
	var label_end: int = r.text_at.x + _text_width(r.label)
	assert_true(label_end <= inner, "%s/%s: the label ends inside the panel (%d of %d)" % [id, r.label, label_end, inner])
	if (r.value as String).is_empty():
		return
	var value_end: int = r.value_at.x + _text_width(r.value)
	assert_true(value_end <= inner, "%s/%s=%s: the value ends inside the panel (%d of %d)" % [id, r.label, r.value, value_end, inner])
	var starts: int = r.value_at.x
	if (r.bar as Rect2i).size != Vector2i.ZERO:
		starts = mini(starts, (r.bar as Rect2i).position.x)
		assert_true((r.bar as Rect2i).end.x <= r.value_at.x, "%s/%s: the bar is left of the percent" % [id, r.label])
	assert_true(label_end + Menu.VALUE_GAP <= starts + 0, "%s/%s=%s: a gap of %d or more between the label (ends %d) and the value (starts %d)" % [id, r.label, r.value, Menu.VALUE_GAP, label_end, starts])


func test_the_longest_label_and_its_value_fit_with_a_gap() -> void:
	var menu := _menu()
	menu.show_page(&"effects")
	var longest := _row(menu, "Slow-down on a perfect dodge")
	var label_end: int = longest.text_at.x + _text_width(longest.label)
	assert_true(longest.value_at.x - label_end >= Menu.VALUE_GAP, "a gap of at least %d px (%d)" % [Menu.VALUE_GAP, longest.value_at.x - label_end])
	assert_true(menu.panel().size.x <= 224)


func test_sliders_bars_and_percents_line_up_in_a_column() -> void:
	var menu := _menu()
	menu.show_page(&"sound")
	var bars := []
	var ends := []
	for step in 4:
		for r in menu.rows():
			if r.kind == MenuRow.Kind.SLIDER:
				bars.append((r.bar as Rect2i).position.x)
				ends.append(r.value_at.x + _text_width(r.value))
		menu.press(C.LEFT)
		menu.press(C.DOWN)
	assert_eq(bars.filter(func(x: int) -> bool: return x != bars[0]), [], "every bar starts at the same x")
	assert_eq(ends.filter(func(x: int) -> bool: return x != ends[0]), [], "every percent ends at the same x")
	var r := _row(menu, "Master")
	assert_eq((r.bar as Rect2i).size, Vector2i(42, 5), "a 40 px bar and its 1 px outline")
	assert_eq(r.fill, 40 * int(Settings.get_value("sound/master")) / 100, "the fill is the percent of 40 px")


# --- what the settings do in the fight, with the game paused behind the menu ---

func _pause_menu_on(page: StringName) -> Menu:
	_pause()
	var menu := _menu()
	menu.show_page(page)
	return menu


# A slow-down of 12 frames, begun, four frames in; the game is paused for a few frames, the switch is turned off in the menu (if `off`)
# and the game goes on. Returns [whether it was still slowed at the resume, the frames it then took to run out].
func _slow_run(off: bool) -> Array:
	var run := Duel.make(self, [{"frames": 600}], [{"frames": 600}], 3.0)
	Melee.slow(12, 0.4)
	await frames(4)
	_pause()
	if off:
		var menu := _menu()
		menu.show_page(&"effects")
		_select(menu, "Slow-down on a perfect dodge")
		menu.press(C.CHOOSE)
		assert_eq(Settings.get_value("effects/slowdown_on"), false)
	await frames(5)
	Game.change(Game.State.PLAY)
	var still := Melee.slowed()
	var left := 0
	while Melee.slowed() and left < 40:
		await frames(1)
		left += 1
	(run["arena"] as Node).queue_free()
	await frames(2)
	return [still, left]


func test_a_slow_down_in_progress_runs_out_when_its_switch_is_turned_off() -> void:
	var control := await _slow_run(false)
	Melee.slow(0, 1.0)
	Game.reset()
	var turned_off := await _slow_run(true)
	assert_true(control[0] and control[1] > 3, "the control: slowed at the resume, and %d frames to go" % control[1])
	assert_true(turned_off[0], "resumed, it is still slowed: the switch does not cut it short")
	assert_eq(turned_off[1], control[1], "and it runs out after the frames it had left, as the control's")
	Settings.reset_all()
	var run := Duel.make(self, [{"frames": 60}], [], 3.0)
	var a: Actor = run["a"]
	Settings.set_value("effects/slowdown_on", false)
	a.chain.link(true, a.buffer_frame)
	assert_false(Melee.slowed(), "the next chain's perfect dodge starts none")


func test_an_afterimage_in_flight_fades_out_and_the_next_is_not_made() -> void:
	var run := Duel.make(self, [{"frames": 600}], [], 6.0)
	var a: Actor = run["a"]
	var image := Afterimage.spawn(a.rig, Color(1, 1, 1, 0.6), 12, {}, a)
	await frames(4)
	var menu := _pause_menu_on(&"effects")
	var left := image.left
	_select(menu, "Dodge afterimage")
	menu.press(C.CHOOSE)
	await frames(3)
	assert_eq(image.left, left, "paused, it hangs as it was")
	Game.change(Game.State.PLAY)
	var frames_left := 0
	while is_instance_valid(image) and not image.is_queued_for_deletion() and frames_left < 40:
		await frames(1)
		frames_left += 1
	assert_true(frames_left >= left and frames_left <= left + 2, "it fades out over the %d frames it had left (%d)" % [left, frames_left])
	var result := HitResult.new()
	result.outcome = HitResult.Outcome.EVADED
	result.perfect = true
	a.chain.link(true, a.buffer_frame)
	a.got_hit.emit(result, Blows.event(run["b"] if run.has("b") else a, a, Blows.profile()))
	await frames(2)
	var made := get_tree().get_nodes_in_group(Afterimage.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_eq(made.size(), 0, "the next perfect dodge leaves none")


func test_the_chain_rim_goes_at_once_when_its_switch_is_turned_off() -> void:
	var run := Duel.make(self, [{"frames": 600}], [], 6.0)
	var a: Actor = run["a"]
	for i in 3:
		a.chain.link(false, a.buffer_frame)
	await frames(2)
	assert_true(a.rig.aura_active(), "a rim at Quick")
	var menu := _pause_menu_on(&"effects")
	_select(menu, "Chain rim")
	menu.press(C.CHOOSE)
	Game.change(Game.State.PLAY)
	await frames(1)
	assert_false(a.rig.aura_active(), "the frame after the resume it is off")
	menu.press(C.CHOOSE)
	await frames(1)
	assert_true(a.rig.aura_active(), "and on again when the switch is")


func test_a_shake_in_progress_follows_the_slider_the_moment_it_is_set() -> void:
	var rig := track(CameraRig.new()) as CameraRig
	rig.shake(1.0)
	await frames(2)
	var full := rig.shake_offset()
	assert_true(full.length() > 0.0, "a shake is on")
	var menu := _pause_menu_on(&"camera")
	menu.press(C.LEFT)
	menu.press(C.LEFT)
	assert_vec2_near(rig.shake_offset(), full * 0.5, "at 50 the same shake is half as far, with no frame between")
	menu.press(C.LEFT)
	menu.press(C.LEFT)
	assert_eq(rig.shake_offset(), Vector2.ZERO, "at 0 it is still")
	menu.press(C.RIGHT)
	assert_vec2_near(rig.shake_offset(), full * 0.25, "and back up it returns")


func assert_vec2_near(a: Vector2, b: Vector2, msg := "") -> void:
	assert_true(a.distance_to(b) < 1e-4, "%s: %s vs %s" % [msg, a, b])


func test_turning_every_effect_off_then_fighting_prints_no_error() -> void:
	var foe := Duel.def(ActorDef.Team.ENEMY, 5.0)
	var run := Duel.make(self, [{"frames": 400}], [{"frames": 400}], 1.2, foe)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var menu := _pause_menu_on(&"effects")
	for i in ReadabilityTuning.SWITCHES.size():
		menu.press(C.CHOOSE)
		menu.press(C.DOWN)
	for switch in ReadabilityTuning.SWITCHES:
		assert_eq(Settings.get_value("effects/%s" % switch), false, "%s is off" % switch)
	Game.change(Game.State.PLAY)
	var started := []
	b.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	for move in [&"knuckle_thrust", &"heavy_slam", &"knuckle_jab"]:
		if Registry.ids(&"moves").has(String(move)):
			b.runner.start(Registry.fetch(&"moves", move) as MoveData)
		await frames(3)
		a.runner.start(Registry.fetch(&"moves", &"parry") as MoveData)
		await frames(30)
	for i in 8:
		var result := HitResult.new()
		result.outcome = HitResult.Outcome.EVADED
		result.perfect = i % 2 == 0
		a.chain.link(result.perfect, a.buffer_frame)
		a.got_hit.emit(result, Blows.event(b, a, Blows.profile()))
		await frames(2)
	await frames(60)
	assert_true(started.has(&"heavy_slam") and started.has(&"knuckle_thrust"), "the foe's heavy and thrust were thrown: %s" % [started])
	assert_true(a.chain.count >= 7, "a flurry was reached (%d)" % a.chain.count)


# --- from the Task 3 review ---

func test_closing_the_menu_stops_the_sample_that_is_playing() -> void:
	var menu := _menu()
	_pause()
	menu.show_page(&"sound")
	menu._process(1.0)
	_select(menu, "Effects")
	menu.press(C.LEFT)
	assert_true(menu.sample_player.playing, "a step started a sample")
	Game.change(Game.State.PLAY)
	assert_false(menu.is_open, "the resume closed the menu")
	assert_false(menu.sample_player.playing, "and the sample does not play on into the fight")


func test_a_held_direction_never_flips_a_choice_row() -> void:
	var menu := _menu()
	menu.show_page(&"window")
	assert_eq(_value(menu, "Mode"), "Fullscreen", "the game comes fullscreen")
	var flips := []
	var count := func(key: String) -> void: flips.append(key)
	Settings.changed.connect(count)
	menu.handle(_key_event(KEY_RIGHT))
	for i in 7:
		menu._process(0.1)
	menu.handle(_key_event(KEY_RIGHT, false))
	assert_eq(flips, ["window/mode"], "Right held for 0.7 s on Mode flipped it once (the press), not again for each repeat")
	Settings.changed.disconnect(count)
	assert_eq(_value(menu, "Mode"), "Window")
	_select(menu, "Size")
	var size := _value(menu, "Size")
	menu.handle(_key_event(KEY_RIGHT))
	var once := _value(menu, "Size")
	for i in 7:
		menu._process(0.1)
	menu.handle(_key_event(KEY_RIGHT, false))
	assert_ne(once, size, "the press moved Size on")
	assert_eq(_value(menu, "Size"), once, "and the repeats did not move it further")
	# A slider still repeats, and the selection still moves on a repeat.
	menu.show_page(&"camera")
	menu.handle(_key_event(KEY_LEFT))
	for i in 12:
		menu._process(0.1)
	menu.handle(_key_event(KEY_LEFT, false))
	assert_eq(Settings.get_value("camera/shake"), 0, "a held Left still runs a slider down")
	menu.show_page(&"settings")
	menu.handle(_key_event(KEY_DOWN))
	for i in 7:
		menu._process(0.1)
	menu.handle(_key_event(KEY_DOWN, false))
	assert_true(menu.index >= 3, "a held Down still moves the selection on repeat (at %d)" % menu.index)


func test_a_line_of_words_is_drawn_in_the_dim_colour_of_a_switched_off_row() -> void:
	var menu := _menu()
	var dim := Color(Hud.POSTURE, Menu.DIM_ALPHA)
	menu.show_page(&"camera")
	assert_eq(_row(menu, SettingsPages.DIPS_NOTE).get("colour"), dim, "the Camera page's note")
	assert_eq(_row(menu, "Camera shake").get("colour"), Hud.ROSE, "the selected row")
	assert_eq(_row(menu, "Camera dips").get("colour"), Hud.WHITE, "a live row")
	menu.show_page(&"window")
	_select(menu, "Back")
	assert_eq(_row(menu, "Size").get("colour"), dim, "a row switched off is the same colour as the words")
