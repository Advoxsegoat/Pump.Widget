class_name ShotChecker
extends RefCounted
## Checks that a scene's shot list names only things that exist and keeps the rules of its kind, so that "no problems"
## means the scene can be played. A problem is a line of text, "<scene>/<shot or ->: <problem>"
## ("fixture_yard_entrance/S2: gap of 10 frames between S1 and S2"); no problems is the empty array. Nothing here
## raises an error: a bad file is reported, not thrown, and a checker that did not run to its end says so (`finished`,
## and a line naming the rules it stopped in), so a crash is never read as OK.
##
## The rules (check), in the order they run:
##   enums: every enum value is one that exists (the files are written by hand, as integers); a rule that would read a bad
##       one is skipped for that item
##   folder (given a folder): script.md has words in it, notes.md's last `Status:` line says what the scene's `status`
##       does, the shot list's `id` is the folder's name; check_folder also reads shots.tres as text for a key its
##       class does not have (`kindd`), and says when a file does not parse
##   the cast: names are unique; a SPAWN has a def the Registry knows and a mark of the scene to stand on; a named live
##       actor that plays a clip has a def; a speaker is in the Registry kind `speakers`; the player is not left with an
##       enemy's brain
##   marks: each has its own name (never an actor's), an ACTOR_START mark is in the space of an actor of the cast, a
##       `rehearsal.` mark is for an actor of the cast; the `region`, when named, exists
##   the shots start at 0 and lie back to back (a gap or an overlap names its frames); each is 12 frames or more with
##       an aim, its blend_in no longer than itself, its key_frame inside it
##   a beat, a line and a cue start inside their shot; every actor, aim, focus, move_to, face, look and at_ref names an
##       actor of the cast or a mark (`name@start` is the same thing), never a `rehearsal.` mark; `@pair`, the middle
##       of a paired move, is a target only in a MOMENT; a beat does something; an actor has one clip a frame
##   a clip is a clip of the actor's rig (a LIVE_PLAYER's def is abarax); one that is not is an error, or, when the beat
##       says `placeholder`, a line that begins PLACEHOLDER (listed, not an error in a draft)
##   a line has text of at most 160 characters and 3 lines in a speaker's portrait, holds at least its typing time plus
##       20 frames and fits in its shot, and lines of one shot do not overlap
##   a sound cue is in the Registry kind `sounds`
##   the camera fields fit the move (STATIC none, PAN aim_to, DOLLY a zoom_to unlike its zoom, CRANE a pitch_to_deg
##       unlike its pitch, ORBIT a yaw_to_deg unlike its yaw, HANDHELD a shake) and the framing (OVER_SHOULDER names the
##       foreground actor, no other does), zoom is 0 to 4 and pitch -15 to -65
##   a MINI is 180 to 360 frames in all, a MOMENT one shot of 90 frames at most with no letterbox and no beats, a
##       CUTSCENE 120 frames or more; the glides are 20 to 90 frames (15 to 90 for a MOMENT)
##   every `move_to` a mark, from a place that is known (a spawn mark, a rehearsal mark, the mark of the actor's last
##       walk), fits before the actor's next `move_to` or the scene's last frame (a walk goes on across a cut), by StoryWalk: the time to be at rest
##       there. Two actors are never at rest nearer than two bodies (0.7 m) at once
##   an approved scene has no placeholder
## The marks and walks are checked in the place itself by PlaceChecker, which needs the region loaded.

## What a problem starts with when it is a listed placeholder and not an error.
const PLACEHOLDER := "placeholder: "
const MIN_SHOT_FRAMES := 12
const MAX_LINE_CHARACTERS := 160
const MAX_LINE_ROWS := 3
## The dialogue box types this many characters a second (2 frames each) ...
const FRAMES_PER_CHARACTER := 2
## ... a line must stay up for its typing time plus this many frames, and by default for this many.
const MIN_HOLD_EXTRA := 20
const DEFAULT_HOLD_EXTRA := 45
const MIN_PITCH := -65.0
const MAX_PITCH := -15.0
const DEFAULT_PITCH := -40.0
const FRAMES_PER_SECOND := 60.0
const MINI_FRAMES := Vector2i(180, 360)
const MOMENT_MAX_FRAMES := 90
const CUTSCENE_MIN_FRAMES := 120
const GLIDE_FRAMES := Vector2i(20, 90)
const MOMENT_GLIDE_FRAMES := Vector2i(15, 90)
## Two bodies: the capsules are 0.35 m in radius.
const BODIES_APART := 0.7
## The actor's capsule (actors/actor.tscn), set a little above the ground so that the floor itself is not in the way.
const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.8
const BODY_LIFT := 0.05
const FLOOR_TOLERANCE := 0.1
const WALK_SAMPLE := 0.1
## A mark is inside the region if walls stop a body on all four sides, seen at this height above the floor (a low kerb
## counts) within this distance.
const OPEN_HEIGHT := 0.15
const OPEN_DISTANCE := 80.0
const OPEN_DIRECTIONS := {"north": Vector3(0, 0, -1), "east": Vector3(1, 0, 0), "south": Vector3(0, 0, 1), "west": Vector3(-1, 0, 0)}
const REHEARSAL := "rehearsal."
const AT_START := "@start"
## The middle of the two fighters in a paired move, which the Director fills in.
const PAIR := "@pair"
## The zoom each framing has when a shot's `zoom` is 0.
const FRAMING_ZOOM: Array[int] = [1, 2, 3, 2, 4]
const STATUS_WORDS: PackedStringArray = ["draft", "in review", "approved"]
## The rules, in order. Each returns false if it did not run to its end.
const STAGES: Array[StringName] = [&"_check_enums", &"_check_folder", &"_check_cast", &"_check_marks", &"_check_layout",
		&"_check_shots", &"_check_kind", &"_check_walks"]
## Fields every resource has that a file may set.
const COMMON_KEYS: PackedStringArray = ["script", "resource_name", "resource_local_to_scene", "resource_path"]

## Whether the last `check` ran every rule to its end.
var finished := false
## The rules it stopped in, if it did not.
var stopped := ""

# The mechanism that says a rule did not run to its end. A script error aborts a function without a word to its caller,
# so every function (but the static ones, which are pure sums, and these two) enters by `_enter(&"name")` first and
# leaves by `_leave(&"name", value)` on every way out. A function that errored never left: when its caller leaves, the
# entries above the caller's are found still open and the first is `_broken`, the place the checker stopped.
# tests/story/test_shot_checker_trace.gd reads this file and fails for a function outside the pattern.
var _trace := PackedStringArray()
var _broken := ""

