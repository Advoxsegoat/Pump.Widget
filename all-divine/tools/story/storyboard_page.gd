class_name StoryboardPage
extends SceneTree
## The storyboard sheet: a scene's shots on paper, for a person who does not program.
##
##   tools/godot.sh --render -s res://tools/story/storyboard_page.gd -- --scene=<id> --out=<dir>
##
## Reads the frames that `StoryReel --capture` saved (<out>/frames/shot-01.png ...) and lays them out in pages 1280 px
## wide: a header (the scene's title, what kind it is, its revision and status, its length, its place, its cast, and a
## band that lists every stand-in and placeholder the shot checker found), then one row to a shot: the captured frame at
## 1:1 (640 by 360, no scaling) on the left and, in a column to its right, what the shot is in words (ShotText). Three rows
## to a page; a row whose text does not fit one row takes two (or three), and the layout says so (`span`); one whose text is longer
## than a page fills a page and goes on, headed "S7, continued", on the pages after it: no text of a shot is ever left off. The pages are
## <out>/storyboard-1.png, -2.png, ... (a relative --out is taken from the project folder, as the contact-sheet tool's is).
## Exits 0 when the pages are written, 1 if a frame is missing or the sheet could not be made, 2 for a wrong command line.
##
## Everything that decides what the sheet says or where a thing goes is a pure function (ShotText, layout, row_spans)
## that the tests call without a display; only `_initialize` draws.
##
## A script run with -s is compiled before the autoloads are known as names (see tools/story_check.gd): so this file never
## names Registry or the shot checker; ShotText reaches the Registry through the tree and loads the checker when it is
## asked for.

const PAGE_WIDTH := 1280
const FRAME := Vector2i(640, 360)
const FRAME_X := 16
const TEXT_X := 672
## The text column ends this far from the page's right edge.
const MARGIN := 16
const ROW_HEIGHT := 380
## The room above a frame inside its row; the row is the frame's 360 plus this twice.
const ROW_PAD := 10
const ROWS_PER_PAGE := 3
## The first page's header (the title, the facts, the band) takes what it needs, at least this; the others a slim title.
const HEAD := 140
const SLIM_HEAD := 48
const FONT_SIZE := 14
const LINE_HEIGHT := 19
const TITLE_SIZE := 18
const TITLE_HEIGHT := 25
## A block of text (ACTION, a beat, a line ...) is followed by this gap.
const GAP := 5
## The space between a title's words and its grey shorthand.
const TAIL_GAP := 14
## The heading of a continuation ("S7, continued") takes this much of its first row.
const CONTINUED_HEAD := TITLE_HEIGHT + GAP
## The label ("ACTION:", "DOES:" ...) takes this much of the column; the words are set to its right.
const LABEL_WIDTH := 72

const PAPER := Color("f3eee3")
const INK := Color("1e1c18")
const GREY := Color("6a6558")
const LABEL := Color("7a4f12")
const RED := Color("b3261e")
const BAND := Color("fbe3b0")
const GOOD := Color("dcebd2")
const RULE := Color("c9c1ad")


