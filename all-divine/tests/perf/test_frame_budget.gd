extends TestCase
## The frame budget of the yard, headless: the main scene's physics frame (Abarax running the self-test's circuit in the training
## yard: approaching a Knuckle and fighting it, with the arena, the HUD and the enemy brain running) takes at most 2 ms, over
## 600 frames. The fights with several foes are tests/perf/test_combat_perf.gd's.
##
## It is measured as the thread's own processor time, in the quietest stretch (FrameMeter), and not as the wall clock's mean as it
## was: that failed (2.5 to 7 ms) whenever another process had the processor, as the other lanes' test runs do, with the game's frame
## costing what it always did. What the frame costs is what is held; tests/perf/test_frame_meter.gd says how, and a frame that
## really costs more still fails (see the mutation in the task's report). PERF_REPORT=1 prints both clocks.
##
## Every frame here has exactly one physics step (--fixed-fps 60).

const MAIN := "res://main/main.tscn"
const FRAMES := 600
const BUDGET_MS := 2.0

var _meter := FrameMeter.new()


func after_each() -> void:
	_meter.detach()
	Game.reset()


func test_yard_physics_frame_under_two_ms() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	var player := main.get_node("PixelStage/World/Player") as Actor
	player.set_brain(ScriptBrain.new(main.selftest_circuit()))
	# The frame that made the scene, and the next, are not the yard's to pay for.
	await frames(2)
	_meter.attach(get_tree())
	await frames(FRAMES)
	await get_tree().process_frame
	_meter.detach()
	var held := _meter.held()
	if OS.get_environment("PERF_REPORT") != "":
		print("PERF yard: %d steps; %s" % [held["count"], _meter.both()])
	assert_true(held["count"] >= FRAMES, "timed %d physics steps" % held["count"])
	assert_true(held["mean"] <= BUDGET_MS, "a physics frame takes %.3f ms in the quietest stretch (%s, budget %.1f ms; the longest %.3f ms); %s" % [held["mean"], held["basis"], BUDGET_MS, held["max"], _meter.both()])
