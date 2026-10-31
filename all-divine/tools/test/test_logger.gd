class_name TestLogger
extends Logger
## Collects the engine errors raised while a test runs.
##
## One shared instance is registered with OS.add_logger the first time it is
## asked for. Contexts nest: an error is recorded in the innermost (top)
## context only, so a runner that is itself under test cannot leak the errors
## of its fixtures into the test that started it. Only errors of type ERROR,
## SCRIPT and SHADER count; warnings never fail a test.

static var _shared: TestLogger

var _mutex := Mutex.new()
var _contexts: Array[PackedStringArray] = []


static func shared() -> TestLogger:
	if _shared == null:
		_shared = TestLogger.new()
		OS.add_logger(_shared)
	return _shared


func push_context() -> void:
	_mutex.lock()
	_contexts.push_back(PackedStringArray())
	_mutex.unlock()


## Ends the top context and returns the errors it captured, oldest first.
func pop_context() -> PackedStringArray:
	_mutex.lock()
	var captured := PackedStringArray()
	if not _contexts.is_empty():
		captured = _contexts.pop_back()
	_mutex.unlock()
	return captured


# Called by the engine, possibly from another thread. The text is what the engine itself prints:
# the rationale when there is one, else the code. For an error raised by the engine (push_error
# and the like) the location is the script frame that triggered it, not the engine's source line;
# script and shader errors already carry their own location.
func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := code if rationale.is_empty() else rationale
	if error_type == ERROR_TYPE_ERROR:
		for backtrace in script_backtraces:
			if backtrace != null and backtrace.get_frame_count() > 0:
				function = backtrace.get_frame_function(0)
				file = backtrace.get_frame_file(0)
				line = backtrace.get_frame_line(0)
				break
	if not file.is_empty():
		text += " (%s:%d in %s)" % [file, line, function]
	_mutex.lock()
	if not _contexts.is_empty():
		_contexts[_contexts.size() - 1].append(text)
	_mutex.unlock()
