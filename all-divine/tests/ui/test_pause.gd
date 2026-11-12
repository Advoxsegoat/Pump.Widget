extends TestCase
## The pause: the menu that opens with it, a pause that gives the fight back exactly as it was, and presses that do not
## leak through the menu into the fight (Review Focus 1 and 2 of the menus plan).
##
## Real events are made with Input.parse_input_event (they reach Main the way the window's would, and set the state
## Input.is_action_pressed reads); a few events go straight to the viewport with push_input.

const MAIN := "res://main/main.tscn"
const SETTINGS_PATH := "user://settings_test.cfg"
const C := MenuNav.Cmd


func before_each() -> void:
	Settings.path = SETTINGS_PATH
	Game.reset()


func after_each() -> void:
	for code in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE, KEY_W, KEY_S, KEY_F1, KEY_F4]:
		_key(code, false)
	for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]:
		_pad(button, false)
	_mouse(false)
	for action in [&"palm", &"heavy", &"guard", &"dodge"]:
		Input.action_release(action)
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


# --- helpers ---

# Main in the yard, two frames in. `calm` leaves the foes without a brain, so that nothing but the test moves Abarax.
func _main(calm := true) -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	if calm:
		for foe in main.arena().enemies():
			foe.set_brain(Brain.new())
	await frames(2)
	return main


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


func _mouse(pressed := true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(200, 200)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _push_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)


# The moves `actor` starts, as [id, frame], from now on.
func _watch(actor: Actor) -> Array:
	var started := []
	actor.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, actor.frame]))
	return started


func _foes(main: Main) -> int:
	return get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP).filter(func(n: Node) -> bool: return main.region.is_ancestor_of(n)).size()


# --- the menu ---

func test_any_move_into_pause_opens_the_menu_and_out_closes_it() -> void:
	var main := await _main()
	var menu := main.menu
	assert_false(menu.is_open, "closed while playing")
	assert_false(menu.visible, "and hidden")
	Game.change(Game.State.PAUSE)
	assert_true(menu.is_open and menu.visible, "any move into PAUSE opens it")
	assert_eq(menu.heading(), "Paused")
	assert_eq([menu.page, menu.index], [&"root", 0], "at the root page with the first row selected")
	assert_true(menu.can_process(), "it runs while the tree is paused")
	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(menu.get_viewport(), main.stage.hud, "in the Hud's picture")
	menu.press(C.DOWN)
	Game.change(Game.State.PLAY)
	assert_false(menu.is_open or menu.visible, "any move out of it closes it")
	Game.change(Game.State.PAUSE)
	assert_eq([menu.page, menu.index], [&"root", 0], "and it opens afresh")
	assert_true(Game.change(Game.State.TITLE))
	assert_false(menu.is_open, "to the title too")


func test_resume_row_and_back_on_the_first_page_both_resume() -> void:
	var main := await _main()
	var menu := main.menu
	Game.change(Game.State.PAUSE)
	assert_eq(menu.rows()[0].label, "Resume", "Resume is the first row")
	menu.press(C.CHOOSE)
	assert_eq(Game.state, Game.State.PLAY, "choosing Resume plays")
	assert_false(get_tree().paused)
	Game.change(Game.State.PAUSE)
	menu.press(C.BACK)
	assert_eq(Game.state, Game.State.PLAY, "Back on the first page plays")
	Game.change(Game.State.PAUSE)
	_key(KEY_ENTER)
	_key(KEY_ENTER, false)
	assert_eq(Game.state, Game.State.PLAY, "and so does the Enter key")


func test_quit_asks_first() -> void:
	# On a Menu of its own: Main's would end the test run when asked to quit.
	var menu := track(Menu.new()) as Menu
	var asked := []
	menu.quit_requested.connect(func() -> void: asked.append(1))
	menu.open()
	assert_eq(menu.rows().map(func(r: Dictionary) -> String: return r.label), ["Resume", "Quit"])
	menu.press(C.DOWN)
	menu.press(C.CHOOSE)
	assert_eq([menu.page, menu.heading()], [&"quit", "Quit the game?"], "Quit goes to the question")
	assert_eq([menu.index, menu.rows()[menu.index].label], [0, "Cancel"], "Cancel is selected on arrival")
	assert_eq(asked, [], "nothing is asked yet")
	menu.press(C.BACK)
	assert_eq(menu.page, &"root", "Back returns")
	menu.press(C.CHOOSE) if menu.index == 1 else null
	menu.show_page(&"quit")
	menu.press(C.CHOOSE)
	assert_eq([menu.page, asked], [&"root", []], "Cancel returns, and asks nothing")
	menu.show_page(&"quit")
	menu.press(C.DOWN)
	menu.press(C.CHOOSE)
	assert_eq(asked, [1], "Quit, Down, Choose asks, once")
	menu.web = true
	menu.open()
	assert_eq(menu.rows().map(func(r: Dictionary) -> String: return r.label), ["Resume"], "on the web the Quit row is left out")


