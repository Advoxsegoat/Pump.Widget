class_name FrameMeter
extends RefCounted
## The stopwatch of the frame budgets: it times each physics step of the running tree twice, by the wall clock and by the
## processor time of the thread that runs it (Linux's /proc/thread-self/schedstat: the nanoseconds the thread was on a core).
##
## Why two: a budget is a statement about what the game's frame costs, and a wall clock also counts every moment another process
## had the core (another lane's test run, another job on a CI runner): at a load of 13 on four cores a frame of 1.4 ms took 3 to 7
## ms by the wall clock and the test failed with nothing the matter with the game. The thread's own time does not count the
## moments it was not running (cache and memory pressure from the others still shows in it, a little). The budget tests hold the
## thread's time; the wall time is kept so that a test or a report can show both.
##
## A step is timed from the tree's physics_frame signal, at its start, to process_frame, once the step (scripts and the physics
## server's step) is done: Performance.TIME_PHYSICS_PROCESS is no use, it is set once a second of real time, to that second's longest
## step. Every frame has one physics step under --fixed-fps 60. Reading the thread's time opens a file (about 20 us), which the time
## measured includes twice at most.

## How many steps make the window the quiet mean is taken over (two seconds of play).
const WINDOW := 120

## Each step's wall time and thread time, in microseconds. `cpu` is empty where the platform does not tell it.
var wall: Array[int] = []
var cpu: Array[int] = []

var _tree: SceneTree
var _wall_start := 0
var _cpu_start := -1


## The processor time the calling thread has used, in microseconds; -1 where the platform does not say.
static func thread_cpu_usec() -> int:
	var file := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if file == null:
		return -1
	var words := file.get_line().split(" ", false)
	return words[0].to_int() / 1000 if not words.is_empty() and words[0].is_valid_int() else -1


## {count, mean, p99, max}: the steps of `times` (microseconds) as milliseconds. The 99th percentile is the value at rank ceil(0.99 n).
static func stats(times: Array[int]) -> Dictionary:
	if times.is_empty():
		return {"count": 0, "mean": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0
	for t in times:
		total += t
	return {"count": times.size(), "mean": total / 1000.0 / times.size(),
			"p99": sorted[ceili(0.99 * times.size()) - 1] / 1000.0, "max": sorted.back() / 1000.0}


## The least of the means of every run of `window` consecutive steps, in milliseconds: the stretch the machine left the game alone.
static func best_window_mean(times: Array[int], window: int) -> float:
	if times.size() < window or window < 1:
		return stats(times)["mean"]
	var total := 0
	for i in window:
		total += times[i]
	var best := total
	for i in range(window, times.size()):
		total += times[i] - times[i - window]
		best = mini(best, total)
	return best / 1000.0 / window


## The steps a budget is held to: the thread's own time where the platform tells it, else the wall time.
func steps() -> Array[int]:
	return cpu if cpu.size() >= wall.size() / 2 and not cpu.is_empty() else wall


## What `steps()` is: "thread time" or "wall time".
func basis() -> String:
	return "thread time" if steps() == cpu else "wall time"


## The two numbers a budget holds, from `steps()`: {mean, p99, max, count, basis}. `mean` is the quietest WINDOW steps' mean
## (best_window_mean): the machine's load only ever adds to a step, so the least stretch is the game's frame; `p99` is the 99th
## percentile over every step, which a load that took a core away for a moment does not push up in thread time (it did in wall
## time: 9 to 26 ms where the thread's was 3 to 5).
func held() -> Dictionary:
	var s := stats(steps())
	s["mean"] = best_window_mean(steps(), WINDOW)
	s["basis"] = basis()
	return s


## "wall mean .. p99 .. | thread mean .. p99 .." for a report: both clocks, each as it was (the plain mean, not the quiet one).
func both() -> String:
	var w := stats(wall)
	var c := stats(cpu)
	return "wall: mean %.2f, p99 %.2f, longest %.2f ms; thread: mean %.2f, p99 %.2f, longest %.2f ms; quietest %d steps: wall %.2f, thread %.2f ms" % [
			w["mean"], w["p99"], w["max"], c["mean"], c["p99"], c["max"], WINDOW, best_window_mean(wall, WINDOW), best_window_mean(cpu, WINDOW)]


## Starts timing `tree`'s physics steps.
func attach(tree: SceneTree) -> void:
	_tree = tree
	_wall_start = 0
	tree.physics_frame.connect(_on_physics_frame)
	tree.process_frame.connect(_on_process_frame)


## Stops timing.
func detach() -> void:
	if _tree != null and _tree.physics_frame.is_connected(_on_physics_frame):
		_tree.physics_frame.disconnect(_on_physics_frame)
		_tree.process_frame.disconnect(_on_process_frame)


func _on_physics_frame() -> void:
	_cpu_start = thread_cpu_usec()
	_wall_start = Time.get_ticks_usec()


func _on_process_frame() -> void:
	if _wall_start <= 0:
		return
	wall.append(Time.get_ticks_usec() - _wall_start)
	var cpu_now := thread_cpu_usec()
	if _cpu_start >= 0 and cpu_now >= 0:
		cpu.append(cpu_now - _cpu_start)
	_wall_start = 0
