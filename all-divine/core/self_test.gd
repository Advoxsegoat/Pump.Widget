extends Node
## The game's self-test: `godot -- --selftest` (a user argument) runs the main scene's scripted circuit
## (Main.selftest_circuit) and quits 0 if no engine error was logged from startup to its end, else 1. It always
## quits.
##
## Autoload "SelfTest", the first autoload, so that with --selftest it starts listening (a TestLogger context)
## before the other autoloads and the main scene load: an error raised while anything loads or boots counts.
## Main calls begin() once its circuit is running, and the self-test ends that many physics frames later. If the
## circuit has not begun WATCHDOG_FRAMES physics frames after startup (the main scene failed to load, or its
## _ready stopped on an error), the self-test ends then, failed, instead of leaving the game running.
## Without --selftest this does nothing.
##
## Physics ticks are fixed, so the circuit is the same at any frame rate; with --fixed-fps 60 (as the tests
## run it) it runs as fast as the machine can, and without it in about ten seconds.

const ARG := "--selftest"
## Physics frames after startup by which the circuit must have begun. The main scene is loaded and ready before
## the first one, so this is a generous wait.
const WATCHDOG_FRAMES := 60

## True when the game was started with --selftest.
var active := false

var _frames := 0  # physics frames since startup
var _circuit_frames := -1  # how many frames the circuit runs; -1 until it begins
var _began_at := 0  # _frames when it began
var _note := Callable()  # returns a line for the summary, or is empty


func _init() -> void:
	active = OS.get_cmdline_user_args().has(ARG)
	if active:
		TestLogger.shared().push_context()
		# A paused game still ends its self-test.
		process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	# Here, not in _init: a node whose script has _physics_process is switched to processing when it is ready.
	set_physics_process(active)


## The circuit is running: the self-test ends `frames` physics frames from now. `note`, if given, returns a
## line to print with the summary (where the circuit left the player, say). Does nothing without --selftest.
func begin(frames: int, note := Callable()) -> void:
	if not active:
		return
	_circuit_frames = frames
	_began_at = _frames
	_note = note


## The self-test's exit code: 0 when no engine error was logged and nothing else went wrong, else 1.
static func result(errors: PackedStringArray, problems: PackedStringArray) -> int:
	return 0 if errors.is_empty() and problems.is_empty() else 1


func _physics_process(_delta: float) -> void:
	if not active:
		return
	_frames += 1
	if _circuit_frames < 0:
		if _frames >= WATCHDOG_FRAMES:
			_end(PackedStringArray(["the circuit never began (%d frames after startup): the main scene did not load or get ready" % _frames]))
	elif _frames - _began_at >= _circuit_frames:
		_end(PackedStringArray())


# Stops listening, prints what went wrong and a summary, and quits with result().
func _end(problems: PackedStringArray) -> void:
	set_physics_process(false)
	var errors := TestLogger.shared().pop_context()
	for error in errors:
		printerr("selftest: " + error)
	for problem in problems:
		printerr("selftest: " + problem)
	if _circuit_frames < 0:
		print("selftest: no circuit, %d errors" % errors.size())
	else:
		var note := str(_note.call()) if _note.is_valid() else ""
		print("selftest: %d frames, %d errors%s" % [_circuit_frames, errors.size(), "" if note.is_empty() else " (%s)" % note])
	get_tree().quit(result(errors, problems))
