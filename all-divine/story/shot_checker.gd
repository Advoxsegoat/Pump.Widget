class_name ShotChecker
extends RefCounted
## Checks that a scene's shot list names only things that exist and keeps the rules of its kind. A problem is a line of
## text, "<scene>/<shot or ->: <problem>" ("fixture_yard_entrance/S2: gap of 10 frames between S1 and S2"); no
## problems is the empty array. Nothing here raises an error: a bad file is reported, not thrown.
##
## The rules (check):
##   the folder holds a script.md with words in it, a notes.md whose last `Status:` line says what the scene's `status`
##       does, and the shot list's `id` is the folder's name (only when a folder is given)
##   every cast name is unique; a SPAWN has a def the Registry knows and a mark of the scene to stand on; a speaker is in
##       the Registry kind `speakers`; every mark has its own name (never an actor's), and an ACTOR_START mark is in the
##       space of an actor of the cast
##   the shots start at 0 and lie back to back (a gap or an overlap names its frames); each is 12 frames or more, its
##       blend_in no longer than itself, its key_frame inside it
##   a beat, a line and a cue start inside their shot; every actor, aim, focus, move_to, face, look and at_ref names an
##       actor of the cast or a mark (`name@start` is the same thing), never a `rehearsal.` mark
##   a clip is a clip of the actor's rig (a LIVE_PLAYER's def is abarax); one that is not is an error, or, when the beat
##       says `placeholder`, a line that begins PLACEHOLDER (listed, not an error in a draft)
##   a line has text of at most 160 characters in a speaker's portrait, holds at least its typing time plus 20 frames
##       and fits in its shot, and lines of one shot do not overlap
##   a sound cue is in the Registry kind `sounds`
##   the camera fields fit the move (STATIC none, PAN aim_to, DOLLY a zoom_to unlike its zoom, CRANE a pitch_to_deg
##       unlike its pitch, ORBIT a yaw_to_deg unlike its yaw, HANDHELD a shake) and the framing (OVER_SHOULDER names the
##       foreground actor, no other does), zoom is 0 to 4 and pitch -15 to -65
##   a MINI is 180 to 360 frames in all, a MOMENT one shot of 90 frames at most with no letterbox and no beats, a
##       CUTSCENE 120 frames or more
##   a `move_to` from a place that is known to a mark in the same space fits before the actor's next beat or the end of
##       the shots, by travel_seconds
##   an approved scene has no placeholder

## What a problem starts with when it is a listed placeholder and not an error.
const PLACEHOLDER := "placeholder: "
const MIN_SHOT_FRAMES := 12
const MAX_LINE_CHARACTERS := 160
## The dialogue box types this many characters a second (2 frames each) ...
const FRAMES_PER_CHARACTER := 2
## ... a line must stay up for its typing time plus this many frames, and by default for this many.
const MIN_HOLD_EXTRA := 20
const DEFAULT_HOLD_EXTRA := 45
const MIN_PITCH := -65.0
const MAX_PITCH := -15.0
const DEFAULT_PITCH := -40.0
const WALK_PUSH := 0.45
const JOG_PUSH := 1.0
const FRAMES_PER_SECOND := 60.0
const MINI_FRAMES := Vector2i(180, 360)
const MOMENT_MAX_FRAMES := 90
const CUTSCENE_MIN_FRAMES := 120
const REHEARSAL := "rehearsal."
const AT_START := "@start"
## The zoom each framing has when a shot's `zoom` is 0.
const FRAMING_ZOOM: Array[int] = [1, 2, 3, 2, 4]
const STATUS_WORDS: PackedStringArray = ["draft", "in review", "approved"]

# actor def id -> {clip: true}; the rigs are built once per run.
var _clips := {}
var _problems := PackedStringArray()
var _scene: SceneShots
var _placeholders := 0


## The seconds a body takes to cover `metres` from rest at `pace`, with `def`'s accel and decel: the formula of
## Main._leg (the frames a push takes to cover a distance, coasting to a stop after it) solved for the time.
static func travel_seconds(def: ActorDef, pace: ActorBeat.Pace, metres: float) -> float:
	var push := WALK_PUSH if pace == ActorBeat.Pace.WALK else JOG_PUSH
	var tuning := def.locomotion
	var v := Locomotion.new(tuning).target_speed(push, false)
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


