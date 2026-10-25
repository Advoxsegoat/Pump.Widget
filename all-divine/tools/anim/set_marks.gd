extends SceneTree
## Writes a clip's marks from a JSON file:
##   tools/godot.sh -s res://tools/anim/set_marks.gd -- <clip.tres> <marks.json>
## where the JSON is a list of {"frame": 10, "kind": "hitbox_on", "args": {"id": "palm_l"}} (frames at 60 Hz;
## "args" may be left out), in any order. The clip's old marks are replaced (Marks.write) and the clip is
## saved to the same file. Strings in the arguments become StringNames, as the rest of the data has them.
## Nothing is written unless every entry is good. Exits 0 on success, 1 if it could not write, 2 for a
## wrong command line. The marks are not checked against the rules of a move; tools/clip_check.gd does that.

# By path rather than by class name, so the tool also runs before the project has been imported.
const MarksScript := preload("res://moves/marks.gd")


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	if args.size() != 2:
		printerr("usage: tools/godot.sh -s res://tools/anim/set_marks.gd -- <clip.tres> <marks.json>")
		return 2
	var clip_path := args[0]
	var json_path := args[1]
	if not FileAccess.file_exists(json_path):
		printerr("set_marks.gd: no '%s'" % json_path)
		return 2
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not parsed is Array:
		printerr("set_marks.gd: '%s' is not a JSON list of marks" % json_path)
		return 1
	var marks: Array = []
	for i in (parsed as Array).size():
		var entry: Variant = parsed[i]
		var problem := _entry_problem(entry)
		if problem != "":
			printerr("set_marks.gd: %s, entry %d: %s" % [json_path, i, problem])
			return 1
		marks.append({
			"time": MarksScript.time_of(int(entry["frame"])),
			"kind": StringName(entry["kind"]),
			"args": _names(entry.get("args", {})),
		})
	var anim := ResourceLoader.load(clip_path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
	if anim == null:
		printerr("set_marks.gd: cannot load the clip '%s'" % clip_path)
		return 1
	MarksScript.write(anim, marks)
	var err := ResourceSaver.save(anim, clip_path)
	if err != OK:
		printerr("set_marks.gd: cannot write '%s': %s" % [clip_path, error_string(err)])
		return 1
	print("set_marks.gd: wrote %d marks to %s" % [marks.size(), clip_path])
	return 0


# What is wrong with one entry of the JSON, or "" if it is fine.
func _entry_problem(entry: Variant) -> String:
	if not entry is Dictionary:
		return "not an object"
	var e: Dictionary = entry
	if not (e.get("frame") is float or e.get("frame") is int) or float(e["frame"]) != floorf(float(e["frame"])) or float(e["frame"]) < 0.0:
		return "'frame' must be a whole number from 0"
	if not e.get("kind") is String or not MarksScript.KINDS.has(StringName(e["kind"])):
		return "'kind' must be one of %s" % ", ".join(PackedStringArray(MarksScript.KINDS))
	if e.has("args") and not e["args"] is Dictionary:
		return "'args' must be an object"
	return ""


# `value` with every String, in a Dictionary's keys and values and in arrays, made a StringName. JSON
# numbers come in as floats; a whole one that is a count (hitstop frames) is made an int.
func _names(value: Variant) -> Variant:
	if value is String:
		return StringName(value)
	if value is float and value == floorf(value):
		return int(value)
	if value is Dictionary:
		var out := {}
		for key in value:
			out[StringName(key) if key is String else key] = _names(value[key])
		return out
	if value is Array:
		return (value as Array).map(_names)
	return value
