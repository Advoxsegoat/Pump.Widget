class_name Menu
extends Control
## The menu, drawn in the Hud's own picture (the PixelStage's Hud viewport: exactly 640x360, shown at a whole-number scale),
## beside the Hud. Any move into Game.State.PAUSE opens it at the root page, and any move out of PAUSE closes it. It runs
## while the tree is paused, takes what Main gives it (handle) and moves by MenuNav's fixed commands, so rebinding the game's
## buttons can never lock the player out of it.
##
## It is a column on the left (PANEL_X, PANEL_Y, PANEL_W), left of the picture's centre where Abarax stands, clear of the wave pips
## at the top and the bars at the bottom left, and nothing outside it is dimmed: the frozen fight stays as readable as it was.
## Everything in it is at a whole picture pixel; layout() says where, in picture pixels, and the drawing and the tests use it.
## The look is the Hud's: its font at its size, its colours.

## Asked to quit (the Quit row of the page that asks first). Main ends the game.
signal quit_requested

## The panel: its left and top, width, and the padding inside it, and the pitch of its lines.
const PANEL_X := 8
const PANEL_Y := 8
const PANEL_W := 224  # the widest the panel gets; it is as wide as its page needs, up to this
const PADDING := 6
const PITCH := 10
## The space between the heading and the rows, and between the rows and the footer.
const GAP := 4
## The lowest the panel may end. A page with more rows than fit above it scrolls (CAPACITY rows show).
const BOTTOM := 190
const CAPACITY := (BOTTOM - PANEL_Y - 2 * PADDING - PITCH - 2 * GAP - PITCH) / PITCH
## Room kept at the right of a scrolling page for its arrows (5 px wide), and the space between a label and its value.
const ARROW_ROOM := 8
const VALUE_GAP := 8
## A slider's bar: its outline is 1 px around the BAR_PIXELS wide, 3 px high inside; BAR_GAP is the space between the bar and the percent.
const BAR_OUTER := Vector2i(MenuRow.BAR_PIXELS + 2, 5)
const BAR_GAP := 4
const BAR_TRACK := Color(0.81, 0.85, 0.94, 0.3)  # the empty part of the bar: Hud.POSTURE, faint
## The widest percent, which every slider's bar is placed by so that the bars of a page line up.
const WIDEST_PERCENT := "100%"
## The least time, in seconds of the menu's own clock (it counts while the game is paused), between two sound samples.
## A row that is switched off is Hud.POSTURE at this strength: the cool white alone is too near the live rows' warm white to tell.
const DIM_ALPHA := 0.55
const SAMPLE_GAP := 0.15
const ARROW_UP_CELLS := ["..X..", ".XXX.", "XXXXX"]
const ARROW_DOWN_CELLS := ["XXXXX", ".XXX.", "..X.."]
const FONT_SIZE := Hud.HINT_FONT_SIZE
## Room left of a label for the selection's chevron, which is 3 x 5 cells (an X is a cell).
const INDENT := 6
const CHEVRON_CELLS := ["X..", ".X.", "..X", ".X.", "X.."]
const FOOTER_KEYBOARD := "Enter: choose   Esc: back"
const FOOTER_PAD := "A: choose   B: back"

## The window F11 switches (Main sets it): the settings page's window rows act on it.
var window: Window
## Whether the game runs on a web page, which owns the window and the quitting.
var web: bool = Settings.on_web
## What the window rows ask the screen's size from (a test gives its own).
var screen_size: Callable = func() -> Vector2i: return DisplayServer.screen_get_usable_rect().size
## The menu's own player of the sound rows' samples, and how many it has started.
var sample_player: AudioStreamPlayer = null
var sample_count := 0
## The page shown (MenuPages), the selected row of it, and whether the menu is up.
var page: StringName = MenuPages.ROOT
var index := 0
var is_open := false
## What the player's hands mean here.
var nav := MenuNav.new()
## Says whether a pad is connected; only a test replaces it.
var pad_present: Callable = func() -> bool: return not Input.get_connected_joypads().is_empty()

var _heading := ""
var _rows: Array[MenuRow] = []
var _back: Callable = Callable()
var _footer_seen := ""
var _top := 0  # the first row shown (a page with more rows than fit scrolls)
var _width := PANEL_W  # the panel's width: what the page needs, fixed while it is open
var _trail: Array[Dictionary] = []  # the pages opened from others: {from, index, to}
var _since_sample := SAMPLE_GAP  # seconds since the last sample, on the menu's own clock


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	sample_player = AudioStreamPlayer.new()
	sample_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sample_player)


func _ready() -> void:
	Game.state_changed.connect(_on_state_changed)
	if Game.state == Game.State.PAUSE:
		open()