## Every scene folder under `root`, checked as `check` does with its folder. A folder with no readable shots.tres is a
## problem of its own.
func check_all(root := "res://scenes/story") -> PackedStringArray:
	var out := PackedStringArray()
	for folder in scene_folders(root):
		out.append_array(check_folder(root.path_join(folder)))
	return out


## The names of the scene folders under `root`, sorted.
func scene_folders(root := "res://scenes/story") -> PackedStringArray:
	var found := PackedStringArray()
	for entry in ResourceLoader.list_directory(root):
		if entry.ends_with("/"):
			found.append(entry.trim_suffix("/"))
	found.sort()
	return found


## One scene folder: its shots.tres loaded and checked with the folder.
func check_folder(folder: String) -> PackedStringArray:
	var name := folder.trim_suffix("/").get_file()
	var path := folder.path_join("shots.tres")
	if not ResourceLoader.exists(path):
		return PackedStringArray(["%s/-: shots.tres is missing" % name])
	var scene := ResourceLoader.load(path) as SceneShots
	if scene == null:
		return PackedStringArray(["%s/-: shots.tres is not a SceneShots" % name])
	return check(scene, folder)


## The problems of `scene`; with a `folder`, also those of its script.md, notes.md and id.
func check(scene: SceneShots, folder := "") -> PackedStringArray:
	_scene = scene
	_problems = PackedStringArray()
	_placeholders = 0
	if folder != "":
		_check_folder(folder)
	_check_cast()
	_check_marks()
	_check_layout()
	for shot in scene.shots:
		_check_shot(shot)
	_check_kind()
	_check_walks()
	if scene.status == SceneShots.Status.APPROVED and _placeholders > 0:
		_add("-", "an approved scene has no placeholder, this one has %d" % _placeholders)
	return _problems


# --- the folder ---

func _check_folder(folder: String) -> void:
	var name := folder.trim_suffix("/").get_file()
	if String(_scene.id) != name:
		_add("-", "id '%s' is not the folder name '%s'" % [_scene.id, name])
	var script := folder.path_join("script.md")
	if not FileAccess.file_exists(script):
		_add("-", "script.md is missing")
	elif FileAccess.get_file_as_string(script).strip_edges() == "":
		_add("-", "script.md is empty")
	var notes := folder.path_join("notes.md")
	if not FileAccess.file_exists(notes):
		_add("-", "notes.md is missing")
		return
	var last := ""
	for text in FileAccess.get_file_as_string(notes).split("\n"):
		if text.strip_edges().to_lower().begins_with("status:"):
			last = text.strip_edges()
	if last == "":
		_add("-", "notes.md has no 'Status:' line")
		return
	var said := last.substr(last.find(":") + 1).strip_edges().to_lower()
	var want := STATUS_WORDS[_scene.status]
	if said != want:
		_add("-", "notes.md ends with '%s' but the scene is %s" % [last, want])


# --- the cast and the marks ---

func _check_cast() -> void:
	var seen := {}
	for entry in _scene.cast:
		var who := String(entry.actor)
		if who == "":
			_add("-", "a cast entry has no actor name")
			continue
		if seen.has(who):
			_add("-", "'%s' is in the cast twice" % who)
		seen[who] = true
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
		if entry.speaker != &"" and not Registry.ids(&"speakers").has(String(entry.speaker)):
			_add("-", "%s: speaker '%s' is not in the Registry" % [who, entry.speaker])


func _check_marks() -> void:
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
		if mark.space == SceneMark.Space.ACTOR_START and _scene.cast_entry(mark.actor) == null:
			_add("-", "mark '%s' is placed in the space of '%s', who is not in the cast" % [name, mark.actor])
		if name.begins_with(REHEARSAL) and _scene.cast_entry(StringName(name.trim_prefix(REHEARSAL))) == null:
			_add("-", "rehearsal mark '%s' is for '%s', who is not in the cast" % [name, name.trim_prefix(REHEARSAL)])


# --- the shot list ---

