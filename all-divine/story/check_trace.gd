class_name CheckTrace
extends RefCounted
## Tells whether a function that was entered was ever left. A script error aborts a function without a word to its
## caller; so each function of the checking path enters by `enter(name)` first and leaves by `leave(name, value)` on
## every way out, and one that errored stays open: when its caller leaves, the entries above the caller's are found still
## open, and the first of them is `broken`, the place the run stopped. Only built-in calls are made here, so this cannot
## itself fail on the data it watches.

## The functions entered and not yet left, outermost first.
var trace := PackedStringArray()
## The first function found open when its caller left; empty while nothing has gone wrong.
var broken := ""


## Forgets everything: a new run.
func reset() -> void:
	trace = PackedStringArray()
	broken = ""


func enter(function: StringName) -> void:
	trace.append(String(function))


## Leaves `function`, and returns `value` so that a function can `return` through it.
func leave(function: StringName, value: Variant = null) -> Variant:
	var at := trace.rfind(String(function))
	if at < 0:
		if broken == "":
			broken = String(function)
		return value
	if at < trace.size() - 1 and broken == "":
		broken = trace[trace.size() - 1]
	trace.resize(at)
	return value


## Where the run stopped, seen from `entry` (still open): the function `broken` names, else the first one left open above
## it, not counting the last `ignoring` entries (the asker's own); empty if none.
func stopped_in(entry: StringName, ignoring := 0) -> String:
	if broken != "":
		return broken
	var at := trace.rfind(String(entry))
	if at >= 0 and at + 1 < trace.size() - ignoring:
		return trace[at + 1]
	return ""