func test_the_menu_is_whole_pixels_inside_the_left_column() -> void:
	var main := await _main()
	Game.change(Game.State.PAUSE)
	var column := Rect2i(8, 8, 224, 182)
	for id in [&"root", &"quit"]:
		main.menu.show_page(id)
		var panel := main.menu.panel()
		assert_eq(panel.position.x, 8, "%s: the panel is at x 8" % id)
		assert_true(panel.size.x <= 224, "%s: and at most 224 wide" % id)
		assert_true(column.encloses(panel), "%s: the panel is inside (8,8)..(232,190): %s" % [id, panel])
		for row in main.menu.rows():
			assert_eq(typeof(row.rect), TYPE_RECT2I, "%s: a row's rect is whole pixels" % id)
			assert_eq(typeof(row.text_at), TYPE_VECTOR2I, "%s: and so is its text's place" % id)
			assert_eq(typeof(row.value_at), TYPE_VECTOR2I)
			assert_true(column.encloses(row.rect as Rect2i), "%s: the row %s is in the column" % [id, row.label])
			assert_true(column.has_point(row.text_at), "%s: its text too" % id)
		var layout := main.menu.layout()
		assert_eq(typeof(layout.heading_at), TYPE_VECTOR2I)
		assert_eq(typeof(layout.footer_at), TYPE_VECTOR2I)
		assert_true(column.has_point(layout.footer_at), "%s: the footer is in the column" % id)
	var rows := main.menu.rows()
	for i in rows.size() - 1:
		assert_eq(rows[i + 1].rect.position.y - rows[i].rect.position.y, 10, "rows are 10 px apart")


func test_the_menu_stays_in_the_picture_when_the_window_changes() -> void:
	var main := await _main()
	main.stage.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	Game.change(Game.State.PAUSE)
	var before := main.menu.rows()
	var panel := main.menu.panel()
	for case: Array in [[Vector2(640, 360), 1], [Vector2(1280, 720), 2], [Vector2(1000, 700), 1], [Vector2(500, 300), 1]]:
		main.stage.size = case[0]
		await frames(2)
		assert_eq(main.menu.rows(), before, "%s: the rows are where they were" % case[0])
		assert_eq(main.menu.panel(), panel, "%s: so is the panel" % case[0])
		assert_eq(main.stage.hud.size, Vector2i(640, 360), "%s: the picture is 640x360" % case[0])
		var scale := PixelStage.scale_for(Vector2i(case[0]))
		assert_eq(scale, case[1], "%s: at x%d" % [case[0], case[1]])
		assert_eq(PixelStage.layout(Vector2i(case[0])).size, Vector2i(640, 360) * scale)
		assert_eq(main.menu.size, Vector2(640, 360), "%s: the menu fills the picture" % case[0])
		assert_true(main.menu.is_open, "%s: and is still open" % case[0])


func test_f11_while_paused_switches_the_window_and_keeps_the_menu_open() -> void:
	var main := await _main()
	var window := Window.new()
	window.mode = Window.MODE_FULLSCREEN
	main.window = window
	Game.change(Game.State.PAUSE)
	_push_key(KEY_F11)
	assert_eq([window.mode, window.size], [Window.MODE_WINDOWED, Vector2i(1280, 720)], "F11 switches the window")
	assert_true(main.menu.is_open, "the menu is still open")
	assert_eq([main.menu.page, main.menu.index], [&"root", 0], "where it was")
	assert_eq(Game.state, Game.State.PAUSE)
	window.free()


func test_nothing_but_the_menu_moves_while_it_is_open() -> void:
	var main := await _main(false)
	await frames(30)
	Game.change(Game.State.PAUSE)
	var foes := main.arena().enemies()
	var player := main.player
	var seen := func() -> Array:
		return [player.frame, foes.map(func(f: Actor) -> int: return f.frame), main.camera_rig.trauma, Game.play_frames, player.global_position]
	var before: Array = seen.call()
	main.menu.press(C.DOWN)
	await frames(60)
	assert_eq(seen.call(), before, "the player, the foes, the camera and the play clock stand still for 60 frames")
	assert_true(main.menu.is_open)


func test_debug_keys_do_nothing_while_paused() -> void:
	var main := await _main()
	await frames(2)
	var region := main.region
	var arena := main.arena()
	var foes := _foes(main)
	var wave := arena.wave
	Game.change(Game.State.PAUSE)
	for code in [KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9]:
		_push_key(code)
		assert_eq(main.region, region, "F%d: the same region" % (code - KEY_F1 + 1))
		assert_eq(_foes(main), foes, "F%d: the same foes" % (code - KEY_F1 + 1))
		assert_eq(arena.wave, wave, "F%d: the arena untouched" % (code - KEY_F1 + 1))
	assert_eq(main.menu.index, 0, "and the menu did not move")
	var hints := main.hud.hints_visible
	_push_key(KEY_F1)
	assert_eq(main.hud.hints_visible, not hints, "F1 still works")
	var look := main.look_on
	_push_key(KEY_F4)
	assert_eq(main.look_on, not look, "F4 still works")
	Game.change(Game.State.PLAY)
	_push_key(KEY_F6)
	assert_eq(_foes(main), foes + 1, "playing, F6 spawns a foe as before")


