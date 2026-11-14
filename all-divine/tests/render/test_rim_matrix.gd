extends TestCase
## The rim on a body's silhouette (Rig.aura) wherever a fight ends up, as drawn (xvfb, gl_compatibility; Forward+ draws the
## same): it must not depend on what is behind the body, nor on the pose. A Knuckle frozen in each of its blows, early in
## the wind-up and at the blow, with its rim lit at full, is put
##   in the open,
##   with its back to the north wall, and along that wall,
##   in the north-east corner facing out (each 0.36 m from the wall, as near as a body gets to one),
##   and in the open with Abarax 0.7 m behind it (further from the camera, so the two overlap in the picture).
## In every place
##   the rim stays off the body's inside: of the silhouette eroded by 2 px, at most 2% of the pixels change;
##   it keeps its edge: the rim pixels on the upper body are at least 80% of what the same pose shows in the open;
##   and nothing changes away from the body.
## In the open, the rim goes all the way round: it lights at least 80% of the pixels just outside the upper body.
## And with two bodies one behind the other, both with a rim on: the front body's rim shows over the body behind it, the
## back body's rim never over the body in front, and neither on its own body's inside.
##
## A pose that leans back at a wall puts part of the body into the wall, which hides it (a sweep's shoulders, a fist drawn
## back). The rim of what is hidden cannot show, so there the rim is asked of the edge that still shows: the count is taken
## per pixel of the open-ground outline that is still outline. With all of the body showing that is the plain count.
##
## The pose is the same in every place: the move is played once in the open and the body frozen, then stood where the case
## says, turned as it says, a whole number of pixels from its place in the open, so that the two pictures of it are the
## same pixels (the camera moves in whole pixels). The silhouette is the body's own pixels exactly (ShotMasks.silhouette).
## Every case's numbers go to out/shots/rim_matrix_<renderer>.txt and its picture to a sheet beside it, for a person to
## look at.

const MAIN := "res://main/main.tscn"
## The blade Knuckle, whose sword is part of the body the rim goes round.
const BLADE := preload("res://data/actors/knuckle_blade.tres")
## The chop's wind-up holds the sword up end-on to the camera: the rim round its tip shows 3 pixels past the pixels the silhouette
## reads there (one more than the fists' 2), a tip a few pixels wide being drawn a little further than the flat-colour pass reads it.
const SWORD_TIP_FAR := 3
## The World picture is what is read, 642x362 whatever the window is: a small window is drawn faster.
const SIZE := Vector2i(640, 360)
const ROSE := Color("e8607e")
const GOLD := Color("fff1c8")
## A pixel is a rim's when its channels are within this of the rim's colour, summed.
const CHANGED := 0.02
## How far inside the silhouette the interior starts, and how far outside it the edge band reaches, in pixels.
const MARGIN_PX := 2
const MAX_INTERIOR_CHANGED := 0.02
const MIN_RIM_KEPT := 0.8
const MIN_OUTLINE_LIT := 0.8
## The yard's walls are 12.5 m from its middle, and a body comes to rest 0.36 m from one.
const WALL := 12.5
const GAP := 0.36
## Open, unlit ground near the middle of the yard.
const OPEN := Vector3(-1.25, 0.0, 2.0)
## Where Abarax stands: aside (toward the middle of the yard), or behind the foe.
const ASIDE := Vector3(2.4, 0.0, 0.6)
const BEHIND := Vector3(0.2, 0.0, -0.7)
## Each case: its name, where the foe's feet are, the way it faces (degrees about up: 0 faces the camera, 90 east, 315
## south-west), and where Abarax stands from it. The first of each facing is that facing's open ground. The wall cases
## stand between two of the wall's pilasters, clear of the banners that hang before it.
const PLACES := [
	{name = "open", at = OPEN, yaw = 0, player = ASIDE},
	{name = "back to the north wall", at = Vector3(-1.4, 0.0, GAP - WALL), yaw = 0, player = ASIDE},
	{name = "Abarax 0.7 m behind", at = OPEN, yaw = 0, player = BEHIND},
	{name = "open, facing east", at = OPEN, yaw = 90, player = ASIDE},
	{name = "along the north wall", at = Vector3(-1.4, 0.0, GAP - WALL), yaw = 90, player = ASIDE},
	{name = "open, facing south-west", at = OPEN, yaw = 315, player = ASIDE},
	{name = "north-east corner, facing out", at = Vector3(WALL - GAP, 0.0, GAP - WALL), yaw = 315, player = Vector3(-2.4, 0.0, 0.6)},
]
## The crop of each case on the sheet, in pixels of the picture, and how many times it is enlarged.
const CELL := Vector2i(104, 104)
const SHEET_SCALE := 3

