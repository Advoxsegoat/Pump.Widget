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
	_petals_bound()


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
	_draw_petals()
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


# --- Task 3: the petals on the Hud ---
# Top right: the count in the Hud's gold with a rose diamond beside it, and under it, for 90 play frames after a gain, "+n". Where the
# pile lies, a rose diamond (an arrow at the picture's edge when it is out of the picture). Nothing of it covers a fighter's head: the
# popup steps down and the marker steps up until it is clear of every living fighter's head. The count itself stands in the corner,
# where no one fights (the camera keeps Abarax in the middle).

## A head is this many picture pixels round its point (look_height above the feet): nothing of the petals is drawn over it.
const HEAD_RADIUS := 10
## The count's and the popup's font size, in the Hud's own plain font, and where the count stands: its right edge, its top and height.
const COUNT_FONT_SIZE := 10
const COUNT_RIGHT := 10
const COUNT_TOP := 6
const COUNT_HEIGHT := 14
## The marker of the pile and the popup stay this far inside the picture's edges.
const INSET := 6
## An arrow (a pile out of the picture) is this long from its tip to its back and this wide across, in picture pixels, with a one pixel
## dark edge; its middle stands this far inside the picture's edges, so that all of it, edge included, is inside.
const ARROW_LENGTH := 12.0
const ARROW_WIDTH := 12.0
const ARROW_INSET := 12
## The popup shows this many play frames after a gain (a pause does not count).
const POPUP_FRAMES := 90
## The marker (a rose diamond of 5 x 5 on an ink one of 7 x 7) and how far above the pile's foot it hangs, in metres.
const MARKER_RADIUS := 2
const MARKER_ABOVE := 0.8
## A marker or popup that would cover a head moves by these steps, this many at most.
const CLEAR_STEP := 12
const CLEAR_TRIES := 8

var _popup_amount := 0
var _popup_until := -1  # Game.play_frames at which it goes


# Listens to the petals (called by `bind`).
func _petals_bound() -> void:
	if run != null and run.petals != null:
		run.petals.gained.connect(_on_petals_won)
		run.petals.taken.connect(_on_petals_won)


func _on_petals_won(amount: int) -> void:
	_popup_amount = (_popup_amount if Game.play_frames < _popup_until else 0) + amount
	_popup_until = Game.play_frames + POPUP_FRAMES


## The carried count as a plain number ("" with no run).
func petal_text() -> String:
	if run == null or not is_instance_valid(run) or run.petals == null:
		return ""
	return str(run.petals.carried())


## "+<n>" for 90 play frames after petals came to him (gains in that time add up), else "".
func gain_popup() -> String:
	if _popup_amount > 0 and Game.play_frames < _popup_until:
		return "+%d" % _popup_amount
	return ""


## The pile's marker: `{}` with no pile; else `{point: Vector2i, arrow: bool, dir: Vector2}`: the picture point of the pile (a hand's breadth
## above its foot) when it is inside the picture inset by INSET pixels, else that point put on the inset's edge with `arrow` true and
## `dir` the way it lies from the middle of the picture. The point steps up clear of any head.
func pile_marker() -> Dictionary:
	if run == null or not is_instance_valid(run) or run.petals == null or hud == null or not is_instance_valid(hud):
		return {}
	var at: Variant = run.petals.pile_at()
	if at == null:
		return {}
	var p := hud.picture_point((at as Vector3) + Vector3.UP * MARKER_ABOVE)
	var low := Vector2(INSET, INSET)
	var high := Hud.PICTURE - low
	var inside := p.x >= low.x and p.x <= high.x and p.y >= low.y and p.y <= high.y
	if not inside:
		low = Vector2(ARROW_INSET, ARROW_INSET)
		high = Hud.PICTURE - low
	var shown := p.clamp(low, high)
	var dir := Vector2.ZERO if inside else (p - Hud.PICTURE / 2.0).normalized()
	var heads := _heads()
	var half := MARKER_RADIUS + 1 if inside else int(ARROW_LENGTH / 2.0) + 1
	for i in CLEAR_TRIES + 1:
		var tried := shown + _marker_step(inside, shown, i)
		tried = tried.clamp(low, high)
		if not _hits_a_head(Rect2(tried - Vector2.ONE * half, Vector2.ONE * (2.0 * half + 1.0)), heads):
			shown = tried
			break
	return {point = Vector2i(shown), arrow = not inside, dir = dir}


# The i'th step of a marker looking for a place clear of heads: up from the pile on the picture; along the edge when it is on one.
func _marker_step(inside: bool, from: Vector2, i: int) -> Vector2:
	if inside:
		return Vector2(0.0, -float(CLEAR_STEP * i))
	var on_side := from.x <= ARROW_INSET or from.x >= Hud.PICTURE.x - ARROW_INSET
	return Vector2(0.0, float(CLEAR_STEP * i)) if on_side else Vector2(float(CLEAR_STEP * i), 0.0)