func test_the_press_that_opens_the_menu_does_not_navigate_it() -> void:
	var main := await _main()
	for pad in [false, true]:
		Game.reset()
		Game.change(Game.State.PLAY)
		if pad:
			_pad(JOY_BUTTON_START)
		else:
			_key(KEY_ESCAPE)
		assert_eq(Game.state, Game.State.PAUSE, "the press opens it (pad %s)" % pad)
		assert_eq([main.menu.page, main.menu.index], [&"root", 0], "on the first row (pad %s)" % pad)
		await frames(3)
		assert_true(main.menu.is_open, "and still open 3 frames later (pad %s)" % pad)
		assert_eq([main.menu.page, main.menu.index], [&"root", 0], "still on the first row (pad %s)" % pad)
		if pad:
			_pad(JOY_BUTTON_START, false)
		else:
			_key(KEY_ESCAPE, false)
		assert_true(main.menu.is_open, "its release changes nothing (pad %s)" % pad)
		assert_eq([main.menu.page, main.menu.index], [&"root", 0])
		Game.change(Game.State.PLAY)


# --- presses that do not leak ---

func test_the_press_that_closes_the_menu_never_reaches_the_fight() -> void:
	# Each closes the menu with the press named (the left mouse button is held first and Esc closes: it is held across the close).
	# `acts` is the gameplay action the button is, which must be dead while it is held.
	var cases := [
		{name = "Space", down = func() -> void: _key(KEY_SPACE), up = func() -> void: _key(KEY_SPACE, false), acts = &"dodge"},
		{name = "Enter", down = func() -> void: _key(KEY_ENTER), up = func() -> void: _key(KEY_ENTER, false), acts = &""},
		{name = "Esc", down = func() -> void: _key(KEY_ESCAPE), up = func() -> void: _key(KEY_ESCAPE, false), acts = &"menu"},
		{name = "pad A", down = func() -> void: _pad(JOY_BUTTON_A), up = func() -> void: _pad(JOY_BUTTON_A, false), acts = &"dodge"},
		{name = "pad B", down = func() -> void: _pad(JOY_BUTTON_B), up = func() -> void: _pad(JOY_BUTTON_B, false), acts = &""},
		{name = "pad Start", down = func() -> void: _pad(JOY_BUTTON_START), up = func() -> void: _pad(JOY_BUTTON_START, false), acts = &"menu"},
		{name = "left mouse button", before = func() -> void: _mouse(), down = func() -> void: _key(KEY_ESCAPE), up = func() -> void: _mouse(false), acts = &"palm"},
	]
	for one: Dictionary in cases:
		var main := await _main()
		var started := _watch(main.player)
		Game.change(Game.State.PAUSE)
		if one.has("before"):
			(one.before as Callable).call()
		(one.down as Callable).call()
		assert_eq(Game.state, Game.State.PLAY, "%s closes the menu" % one.name)
		assert_eq(Inputs.pressed_this_frame(), [], "%s: no press on the frame of the close" % one.name)
		await frames(1)
		assert_eq(Inputs.pressed_this_frame(), [], "%s: none on the second frame" % one.name)
		await frames(8)
		assert_eq(started, [], "%s: Abarax starts nothing in 10 frames" % one.name)
		if one.acts != &"":
			assert_false(Inputs.held(one.acts), "%s: %s is dead while it is held across the close" % [one.name, one.acts])
			assert_false(Inputs.pressed_this_frame().has(one.acts), "%s: and is no press" % one.name)
		(one.up as Callable).call()
		if one.name == "left mouse button":
			_key(KEY_ESCAPE, false)
		await frames(1)
		assert_eq(started, [], "%s: nor when it is let go" % one.name)
		main.free()
		Game.reset()


func test_a_deliberate_press_a_few_frames_after_the_close_still_acts() -> void:
	var main := await _main()
	var started := _watch(main.player)
	Game.change(Game.State.PAUSE)
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PLAY)
	await frames(4)
	Input.action_press(&"palm")
	await frames(3)
	Input.action_release(&"palm")
	assert_eq(started.map(func(s: Array) -> StringName: return s[0]).slice(0, 1), [&"palm_jab"], "4 frames after the close a palm press starts the jab")


func test_a_held_move_key_carries_on_through_the_close() -> void:
	var main := await _main()
	var started := _watch(main.player)
	Game.change(Game.State.PAUSE)
	_key(KEY_W)
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, false)
	assert_eq(Game.state, Game.State.PLAY)
	var from := main.player.global_position
	await frames(20)
	assert_true(main.player.global_position.distance_to(from) > 0.3, "W held across the close: he walks")
	var ids: Array = started.map(func(s: Array) -> String: return String(s[0]))
	assert_eq(ids.filter(func(id: String) -> bool: return id.begins_with("sway_") or id.begins_with("dash_step") or id.begins_with("duck_")), [], "no sway, duck or dash-step: %s" % [ids])