static var _sheet: Image
static var _rows := 0
static var _lines := PackedStringArray()


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_the_jab_rim_holds_everywhere() -> void:
	await _check_move(&"knuckle_jab", [8, 19])


func test_the_hook_rim_holds_everywhere() -> void:
	await _check_move(&"knuckle_hook", [12, 39])


func test_the_sweep_rim_holds_everywhere() -> void:
	await _check_move(&"knuckle_sweep", [10, 42])


func test_the_thrust_rim_holds_everywhere() -> void:
	await _check_move(&"knuckle_thrust", [10, 42])


func test_the_grab_rim_holds_everywhere() -> void:
	await _check_move(&"knuckle_grab", [10, 45])


func test_the_blade_cut_rim_holds_everywhere() -> void:
	await _check_move(&"blade_cut", [8, 20], BLADE)


func test_the_blade_chop_rim_holds_everywhere() -> void:
	await _check_move(&"blade_chop", [10, 24], BLADE, SWORD_TIP_FAR)


func test_the_blade_lunge_rim_holds_everywhere() -> void:
	await _check_move(&"blade_lunge", [10, 42], BLADE)


# Two rims at once, one body 0.7 m behind the other (so they overlap in the picture), each way round. A rim at full strength
# is its colour exactly, so each lit pixel says whose rim it is.
func test_two_rims_one_body_behind_the_other() -> void:
	var run := await _pose(&"knuckle_sweep", 10)
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	var player := main.player
	var at := _open_for(main, 0)
	for case: Array in [["the Knuckle in front", foe, player, BEHIND], ["Abarax in front", player, foe, -BEHIND]]:
		var front: Actor = case[1]
		var back: Actor = case[2]
		_put(foe, Transform3D(run["turn"] as Basis, at))
		_put(player, Transform3D(Basis.IDENTITY, at + case[3]))
		foe.rig.clear_aura()
		player.rig.clear_aura()
		main.camera_rig.snap_now()
		await frames(2)
		main.camera_rig.snap_now()
		await _draw()
		var without := _world(main)
		var feet := _feet(main, foe)
		var box := Rect2i(feet.x - 80, feet.y - 110, 160, 160).intersection(Rect2i(Vector2i.ZERO, without.get_size()))
		var shows := {front: await ShotMasks.silhouette(main, front, box), back: await ShotMasks.silhouette(main, back, box)}
		foe.rig.hold_aura(ROSE, 1.0)
		player.rig.hold_aura(GOLD, 1.0)
		await _draw()
		var with := _world(main)
		_save_picture(with.get_region(box), "rim_two_%s" % String(case[0]).replace(" ", "_"))
		var colour := {foe: ROSE, player: GOLD}
		var changed := ShotMasks.diff(with, without, box)
		# Whose rim each lit pixel is: [front's, back's] counts over the back body, over the front body, and inside each one's own body.
		var over_back := [0, 0]
		var over_front := [0, 0]
		var own_inside := [0, 0]
		var inside := [ShotMasks.eroded(shows[front], MARGIN_PX), ShotMasks.eroded(shows[back], MARGIN_PX)]
		var other := 0
		for p: Vector2i in changed:
			var lit := with.get_pixelv(p)
			var whose := -1
			for i in 2:
				var rim: Color = colour[[front, back][i]]
				if absf(lit.r - rim.r) + absf(lit.g - rim.g) + absf(lit.b - rim.b) <= CHANGED:
					whose = i
			if whose < 0:
				other += 1
				continue
			if (shows[back] as Dictionary).has(p):
				over_back[whose] += 1
			if (shows[front] as Dictionary).has(p):
				over_front[whose] += 1
			if (inside[whose] as Dictionary).has(p):
				own_inside[whose] += 1
		_lines.append("two rims   %-30s rim %3d px | the front's rim over the back body %d, the back's over the front body %d | inside its own body: front %d of %d, back %d of %d | neither colour %d" % [
				case[0], changed.size(), over_back[0], over_front[1], own_inside[0], inside[0].size(), own_inside[1], inside[1].size(), other])
		assert_true(over_back[0] >= 10, "%s: its rim shows over the body behind it (%d pixels)" % [case[0], over_back[0]])
		assert_eq(over_front[1], 0, "%s: the rim of the body behind is never drawn over it" % case[0])
		for i in 2:
			assert_true(inside[i].size() >= 20, "%s: body %d has an inside (%d pixels)" % [case[0], i, inside[i].size()])
			assert_true(float(own_inside[i]) <= MAX_INTERIOR_CHANGED * inside[i].size(), "%s: %d of the %d pixels inside body %d are its own rim's" % [case[0], own_inside[i], inside[i].size(), i])
		assert_eq(other, 0, "%s: every lit pixel is one rim's colour or the other's: none is drawn twice or mixed" % case[0])
	_save()


