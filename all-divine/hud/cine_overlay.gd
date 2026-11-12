class_name CineOverlay
extends Control
## The scene's letterbox bars and dialogue box, drawn in the HUD's viewport (exactly the 640x360 picture) over the Hud, in
## whole picture pixels so that they are as crisp as the pixels under them. The Director adds it beside the Hud at run
## time and suppresses the Hud (Hud.suppressed) while a scene plays; the CineCamera sets `letterbox` every frame.
##
## The bars are BAR (44) px at full weight, top and bottom: a 2.35:1 picture of 640x272. They are the only shapes that
## cover the picture (88 of its 360 rows, 0.244). The dialogue box is BOX (620x64), MARGIN (10) px from the sides and
## MARGIN px above the bars, or above the picture's bottom with none; the speaker's portrait is drawn in it at 48x48,
## MARGIN - 2 px in, with the line of text beside it and the speaker's name on a tab at its top left.
##
## A line is typed at CPS (30) characters a second, one character every two physics frames, with a voice blip
## (`voice_blip`, at the speaker's `blip_pitch`) on every BLIP_EVERY'th character, and goes after `hold_frames` frames.
## The overlay counts its own physics frames (`auto`), so a paused tree stops the typing and the hold where they were and
## a resume goes on from there: whoever shows lines must not call `advance` as well. `advance` is for a run with `auto`
## off (tests, the storyboard tool).
##
## The queries (bar_rects, box_rect, portrait_rect, visible_text, ...) say what is drawn, in picture pixels, and the
## drawing uses the same, so the tests read what a player would see.

const BAR := 44
const BOX := Vector2i(620, 64)
const MARGIN := 10
const PORTRAIT := 48
## Characters typed a second, and a blip on every this many of them.
const CPS := 30
const BLIP_EVERY := 2
const MAX_LINES := 3
## The shown text's size and the outline round it, as the Hud's.
const FONT_SIZE := 8
const OUTLINE := 3
## The portrait's and the text's distance from the box's edge, the portrait's gap to its text, the rows of text.
const INSET := 8
const GAP := 8
const LINE_HEIGHT := 12
## The name tab: its height and the room round the name.
const TAB_HEIGHT := 11
const TAB_PAD := 4
## Frames a line without a hold of its own stays up after it is typed.
const DEFAULT_HOLD_AFTER := 45
const PICTURE := Vector2i(640, 360)

## How far the bars are in, 0 to 1 (more is held to 1).
var letterbox := 0.0:
	set(value):
		letterbox = value
		queue_redraw()
## A small caption at the top left, for the animatic (the name of the shot, what a cue is).
var burn_in := "":
	set(value):
		burn_in = value
		queue_redraw()
## Whether the overlay counts its own physics frames (see the header).
var auto := true

var _speaker: Speaker
var _text := ""
var _expr: StringName = &"neutral"
var _hold := 0
var _elapsed := 0  # physics frames since the line was shown
var _showing := false
var _rows: Array[Vector2i] = []  # (start, length) of each row in _text


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(PICTURE)


func _physics_process(_delta: float) -> void:
	if auto and _showing:
		advance(1)


## The frames a line of `characters` characters takes to type.
static func typing_frames(characters: int) -> int:
	return ceili(characters * 60.0 / CPS)


## Shows `text` by `speaker` with the portrait of `expr` (neutral if the speaker has none such), typed from nothing and
## held `hold_frames` frames from now; 0 holds it for its typing time and DEFAULT_HOLD_AFTER more.
func show_line(speaker: Speaker, text: String, expr: StringName, hold_frames: int) -> void:
	_speaker = speaker
	_text = text
	_expr = expr
	_hold = hold_frames if hold_frames > 0 else typing_frames(text.length()) + DEFAULT_HOLD_AFTER
	_elapsed = 0
	_showing = true
	_rows = _wrap(text)
	queue_redraw()


## Goes `frames` physics frames on: types the characters that are due, blips on those that are to, and ends the line when
## its hold is over.
func advance(frames := 1) -> void:
	for i in frames:
		if not _showing:
			return
		var before := _typed()
		_elapsed += 1
		var after := _typed()
		for count in range(before + 1, after + 1):
			if (count - 1) % BLIP_EVERY == 0:
				Sfx.play(&"voice_blip", null, _speaker.blip_pitch if _speaker != null else 1.0)
		if _elapsed >= _hold:
			close()
	queue_redraw()


## Takes the box away.
func close() -> void:
	_showing = false
	_speaker = null
	_text = ""
	_rows = []
	_elapsed = 0
	queue_redraw()


## Whether a line is up now.
func showing() -> bool:
	return _showing


## The bars, in picture pixels: top then bottom, none when there are none to see.
func bar_rects() -> Array[Rect2i]:
	var height := bar_height()
	var rects: Array[Rect2i] = []
	if height > 0:
		rects.append(Rect2i(0, 0, PICTURE.x, height))
		rects.append(Rect2i(0, PICTURE.y - height, PICTURE.x, height))
	return rects


## How tall each bar is: a whole number of pixels, BAR at full weight.
func bar_height() -> int:
	return roundi(clampf(letterbox, 0.0, 1.0) * BAR)


## The dialogue box, in picture pixels: its bottom MARGIN px above the bars, or above the picture's bottom with none.
func box_rect() -> Rect2i:
	return Rect2i(MARGIN, PICTURE.y - bar_height() - MARGIN - BOX.y, BOX.x, BOX.y)