# --- a pause that gives the fight back ---
# Each test plays a fight twice, once paused at an awkward instant for a long time and once never paused, and compares what the
# fighters, the effects and the clocks are at the instant of the pause, just after it, and at a later play frame.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE := "res://data/actors/knuckle_1.tres"
const DRUMMER := "res://data/actors/knuckle_drummer.tres"
const HEAVY := "res://data/actors/knuckle_heavy.tres"
const FINISHER := "res://data/pairs/finisher_open_hand.tres"
const LONG_PAUSE := 200


# Pauses the game for `n` physics frames, and plays on.
func _pause_for(n: int) -> void:
	if Game.state != Game.State.PLAY:
		Game.reset()
		Game.change(Game.State.PLAY)
	Game.change(Game.State.PAUSE)
	await frames(n)
	Game.change(Game.State.PLAY)


# What the fighters, the slow-down, the afterimages and the effects of `run` are now.
func _snap(run: Dictionary) -> Dictionary:
	var out := {}
	for who in ["a", "b"]:
		var x: Actor = run[who]
		out[who] = {
			frame = x.frame, buffer = x.buffer_frame, frozen = x.frozen, at = x.global_position, hp = x.stats.hp,
			posture = x.stats.posture, stamina = x.stats.stamina, dead = x.dead, paired = x.paired_with != null,
			move = x.runner.current.id if x.runner.current != null else &"", time = x.runner.time,
			aura = x.rig.aura_active(), level = x.rig.aura_level(),
		}
	out["slow"] = [Melee.slowed(), Melee._slow_next]
	out["images"] = get_tree().get_nodes_in_group(Afterimage.GROUP).map(func(n: Node) -> Array: return [n.left, n.alpha()])
	out["fx"] = get_tree().get_nodes_in_group(ActorFx.GROUP).size()
	out["rings"] = get_tree().get_nodes_in_group(&"slam_ring").map(func(n: Node) -> Array: return [n.is_in_group(&"slam_wave"), n.shown_radius()])
	return out


# Plays the fight `build` makes until `ready` says so, pauses for `held` frames if it is above 0 (taking what the fight is
# before and after), then plays until `a` has lived `until` frames. Returns {before, after (when paused), end}.
func _run(build: Callable, ready: Callable, held: int, until: int) -> Dictionary:
	Melee.slow(0, 1.0)
	var run: Dictionary = build.call()
	var a: Actor = run["a"]
	var limit := 600
	while not ready.call(run) and limit > 0:
		await frames(1)
		limit -= 1
	var out := {before = _snap(run), a_frame = a.frame}
	if held > 0:
		await _pause_for(held)
		out["after"] = _snap(run)
	while a.frame < until:
		await frames(1)
	out["end"] = _snap(run)
	(run["arena"] as Node).free()
	Melee.slow(0, 1.0)
	return out


# Asserts that pausing at the instant `ready` names, for LONG_PAUSE frames, changes nothing of what _snap says, against a control
# run that is never paused, at the pause, after it and `later` frames on. Returns the paused run's snapshot at the pause.
func _gives_back(why: String, build: Callable, ready: Callable, later := 40) -> Dictionary:
	var first: Dictionary = await _run(build, ready, 0, 0)
	var until: int = first.a_frame + later
	var control: Dictionary = await _run(build, ready, 0, until)
	var paused: Dictionary = await _run(build, ready, LONG_PAUSE, until)
	assert_eq(paused.a_frame, control.a_frame, "%s: the same instant" % why)
	assert_eq(_differences(paused.before, control.before), [], "%s: the control is where the pause came" % why)
	assert_eq(_differences(paused.after, paused.before), [], "%s: the pause changed nothing" % why)
	assert_eq(_differences(paused.end, control.end), [], "%s: and %d play frames on it is the control's" % [why, later])
	return paused.before


# What differs between two snapshots, as "path: got vs wanted".
func _differences(got: Variant, wanted: Variant, path := "") -> Array:
	var out := []
	if got is Dictionary and wanted is Dictionary:
		for key in wanted:
			out.append_array(_differences(got.get(key), wanted[key], "%s/%s" % [path, key]))
	elif typeof(got) != typeof(wanted) or got != wanted:
		out.append("%s: %s vs %s" % [path, got, wanted])
	return out


func _fighters(b_def: ActorDef, gap := 1.0, a_steps := [], b_steps := []) -> Callable:
	return func() -> Dictionary:
		return Duel.make(self, a_steps, b_steps, gap, b_def)