## The sheet's words for the shots, and which frame of a shot is photographed.
class ShotText extends RefCounted:
	const FRAMING := ["WIDE", "MEDIUM", "CLOSE", "OVER THE SHOULDER", "INSERT"]
	const FRAMING_NOTE := [
		"everyone and the ground round them",
		"people from about the waist up",
		"one person or detail filling the picture",
		"the camera sits behind %s's shoulder",
		"a small detail, very close",
	]
	const ZOOM_NAME := ["", "wide", "medium", "close", "insert"]
	const BURN_FRAMING := ["WIDE", "MEDIUM", "CLOSE", "OVER SHOULDER", "INSERT"]
	## A cue's caption stays up this many frames.
	const CUE_SHOWN := 60
	const MOVE_SHORT := ["STATIC", "PAN", "DOLLY", "CRANE", "ORBIT", "HANDHELD"]
	const FPS := 60.0
	const CHECKER := "res://story/shot_checker.gd"
	static var _checker: RefCounted

	## The text of shot `index` of `scene`, one string a row of the sheet. The first two are the shot's title (its name,
	## framing and camera move, in plain words with the shorthand after it in grey) and its timing (seconds, then the frames, on that
	## row only), then the instant its picture was taken;
	## the rest begin with a label: ACTION (the storyboard's words), CAMERA, DOES (one for each beat), SAYS, SOUND, MUSIC,
	## FOCUS. A stand-in or a placeholder is marked on its own row, in square brackets after the thing it stands in for.
	## Deterministic: the same scene gives the same text.
	static func describe(scene: SceneShots, index: int) -> PackedStringArray:
		var out := PackedStringArray()
		if scene == null or index < 0 or index >= scene.shots.size():
			return out
		var shot := scene.shots[index]
		out.append("%s   %s, the camera %s   (%s)" % [shot.id, FRAMING[shot.framing], _move_phrase(scene, shot), _shorthand(scene, shot)])
		out.append("%s long   ·   %s to %s   (frames %d to %d)" % [_secs(shot.length), _secs(shot.start), _secs(shot.start + shot.length), shot.start, shot.start + shot.length])
		var choice := key_choice(shot, scene)
		out.append("picture: %s into the shot (%s)" % [_secs(choice.frame), choice.reason])
		out.append("ACTION: " + (shot.action if shot.action != "" else "(no action written yet)"))
		out.append("CAMERA: " + _camera_sentence(scene, shot, index))
		for beat in shot.beats:
			out.append("DOES: " + _beat_sentence(scene, beat))
		for line in shot.lines:
			out.append("SAYS: " + _line_sentence(scene, line))
		for cue in shot.cues:
			out.append(_cue_sentence(scene, cue))
		if shot.focus != &"":
			var focus := "FOCUS: sharp on " + who(scene, shot.focus)
			if shot.focus_to != &"":
				focus += ", then pulling to " + who(scene, shot.focus_to)
			out.append(focus)
		return out

	## The frame of `shot` (counted from its first) the sheet shows: the data's own `key_frame` if it has one; else, for
	## a shot with a line, the frame its last line is fully typed (so that the sheet shows the words); else, for a shot
	## whose walk arrives inside it (given the `scene` to know the places), the frame the body is at rest at its mark; else
	## the middle. Always inside the shot.
	static func key_frame(shot: Shot, scene: SceneShots = null) -> int:
		return key_choice(shot, scene).frame

	## The frame key_frame picks and why: {frame, reason}, the reason in the sheet's words ("the line just typed", "the walk's end",
	## "the middle", or "chosen in the shot's data").
	static func key_choice(shot: Shot, scene: SceneShots = null) -> Dictionary:
		var last := maxi(shot.length - 1, 0)
		if shot.key_frame >= 0:
			return {frame = clampi(shot.key_frame, 0, last), reason = "chosen in the shot's data"}
		if not shot.lines.is_empty():
			var line := shot.lines[shot.lines.size() - 1]
			return {frame = clampi(line.at + int(_shared().call("typing_frames", line.text)), 0, last), reason = "the line just typed"}
		if scene != null:
			var arrival := _arrival(scene, shot)
			if arrival >= 0 and arrival <= last:
				return {frame = arrival, reason = "the walk's end"}
		return {frame = clampi(shot.length / 2, 0, last), reason = "the middle"}

	## The key frame of each shot, counted from the first shot's first frame (the scene's own clock, without the glide in).
	static func key_frames(scene: SceneShots) -> PackedInt32Array:
		var frames := PackedInt32Array()
		for shot in scene.shots:
			frames.append(shot.start + key_frame(shot, scene))
		return frames

	## The words burnt into the animatic at scene frame `frame` (counted from the first shot's first frame; negative in the glide
	## in): row one names the shot, its framing and camera move, the frame and the time; the rows after it say what the
	## video cannot (a sound or music cue, for a second after it; a clip that is not made yet; a line spoken over a stand-in
	## portrait). The glides are only named.
	static func burn_in(scene: SceneShots, frame: int) -> String:
		if frame < 0:
			return "GLIDE IN"
		var index := scene.shot_at(frame)
		if index < 0:
			return "GLIDE OUT"
		var shot := scene.shots[index]
		var rows := PackedStringArray()
		rows.append("%s/%d %s %s f%03d %s" % [shot.id, scene.shots.size(), BURN_FRAMING[shot.framing], _shorthand(scene, shot), frame, clock(frame)])
		for cue in shot.cues:
			var at := shot.start + cue.at
			if frame >= at and frame < at + CUE_SHOWN:
				rows.append("%s %s" % ["MUSIC" if cue.kind == CueEvent.Kind.MUSIC else "SFX", cue.id])
		for beat in shot.beats:
			if beat.placeholder and beat.clip != &"" and frame >= shot.start + beat.at:
				rows.append("PLACEHOLDER %s" % beat.clip)
		for line in shot.lines:
			var from := shot.start + line.at
			var speaker := _registry_fetch(&"speakers", line.speaker) as Speaker
			if speaker != null and speaker.placeholder_exprs.has(line.expr) and frame >= from and frame < from + int(_shared().call("hold_of", line)):
				rows.append("STAND-IN portrait: %s" % line.speaker)
		return "\n".join(rows)

	## `frame` frames (60 a second) as minutes, seconds and hundredths: 0:01.50.
	static func clock(frame: int) -> String:
		var hundredths := maxi(frame, 0) * 100 / 60
		return "%d:%02d.%02d" % [hundredths / 6000, hundredths / 100 % 60, hundredths % 100]

	## The name of a cast member, a mark or `name@start` as a person says it.
	static func who(scene: SceneShots, id: StringName) -> String:
		var text := String(id)
		if text == "":
			return ""
		if text.ends_with("@start"):
			return "where %s stood when the scene began" % who(scene, StringName(text.trim_suffix("@start")))
		if scene.cast_entry(id) != null:
			return text.substr(0, 1).to_upper() + text.substr(1).replace("_", " ")
		return "the %s mark" % text.replace("_", " ")

	## The same name for the shorthand beside a title: no "the ... mark".
	static func short_name(scene: SceneShots, id: StringName) -> String:
		var text := String(id).replace("_", " ")
		return text.substr(0, 1).to_upper() + text.substr(1) if scene.cast_entry(id) != null else text

	static func _secs(frames: int) -> String:
		return "%.2f s" % (float(frames) / FPS)

	# "at the start" or "at +0.23 s": seconds only (the frames are on the row's own time line).
	static func _when(frames: int) -> String:
		return "at the start" if frames == 0 else "at +%s" % _secs(frames)

	static func _zoom_of(shot: Shot) -> int:
		return shot.zoom if shot.zoom > 0 else CinePose.FRAMING_ZOOM[shot.framing]

	static func _pitch_of(shot: Shot) -> float:
		return shot.pitch_deg if shot.pitch_deg != 0.0 else CinePose.FRAMING_PITCH[shot.framing]

	# What the camera does, as the end of "the camera ...", in the words a script would use. The shorthand (_shorthand) goes
	# after it in the title. Every move has its sentence; one that has none says so out loud (a test fails on that).
	static func _move_phrase(scene: SceneShots, shot: Shot) -> String:
		match shot.move:
			Shot.CamMove.STATIC:
				return "holds still"
			Shot.CamMove.PAN:
				return "turns from %s to %s" % [who(scene, shot.aim), who(scene, shot.aim_to)]
			Shot.CamMove.DOLLY:
				var from := _zoom_of(shot)
				var text := "pushes in" if shot.zoom_to > from else "pulls out"
				if shot.zoom_to > 0:
					text += ", from %s to %s" % [ZOOM_NAME[clampi(from, 1, 4)], ZOOM_NAME[clampi(shot.zoom_to, 1, 4)]]
				return text
			Shot.CamMove.CRANE:
				return _crane_phrase(_pitch_of(shot), shot.pitch_to_deg)
			Shot.CamMove.ORBIT:
				return _orbit_phrase(shot.yaw_deg, shot.yaw_to_deg)
			Shot.CamMove.HANDHELD:
				return "is hand-held, with %s shake" % _shake_word(shot.shake)
		return "makes a move the sheet has no words for (%d)" % shot.move

	# A crane is a change of pitch: a pitch below the horizon is negative, so a more negative one is a higher camera looking
	# down more steeply.
	static func _crane_phrase(from: float, to: float) -> String:
		var verb := "rises" if to < from else ("sinks" if to > from else "holds its height")
		if from <= 0.0 and to <= 0.0:
			return "%s, tilting down from %d to %d degrees" % [verb, roundi(-from), roundi(-to)]
		if from >= 0.0 and to >= 0.0:
			return "%s, tilting up from %d to %d degrees" % [verb, roundi(from), roundi(to)]
		return "%s, from looking %s to looking %s" % [verb, _tilt_word(from), _tilt_word(to)]

	static func _tilt_word(pitch: float) -> String:
		if absf(pitch) < 0.5:
			return "level"
		return "%s %d degrees" % ["down" if pitch < 0.0 else "up", roundi(absf(pitch))]

	# An orbit is a change of yaw; a positive one carries the camera round to its right (it looks along (-sin yaw, -cos yaw)).
	static func _orbit_phrase(from: float, to: float) -> String:
		var turn := to - from
		if absf(turn) < 0.5:
			return "holds still"
		var amount := absf(turn)
		var words := "%d degrees" % roundi(amount)
		if is_equal_approx(amount, 90.0):
			words = "a quarter turn"
		elif is_equal_approx(amount, 180.0):
			words = "half way round"
		elif is_equal_approx(amount, 270.0):
			words = "three quarters of the way round"
		elif is_equal_approx(amount, 360.0):
			words = "a full circle"
		return "circles %s to the %s" % [words, "right" if turn > 0.0 else "left"]

	static func _shake_word(shake: float) -> String:
		if shake < 0.25:
			return "a slight"
		if shake < 0.5:
			return "a gentle"
		if shake < 0.75:
			return "a clear"
		return "a strong"

	static func _shorthand(scene: SceneShots, shot: Shot) -> String:
		var name: String = MOVE_SHORT[shot.move]
		match shot.move:
			Shot.CamMove.PAN:
				return "%s %s>%s" % [name, short_name(scene, shot.aim), short_name(scene, shot.aim_to)]
			Shot.CamMove.DOLLY:
				return "%s %d>%d" % [name, _zoom_of(shot), shot.zoom_to]
			Shot.CamMove.CRANE:
				return "%s %d>%d" % [name, roundi(_pitch_of(shot)), roundi(shot.pitch_to_deg)]
			Shot.CamMove.ORBIT:
				return "%s %d>%d" % [name, roundi(shot.yaw_deg), roundi(shot.yaw_to_deg)]
			Shot.CamMove.HANDHELD:
				return "%s %s" % [name, str(snappedf(shot.shake, 0.01))]
		return name

	static func _camera_sentence(scene: SceneShots, shot: Shot, index: int) -> String:
		var framing: String = "Over the shoulder" if shot.framing == Shot.Framing.OVER_SHOULDER else String(FRAMING[shot.framing]).capitalize()
		var note: String = FRAMING_NOTE[shot.framing]
		if shot.framing == Shot.Framing.OVER_SHOULDER:
			note = note % who(scene, shot.over_shoulder)
		var text := "%s (%s), looking at %s. The camera %s" % [framing, note, who(scene, shot.aim), _move_phrase(scene, shot)]
		text += "."
		if index > 0:
			if shot.blend_in > 0:
				text += " It glides in from the last shot over %s." % _secs(shot.blend_in)
			else:
				text += " It cuts in from the last shot."
		return text

	static func _beat_sentence(scene: SceneShots, beat: ActorBeat) -> String:
		var parts := PackedStringArray()
		if beat.clip != &"":
			parts.append("plays the clip %s" % beat.clip)
			if beat.loop:
				parts.append("repeating")
		if beat.move_to != &"":
			parts.append("%s to %s" % ["walks" if beat.pace == ActorBeat.Pace.WALK else "jogs", who(scene, beat.move_to)])
		if beat.face != &"":
			parts.append("turns to face %s" % who(scene, beat.face))
		if beat.look != &"":
			parts.append("looks at %s" % who(scene, beat.look))
		if parts.is_empty():
			parts.append("does nothing yet")
		var actor := who(scene, beat.actor)
		var text := "%s %s (%s)" % [actor, ", ".join(parts), _when(beat.at)]
		if beat.placeholder:
			text += "  [PLACEHOLDER: this clip is not made yet, so %s just stands]" % actor
		return text

	static func _line_sentence(scene: SceneShots, line: DialogueLine) -> String:
		var speaker := speaker_of(line.speaker)
		var hold := int(_shared().call("hold_of", line))
		var text := "%s: \"%s\" (%s, on screen %s)" % [speaker_name(line.speaker, speaker), line.text, _when(line.at), _secs(hold)]
		if speaker != null and speaker.placeholder_exprs.has(line.expr):
			text += "  [STAND-IN: %s]" % portrait_sentence(scene, line.speaker, line.expr, speaker)
		return text

	## The speaker as a row names them: the speaker's own name, the id only when the Registry has no such speaker.
	static func speaker_name(id: StringName, speaker: Speaker) -> String:
		return speaker.display_name if speaker != null else String(id)

	## The speaker `id`: the Registry's, or `lookup`'s (a Callable taking the id) when one is given.
	static func speaker_of(id: StringName, lookup := Callable()) -> Speaker:
		if lookup.is_valid():
			return lookup.call(id) as Speaker
		return _registry_fetch(&"speakers", id) as Speaker

	## The stand-in expressions of the speaker `id` that a line of the scene uses, each once.
	static func stand_in_looks(scene: SceneShots, id: StringName, lookup := Callable()) -> PackedStringArray:
		var speaker := speaker_of(id, lookup)
		var looks := PackedStringArray()
		if speaker == null:
			return looks
		for shot in scene.shots:
			for line in shot.lines:
				if line.speaker == id and speaker.placeholder_exprs.has(line.expr) and not looks.has(String(line.expr)):
					looks.append(String(line.expr))
		return looks

	## "the portrait of Fixture Knuckle is not drawn yet, so a plain card shows" (the expression is named only when the scene
	## uses more than one stand-in expression of this speaker).
	static func portrait_sentence(scene: SceneShots, id: StringName, expr: StringName, speaker: Speaker, lookup := Callable()) -> String:
		var of := "the portrait of %s" % speaker_name(id, speaker)
		if stand_in_looks(scene, id, lookup).size() > 1:
			of = "the '%s' portrait of %s" % [expr, speaker_name(id, speaker)]
		return "%s is not drawn yet, so %s shows" % [of, "a plain card" if speaker.portraits.is_empty() else "the neutral drawing"]

	## Whether a cast member is shown by the body of another character (a Knuckle's, say, for Noella): a spawned or named actor
	## whose def is not its own, as far as the names say: the def's id does not begin with the actor's name (the Knuckle's
	## `knuckle` is made from `knuckle_1`; `noella` from `knuckle_2` is a stand-in). The player is always his own.
	static func stand_in_model(entry: CastEntry) -> bool:
		return entry.source != CastEntry.Source.LIVE_PLAYER and entry.def != null and not String(entry.def.id).begins_with(String(entry.actor))

	static func _cue_sentence(scene: SceneShots, cue: CueEvent) -> String:
		if cue.kind == CueEvent.Kind.MUSIC:
			return "MUSIC: %s starts (%s)" % [cue.id, _when(cue.at)]
		if cue.at_ref != &"":
			return "SOUND: %s, heard at %s (%s)" % [cue.id, who(scene, cue.at_ref), _when(cue.at)]
		return "SOUND: %s (%s)" % [cue.id, _when(cue.at)]

	# The frame (of the shot) the last walk of the shot has its body at rest, or -1 if there is none that is known. A walk is
	# from where the actor was (a spawn mark, or where an earlier shot's walk left him) to a mark of the scene.
	static func _arrival(scene: SceneShots, shot: Shot) -> int:
		var latest := -1
		for beat in shot.beats:
			if beat.move_to == &"":
				continue
			var entry := scene.cast_entry(beat.actor)
			var to: Variant = scene.region_position(scene.mark(beat.move_to))
			var from: Variant = _place_before(scene, beat)
			if entry == null or entry.def == null or not to is Vector3 or not from is Vector3:
				continue
			var metres := Vector2((to as Vector3).x - (from as Vector3).x, (to as Vector3).z - (from as Vector3).z).length()
			var frames := StoryWalk.frames(entry.def.locomotion, beat.pace, metres)
			if frames >= 0:
				latest = maxi(latest, beat.at + frames)
		return latest

	# Where `beat`'s actor is as the beat begins, as far as the data says: the end of the walk before it, else the spawn mark.
	static func _place_before(scene: SceneShots, beat: ActorBeat) -> Variant:
		var place: Variant = null
		var entry := scene.cast_entry(beat.actor)
		if entry != null and entry.spawn_mark != &"":
			place = scene.region_position(scene.mark(entry.spawn_mark))
		for each in scene.shots:
			for other in each.beats:
				if other == beat:
					return place
				if other.actor == beat.actor and other.move_to != &"":
					var there: Variant = scene.region_position(scene.mark(other.move_to))
					if there != null:
						place = there
		return place

	static func _shared() -> RefCounted:
		if _checker == null:
			_checker = (load(CHECKER) as GDScript).new()
		return _checker

	# A Registry resource, fetched through the tree (this file never names the autoload).
	static func _registry_fetch(kind: StringName, id: StringName) -> Resource:
		var tree := Engine.get_main_loop() as SceneTree
		var registry := tree.root.get_node_or_null("Registry") if tree != null else null
		if registry == null:
			return null
		if (registry.call("ids", kind) as PackedStringArray).is_empty():
			registry.call("scan")
		return registry.call("fetch", kind, id) as Resource