# actor def id -> {clip: true}; the rigs are built once per run.
var _clips := {}
var _problems := PackedStringArray()
var _scene: SceneShots
var _folder := ""
var _placeholders := 0
# Objects (by instance id) whose enums are bad: the rules that would read them skip them.
var _bad := {}
# The walks that were measured, for the place check: {actor, shot, from, to (Vector3, region space), from_mark, to_mark}.
var _walks: Array[Dictionary] = []
# The Rest intervals of the walks, for the bodies-apart rule: {actor, from, to, at (Vector3), mark}.
var _rests: Array[Dictionary] = []


func _enter(function: StringName) -> void:
	_trace.append(String(function))


func _leave(function: StringName, value: Variant = null) -> Variant:
	var at := _trace.rfind(String(function))
	if at < 0:
		if _broken == "":
			_broken = String(function)
		return value
	if at < _trace.size() - 1 and _broken == "":
		_broken = _trace[_trace.size() - 1]
	_trace.resize(at)
	return value


## The seconds a body takes to cover `metres` from rest at `pace` and stop pushing, with `def`'s accel and decel: the
## formula of Main._leg (the frames a push takes to cover a distance) solved for the time. It is not the time to
## arrive: the body coasts after the push, which StoryWalk.frames counts and the checker uses.
static func travel_seconds(def: ActorDef, pace: ActorBeat.Pace, metres: float) -> float:
	var v := Locomotion.new(def.locomotion).target_speed(StoryWalk.push_of(pace), false)
	var tuning := def.locomotion
	return (metres + v * v / (2.0 * tuning.accel) - v * v / (2.0 * tuning.decel)) / v


## The frames a line takes to type.
static func typing_frames(text: String) -> int:
	return text.length() * FRAMES_PER_CHARACTER


## The frames a line stays up: its `hold`, or its typing time plus 45 when that is 0.
static func hold_of(line: DialogueLine) -> int:
	return line.hold if line.hold > 0 else typing_frames(line.text) + DEFAULT_HOLD_EXTRA


## Whether a line from `check` is a listed placeholder and not an error.
static func is_placeholder(line: String) -> bool:
	var colon := line.find(": ")
	return colon >= 0 and line.substr(colon + 2).begins_with(PLACEHOLDER)


## Every scene folder under `root`, checked as `check_folder` does. A folder with no readable shots.tres is a problem of
## its own.
func check_all(root := "res://scenes/story") -> PackedStringArray:
	_enter(&"check_all")
	var out := PackedStringArray()
	for folder in scene_folders(root):
		out.append_array(check_folder(root.path_join(folder)))
	return _leave(&"check_all", out)


## The names of the scene folders under `root`, sorted.
func scene_folders(root := "res://scenes/story") -> PackedStringArray:
	_enter(&"scene_folders")
	var found := PackedStringArray()
	for entry in ResourceLoader.list_directory(root):
		if entry.ends_with("/"):
			found.append(entry.trim_suffix("/"))
	found.sort()
	return _leave(&"scene_folders", found)


## One scene folder: its shots.tres read as text for keys the class lacks, loaded, and checked with the folder.
func check_folder(folder: String) -> PackedStringArray:
	_enter(&"check_folder")
	var name := folder.trim_suffix("/").get_file()
	var path := folder.path_join("shots.tres")
	var loaded := _load(path, name)
	if loaded.scene == null:
		return _leave(&"check_folder", loaded.problems)
	var out: PackedStringArray = loaded.problems
	if not loaded.get("blocking", false):
		out.append_array(check(loaded.scene, folder))
		if not finished and not _said_stopped(out):
			out.append("%s/-: the checker stopped before it finished (a script error; see the engine's lines above)" % loaded.scene.id)
	return _leave(&"check_folder", out)


## One shots.tres anywhere (a combat moment's, say), checked without a folder.
func check_file(path: String) -> PackedStringArray:
	_enter(&"check_file")
	var loaded := _load(path, path.get_base_dir().get_file())
	if loaded.scene == null:
		return _leave(&"check_file", loaded.problems)
	var out: PackedStringArray = loaded.problems
	if not loaded.get("blocking", false):
		out.append_array(check(loaded.scene))
		if not finished and not _said_stopped(out):
			out.append("%s/-: the checker stopped before it finished (a script error; see the engine's lines above)" % loaded.scene.id)
	return _leave(&"check_file", out)


## The problems of `scene`; with a `folder`, also those of its script.md, notes.md and id. `finished` says whether every
## rule ran to its end; if one did not, the last line says which.
func check(scene: SceneShots, folder := "") -> PackedStringArray:
	_enter(&"check")
	_scene = scene
	_folder = folder
	_problems = PackedStringArray()
	_placeholders = 0
	_bad = {}
	_rests = []
	_walks = []
	_broken = ""
	finished = false
	stopped = ""
	for stage in STAGES:
		if not call(stage) and _broken == "":
			_broken = String(stage)
		if _broken != "":
			break
	if _broken != "":
		stopped = _broken.trim_prefix("_check_")
		_add("-", "the checker stopped before it finished: in %s (a script error; see the engine's lines above)" % _described(_broken))
		return _leave(&"check", _problems)
	if scene.status == SceneShots.Status.APPROVED and _placeholders > 0:
		_add("-", "an approved scene has no placeholder, this one has %d" % _placeholders)
	finished = true
	return _leave(&"check", _problems)


# Whether `lines` already say the checker stopped.
func _said_stopped(lines: PackedStringArray) -> bool:
	_enter(&"_said_stopped")
	for line in lines:
		if line.contains("the checker stopped before it finished"):
			return _leave(&"_said_stopped", true)
	return _leave(&"_said_stopped", false)


# Where the checker stopped, in a writer's words: a stage is "the marks rules", a helper "the helper _check_target".
func _described(function: String) -> String:
	_enter(&"_described")
	if STAGES.has(StringName(function)):
		return _leave(&"_described", "the %s rules" % function.trim_prefix("_check_"))
	return _leave(&"_described", "the helper %s" % function)


# --- the file ---

# {scene: SceneShots or null, problems, blocking} for a shots.tres at `path`, `name` standing for it in a line.
func _load(path: String, name: String) -> Dictionary:
	_enter(&"_load")
	if not FileAccess.file_exists(path):
		return _leave(&"_load", {scene = null, problems = PackedStringArray(["%s/-: %s is missing (%s)" % [name, path.get_file(), path]])})
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		# the text may say why: an element of the wrong class in a typed array fails some loads outright
		var why: PackedStringArray = _file_problems(path, name).lines
		if not why.is_empty():
			return _leave(&"_load", {scene = null, problems = why})
		return _leave(&"_load", {scene = null, problems = PackedStringArray(["%s/-: %s does not parse; see the engine's lines above (%s)" % [name, path.get_file(), path]])})
	var scene := resource as SceneShots
	if scene == null:
		return _leave(&"_load", {scene = null, problems = PackedStringArray(["%s/-: %s is not a SceneShots (%s)" % [name, path.get_file(), path]])})
	var file := _file_problems(path, String(scene.id) if scene.id != &"" else name)
	return _leave(&"_load", {scene = scene, problems = file.lines, blocking = file.blocking})