func _enemy_of(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.team = ActorDef.Team.ENEMY
	return def


func test_pause_gives_back_a_trade_mid_hit_stop() -> void:
	var build := func() -> Dictionary:
		var run := Duel.make(self, [{"frames": 400}], [{"frames": 400}], 1.3, _enemy_of(KNUCKLE))
		(run["b"] as Actor).runner.start(Registry.fetch(&"moves", &"knuckle_hook") as MoveData)
		return run
	var ready := func(run: Dictionary) -> bool: return (run["a"] as Actor).frozen == 3
	var seen := await _gives_back("a blow mid hit-stop", build, ready)
	assert_eq([seen.a.frozen, seen.b.frozen], [3, 3], "paused with 3 frames of the hit-stop left, on both")
	assert_true(seen.a.hp < 100.0, "the blow landed")


func test_pause_gives_back_a_slow_down_mid_way() -> void:
	var build := func() -> Dictionary:
		var run := Duel.make(self, [{"frames": 400}], [{"frames": 400}], 3.0)
		Melee.slow(12, 0.4)
		return run
	var started := {"frame": -1}
	var ready := func(run: Dictionary) -> bool:
		if started.frame < 0:
			started.frame = (run["a"] as Actor).frame
		return (run["a"] as Actor).frame >= started.frame + 5
	var seen := await _gives_back("a slow-down after 5 of its 12 frames", build, ready)
	assert_eq(seen.slow[0], true, "it was still slowed when paused")
	assert_true(seen.slow[1] > 0 and seen.slow[1] < 12, "part of the way: %d of 12 decided" % seen.slow[1])


func _finisher_build() -> Dictionary:
	var foe := Duel.def(ActorDef.Team.ENEMY, 5.0)
	foe.max_hp = 60.0
	var run := Duel.make(self, [{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 300}], [], 1.0, foe)
	track(PostureBreaker.make(run["a"], run["b"]))
	return run


func _grab_build() -> Dictionary:
	var pair := (load(FINISHER) as PairedMove).duplicate() as PairedMove
	pair.id = &"test_pair"
	pair.moment = &"grab"
	var grabber_def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	grabber_def.grab_pair = pair
	var arena := TestArena.make(self)
	var grabber := TestArena.spawn(arena, grabber_def, ScriptBrain.new([]), Vector3.ZERO, "Grabber")
	grabber.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var abarax := TestArena.spawn(arena, load(ABARAX) as ActorDef, ScriptBrain.new([]), Vector3(0, 0, 1), "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1)))
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var grab := jab.duplicate() as MoveData
	grab.id = &"grab_jab"
	var palm := (jab.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	palm.perilous = HitProfile.Perilous.GRAB
	grab.hits = {&"palm": palm}
	grabber.runner.start(grab)
	return {"arena": arena, "a": grabber, "b": abarax}


# The pair of `run` has been going on for 10 of the lead's frames.
func _ten_into_the_pair(run: Dictionary) -> bool:
	var a: Actor = run["a"]
	if a.paired_with == null:
		run["began"] = -1
		return false
	if not run.has("began") or run["began"] < 0:
		run["began"] = a.frame
	return a.frame >= run["began"] + 10


func test_pause_gives_back_a_finisher_pair_and_a_grab() -> void:
	# The pair is played to its end after the pause, and ends on the same play frame as in a control run.
	var pairs := {}
	for case: Array in [["the finisher", _finisher_build], ["a grab", _grab_build]]:
		var ready := func(run: Dictionary) -> bool: return _ten_into_the_pair(run)
		var seen := await _gives_back(case[0], case[1], ready, 120)
		assert_true(seen.a.paired and seen.b.paired, "%s: paused with the pair going" % case[0])
		assert_eq(seen.b.move != &"", true)
		pairs[case[0]] = seen


func test_pause_while_dead_keeps_get_up_counting_play_frames() -> void:
	# Abarax dies; a second in, the game is paused for five; the arena's reset (three seconds after the death, with his getup)
	# comes after the two that were left, not at once behind the menu.
	var took := []
	for pause_it: bool in [false, true]:
		var main := await _main(false)
		var player := main.player
		player.die()
		var from := Game.play_frames
		assert_true(player.dead)
		if pause_it:
			await frames(60)
			await _pause_for(300)
			assert_true(player.dead, "five seconds paused: he is still lying there")
		while player.dead and Game.play_frames - from < 600:
			await frames(1)
		took.append(Game.play_frames - from)
		main.free()
		Game.reset()
	assert_eq(took[1], took[0], "Get Up begins on the same play frame after the pause as without it")
	assert_true(took[0] >= 175 and took[0] <= 190, "which is three seconds of play after the death (%d frames)" % took[0])


func _hit_result() -> HitResult:
	var r := HitResult.new()
	r.outcome = HitResult.Outcome.HIT
	return r


func _hit_event(foe: Actor) -> HitEvent:
	var e := HitEvent.new()
	e.target = foe
	e.profile = HitProfile.new()
	e.point = foe.global_position + Vector3.UP
	return e


func test_the_huds_clocks_count_play_frames() -> void:
	var main := await _main()
	var hud := main.hud
	var foe := main.arena().enemies()[0]
	foe.got_hit.emit(_hit_result(), _hit_event(foe))
	hud._on_refused(null, &"stamina")
	assert_true(hud.stamina_blink_on(), "the stamina bar blinks at the refusal")
	await frames(10)
	assert_eq(hud.foe_bars().size(), 1, "the foe's bars show after the blow")
	var played := Game.play_frames
	var lit_at_pause := hud.stamina_blink_on()
	Game.change(Game.State.PAUSE)
	await frames(300)
	assert_eq(Game.play_frames, played, "the play clock did not run in the pause")
	assert_eq(hud.foe_bars().size(), 1, "a foe hit 10 play frames ago still shows its bars after 300 paused frames")
	assert_eq(hud.stamina_blink_on(), lit_at_pause, "the blink is where it was")
	Game.change(Game.State.PLAY)
	await frames(165)
	assert_eq(hud.foe_bars().size(), 1, "175 play frames after the blow it is still there")
	await frames(15)
	assert_eq(hud.foe_bars().size(), 0, "and gone after three seconds of play")
	# The blink goes on from its phase: 2 frames lit, 2 dark, twice (Hud.stamina_blink_on from the refusal's frame 0).
	hud._refused_at = -1000
	hud._on_refused(null, &"stamina")
	await frames(1)
	var seen: Array[bool] = [hud.stamina_blink_on()]
	Game.change(Game.State.PAUSE)
	await frames(300)
	seen.append(hud.stamina_blink_on())
	Game.change(Game.State.PLAY)
	for i in 8:
		await frames(1)
		seen.append(hud.stamina_blink_on())
	assert_eq(seen, [true, true, false, false, true, true, false, false, false, false] as Array[bool], "the blink goes on from its phase after the pause")


func test_a_spark_alive_at_the_pause_is_still_there_after_a_long_pause() -> void:
	var run := Duel.make(self, [{"frames": 600}], [], 6.0)
	var a: Actor = run["a"]
	var def := Registry.fetch(&"fx", &"hit_spark") as FxDef
	var kept := def.lifetime
	def.lifetime = 0.3
	var spark := (a.get_node("ActorFx") as ActorFx).show_fx(&"hit_spark")
	def.lifetime = kept
	assert_true(is_instance_valid(spark) and spark.is_inside_tree(), "the effect is shown")
	await frames(6)
	assert_true(is_instance_valid(spark), "alive at 0.1 s")
	await _pause_for(120)
	assert_true(is_instance_valid(spark) and not spark.is_queued_for_deletion(), "and still there after 2 s paused")
	await frames(6)
	assert_true(is_instance_valid(spark), "0.1 s of play after the resume: there")
	await frames(16)
	assert_false(is_instance_valid(spark) and not spark.is_queued_for_deletion(), "gone 0.2 s of play after the resume")
	(run["arena"] as Node).free()


# --- the instants the game has gained since the plan was written ---

# A foe that throws the string at `target`, as the test_drummer's Strike does: palm to start it, and again as each window opens.
class Strike extends Brain:
	var target: Actor
	var _frame := 0
	var _left := 7

	func _init(foe: Actor) -> void:
		target = foe

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		_frame += 1
		intent.aim_target = target.global_position
		intent.face_target = target.global_position
		intent.warp = true
		if _frame == 1:
			intent.pressed.append(&"palm")
		elif actor.frozen == 0 and actor.runner.window.has(&"palm") and _left > 1:
			intent.pressed.append(&"palm")
			_left -= 1
		return intent


func test_pause_gives_back_the_drummers_string_between_its_fourth_and_fifth_blows() -> void:
	# The Drummer (b) throws its string at a dummy beside it while Abarax (a), his chain at Quick, stands with the rim breathing.
	var build := func() -> Dictionary:
		var run := Duel.make(self, [{"frames": 900}], [], 6.0, _enemy_of(DRUMMER))
		var a: Actor = run["a"]
		var b: Actor = run["b"]
		Duel.without_slow(run)
		# Quick is held for the whole of the string (a chain's own timeout is 90 frames, and this string is longer): a tuning of its own.
		a.chain._tuning = (a.chain._tuning as ChainTuning).duplicate() as ChainTuning
		a.chain._tuning.timeout_frames = 100000
		for i in 3:
			a.chain.link(false, a.buffer_frame)
		var dummy := TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.PLAYER, 50.0), Brain.new(), Vector3(0, 0, 4.7), "Dummy")
		dummy.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 0, 4.7)))
		b.set_brain(Strike.new(dummy))
		return run
	var ready := func(run: Dictionary) -> bool:
		var b: Actor = run["b"]
		if b.runner.current == null or b.runner.current.id != &"drum_5":
			run["at5"] = -1
			return false
		if not run.has("at5") or run["at5"] < 0:
			run["at5"] = b.frame
		return b.frame >= run["at5"] + 5
	var seen := await _gives_back("the Drummer's string, between blows 4 and 5", build, ready, 60)
	assert_eq(seen.b.move, &"drum_5", "paused in the fifth move, before its blow")
	assert_true(seen.a.aura, "the chain's rim is lit on Abarax")
	assert_true(seen.a.level > 0.0 and seen.a.level < 1.0, "and breathing (%.2f)" % seen.a.level)


