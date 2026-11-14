class_name StoryLog
extends RefCounted
## Which scenes the player has seen to the end, so that a scene can be skipped the second time and never the first
## (Director.skip). It is kept in memory for the life of the game; the save file is the save system's to add.

static var _seen := {}


## Whether the scene `id` has been played to its end (or skipped, which is only possible after it was).
static func seen(id: StringName) -> bool:
	return _seen.has(id)


## Notes that the scene `id` has been seen.
static func mark_seen(id: StringName) -> void:
	_seen[id] = true


## Forgets every scene: the first viewing again. For tests.
static func forget_all() -> void:
	_seen.clear()