func _check_layout() -> void:
	if _scene.shots.is_empty():
		_add("-", "the scene has no shots")
		return
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
		if gap > 0:
			_add(_name(shot, i), "gap of %d frames between %s and %s (%s ends at frame %d, %s starts at %d)" % [
					gap, _name(before, i - 1), _name(shot, i), _name(before, i - 1), before.start + before.length, _name(shot, i), shot.start])
		elif gap < 0:
			_add(_name(shot, i), "overlap of %d frames between %s and %s (%s ends at frame %d, %s starts at %d)" % [
					-gap, _name(before, i - 1), _name(shot, i), _name(before, i - 1), before.start + before.length, _name(shot, i), shot.start])


func _check_shot(shot: Shot) -> void:
	var where := String(shot.id)
	if shot.length < MIN_SHOT_FRAMES:
		_add(where, "is %d frames, under the %d a shot needs" % [shot.length, MIN_SHOT_FRAMES])
	if shot.blend_in > shot.length:
		_add(where, "blend_in %d is longer than the shot (%d frames)" % [shot.blend_in, shot.length])
	if shot.key_frame < -1 or shot.key_frame >= shot.length:
		_add(where, "key_frame %d is outside the shot (-1 or 0 to %d)" % [shot.key_frame, shot.length - 1])
	_check_camera(shot)
	for target in [["aim", shot.aim], ["aim_to", shot.aim_to], ["over_shoulder", shot.over_shoulder],
			["focus", shot.focus], ["focus_to", shot.focus_to]]:
		_check_target(where, target[0], target[1])
	for beat in shot.beats:
		_check_beat(shot, beat)
	for line in shot.lines:
		_check_line(shot, line)
	_check_line_overlaps(shot)
	for cue in shot.cues:
		_check_cue(shot, cue)


func _check_camera(shot: Shot) -> void:
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


func _check_beat(shot: Shot, beat: ActorBeat) -> void:
	var where := String(shot.id)
	var what := "beat at frame %d" % beat.at
	if beat.at < 0 or beat.at >= shot.length:
		_add(where, "%s is outside the shot (frames 0 to %d)" % [what, shot.length - 1])
	var entry := _scene.cast_entry(beat.actor)
	if entry == null:
		_add(where, "%s: '%s' is not in the cast" % [what, beat.actor])
	for target in [["move_to", beat.move_to], ["face", beat.face], ["look", beat.look]]:
		_check_target(where, target[0], target[1], what)
	if beat.clip == &"" or entry == null:
		return
	var def := _def_of(entry)
	if def == null:
		return  # a live actor of no known def: its clips cannot be looked up
	if not _clip_names(def).has(beat.clip):
		if beat.placeholder:
			_placeholders += 1
			_add(where, "%s%s has no clip '%s'" % [PLACEHOLDER, beat.actor, beat.clip])
		else:
			_add(where, "%s has no clip '%s' in its rig (%s); fix the name, or set the beat's placeholder" % [beat.actor, beat.clip, def.id])


func _check_line(shot: Shot, line: DialogueLine) -> void:
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
		return
	if line.text.length() > MAX_LINE_CHARACTERS:
		_add(where, "the line at frame %d is %d characters, at most %d" % [line.at, line.text.length(), MAX_LINE_CHARACTERS])
	if line.at < 0 or line.at >= shot.length:
		_add(where, "line at frame %d is outside the shot (frames 0 to %d)" % [line.at, shot.length - 1])
		return
	var typing := typing_frames(line.text)
	if line.hold > 0 and line.hold < typing + MIN_HOLD_EXTRA:
		_add(where, "the line at frame %d: a hold of %d frames is under the %d it needs (typing %d plus %d)" % [
				line.at, line.hold, typing + MIN_HOLD_EXTRA, typing, MIN_HOLD_EXTRA])
	var end := line.at + hold_of(line)
	if end > shot.length:
		_add(where, "the line at frame %d cannot finish: it needs frames %d to %d and the shot ends at %d" % [
				line.at, line.at, end, shot.length])


