extends TestCase
## What a cancel leaves behind. When a move is cancelled into another, nothing of the first may carry on in
## the second: its hitboxes are off, its invulnerability and armour are off, and its cancel window is gone
## (the new move has its own, from its own marks). Tested on the real clips' windows: palm_jab opens
## {palm: palm_cross} at f15 and {palm, dodge} at f20; palm_cross opens {palm: palm_hook} at f20 and
## {palm, dodge} at f25; dodge_roll has iframes on f3 to f15 and opens {palm, dodge} at f22. The jab's hitbox
## is palm_l (on at f10, off at f15), the cross's is palm_r (f15 to f20).
##
## A move frame counts the actor's frames since the move started; 0 is the frame it started on. The windows
## only open once a hitbox's own mark has turned it off, so a second pair of tests cancels with
## MoveRunner.start in the middle of a swing and a roll, where the state to clear is really on.

const ABARAX := "res://data/actors/abarax.tres"
const DT := 1.0 / 60


## Plays `steps` for `total` actor frames and returns what happened, keyed by the actor's frame:
##   actor     the Actor
##   started   [[move id, actor frame], ...] from move_started
##   ended     [[move id, actor frame, cancelled], ...] from move_ended
##   states    actor frame -> {move (its id, or &""), hitboxes (active ids), iframes, window, recovery, facing}
func _run(steps: Array, total: int) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var run := {"actor": actor, "started": [], "ended": [], "states": {}}
	actor.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append([m.id, actor.frame]))
	actor.runner.move_ended.connect(func(m: MoveData, cancelled: bool) -> void:
		run["ended"].append([m.id, actor.frame, cancelled]))
	while actor.frame < total:
		await frames(1)
		run["states"][actor.frame] = _state(actor)
	return run


func _state(actor: Actor) -> Dictionary:
	var current := actor.runner.current
	return {
		"move": current.id if current != null else &"",
		"hitboxes": actor.rig.active_hitboxes(),
		"iframes": actor.runner.iframes,
		"hyperarmour": actor.runner.hyperarmour,
		"window": actor.runner.window.duplicate(),
		"recovery": actor.runner.in_recovery,
		"facing": actor.facing(),
	}


func _at(run: Dictionary, f: int) -> Dictionary:
	if not run["states"].has(f):
		fail("no state for frame %d" % f)
		return {"move": &"?", "hitboxes": [&"?"], "iframes": true, "hyperarmour": true, "window": {"?": &"?"}, "recovery": true, "facing": Vector3.INF}
	return run["states"][f]


func test_jab_cancelled_into_cross_turns_its_hitbox_off() -> void:
	# Palm at frame 11 (jab f0), and again at frame 26 (jab f15, where the window opens).
	var run: Dictionary = await _run([
		{"frames": 10}, {"frames": 1, "press": [&"palm"]},
		{"frames": 14}, {"frames": 1, "press": [&"palm"]},
		{"frames": 20},
	], 50)
	assert_eq(run["started"], [[&"palm_jab", 11], [&"palm_cross", 26]], "the cross at jab f15")
	assert_eq(run["ended"].front(), [&"palm_jab", 26, true], "the jab was cancelled")
	assert_eq(_at(run, 25)["hitboxes"], [&"palm_l"], "the jab's hand is live the frame before")
	var cancel := _at(run, 26)
	assert_eq(cancel["move"], &"palm_cross")
	assert_eq(cancel["hitboxes"], [] as Array[StringName], "on the frame the cross starts, palm_l is off and palm_r is not on yet")
	assert_eq(cancel["window"], {}, "the jab's window is gone; the cross's opens at its f20")
	assert_false(cancel["recovery"], "and the jab's recovery with it")
	assert_eq(_at(run, 40)["hitboxes"], [] as Array[StringName], "the cross's own hand comes on at its f15, frame 41")
	assert_eq(_at(run, 41)["hitboxes"], [&"palm_r"])
	assert_eq(_at(run, 46)["window"], {&"palm": &"palm_hook"}, "the cross's window at its f20")