# What the file's text says that the loaded scene would not show: a key its resource's class does not have (Godot ignores
# it in silence), and an element of a typed array that is of another class, a string or null (the loader prints an
# error and drops the whole array). Returns {lines, blocking}: blocking when an array lost elements, since the scene
# that loaded is then not what was written and checking it would only list what the loss caused.
func _file_problems(path: String, name: String) -> Dictionary:
	_enter(&"_file_problems")
	var scripts := {}   # ext_resource id -> script path
	var blocks: Array[Dictionary] = []   # {id, script, keys: [[key, value]]}
	var header := RegEx.create_from_string("^\\[ext_resource\\b(?=.*type=\"Script\")(?=.*path=\"([^\"]+)\")(?=.*\\bid=\"([^\"]+)\")")
	var sub_id := RegEx.create_from_string("^\\[sub_resource\\b.*\\bid=\"([^\"]+)\"")
	var key := RegEx.create_from_string("^([A-Za-z_][A-Za-z0-9_]*) = (.*)$")
	var ext := RegEx.create_from_string("ExtResource\\(\"([^\"]+)\"\\)")
	var block: Dictionary = {}
	var lines := FileAccess.get_file_as_string(path).split("\n")
	lines.append("[end]")
	for text in lines:
		if text.begins_with("["):
			if not block.is_empty():
				blocks.append(block)
			block = {}
			if text.begins_with("[sub_resource") or text.begins_with("[resource]"):
				var found_id := sub_id.search(text)
				block = {id = found_id.get_string(1) if found_id != null else "", script = "", keys = []}
			var found := header.search(text)
			if found != null:
				scripts[found.get_string(2)] = found.get_string(1)
		elif not block.is_empty():
			var match := key.search(text)
			if match == null:
				continue
			if match.get_string(1) == "script":
				var which := ext.search(match.get_string(2))
				block.script = scripts.get(which.get_string(1), "") if which != null else ""
			else:
				block.keys.append([match.get_string(1), match.get_string(2)])
	var out := PackedStringArray()
	var by_id := {}
	for each in blocks:
		if each.id != "":
			by_id[each.id] = each
	for each in blocks:
		if each.script != "":
			out.append_array(_keys_unknown_to(each.script, each.keys, name))
	var dropped := PackedStringArray()
	for each in blocks:
		if each.script != "":
			dropped.append_array(_dropped_elements(each, scripts, by_id, name))
	out.append_array(dropped)
	return _leave(&"_file_problems", {lines = out, blocking = not dropped.is_empty()})


func _keys_unknown_to(script_path: String, keys: Array, name: String) -> PackedStringArray:
	_enter(&"_keys_unknown_to")
	var out := PackedStringArray()
	var script := load(script_path) as GDScript
	if script == null:
		return _leave(&"_keys_unknown_to", out)
	var fields := PackedStringArray()
	for info in script.get_script_property_list():
		if info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(info.name)
	var class_title := script.get_global_name()
	for pair in keys:
		var key: String = pair[0]
		if fields.has(key) or COMMON_KEYS.has(key):
			continue
		var best := ""
		var best_score := 0.5
		for field in fields:
			var score := key.similarity(field)
			if score > best_score:
				best = field
				best_score = score
		var help := " (did you mean '%s'?)" % best if best != "" else " (its fields: %s)" % ", ".join(fields)
		var where := _owner_label(script, pair, keys)
		out.append("%s/-: shots.tres: '%s' is not a field of %s%s%s; Godot ignores it" % [name, key, class_title, help, "" if where == class_title else "; found in " + where])
	return _leave(&"_keys_unknown_to", out)


# "SceneShots" for the file's own resource, "Shot 'S2'" for a sub-resource with an id of its own (a shot, a cast entry, a mark).
func _owner_label(script: GDScript, _pair: Array, keys: Array) -> String:
	_enter(&"_owner_label")
	var title := script.get_global_name()
	for each in keys:
		if each[0] in ["id", "actor", "name"]:
			return _leave(&"_owner_label", "%s '%s'" % [title, String(each[1]).trim_prefix("&").trim_prefix("\"").trim_suffix("\"")] if title != "SceneShots" else title)
	return _leave(&"_owner_label", title)


# The elements of a typed array in a block that the loader would drop: other than the array's own class, strings, null.
func _dropped_elements(block: Dictionary, scripts: Dictionary, by_id: Dictionary, name: String) -> PackedStringArray:
	_enter(&"_dropped_elements")
	var out := PackedStringArray()
	var script := load(block.script) as GDScript
	var owner_text: String = _owner_label(script, [], block.keys) if script != null else String(block.script)
	var typed := RegEx.create_from_string("^Array\\[ExtResource\\(\"([^\"]+)\"\\)\\]\\(\\[")
	var sub := RegEx.create_from_string("^SubResource\\(\"([^\"]+)\"\\)$")
	for pair in block.keys:
		var value: String = pair[1]
		var found := typed.search(value)
		if found == null:
			continue
		var wanted: String = scripts.get(found.get_string(1), "")
		var wanted_script := load(wanted) as GDScript
		var title: String = wanted_script.get_global_name() if wanted_script != null else wanted.get_file()
		var wrong := 0
		var empty := 0
		for element in _elements(value.substr(found.get_end())):
			var as_sub := sub.search(element)
			if element == "null":
				empty += 1
			elif as_sub == null or not by_id.has(as_sub.get_string(1)) or by_id[as_sub.get_string(1)].script != wanted:
				wrong += 1
		if wrong > 0:
			out.append("%s/-: shots.tres: %s: '%s' has %d element%s that is not %s %s (the loader drops the whole array)" % [
					name, owner_text, pair[0], wrong, "" if wrong == 1 else "s", "an" if title[0] in "AEIOU" else "a", title])
		if empty > 0:
			out.append("%s/-: shots.tres: %s: '%s' has %d empty (null) element%s" % [name, owner_text, pair[0], empty, "" if empty == 1 else "s"])
	return _leave(&"_dropped_elements", out)


