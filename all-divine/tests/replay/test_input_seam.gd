extends TestCase
## The seam a replay and the bot feed the game's input through (Inputs.inject_move, Inputs.inject_direction): what it
## gives in place of the devices, and that it ends when it is let go of.


func after_each() -> void:
	Inputs.inject_move(null)
	Inputs.inject_direction(null)
	await frames(1)


func test_an_injected_move_is_what_move_vector_returns_until_it_is_given_null() -> void:
	assert_eq(Inputs.move_vector(), Vector2.ZERO, "no device is pushed in a headless run")
	Inputs.inject_move(Vector2(0.5, -1.0))
	assert_eq(Inputs.move_vector(), Vector2(0.5, -1.0), "the injected stick is read in place of the devices'")
	Inputs.inject_move(null)
	assert_eq(Inputs.move_vector(), Vector2.ZERO, "and the devices are read again once it is let go of")


func test_an_injected_direction_is_this_frames_direction_press_and_only_this_frames() -> void:
	await frames(1)
	Inputs.inject_direction(Vector2.LEFT)
	assert_eq(Inputs.direction_pressed_this_frame(), Vector2.LEFT, "the press is what was injected")
	assert_eq(Inputs.direction_pressed_this_frame(), Vector2.LEFT, "however often it is asked in the frame")
	Inputs.inject_direction(null)
	assert_eq(Inputs.direction_pressed_this_frame(), Vector2.ZERO, "and no press once it is let go of")


func test_an_injected_direction_with_guard_held_is_a_sway_through_the_player_brain() -> void:
	var hands := PlayerBrain.new()
	Input.action_press(&"guard")
	await frames(1)
	Inputs.inject_direction(Vector2.LEFT)
	var intent := hands.think(null, 1.0 / 60.0)
	Input.action_release(&"guard")
	Inputs.inject_direction(null)
	assert_true(intent.pressed.has(Actor.SWAY_ACTION), "the brain reads it as it reads a player's flick")
