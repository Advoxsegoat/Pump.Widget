extends TestCase
## The main scene (main/main.tscn): it boots into PLAY with Abarax at the courtyard's spawn, the camera on him
## and the screen look on; F3 shows the debug overlay, F4 turns the look off, the menu button (Esc) pauses and
## "Paused" shows while it is paused. F11 and Alt+Enter are tests/main/test_window_toggle.gd's.
## The self-test (--selftest) is tests/main/test_selftest.gd's.

const MAIN := "res://main/main.tscn"
const DEFAULT_SETTINGS := "res://data/render/default_settings.tres"


func after_each() -> void:
	Game.reset()


func _main() -> Main:
	Game.reset()
	return track((load(MAIN) as PackedScene).instantiate()) as Main


func _player(main: Main) -> Actor:
	return main.get_node("PixelStage/World/Player") as Actor


func _region(main: Main) -> Region:
	return main.get_node("PixelStage/World/Region") as Region


func _rig(main: Main) -> CameraRig:
	return main.get_node("PixelStage/World/CameraRig") as CameraRig


func _stage(main: Main) -> PixelStage:
	return main.get_node("PixelStage") as PixelStage


func _press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		get_viewport().push_input(event)


func _press_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)


func test_main_boots_into_play_with_player_and_camera() -> void:
	var main := _main()
	assert_eq(Game.state, Game.State.PLAY, "the game is in PLAY")
	var player := _player(main)
	var region := _region(main)
	var rig := _rig(main)
	assert_true(player is Actor, "a Player actor")
	assert_eq(player.def, load("res://data/actors/abarax.tres"), "the player is Abarax")
	var spawn := region.spawn()
	assert_vec_near(player.global_position, spawn.origin, 1e-4, "the player stands at the spawn")
	assert_near(player.locomotion.facing_yaw, spawn.basis.get_euler().y, 1e-4, "facing the spawn's way")
	assert_true(player.brain is PlayerBrain, "the player's brain is a PlayerBrain")
	if player.brain is PlayerBrain:
		assert_near((player.brain as PlayerBrain).view_yaw, rig.yaw(), 1e-6, "turned by the camera's yaw")
	assert_eq(rig.target, player, "the camera follows the player")
	assert_eq(rig.stage, _stage(main), "the camera reports to the stage")
	assert_vec_near(rig.global_position, player.global_position, 1e-3, "the camera starts on the player")
	var stage := _stage(main)
	assert_true(stage.settings != null, "the look is on")
	if stage.settings != null:
		assert_eq(stage.settings.resource_path, DEFAULT_SETTINGS, "the default look")
	assert_eq(stage.grade, region.grade, "in the region's grade")
	var overlay := main.get_node("DebugOverlay") as CanvasLayer
	assert_false(overlay.visible, "the debug overlay starts hidden")
	# Abarax stands and breathes: a few frames on, he is where he was and nothing has fallen.
	await frames(10)
	assert_vec_near(player.global_position, spawn.origin, 0.02, "he stays at the spawn")


func test_f3_toggles_the_debug_overlay() -> void:
	var main := _main()
	var overlay := main.get_node("DebugOverlay") as CanvasLayer
	_press_key(KEY_F3)
	assert_true(overlay.visible, "F3 shows the overlay")
	await frames(2)
	await get_tree().process_frame
	var text := (overlay.get_node("Label") as Label).text
	for part in ["fps", "physics", "move", "speed"]:
		assert_true(text.contains(part), "the overlay shows %s: %s" % [part, text])
	_press_key(KEY_F3)
	assert_false(overlay.visible, "F3 again hides it")


func test_f4_toggles_the_look_off_and_on() -> void:
	var main := _main()
	var stage := _stage(main)
	var on := load(DEFAULT_SETTINGS) as RenderSettings
	_press_key(KEY_F4)
	assert_true(stage.settings != null, "the look is set")
	for strength in [&"outline", &"dof_strength", &"bloom_strength", &"fog_strength", &"grade_strength", &"vignette_strength"]:
		assert_eq(stage.settings.get(strength), 0.0, "F4 turns %s off" % strength)
	assert_eq(stage.grade, _region(main).grade, "the grade stays the region's")
	_press_key(KEY_F4)
	for strength in [&"outline", &"dof_strength", &"bloom_strength", &"fog_strength", &"grade_strength", &"vignette_strength"]:
		assert_eq(stage.settings.get(strength), on.get(strength), "F4 again turns %s back on" % strength)


func test_menu_pauses_and_resumes() -> void:
	var main := _main()
	var player := _player(main)
	_press_action(&"menu")
	assert_eq(Game.state, Game.State.PAUSE, "the menu button pauses")
	assert_true(get_tree().paused, "the tree is paused")
	var frame := player.frame
	await frames(3)
	assert_eq(player.frame, frame, "the player does not tick while paused")
	_press_action(&"menu")
	assert_eq(Game.state, Game.State.PLAY, "pressed again, it plays")
	assert_false(get_tree().paused, "the tree runs")
	await frames(3)
	assert_true(player.frame > frame, "the player ticks again")


func test_paused_shows_while_the_game_is_paused() -> void:
	var main := _main()
	var paused := main.get_node_or_null("PauseLabel") as CanvasLayer
	if paused == null:
		fail("main has a PauseLabel CanvasLayer")
		return
	var label := paused.get_node_or_null("Label") as Label
	if label == null:
		fail("the PauseLabel has a Label")
		return
	assert_eq(label.text, "Paused")
	assert_false(paused.visible, "hidden while playing")
	_press_action(&"menu")
	assert_eq(Game.state, Game.State.PAUSE)
	assert_true(paused.visible, "shown as soon as the menu button pauses")
	assert_true(label.is_visible_in_tree(), "the label shows")
	assert_true(paused.can_process(), "it runs while the tree is paused")
	await frames(2)
	assert_true(paused.visible, "and stays up while paused")
	_press_key(KEY_ESCAPE)
	assert_eq(Game.state, Game.State.PLAY)
	assert_false(paused.visible, "hidden again when the game plays")
	# Whatever else pauses the game (not the menu button) shows it too.
	Game.change(Game.State.PAUSE)
	assert_true(paused.visible, "any move into PAUSE shows it")
	Game.change(Game.State.PLAY)
	assert_false(paused.visible)


func test_escape_is_the_menu_button() -> void:
	_main()
	_press_key(KEY_ESCAPE)
	assert_eq(Game.state, Game.State.PAUSE, "Esc pauses")
	_press_key(KEY_ESCAPE)
	assert_eq(Game.state, Game.State.PLAY, "Esc again plays")