func _process(delta: float) -> void:
	_since_sample += delta
	if not is_open:
		return
	refresh()
	var cmd := nav.tick(delta)
	if cmd != MenuNav.Cmd.NONE:
		press(cmd, true)
	# A pad picked up or put down changes the footer; values change under their rows: draw what is there now.
	queue_redraw()


## Shows the menu at the root page with its first row selected.
func open() -> void:
	is_open = true
	visible = true
	_trail.clear()
	nav.begin()
	show_page(MenuPages.ROOT)


## Opens the page `id` from the page shown, to come back to: pop_page returns here with this row selected.
func push_page(id: StringName) -> void:
	_trail.append({from = page, index = index, to = id})
	show_page(id)


## Goes back from the page shown to the page it was opened from, on the row it was opened with (or, for a page shown directly, the
## page it belongs under).
func pop_page() -> void:
	var target := MenuPages.parent_of(page)
	var start := 0
	if not _trail.is_empty() and _trail.back().to == page:
		var entry: Dictionary = _trail.pop_back()
		target = entry.from
		start = entry.index
	var built := MenuPages.build(target, self)
	built.start = start
	show_page(target, built)


## Asks every row whether it is enabled now, and moves the selection off a row that has gone dim (so a chevron is always shown). Called
## each frame, and by press and show_page.
func refresh() -> void:
	for row in _rows:
		if row.enabled_when.is_valid():
			row.enabled = row.enabled_when.call()
	if not _rows.is_empty() and not _rows[index].selectable():
		_move(-1)


## Plays the cue `cue` on `bus` through the menu's own player, so that a sound row's step can be heard while the game is paused: at most
## one in SAMPLE_GAP seconds, and none when the row's own level (`key`) or the master level is 0. The level is the bus's, already set.
func play_sample(cue: StringName, bus: StringName, key: String) -> void:
	if _since_sample < SAMPLE_GAP or Settings.get_value("sound/master") == 0 or Settings.get_value(key) == 0:
		return
	if not Registry.ids(&"sounds").has(String(cue)):
		return
	var sound := Registry.fetch(&"sounds", cue) as SoundCue
	if sound == null or sound.streams.is_empty():
		return
	_since_sample = 0.0
	sample_count += 1
	sample_player.stream = sound.streams[0]
	sample_player.bus = bus
	sample_player.volume_db = sound.volume_db
	sample_player.play()


## Hides the menu.
func close() -> void:
	is_open = false
	visible = false
	sample_player.stop()  # a sample started a moment ago must not play on into the fight


## Shows the page `id` (built by MenuPages unless `built` is given), with its starting row selected.
func show_page(id: StringName, built: MenuPage = null) -> void:
	if built == null:
		built = MenuPages.build(id, self)
	page = id
	_heading = built.heading
	_rows = built.rows
	_back = built.back
	index = clampi(built.start, 0, maxi(_rows.size() - 1, 0))
	for row in _rows:
		if row.enabled_when.is_valid():
			row.enabled = row.enabled_when.call()
	if not _rows.is_empty() and not _rows[index].selectable():
		_move(1)
	_top = 0
	_scroll_to_selection()
	_width = _fit_width()
	queue_redraw()


## What the menu does with `event`: true when it took it. Main hands it everything but the window toggle and F3 while the game
## is paused, and the menu takes all of it (a mouse click, a key it does not use), so that nothing reaches the fight behind it.
func handle(event: InputEvent) -> bool:
	if not is_open:
		return false
	var cmd := nav.command(event)
	if cmd != MenuNav.Cmd.NONE:
		press(cmd)
	return true


## Does what the command `cmd` means on the page shown: moves the selection (it wraps, and skips text), adjusts or chooses
## the selected row, or goes back. A `repeat` is a held direction coming round again: it moves the selection and steps a slider,
## but never flips a switch, a choice (the window's Mode and Size act at once) or anything else that a fresh press means.
func press(cmd: MenuNav.Cmd, repeat := false) -> void:
	var row := _selected()
	match cmd:
		MenuNav.Cmd.UP:
			_move(-1)
		MenuNav.Cmd.DOWN:
			_move(1)
		MenuNav.Cmd.LEFT, MenuNav.Cmd.RIGHT:
			if row != null and row.enabled and row.on_step.is_valid() and (not repeat or row.kind == MenuRow.Kind.SLIDER):
				row.on_step.call(-1 if cmd == MenuNav.Cmd.LEFT else 1)
		MenuNav.Cmd.CHOOSE:
			if row != null and row.enabled and row.on_choose.is_valid():
				row.on_choose.call()
		MenuNav.Cmd.BACK:
			if _back.is_valid():
				_back.call()
	refresh()
	queue_redraw()


## The heading of the page shown.
func heading() -> String:
	return _heading


