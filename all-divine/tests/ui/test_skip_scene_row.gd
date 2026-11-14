extends TestCase
## `Skip scene` on the pause menu: the row stands second on the root page when the game was paused from a scene that can be skipped
## (one that has been seen), and is not there otherwise (not dim: absent). Choosing it ends the scene as its own end would, from the
## menu: the game plays, the fight is handed back with the foes' rest and the input quarantine, the camera glides home from the
## frame it stood at. Through the real Main and the real menu.

const MAIN := "res://main/main.tscn"
const SETTINGS_PATH := "user://settings_test.cfg"
const C := MenuNav.Cmd
const PLAIN := ["Resume", "Controls", "Settings", "Quit"]
const WITH_ROW := ["Resume", "Skip scene", "Controls", "Settings", "Quit"]


func before_each() -> void:
	Settings.path = SETTINGS_PATH
	Game.reset()
	Director.reset_spawn_counts()
	StoryLog.forget_all()
	Melee.slow(0, 1.0)


func after_each() -> void:
	for code in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE, KEY_W]:
		_key(code, false)
	_pad(JOY_BUTTON_A, false)
	for action in [&"palm", &"heavy", &"guard", &"dodge"]:
		Input.action_release(action)
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Melee.slow(0, 1.0)
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pad(button: JoyButton, pressed := true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# Main in the yard, two frames in; `calm` leaves the foes without a brain.
func _main(calm := true) -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	if calm:
		for foe in main.arena().enemies():
			foe.set_brain(Brain.new())
	await frames(2)
	return main


# The fixture scene playing in `main`, run to scene frame `at`; `seen` makes it a later viewing (one that can be skipped).
func _scene(main: Main, at: int, seen := true) -> Director:
	if seen:
		StoryLog.mark_seen(&"fixture_yard_entrance")
	var director := Director.play(&"fixture_yard_entrance", main)
	assert_true(director != null, "the scene plays: %s" % Director.last_refusal)
	while director != null and director.frame < at:
		await frames(1)
	return director


func _labels(main: Main) -> Array:
	return main.menu.rows().map(func(r: Dictionary) -> String: return r.label)


func _watch(actor: Actor) -> Array:
	var started := []
	actor.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, m.kind, actor.frame]))
	return started


func _overlays(main: Main) -> int:
	return main.stage.hud.get_children().filter(func(c: Node) -> bool: return c is CineOverlay and not c.is_queued_for_deletion()).size()


# Plays frames until the scene's glide home is over (at most 120).
func _until_home(director: Director) -> void:
	var n := 0
	while is_instance_valid(director) and director.phase != Director.Phase.DONE and n < 120:
		await frames(1)
		n += 1


func test_paused_from_play_the_root_page_is_as_it_was() -> void:
	var main := await _main()
	Game.change(Game.State.PAUSE)
	assert_eq(_labels(main), PLAIN, "Resume, Controls, Settings, Quit: no Skip scene")


func test_paused_from_a_scene_that_can_be_skipped_the_row_stands_second() -> void:
	var main := await _main()
	var director := await _scene(main, 100)
	if director == null:
		return
	Game.change(Game.State.PAUSE)
	assert_eq(_labels(main), WITH_ROW, "Skip scene is second, under Resume")
	assert_eq(main.menu.index, 0, "and the selection starts on Resume")
	assert_true(main.menu.rows()[1].enabled, "it is lit")


func test_paused_from_a_first_viewing_there_is_no_row() -> void:
	var main := await _main()
	var director := await _scene(main, 100, false)
	if director == null:
		return
	assert_false(director.is_skippable(), "a first viewing cannot be skipped")
	Game.change(Game.State.PAUSE)
	assert_eq(_labels(main), PLAIN, "so the menu has no row for it: not dim, not there")


func test_a_scene_that_has_handed_back_is_not_offered() -> void:
	var main := await _main()
	var director := await _scene(main, 300)
	if director == null:
		return
	while director.phase != Director.Phase.LEAD_OUT:
		await frames(1)
	Game.change(Game.State.PAUSE)
	assert_eq(_labels(main), PLAIN, "in the glide home there is nothing to skip")