func test_pause_gives_back_the_heavys_slam_with_its_ring_on_the_ground() -> void:
	# Abarax stands well off, so the slam falls on nothing; the warning ring is on the ground from the tell to the blow, and a
	# wave goes out at it. All of it is bound to the move, and must be there after a long pause and end when it would have.
	var build := func() -> Dictionary:
		var run := Duel.make(self, [{"frames": 600}], [{"frames": 1, "press": [&"gift"]}, {"frames": 600}], 5.0, _enemy_of(HEAVY))
		return run
	var ready := func(run: Dictionary) -> bool: return (run["b"] as Actor).frame >= 24
	var seen := await _gives_back("the heavy's slam with its warning ring", build, ready, 90)
	assert_eq(seen.b.move, &"heavy_slam", "paused in the slam")
	var warnings: Array = seen.rings.filter(func(r: Array) -> bool: return not r[0])
	assert_eq(warnings.size(), 1, "the warning ring is on the ground at the pause")


func test_pause_gives_back_an_afterimage_half_faded() -> void:
	var build := func() -> Dictionary:
		var run := Duel.make(self, [{"frames": 600}], [], 6.0)
		var a: Actor = run["a"]
		Afterimage.spawn(a.rig, Color(1, 1, 1, 0.6), 12, {}, a)
		return run
	var ready := func(run: Dictionary) -> bool:
		var images := get_tree().get_nodes_in_group(Afterimage.GROUP)
		return not images.is_empty() and images[0].left <= 6
	var seen := await _gives_back("an afterimage half faded", build, ready, 20)
	assert_eq(seen.images.size(), 1, "one afterimage at the pause")
	assert_eq(seen.images[0][0], 6, "with 6 of its 12 frames left")


