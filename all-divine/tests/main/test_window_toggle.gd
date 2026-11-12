extends TestCase
## The game's window: it starts in borderless fullscreen, so the 640x360 picture fills a 1080p screen at x3
## (x4 at 1440p, x6 at 4K); F11 or Alt+Enter switches to a 1280x720 window (x2) and back (WindowToggle,
## used by main/main.gd). A headless run has no real window to switch, so the switch is checked on a
## Window node outside the tree, which keeps the mode and size it is given.

const PROJECT := "res://project.godot"
const SETTINGS_PATH := "user://settings_test.cfg"


# F11 in Main writes the chosen mode down, so every test here keeps the settings in a file of its own.
func before_each() -> void:
	Settings.path = SETTINGS_PATH


func after_each() -> void:
	_restore_settings()


func test_the_game_starts_in_borderless_fullscreen() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/size/mode"), DisplayServer.WINDOW_MODE_FULLSCREEN,
		"display/window/size/mode is fullscreen (3, borderless), not exclusive (4)")
	# The setting as written, and the web build's own: a browser refuses fullscreen until the player asks
	# for it with a key or a click, so the web build starts in its page.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PROJECT), OK)
	assert_eq(cfg.get_value("display", "window/size/mode", -1), 3, "fullscreen in project.godot")
	assert_eq(cfg.get_value("display", "window/size/mode.web", -1), 0, "windowed on the web")
	# The window size the stage scales to (and the one xvfb runs and the contact sheets get) is unchanged.
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1920)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1080)


func test_fullscreen_switches_to_a_1280x720_window() -> void:
	for mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		assert_eq(WindowToggle.target(mode), {"mode": Window.MODE_WINDOWED, "size": Vector2i(1280, 720)}, "from mode %d" % mode)
	assert_eq(PixelStage.scale_for(Vector2i(1280, 720)), 2, "the window shows the picture at x2")


func test_a_window_switches_to_fullscreen() -> void:
	# Fullscreen takes the screen's size, so the toggle gives none (Vector2i.ZERO).
	for mode in [Window.MODE_WINDOWED, Window.MODE_MAXIMIZED, Window.MODE_MINIMIZED]:
		assert_eq(WindowToggle.target(mode), {"mode": Window.MODE_FULLSCREEN, "size": Vector2i.ZERO}, "from mode %d" % mode)


func test_toggling_twice_comes_back() -> void:
	var there: Dictionary = WindowToggle.target(Window.MODE_FULLSCREEN)
	assert_eq(WindowToggle.target(there.mode).mode, Window.MODE_FULLSCREEN)


func test_f11_and_alt_enter_are_the_toggle() -> void:
	assert_true(WindowToggle.is_toggle(_key(KEY_F11)), "F11")
	assert_true(WindowToggle.is_toggle(_key(KEY_ENTER, true)), "Alt+Enter")
	assert_true(WindowToggle.is_toggle(_key(KEY_KP_ENTER, true)), "Alt+keypad Enter")
	assert_false(WindowToggle.is_toggle(_key(KEY_ENTER)), "Enter alone")
	assert_false(WindowToggle.is_toggle(_key(KEY_F10)), "another key")
	assert_false(WindowToggle.is_toggle(_key(KEY_ALT, true)), "Alt alone")
	var released := _key(KEY_F11)
	released.pressed = false
	assert_false(WindowToggle.is_toggle(released), "letting go of F11")
	var repeat := _key(KEY_F11)
	repeat.echo = true
	assert_false(WindowToggle.is_toggle(repeat), "F11 held down repeats; only the press counts")
	var action := InputEventAction.new()
	action.action = &"menu"
	action.pressed = true
	assert_false(WindowToggle.is_toggle(action), "not a key")


func test_apply_switches_the_window_it_is_given() -> void:
	var window := Window.new()
	window.mode = Window.MODE_FULLSCREEN
	WindowToggle.apply(window)
	assert_eq(window.mode, Window.MODE_WINDOWED)
	assert_eq(window.size, Vector2i(1280, 720))
	WindowToggle.apply(window)
	assert_eq(window.mode, Window.MODE_FULLSCREEN)
	window.free()


func test_main_switches_its_window_on_f11_and_alt_enter() -> void:
	Game.reset()
	var main := track((load("res://main/main.tscn") as PackedScene).instantiate()) as Main
	assert_eq(main.window, get_window(), "the game's own window by default")
	var window := Window.new()
	window.mode = Window.MODE_FULLSCREEN
	main.window = window
	_push(_key(KEY_F11))
	assert_eq([window.mode, window.size], [Window.MODE_WINDOWED, Vector2i(1280, 720)], "F11: a 1280x720 window")
	_push(_key(KEY_ENTER, true))
	assert_eq(window.mode, Window.MODE_FULLSCREEN, "Alt+Enter: fullscreen again")
	window.free()
	Game.reset()


func test_f11_returns_to_the_chosen_window_size() -> void:
	Settings.set_value("window/scale", 3)
	var screen := Vector2i(1920, 1080)
	assert_eq(WindowToggle.target(Window.MODE_FULLSCREEN, screen).size, Vector2i(1920, 1080), "scale 3")
	Settings.set_value("window/scale", 6)
	assert_eq(WindowToggle.target(Window.MODE_FULLSCREEN, screen).size, Vector2i(1920, 1080), "6 does not fit 1080p: 3")
	Settings.reset_all()
	assert_eq(WindowToggle.target(Window.MODE_FULLSCREEN, screen).size, Vector2i(1280, 720), "the default stays 1280x720")
	assert_eq(WindowToggle.target(Window.MODE_FULLSCREEN).size, Vector2i(1280, 720), "and so on a screen it does not know")


func test_f11_records_the_mode_it_leaves() -> void:
	Game.reset()
	var main := track((load("res://main/main.tscn") as PackedScene).instantiate()) as Main
	var window := Window.new()
	window.mode = Window.MODE_FULLSCREEN
	main.window = window
	_push(_key(KEY_F11))
	assert_eq(Settings.get_value("window/mode"), "windowed", "F11 left it windowed")
	_push(_key(KEY_F11))
	assert_eq(Settings.get_value("window/mode"), "fullscreen", "and again, fullscreen")
	window.free()
	Game.reset()


func test_on_the_web_f11_goes_to_the_base_window_size() -> void:
	Settings.on_web = true
	Settings.set_value("window/scale", 3)
	assert_eq(WindowToggle.target(Window.MODE_FULLSCREEN, Vector2i(1920, 1080)).size, Vector2i(1280, 720),
		"the web's windowed size does not follow the setting")
	assert_eq(WindowToggle.target(Window.MODE_FULLSCREEN).size, Vector2i(1280, 720))
	Settings.on_web = false
	assert_eq(WindowToggle.target(Window.MODE_FULLSCREEN, Vector2i(1920, 1080)).size, Vector2i(1920, 1080), "off the web it does")


func _restore_settings() -> void:
	Settings.on_web = OS.has_feature("web")
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func _key(keycode: Key, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.alt_pressed = alt
	event.pressed = true
	return event


# Pushes the press, then its release, into the viewport.
func _push(event: InputEventKey) -> void:
	get_viewport().push_input(event)
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	get_viewport().push_input(up)