func test_the_scene_does_not_move_while_the_menu_is_open_so_the_row_cannot_go_dead() -> void:
	var main := await _main()
	var director := await _scene(main, 100)
	if director == null:
		return
	Game.change(Game.State.PAUSE)
	var frame := director.frame
	await frames(60)
	assert_eq(director.frame, frame, "the scene's frame does not move in the pause")
	assert_true(director.is_skippable(), "so the row it offered is still good")
	assert_eq(_labels(main), WITH_ROW)
	main.menu.press(C.DOWN)
	main.menu.press(C.UP)
	assert_eq(_labels(main), WITH_ROW, "and after the menu has refreshed")


func test_choosing_the_row_with_enter_ends_the_scene_and_plays() -> void:
	var main := await _main(false)
	var player := main.player
	var started := _watch(player)
	var foes := get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP).filter(func(n: Node) -> bool: return main.region.is_ancestor_of(n))
	var swings := []
	for foe: Actor in foes:
		foe.runner.move_started.connect(func(m: MoveData) -> void: if m.kind == MoveData.Kind.ATTACK: swings.append(foe.frame))
	var director := await _scene(main, 100)
	if director == null:
		return
	var hp := player.stats.hp
	Game.change(Game.State.PAUSE)
	main.menu.press(C.DOWN)
	assert_eq(main.menu.rows()[main.menu.index].label, "Skip scene", "selected")
	_key(KEY_ENTER)  # Enter chooses, and is the dash-step in the fight
	assert_eq(Game.state, Game.State.PLAY, "the game plays")
	assert_false(main.menu.is_open, "the menu is closed")
	assert_false(director.is_skippable(), "and the scene is no longer skippable (it is ending)")
	await frames(6)
	assert_false(Inputs.held(&"dodge"), "the key that chose it is dead while it is held")
	assert_eq(started, [], "and does nothing in the fight: %s" % [started])
	_key(KEY_ENTER, false)
	_key(KEY_W)
	var from := player.global_position
	await frames(24)
	assert_true(player.global_position.distance_to(from) > 0.3, "the player moves on the next stick input")
	assert_eq(swings, [], "no foe has begun an attack in the first 30 frames")
	assert_eq(player.stats.hp, hp, "and nothing landed on him")
	await _until_home(director)
	assert_true(Director.current() == null, "once the camera is home no scene is current")
	assert_eq(_overlays(main), 0, "the bars and the box are gone")
	assert_eq(main.camera_rig.cine_weight, 0.0, "the camera is the game's")
	assert_false(main.hud.suppressed)


func test_choosing_the_row_with_the_pad_button_ends_the_scene_and_plays() -> void:
	var main := await _main(false)
	var player := main.player
	Inputs._device = Inputs.Device.GAMEPAD
	var started := _watch(player)
	var director := await _scene(main, 100)
	if director == null:
		return
	Game.change(Game.State.PAUSE)
	main.menu.press(C.DOWN)
	_pad(JOY_BUTTON_A)  # the pad's A chooses; in the fight it is the dash-step
	assert_eq(Game.state, Game.State.PLAY)
	await frames(6)
	assert_false(Inputs.held(&"dodge"), "the button that chose it is dead while held")
	assert_eq(started, [], "and starts nothing")
	_pad(JOY_BUTTON_A, false)
	await frames(2)
	_pad(JOY_BUTTON_A)
	await frames(4)
	assert_true(started.size() > 0, "let go and pressed again, it acts")
	_pad(JOY_BUTTON_A, false)
	await _until_home(director)
	assert_true(Director.current() == null)


func test_a_skip_from_the_menu_glides_home_from_the_frame_it_stood_at_in_steps_of_12_px() -> void:
	var main := await _main()
	var player := main.player
	var director := await _scene(main, 170)  # a close shot at zoom 3: the longest way home
	if director == null:
		return
	Game.change(Game.State.PAUSE)
	var head := main.hud.picture_point(player.head_point())  # measured from the paused frame
	main.menu.press(C.DOWN)
	main.menu.press(C.CHOOSE)
	assert_eq(Game.state, Game.State.PLAY, "Skip scene plays")
	assert_eq(director.phase, Director.Phase.LEAD_OUT, "and the scene is in its glide home")
	var worst := 0.0
	var n := 0
	while is_instance_valid(director) and director.phase != Director.Phase.DONE and n < 120:
		await frames(1)
		n += 1
		var now := main.hud.picture_point(player.head_point())
		worst = maxf(worst, now.distance_to(head))
		head = now
	assert_true(worst <= 12.0, "his head moves at most 12 px a frame from the paused frame home (%.1f)" % worst)
	assert_true(n > 20, "over the whole skip glide (%d frames)" % n)