## The speaker's name tab: sits on the box's top left.
func tab_rect() -> Rect2i:
	var box := box_rect()
	var width := ceili(text_width(_speaker.display_name)) + 2 * TAB_PAD if _speaker != null else 2 * TAB_PAD
	return Rect2i(box.position.x, box.position.y - TAB_HEIGHT, width, TAB_HEIGHT)


## Where the portrait is drawn: 48x48, INSET px inside the box's top left.
func portrait_rect() -> Rect2i:
	return Rect2i(box_rect().position + Vector2i(INSET, INSET), Vector2i(PORTRAIT, PORTRAIT))


## Where the text goes: beside the portrait, MAX_LINES rows high.
func text_rect() -> Rect2i:
	var box := box_rect()
	var left := INSET + PORTRAIT + GAP
	return Rect2i(box.position + Vector2i(left, INSET), Vector2i(BOX.x - left - INSET, BOX.y - 2 * INSET))


## The portrait of the line up now (null when none is).
func portrait() -> Texture2D:
	if _speaker == null:
		return null
	var picture := _speaker.portraits.get(_expr) as Texture2D
	return picture if picture != null else _speaker.portraits.get(&"neutral") as Texture2D


## The characters typed so far of the line up now (nothing when none is).
func visible_text() -> String:
	return _text.substr(0, _typed()) if _showing else ""


## `text` as the rows the box draws it in: as many words as fit the text's width, a word wider than a row broken where it
## must. No letter is lost; a space where a row breaks is.
func lines_of(text: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for row in _wrap(text):
		lines.append(text.substr(row.x, row.y))
	return lines


## How wide `line` is drawn, in pixels.
func text_width(line: String) -> float:
	return ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


## The share of the picture the bars cover (never more than 88 of 360 rows: 0.244).
func covered_fraction() -> float:
	var area := 0
	for bar in bar_rects():
		area += bar.get_area()
	return float(area) / float(PICTURE.x * PICTURE.y)


## The share of the picture the dialogue box (with its tab) takes, 0 with no line up. A panel with the picture
## showing round it, not a cover: it is counted apart from covered_fraction.
func box_fraction() -> float:
	if not _showing:
		return 0.0
	return float(box_rect().get_area() + tab_rect().get_area()) / float(PICTURE.x * PICTURE.y)


func _typed() -> int:
	return mini(_text.length(), _elapsed * CPS / 60)


# The rows of `text`, as (start, length) in it.
func _wrap(text: String) -> Array[Vector2i]:
	var rows: Array[Vector2i] = []
	var width := float(text_rect().size.x)
	var pos := 0
	while pos < text.length():
		while pos < text.length() and text[pos] == " ":
			pos += 1
		if pos >= text.length():
			break
		var fit := pos  # the furthest end at which text[pos:fit] fits
		var space := -1  # the last space in what fits
		while fit < text.length() and text_width(text.substr(pos, fit + 1 - pos)) <= width:
			fit += 1
			if text[fit - 1] == " ":
				space = fit - 1
		if fit >= text.length():
			rows.append(Vector2i(pos, text.length() - pos))
			break
		if fit == pos:
			fit = pos + 1  # a letter wider than the row: it goes alone
		if space > pos and text[fit] != " ":
			rows.append(Vector2i(pos, space - pos))
			pos = space + 1
		else:
			rows.append(Vector2i(pos, fit - pos))
			pos = fit
	return rows


func _draw() -> void:
	var ink := Color(Hud.INK, 1.0)
	for bar in bar_rects():
		draw_rect(Rect2(bar), ink)
	var font := ThemeDB.fallback_font
	if burn_in != "":
		var caption := Vector2(MARGIN, bar_height() + MARGIN + FONT_SIZE)
		draw_string_outline(font, caption, burn_in, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, OUTLINE, Hud.INK)
		draw_string(font, caption, burn_in, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Hud.WHITE)
	if not _showing:
		return
	var box := box_rect()
	var tab := tab_rect()
	_panel(tab)
	_panel(box)
	draw_rect(Rect2(tab.position.x + 1, box.position.y, tab.size.x - 2, 1), Hud.INK)  # the tab opens into the box
	var name_at := Vector2(tab.position.x + TAB_PAD, tab.position.y + FONT_SIZE + 1)
	draw_string_outline(font, name_at, _speaker.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, OUTLINE, Hud.INK)
	draw_string(font, name_at, _speaker.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Hud.WHITE)
	var face := portrait()
	if face != null:
		draw_texture(face, Vector2(portrait_rect().position))
	var typed := _typed()
	var area := text_rect()
	for i in mini(_rows.size(), MAX_LINES):
		var row := _rows[i]
		var shown := mini(row.y, typed - row.x)
		if shown <= 0:
			break
		var at := Vector2(area.position.x, area.position.y + i * LINE_HEIGHT + FONT_SIZE)
		draw_string_outline(font, at, _text.substr(row.x, shown), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, OUTLINE, Hud.INK)
		draw_string(font, at, _text.substr(row.x, shown), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Hud.WHITE)


# A filled rectangle in the box's ink with a one pixel white border, made of rows and columns so that it is crisp.
func _panel(rect: Rect2i) -> void:
	draw_rect(Rect2(rect), Hud.INK)
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1), Hud.WHITE)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), Hud.WHITE)
	draw_rect(Rect2(rect.position.x, rect.position.y, 1, rect.size.y), Hud.WHITE)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), Hud.WHITE)