# The top-level elements of an array's text, which starts just inside its `[` and ends at the matching `]`.
func _elements(text: String) -> PackedStringArray:
	_enter(&"_elements")
	var out := PackedStringArray()
	var depth := 0
	var quoted := false
	var current := ""
	for i in text.length():
		var c := text[i]
		if quoted:
			current += c
			if c == "\"" and text[i - 1] != "\\":
				quoted = false
		elif c == "\"":
			quoted = true
			current += c
		elif c == "(" or c == "[" or c == "{":
			depth += 1
			current += c
		elif (c == ")" or c == "]" or c == "}") and depth > 0:
			depth -= 1
			current += c
		elif c == "]":
			break
		elif c == "," and depth == 0:
			out.append(current.strip_edges())
			current = ""
		else:
			current += c
	if current.strip_edges() != "":
		out.append(current.strip_edges())
	return _leave(&"_elements", out)


# --- the enums ---

func _check_enums() -> bool:
	_enter(&"_check_enums")
	_enum("-", "kind", _scene.kind, SceneShots.Kind, _scene)
	_enum("-", "status", _scene.status, SceneShots.Status, _scene)
	for entry in _scene.cast:
		_enum("-", "%s: source" % entry.actor, entry.source, CastEntry.Source, entry)
		_enum("-", "%s: after" % entry.actor, entry.after, CastEntry.After, entry)
	for mark in _scene.marks:
		_enum("-", "mark '%s': space" % mark.name, mark.space, SceneMark.Space, mark)
	for shot in _scene.shots:
		_enum(String(shot.id), "framing", shot.framing, Shot.Framing, shot)
		_enum(String(shot.id), "move", shot.move, Shot.CamMove, shot)
		for beat in shot.beats:
			_enum(String(shot.id), "beat at frame %d: pace" % beat.at, beat.pace, ActorBeat.Pace, beat)
		for cue in shot.cues:
			_enum(String(shot.id), "cue kind", cue.kind, CueEvent.Kind, cue)
	return _leave(&"_check_enums", true)


# Notes a bad enum value `value` of `field` on `owner`: a line, and the owner is skipped by the rules that read it.
# The field's own words come first ("framing 9 is not one of ..."), and a field label with a colon says whose it is.
func _enum(where: String, field: String, value: int, kind: Dictionary, owner: Object) -> void:
	_enter(&"_enum")
	if kind.values().has(value):
		_leave(&"_enum")
		return
	_bad[owner.get_instance_id()] = true
	var names := PackedStringArray()
	for key: String in kind:
		names.append("%d (%s)" % [kind[key], key])
	var label := field.get_slice(": ", 1) if field.contains(": ") else field
	var owner_text := field.get_slice(": ", 0) + ": " if field.contains(": ") else ""
	_add(where, "%s%s %d is not one of %s" % [owner_text, label, value, ", ".join(names)])
	_leave(&"_enum")


func _ok(owner: Object) -> bool:
	_enter(&"_ok")
	return _leave(&"_ok", not _bad.has(owner.get_instance_id()))


# --- the folder ---

func _check_folder() -> bool:
	_enter(&"_check_folder")
	if _folder == "":
		return _leave(&"_check_folder", true)
	var name := _folder.trim_suffix("/").get_file()
	if String(_scene.id) != name:
		_add("-", "id '%s' is not the folder name '%s'" % [_scene.id, name])
	var script := _folder.path_join("script.md")
	if not FileAccess.file_exists(script):
		_add("-", "script.md is missing")
	elif FileAccess.get_file_as_string(script).strip_edges() == "":
		_add("-", "script.md is empty")
	var notes := _folder.path_join("notes.md")
	if not FileAccess.file_exists(notes):
		_add("-", "notes.md is missing")
		return _leave(&"_check_folder", true)
	var last := ""
	for text in FileAccess.get_file_as_string(notes).split("\n"):
		if text.strip_edges().to_lower().begins_with("status:"):
			last = text.strip_edges()
	if last == "":
		_add("-", "notes.md has no 'Status:' line")
		return _leave(&"_check_folder", true)
	var said := last.substr(last.find(":") + 1).strip_edges().to_lower()
	if _ok(_scene) and said != STATUS_WORDS[_scene.status]:
		_add("-", "notes.md ends with '%s' but the scene is %s" % [last, STATUS_WORDS[_scene.status]])
	return _leave(&"_check_folder", true)


# --- the cast and the marks ---

func _check_cast() -> bool:
	_enter(&"_check_cast")
	var seen := {}
	for entry in _scene.cast:
		var who := String(entry.actor)
		if who == "":
			_add("-", "a cast entry has no actor name")
			continue
		if seen.has(who):
			_add("-", "'%s' is in the cast twice" % who)
		seen[who] = true
		if _ok(entry):
			if entry.source == CastEntry.Source.SPAWN:
				if entry.def == null:
					_add("-", "%s has no def to spawn" % who)
				elif not Registry.ids(&"actors").has(String(entry.def.id)):
					_add("-", "%s: its def '%s' is not in the Registry" % [who, entry.def.id])
				var mark := _scene.mark(entry.spawn_mark)
				if mark == null or String(mark.name).begins_with(REHEARSAL):
					_add("-", "%s: spawn mark '%s' is not a mark of the scene" % [who, entry.spawn_mark])
			elif entry.source == CastEntry.Source.LIVE_NAMED and entry.node_name == &"":
				_add("-", "%s is LIVE_NAMED but has no node_name" % who)
			if entry.source == CastEntry.Source.LIVE_PLAYER and entry.after == CastEntry.After.ENEMY_BRAIN:
				_add("-", "%s is the player's and cannot be left with ENEMY_BRAIN" % who)
		if entry.speaker != &"" and not Registry.ids(&"speakers").has(String(entry.speaker)):
			_add("-", "%s: speaker '%s' is not in the Registry" % [who, entry.speaker])
	return _leave(&"_check_cast", true)


func _check_marks() -> bool:
	_enter(&"_check_marks")
	var seen := {}
	for mark in _scene.marks:
		var name := String(mark.name)
		if name == "":
			_add("-", "a mark has no name")
			continue
		if seen.has(name):
			_add("-", "mark '%s' is in the scene twice" % name)
		seen[name] = true
		if _scene.cast_entry(mark.name) != null:
			_add("-", "mark '%s' has the name of an actor" % name)
		if _ok(mark) and mark.space == SceneMark.Space.ACTOR_START and _scene.cast_entry(mark.actor) == null:
			_add("-", "mark '%s' is placed in the space of '%s', who is not in the cast" % [name, mark.actor])
		if name.begins_with(REHEARSAL) and _scene.cast_entry(StringName(name.trim_prefix(REHEARSAL))) == null:
			_add("-", "rehearsal mark '%s' is for '%s', who is not in the cast" % [name, name.trim_prefix(REHEARSAL)])
	if _scene.region != "" and not ResourceLoader.exists(_scene.region):
		_add("-", "region '%s' does not exist" % _scene.region)
	return _leave(&"_check_marks", true)


# --- the shot list ---