# --- a hold that was down before the pause is still down after it ---

# Abarax in Main (his own PlayerBrain, on the real Input) holds `action` from the start; the game is paused for `held` frames once
# he has lived `pause_at` frames (`during` is called in the pause, if given) and resumed the way the menu resumes it (Main
# quarantines what the pause brought in); he goes on to `until`. With `jab`, the foe stands a pace off and throws its jab at him
# on his frame 6. Returns what the fight saw.
func _hold_run(action: StringName, pause_at: int, held: int, until: int, jab := false, during := Callable()) -> Dictionary:
	Melee.slow(0, 1.0)
	var main := await _main()
	var a := main.player
	var seen := {"charged": [], "started": [], "outcomes": [], "guarding": []}
	if jab:
		# On the pad a held guard turns him to the nearest foe. On the keyboard and mouse he would face the cursor, which is
		# wherever the window's pointer happens to be: under a real window (the render suite) that is behind him, and the blow
		# comes from outside the guard's arc.
		Inputs._device = Inputs.Device.GAMEPAD
		var foe := main.arena().enemies()[0]
		var at := a.global_position + a.facing() * 0.9
		foe.place(Transform3D(Basis(Vector3.UP, a.locomotion.facing_yaw + PI), at))
	a.runner.charged.connect(func(_m: MoveData) -> void: seen["charged"].append(a.frame))
	a.runner.move_started.connect(func(m: MoveData) -> void: seen["started"].append([m.id, a.frame]))
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: seen["outcomes"].append([HitResult.Outcome.keys()[r.outcome], a.frame]))
	var start := a.frame
	Input.action_press(action)
	while a.frame < start + pause_at:
		if jab and a.frame == start + 6:
			main.arena().enemies()[0].runner.start(Registry.fetch(&"moves", &"knuckle_jab") as MoveData)
		await frames(1)
	if held > 0:
		Game.change(Game.State.PAUSE)
		await frames(3)
		if during.is_valid():
			during.call()
		await frames(held)
		Game.change(Game.State.PLAY)
		seen["held_at_resume"] = Inputs.held(action)
		seen["charging_at_resume"] = a.runner.charging
	while a.frame < start + until:
		await frames(1)
		seen["guarding"].append(a.guarding)
	Input.action_release(action)
	main.free()
	Melee.slow(0, 1.0)
	return seen


func test_a_charge_held_through_the_pause_goes_on_from_where_it_was() -> void:
	var control := await _hold_run(&"heavy", 30, 0, 80)
	var paused := await _hold_run(&"heavy", 30, 200, 80)
	assert_eq(paused["held_at_resume"], true, "the heavy button is still held at the resume")
	assert_eq(paused["charging_at_resume"], true, "and the charge is going on")
	assert_eq(control["charged"].size(), 1, "the control charged once: %s" % [control["charged"]])
	assert_eq(paused["charged"], control["charged"], "the paused charge is full on the same play frame")
	assert_eq(paused["started"], control["started"], "one heavy, no uncharged swing at the resume")


func test_a_guard_held_through_the_pause_is_still_up_and_takes_the_blow() -> void:
	# The foe's jab lands after the resume; the guard held from before is up for it, as in a control that never paused.
	var control := await _hold_run(&"guard", 12, 0, 45, true)
	var paused := await _hold_run(&"guard", 12, 200, 45, true)
	assert_eq(paused["held_at_resume"], true, "guard is still held at the resume")
	assert_eq(control["outcomes"].map(func(o: Array) -> String: return o[0]).slice(0, 1), ["GUARDED"], "the control guards the blow: %s" % [control["outcomes"]])
	assert_eq(paused["outcomes"], control["outcomes"], "and so does the paused fight, on the same frame")
	assert_eq(paused["guarding"], control["guarding"], "the stance is up and down on the same frames")