# The passes a region's first frames are drawn with, so that a rim's shaders are built before a fight needs them
# (Rig.warm_rim): eight passes over Abarax, and not a pixel of the picture changes.
func test_the_warming_passes_show_nothing() -> void:
	var run := await _pose(&"knuckle_sweep", 10)
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	var player := main.player
	var at := _open_for(main, 0)
	_put(foe, Transform3D(run["turn"] as Basis, at))
	_put(player, Transform3D(Basis.IDENTITY, at - BEHIND))
	main.camera_rig.snap_now()
	await frames(Rig.WARM_FRAMES + 2)  # the passes the region put on when it loaded are off again
	main.camera_rig.snap_now()
	await _draw()
	var without := _world(main)
	var body := player.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert_true(body.material_overlay == null, "nothing over Abarax before")
	player.rig.warm_rim()
	await _draw()
	assert_true(body.material_overlay != null, "the picture is taken with the passes on")
	var with := _world(main)
	var changed := ShotMasks.diff(with, without, Rect2i(Vector2i.ZERO, without.get_size()), 0.0)
	_lines.append("warming    Abarax wearing the passes of the first %d marks: %d pixels of %d changed" % [RimMarks.WARM, changed.size(), without.get_width() * without.get_height()])
	assert_eq(changed.size(), 0, "the warming passes change no pixel of the picture")
	_save()


# One move at an early frame and at its blow, in every place.
func _check_move(move_id: StringName, at_frames: Array, def: ActorDef = null, far_allowed := 2) -> void:
	for frame: int in at_frames:
		var run := await _pose(move_id, frame, def)
		var main: Main = run["main"]
		var foe: Actor = run["foe"]
		var label := "%s f%d" % [String(move_id).trim_prefix("knuckle_").trim_prefix("blade_"), frame]
		var open := {}
		var column := 0
		for place: Dictionary in PLACES:
			var is_open := String(place.name).begins_with("open")
			var at: Vector3 = _open_for(main, place.yaw) if place.at == OPEN else place.at
			var to := Transform3D(Basis(Vector3.UP, deg_to_rad(place.yaw)) * (run["turn"] as Basis), at)
			var stats := await _measure(main, foe, to, place.player, {} if is_open else open)
			_add_to_sheet(stats.picture, main, foe, column)
			column += 1
			var where := "%s, %s" % [label, place.name]
			if is_open:
				open = stats
				assert_true(open.outline >= 30, "%s: the upper body has an outline (%d pixels)" % [where, open.outline])
				assert_true(open.lit >= MIN_OUTLINE_LIT * open.outline, "%s: the rim goes all the way round: it lights %d of the %d pixels just outside the upper body (at least %d%%)" % [
						where, open.lit, open.outline, roundi(MIN_OUTLINE_LIT * 100)])
			# The rim per pixel of the outline that still shows, against the open ground's: with all of the body showing, the
			# share of the open ground's count.
			var kept: float = (float(stats.upper) / maxf(stats.outline_showing, 1.0)) / (float(open.upper) / open.outline)
			_lines.append("%-10s %-30s rim %3d px | upper %3d of the open's %3d (%3d%%), outline showing %3d of %3d (%3d lit), kept %3d%% | interior %2d of %3d (%.1f%%) | far %d" % [
				label, place.name, stats.rim, stats.upper, open.upper, roundi(100.0 * stats.upper / open.upper), stats.outline_showing, open.outline, stats.lit,
				roundi(100.0 * kept), stats.inside, stats.interior, 100.0 * stats.inside / maxf(stats.interior, 1.0), stats.far])
			assert_true(stats.steady, "%s: the frame is steady (nothing in it moves by itself)" % where)
			assert_true(stats.interior > 40, "%s: the body has an inside to keep clean (%d pixels)" % [where, stats.interior])
			assert_true(float(stats.inside) <= MAX_INTERIOR_CHANGED * stats.interior,
					"%s: %d of the %d interior pixels changed (at most %d%% may)" % [where, stats.inside, stats.interior, roundi(MAX_INTERIOR_CHANGED * 100)])
			assert_true(stats.outline_showing >= 15, "%s: some of the upper body's edge shows (%d of %d outline pixels)" % [where, stats.outline_showing, open.outline])
			assert_true(kept >= MIN_RIM_KEPT, "%s: the upper body keeps %d%% of the open ground's rim (%d pixels on %d of outline; in the open %d on %d)" % [
					where, roundi(100.0 * kept), stats.upper, stats.outline_showing, open.upper, open.outline])
			assert_true(stats.far <= far_allowed, "%s: nothing away from the body changed (%d pixels, at most %d)" % [where, stats.far, far_allowed])
		_rows += 1
		main.queue_free()
		await frames(2)
	_save()


