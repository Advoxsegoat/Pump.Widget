class_name Hud
extends Control
## The heads-up display, drawn in the PixelStage's `hud` viewport: exactly the 640x360 picture, transparent, shown over the
## world at the same whole-number scale, with no grade and no sub-pixel shift (PixelStage). Everything here is drawn in
## whole picture pixels, so it is as crisp as the pixels under it.
##
## It draws:
##   - the player's bars, bottom left: HP in rose and stamina in gold below it, 1 px per point up to MAX_BAR px, and a thin
##     posture bar above HP, shown only while it is not full. The stamina bar blinks twice (2 frames lit, 2 not) when a press
##     was refused for lack of stamina (Actor.move_refused)
##   - a foe's posture and HP bars (24 px) over its head while it is locked on, or for 3 s after a blow reached it
##   - the lock reticle, a 5x5 rose diamond at the head of the foe locked on to
##   - the finisher prompt, a 7x7 rose glyph over the foe the player's palm would finish now (Actor.finishable_target)
##   - the unblockable icon over the head of an enemy giving a perilous attack its tell (ActorFx.icon_shape): a 9x9 rose
##     glyph with a 1 px dark outline, one shape for each answer (a sweep: hop it; a thrust: catch it; a grab: sway or duck it),
##     drawn from the tell to the blow's last hitbox_off, its bottom at least 4 px above the head point, never over the
##     body (spec 3.5)
##   - the wave as pips, top centre
##   - the controls, bottom right, for the first 8 s and again whenever F1 (a pad's Select) toggles them
## Where something stands in the world is projected by the stage's camera, to the pixel the world is drawn at (the stage's
## sub-pixel shift included), and rounded to a whole picture pixel.
##
## The queries (hp_rect, reticle_at, ...) say what is drawn, in picture pixels, so that the tests and the drawing agree.

## The picture the HUD is drawn in.
const PICTURE := Vector2(PixelSnap.INTERNAL)
const ROSE := Color("e8607e")
const GOLD := Color("e8c170")
const POSTURE := Color("cfd9f0")
const INK := Color(0.07, 0.04, 0.09, 0.9)
const WHITE := Color("fff3d6")
## Where the player's bars start (left edge) and how long the longest is.
const LEFT := 10
const MAX_BAR := 120
## The bars' rows: stamina, then HP above it, then posture above that, each as {y, height}.
const STAMINA_ROW := Vector2i(346, 4)
const HP_ROW := Vector2i(339, 5)
const POSTURE_ROW := Vector2i(335, 2)
## The finisher prompt's glyph is this many pixels square.
const PROMPT_SIZE := 7
## A foe's bars: this wide, the HP and posture rows' heights, and how far above its head point the HP bar's bottom is.
const FOE_BAR := 24
const FOE_HP_HEIGHT := 3
const FOE_POSTURE_HEIGHT := 2
const FOE_ABOVE := 12
## A foe shows its bars this many physics frames after a blow reached it (3 s).
const FOE_SHOWN_FRAMES := 180
## The stamina bar's blink at a refused press: lit and then dark, this many times, over ActorFx.REFUSAL_FRAMES physics
## frames in all (2 frames lit and 2 dark, twice). That one number is also how seldom a refused press starts the blink,
## and sounds (ActorFx): a blink is never cut short by the next.
const BLINKS := 2
@warning_ignore("integer_division")
const BLINK_FRAMES := ActorFx.REFUSAL_FRAMES / (2 * BLINKS)
## The wave pips: each this square, this far apart, this far from the top.
const PIP := 5
const PIP_GAP := 3
const PIP_TOP := 8
## The controls list is shown this many seconds at the start.
const HINT_SECONDS := 8.0
const HINT_FONT_SIZE := 8
const HINT_MARGIN := 6
## The wave pips' states, as pip_states() gives them.
enum Pip { COMING, ON, CLEARED }
## The unblockable icon of each answer, as 9 rows of 9 cells, an X where the glyph is drawn: a sweep is an upward chevron
## over a low bar (hop it), a thrust a point between two brackets (catch it), a grab a body leaning off a line (lean out of its way: sway or duck it).
const ICON_CELLS := {
	HitProfile.Perilous.SWEEP: [
		"....X....",
		"...XXX...",
		"..XX.XX..",
		".XX...XX.",
		"XX.....XX",
		".........",
		".........",
		"XXXXXXXXX",
		"XXXXXXXXX",
	],
	HitProfile.Perilous.THRUST: [
		"XX.....XX",
		"X.......X",
		"X.XXXXX.X",
		"X..XXX..X",
		"X...X...X",
		"X.......X",
		"X.......X",
		"X.......X",
		"XX.....XX",
	],
	HitProfile.Perilous.GRAB: [
		"X....XX..",
		"X....XX..",
		"X...XXX..",
		"X..XXXXX.",
		"X..XXX...",
		"X.XXX....",
		"X.XX.X...",
		"X.X...X..",
		"X........",
	],
}