func test_a_hold_let_go_during_the_pause_is_up_at_the_resume() -> void:
	var seen := await _hold_run(&"guard", 15, 30, 30, false, func() -> void: Input.action_release(&"guard"))
	assert_eq(seen["held_at_resume"], false, "guard let go in the pause is not held at the resume")
	assert_eq(seen["guarding"].slice(-1), [false], "and the guard is down")


# --- the quarantine's second half ---

func test_a_tap_on_the_frame_of_the_close_does_not_act_and_the_same_tap_two_frames_later_does() -> void:
	var main := await _main()
	var started := _watch(main.player)
	Game.change(Game.State.PAUSE)
	Game.change(Game.State.PLAY)
	Input.action_press(&"palm")
	await frames(1)
	Input.action_release(&"palm")
	await frames(10)
	assert_eq(started, [], "a palm tapped on the very frame of the close does nothing")
	Game.change(Game.State.PAUSE)
	Game.change(Game.State.PLAY)
	await frames(2)
	Input.action_press(&"palm")
	await frames(1)
	Input.action_release(&"palm")
	await frames(3)
	assert_eq(started.map(func(s: Array) -> StringName: return s[0]).slice(0, 1), [&"palm_jab"], "the same tap two frames after the close starts the jab")


func test_a_button_held_across_the_close_acts_again_when_let_go_and_pressed() -> void:
	var main := await _main()
	var started := _watch(main.player)
	Game.change(Game.State.PAUSE)
	_key(KEY_SPACE)
	assert_eq(Game.state, Game.State.PLAY, "Space on Resume closes the menu")
	await frames(6)
	assert_false(Inputs.held(&"dodge"), "held across the close, the dash-step button is dead")
	_key(KEY_SPACE, false)
	await frames(3)
	assert_eq(started, [], "and nothing started")
	_key(KEY_SPACE)
	await frames(3)
	assert_true(Inputs.held(&"dodge"), "pressed again, it is held")
	assert_true(started.size() > 0, "and it acts: %s" % [started])


func test_a_stick_already_pushed_when_the_menu_opens_moves_nothing_through_open() -> void:
	var menu := track(Menu.new()) as Menu
	var push := InputEventJoypadMotion.new()
	push.axis = JOY_AXIS_LEFT_Y
	push.axis_value = -0.9
	Input.parse_input_event(push)
	Input.flush_buffered_events()
	menu.open()
	assert_eq(menu.index, 0)
	menu.handle(push)
	assert_eq(menu.index, 0, "the stick held as the menu opened moves nothing")
	var rest := InputEventJoypadMotion.new()
	rest.axis = JOY_AXIS_LEFT_Y
	rest.axis_value = 0.0
	menu.handle(rest)
	menu.handle(push)
	assert_eq(menu.index, menu.rows().size() - 1, "let go and pushed again it moves (up from the first wraps to the last)")
	Input.parse_input_event(rest)
	Input.flush_buffered_events()


# --- small things ---

func test_the_refusal_cue_gate_counts_play_frames() -> void:
	var main := await _main()
	var refuse := func() -> void:
		main.player.stats.spend_stamina(1000.0)
		main.player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	refuse.call()
	assert_true(Sfx.last_played().has(&"stamina_refused"), "the first refused press sounds the cue")
	Game.change(Game.State.PAUSE)
	await frames(300)
	Game.change(Game.State.PLAY)
	await frames(3)
	main.player.runner.stop()
	refuse.call()
	assert_false(Sfx.last_played().has(&"stamina_refused"), "a refused press 3 play frames after a 300-frame pause is still inside the gate")


func test_the_window_cannot_be_smaller_than_the_picture() -> void:
	Game.reset()
	var window := Window.new()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.window = window
	track(main)
	assert_eq(window.min_size, Vector2i(640, 360), "the picture's own size")
	window.free()


func test_main_quits_when_the_menu_asks_and_gives_the_menu_its_window() -> void:
	Game.reset()
	var window := Window.new()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.window = window
	var quits := []
	main.quit_game = func() -> void: quits.append(1)
	track(main)
	assert_eq(main.menu.window, window, "the menu has Main's window")
	main.menu.quit_requested.emit()
	assert_eq(quits, [1], "Main quits when the menu asks, once")
	window.free()


func test_the_menu_follows_settings_on_web_and_the_footer_follows_the_device() -> void:
	Settings.on_web = true
	var web := Menu.new()
	assert_true(web.web, "on the web the menu is the web's")
	web.free()
	Settings.on_web = false
	var home := Menu.new()
	assert_false(home.web, "off it, not")
	home.free()
	Settings.on_web = OS.has_feature("web")
	var menu := track(Menu.new()) as Menu
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	assert_eq(menu.footer(), "Enter: choose   Esc: back")
	Inputs._device = Inputs.Device.GAMEPAD
	menu.pad_present = func() -> bool: return true
	assert_eq(menu.footer(), "A: choose   B: back", "a pad in hand and connected")
	menu.pad_present = func() -> bool: return false
	assert_eq(menu.footer(), "Enter: choose   Esc: back", "a pad in hand but unplugged: the keyboard's")