# The yard with a Knuckle `frame` frames into `move_id`, started in the open facing the camera, and Abarax; both frozen, no
# shadows, nothing else moving. Returns {main, foe, turn}: `turn` is how far the move has turned the body from the way it
# started; each case then stands the frozen body where it wants, facing its way.
func _pose(move_id: StringName, frame: int, def: ActorDef = null) -> Dictionary:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	for light in main.region.find_children("*", "Light3D", true, false):
		(light as Light3D).shadow_enabled = false
	if def != null:  # the one foe of this def, in place of the first wave's
		var wave := ArenaWave.new()
		wave.defs.assign([def])
		wave.count = PackedInt32Array([1])
		main.arena().clear_foes()
		main.arena().waves.assign([wave])
		main.arena().start_wave(0)
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	main.player.set_brain(Brain.new())
	foe.place(Transform3D(Basis.IDENTITY, OPEN))
	main.player.place(Transform3D(Basis.IDENTITY, OPEN + Vector3(6.0, 0.0, 0.0)))
	await frames(3)
	foe.runner.start(Registry.fetch(&"moves", move_id) as MoveData)
	await frames(frame)
	foe.freeze(100000000)
	main.player.freeze(100000000)
	# The tell's own rim, wave and sparks are not what is measured: the rim is lit by hand, at full.
	(foe.get_node("ActorFx") as ActorFx).end_tell()
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.free()
	for spark in get_tree().get_nodes_in_group(ActorFx.GROUP):
		spark.free()
	return {"main": main, "foe": foe, "turn": foe.global_basis.orthonormalized()}


# The open ground for the cases that face `yaw`: OPEN, moved by less than a pixel so that the wall case of that facing is a
# whole number of pixels from it in the picture.
func _open_for(main: Main, yaw: int) -> Vector3:
	var to := OPEN
	for place: Dictionary in PLACES:
		if place.yaw == yaw and place.at != OPEN:
			to = place.at
	var up := main.camera_rig.camera.global_basis.y
	# A step north or south shows as its share along the camera's up; a step east or west as itself.
	var step_z := PixelSnap.TEXEL / absf(up.z)
	return Vector3(to.x + roundf((OPEN.x - to.x) / PixelSnap.TEXEL) * PixelSnap.TEXEL, 0.0, to.z + roundf((OPEN.z - to.z) / step_z) * step_z)


func _draw(n := 2) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _world(main: Main) -> Image:
	return main.stage.world.get_texture().get_image()


func _put(actor: Actor, to: Transform3D) -> void:
	actor.global_transform = to
	actor.reset_physics_interpolation()


# The pixel of the World image a body's feet are at.
func _feet(main: Main, actor: Actor) -> Vector2i:
	return Vector2i(main.camera_rig.camera.unproject_position(actor.global_position).round())


