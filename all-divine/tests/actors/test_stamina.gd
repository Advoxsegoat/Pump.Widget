extends TestCase
## Stamina in play, on Abarax in an arena: the moves cost what their data says, at once; an attack or a dodge
## is refused at zero (and while exhausted, until stamina has climbed back to 20) and the press that asked is
## used up; walking never needs stamina; a sprint drains 12 a second and does not begin when exhausted; and
## stamina comes back by itself once the actor has waited.
##
## A frame is the actor's: the first it lives is 1. Palm at frame N starts the jab on N (its f0), and its
## cancel window into the cross opens at its f15.

const ABARAX := "res://data/actors/abarax.tres"
const EAST := Vector2(1, 0)


## Abarax in a new arena, with a ScriptBrain playing `steps`, recording what starts and ends:
##   actor     the Actor
##   started   [[move id, actor frame], ...] from move_started
##   ended     [[move id, actor frame, cancelled], ...] from move_ended
func _spawn(steps: Array) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var run := {"actor": actor, "started": [], "ended": []}
	actor.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append([m.id, actor.frame]))
	actor.runner.move_ended.connect(func(m: MoveData, cancelled: bool) -> void:
		run["ended"].append([m.id, actor.frame, cancelled]))
	return run


# Plays `actor` until it has lived `frame` frames.
func _play_to(actor: Actor, frame: int) -> void:
	while actor.frame < frame:
		await frames(1)


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


func test_the_moves_carry_their_costs() -> void:
	assert_eq(_move(&"palm_jab").stamina_cost, 12.0)
	assert_eq(_move(&"palm_cross").stamina_cost, 14.0)
	assert_eq(_move(&"dash_step").stamina_cost, 8.0)


func test_a_dash_step_costs_eight() -> void:
	var run := _spawn([{"frames": 1, "press": [&"dodge"], "move": EAST}, {"frames": 10}])
	var actor: Actor = run["actor"]
	assert_eq(actor.stats.stamina, 100.0, "full before")
	await _play_to(actor, 1)
	assert_eq(run["started"], [[&"dash_step_left", 1]])
	assert_near(actor.stats.stamina, 92.0, 1e-6, "spent on the frame the dash-step starts")
	await _play_to(actor, 11)
	assert_near(actor.stats.stamina, 92.0, 1e-6, "and not again while it plays")


func test_jab_costs_twelve_and_the_cross_it_cancels_into_fourteen() -> void:
	var run := _spawn([{"frames": 1, "press": [&"palm"]}, {"frames": 14}, {"frames": 1, "press": [&"palm"]}, {"frames": 10}])
	var actor: Actor = run["actor"]
	await _play_to(actor, 1)
	assert_near(actor.stats.stamina, 88.0, 1e-6, "the jab")
	await _play_to(actor, 16)
	assert_eq(run["started"], [[&"palm_jab", 1], [&"palm_cross", 16]])
	assert_near(actor.stats.stamina, 74.0, 1e-6, "then the cross, started by the jab's cancel window")


func test_stamina_comes_back_after_the_wait() -> void:
	var run := _spawn([{"frames": 1, "press": [&"dodge"], "move": EAST}, {"frames": 100}])
	var actor: Actor = run["actor"]
	await _play_to(actor, 36)
	assert_near(actor.stats.stamina, 92.0, 1e-6, "still waiting 0.6 s after the dash-step")
	await _play_to(actor, 90)
	assert_near(actor.stats.stamina, 100.0, 1e-6, "8 at 45 a second takes 0.18 s more")


func test_no_attack_or_dodge_at_zero_but_walking_works() -> void:
	var run := _spawn([{"frames": 1, "press": [&"palm", &"dodge"], "move": EAST}, {"frames": 30, "move": EAST}])
	var actor: Actor = run["actor"]
	actor.stats.spend_stamina(999.0)
	var started_at := actor.global_position
	await _play_to(actor, 31)
	assert_eq(run["started"], [], "neither the palm nor the dodge started anything")
	assert_false(actor.runner.busy())
	assert_true(actor.global_position.x - started_at.x > 1.0, "but the stick moved him: %s m" % (actor.global_position.x - started_at.x))


func test_exhausted_actor_acts_again_only_once_stamina_is_back_to_twenty() -> void:
	# Stamina starts coming back 0.6 s (frame 37) after it ran out and is above 0 from then on, but the actor
	# stays exhausted until 20 (frame 64): a palm at frame 50 is refused, and one at frame 80 is not.
	var run := _spawn([{"frames": 49}, {"frames": 1, "press": [&"palm"]}, {"frames": 29}, {"frames": 1, "press": [&"palm"]}, {"frames": 10}])
	var actor: Actor = run["actor"]
	actor.stats.spend_stamina(999.0)
	await _play_to(actor, 50)
	assert_true(actor.stats.stamina > 0.0, "some stamina is back")
	assert_true(actor.stats.exhausted)
	assert_eq(run["started"], [], "a palm with some stamina but not enough is refused")
	await _play_to(actor, 80)
	assert_eq(run["started"], [[&"palm_jab", 80]], "and one after it has climbed to 20 starts")