## Where each shot's frame goes: for each of `shot_count` shots (in order) {page (from 1), slot (the first row of the page it
## fills), span (how many rows it fills), rect (the frame, 640 by 360, at x 16), row (the whole row, to the page's edge),
## page_size (the page's whole size: the header and the rows filled), more (the continuations, see below)}. `spans` is how many rows each
## shot needs (row_spans; 1 where not given); a shot that does not fit in what is left of a page starts the next one. The first page's
## header is `first_head` high; later pages carry a slim title. A shot whose text is longer than a page fills one (span 3) and
## `continued` (continuation_spans: for each shot the rows each of its continuations fills) goes on over the pages after it: `more` holds
## {page, slot, span, row, page_size} for each, a continuation having no frame.
static func layout(shot_count: int, spans: Array[int] = [], first_head := HEAD, continued: Array = []) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var page := 1
	var slot := 0
	var used := {}   # page -> rows of it that are filled
	for i in shot_count:
		var span := clampi(spans[i] if i < spans.size() else 1, 1, ROWS_PER_PAGE)
		if slot + span > ROWS_PER_PAGE:
			page += 1
			slot = 0
		var head := first_head if page == 1 else SLIM_HEAD
		var top := head + slot * ROW_HEIGHT
		var box := {
			page = page,
			slot = slot,
			span = span,
			rect = Rect2i(FRAME_X, top + ROW_PAD, FRAME.x, FRAME.y),
			row = Rect2i(0, top, PAGE_WIDTH, span * ROW_HEIGHT),
		}
		slot += span
		used[page] = slot
		var more: Array[Dictionary] = []
		var rest: PackedInt32Array = continued[i] if i < continued.size() else PackedInt32Array()
		for each in rest:
			page += 1
			var rows := clampi(each, 1, ROWS_PER_PAGE)
			more.append({page = page, slot = 0, span = rows, row = Rect2i(0, SLIM_HEAD, PAGE_WIDTH, rows * ROW_HEIGHT)})
			slot = rows
			used[page] = slot
		box["more"] = more
		boxes.append(box)
	for box in boxes:
		box["page_size"] = Vector2i(PAGE_WIDTH, (first_head if box.page == 1 else SLIM_HEAD) + int(used[box.page]) * ROW_HEIGHT)
		for each: Dictionary in box.more:
			each["page_size"] = Vector2i(PAGE_WIDTH, SLIM_HEAD + int(used[each.page]) * ROW_HEIGHT)
	return boxes