## Where the count stands: the diamond and the number, at the top right.
func count_rect() -> Rect2:
	var width := float(_text_width(petal_text()) + 8)
	return Rect2(Hud.PICTURE.x - COUNT_RIGHT - width, COUNT_TOP, width, COUNT_HEIGHT)


## Where the popup stands (under the count, its right edge on the count's, stepped down clear of any head); an empty rectangle with none.
func popup_rect() -> Rect2:
	var text := gain_popup()
	if text.is_empty():
		return Rect2()
	var width := float(_text_width(text))
	var count := count_rect()
	var base := Rect2(count.end.x - width, count.end.y + 1.0, width, COUNT_HEIGHT)
	var heads := _heads()
	for i in CLEAR_TRIES + 1:
		var moved := Rect2(base.position + Vector2(0.0, float(CLEAR_STEP * i)), base.size)
		if not _hits_a_head(moved, heads):
			return moved
	return base


## Whether the petals draw anything now: the Hud is shown at all.
func draws_petals() -> bool:
	return hud != null and is_instance_valid(hud) and hud.shown_alpha() > 0.0 and run != null and is_instance_valid(run) and run.petals != null


func _text_width(text: String) -> int:
	return ceili(ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE).x)


# The picture points of the heads of every fighter standing (a body on the ground has none to cover).
func _heads() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor == null or actor.dead or actor.def == null or not actor.is_inside_tree() or not actor.visible:
			continue
		out.append(hud.picture_point(actor.get_global_transform_interpolated().origin + Vector3.UP * actor.def.look_height))
	return out


# Whether `rect` is within a hand's breadth of a head's square.
func _hits_a_head(rect: Rect2, heads: Array[Vector2]) -> bool:
	var grown := rect.grow(3.0)
	for head in heads:
		if grown.intersects(Rect2(head - Vector2.ONE * HEAD_RADIUS, Vector2.ONE * 2.0 * HEAD_RADIUS)):
			return true
	return false


func _draw_petals() -> void:
	if not draws_petals():
		return
	var alpha := hud.shown_alpha()
	var font := ThemeDB.fallback_font
	var ink := Hud.INK
	ink.a *= alpha
	var gold := Hud.GOLD
	gold.a *= alpha
	var rose := Hud.ROSE
	rose.a *= alpha
	var count := count_rect()
	var text := petal_text()
	var baseline := Vector2(count.end.x - float(_text_width(text)), count.position.y + float(COUNT_HEIGHT) - 3.0)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, 3, ink)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, gold)
	_diamond(Vector2i(int(count.position.x) + 2, int(count.position.y) + COUNT_HEIGHT / 2), MARKER_RADIUS, rose, ink)
	var popup := gain_popup()
	if not popup.is_empty():
		var at := popup_rect()
		var line := Vector2(at.position.x, at.position.y + float(COUNT_HEIGHT) - 3.0)
		draw_string_outline(font, line, popup, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, 3, ink)
		draw_string(font, line, popup, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, Color(Hud.WHITE.r, Hud.WHITE.g, Hud.WHITE.b, alpha))
	var marker := pile_marker()
	if marker.is_empty():
		return
	if marker.arrow:
		var dir: Vector2 = marker.dir
		var centre := Vector2(marker.point)
		draw_colored_polygon(arrow_points(centre, dir, 0.0), ink)
		draw_colored_polygon(arrow_points(centre, dir, 1.0), rose)
	else:
		_diamond(marker.point, MARKER_RADIUS, rose, ink)


## The three corners of the arrow at `centre` pointing along `dir`, drawn `shrink` picture pixels smaller all round (0 is the dark edge, 1 the
## rose inside it).
static func arrow_points(centre: Vector2, dir: Vector2, shrink: float) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x)
	var tip := ARROW_LENGTH * 0.6 - shrink * 1.6
	var back := ARROW_LENGTH * 0.4 - shrink * 1.2
	var half := ARROW_WIDTH / 2.0 - shrink * 1.8
	return PackedVector2Array([centre + dir * tip, centre - dir * back + side * half, centre - dir * back - side * half])


# A filled diamond of radius `r` over an ink one a pixel larger.
func _diamond(centre: Vector2i, r: int, color: Color, ink: Color) -> void:
	for pass_radius: int in [r + 1, r]:
		for dy in range(-pass_radius, pass_radius + 1):
			var half: int = pass_radius - absi(dy)
			draw_rect(Rect2(centre.x - half, centre.y + dy, 2 * half + 1, 1), ink if pass_radius > r else color)
