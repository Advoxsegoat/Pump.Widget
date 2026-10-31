extends TestCase
## The main scene (main/main.tscn): it boots into PLAY with Abarax at the courtyard's spawn, the camera on him
## and the screen look on; F3 shows the debug overlay, F4 turns the look off, the menu button (Esc) pauses;
## and --selftest runs a scripted circuit of the courtyard and exits 0 when nothing logged an error.

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
	assert_ne(stage.settings, null, "the look is on")
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
	assert_ne(stage.settings, null)
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


func test_escape_is_the_menu_button() -> void:
	var main := _main()
	_press_key(KEY_ESCAPE)
	assert_eq(Game.state, Game.State.PAUSE, "Esc pauses")
	_press_key(KEY_ESCAPE)
	assert_eq(Game.state, Game.State.PLAY, "Esc again plays")
	assert_ne(main, null)


# The self-test's circuit, here in this process: in 600 frames Abarax walks to the fountain, rolls, jabs and
# climbs the stairs, ending at StairsTop.
func test_selftest_circuit_walks_rolls_jabs_and_climbs() -> void:
	var main := _main()
	var player := _player(main)
	var started: Array[StringName] = []
	player.runner.move_started.connect(func(move: MoveData) -> void: started.append(move.id))
	player.set_brain(ScriptBrain.new(main.selftest_circuit()))
	var closest_to_fountain := INF
	for i in Main.SELFTEST_FRAMES:
		await frames(1)
		closest_to_fountain = minf(closest_to_fountain, Vector2(player.global_position.x, player.global_position.z).length())
	var top := (_region(main).get_node("StairsTop") as Marker3D).global_position
	assert_true(closest_to_fountain < 5.0, "he comes to the fountain (%.2f m from its centre at the closest)" % closest_to_fountain)
	assert_eq(started, [&"dodge_roll", &"palm_jab"] as Array[StringName], "he rolls, then jabs")
	assert_true(player.global_position.distance_to(top) < 1.0, "he ends at StairsTop (%.2f m off, at %s)" % [player.global_position.distance_to(top), player.global_position])


# `godot -- --selftest` on the real project: the main scene runs its circuit for 600 frames and quits 0.
func test_selftest_exits_zero() -> void:
	var argv := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--", "--selftest"])
	var output := []
	var code := OS.execute(OS.get_executable_path(), argv, output, true)
	var text := str(output[0])
	assert_eq(code, 0, text)
	assert_true(text.contains("selftest: 600 frames, 0 errors"), text)
