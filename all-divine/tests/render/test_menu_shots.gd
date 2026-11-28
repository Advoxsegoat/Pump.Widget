extends TestCase
## The menu as a person sees it (xvfb, gl_compatibility): every page, as the Hud's own 640x360 picture (out/menu/<page>_640.png)
## and as the whole stage at 1920x1080, the world frozen mid-fight behind it (out/menu/<page>_1080.png), saved for a person to
## look at. The fight behind the panel is not dimmed: outside the panel the picture is the one the paused world shows without it.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(1920, 1080)
const DIR := "out/menu"
const SETTINGS_PATH := "user://settings_test.cfg"


func _settle() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw


func _save(img: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(DIR).path_join(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(img.save_png(path), OK, "saved %s" % path)


func before_each() -> void:
	Settings.path = SETTINGS_PATH
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


# The pages shot besides every page as it is at the start: [file name, page, settings put first]. The Window page is shot in
# fullscreen (as the game comes) and in a window, and the settings pages with values that are not the defaults, so that a
# bar short of full, an Off and a dim row are seen.
const VARIANTS := [
	["window_windowed", &"window", {"window/mode": "windowed", "window/scale": 3}],
	["effects_some_off", &"effects", {"effects/perilous_rim_on": false, "effects/slowdown_on": false, "effects/chain_rim_on": false}],
	["camera_set", &"camera", {"camera/shake": 50, "camera/dips": false}],
	["look_set", &"look", {"look/outline": 75, "look/dof": 50, "look/bloom": 0, "look/fog": 25, "look/grade": 100, "look/vignette": 75}],
	["sound_set", &"sound", {"sound/master": 80, "sound/music": 40, "sound/sfx": 100, "sound/voice": 0, "sound/ui": 60}],
]


func test_every_page_is_shot_at_640_and_at_1080() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	# Long enough for the Knuckle to have walked into view and the shadows to be drawn.
	await frames(90)
	Game.change(Game.State.PAUSE)
	await frames(2)
	assert_eq(PixelStage.scale_for(SIZE), 3, "x3 at 1080p")
	var shots: Array = MenuPages.ids().map(func(id: StringName) -> Array: return [String(id), id, {}])
	shots.append_array(VARIANTS)
	for shot: Array in shots:
		Settings.reset_all()
		for key: String in shot[2]:
			Settings.set_value(key, shot[2][key])
		await _shoot(main, shot[0], shot[1])


# One page shown (settings already put), saved as <name>_640.png and <name>_1080.png, and what it must be checked.
func _shoot(main: Main, name: String, id: StringName) -> void:
	var k := PixelStage.scale_for(SIZE)
	var origin := PixelStage.layout(SIZE).position
	main.menu.show_page(id)
	main.menu.visible = false
	await _settle()
	var without := get_viewport().get_texture().get_image()
	main.menu.visible = true
	await _settle()
	var picture := main.stage.hud.get_texture().get_image()
	var stage := get_viewport().get_texture().get_image()
	assert_eq(picture.get_size(), Vector2i(640, 360))
	assert_eq(stage.get_size(), SIZE, "the test needs a 1920x1080 window")
	_save(picture, "%s_640.png" % name)
	_save(stage, "%s_1080.png" % name)
	var panel := main.menu.panel()
	assert_true(panel.size.x <= 224 and panel.end.y <= 190, "%s: the panel is inside its limits (%s)" % [name, panel])
	# The panel's gold border is crisp at x3: a solid three pixel line at its top edge, ungraded.
	var edge := origin + (panel.position + Vector2i(40, 0)) * k
	for dy in 3:
		var c := stage.get_pixelv(edge + Vector2i(0, dy))
		assert_true(absf(c.r - Hud.GOLD.r) < 0.03 and absf(c.g - Hud.GOLD.g) < 0.03 and absf(c.b - Hud.GOLD.b) < 0.03, "%s: the border is gold, 3 px at x3 (%s)" % [name, c.to_html(false)])
	# Outside the panel the stage is what the paused world shows without the menu: nothing is dimmed or tinted.
	var differs := 0
	var area := Rect2i(origin + panel.position * k, panel.size * k).grow(k)
	for y in range(0, SIZE.y, 2):
		for x in range(0, SIZE.x, 2):
			if not area.has_point(Vector2i(x, y)) and stage.get_pixel(x, y) != without.get_pixel(x, y):
				differs += 1
	assert_eq(differs, 0, "%s: the fight outside the panel is untouched" % name)


# A page of twenty rows that is not one of the game's (the controls page will be the first long one), scrolled by Down presses:
# saved as out/menu/scrolled_640.png and scrolled_1080.png, and its arrows are drawn where the layout says.
func test_a_scrolled_page_is_shot_with_its_arrows() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(90)
	Game.change(Game.State.PAUSE)
	var page := MenuPage.new()
	page.heading = "A page of twenty rows"
	page.back = func() -> void: pass
	for i in 20:
		var row := MenuRow.action("Row %d" % (i + 1), func() -> void: pass)
		row.kind = MenuRow.Kind.SLIDER
		row.value_text = func() -> String: return "%d%%" % (i * 5)
		page.rows.append(row)
	main.menu.show_page(&"scrolled", page)
	for i in 17:
		main.menu.press(MenuNav.Cmd.DOWN)
	await frames(2)
	await _settle()
	var picture := main.stage.hud.get_texture().get_image()
	_save(picture, "scrolled_640.png")
	_save(get_viewport().get_texture().get_image(), "scrolled_1080.png")
	var layout := main.menu.layout()
	assert_true(main.menu.panel().end.y <= 190, "the panel ends above y 190")
	for arrow: Rect2i in [layout.arrow_up, layout.arrow_down]:
		assert_true(arrow.size != Vector2i.ZERO, "both arrows show (rows hidden above and below)")
		var c := picture.get_pixelv(arrow.position + Vector2i(2, 0) if arrow == layout.arrow_down else arrow.position + Vector2i(2, 2))
		assert_true(absf(c.r - Hud.GOLD.r) < 0.03 and absf(c.g - Hud.GOLD.g) < 0.03 and c.a > 0.8, "the arrow is gold at its tip row: %s" % c.to_html(false))


# The Controls page for each device, as it opens, mid-capture (Palm waiting) and scrolled to its last row: out/menu/controls_<device>_<state>_640.png
# and _1080.png. The panel stays inside its limits, and its size does not change between the three.
func test_the_controls_page_is_shot_for_each_device_mid_capture_and_scrolled() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(90)
	Game.change(Game.State.PAUSE)
	main.menu.pad_present = func() -> bool: return Inputs.last_device() == Inputs.Device.GAMEPAD
	var path_was := Inputs.bindings_path
	Inputs.bindings_path = "user://menu_shots_input.cfg"
	for pad in [false, true]:
		Inputs._device = Inputs.Device.GAMEPAD if pad else Inputs.Device.KEYBOARD_MOUSE
		var name := "controls_pad" if pad else "controls_keyboard"
		main.menu.show_page(MenuPages.CONTROLS)
		var size := main.menu.panel().size
		await _settle()
		_save(main.stage.hud.get_texture().get_image(), "%s_normal_640.png" % name)
		_save(get_viewport().get_texture().get_image(), "%s_normal_1080.png" % name)
		for i in 4:  # Palm is the fifth row
			main.menu.press(MenuNav.Cmd.DOWN)
		main.menu.press(MenuNav.Cmd.CHOOSE)
		assert_true(main.menu.capturing(), "%s: waiting for Palm" % name)
		await _settle()
		_save(main.stage.hud.get_texture().get_image(), "%s_capture_640.png" % name)
		_save(get_viewport().get_texture().get_image(), "%s_capture_1080.png" % name)
		assert_eq(main.menu.panel().size, size, "%s: the panel does not change in a capture" % name)
		assert_true(main.menu.panel().end.y <= 190)
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.physical_keycode = KEY_ESCAPE
		escape.pressed = true
		main.menu.handle(escape)
		assert_false(main.menu.capturing())
		main.menu.show_page(MenuPages.CONTROLS)
		main.menu.press(MenuNav.Cmd.UP)  # from the first row to the last (Back): the list is scrolled to its end
		await _settle()
		_save(main.stage.hud.get_texture().get_image(), "%s_scrolled_640.png" % name)
		_save(get_viewport().get_texture().get_image(), "%s_scrolled_1080.png" % name)
		assert_eq(main.menu.panel().size, size)
	Inputs.bindings_path = path_was
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Bindings.apply(Bindings.defaults())


# The pause over a scene that can be skipped: a CUTSCENE (bars) paused while a line is up in the dialogue box, the menu with its
# Skip scene row over the top bar and the box: out/menu/pause_scene_640.png and pause_scene_1080.png.
func test_a_paused_scene_is_shot_with_the_menu_and_its_skip_row() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	Director.reset_spawn_counts()
	StoryLog.mark_seen(&"fixture_yard_entrance")
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	for foe in main.arena().enemies():
		foe.set_brain(Brain.new())
	await frames(30)
	var scene := (load("res://scenes/story/fixture_yard_entrance/shots.tres") as SceneShots).duplicate_deep()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.letterbox = true
	var director := Director.new()
	assert_true(director.begin(scene, main.region, main.camera_rig, main.hud, main), "the scene is taken: %s" % Director.last_refusal)
	while director.frame < 30 + 150 + 12:
		await frames(1)
	Game.change(Game.State.PAUSE)
	await frames(2)
	var labels: Array = main.menu.rows().map(func(r: Dictionary) -> String: return r.label)
	assert_eq(labels, ["Resume", "Skip scene", "Controls", "Settings", "Quit"], "the menu offers Skip scene")
	await _settle()
	var picture := main.stage.hud.get_texture().get_image()
	var stage := get_viewport().get_texture().get_image()
	assert_eq(picture.get_size(), Vector2i(640, 360))
	_save(picture, "pause_scene_640.png")
	_save(stage, "pause_scene_1080.png")
	var panel := main.menu.panel()
	assert_true(panel.size.x <= 224 and panel.end.y <= 190, "the panel is inside its limits (%s)" % panel)
	# The top bar is black and the menu's panel is drawn over it: the panel's gold border is on top of the bar, not under it.
	var k := PixelStage.scale_for(SIZE)
	var origin := PixelStage.layout(SIZE).position
	var edge := origin + (panel.position + Vector2i(40, 0)) * k
	var c := stage.get_pixelv(edge)
	assert_true(absf(c.r - Hud.GOLD.r) < 0.03 and absf(c.g - Hud.GOLD.g) < 0.03 and absf(c.b - Hud.GOLD.b) < 0.03, "the menu's border is gold over the bar (%s)" % c.to_html(false))