var player: Actor
var camera_rig: CameraRig
var stage: PixelStage
var arena: Arena
## Whether the controls are shown now.
var hints_visible := true
## True while a scene plays: the HUD draws nothing (the Director's CineOverlay has the picture).
var suppressed := false

var _hint_left := HINT_SECONDS
var _hints_pinned := false  # F1 was pressed: the timer no longer hides them
var _refused_at := -1000  # the physics frame the latest refused press was on
var _hit_at := {}  # foe (Actor) -> the physics frame a blow last reached it
var _watching := {}  # foes whose got_hit is connected (Actor -> true)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Gives the HUD what it shows: the player, the camera (which projects the world onto the picture and tells the lock), the
## stage (whose sub-pixel shift the projection follows) and, if there is one, the arena whose waves are the pips.
func bind(who: Actor, rig: CameraRig, pixel_stage: PixelStage, fight: Arena = null) -> void:
	if player != null and player.move_refused.is_connected(_on_refused):
		player.move_refused.disconnect(_on_refused)
	player = who
	camera_rig = rig
	stage = pixel_stage
	arena = fight
	player.move_refused.connect(_on_refused)


func _process(delta: float) -> void:
	advance(delta)
	_watch_foes()
	queue_redraw()


## Counts the controls list's timer by `delta` seconds: it hides itself after HINT_SECONDS unless F1 has been pressed.
func advance(delta: float) -> void:
	if _hints_pinned:
		return
	_hint_left -= delta
	if _hint_left <= 0.0:
		hints_visible = false


## F1 (a pad's Select): shows or hides the controls, for good.
func toggle_hints() -> void:
	_hints_pinned = true
	hints_visible = not hints_visible


# --- what is drawn (picture pixels) ---

## The fill of the player's HP bar: 1 px per HP up to MAX_BAR (the whole bar is that long, the fill is what is left).
func hp_rect() -> Rect2i:
	return _bar(HP_ROW, player.stats.hp, player.stats.max_hp)


## The fill of the stamina bar.
func stamina_rect() -> Rect2i:
	return _bar(STAMINA_ROW, player.stats.stamina, player.stats.max_stamina)


## The fill of the posture bar, thin, above HP: empty while posture is full (it shows only when it is not).
func posture_rect() -> Rect2i:
	if player.stats.posture >= player.stats.max_posture:
		return Rect2i()
	return _bar(POSTURE_ROW, player.stats.posture, player.stats.max_posture)


## Whether the stamina bar is lit by a refused press: lit for BLINK_FRAMES physics frames, dark for as many, BLINKS times,
## counted from the frame the press was refused on.
func stamina_blink_on() -> bool:
	var since := Engine.get_physics_frames() - _refused_at
	return since >= 0 and since < ActorFx.REFUSAL_FRAMES and (since / BLINK_FRAMES) % 2 == 0


## The foes whose bars show now (locked on, or hit in the last FOE_SHOWN_FRAMES) as {actor, hp, posture}: the two fills in
## picture pixels, the posture bar over the HP bar, both over the head.
func foe_bars() -> Array[Dictionary]:
	return _bars(icons(), _finishing())