## The footer line: the keys for the keyboard, or the buttons when a pad is in hand (and connected).
func footer() -> String:
	var pad: bool = Inputs.last_device() == Inputs.Device.GAMEPAD and pad_present.call()
	return FOOTER_PAD if pad else FOOTER_KEYBOARD


## The panel, in picture pixels.
func panel() -> Rect2i:
	var lines := PADDING + PITCH + GAP + PITCH * mini(_rows.size(), CAPACITY) + GAP + PITCH + PADDING
	return Rect2i(PANEL_X, PANEL_Y, _width, lines)


## Where the page's parts are, in whole picture pixels: {panel, heading_at, footer_at, chevron_size, rows}, `rows` as rows() gives
## them. A text position is where the text's baseline starts (what draw_string takes).
func layout() -> Dictionary:
	var font := ThemeDB.fallback_font
	var area := panel()
	var left := area.position.x + PADDING
	var width := area.size.x - 2 * PADDING
	var top := area.position.y + PADDING
	var rise := roundi(font.get_ascent(FONT_SIZE)) + maxi(0, (PITCH - roundi(font.get_height(FONT_SIZE))) / 2)
	var rows_top := top + PITCH + GAP
	var shown: Array[Dictionary] = []
	var last := mini(_top + CAPACITY, _rows.size())
	for i in range(_top, last):
		var row := _rows[i]
		var line := rows_top + PITCH * (i - _top)
		var value := row.value()
		var wide := ceili(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
		var bar := Rect2i()
		if row.has_bar():
			bar = Rect2i(Vector2i(left + width - _text_width(WIDEST_PERCENT) - BAR_GAP - BAR_OUTER.x, line + (PITCH - BAR_OUTER.y) / 2), BAR_OUTER)
		shown.append({
			index = i,
			label = row.label,
			value = value,
			kind = row.kind,
			bar = bar,
			fill = row.fill(),
			enabled = row.enabled,
			selected = i == index and row.selectable(),
			colour = _colour_of(row, i == index and row.selectable()),
			rect = Rect2i(left, line, width, PITCH),
			text_at = Vector2i(left + INDENT, line + rise),
			value_at = Vector2i(left + width - wide, line + rise),
			chevron = Rect2i(left, line + (PITCH - CHEVRON_CELLS.size()) / 2, 3, CHEVRON_CELLS.size()),
		})
	var arrow_x := area.end.x - PADDING - 5
	return {
		panel = area,
		heading_at = Vector2i(left, top + rise),
		footer_at = Vector2i(left, rows_top + PITCH * (last - _top) + GAP + rise),
		rows = shown,
		arrow_up = Rect2i(arrow_x, top + 3, 5, 3) if _top > 0 else Rect2i(),
		arrow_down = Rect2i(arrow_x, area.end.y - PADDING - 7, 5, 3) if last < _rows.size() else Rect2i(),
	}


## What is drawn for each row of the page shown, as {index (in the page), label, value, kind, enabled, selected, colour (the label's), rect, text_at, value_at, chevron, bar, fill}: the
## rect is the row's line, text_at where its label starts, value_at its right-hand text, chevron the cells' box.
func rows() -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	shown.assign(layout().rows)
	return shown


# The colour a row's label is drawn in: rose when selected, warm white when live, and the dim note colour for a row switched off and
# for a line of words (which is not a row, and must not read as one).
func _colour_of(row: MenuRow, selected: bool) -> Color:
	if selected:
		return Hud.ROSE
	if row.kind == MenuRow.Kind.TEXT or not row.enabled:
		return Color(Hud.POSTURE, DIM_ALPHA)
	return Hud.WHITE


func _selected() -> MenuRow:
	return _rows[index] if index >= 0 and index < _rows.size() and _rows[index].selectable() else null


# The panel's width: the heading, the rows (label, a gap and the value as it is now) and both footers, each as wide as it is, plus
# the padding, and room for the arrows on a scrolling page; never more than PANEL_W.
func _fit_width() -> int:
	var widest := _text_width(_heading)
	for row in _rows:
		var wide := INDENT + _text_width(row.label)
		var room := _value_room(row)
		if room > 0:
			wide += VALUE_GAP + room
		widest = maxi(widest, wide)
	widest = maxi(widest, maxi(_text_width(FOOTER_KEYBOARD), _text_width(FOOTER_PAD)))
	if _rows.size() > CAPACITY:
		widest += ARROW_ROOM
	return mini(widest + 2 * PADDING, PANEL_W)


# The room a row's right-hand side needs: the widest text the row can ever show (not just the one it shows now), and for a slider
# its bar and the widest percent, since the width is fixed while the page is open.
func _value_room(row: MenuRow) -> int:
	var texts: Array = [row.value()]
	if row.all_values.is_valid():
		texts.append_array(row.all_values.call())
	var room := 0
	for text: String in texts:
		room = maxi(room, _text_width(text))
	if row.has_bar():
		room = maxi(room, _text_width(WIDEST_PERCENT)) + BAR_GAP + BAR_OUTER.x
	return room


func _text_width(text: String) -> int:
	return ceili(ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)


# The window of rows follows the selection: it moves one row when the selection passes its edge.
func _scroll_to_selection() -> void:
	if index < _top:
		_top = index
	elif index >= _top + CAPACITY:
		_top = index - CAPACITY + 1
	_top = clampi(_top, 0, maxi(_rows.size() - CAPACITY, 0))


# The selection moves `step` (-1 or 1) rows, wrapping and skipping rows that are only text.
func _move(step: int) -> void:
	var count := _rows.size()
	if count == 0:
		return
	var at := index
	for i in count:
		at = posmod(at + step, count)
		if _rows[at].selectable():
			index = at
			_scroll_to_selection()
			return


func _on_state_changed(from: Game.State, to: Game.State) -> void:
	if to == Game.State.PAUSE:
		open()
	elif from == Game.State.PAUSE:
		close()


# --- drawing ---

func _draw() -> void:
	if not is_open:
		return
	var font := ThemeDB.fallback_font
	var map := layout()
	var area: Rect2i = map.panel
	draw_rect(Rect2(area), Hud.INK)
	for edge in [Rect2i(area.position, Vector2i(area.size.x, 1)), Rect2i(area.position + Vector2i(0, area.size.y - 1), Vector2i(area.size.x, 1)),
			Rect2i(area.position, Vector2i(1, area.size.y)), Rect2i(area.position + Vector2i(area.size.x - 1, 0), Vector2i(1, area.size.y))]:
		draw_rect(Rect2(edge), Hud.GOLD)
	draw_string(font, Vector2(map.heading_at), _heading, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Hud.GOLD)
	for shown: Dictionary in map.rows:
		var colour: Color = shown.colour
		draw_string(font, Vector2(shown.text_at), shown.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
		if not (shown.value as String).is_empty():
			var value_colour := colour if shown.selected or not shown.enabled else Hud.GOLD
			draw_string(font, Vector2(shown.value_at), shown.value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, value_colour)
		if (shown.bar as Rect2i).size != Vector2i.ZERO:
			_draw_bar(shown.bar, shown.fill, shown.enabled)
		if shown.selected:
			_draw_chevron((shown.chevron as Rect2i).position)
	draw_string(font, Vector2(map.footer_at), footer(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Hud.POSTURE)
	_draw_arrow((map.arrow_up as Rect2i).position, ARROW_UP_CELLS, map.arrow_up.size != Vector2i.ZERO)
	_draw_arrow((map.arrow_down as Rect2i).position, ARROW_DOWN_CELLS, map.arrow_down.size != Vector2i.ZERO)


# A slider's bar: its empty track, the gold fill (a dim one if the row is off) from the left, and the 1 px outline of the Hud's ink.
func _draw_bar(outer: Rect2i, fill: int, enabled: bool) -> void:
	var inside := Rect2i(outer.position + Vector2i(1, 1), outer.size - Vector2i(2, 2))
	draw_rect(Rect2(inside), BAR_TRACK)
	if fill > 0:
		draw_rect(Rect2(inside.position, Vector2i(fill, inside.size.y)), Hud.GOLD if enabled else Color(Hud.POSTURE, DIM_ALPHA))
	for edge in [Rect2i(outer.position, Vector2i(outer.size.x, 1)), Rect2i(outer.position + Vector2i(0, outer.size.y - 1), Vector2i(outer.size.x, 1)),
			Rect2i(outer.position, Vector2i(1, outer.size.y)), Rect2i(outer.position + Vector2i(outer.size.x - 1, 0), Vector2i(1, outer.size.y))]:
		draw_rect(Rect2(edge), Hud.INK)


# A small gold arrow of 5 x 3 cells where rows are hidden.
func _draw_arrow(at: Vector2i, cells: Array, shown: bool) -> void:
	if not shown:
		return
	for y in cells.size():
		var line: String = cells[y]
		for x in line.length():
			if line[x] == "X":
				draw_rect(Rect2(at + Vector2i(x, y), Vector2(1, 1)), Hud.GOLD)


# The selection's chevron: 3 x 5 cells, each a rose pixel.
func _draw_chevron(at: Vector2i) -> void:
	for y in CHEVRON_CELLS.size():
		var line: String = CHEVRON_CELLS[y]
		for x in line.length():
			if line[x] == "X":
				draw_rect(Rect2(at + Vector2i(x, y), Vector2(1, 1)), Hud.ROSE)