func _check_line_overlaps(shot: Shot) -> void:
	var lines: Array[DialogueLine] = shot.lines.duplicate()
	lines.sort_custom(func(a: DialogueLine, b: DialogueLine) -> bool: return a.at < b.at)
	for i in range(1, lines.size()):
		var before := lines[i - 1]
		if lines[i].at < before.at + hold_of(before):
			_add(String(shot.id), "the line at frame %d overlaps the line at frame %d, which is up until frame %d" % [
					lines[i].at, before.at, before.at + hold_of(before)])


func _check_cue(shot: Shot, cue: CueEvent) -> void:
	var where := String(shot.id)
	if cue.at < 0 or cue.at >= shot.length:
		_add(where, "cue at frame %d is outside the shot (frames 0 to %d)" % [cue.at, shot.length - 1])
	if cue.id == &"":
		_add(where, "the cue at frame %d has no id" % cue.at)
	elif cue.kind == CueEvent.Kind.SOUND and not Registry.ids(&"sounds").has(String(cue.id)):
		_add(where, "sound '%s' is not in the Registry" % cue.id)
	_check_target(where, "at_ref", cue.at_ref, "cue at frame %d" % cue.at)


# A target field: empty is fine; otherwise an actor of the cast or a mark, `@start` allowed, never a rehearsal mark.
func _check_target(where: String, field: String, target: StringName, what := "") -> void:
	if target == &"":
		return
	var prefix := what + ": " if what != "" else ""
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


# --- the kinds ---

func _check_kind() -> void:
	var total := _scene.total_frames()
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


# --- walking ---

# Each actor's beats in time order: a `move_to` a mark from a place that is known, in the same space, must be walkable
# before the actor's next beat (or the end of the shots). Where a body stands is known from its spawn mark and from the
# mark of its last `move_to`; anywhere else it is not known and nothing is claimed.
func _check_walks() -> void:
	var end := 0
	for shot in _scene.shots:
		end = maxi(end, shot.start + shot.length)
	for entry in _scene.cast:
		var def := _def_of(entry)
		if def == null or def.locomotion == null:
			continue
		var beats := []  # {frame, beat, shot}
		for shot in _scene.shots:
			for beat in shot.beats:
				if beat.actor == entry.actor:
					beats.append({frame = shot.start + beat.at, beat = beat, shot = shot})
		beats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.frame < b.frame)
		var known: SceneMark = null
		if entry.source == CastEntry.Source.SPAWN:
			known = _scene.mark(entry.spawn_mark)
		for i in beats.size():
			var beat: ActorBeat = beats[i].beat
			if beat.move_to == &"":
				continue
			var to := _scene.mark(StringName(String(beat.move_to).trim_suffix(AT_START)))
			if to != null and known != null and _same_space(known, to):
				var metres := known.position.distance_to(to.position)
				var next := end
				for j in range(i + 1, beats.size()):
					if beats[j].frame > beats[i].frame:
						next = beats[j].frame
						break
				var needed := travel_seconds(def, beat.pace, metres)
				var left := float(next - beats[i].frame) / FRAMES_PER_SECOND
				if needed > left + 0.0001:
					_add(String(beats[i].shot.id), "%s needs %.2f s to walk %.1f m at %s to '%s' but has %.2f s (%d frames) before %s" % [
							entry.actor, needed, metres, ActorBeat.Pace.keys()[beat.pace], beat.move_to, left, next - beats[i].frame,
							"its next beat" if next != end else "the end of the shots"])
			known = to


func _same_space(a: SceneMark, b: SceneMark) -> bool:
	if a.space != b.space:
		return false
	return a.space == SceneMark.Space.REGION or a.actor == b.actor


# --- helpers ---

func _name(shot: Shot, index: int) -> String:
	return String(shot.id) if shot.id != &"" else "shot %d" % (index + 1)


func _add(shot: String, problem: String) -> void:
	_problems.append("%s/%s: %s" % [_scene.id, shot, problem])


# The def an actor of the cast is made of: a spawn's own, the player's (abarax), else the def given to a named one.
func _def_of(entry: CastEntry) -> ActorDef:
	if entry.source == CastEntry.Source.LIVE_PLAYER:
		return Registry.fetch(&"actors", &"abarax") as ActorDef if Registry.ids(&"actors").has("abarax") else null
	return entry.def


func _clip_names(def: ActorDef) -> PackedStringArray:
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
	return _clips[key]
