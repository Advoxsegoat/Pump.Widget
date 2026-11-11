extends TestCase
## The self-test: `godot -- --selftest` runs the main scene's scripted fight in the training yard and quits 0 when
## no engine error was logged from startup to its end, else 1; and it always quits. The command-line runs are
## child Godots (their errors are printed in their output, which is captured here), each stopped if it is still
## running after CHILD_LIMIT seconds, so a self-test that never ends fails this test instead of hanging the run.
##
## An in-process test cannot raise a real engine error to count: with printing switched off (quietly) the
## engine does not hand the error to loggers either, and with printing on it would show in this run's output.
## So the counting is checked through child runs of fixture scenes, and the exit code's rule on its own.

const MAIN := "res://main/main.tscn"
const SELF_TEST := "res://core/self_test.gd"
## The main scene with a node that raises an error while it boots, before Main is ready.
const BOOT_ERROR := "res://tests/fixtures/selftest/boot_error.tscn"
## The main scene without its Player: Main._ready stops at the first use of him, before the circuit begins.
const NO_PLAYER := "res://tests/fixtures/selftest/no_player.tscn"
## Seconds a child Godot may run. A good self-test takes a few (600 frames at --fixed-fps 60, and the loading).
const CHILD_LIMIT := 30


func after_each() -> void:
	Game.reset()


# Runs this project in a headless child Godot at --fixed-fps 60 with `before` ahead of the user arguments and
# `after` as them, stopped after CHILD_LIMIT seconds. Returns {code, text}; code 124 means it was stopped.
func _run_child(before: Array[String], after: Array[String]) -> Dictionary:
	var argv := PackedStringArray(["-k", "5", str(CHILD_LIMIT), OS.get_executable_path(), "--headless",
			"--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60"])
	argv.append_array(PackedStringArray(before))
	argv.append("--")
	argv.append_array(PackedStringArray(after))
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	return {code = code, text = str(output[0]) if not output.is_empty() else ""}


# The circuit, here in this process: in 600 frames Abarax approaches the tier I Knuckle the yard sends, and fights it:
# a jab, a cross and a hook, a sway, a duck, a dash-step, a guard and a heavy, trading blows with it.
func test_selftest_circuit_fights_a_knuckle_in_the_yard() -> void:
	Game.reset()
	Arena.reset_spawn_counts()  # the Knuckle's dice as in a fresh game, which --selftest is
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	var player := main.get_node("PixelStage/World/Player") as Actor
	var arena := main.arena()
	assert_true(arena != null, "the region is the yard")
	var foe := arena.enemies()[0]
	assert_eq(foe.def.id, &"knuckle_1", "one tier I")
	var started: Array[StringName] = []
	player.runner.move_started.connect(func(move: MoveData) -> void: started.append(move.id))
	var landed := [0]
	player.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void:
		if r.outcome == HitResult.Outcome.HIT:
			landed[0] += 1)
	player.set_brain(ScriptBrain.new(main.selftest_circuit()))
	await frames(Main.SELFTEST_FRAMES)
	for move in [&"palm_jab", &"palm_cross", &"palm_hook", &"sway_right_slip", &"duck_slip", &"dash_step_back", &"guard_raise", &"palm_heavy"]:
		assert_true(started.has(move), "he played %s (%s)" % [move, started])
	assert_true(landed[0] >= 1, "and landed a blow on it (%d)" % landed[0])
	assert_true(foe.stats.hp < foe.stats.max_hp, "it is hurt")


# The real thing: the main scene runs its circuit for 600 frames in the yard, nothing prints an error, and it quits 0.
func test_selftest_fights_in_the_yard_and_exits_zero() -> void:
	var run := _run_child([], ["--selftest"])
	assert_ne(run.code, 124, "the self-test was still running after %d s:\n%s" % [CHILD_LIMIT, run.text])
	assert_eq(run.code, 0, run.text)
	assert_true((run.text as String).contains("selftest: 600 frames, 0 errors"), run.text)
	assert_true((run.text as String).contains("Knuckle at"), "it fought a Knuckle:\n%s" % run.text)
	assert_false((run.text as String).contains("ERROR"), "the self-test printed an error:\n%s" % run.text)


# An error raised while the scene boots, before Main is ready, counts: the self-test quits 1 and names it.
func test_an_error_while_booting_fails_the_selftest() -> void:
	var run := _run_child([BOOT_ERROR], ["--selftest"])
	assert_ne(run.code, 124, "the self-test was still running after %d s:\n%s" % [CHILD_LIMIT, run.text])
	assert_eq(run.code, 1, run.text)
	assert_true((run.text as String).contains("selftest: a boot error, raised on purpose"), "the error is reported:\n%s" % run.text)
	assert_true((run.text as String).contains("selftest: 600 frames, 1 errors"), run.text)


# A main scene that never gets as far as starting the circuit (here Main._ready stops at a missing node) still
# ends the self-test, failed, at once rather than leaving the game running.
func test_a_circuit_that_never_begins_fails_the_selftest_promptly() -> void:
	var started := Time.get_ticks_msec()
	var run := _run_child([NO_PLAYER], ["--selftest"])
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	assert_ne(run.code, 124, "the self-test was still running after %d s:\n%s" % [CHILD_LIMIT, run.text])
	assert_eq(run.code, 1, run.text)
	assert_true((run.text as String).contains("selftest: the circuit never began"), run.text)
	assert_true(seconds < CHILD_LIMIT / 2.0, "it ended after %.1f s" % seconds)


# Without --selftest the game runs as a game: nothing is listening for errors and nothing will end it.
func test_without_the_argument_the_selftest_is_off() -> void:
	var self_test := get_node_or_null(^"/root/SelfTest")
	assert_true(self_test != null, "the SelfTest autoload")
	if self_test != null:
		assert_false(self_test.get(&"active"), "it is off in a test run")
		assert_false(self_test.is_physics_processing(), "and counts nothing")


# The exit code: 0 only when no error was logged and nothing went wrong (the circuit never beginning is a
# problem).
func test_result_is_one_with_any_error_or_problem() -> void:
	var script := load(SELF_TEST) as Script
	assert_true(script != null, "core/self_test.gd")
	if script == null:
		return
	var none := PackedStringArray()
	assert_eq(script.call(&"result", none, none), 0, "nothing wrong: 0")
	assert_eq(script.call(&"result", PackedStringArray(["boom"]), none), 1, "an error: 1")
	assert_eq(script.call(&"result", none, PackedStringArray(["the circuit never began"])), 1, "a problem: 1")