## What the text of each shot comes to on paper: [{first (the drawn rows beside the frame), more (the drawn rows of each continuation: an
## Array of Arrays), span (rows the first part fills), spans_more (rows each continuation fills)}]. Text that fits a page's three rows is
## one part; longer text fills the page and goes on, row by row, over as many continuations as it needs, so that none of it is left off.
## A drawn row is {text, tail, label, size, color, indent, height, gap} (text_atoms).
static func plan(scene: SceneShots) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var page_room := ROWS_PER_PAGE * ROW_HEIGHT - 2 * ROW_PAD
	var more_room := page_room - CONTINUED_HEAD
	for i in scene.shots.size():
		var atoms := text_atoms(ShotText.describe(scene, i))
		var total := 0
		for atom in atoms:
			total += int(atom.height) + int(atom.gap)
		if total <= page_room:
			out.append({first = atoms, more = [], span = clampi(ceili(float(total + 2 * ROW_PAD) / float(ROW_HEIGHT)), 1, ROWS_PER_PAGE), spans_more = PackedInt32Array()})
			continue
		var first: Array[Dictionary] = []
		var at := 0
		var used := 0
		while at < atoms.size() and used + int(atoms[at].height) + int(atoms[at].gap) <= page_room:
			used += int(atoms[at].height) + int(atoms[at].gap)
			first.append(atoms[at])
			at += 1
		var more: Array = []
		var spans_more := PackedInt32Array()
		while at < atoms.size():
			var part: Array[Dictionary] = []
			var height := 0
			while at < atoms.size() and (part.is_empty() or height + int(atoms[at].height) + int(atoms[at].gap) <= more_room):
				height += int(atoms[at].height) + int(atoms[at].gap)
				part.append(atoms[at])
				at += 1
			more.append(part)
			spans_more.append(clampi(ceili(float(height + 2 * ROW_PAD + CONTINUED_HEAD) / float(ROW_HEIGHT)), 1, ROWS_PER_PAGE))
		out.append({first = first, more = more, span = ROWS_PER_PAGE, spans_more = spans_more})
	return out


