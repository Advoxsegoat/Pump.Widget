class_name StretchHud
extends Control
## The stretch's line on the Hud: what the interact button would do right now ("F  Rest"), at the bottom centre of the picture, in
## the Hud's own plain font with its ink outline. A child of the Hud, made when the stretch is entered and gone when it is left.
## It draws only when the Hud does (not while a scene has taken the picture), and fades with it.

## Where the line stands: its baseline this far above the picture's bottom edge.
const LINE_ABOVE := 24

var run: StretchRun
var hud: Hud


## Gives it the Hud it draws for and the run it asks.
func bind(parent_hud: Hud, stretch_run: StretchRun) -> void:
	hud = parent_hud
	run = stretch_run
	name = &"StretchHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Hud.PICTURE


## The interactor's line, "" with nothing in reach.
func prompt_line() -> String:
	if run == null or not is_instance_valid(run) or run.interactor == null:
		return ""
	return run.interactor.prompt_line()


## Whether it draws anything now: the Hud is shown at all and there is a line.
func draws() -> bool:
	return hud != null and is_instance_valid(hud) and hud.shown_alpha() > 0.0 and not prompt_line().is_empty()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not draws():
		return
	var alpha := hud.shown_alpha()
	var line := prompt_line()
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, Hud.HINT_FONT_SIZE).x
	var at := Vector2(roundf((Hud.PICTURE.x - width) / 2.0), Hud.PICTURE.y - LINE_ABOVE)
	var ink := Hud.INK
	ink.a *= alpha
	var white := Hud.WHITE
	white.a *= alpha
	draw_string_outline(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, Hud.HINT_FONT_SIZE, 3, ink)
	draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, Hud.HINT_FONT_SIZE, white)
