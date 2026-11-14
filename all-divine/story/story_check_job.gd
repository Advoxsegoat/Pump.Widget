class_name StoryCheckJob
extends RefCounted
## What the tool asks of the checker for one scene, with the rule that makes "OK" mean finished: a result is trusted only
## when the checker says it ran to its end. An entry point that was a script error from its first line returns nothing
## and says nothing; `finished` is set false before each call and only a call that got to its end sets it true, so the
## job turns a result that did not finish into a line, whatever the checker returned.

## The entry points; a call to one starts a fresh trace.
const ENTRY: Array[StringName] = [&"folder_lines", &"file_lines", &"place_lines"]

var _t := CheckTrace.new()


func _enter(function: StringName) -> void:
	if ENTRY.has(function):
		_t.reset()
	_t.enter(function)


func _leave(function: StringName, value: Variant = null) -> Variant:
	return _t.leave(function, value)


## The lines of the scene folder `folder`.
func folder_lines(checker: ShotChecker, folder: String) -> PackedStringArray:
	_enter(&"folder_lines")
	checker.finished = false
	var lines := checker.check_folder(folder)
	return _leave(&"folder_lines", _trusted(checker, lines, folder.trim_suffix("/").get_file()))


## The lines of the shots.tres at `path`.
func file_lines(checker: ShotChecker, path: String) -> PackedStringArray:
	_enter(&"file_lines")
	checker.finished = false
	var lines := checker.check_file(path)
	return _leave(&"file_lines", _trusted(checker, lines, path.get_base_dir().get_file()))


## The place lines of `scene` in `space`, the region's Spawn at `spawn` (a Vector3, or null).
func place_lines(checker: ShotChecker, scene: SceneShots, space: PhysicsDirectSpaceState3D, spawn: Variant) -> PackedStringArray:
	_enter(&"place_lines")
	checker.finished = false
	var lines := checker.check_place(scene, space, spawn)
	return _leave(&"place_lines", _trusted(checker, lines, String(scene.id)))


# `lines`, with a line added if the checker did not finish and none of them says so.
func _trusted(checker: ShotChecker, lines: PackedStringArray, name: String) -> PackedStringArray:
	_enter(&"_trusted")
	if checker.finished:
		return _leave(&"_trusted", lines)
	for line in lines:
		if line.contains("the checker stopped before it finished"):
			return _leave(&"_trusted", lines)
	lines.append("%s/-: the checker stopped before it finished (a script error; see the engine's lines above)" % name)
	return _leave(&"_trusted", lines)
