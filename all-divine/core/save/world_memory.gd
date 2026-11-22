class_name WorldMemory
extends RefCounted
## What the player's deeds have changed in the world, as a set of named flags (the shortcut is open, the Collector is
## down, the Bell has been rung). A flag is only ever set, never cleared: the world remembers. It is the part of the
## saved game that the places read, so a place asks `has(&"name")` and never knows about files.

## A flag was set for the first time.
signal flagged(flag: StringName)

var _flags: Dictionary[StringName, bool] = {}


## Whether `flag` has been set.
func has(flag: StringName) -> bool:
	return _flags.has(flag)


## Sets `flag`. True, and `flagged` is emitted, only the first time; setting it again changes and says nothing.
func set_flag(flag: StringName) -> bool:
	if _flags.has(flag):
		return false
	_flags[flag] = true
	flagged.emit(flag)
	return true


## Every flag that is set, sorted, so that two memories of the same deeds list the same.
func names() -> Array[StringName]:
	var out: Array[StringName] = []
	for flag: StringName in _flags:
		out.append(flag)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The flags as they go into the file: each name (a String) to `true`, keys sorted.
func to_dict() -> Dictionary:
	var out := {}
	for flag in names():
		out[String(flag)] = true
	return out


## A memory read from `d`. Anything that is not a dictionary is an empty memory, and a value that is not `true` costs
## only its own key: a file written by a newer game or edited by hand never crashes a load.
static func from_dict(d: Variant) -> WorldMemory:
	var memory := WorldMemory.new()
	if typeof(d) != TYPE_DICTIONARY:
		return memory
	var source: Dictionary = d
	for key: Variant in source:
		if (typeof(key) == TYPE_STRING or typeof(key) == TYPE_STRING_NAME) and typeof(source[key]) == TYPE_BOOL \
				and source[key] == true:
			memory._flags[StringName(key)] = true
	return memory