func _check_layout() -> bool:
	_enter(&"_check_layout")
	if _scene.shots.is_empty():
		_add("-", "the scene has no shots")
		return _leave(&"_check_layout", true)
	var ids := {}
	for i in _scene.shots.size():
		var shot := _scene.shots[i]
		if shot.id == &"" or ids.has(shot.id):
			_add(_name(shot, i), "the shot id is empty or used twice")
		ids[shot.id] = true
		if i == 0:
			if shot.start != 0:
				_add(_name(shot, i), "starts at frame %d, not 0" % shot.start)
			continue
		var before := _scene.shots[i - 1]
		var gap := shot.start - (before.start + before.length)
		var ends := "(%s ends at frame %d, %s starts at %d)" % [_name(before, i - 1), before.start + before.length, _name(shot, i), shot.start]
		if gap > 0:
			_add(_name(shot, i), "gap of %d frames between %s and %s %s" % [gap, _name(before, i - 1), _name(shot, i), ends])
		elif gap < 0:
			_add(_name(shot, i), "overlap of %d frames between %s and %s %s" % [-gap, _name(before, i - 1), _name(shot, i), ends])
	return _leave(&"_check_layout", true)


func _check_shots() -> bool:
	_enter(&"_check_shots")
	var ok := true
	for shot in _scene.shots:
		ok = _check_shot(shot) and ok
	return _leave(&"_check_shots", ok)


func _check_shot(shot: Shot) -> bool:
	_enter(&"_check_shot")
	var where := String(shot.id)
	var ok := true
	if shot.length < MIN_SHOT_FRAMES:
		_add(where, "is %d frames, under the %d a shot needs" % [shot.length, MIN_SHOT_FRAMES])
	if shot.aim == &"":
		_add(where, "has no aim: the camera has nothing to look at")
	if _ok(shot):
		ok = _check_camera(shot) and ok
	for target in [["aim", shot.aim], ["aim_to", shot.aim_to], ["over_shoulder", shot.over_shoulder],
			["focus", shot.focus], ["focus_to", shot.focus_to]]:
		_check_target(where, target[0], target[1])
	if shot.length <= 0:
		return _leave(&"_check_shot", ok)   # one fault, one line: what depends on a length has none to depend on
	if shot.blend_in > shot.length:
		_add(where, "blend_in %d is longer than the shot (%d frames)" % [shot.blend_in, shot.length])
	if shot.key_frame < -1 or shot.key_frame >= shot.length:
		_add(where, "key_frame %d is outside the shot (-1 or 0 to %d)" % [shot.key_frame, shot.length - 1])
	var clips := {}   # "actor@frame" -> true
	for beat in shot.beats:
		ok = _check_beat(shot, beat) and ok
		if beat.clip != &"":
			var at := "%s@%d" % [beat.actor, beat.at]
			if clips.has(at):
				_add(where, "%s has two clips at frame %d" % [beat.actor, beat.at])
			clips[at] = true
	for line in shot.lines:
		ok = _check_line(shot, line) and ok
	ok = _check_line_overlaps(shot) and ok
	for cue in shot.cues:
		ok = _check_cue(shot, cue) and ok
	return _leave(&"_check_shot", ok)


func _check_camera(shot: Shot) -> bool:
	_enter(&"_check_camera")
	var where := String(shot.id)
	var move: String = Shot.CamMove.keys()[shot.move]
	var framing: String = Shot.Framing.keys()[shot.framing]
	var zoom := shot.zoom if shot.zoom != 0 else FRAMING_ZOOM[shot.framing]
	if shot.zoom < 0 or shot.zoom > 4:
		_add(where, "zoom %d is not 0 to 4" % shot.zoom)
	if shot.zoom_to < 0 or shot.zoom_to > 4:
		_add(where, "zoom_to %d is not 0 to 4" % shot.zoom_to)
	if shot.pitch_deg < MIN_PITCH or shot.pitch_deg > MAX_PITCH:
		_add(where, "pitch %s is outside %d to %d degrees" % [String.num(shot.pitch_deg), int(MIN_PITCH), int(MAX_PITCH)])
	var pitch_set := not is_equal_approx(shot.pitch_to_deg, shot.pitch_deg) and not is_equal_approx(shot.pitch_to_deg, DEFAULT_PITCH)
	if pitch_set and (shot.pitch_to_deg < MIN_PITCH or shot.pitch_to_deg > MAX_PITCH):
		_add(where, "pitch_to %s is outside %d to %d degrees" % [String.num(shot.pitch_to_deg), int(MIN_PITCH), int(MAX_PITCH)])
	var yaw_set := not is_zero_approx(shot.yaw_to_deg) and not is_equal_approx(shot.yaw_to_deg, shot.yaw_deg)
	if shot.move != Shot.CamMove.PAN and shot.aim_to != &"":
		_add(where, "aim_to is set but the move is %s" % move)
	if shot.move != Shot.CamMove.DOLLY and shot.zoom_to != 0:
		_add(where, "zoom_to is set but the move is %s" % move)
	if shot.move != Shot.CamMove.ORBIT and yaw_set:
		_add(where, "yaw_to_deg is set but the move is %s" % move)
	if shot.move != Shot.CamMove.CRANE and pitch_set:
		_add(where, "pitch_to_deg is set but the move is %s" % move)
	if shot.move != Shot.CamMove.HANDHELD and shot.shake > 0.0:
		_add(where, "shake is set but the move is %s" % move)
	if shot.move == Shot.CamMove.PAN and shot.aim_to == &"":
		_add(where, "PAN has no aim_to")
	if shot.move == Shot.CamMove.DOLLY:
		if shot.zoom_to == 0:
			_add(where, "DOLLY has no zoom_to")
		elif shot.zoom_to == zoom:
			_add(where, "DOLLY zoom_to %d is the same as its zoom" % shot.zoom_to)
	if shot.move == Shot.CamMove.CRANE and not pitch_set:
		_add(where, "CRANE pitch_to_deg is the same as its pitch_deg")
	if shot.move == Shot.CamMove.ORBIT and not yaw_set:
		_add(where, "ORBIT yaw_to_deg is the same as its yaw_deg")
	if shot.move == Shot.CamMove.HANDHELD and shot.shake <= 0.0:
		_add(where, "HANDHELD has no shake above 0")
	if shot.framing == Shot.Framing.OVER_SHOULDER and shot.over_shoulder == &"":
		_add(where, "OVER_SHOULDER has no over_shoulder actor")
	if shot.framing != Shot.Framing.OVER_SHOULDER and shot.over_shoulder != &"":
		_add(where, "over_shoulder is set but the framing is %s" % framing)
	return _leave(&"_check_camera", true)