func test_skipped_on_the_first_frame_and_on_the_last_frame_the_end_state_is_the_same() -> void:
	var ends := []
	for at in [0, 299]:
		var main := await _main()
		var brain := main.player.brain
		var director := await _scene(main, at)
		if director == null:
			return
		Game.change(Game.State.PAUSE)
		main.menu.press(C.DOWN)
		main.menu.press(C.CHOOSE)
		await _until_home(director)
		await frames(2)
		ends.append({
			state = Game.state, brain = main.player.brain == brain, weight = main.camera_rig.cine_weight, overlays = _overlays(main),
			hud = main.hud.suppressed, alpha = main.hud.shown_alpha(), current = Director.current() == null,
			foes = get_tree().get_nodes_in_group(Actor.GROUP).filter(func(n: Node) -> bool: return main.region.is_ancestor_of(n)).size(),
		})
		main.free()
		await frames(1)
	assert_eq(ends[0], ends[1], "skipped on frame 0 or on frame 299: the same end state")
	assert_eq(ends[0].state, Game.State.PLAY)
	assert_true(ends[0].brain and ends[0].current)


func test_esc_skip_scene_esc_again_opens_the_menu_over_play_as_usual() -> void:
	var main := await _main()
	var director := await _scene(main, 100)
	if director == null:
		return
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PAUSE, "Esc pauses the scene")
	assert_eq(_labels(main), WITH_ROW)
	main.menu.press(C.DOWN)
	main.menu.press(C.CHOOSE)
	assert_eq(Game.state, Game.State.PLAY)
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PAUSE, "Esc again at once opens the menu")
	assert_true(main.menu.is_open)
	assert_eq(_labels(main), PLAIN, "over play, as usual: no row for a scene that is over")
	assert_eq(main.menu.index, 0)
	main.menu.press(C.CHOOSE)
	assert_eq(Game.state, Game.State.PLAY, "and Resume plays (nothing left behind)")
	await frames(60)
	assert_eq(Game.state, Game.State.PLAY)


func test_resume_from_a_paused_scene_goes_back_to_the_frame_it_stopped_at_with_the_row_present() -> void:
	var main := await _main()
	var director := await _scene(main, 100)
	if director == null:
		return
	Game.change(Game.State.PAUSE)
	var frame := director.frame
	assert_eq(_labels(main), WITH_ROW)
	await frames(20)
	main.menu.press(C.CHOOSE)  # Resume
	assert_eq(Game.state, Game.State.CUTSCENE, "Resume goes back to the scene")
	await frames(1)
	assert_true(director.frame <= frame + 2 and director.frame >= frame, "on the frame it stopped at (%d, %d)" % [frame, director.frame])


func test_the_panel_stays_inside_the_menus_bounds_with_the_fifth_row() -> void:
	var main := await _main()
	var director := await _scene(main, 100)
	if director == null:
		return
	Game.change(Game.State.PAUSE)
	var panel := main.menu.panel()
	assert_eq(main.menu.rows().size(), 5, "all five rows are shown, none scrolled away")
	assert_true(panel.size.x < 140, "the panel is narrower than 140 px (%d)" % panel.size.x)
	assert_eq(panel.position, Vector2i(8, 8), "where it was")
	assert_true(panel.end.y <= 190, "and ends above y 190 (%d)" % panel.end.y)
	assert_eq(panel.size.y, 90, "one row (10 px) taller than the four-row page")
	var font := ThemeDB.fallback_font
	var layout := main.menu.layout()
	var inner := panel.end.x - Menu.PADDING
	for r in main.menu.rows():
		var right: int = r.text_at.x + ceili(font.get_string_size(r.label, HORIZONTAL_ALIGNMENT_LEFT, -1, Menu.FONT_SIZE).x)
		assert_true(right <= inner, "'%s' ends inside the padding (%d <= %d)" % [r.label, right, inner])
