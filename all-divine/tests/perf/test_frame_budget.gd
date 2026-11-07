extends TestCase
## The frame budget, headless: the main scene's physics frame (Abarax running the self-test's circuit of the
## courtyard: walking, rolling, jabbing, climbing the stairs) takes at most 2 ms on average over 600 frames.
##
## Performance.TIME_PHYSICS_PROCESS is no use here: the engine sets it once a second of real time, to the
## longest physics step of that second, and under --fixed-fps 600 frames can take less than a second. So the
## test times each physics step itself, over the same span: from the tree's physics_frame signal, at the start
## of the step, to its process_frame signal, which comes once the step (scripts and the physics server's step)
## is done. Every frame here has exactly one physics step (--fixed-fps 60).

const MAIN := "res://main/main.tscn"
const FRAMES := 600
const BUDGET_MS := 2.0

var _step_start := 0
var _step_times: Array[int] = []


func after_each() -> void:
	Game.reset()
	var tree := get_tree()
	if tree.physics_frame.is_connected(_on_physics_frame):
		tree.physics_frame.disconnect(_on_physics_frame)
		tree.process_frame.disconnect(_on_process_frame)


func _on_physics_frame() -> void:
	_step_start = Time.get_ticks_usec()


func _on_process_frame() -> void:
	if _step_start > 0:
		_step_times.append(Time.get_ticks_usec() - _step_start)
		_step_start = 0


func test_courtyard_physics_frame_under_two_ms() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	var player := main.get_node("PixelStage/World/Player") as Actor
	player.set_brain(ScriptBrain.new(main.selftest_circuit()))
	# The frame that made the scene, and the next, are not the courtyard's to pay for.
	await frames(2)
	_step_times.clear()
	_step_start = 0
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	await frames(FRAMES)
	await get_tree().process_frame
	assert_true(_step_times.size() >= FRAMES, "timed %d physics steps" % _step_times.size())
	var total := 0
	for t in _step_times:
		total += t
	var mean_ms := total / 1000.0 / maxi(1, _step_times.size())
	var sorted := _step_times.duplicate()
	sorted.sort()
	var worst_ms: float = sorted.back() / 1000.0 if not sorted.is_empty() else 0.0
	assert_true(mean_ms <= BUDGET_MS, "a physics frame takes %.3f ms on average (the longest %.3f ms)" % [mean_ms, worst_ms])