## The rows a shot's text is set in, one drawn row each: [{text, tail, label (on the first row of a block only), size, color, indent,
## height, gap (the space after the last row of a block)}].
static func text_atoms(lines: PackedStringArray) -> Array[Dictionary]:
	var atoms: Array[Dictionary] = []
	for block in blocks_of(lines):
		var rows: PackedStringArray = block.rows
		for r in rows.size():
			atoms.append({text = rows[r], tail = (block.tails as PackedStringArray)[r], label = block.label if r == 0 else "", size = block.size, color = block.color,
				indent = block.indent, height = block.height, gap = GAP if r == rows.size() - 1 else 0})
	return atoms


## The heading of a shot's continuation: "S7, continued".
static func continued_heading(scene: SceneShots, index: int) -> String:
	var shot := scene.shots[index]
	return "%s, continued" % (String(shot.id) if shot.id != &"" else "Shot %d" % (index + 1))


## How many rows of the page each shot's first part of text needs: 1 when its text fits beside the frame, else as many as it takes (3, a
## whole page, at most: what is more goes on in continuation_spans).
static func row_spans(scene: SceneShots) -> Array[int]:
	var spans: Array[int] = []
	for each in plan(scene):
		spans.append(each.span)
	return spans


## For each shot the rows each of its continuations fills (none for a shot whose text fits its page).
static func continuation_spans(scene: SceneShots) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for each in plan(scene):
		out.append(each.spans_more)
	return out