func _check_beat(shot: Shot, beat: ActorBeat) -> bool:
	_enter(&"_check_beat")
	var where := String(shot.id)
	var what := "beat at frame %d" % beat.at
	if beat.at < 0 or beat.at >= shot.length:
		_add(where, "%s is outside the shot (frames 0 to %d)" % [what, shot.length - 1])
	var entry := _scene.cast_entry(beat.actor)
	if entry == null:
		_add(where, "%s: '%s' is not in the cast" % [what, beat.actor])
	for target in [["move_to", beat.move_to], ["face", beat.face], ["look", beat.look]]:
		_check_target(where, target[0], target[1], what)
	if beat.clip == &"" and beat.move_to == &"" and beat.face == &"" and beat.look == &"":
		_add(where, "%s does nothing: it has no clip, move_to, face or look" % what)
	if beat.clip == &"" or entry == null:
		return _leave(&"_check_beat", true)
	var def := _def_of(entry)
	if def == null:
		if entry.source == CastEntry.Source.LIVE_NAMED:
			_add(where, "%s plays the clip '%s' but has no def to look it up in" % [beat.actor, beat.clip])
		return _leave(&"_check_beat", true)
	if not _clip_names(def).has(beat.clip):
		if beat.placeholder:
			_placeholders += 1
			_add(where, "%s%s has no clip '%s'" % [PLACEHOLDER, beat.actor, beat.clip])
		else:
			_add(where, "%s has no clip '%s' in its rig (%s); fix the name, or set the beat's placeholder" % [beat.actor, beat.clip, def.id])
	return _leave(&"_check_beat", true)


func _check_line(shot: Shot, line: DialogueLine) -> bool:
	_enter(&"_check_line")
	var where := String(shot.id)
	var speaker: Speaker = null
	if line.speaker == &"":
		_add(where, "a line has no speaker")
	elif not Registry.ids(&"speakers").has(String(line.speaker)):
		_add(where, "speaker '%s' is not in the Registry" % line.speaker)
	else:
		speaker = Registry.fetch(&"speakers", line.speaker) as Speaker
	if speaker != null and not speaker.portraits.has(line.expr):
		_add(where, "speaker '%s' has no '%s' portrait" % [line.speaker, line.expr])
	if line.text.strip_edges() == "":
		_add(where, "the line at frame %d has no text" % line.at)
		return _leave(&"_check_line", true)
	if line.text.length() > MAX_LINE_CHARACTERS:
		_add(where, "the line at frame %d is %d characters, at most %d" % [line.at, line.text.length(), MAX_LINE_CHARACTERS])
	var rows := line.text.split("\n").size()
	if rows > MAX_LINE_ROWS:
		_add(where, "the line at frame %d has %d lines, the box holds %d" % [line.at, rows, MAX_LINE_ROWS])
	if line.at < 0 or line.at >= shot.length:
		_add(where, "line at frame %d is outside the shot (frames 0 to %d)" % [line.at, shot.length - 1])
		return _leave(&"_check_line", true)
	var typing := typing_frames(line.text)
	if line.hold > 0 and line.hold < typing + MIN_HOLD_EXTRA:
		_add(where, "the line at frame %d: a hold of %d frames is under the %d it needs (typing %d plus %d)" % [
				line.at, line.hold, typing + MIN_HOLD_EXTRA, typing, MIN_HOLD_EXTRA])
	var end := line.at + hold_of(line)
	if end > shot.length:
		_add(where, "the line at frame %d cannot finish: it needs frames %d to %d and the shot ends at %d" % [
				line.at, line.at, end, shot.length])
	return _leave(&"_check_line", true)


func _check_line_overlaps(shot: Shot) -> bool:
	_enter(&"_check_line_overlaps")
	var lines: Array[DialogueLine] = shot.lines.duplicate()
	lines.sort_custom(func(a: DialogueLine, b: DialogueLine) -> bool: return a.at < b.at)
	for i in range(1, lines.size()):
		var before := lines[i - 1]
		if lines[i].at < before.at + hold_of(before):
			_add(String(shot.id), "the line at frame %d overlaps the line at frame %d, which is up until frame %d" % [
					lines[i].at, before.at, before.at + hold_of(before)])
	return _leave(&"_check_line_overlaps", true)


func _check_cue(shot: Shot, cue: CueEvent) -> bool:
	_enter(&"_check_cue")
	var where := String(shot.id)
	if cue.at < 0 or cue.at >= shot.length:
		_add(where, "cue at frame %d is outside the shot (frames 0 to %d)" % [cue.at, shot.length - 1])
	if cue.id == &"":
		_add(where, "the cue at frame %d has no id" % cue.at)
	elif _ok(cue) and cue.kind == CueEvent.Kind.SOUND and not Registry.ids(&"sounds").has(String(cue.id)):
		_add(where, "sound '%s' is not in the Registry" % cue.id)
	_check_target(where, "at_ref", cue.at_ref, "cue at frame %d" % cue.at)
	return _leave(&"_check_cue", true)


# A target field: empty is fine; otherwise an actor of the cast or a mark, `@start` allowed, never a rehearsal mark.
# `@pair` is the middle of a paired move: only a MOMENT has one.
func _check_target(where: String, field: String, target: StringName, what := "") -> void:
	_enter(&"_check_target")
	if target == &"":
		_leave(&"_check_target")
		return
	var prefix := what + ": " if what != "" else ""
	if String(target) == PAIR:
		if _scene.kind != SceneShots.Kind.MOMENT:
			_add(where, "%s%s '%s' is the middle of a paired move, which only a MOMENT has" % [prefix, field, target])
		_leave(&"_check_target")
		return
	var name := String(target).trim_suffix(AT_START)
	if name.begins_with(REHEARSAL):
		_add(where, "%s%s '%s' is a rehearsal mark, which a shot may not name" % [prefix, field, target])
	elif _scene.mark(StringName(name)) == null and _scene.cast_entry(StringName(name)) == null:
		var actors := PackedStringArray()
		for entry in _scene.cast:
			actors.append(String(entry.actor))
		var marks := PackedStringArray()
		for mark in _scene.marks:
			if not String(mark.name).begins_with(REHEARSAL):
				marks.append(String(mark.name))
		_add(where, "%s%s '%s' is no actor or mark of the scene (actors: %s; marks: %s)" % [
				prefix, field, target, ", ".join(actors), ", ".join(marks)])
	_leave(&"_check_target")


# --- the kinds ---

