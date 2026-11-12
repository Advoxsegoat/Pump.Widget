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
const PANEL_W := 224
const PADDING := 6
const PITCH := 10
## The space between the heading and the rows, and between the rows and the footer.
const GAP := 4
## The lowest the panel may end (the bars start at 335 but the fight's own ground is above this line).
const BOTTOM := 190
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


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	Game.state_changed.connect(_on_state_changed)
	if Game.state == Game.State.PAUSE:
		open()


func _process(delta: float) -> void:
	if not is_open:
		return
	var cmd := nav.tick(delta)
	if cmd != MenuNav.Cmd.NONE:
		press(cmd)
	# A pad picked up or put down changes the footer; values change under their rows: draw what is there now.
	queue_redraw()


## Shows the menu at the root page with its first row selected.
func open() -> void:
	is_open = true
	visible = true
	nav.begin()
	show_page(MenuPages.ROOT)


## Hides the menu.
func close() -> void:
	is_open = false
	visible = false


## Shows the page `id` (built by MenuPages unless `built` is given), with its starting row selected.
func show_page(id: StringName, built: Dictionary = {}) -> void:
	if built.is_empty():
		built = MenuPages.build(id, self)
	page = id
	_heading = built.heading
	_rows = built.rows
	_back = built.back
	index = clampi(built.get("start", 0), 0, maxi(_rows.size() - 1, 0))
	if not _rows.is_empty() and not _rows[index].selectable():
		_move(1)
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
## the selected row, or goes back.
func press(cmd: MenuNav.Cmd) -> void:
	var row := _selected()
	match cmd:
		MenuNav.Cmd.UP:
			_move(-1)
		MenuNav.Cmd.DOWN:
			_move(1)
		MenuNav.Cmd.LEFT, MenuNav.Cmd.RIGHT:
			if row != null and row.enabled and row.on_step.is_valid():
				row.on_step.call(-1 if cmd == MenuNav.Cmd.LEFT else 1)
		MenuNav.Cmd.CHOOSE:
			if row != null and row.enabled and row.on_choose.is_valid():
				row.on_choose.call()
		MenuNav.Cmd.BACK:
			if _back.is_valid():
				_back.call()
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
	var lines := PADDING + PITCH + GAP + PITCH * _rows.size() + GAP + PITCH + PADDING
	return Rect2i(PANEL_X, PANEL_Y, PANEL_W, lines)


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
	for i in _rows.size():
		var row := _rows[i]
		var line := rows_top + PITCH * i
		var value := row.value()
		var wide := ceili(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
		shown.append({
			label = row.label,
			value = value,
			kind = row.kind,
			enabled = row.enabled,
			selected = i == index and row.selectable(),
			rect = Rect2i(left, line, width, PITCH),
			text_at = Vector2i(left + INDENT, line + rise),
			value_at = Vector2i(left + width - wide, line + rise),
			chevron = Rect2i(left, line + (PITCH - CHEVRON_CELLS.size()) / 2, 3, CHEVRON_CELLS.size()),
		})
	return {
		panel = area,
		heading_at = Vector2i(left, top + rise),
		footer_at = Vector2i(left, rows_top + PITCH * _rows.size() + GAP + rise),
		rows = shown,
	}


## What is drawn for each row of the page, as {label, value, kind, enabled, selected, rect, text_at, value_at, chevron}: the
## rect is the row's line, text_at where its label starts, value_at its right-hand text, chevron the cells' box.
func rows() -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	shown.assign(layout().rows)
	return shown


func _selected() -> MenuRow:
	return _rows[index] if index >= 0 and index < _rows.size() else null


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
	for i in _rows.size():
		var shown: Dictionary = map.rows[i]
		var colour := Hud.WHITE
		if _rows[i].kind == MenuRow.Kind.TEXT or not shown.enabled:
			colour = Hud.POSTURE
		if shown.selected:
			colour = Hud.ROSE
		draw_string(font, Vector2(shown.text_at), shown.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
		if not (shown.value as String).is_empty():
			draw_string(font, Vector2(shown.value_at), shown.value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour if shown.selected else Hud.GOLD)
		if shown.selected:
			_draw_chevron((shown.chevron as Rect2i).position)
	draw_string(font, Vector2(map.footer_at), footer(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Hud.POSTURE)


# The selection's chevron: 3 x 5 cells, each a rose pixel.
func _draw_chevron(at: Vector2i) -> void:
	for y in CHEVRON_CELLS.size():
		var line: String = CHEVRON_CELLS[y]
		for x in line.length():
			if line[x] == "X":
				draw_rect(Rect2(at + Vector2i(x, y), Vector2(1, 1)), Hud.ROSE)