## The text of a shot as it is set: [{label, size, color, rows, tails, height, indent}] (the title lines large and without a label; each other
## line a label and its words wrapped to the column; a bracketed stand-in note is a block of its own, in red). `tails` is a grey
## string drawn after each row's text: the title's shorthand "(CRANE -30>-50)" is the tail of its last row, or a row of its own when it
## does not fit there, and is never broken inside its bracket. Pure given the font (the engine's fallback font, which a headless run has as well).
static func blocks_of(lines: PackedStringArray) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var font := ThemeDB.fallback_font
	var column := PAGE_WIDTH - MARGIN - TEXT_X
	for i in lines.size():
		var line := lines[i]
		if i == 0:
			var shorthand := ""
			var cut := line.rfind("   (")
			if cut > 0 and line.ends_with(")"):
				shorthand = line.substr(cut + 3)
				line = line.substr(0, cut)
			var title_rows := wrap_text(line, column, TITLE_SIZE, font)
			var tails := _blank_tails(title_rows.size())
			if shorthand != "":
				var last := title_rows[title_rows.size() - 1]
				var used := font.get_string_size(last, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x + TAIL_GAP
				if used + font.get_string_size(shorthand, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= column:
					tails[tails.size() - 1] = shorthand
				else:
					title_rows.append("")
					tails.append(shorthand)
			blocks.append({label = "", size = TITLE_SIZE, color = INK, rows = title_rows, tails = tails, height = TITLE_HEIGHT, indent = 0})
		elif i <= 2:
			var grey_rows := wrap_text(line, column, FONT_SIZE, font)
			blocks.append({label = "", size = FONT_SIZE, color = GREY, rows = grey_rows, tails = _blank_tails(grey_rows.size()), height = LINE_HEIGHT, indent = 0})
		else:
			var colon := line.find(": ")
			var label := line.substr(0, colon + 1) if colon > 0 else ""
			var words := line.substr(colon + 2) if colon > 0 else line
			var note := ""
			var bracket := words.find("  [")
			if bracket >= 0:
				note = words.substr(bracket + 2)
				words = words.substr(0, bracket)
			var word_rows := wrap_text(words, column - LABEL_WIDTH, FONT_SIZE, font)
			blocks.append({label = label, size = FONT_SIZE, color = INK, rows = word_rows, tails = _blank_tails(word_rows.size()), height = LINE_HEIGHT, indent = LABEL_WIDTH})
			if note != "":
				var note_rows := wrap_text(note, column - LABEL_WIDTH, FONT_SIZE, font)
				blocks.append({label = "", size = FONT_SIZE, color = RED, rows = note_rows, tails = _blank_tails(note_rows.size()), height = LINE_HEIGHT, indent = LABEL_WIDTH})
	return blocks


static func _blank_tails(count: int) -> PackedStringArray:
	var tails := PackedStringArray()
	tails.resize(count)
	return tails


## The places the shots name, in words, one line each, in the order of the scene's marks: every mark a shot's beats, camera, focus or
## cues name, and every mark an actor of the cast is made at (a rehearsal mark is the tools' own and is left out). A mark in an actor's
## space is told from where that actor stands as the scene begins (in front of him or behind, to his left or right); one in the place's
## own space by its map coordinates.
static func mark_sentences(scene: SceneShots) -> PackedStringArray:
	var named := {}
	for shot in scene.shots:
		for each: StringName in [shot.aim, shot.aim_to, shot.focus, shot.focus_to, shot.over_shoulder]:
			named[String(each).trim_suffix("@start")] = true
		for beat in shot.beats:
			for each: StringName in [beat.move_to, beat.face, beat.look]:
				named[String(each).trim_suffix("@start")] = true
		for cue in shot.cues:
			named[String(cue.at_ref).trim_suffix("@start")] = true
	var starts := {}   # mark -> who starts there
	for entry in scene.cast:
		if entry.spawn_mark != &"":
			named[String(entry.spawn_mark)] = true
			starts[String(entry.spawn_mark)] = ShotText.who(scene, entry.actor)
	var out := PackedStringArray()
	for mark in scene.marks:
		var name := String(mark.name)
		if name.begins_with("rehearsal.") or not named.has(name):
			continue
		var label := name.replace("_", " ")
		if starts.has(name):
			label += " (where %s starts)" % starts[name]
		out.append("%s: %s" % [label, _place_words(scene, mark)])
	return out


# Where a mark is, in words (see mark_sentences). An actor's +Z is the way he faces and his +X is to his left.
static func _place_words(scene: SceneShots, mark: SceneMark) -> String:
	if mark.space != SceneMark.Space.ACTOR_START:
		return "at x %.1f, z %.1f on the place's own map" % [mark.position.x, mark.position.z]
	var who := ShotText.who(scene, mark.actor)
	var ahead := mark.position.z
	var side := mark.position.x
	var parts := PackedStringArray()
	if absf(ahead) >= 0.05:
		parts.append("%.1f m %s %s" % [absf(ahead), "in front of" if ahead > 0.0 else "behind", who])
	if absf(side) >= 0.05:
		parts.append("%.1f m to the %s%s" % [absf(side), "left" if side > 0.0 else "right", " as he faces" if not parts.is_empty() else " of %s, as he faces" % who])
	if parts.is_empty():
		return "where %s stands as the scene begins" % who
	return ", ".join(parts)


## The height `blocks` take when drawn (each block's rows, and a gap after each).
static func text_height(blocks: Array[Dictionary]) -> int:
	var total := 0
	for block in blocks:
		total += (block.rows as PackedStringArray).size() * int(block.height) + GAP
	return total


## `text` broken into rows no wider than `width` at `size`, at spaces (a word wider than the row is broken where it must be).
static func wrap_text(text: String, width: int, size: int, font: Font) -> PackedStringArray:
	var rows := PackedStringArray()
	var row := ""
	for word in text.split(" "):
		var tried := word if row == "" else row + " " + word
		if font.get_string_size(tried, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			row = tried
			continue
		if row != "":
			rows.append(row)
		row = word
		while font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and row.length() > 1:
			var cut := row.length() - 1
			while cut > 1 and font.get_string_size(row.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				cut -= 1
			rows.append(row.substr(0, cut))
			row = row.substr(cut)
	rows.append(row)
	return rows


# ---- the tool: drawing the pages ----

const SCRIPT := "res://tools/story/storyboard_page.gd"
const USAGE := "usage: tools/godot.sh --render -s res://tools/story/storyboard_page.gd -- --scene=<id> --out=<dir>"
const TITLE_BIG := 26
const TITLE_BIG_HEIGHT := 34
const KIND_WORDS := {
	SceneShots.Kind.CUTSCENE: "Cutscene (cinema bars; the game's picture is taken over)",
	SceneShots.Kind.MINI: "Mini-cutscene (no bars; the game's picture is taken over)",
	SceneShots.Kind.MOMENT: "Combat moment (a short camera dip; the fight goes on)",
}
const STATUS_WORDS := {
	SceneShots.Status.DRAFT: "DRAFT",
	SceneShots.Status.IN_REVIEW: "IN REVIEW",
	SceneShots.Status.APPROVED: "APPROVED",
}


func _initialize() -> void:
	quit(await _run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var id := ""
	var out := ""
	for arg in args:
		if arg.begins_with("--scene="):
			id = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		else:
			printerr("storyboard_page.gd: unknown argument '%s'" % arg)
			return _usage()
	if id == "" or out == "":
		return _usage()
	if out.is_relative_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	var path := "res://scenes/story/%s/shots.tres" % id
	if not ResourceLoader.exists(path):
		printerr("storyboard_page.gd: no scene '%s'" % id)
		return 2
	var scene := load(path) as SceneShots
	if scene == null:
		printerr("storyboard_page.gd: '%s' is not a shot list" % path)
		return 2
	var textures: Array[ImageTexture] = []
	for i in scene.shots.size():
		var frame := out.path_join("frames/shot-%02d.png" % (i + 1))
		var image := Image.load_from_file(frame) if FileAccess.file_exists(frame) else null
		if image == null:
			printerr("storyboard_page.gd: the frame of shot %d is missing: %s (run tools/storyboard.sh)" % [i + 1, frame])
			return 1
		textures.append(ImageTexture.create_from_image(image))
	ShotText._registry_fetch(&"speakers", &"abarax")   # (makes sure the Registry has scanned: a script run with -s starts before it has)
	var standins := stand_ins(scene)
	var head := header_blocks(scene, standins)
	var texts := plan(scene)
	var spans: Array[int] = []
	var continued: Array = []
	for each in texts:
		spans.append(each.span)
		continued.append(each.spans_more)
	var boxes := layout(scene.shots.size(), spans, maxi(HEAD, header_height(head)), continued)
	var pages := 1
	for box in boxes:
		pages = maxi(pages, int(box.page))
		for more: Dictionary in box.more:
			pages = maxi(pages, int(more.page))
	DirAccess.make_dir_recursive_absolute(out)
	for page in range(1, pages + 1):
		var sheet := _Sheet.new()
		sheet.scene = scene
		sheet.page = page
		sheet.pages = pages
		sheet.head = head
		sheet.rows = []
		var size := Vector2i(PAGE_WIDTH, SLIM_HEAD + ROW_HEIGHT)
		for i in boxes.size():
			if boxes[i].page == page:
				size = boxes[i].page_size
				sheet.rows.append({box = boxes[i], texture = textures[i], atoms = texts[i].first, heading = ""})
			for k in boxes[i].more.size():
				var more: Dictionary = boxes[i].more[k]
				if more.page == page:
					size = more.page_size
					sheet.rows.append({box = more, texture = null, atoms = texts[i].more[k], heading = continued_heading(scene, i)})
		sheet.size = Vector2(size)
		var viewport := SubViewport.new()
		viewport.disable_3d = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.size = size
		viewport.add_child(sheet)
		root.add_child(viewport)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		viewport.queue_free()
		var file := out.path_join("storyboard-%d.png" % page)
		var err := picture.save_png(file)
		if err != OK:
			printerr("storyboard_page.gd: cannot write '%s': %s" % [file, error_string(err)])
			return 1
		print("storyboard_page.gd: wrote %s (%dx%d)" % [file, picture.get_width(), picture.get_height()])
	return 0


func _usage() -> int:
	printerr(USAGE)
	return 2


## Everything in the scene that is not final yet, once each, with the shot it first appears in: [{kind, shot, text}] in the order
## of the shots. kind is "portrait" (a line of a speaker whose drawing is a stand-in), "clip" (a beat marked placeholder), "model"
## (a cast member shown by another character's body: ShotText.stand_in_model) or "sound" (a sound cue with no recording).
## `speakers` (a Callable from a speaker's id to its Speaker) and `has_sound` (from a sound's id to whether it is recorded)
## stand in for the Registry, which a test does not want to change.
static func stand_ins(scene: SceneShots, speakers := Callable(), has_sound := Callable()) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen := {}
	for i in scene.shots.size():
		var shot := scene.shots[i]
		var name := String(shot.id) if shot.id != &"" else "shot %d" % (i + 1)
		for beat in shot.beats:
			var clip_key := "clip/%s/%s" % [beat.actor, beat.clip]
			if beat.placeholder and beat.clip != &"" and not seen.has(clip_key):
				seen[clip_key] = true
				var who := ShotText.who(scene, beat.actor)
				found.append({kind = "clip", shot = name, text = "%s's clip '%s' is not made yet, so %s just stands" % [who, beat.clip, who]})
		for line in shot.lines:
			var speaker := ShotText.speaker_of(line.speaker, speakers)
			var look_key := "portrait/%s/%s" % [line.speaker, line.expr]
			if speaker != null and speaker.placeholder_exprs.has(line.expr) and not seen.has(look_key):
				seen[look_key] = true
				var sentence := ShotText.portrait_sentence(scene, line.speaker, line.expr, speaker, speakers)
				found.append({kind = "portrait", shot = name, text = sentence.substr(0, 1).to_upper() + sentence.substr(1)})
		for cue in shot.cues:
			var sound_key := "sound/%s" % cue.id
			if cue.kind == CueEvent.Kind.SOUND and cue.id != &"" and not seen.has(sound_key) and not _recorded(cue.id, has_sound):
				seen[sound_key] = true
				found.append({kind = "sound", shot = name, text = "The sound '%s' has no recording yet" % cue.id})
		for entry in scene.cast:
			var model_key := "model/%s" % entry.actor
			if not seen.has(model_key) and ShotText.stand_in_model(entry) and _appears(entry, shot):
				seen[model_key] = true
				found.append({kind = "model", shot = name, text = "%s is shown by a stand-in model (%s)" % [ShotText.who(scene, entry.actor), String(entry.def.id).replace("_", " ")]})
	return found


# Whether the sound `id` has a recording: `has_sound` says when it is given, else the Registry's cue has a stream.
static func _recorded(id: StringName, has_sound: Callable) -> bool:
	if has_sound.is_valid():
		return has_sound.call(id)
	var cue := ShotText._registry_fetch(&"sounds", id) as SoundCue
	return cue != null and not cue.streams.is_empty()


# Whether `entry`'s actor is in `shot`: a beat of his, a line of his speaker's, or the camera looking at him.
static func _appears(entry: CastEntry, shot: Shot) -> bool:
	for beat in shot.beats:
		if beat.actor == entry.actor:
			return true
	for line in shot.lines:
		if entry.speaker != &"" and line.speaker == entry.speaker:
			return true
	return [shot.aim, shot.aim_to, shot.focus, shot.focus_to, shot.over_shoulder].has(entry.actor)


## The header of the first page, as blocks (see blocks_of): the title, the facts, the stand-in band.
static func header_blocks(scene: SceneShots, standins: Array[Dictionary]) -> Dictionary:
	var font := ThemeDB.fallback_font
	var column := PAGE_WIDTH - 2 * MARGIN
	var facts: Array[PackedStringArray] = []
	var title := String(scene.id).replace("_", " ")
	title = title.substr(0, 1).to_upper() + title.substr(1)
	var kind: String = KIND_WORDS.get(scene.kind, "?")
	facts.append(wrap_text("%s  ·  Revision %d  ·  Status: %s" % [kind, scene.revision, STATUS_WORDS.get(scene.status, "?")], column, FONT_SIZE, font))
	var glide_in := float(scene.lead_in) / ShotText.FPS
	var glide_out := float(scene.lead_out) / ShotText.FPS
	var place := "where the player stands (the live region)" if scene.region == "" else scene.region.get_file().get_basename().replace("_", " ")
	facts.append(wrap_text("%d shots, %.2f s of shots, with a camera glide in of %.2f s and out of %.2f s or more  ·  Place: %s" % [scene.shots.size(), float(scene.length()) / ShotText.FPS, glide_in, glide_out, place], column, FONT_SIZE, font))
	var cast := PackedStringArray()
	for entry in scene.cast:
		var name := ShotText.who(scene, entry.actor)
		if entry.source == CastEntry.Source.LIVE_PLAYER:
			name += " (the player)"
		elif ShotText.stand_in_model(entry):
			name += " (shown by a stand-in model)"
		cast.append(name)
	facts.append(wrap_text("Cast: %s" % ", ".join(cast), column, FONT_SIZE, font))
	var places := mark_sentences(scene)
	var place_rows := PackedStringArray()
	if not places.is_empty():
		place_rows.append("Places the shots name:")
		for each in places:
			place_rows.append_array(wrap_text("• " + each, column - 24, FONT_SIZE, font))
	var band := PackedStringArray()
	if standins.is_empty():
		band.append("No stand-ins or placeholders: every clip and portrait in this scene is real.")
	else:
		band.append("NOT FINAL: %d stand-in%s or placeholder%s in this scene. Each is marked on its row too." % [standins.size(), "" if standins.size() == 1 else "s", "" if standins.size() == 1 else "s"])
		for found in standins:
			band.append_array(wrap_text("• %s: %s" % [found.shot, found.text], column - 24, FONT_SIZE, font))
	return {title = title, facts = facts, marks = places, marks_rows = place_rows, band = band, good = standins.is_empty()}


## How tall the header of the first page is for those blocks.
static func header_height(head: Dictionary) -> int:
	var rows := 0
	for fact: PackedStringArray in head.facts:
		rows += fact.size()
	return 14 + TITLE_BIG_HEIGHT + rows * LINE_HEIGHT + 4 + (head.marks_rows as PackedStringArray).size() * LINE_HEIGHT + 8 + (head.band as PackedStringArray).size() * LINE_HEIGHT + 20 + 8


# One page, drawn.
class _Sheet extends Control:
	var scene: SceneShots
	var page := 1
	var pages := 1
	var head: Dictionary
	var rows: Array = []

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), StoryboardPage.PAPER)
		var top := StoryboardPage.SLIM_HEAD
		if page == 1:
			top = _draw_head(font)
		else:
			var title := String(scene.id).replace("_", " ")
			_text(font, Vector2(StoryboardPage.MARGIN, 30), "%s  ·  Revision %d  ·  %s" % [title.substr(0, 1).to_upper() + title.substr(1), scene.revision, StoryboardPage.STATUS_WORDS.get(scene.status, "?")], StoryboardPage.FONT_SIZE, StoryboardPage.GREY)
		_text(font, Vector2(size.x - StoryboardPage.MARGIN - 110, 30 if page > 1 else 28), "page %d of %d" % [page, pages], StoryboardPage.FONT_SIZE, StoryboardPage.GREY)
		for each: Dictionary in rows:
			_draw_row(font, each)
		draw_rect(Rect2(0, top - 1, size.x, 1), StoryboardPage.RULE)

	func _draw_head(font: Font) -> int:
		var y := 14
		_text(font, Vector2(StoryboardPage.MARGIN, y + 24), head.title, StoryboardPage.TITLE_BIG, StoryboardPage.INK)
		y += StoryboardPage.TITLE_BIG_HEIGHT
		for fact: PackedStringArray in head.facts:
			for row in fact:
				_text(font, Vector2(StoryboardPage.MARGIN, y + 14), row, StoryboardPage.FONT_SIZE, StoryboardPage.INK)
				y += StoryboardPage.LINE_HEIGHT
		y += 4
		var marks_rows: PackedStringArray = head.marks_rows
		for i in marks_rows.size():
			_text(font, Vector2(StoryboardPage.MARGIN + (0 if i == 0 else 12), y + 14), marks_rows[i], StoryboardPage.FONT_SIZE, StoryboardPage.GREY if i == 0 else StoryboardPage.INK)
			y += StoryboardPage.LINE_HEIGHT
		y += 8
		var band: PackedStringArray = head.band
		var colour := StoryboardPage.GOOD if head.good else StoryboardPage.BAND
		draw_rect(Rect2(StoryboardPage.MARGIN - 6, y - 2, size.x - 2 * StoryboardPage.MARGIN + 12, band.size() * StoryboardPage.LINE_HEIGHT + 10), colour)
		for i in band.size():
			var warning: bool = i == 0 and not head.good
			_text(font, Vector2(StoryboardPage.MARGIN + (0 if i == 0 or head.good else 12), y + 14 + i * StoryboardPage.LINE_HEIGHT), band[i], StoryboardPage.FONT_SIZE, StoryboardPage.RED if warning else StoryboardPage.INK)
		return y + band.size() * StoryboardPage.LINE_HEIGHT + 10

	func _draw_row(font: Font, each: Dictionary) -> void:
		var box: Dictionary = each.box
		var row: Rect2i = box.row
		draw_rect(Rect2(row.position.x, row.end.y - 1, row.size.x, 1), StoryboardPage.RULE)
		var y := row.position.y + StoryboardPage.ROW_PAD
		if each.texture != null:
			var rect: Rect2i = box.rect
			draw_rect(Rect2(rect).grow(2), StoryboardPage.INK, false, 2.0)
			draw_texture(each.texture, Vector2(rect.position))
		else:
			_text(font, Vector2(StoryboardPage.TEXT_X, y + StoryboardPage.TITLE_HEIGHT - 5), each.heading, StoryboardPage.TITLE_SIZE, StoryboardPage.GREY)
			y += StoryboardPage.CONTINUED_HEAD
		for atom: Dictionary in each.atoms:
			var base := y + int(atom.height) - 5 if atom.size == StoryboardPage.TITLE_SIZE else y + 14
			if atom.label != "":
				_text(font, Vector2(StoryboardPage.TEXT_X, y + 14), atom.label, StoryboardPage.FONT_SIZE, StoryboardPage.LABEL)
			var x := StoryboardPage.TEXT_X + int(atom.indent)
			_text(font, Vector2(x, base), atom.text, atom.size, atom.color)
			if atom.tail != "":
				var after := font.get_string_size(atom.text, HORIZONTAL_ALIGNMENT_LEFT, -1, atom.size).x + (StoryboardPage.TAIL_GAP if atom.text != "" else 0)
				_text(font, Vector2(x + after, base), atom.tail, StoryboardPage.FONT_SIZE, StoryboardPage.GREY)
			y += int(atom.height) + int(atom.gap)

	func _text(font: Font, at: Vector2, text: String, font_size: int, colour: Color) -> void:
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
