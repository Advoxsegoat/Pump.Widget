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
## to a page; a row whose text does not fit one row takes two (or three), and the layout says so (`span`). The pages are
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
	const MOVE_SHORT := ["STATIC", "PAN", "DOLLY", "CRANE", "ORBIT", "HANDHELD"]
	const FPS := 60.0
	const CHECKER := "res://story/shot_checker.gd"
	static var _checker: RefCounted

	## The text of shot `index` of `scene`, one string a row of the sheet. The first two are the shot's title (its name,
	## framing and camera move, in plain words with the shorthand beside) and its timing (seconds first, frames after);
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
		out.append("ACTION: " + (shot.action if shot.action != "" else "(no action written yet)"))
		out.append("CAMERA: " + _camera_sentence(scene, shot, index))
		for beat in shot.beats:
			out.append("DOES: " + _beat_sentence(scene, beat))
		for line in shot.lines:
			out.append("SAYS: " + _line_sentence(line))
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
		var last := maxi(shot.length - 1, 0)
		if shot.key_frame >= 0:
			return clampi(shot.key_frame, 0, last)
		if not shot.lines.is_empty():
			var line := shot.lines[shot.lines.size() - 1]
			return clampi(line.at + int(_shared().call("typing_frames", line.text)), 0, last)
		if scene != null:
			var arrival := _arrival(scene, shot)
			if arrival >= 0 and arrival <= last:
				return arrival
		return clampi(shot.length / 2, 0, last)

	## The key frame of each shot, counted from the first shot's first frame (the scene's own clock, without the glide in).
	static func key_frames(scene: SceneShots) -> PackedInt32Array:
		var frames := PackedInt32Array()
		for shot in scene.shots:
			frames.append(shot.start + key_frame(shot, scene))
		return frames

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

	# "at the start" or "at +0.23 s, frame 14": the time in seconds first, the frame after.
	static func _when(frames: int) -> String:
		return "at the start" if frames == 0 else "at +%s, frame %d" % [_secs(frames), frames]

	static func _zoom_of(shot: Shot) -> int:
		return shot.zoom if shot.zoom > 0 else CinePose.FRAMING_ZOOM[shot.framing]

	static func _pitch_of(shot: Shot) -> float:
		return shot.pitch_deg if shot.pitch_deg != 0.0 else CinePose.FRAMING_PITCH[shot.framing]

	# What the camera does, as the end of "the camera ...".
	static func _move_phrase(scene: SceneShots, shot: Shot) -> String:
		match shot.move:
			Shot.CamMove.PAN:
				return "turns from %s to %s" % [who(scene, shot.aim), who(scene, shot.aim_to)]
			Shot.CamMove.DOLLY:
				return "pushes in" if shot.zoom_to > _zoom_of(shot) else "pulls out"
			Shot.CamMove.CRANE:
				return "rises" if shot.pitch_to_deg < _pitch_of(shot) else "sinks"
			Shot.CamMove.ORBIT:
				return "circles round"
			Shot.CamMove.HANDHELD:
				return "is handheld and shakes %s" % ("a lot" if shot.shake >= 0.5 else "a little")
		return "holds still"

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
		if shot.move == Shot.CamMove.DOLLY and shot.zoom_to > 0:
			text += ", from %s to %s" % [ZOOM_NAME[clampi(_zoom_of(shot), 1, 4)], ZOOM_NAME[clampi(shot.zoom_to, 1, 4)]]
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
			parts.append("plays %s" % beat.clip)
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

	static func _line_sentence(line: DialogueLine) -> String:
		var speaker := _registry_fetch(&"speakers", line.speaker) as Speaker
		var name := speaker.display_name if speaker != null else String(line.speaker)
		var hold := int(_shared().call("hold_of", line))
		var text := "%s: \"%s\" (%s, on screen %s)" % [name, line.text, _when(line.at), _secs(hold)]
		if speaker != null and speaker.placeholder_exprs.has(line.expr):
			if speaker.portraits.is_empty():
				text += "  [STAND-IN: a plain card, the portrait is not drawn yet]"
			else:
				text += "  [STAND-IN: this look is not drawn yet, the neutral drawing shows]"
		return text

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
## page_size}. `spans` is how many rows each shot needs (row_spans; 1 where not given); a shot that does not fit in what is left
## of a page starts the next one. The first page's header is `first_head` high; later pages carry a slim title.
static func layout(shot_count: int, spans: Array[int] = [], first_head := HEAD) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var page := 1
	var slot := 0
	for i in shot_count:
		var span := clampi(spans[i] if i < spans.size() else 1, 1, ROWS_PER_PAGE)
		if slot + span > ROWS_PER_PAGE:
			page += 1
			slot = 0
		var head := first_head if page == 1 else SLIM_HEAD
		var top := head + slot * ROW_HEIGHT
		boxes.append({
			page = page,
			slot = slot,
			span = span,
			rect = Rect2i(FRAME_X, top + ROW_PAD, FRAME.x, FRAME.y),
			row = Rect2i(0, top, PAGE_WIDTH, span * ROW_HEIGHT),
			page_size = Vector2i(PAGE_WIDTH, head + ROWS_PER_PAGE * ROW_HEIGHT),
		})
		slot += span
	return boxes


## How many rows of the page each shot's text needs: 1 when its text fits beside the frame, else as many as it takes.
static func row_spans(scene: SceneShots) -> Array[int]:
	var spans: Array[int] = []
	for i in scene.shots.size():
		var height := text_height(blocks_of(ShotText.describe(scene, i)))
		spans.append(clampi(ceili(float(height + 2 * ROW_PAD) / float(ROW_HEIGHT)), 1, ROWS_PER_PAGE))
	return spans


## The text of a shot as it is set: [{label, size, color, rows, height}] (the title lines large and without a label; each other
## line a label and its words wrapped to the column; a bracketed stand-in note is a block of its own, in red). Pure given the
## font (the engine's fallback font, which a headless run has as well).
static func blocks_of(lines: PackedStringArray) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var font := ThemeDB.fallback_font
	var column := PAGE_WIDTH - MARGIN - TEXT_X
	for i in lines.size():
		var line := lines[i]
		if i == 0:
			blocks.append({label = "", size = TITLE_SIZE, color = INK, rows = wrap_text(line, column, TITLE_SIZE, font), height = TITLE_HEIGHT, indent = 0})
		elif i == 1:
			blocks.append({label = "", size = FONT_SIZE, color = GREY, rows = wrap_text(line, column, FONT_SIZE, font), height = LINE_HEIGHT, indent = 0})
		else:
			var colon := line.find(": ")
			var label := line.substr(0, colon + 1) if colon > 0 else ""
			var words := line.substr(colon + 2) if colon > 0 else line
			var note := ""
			var bracket := words.find("  [")
			if bracket >= 0:
				note = words.substr(bracket + 2)
				words = words.substr(0, bracket)
			blocks.append({label = label, size = FONT_SIZE, color = INK, rows = wrap_text(words, column - LABEL_WIDTH, FONT_SIZE, font), height = LINE_HEIGHT, indent = LABEL_WIDTH})
			if note != "":
				blocks.append({label = "", size = FONT_SIZE, color = RED, rows = wrap_text(note, column - LABEL_WIDTH, FONT_SIZE, font), height = LINE_HEIGHT, indent = LABEL_WIDTH})
	return blocks


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
