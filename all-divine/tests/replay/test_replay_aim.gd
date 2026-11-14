extends TestCase
## A recording holds what the player aimed with: on each frame the device that was the aiming one and, on the keyboard and mouse, the
## ground point of the cursor as the brain read it. The point, not the screen position: a replay in a window of another size, with
## the real mouse somewhere else, is the fight recorded. The world is Main (it has the camera the cursor is read through).

const SMALL := Vector2i(640, 360)
const LARGE := Vector2i(1920, 1080)


func after_each() -> void:
	InputFeed.release()
	get_tree().paused = false
	Game.reset()
	await frames(1)


# A PlayerBrain whose mouse is where the test puts it.
class MovingMouse:
	extends PlayerBrain
	var mouse := Vector2.ZERO

	func mouse_position(_actor: Actor) -> Vector2:
		return mouse


# Moves the mouse of `brain` along `places` (screen positions), one every `every` frames, before the brain reads it.
class MouseHand:
	extends Node
	var brain: MovingMouse
	var places: Array
	var every := 20
	var _frame := 0

	func _init(for_brain: MovingMouse, along: Array) -> void:
		brain = for_brain
		places = along
		process_physics_priority = -200

	func _physics_process(_delta: float) -> void:
		brain.mouse = places[mini(_frame / every, places.size() - 1)]
		_frame += 1


# Records `count` frames of `hands` in Main with the window at `size`; with `places`, the player's mouse moves along them as it records.
func _record_fight(hands: Array, count: int, size: Vector2i, places := []) -> InputRecording:
	get_window().size = size
	var game := BotWorld.make(self, 3)
	if not places.is_empty():
		var brain := MovingMouse.new()
		brain.view_yaw = (game.player.brain as PlayerBrain).view_yaw
		game.player.set_brain(brain)
		track(MouseHand.new(brain, places))
	var recorder := track(InputRecorder.new()) as InputRecorder
	recorder.arena = game.arena()
	recorder.hash_every = 20
	recorder.begin(game.region.scene_file_path, 3, 0)
	var driver := track(ScriptedHands.new(hands))
	while recorder.recording().frames.size() < count:
		await frames(1)
	recorder.close()
	recorder.set_physics_process(false)
	var rec := recorder.recording()
	for node: Node in [driver, recorder, game]:
		node.queue_free()
	await frames(2)
	InputFeed.release()
	return rec


# Plays `rec` into a new Main whose window is `size` and whose mouse is somewhere else: [the frame it diverged on or -1, whether it finished].
func _replay_fight(rec: InputRecording, size: Vector2i) -> Array:
	get_window().size = size
	var game := BotWorld.make(self, rec.seed)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(600, 40)
	get_tree().root.push_input(motion)
	var replayer := track(InputReplayer.new()) as InputReplayer
	replayer.arena = game.arena()
	var result := [-1, false]
	replayer.diverged.connect(func(at: int, _recorded: int, _got: int) -> void: result[0] = at)
	replayer.finished.connect(func() -> void: result[1] = true)
	replayer.play(rec)
	while replayer.playing():
		await frames(1)
	for node: Node in [replayer, game]:
		node.queue_free()
	await frames(2)
	InputFeed.release()
	return result


# The hands: walk, jab, lock on and let go, jab, guard.
func _hands() -> Array:
	return [{"frames": 10}, {"frames": 20, "move": Vector2(0, -1)}, {"frames": 1, "press": [&"palm"], "hold": [&"palm"]}, {"frames": 15},
			{"frames": 1, "press": [&"lock_on"]}, {"frames": 30}, {"frames": 1, "press": [&"lock_on"]}, {"frames": 20, "move": Vector2(1, 0.5)},
			{"frames": 1, "press": [&"palm"], "hold": [&"palm"]}, {"frames": 30}, {"frames": 40, "hold": [&"guard"]}]


func test_a_fight_on_the_mouse_replays_as_recorded_in_a_window_of_another_size_with_the_mouse_elsewhere() -> void:
	var places := [Vector2(100, 100), Vector2(500, 300), Vector2(320, 20), Vector2(40, 340), Vector2(600, 350), Vector2(300, 180)]
	var rec := await _record_fight(_hands(), 200, SMALL, places)
	var cursors := rec.frames.filter(func(f: Dictionary) -> bool: return f.has("cursor"))
	assert_true(cursors.size() > 10, "the recording holds the cursor's point on the frames the brain read it: %d" % cursors.size())
	assert_true(rec.frames.all(func(f: Dictionary) -> bool: return f.get("device") == Inputs.Device.KEYBOARD_MOUSE), "and the device on every frame")
	var again := await _replay_fight(rec, LARGE)
	assert_eq(again[0], -1, "no divergence in a window of another size")
	assert_true(again[1], "and it finished")


func test_a_fight_in_which_the_hands_change_device_twice_replays_as_recorded() -> void:
	var spot := Vector3(2, 0, -3)
	var hands := [{"frames": 10, "device": Inputs.Device.GAMEPAD}, {"frames": 30, "device": Inputs.Device.GAMEPAD, "move": Vector2(0, -1)},
			{"frames": 1, "device": Inputs.Device.KEYBOARD_MOUSE, "cursor": spot, "press": [&"palm"], "hold": [&"palm"]},
			{"frames": 30, "device": Inputs.Device.KEYBOARD_MOUSE, "cursor": spot * 2.0}, {"frames": 1, "device": Inputs.Device.GAMEPAD, "press": [&"palm"], "hold": [&"palm"]},
			{"frames": 30, "device": Inputs.Device.GAMEPAD, "hold": [&"guard"]}, {"frames": 20, "device": Inputs.Device.GAMEPAD}]
	var rec := await _record_fight(hands, 120, SMALL)
	var devices := rec.frames.map(func(f: Dictionary) -> Variant: return f.get("device"))
	assert_true(devices.has(Inputs.Device.GAMEPAD) and devices.has(Inputs.Device.KEYBOARD_MOUSE), "both devices are in it")
	var changes := 0
	for i in range(1, devices.size()):
		if devices[i] != devices[i - 1]:
			changes += 1
	assert_eq(changes, 2, "and it changes twice: %s" % [devices])
	var again := await _replay_fight(rec, LARGE)
	assert_eq(again[0], -1, "no divergence")
	assert_true(again[1], "and it finished")


func test_a_bots_recording_is_a_pad_throughout_and_replays_as_recorded() -> void:
	get_window().size = SMALL
	var game := BotWorld.make(self, 3)
	var bot := track(CombatBot.new()) as CombatBot
	bot.begin(game.player, game.arena(), 3, CombatBot.Policy.COUNTER)
	await frames(240)
	bot.finish()
	var rec := bot.recorder.recording()
	assert_true(rec.frames.all(func(f: Dictionary) -> bool: return f.get("device") == Inputs.Device.GAMEPAD), "the pad on every frame")
	assert_false(rec.frames.any(func(f: Dictionary) -> bool: return f.has("cursor")), "and no cursor")
	for node: Node in [bot, game]:
		node.free()
	await frames(2)
	InputFeed.release()
	var again := await _replay_fight(rec, LARGE)
	assert_eq(again[0], -1, "no divergence")
	assert_true(again[1], "and it finished")


func test_the_old_format_is_refused_by_its_number() -> void:
	var rec := InputRecording.new()
	rec.frames.append(InputRecording.idle())
	rec.frame_count = 1
	rec.hashes[1] = 1
	assert_eq(InputRecording.VERSION, 2, "the format went up by one")
	rec.version = 1
	assert_true(rec.problem().contains("format 1"), "version 1: %s" % rec.problem())
