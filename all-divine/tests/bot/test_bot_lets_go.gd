extends TestCase
## A bot that leaves the tree while it plays lets the controls go: no action stays down and the devices are read again. A test that freed
## its bot without finish() used to hand the bot's presses and its stick to the next test file (the pause menu's "W held across the
## close: he walks" then failed in whichever CI shard put the two files together).

const KNUCKLE := "res://data/actors/knuckle_1.tres"


func after_each() -> void:
	InputFeed.release()
	Game.reset()
	await frames(1)


func test_a_bot_freed_while_it_plays_lets_the_controls_go() -> void:
	var run := Duel.make(self, [], [], 1.0, load(KNUCKLE) as ActorDef)
	var a: Actor = run["a"]
	a.set_brain(PlayerBrain.new())
	var bot := CombatBot.new()
	add_child(bot)
	bot.reaction_frames = 0
	bot.begin(a, null, 1, CombatBot.Policy.MASH)
	await frames(30)
	assert_true(Inputs.aim_injected(), "while it plays the bot has the controls")
	bot.free()
	await frames(1)
	var down: Array[StringName] = []
	for action: StringName in Inputs.GAMEPLAY:
		if Input.is_action_pressed(action):
			down.append(action)
	assert_eq(down, [] as Array[StringName], "no action is still down")
	assert_false(Inputs.aim_injected(), "and the devices are read again")


func test_a_bot_that_never_began_takes_nothing_from_the_controls_when_it_goes() -> void:
	# A replay or a person may have the controls: a bot that was made and freed without playing must not let go of what is not its own.
	Inputs.inject_aim(Inputs.Device.GAMEPAD)
	var bot := CombatBot.new()
	add_child(bot)
	await frames(2)
	bot.free()
	await frames(1)
	assert_true(Inputs.aim_injected(), "the controls another gave are still given")