# foe_bars, given the icons and the foe the palm would finish that this frame has found already (a draw finds them once).
func _bars(icons_now: Array[Dictionary], finishing: Actor) -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	if player == null or camera_rig == null:
		return shown
	var locked := _locked()
	var now := Engine.get_physics_frames()
	# The bars sit above whatever stands over a head: an unblockable icon, or the finisher prompt.
	var raised := {}
	for icon in icons_now:
		raised[icon.actor] = (icon.rect as Rect2i).size.y + 3
	if finishing != null:
		raised[finishing] = PROMPT_SIZE + 3
	for node in get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		var foe := node as Actor
		if foe == null or foe.dead or foe.stats == null or not foe.is_inside_tree():
			continue
		_watch(foe)
		if foe != locked and now - int(_hit_at.get(foe, -FOE_SHOWN_FRAMES * 2)) > FOE_SHOWN_FRAMES:
			continue
		var head := picture_point(_head(foe))
		var x := int(head.x) - FOE_BAR / 2
		var hp_y := int(head.y) - FOE_ABOVE - FOE_HP_HEIGHT - int(raised.get(foe, 0))
		shown.append({
			actor = foe,
			hp = Rect2i(x, hp_y, ceili(FOE_BAR * foe.stats.hp / foe.stats.max_hp), FOE_HP_HEIGHT),
			posture = Rect2i(x, hp_y - 1 - FOE_POSTURE_HEIGHT, ceili(FOE_BAR * foe.stats.posture / foe.stats.max_posture), FOE_POSTURE_HEIGHT),
		})
	return shown


## Where the lock reticle is, the picture pixel at the head of the foe locked on to; null while nothing is locked.
func reticle_at() -> Variant:
	var target := _locked()
	if target == null or camera_rig == null:
		return null
	return Vector2i(picture_point(_head(target)))


## Where the finisher prompt is (the centre of its 7x7 glyph, over the head of the foe the player's palm would finish now);
## null when there is no such foe in reach.
func prompt_at() -> Variant:
	return _prompt_over(_finishing())


# The foe the player's palm would finish now, or null (none, or no camera to place it, or he is dead).
func _finishing() -> Actor:
	if player == null or camera_rig == null or player.dead:
		return null
	return player.finishable_target()


func _prompt_over(foe: Actor) -> Variant:
	return null if foe == null else glyph_centre(foe, PROMPT_SIZE)


## The centre of a glyph `size` px square over `foe`'s head: its bottom `icon_above` (the foe's tuning's, as the unblockable
## icon's) above the head point.
func glyph_centre(foe: Actor, size: int) -> Vector2i:
	var head := Vector2i(picture_point(_head(foe)))
	return Vector2i(head.x, head.y - _tuning_of(foe).icon_above - size / 2 - 1)


# The readability tuning `foe`'s own ActorFx works by (the default one when it has none): what its icon is sized by.
func _tuning_of(foe: Actor) -> ReadabilityTuning:
	var fx := foe.get_node_or_null(^"ActorFx") as ActorFx
	return fx.tuning if fx != null else ActorFx.TUNING


## The unblockable icons shown now, one for each enemy whose perilous tell is on (ActorFx.icon_shape) as {actor, shape,
## centre, rect}: the shape (a HitProfile.Perilous), the middle of its 9x9 glyph and the glyph's rect, in picture pixels. The
## glyph's bottom edge is the foe's tuning's icon_above pixels over the head point (4 at the least), and it follows the head.
func icons() -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	if player == null or camera_rig == null or not is_instance_valid(camera_rig.camera) or not camera_rig.camera.is_inside_tree():
		return shown
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var foe := node as Actor
		if foe == null or foe.dead or foe == player or not foe.is_inside_tree():
			continue
		var fx := foe.get_node_or_null(^"ActorFx") as ActorFx
		if fx == null or fx.icon_shape == HitProfile.Perilous.NONE:
			continue
		var head := Vector2i(picture_point(_head(foe)))
		var size := fx.tuning.icon_size
		var rect := Rect2i(head.x - size / 2, head.y - maxi(fx.tuning.icon_above, 4) - size, size, size)
		shown.append({actor = foe, shape = fx.icon_shape, centre = rect.get_center(), rect = rect, color = fx.tuning.icon_color})
	return shown


## The wave pips, left to right: Pip.CLEARED for waves done, Pip.ON for the one on, Pip.COMING for the rest. None without an
## arena.
func pip_states() -> Array[int]:
	var states: Array[int] = []
	if arena == null or arena.wave < 0:
		return states
	for i in arena.wave_count():
		states.append(Pip.CLEARED if i < arena.wave or (i == arena.wave and arena.wave_is_cleared()) else (Pip.ON if i == arena.wave else Pip.COMING))
	return states