# The rim of the frozen `foe` stood at `to`, with Abarax `player_from` it, measured against `open`, the same body's
# measurement on open ground ({} when this is it). Returns
#   rim       how many pixels the rim changes
#   upper     how many of them on the upper body's edge: within MARGIN_PX of the silhouette's edge, above the body's middle
#   outline   the pixels just outside the silhouette, above the middle (a set, from the feet), and how many there are
#   lit       how many of those the rim lights
#   outline_showing  how many of them are outline in the open too: the body's own edge, not where a wall cuts it off
#   inside, interior   how many pixels of the silhouette eroded by MARGIN_PX changed, of how many
#   far       how many changed pixels are further than MARGIN_PX from the body, hidden parts and all
#   body, middle   the silhouette (a set, from the feet) and the row of the body's middle (from the feet), for the next case
#   steady, picture   whether the frame stood still, and the frame with the rim
func _measure(main: Main, foe: Actor, to: Transform3D, player_from: Vector3, open: Dictionary) -> Dictionary:
	_put(foe, to)
	_put(main.player, Transform3D(Basis.IDENTITY, to.origin + player_from))
	foe.rig.clear_aura()
	main.camera_rig.snap_now()
	await frames(2)
	main.camera_rig.snap_now()
	await _draw()
	foe.rig.hold_aura(ROSE, 1.0)
	await _draw()
	var with := _world(main)
	foe.rig.clear_aura()
	await _draw()
	var without := _world(main)
	await _draw(1)
	var steady := _world(main).get_data() == without.get_data()
	var feet := _feet(main, foe)
	var box := Rect2i(feet.x - 70, feet.y - 95, 140, 130).intersection(Rect2i(Vector2i.ZERO, with.get_size()))
	var changed := ShotMasks.diff(with, without, box)
	var body := await ShotMasks.silhouette(main, foe, box)
	var interior := ShotMasks.eroded(body, MARGIN_PX)
	var band := ShotMasks.grown(body, MARGIN_PX)
	# The middle of the body: half of the open-ground silhouette's height above the feet, the same row in every place.
	var middle: int
	if open.is_empty():
		var top := feet.y
		for p: Vector2i in body:
			top = mini(top, p.y)
		middle = (top - feet.y) / 2
	else:
		middle = open.middle
	# The whole body's band, with what a wall hides of it: the open-ground silhouette, stood here.
	var whole_band := band if open.is_empty() else ShotMasks.grown(open.body, MARGIN_PX, feet)
	var upper := 0
	var inside := 0
	var far := 0
	for p: Vector2i in changed:
		if interior.has(p):
			inside += 1
		elif not band.has(p):
			if not whole_band.has(p):
				far += 1
		elif p.y < feet.y + middle:
			upper += 1
	var outline := {}
	var lit := 0
	var outline_showing := 0
	for p: Vector2i in ShotMasks.grown(body, 1):
		if p.y < feet.y + middle and not body.has(p):
			outline[p - feet] = true
			if changed.has(p):
				lit += 1
			if open.is_empty() or (open.outline_at as Dictionary).has(p - feet):
				outline_showing += 1
	var body_from_feet := {}
	for p: Vector2i in body:
		body_from_feet[p - feet] = true
	return {rim = changed.size(), upper = upper, outline = outline.size(), outline_at = outline, lit = lit, outline_showing = outline_showing,
			inside = inside, interior = interior.size(), far = far, body = body_from_feet, middle = middle, steady = steady, picture = with}


# Puts the case's picture on the sheet: the rows are the poses, the columns the places.
func _add_to_sheet(picture: Image, main: Main, foe: Actor, column: int) -> void:
	if _sheet == null:
		_sheet = Image.create(CELL.x * PLACES.size(), CELL.y * 10, false, Image.FORMAT_RGBA8)
	var feet := _feet(main, foe)
	var from := Rect2i(feet.x - CELL.x / 2, feet.y - CELL.y * 3 / 4, CELL.x, CELL.y).intersection(Rect2i(Vector2i.ZERO, picture.get_size()))
	var crop := picture.get_region(from)
	crop.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(column * CELL.x, _rows * CELL.y))


# Saves `picture`, enlarged, as out/shots/<name>_<renderer>.png.
func _save_picture(picture: Image, name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	picture.resize(picture.get_width() * SHEET_SCALE, picture.get_height() * SHEET_SCALE, Image.INTERPOLATE_NEAREST)
	assert_eq(picture.save_png(dir.path_join("%s_%s.png" % [name, RenderingServer.get_current_rendering_method()])), OK)


# Saves the sheet and the table, as far as they have got.
func _save() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("out/shots")
	var method := RenderingServer.get_current_rendering_method()
	if _sheet != null:
		_save_picture(_sheet.duplicate() as Image, "rim_matrix")
	var file := FileAccess.open(dir.path_join("rim_matrix_%s.txt" % method), FileAccess.WRITE)
	assert_true(file != null, "the table can be written")
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
