class_name CineOverlay
extends Control
## The scene's letterbox bars and dialogue box, drawn in the HUD's viewport (exactly the 640x360 picture) over the Hud, in
## whole picture pixels so that they are as crisp as the pixels under them. The Director adds it beside the Hud at run
## time and suppresses the Hud (Hud.suppressed) while a scene plays; the CineCamera sets `letterbox` every frame.
##
## The bars are BAR (44) px at full weight, top and bottom: a 2.35:1 picture of 640x272. They are the only shapes that
## cover the picture (88 of its 360 rows, 0.244). The dialogue box is BOX (620x64), MARGIN (10) px from the sides and its
## bottom BOTTOM (4) px above the picture's bottom, over the lower bar, with or without bars; the rows between the top
## bar and the name tab's top edge are the free band (free_band), and the part of it right of the card is the free area
## (free_rect), where a shot with a line frames its people. The speaker's portrait is a card (PortraitCard: 116x160 picture
## pixels, drawn in the window at the picture's scale and not in this viewport) standing at the box's left and rising above
## it; the line of text is beside it (GAP px right of the card) and the speaker's name is on a tab on the box's top edge, which
## begins where the text does.
##
## A line is typed at CPS (30) characters a second, one character every two physics frames, with a voice blip
## (`voice_blip`, at the speaker's `blip_pitch`) on every BLIP_EVERY'th character, and goes after `hold_frames` frames.
## The overlay counts its own physics frames (`auto`), so a paused tree stops the typing and the hold where they were and
## a resume goes on from there: whoever shows lines must not call `advance` as well. `advance` is for a run with `auto`
## off (tests, the storyboard tool).
##
## The queries (bar_rects, box_rect, portrait_rect, visible_text, ...) say what is drawn, in picture pixels, and the
## drawing uses the same, so the tests read what a player would see. The card is made when a line is shown and freed when the
## box closes or the overlay leaves the tree (`_card`), so a scene cut short at any frame leaves none.

const BAR := 44
const BOX := Vector2i(620, 64)
const MARGIN := 10
## The box's bottom edge is this many rows above the picture's bottom: it lies over the lower bar, which it leaves no more
## than the bar's own edge showing round it, so that the picture between the bars is the people's.
const BOTTOM := 4
## Characters typed a second, and a blip on every this many of them.
const CPS := 30
const BLIP_EVERY := 2
const MAX_LINES := 3
## The shown text's size and the outline round it, as the Hud's.
const FONT_SIZE := 8
const OUTLINE := 3
## The text's distance from the box's edge, the gap between the card and the text (and the free area), the rows of text.
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
# The card of the line up now, in the PixelStage (null when none is up or there is no stage).
var _card: PortraitCard
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
	_show_card()
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
	_drop_card()
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


## The dialogue box, in picture pixels: its bottom BOTTOM px above the picture's bottom, whatever the bars.
func box_rect() -> Rect2i:
	return _box()


## The rows of the picture that nothing covers while a line is up: from the top bar's lower edge (the top of the picture
## with no bars) to the name tab's upper edge, as (first row, row after the last).
static func free_band(bars: bool) -> Vector2i:
	return Vector2i(BAR if bars else 0, PICTURE.y - BOTTOM - BOX.y - TAB_HEIGHT)


## What nothing covers while a line is up, in the picture: the free band's rows, right of the card (and GAP clear of it) to
## the picture's right edge. The camera frames a shot with a line in the middle of it (CinePose.solve).
static func free_rect(bars: bool) -> Rect2i:
	var band := free_band(bars)
	var left := _card_rect().end.x + GAP
	return Rect2i(left, band.x, PICTURE.x - left, band.y - band.x)


## The speaker's name tab: sits on the box's top edge, beginning where the text does (GAP px right of the card).
func tab_rect() -> Rect2i:
	var box := box_rect()
	var width := ceili(text_width(_speaker.display_name)) + 2 * TAB_PAD if _speaker != null else 2 * TAB_PAD
	return Rect2i(_card_rect().end.x + GAP, box.position.y - TAB_HEIGHT, width, TAB_HEIGHT)


## Where the card stands, in picture pixels: 116x160, at the box's left (6 px in) and rising above it (its bottom 2 px
## above the box's). The card itself is drawn in the window (PortraitCard).
func portrait_rect() -> Rect2i:
	return _card_rect()


## Where the text goes: beside the card, MAX_LINES rows high.
func text_rect() -> Rect2i:
	var box := box_rect()
	var left := _card_rect().end.x + GAP
	return Rect2i(left, box.position.y + INSET, box.end.x - INSET - left, BOX.y - 2 * INSET)


## The card picture of the line up now (null when none is): the speaker's own, else the blank card.
func portrait() -> Texture2D:
	if _speaker == null:
		return null
	return _speaker.card(_expr)


## The rows of the line up now as drawn, each as far as it is typed.
func rows_shown() -> PackedStringArray:
	var shown := PackedStringArray()
	if not _showing:
		return shown
	var typed := _typed()
	for row in _rows:
		if typed > row.x:
			shown.append(_text.substr(row.x, mini(row.y, typed - row.x)))
	return shown


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


# The dialogue box, in picture pixels: its bottom BOTTOM px above the picture's bottom, whatever the bars.
static func _box() -> Rect2i:
	return Rect2i(MARGIN, PICTURE.y - BOTTOM - BOX.y, BOX.x, BOX.y)


# The card's rectangle, in picture pixels.
static func _card_rect() -> Rect2i:
	return PortraitCard.rect_for(_box())


# Shows the card of the line up now, in the PixelStage this overlay's viewport is the Hud of (there is none to show it in when
# the overlay is on its own: its queries still say where the card would be).
func _show_card() -> void:
	var picture := portrait()
	if picture == null:
		_drop_card()
		return
	if _card == null or not is_instance_valid(_card):
		var stage := _stage()
		if stage == null:
			return
		_card = PortraitCard.new()
		_card.box = _box()
		if stage.is_node_ready():
			stage.add_child(_card)
		else:
			stage.add_child.call_deferred(_card)
	_card.show_card(picture)


# Takes the card away with the line: hidden now, freed at the end of the frame.
func _drop_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.hide_card()
		_card.queue_free()
	_card = null


# The PixelStage whose Hud viewport this overlay is drawn in (null when it is not in one).
func _stage() -> PixelStage:
	if not is_inside_tree():
		return null
	var viewport := get_viewport()
	return viewport.get_parent() as PixelStage if viewport is SubViewport else null


func _exit_tree() -> void:
	_drop_card()


func _typed() -> int:
	return mini(_text.length(), _elapsed * CPS / 60)


# The rows of `text`, as (start, length) in it: each part between line breaks, wrapped.
func _wrap(text: String) -> Array[Vector2i]:
	var rows: Array[Vector2i] = []
	var start := 0
	for part in text.split("\n"):
		rows.append_array(_wrap_part(text, start, start + part.length()))
		start += part.length() + 1
	return rows


# The rows of text[from:to], which has no line break in it.
func _wrap_part(text: String, from: int, to: int) -> Array[Vector2i]:
	var rows: Array[Vector2i] = []
	var width := float(text_rect().size.x)
	var pos := from
	while pos < to:
		while pos < to and text[pos] == " ":
			pos += 1
		if pos >= to:
			break
		var fit := pos  # the furthest end at which text[pos:fit] fits
		var space := -1  # the last space in what fits
		while fit < to and text_width(text.substr(pos, fit + 1 - pos)) <= width:
			fit += 1
			if text[fit - 1] == " ":
				space = fit - 1
		if fit >= to:
			rows.append(Vector2i(pos, to - pos))
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