## The picture pixel (whole, from the picture's top-left) that the world point `point` is drawn at: the camera's projection
## into the World image, less its margin and the sub-pixel shift the stage draws it with, rounded.
func picture_point(point: Vector3) -> Vector2:
	var p := camera_rig.camera.unproject_position(point)
	var sub := stage.subpixel if is_instance_valid(stage) else Vector2.ZERO
	return (p + Vector2(-PixelSnap.MARGIN - sub.x, -PixelSnap.MARGIN + sub.y)).round()


## The controls list, one line a row (see ControlsList).
func controls_text() -> String:
	return ControlsList.text()


# --- drawing ---

func _draw() -> void:
	if suppressed:
		return
	if player == null or player.stats == null:
		return
	_draw_player_bars()
	if camera_rig != null and is_instance_valid(camera_rig.camera) and camera_rig.camera.is_inside_tree():
		# What this frame needs of the world is found once: the icons and the foe the palm would finish.
		var icons_now := icons()
		var finishing := _finishing()
		for bars in _bars(icons_now, finishing):
			_draw_foe_bars(bars)
		var reticle: Variant = reticle_at()
		if reticle is Vector2i:
			_diamond(reticle, 2, ROSE, true)
		var prompt: Variant = _prompt_over(finishing)
		if prompt is Vector2i:
			_glyph(prompt)
		for icon in icons_now:
			_draw_icon(icon.shape, icon.rect, icon.color)
	_draw_pips()
	if hints_visible:
		_draw_hints()


func _draw_player_bars() -> void:
	var rows := [
		[STAMINA_ROW, player.stats.max_stamina, stamina_rect(), GOLD],
		[HP_ROW, player.stats.max_hp, hp_rect(), ROSE],
		[POSTURE_ROW, player.stats.max_posture, posture_rect(), POSTURE],
	]
	for row: Array in rows:
		var fill := row[2] as Rect2i
		if row[3] == POSTURE and fill.size == Vector2i.ZERO:
			continue
		var span := Rect2i(LEFT, (row[0] as Vector2i).x, mini(ceili(row[1]), MAX_BAR), (row[0] as Vector2i).y)
		var lit: bool = row[3] == GOLD and stamina_blink_on()
		draw_rect(Rect2(span.grow(1)), WHITE if lit else INK)
		draw_rect(Rect2(span), INK)
		draw_rect(Rect2(fill), WHITE if lit else row[3])


func _draw_foe_bars(bars: Dictionary) -> void:
	var hp := bars.hp as Rect2i
	var posture := bars.posture as Rect2i
	draw_rect(Rect2(Rect2i(hp.position, Vector2i(FOE_BAR, hp.size.y)).grow(1)), INK)
	draw_rect(Rect2(Rect2i(posture.position, Vector2i(FOE_BAR, posture.size.y)).grow(1)), INK)
	draw_rect(Rect2(hp), ROSE)
	draw_rect(Rect2(posture), POSTURE)


func _draw_pips() -> void:
	var states := pip_states()
	if states.is_empty():
		return
	var width := states.size() * PIP + (states.size() - 1) * PIP_GAP
	var x := (int(PICTURE.x) - width) / 2
	for state in states:
		var box := Rect2i(x, PIP_TOP, PIP, PIP)
		draw_rect(Rect2(box.grow(1)), INK)
		match state:
			Pip.CLEARED:
				draw_rect(Rect2(box), ROSE)
			Pip.ON:
				draw_rect(Rect2(box), GOLD)
			_:
				draw_rect(Rect2(box.grow(-1)), Color(0.35, 0.25, 0.38, 0.9))
		x += PIP + PIP_GAP


func _draw_hints() -> void:
	var font := ThemeDB.fallback_font
	var lines := controls_text().split("\n")
	var y := PICTURE.y - HINT_MARGIN - (lines.size() - 1) * (HINT_FONT_SIZE + 2)
	for line in lines:
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x
		var at := Vector2(PICTURE.x - HINT_MARGIN - width, y)
		draw_string_outline(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, 3, INK)
		draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, Color.WHITE)
		y += HINT_FONT_SIZE + 2


