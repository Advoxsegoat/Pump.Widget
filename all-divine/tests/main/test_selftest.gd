extends TestCase
## The self-test: `godot -- --selftest` runs the main scene's scripted circuit of the courtyard and quits 0 when
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


# The circuit, here in this process: in 600 frames Abarax walks to the fountain, rolls, jabs and climbs the
# stairs, ending at StairsTop.
func test_selftest_circuit_walks_rolls_jabs_and_climbs() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	var player := main.get_node("PixelStage/World/Player") as Actor
	var started: Array[StringName] = []
	player.runner.move_started.connect(func(move: MoveData) -> void: started.append(move.id))
	player.set_brain(ScriptBrain.new(main.selftest_circuit()))
	var closest_to_fountain := INF
	for i in Main.SELFTEST_FRAMES:
		await frames(1)
		closest_to_fountain = minf(closest_to_fountain, Vector2(player.global_position.x, player.global_position.z).length())
	var top := (main.get_node("PixelStage/World/Region/StairsTop") as Marker3D).global_position
	assert_true(closest_to_fountain < 5.0, "he comes to the fountain (%.2f m from its centre at the closest)" % closest_to_fountain)
	assert_eq(started, [&"dodge_roll", &"palm_jab"] as Array[StringName], "he rolls, then jabs")
	assert_true(player.global_position.distance_to(top) < 1.0, "he ends at StairsTop (%.2f m off, at %s)" % [player.global_position.distance_to(top), player.global_position])


# The real thing: the main scene runs its circuit for 600 frames, nothing prints an error, and it quits 0.
func test_selftest_exits_zero() -> void:
	var run := _run_child([], ["--selftest"])
	assert_ne(run.code, 124, "the self-test was still running after %d s:\n%s" % [CHILD_LIMIT, run.text])
	assert_eq(run.code, 0, run.text)
	assert_true((run.text as String).contains("selftest: 600 frames, 0 errors"), run.text)
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