func _check_kind() -> bool:
	_enter(&"_check_kind")
	var total := _scene.total_frames()
	if _ok(_scene):
		match _scene.kind:
			SceneShots.Kind.MINI:
				if total < MINI_FRAMES.x or total > MINI_FRAMES.y:
					_add("-", "a MINI is %d to %d frames in all, this one is %d" % [MINI_FRAMES.x, MINI_FRAMES.y, total])
			SceneShots.Kind.CUTSCENE:
				if total < CUTSCENE_MIN_FRAMES:
					_add("-", "a CUTSCENE is %d frames or more, this one is %d" % [CUTSCENE_MIN_FRAMES, total])
			SceneShots.Kind.MOMENT:
				if _scene.shots.size() != 1:
					_add("-", "a MOMENT has one shot, this one has %d" % _scene.shots.size())
				if total > MOMENT_MAX_FRAMES:
					_add("-", "a MOMENT is %d frames at most, this one is %d" % [MOMENT_MAX_FRAMES, total])
				if _scene.letterbox:
					_add("-", "a MOMENT has no letterbox")
				for shot in _scene.shots:
					if not shot.beats.is_empty():
						_add(String(shot.id), "a MOMENT has no beats")
	var glide := MOMENT_GLIDE_FRAMES if _scene.kind == SceneShots.Kind.MOMENT else GLIDE_FRAMES
	for field in [["lead_in", _scene.lead_in], ["lead_out", _scene.lead_out]]:
		if field[1] < glide.x or field[1] > glide.y:
			_add("-", "%s %d is not %d to %d" % [field[0], field[1], glide.x, glide.y])
	return _leave(&"_check_kind", true)


# --- walking ---

# Each actor's `move_to`s in time order, by StoryWalk: a walk to a mark, from a place that is known, is over (the body
# at rest within the arrival distance) before the actor's next `move_to` or the scene's last frame. Where a body stands is
# known from its spawn mark (a spawned actor) or its rehearsal mark (a live one) and from the mark of its last walk.
# Then no two bodies are at rest nearer than two bodies.
func _check_walks() -> bool:
	_enter(&"_check_walks")
	var end := 0
	for shot in _scene.shots:
		end = maxi(end, shot.start + shot.length)
	for entry in _scene.cast:
		if not _ok(entry):
			continue
		var def := _def_of(entry)
		var beats: Array[Dictionary] = []   # {frame, beat, shot} of the walks
		for shot in _scene.shots:
			for beat in shot.beats:
				if beat.actor == entry.actor and beat.move_to != &"" and _ok(beat):
					beats.append({frame = shot.start + beat.at, beat = beat, shot = shot})
		beats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.frame < b.frame)
		var known: SceneMark = null
		if entry.source == CastEntry.Source.SPAWN:
			known = _scene.mark(entry.spawn_mark)
		else:
			known = _scene.mark(StringName(REHEARSAL + String(entry.actor)))
		var walking := not beats.is_empty()
		if walking and known == null and entry.source != CastEntry.Source.SPAWN:
			_add(String(beats[0].shot.id), "%s walks but the scene has no '%s%s' mark to start it from" % [entry.actor, REHEARSAL, entry.actor])
		if walking and (def == null or def.locomotion == null):
			if entry.source != CastEntry.Source.SPAWN:   # a spawn with no def is reported with the cast
				_add(String(beats[0].shot.id), "%s walks but has no def to take its speed from" % entry.actor)
			continue
		var first: int = beats[0].frame if walking else end
		_rest(entry, known, 0, first)
		for i in beats.size():
			var beat: ActorBeat = beats[i].beat
			var shot: Shot = beats[i].shot
			var to := _scene.mark(StringName(String(beat.move_to).trim_suffix(AT_START)))
			var next: int = beats[i + 1].frame if i + 1 < beats.size() else end
			if to == null:
				_rest(entry, null, beats[i].frame, next)   # walking to an actor: not measured
				known = null
				continue
			var from_at: Variant = _scene.region_position(known)
			var to_at: Variant = _scene.region_position(to)
			var metres := -1.0
			if from_at != null and to_at != null:
				metres = Vector2(from_at.x - to_at.x, from_at.z - to_at.z).length()
			elif known != null and known.space == to.space and known.actor == to.actor:
				metres = Vector2(known.position.x - to.position.x, known.position.z - to.position.z).length()
			if from_at != null and to_at != null and known != null:
				_walks.append({actor = entry.actor, shot = shot.id, from = from_at, to = to_at, from_mark = known.name, to_mark = to.name})
			var arrive: int = beats[i].frame
			if metres >= 0.0 and def != null and def.locomotion != null:
				var needed := StoryWalk.frames(def.locomotion, beat.pace, metres)
				if needed < 0:
					_add(String(shot.id), "%s: could not work out how long a walk of %.1f m takes (the locomotion numbers give no speed)" % [entry.actor, metres])
					needed = 0
				var left: int = next - beats[i].frame
				arrive += needed
				if needed > left:
					_add(String(shot.id), "%s needs %.2f s (%d frames) to walk %.1f m at %s to '%s' and come to rest, but has %.2f s (%d frames) before %s" % [
							entry.actor, float(needed) / FRAMES_PER_SECOND, needed, metres, ActorBeat.Pace.keys()[beat.pace], beat.move_to,
							float(left) / FRAMES_PER_SECOND, left, "its next move_to" if i + 1 < beats.size() else "the end of the scene"])
			_rest(entry, to, mini(arrive, next), next)
			known = to
	_check_bodies_apart()
	return _leave(&"_check_walks", true)


# Notes that `entry`'s body is at rest at `mark` from frame `from` up to frame `to`.
func _rest(entry: CastEntry, mark: SceneMark, from: int, to: int) -> void:
	_enter(&"_rest")
	if mark == null or to <= from:
		_leave(&"_rest")
		return
	var at: Variant = _scene.region_position(mark)
	if at != null:
		_rests.append({actor = entry.actor, from = from, to = to, at = at, mark = mark.name})
	_leave(&"_rest")


func _check_bodies_apart() -> void:
	_enter(&"_check_bodies_apart")
	var reported := {}
	for i in _rests.size():
		for j in range(i + 1, _rests.size()):
			var a := _rests[i]
			var b := _rests[j]
			if a.actor == b.actor:
				continue
			var from := maxi(a.from, b.from)
			if from >= mini(a.to, b.to):
				continue
			var apart := Vector2(a.at.x - b.at.x, a.at.z - b.at.z).length()
			var key := "%s|%s" % [a.actor, b.actor]
			if apart < BODIES_APART and not reported.has(key):
				reported[key] = true
				_add("-", "%s and %s stand %.1f m apart at rest from frame %d (marks '%s' and '%s'), under %.1f m: two bodies" % [
						b.actor, a.actor, apart, from, b.mark, a.mark, BODIES_APART])
	_leave(&"_check_bodies_apart")


# --- the place ---