func test_a_refused_press_is_used_up() -> void:
	# The palm at frame 6 is refused. Stamina is put right at once, well inside the buffer's 9 frames: a
	# press that was kept would start the jab on frame 7.
	var run := _spawn([{"frames": 5}, {"frames": 1, "press": [&"palm"]}, {"frames": 15}])
	var actor: Actor = run["actor"]
	actor.stats.spend_stamina(999.0)
	await _play_to(actor, 6)
	actor.stats.stamina = actor.stats.max_stamina
	actor.stats.exhausted = false
	await _play_to(actor, 21)
	assert_eq(run["started"], [])
	assert_eq(actor.buffer.size(), 0, "nothing left in the buffer")


# The jab at frame 1 and a palm at its f15 to cancel into the cross, with stamina taken at frame 5 if `exhaust`.
func _cancel_attempt(exhaust: bool) -> Dictionary:
	var run := _spawn([{"frames": 1, "press": [&"palm"]}, {"frames": 14}, {"frames": 1, "press": [&"palm"]}, {"frames": 40}])
	var actor: Actor = run["actor"]
	await _play_to(actor, 5)
	if exhaust:
		actor.stats.spend_stamina(999.0)
	await _play_to(actor, 60)
	return run


func test_a_refused_cancel_leaves_the_move_playing() -> void:
	var run: Dictionary = await _cancel_attempt(true)
	assert_eq(run["started"], [[&"palm_jab", 1]], "no cross")
	assert_eq(run["ended"].size(), 1)
	assert_false(run["ended"][0][2], "and the jab was not cancelled: it ran to its end")
	assert_true(run["ended"][0][1] > 16, "after the press at frame 16")


func test_the_same_cancel_with_stamina_goes_through() -> void:
	var run: Dictionary = await _cancel_attempt(false)
	assert_eq(run["started"], [[&"palm_jab", 1], [&"palm_cross", 16]])
	assert_eq(run["ended"].front(), [&"palm_jab", 16, true])


func test_a_reaction_or_other_move_needs_no_stamina() -> void:
	var run := _spawn([{"frames": 1}])
	var actor: Actor = run["actor"]
	await _play_to(actor, 1)
	actor.stats.spend_stamina(999.0)
	var kinds: Array[MoveData.Kind] = [MoveData.Kind.REACTION, MoveData.Kind.OTHER]
	for kind in kinds:
		var move := MoveData.new()
		move.id = &"test_move"
		move.kind = kind
		move.clip = &"palm_jab"
		actor.runner.start(move)
		assert_eq(actor.runner.current, move, "kind %d starts at zero stamina" % kind)
		assert_eq(actor.stats.stamina, 0.0)


func test_sprint_drains_twelve_a_second() -> void:
	var run := _spawn([{"frames": 60, "hold": [&"dodge"], "move": EAST}])
	var actor: Actor = run["actor"]
	await _play_to(actor, 1)
	assert_true(actor.locomotion.sprinting)
	await _play_to(actor, 60)
	assert_near(actor.stats.stamina, 88.0, 1e-6, "12 for the second, with none coming back meanwhile")
	assert_eq(run["started"], [], "holding dodge is a sprint, not a dash-step")


func test_sprint_drains_then_stops_when_exhausted() -> void:
	# Ten stamina is 50 frames of sprint. Holding dodge on, the actor jogs while exhausted (stamina is back to
	# 20 about 63 frames after it ran out) and then sprints again.
	var run := _spawn([{"frames": 160, "hold": [&"dodge"], "move": EAST}])
	var actor: Actor = run["actor"]
	var tuning := (load(ABARAX) as ActorDef).locomotion
	actor.stats.spend_stamina(90.0)
	var ran_out := -1
	var sprinting := {}
	var speeds := {}
	while actor.frame < 160:
		await frames(1)
		sprinting[actor.frame] = actor.locomotion.sprinting
		speeds[actor.frame] = actor.locomotion.speed
		if ran_out < 0 and actor.stats.exhausted:
			ran_out = actor.frame
	assert_true(sprinting[30], "sprinting on the way down")
	assert_true(ran_out >= 49 and ran_out <= 52, "stamina ran out on frame %d" % ran_out)
	var sprinted_exhausted := range(ran_out + 1, ran_out + 60).filter(func(f: int) -> bool: return sprinting[f])
	assert_eq(sprinted_exhausted, [], "frames on which he sprinted while exhausted")
	assert_near(speeds[ran_out + 30], tuning.jog_speed, 1e-6, "he jogs instead")
	assert_true(sprinting[ran_out + 90], "and sprints again once stamina has climbed back")
	assert_false(actor.stats.exhausted)


func test_a_forced_start_passes_the_stamina_gate() -> void:
	# A paired move starts whatever the stamina (Actor.start_paired forces both of its moves): the runner's start
	# refuses an attack to an exhausted actor, and starts it when forced.
	var run := _spawn([{"frames": 10}])
	var actor: Actor = run["actor"]
	await _play_to(actor, 1)
	actor.stats.spend_stamina(999.0)
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	actor.runner.start(jab)
	assert_eq(run["started"], [], "refused")
	actor.runner.start(jab, true)
	assert_eq(run["started"], [[&"palm_jab", 1]], "forced")