# An unblockable icon: the rose cells of its shape in `rect`, in a dark outline one pixel thick.
func _draw_icon(shape: int, rect: Rect2i, color: Color) -> void:
	var rows: Array = ICON_CELLS[shape]
	for pass_outline in [true, false]:
		for y in rows.size():
			for x in (rows[y] as String).length():
				if (rows[y] as String)[x] != "X":
					continue
				var cell := Vector2i(rect.position.x + x, rect.position.y + y)
				if pass_outline:
					draw_rect(Rect2(cell - Vector2i.ONE, Vector2(3, 3)), INK)
				else:
					draw_rect(Rect2(cell, Vector2(1, 1)), color)


# A filled diamond of radius `r` pixels about `centre` (a (2r+1) square), with a dark outline of one more if `outlined`.
func _diamond(centre: Vector2i, r: int, color: Color, outlined: bool) -> void:
	if outlined:
		_diamond_fill(centre, r + 1, INK)
	_diamond_fill(centre, r, color)


func _diamond_fill(centre: Vector2i, r: int, color: Color) -> void:
	for dy in range(-r, r + 1):
		var half := r - absi(dy)
		draw_rect(Rect2(centre.x - half, centre.y + dy, 2 * half + 1, 1), color)


# The finisher prompt: a rose octagon 7 px across with a bright centre, in a dark outline.
func _glyph(centre: Vector2i) -> void:
	var rows := [3, 5, 7, 7, 7, 5, 3]
	for pass_outline in [true, false]:
		for i in rows.size():
			var half: int = (rows[i] as int) / 2 + (1 if pass_outline else 0)
			var y := centre.y - 3 + i
			if pass_outline:
				draw_rect(Rect2(centre.x - half, y, 2 * half + 1, 1), INK)
				if i == 0:
					draw_rect(Rect2(centre.x - 1, y - 1, 3, 1), INK)
				elif i == rows.size() - 1:
					draw_rect(Rect2(centre.x - 1, y + 1, 3, 1), INK)
			else:
				draw_rect(Rect2(centre.x - half, y, 2 * half + 1, 1), ROSE)
	draw_rect(Rect2(centre.x - 1, centre.y - 1, 3, 3), WHITE)


# --- bits ---

# Listens to every foe there is for the blows that reach it (and forgets the ones that are gone), so that a foe hit
# before it was ever drawn still shows its bars.
func _watch_foes() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		if node is Actor:
			_watch(node as Actor)
	for foe: Variant in _watching.keys():
		if not is_instance_valid(foe):
			_watching.erase(foe)
			_hit_at.erase(foe)

# The fill of a bar in `row` (y, height) for `value` of `maximum`: MAX_BAR px at most for the whole bar, the fill its share
# of it, never less than a pixel while there is any value.
func _bar(row: Vector2i, value: float, maximum: float) -> Rect2i:
	var span := mini(ceili(maximum), MAX_BAR)
	var width := 0 if value <= 0.0 else clampi(ceili(span * value / maxf(maximum, 0.001)), 1, span)
	return Rect2i(LEFT, row.x, width, row.y)


# The foe the player has locked on to, or null.
func _locked() -> Actor:
	if player != null and player.brain is PlayerBrain:
		var target: Variant = (player.brain as PlayerBrain).lock.target  # (a Variant: it may have been freed)
		if is_instance_valid(target) and (target as Actor).is_inside_tree() and not (target as Actor).dead:
			return target as Actor
	return null


# Where `actor`'s head is as it is shown: its interpolated place (the camera follows that), its look_height up.
func _head(actor: Actor) -> Vector3:
	return actor.get_global_transform_interpolated().origin + Vector3.UP * actor.def.look_height


func _watch(foe: Actor) -> void:
	if _watching.has(foe):
		return
	_watching[foe] = true
	foe.got_hit.connect(_on_foe_hit.bind(foe))


func _on_foe_hit(result: HitResult, _event: HitEvent, foe: Actor) -> void:
	if result.outcome != HitResult.Outcome.WHIFF and result.outcome != HitResult.Outcome.EVADED:
		_hit_at[foe] = Engine.get_physics_frames()


func _on_refused(_move: MoveData, _reason: StringName) -> void:
	# A press mashed while the bar blinks does not restart it: one blink (and one cue) every ActorFx.REFUSAL_FRAMES at most.
	var now := Engine.get_physics_frames()
	if now - _refused_at >= ActorFx.REFUSAL_FRAMES:
		_refused_at = now