## The marks and walks of `scene` checked in the region's own physics `space` (the region instanced in a tree, a physics
## frame run): every mark that has a place in the region, REGION or ACTOR_START as the rehearsal marks resolve it, has
## walkable floor within 0.1 m under it, room for a body (an actor's capsule there touches no wall, prop or edge) and
## walls on all four sides (a mark with an open side is outside the region); and the straight line of every walk
## the checker measured is clear for a body. Each failure is a line naming the mark or walk, where, and what is in the
## way. The tool loads the region; the other rules do not need it.
func check_place(scene: SceneShots, space: PhysicsDirectSpaceState3D) -> PackedStringArray:
	_enter(&"check_place")
	var rule_lines := check(scene)   # it leaves the walks it measured; if it stopped, its lines say so and are the answer
	if not finished:
		return _leave(&"check_place", rule_lines)
	_problems = PackedStringArray()
	_broken = ""
	_place_rules(scene, space)
	var open := _first_open_above(&"check_place")
	if _broken == "" and open != "":
		_broken = open
	if _broken != "":
		finished = false
		stopped = "place"
		_add("-", "the place check stopped before it finished: in %s (a script error; see the engine's lines above)" % _described(_broken))
	return _leave(&"check_place", _problems)


# The marks and the walks, in the space.
func _place_rules(scene: SceneShots, space: PhysicsDirectSpaceState3D) -> void:
	_enter(&"_place_rules")
	var failed := {}
	for mark in scene.marks:
		var at: Variant = scene.region_position(mark)
		if at != null and not _mark_in_place(space, mark, at):
			failed[mark.name] = true
	for walk in _walks:
		if failed.has(walk.from_mark) or failed.has(walk.to_mark):
			continue
		var length: float = Vector2(walk.from.x - walk.to.x, walk.from.z - walk.to.z).length()
		var steps := maxi(1, ceili(length / WALK_SAMPLE))
		for step in steps + 1:
			var at: Vector3 = walk.from.lerp(walk.to, float(step) / float(steps))
			var hits := _body_hits(space, at)
			if not hits.is_empty():
				_add(String(walk.shot), "walk of %s from '%s' to '%s' is blocked by %s at %s, %.1f m along its %.1f m" % [
						walk.actor, walk.from_mark, walk.to_mark, ", ".join(hits), _where(at), length * float(step) / float(steps), length])
				break
	_leave(&"_place_rules")


# The first function entered after `function` that was never left: where a script error stopped, or "".
func _first_open_above(function: StringName) -> String:
	_enter(&"_first_open_above")
	var at := _trace.rfind(String(function))
	var found := _trace[at + 1] if at >= 0 and at < _trace.size() - 2 else ""   # the last entry is this function's own
	return _leave(&"_first_open_above", found)


# False, with a line, if a body cannot stand at `mark` (at `at` in the region).
func _mark_in_place(space: PhysicsDirectSpaceState3D, mark: SceneMark, at: Vector3) -> bool:
	_enter(&"_mark_in_place")
	var here := "mark '%s' at %s" % [mark.name, _where(at)]
	var floor_hit := _ray(space, at + Vector3(0, 0.5, 0), at + Vector3(0, -0.6, 0))
	if floor_hit.is_empty() or absf(floor_hit.position.y - at.y) > FLOOR_TOLERANCE:
		var found := "there is none under it" if floor_hit.is_empty() else "the floor there is %.2f m %s it, at %s" % [
				absf(floor_hit.position.y - at.y), "below" if floor_hit.position.y < at.y else "above", _what(floor_hit.collider)]
		_add("-", "%s: no walkable floor within %.1f m under it (%s)" % [here, FLOOR_TOLERANCE, found])
		return _leave(&"_mark_in_place", false)
	var hits := _body_hits(space, at)
	if not hits.is_empty():
		_add("-", "%s: a body does not fit there, %s is in the way" % [here, ", ".join(hits)])
		return _leave(&"_mark_in_place", false)
	var open := PackedStringArray()
	for direction: String in OPEN_DIRECTIONS:
		var from := at + Vector3(0, OPEN_HEIGHT, 0)
		if _ray(space, from, from + OPEN_DIRECTIONS[direction] * OPEN_DISTANCE).is_empty():
			open.append(direction)
	if not open.is_empty():
		_add("-", "%s: nothing stops a body to the %s, so it is outside the region's walls (or the region has none there)" % [here, " and ".join(open)])
		return _leave(&"_mark_in_place", false)
	return _leave(&"_mark_in_place", true)


# The names of what the world has where an actor's capsule would stand at `at` (empty: room for a body).
func _body_hits(space: PhysicsDirectSpaceState3D, at: Vector3) -> PackedStringArray:
	_enter(&"_body_hits")
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), at + Vector3(0, BODY_LIFT + BODY_HEIGHT / 2.0, 0))
	query.collision_mask = Layers.WORLD
	var names := PackedStringArray()
	for hit in space.intersect_shape(query, 8):
		var name := _what(hit.collider)
		if not names.has(name):
			names.append(name)
	return _leave(&"_body_hits", names)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_enter(&"_ray")
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return _leave(&"_ray", space.intersect_ray(query))


# What a collider is called to a writer: a body named Body is its parent's.
func _what(collider: Object) -> String:
	_enter(&"_what")
	var node := collider as Node
	if node == null:
		return _leave(&"_what", "something")
	if (node.name == &"Body" or node.name == &"StaticBody3D") and node.get_parent() != null:
		return _leave(&"_what", String(node.get_parent().name))
	return _leave(&"_what", String(node.name))


func _where(at: Vector3) -> String:
	_enter(&"_where")
	return _leave(&"_where", "(%.2f, %.2f, %.2f)" % [at.x, at.y, at.z])


# --- helpers ---

func _name(shot: Shot, index: int) -> String:
	_enter(&"_name")
	return _leave(&"_name", String(shot.id) if shot.id != &"" else "shot %d" % (index + 1))


func _add(shot: String, problem: String) -> void:
	_enter(&"_add")
	_problems.append("%s/%s: %s" % [_scene.id, shot, problem])
	_leave(&"_add")


# The def an actor of the cast is made of: a spawn's own, the player's (abarax), else the def given to a named one.
func _def_of(entry: CastEntry) -> ActorDef:
	_enter(&"_def_of")
	if entry.source == CastEntry.Source.LIVE_PLAYER:
		return _leave(&"_def_of", Registry.fetch(&"actors", &"abarax") as ActorDef if Registry.ids(&"actors").has("abarax") else null)
	return _leave(&"_def_of", entry.def)


func _clip_names(def: ActorDef) -> PackedStringArray:
	_enter(&"_clip_names")
	var key := String(def.id)
	if not _clips.has(key):
		var names := PackedStringArray()
		if def.rig_scene != null:
			var rig := def.rig_scene.instantiate()
			var tree := rig.get_node_or_null("AnimationTree") as AnimationTree
			if tree != null:
				names = tree.get_animation_list()
			rig.free()
		_clips[key] = names
	return _leave(&"_clip_names", _clips[key])