func test_jab_cancelled_into_roll_at_its_recovery_window() -> void:
	# Palm at frame 11, then dodge with the stick pushed east at jab f20 (frame 31), where {palm, dodge} opens.
	var east := Vector2(1, 0)
	var run: Dictionary = await _run([
		{"frames": 10}, {"frames": 1, "press": [&"palm"]},
		{"frames": 19}, {"frames": 1, "press": [&"dodge"], "move": east},
		{"frames": 20, "move": east},
	], 55)
	assert_eq(run["started"], [[&"palm_jab", 11], [&"dodge_roll", 31]])
	assert_eq(run["ended"].front(), [&"palm_jab", 31, true], "the jab was cancelled")
	var cancel := _at(run, 31)
	assert_eq(cancel["move"], &"dodge_roll")
	assert_eq(cancel["hitboxes"], [] as Array[StringName], "no hitbox is on")
	assert_false(cancel["iframes"], "the roll's iframes start at its f3")
	assert_eq(cancel["window"], {}, "the jab's {palm, dodge} window did not carry over")
	assert_false(cancel["recovery"], "nor its recovery")
	assert_vec_near(cancel["facing"], Vector3(1, 0, 0), 1e-6, "the roll turned to the stick at once")
	assert_false(_at(run, 33)["iframes"], "f2")
	assert_true(_at(run, 34)["iframes"], "iframes from the roll's f3")
	assert_true(_at(run, 46)["iframes"], "through f15")
	assert_false(_at(run, 47)["iframes"], "and off at f16")
	for f in range(31, 56):
		assert_eq(_at(run, f)["hitboxes"], [] as Array[StringName], "no hitbox in frame %d" % f)


func test_roll_cancelled_into_jab_clears_iframes_and_the_window() -> void:
	# Dodge at frame 11 (roll f0), palm at roll f22 (frame 33), where {palm, dodge} opens.
	var run: Dictionary = await _run([
		{"frames": 10}, {"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)},
		{"frames": 21}, {"frames": 1, "press": [&"palm"]},
		{"frames": 20},
	], 60)
	assert_eq(run["started"], [[&"dodge_roll", 11], [&"palm_jab", 33]])
	assert_eq(run["ended"].front(), [&"dodge_roll", 33, true], "the roll was cancelled")
	assert_eq(_at(run, 32)["window"], {}, "no window the frame before")
	var cancel := _at(run, 33)
	assert_eq(cancel["move"], &"palm_jab")
	assert_false(cancel["iframes"], "the roll's invulnerability is not the jab's")
	assert_eq(cancel["window"], {}, "the roll's {palm, dodge} window is gone, and the jab's is empty until its f15")
	assert_false(cancel["recovery"], "the roll's recovery is over with it")
	assert_eq(_at(run, 47)["window"], {} , "still empty at jab f14")
	assert_eq(_at(run, 48)["window"], {&"palm": &"palm_cross"}, "the jab's own window opens at its f15, with no dodge in it")


func test_jab_forced_into_roll_mid_swing_turns_the_hitbox_off() -> void:
	# The windows only open after the hand is off, so force the cancel at jab f12, with palm_l on.
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new([{"frames": 1, "press": [&"palm"]}]))
	while actor.frame < 13:  # the jab starts on frame 1, so frame 13 is its f12
		await frames(1)
	assert_eq(actor.runner.current.id, &"palm_jab")
	assert_eq(actor.rig.active_hitboxes(), [&"palm_l"], "mid-swing")
	actor.runner.start(Registry.fetch(&"moves", &"dodge_roll") as MoveData)
	assert_eq(actor.runner.current.id, &"dodge_roll")
	assert_eq(actor.rig.active_hitboxes(), [] as Array[StringName], "the cancelled jab's hitbox is off at once")
	assert_false(actor.runner.iframes)
	assert_false(actor.runner.hyperarmour)
	assert_eq(actor.runner.window, {})


func test_roll_forced_into_jab_mid_roll_clears_iframes() -> void:
	# Iframes are on from the roll's f3 to f15: cancel at f5, inside them.
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new([{"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)}]))
	while actor.frame < 6:  # the roll starts on frame 1, so frame 6 is its f5
		await frames(1)
	assert_eq(actor.runner.current.id, &"dodge_roll")
	assert_true(actor.is_invulnerable(), "mid-roll")
	actor.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	assert_eq(actor.runner.current.id, &"palm_jab")
	assert_false(actor.is_invulnerable(), "the cancelled roll's iframes are off at once")
	assert_false(actor.runner.hyperarmour)
	assert_eq(actor.runner.window, {})
	assert_eq(actor.rig.active_hitboxes(), [] as Array[StringName], "and the jab's hand is not on until its f10")
