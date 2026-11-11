extends TestCase
## No planted foot is dragged when a counter or clear-out starts (the controller's fix round 1). The pack clips begin in their own
## stances, and the 0.05 s blend into them slid the feet across the floor (0.14 to 0.34 m in a frame), which the clip tests cannot see
## since they play a clip alone. Here a real Actor on a floor starts each of the four moves out of each dodge (at its cancel window), out
## of the guard stance and out of rest, and a foot that stays on the ground moves 0.05 m along it in a frame at most through the first 8.

const ABARAX := "res://data/actors/abarax.tres"
const MOVES: Array[StringName] = [&"counter_hook", &"counter_rise", &"clear_backpalm", &"clear_wave"]
const DODGES: Array[StringName] = [&"sway_left_slip", &"sway_right_slip", &"sway_back_slip", &"sway_left_quick", &"sway_right_quick",
		&"sway_back_quick", &"sway_left_flurry", &"sway_right_flurry", &"sway_back_flurry", &"duck_slip", &"duck_quick", &"duck_flurry"]
const FRAMES := 8
const MOST := 0.05
## A foot is on the ground while its bone is within this of the height it stands at in rest.
const GROUNDED := 0.05


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


# The largest ground travel of a grounded foot in one frame over the FRAMES after `start` is called on a fresh Abarax out of `from`
# ("rest", "guard" or a dodge's id, at its cancel window): [metres, foot, frame].
func _worst(start: StringName, from: StringName) -> Array:
	var arena := TestArena.make(self)
	var a := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new([{"frames": 400, "hold": [&"guard"] if from == &"guard" else []}]), Vector3.ZERO, "A")
	await frames(30)
	var rest_height := a.rig.bone_global(&"foot_l").y
	if from != &"rest" and from != &"guard":
		a.runner.start(_move(from))
		while a.runner.window.is_empty() and a.runner.current != null:
			await frames(1)
	elif from == &"guard":
		await frames(30)
	var before := {&"foot_l": a.rig.bone_global(&"foot_l"), &"foot_r": a.rig.bone_global(&"foot_r")}
	a.runner.start(_move(start))
	var worst := [0.0, &"", 0]
	for frame in range(1, FRAMES + 1):
		await frames(1)
		for foot: StringName in [&"foot_l", &"foot_r"]:
			var now := a.rig.bone_global(foot)
			var was: Vector3 = before[foot]
			if now.y < rest_height + GROUNDED and was.y < rest_height + GROUNDED:
				var moved := Vector2(now.x - was.x, now.z - was.z).length()
				if moved > worst[0]:
					worst = [moved, foot, frame]
			before[foot] = now
	arena.queue_free()
	await frames(2)
	return worst


func test_no_planted_foot_is_dragged_when_a_counter_starts() -> void:
	for move in MOVES + [&"palm_jab"]:
		for from: StringName in DODGES + [&"guard", &"rest"]:
			var worst: Array = await _worst(move, from)
			assert_true(worst[0] <= MOST, "%s out of %s: the %s moves %.3f m along the ground on frame %d (at most %.2f)" % [move, from, worst[1], worst[0], worst[2], MOST])


# The hold of the feet lasts a few ticks from a counter's start; a blow that lands inside it starts a flinch or a stagger, and the
# feet must not be pinned for its first frames. Any other move starting lets them go (a reaction is one), and so does dying.
func test_a_held_foot_is_let_go_when_anything_else_starts() -> void:
	var run := Duel.make(self, [], [], 1.0, Duel.def(ActorDef.Team.ENEMY, 5.0))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await frames(30)
	a.runner.start(_move(&"counter_hook"))
	await frames(1)
	assert_false(a.rig.foot_planter.holds.is_empty(), "the feet are held after the counter starts (the control)")
	Blows.post(b, a, {})
	await frames(1)
	assert_true(a.runner.current != null and a.runner.current.kind == MoveData.Kind.REACTION, "the blow on his f2 started a reaction (%s)" % [a.runner.current.id if a.runner.current != null else &""])
	assert_true(a.rig.foot_planter.holds.is_empty(), "and on that frame no foot is held")
	# dying lets them go at once, even with no clip to start
	run["arena"].queue_free()
	await frames(2)
	var run2 := Duel.make(self, [], [], 1.0, Duel.def(ActorDef.Team.ENEMY, 5.0))
	var c: Actor = run2["a"]
	await frames(30)
	c.runner.start(_move(&"counter_hook"))
	await frames(2)
	assert_false(c.rig.foot_planter.holds.is_empty(), "held again")
	c.die()
	assert_true(c.rig.foot_planter.holds.is_empty(), "he dies: nothing is held")
