extends TestCase
## What a fight draws reads on every ground (xvfb, gl_compatibility): the stretch's pale ground and the training yard's dark one. At each of the
## stretch's 26 reference positions (the readability tests') and in the yard, a Knuckle stands frozen in the middle of a move that draws a cue, and
## the picture the player sees (the stage's World image) is taken with the cue and without it. The cues: the parry's rim (knuckle_jab), the heavy's
## rim (knuckle_hook), the perilous attack's rose rim (knuckle_sweep) and its ground wave, the hit spark, the dust puff. The lock-on marker is the Hud's
## diamond, which carries its own ink edge in the code that draws it (Hud._diamond) and is not measured here.
##
## A cue's pixels are those the picture changes by 0.2 or more in luma (off the foe's own body); the rule: at least 85% of its outline (its pixels with a
## neighbour, four ways, that is neither the cue nor the body) changes the picture by 0.35 or more, bright or dark, or is a dark edge (a pixel of 0.16 or less
## in the picture, or touching one): the cue differs from the ground by 0.35, or it is carried by a dark edge all round it. A rim carries an ink edge (the second, wider hull of the rim), a wave a dark band each side of its ring, and
## a spark and a puff a dark pass behind them.
## The table goes to out/shots/bilibara_cues.txt and a crop of each cue at four times its size (the yard's and one in the stretch) to
## out/shots/bilibara/cues/.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(1920, 1080)
const OUT_TEXT := "out/shots/bilibara_cues.txt"
const OUT_PICTURES := "out/shots/bilibara/cues/"
const STRONG := 0.35
## A pixel is the cue's when the picture changes it by this much in luma or more; the cue's outline reads when this share of it changes by STRONG or more.
const VISIBLE := 0.2
const EDGE_SHARE := 0.85
## The dark edges are this dark or darker in the picture (the ink is 0.04 before the screen look).
const INK_LUMA := 0.16
const FOE := "res://data/actors/knuckle_1.tres"
## The pictures kept: a crop of these cues, in the yard and at this position of the stretch (the street's middle).
const PICTURE_AT := "street (cobble, open)"


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _draw() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw


func _world(main: Main) -> Image:
	return main.stage.world.get_texture().get_image()


# The cue's pixels (those the picture changes by VISIBLE or more in luma, off the foe's body) and what their outline is: {n, mean (their mean change),
# edge (the pixels on the cue's outer boundary: a four-way neighbour that is neither the cue nor the body), carried (how many of those differ from the
# ground by STRONG or more, bright or dark, or are a dark edge themselves or touch one: a pixel of INK_LUMA or less, itself or among its eight
# neighbours), strong (how many cue pixels change by STRONG or more)}.
func _measure(with: Image, without: Image, body: Dictionary, box: Rect2i) -> Dictionary:
	var changed := {}
	var sum := 0.0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var at := Vector2i(x, y)
			if body.has(at):
				continue
			var d := absf(_luma(with.get_pixel(x, y)) - _luma(without.get_pixel(x, y)))
			if d >= VISIBLE:
				changed[at] = d
				sum += d
	var edge := 0
	var carried := 0
	var strong := 0
	var debug := OS.get_environment("CUES_DEBUG") == "1"
	var weak_at := PackedStringArray()
	for at: Vector2i in changed:
		if changed[at] >= STRONG:
			strong += 1
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + step
			if not changed.has(next) and not body.has(next):
				edge += 1
				var ok: bool = changed[at] >= STRONG or _luma(with.get_pixelv(at)) <= INK_LUMA
				if not ok:
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var near := at + Vector2i(dx, dy)
							if changed.has(near) and _luma(with.get_pixelv(near)) <= INK_LUMA:
								ok = true
				if ok:
					carried += 1
				elif debug:
					weak_at.append("%s:%.2f(with %.2f)" % [at, changed[at], _luma(with.get_pixelv(at))])
				break
	if debug and not weak_at.is_empty():
		print("WEAK ", weak_at.slice(0, 40))
	return {n = changed.size(), mean = sum / maxf(changed.size(), 1.0), edge = edge, carried = carried, strong = strong}


# Whether the cue reads: its outline is carried nearly all round (differs from the ground by STRONG or more, or is a dark edge), and some of it is strong.
func _reads(m: Dictionary) -> bool:
	return m.n >= 8 and m.edge > 0 and m.strong >= 4 and m.carried >= m.edge * EDGE_SHARE


func _save(main: Main, label: String, img: Image, centre: Actor) -> void:
	var sub := OS.get_environment("CUES_OUT")
	var dir := ProjectSettings.globalize_path("res://").path_join(OUT_PICTURES if sub.is_empty() else OUT_PICTURES + sub + "/")
	DirAccess.make_dir_recursive_absolute(dir)
	var feet := main.camera_rig.camera.unproject_position(centre.global_position) + Vector2(PixelSnap.MARGIN, PixelSnap.MARGIN)
	var r := Rect2i(int(feet.x) - 60, int(feet.y) - 90, 120, 120).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.convert(Image.FORMAT_RGB8)
	crop.resize(r.size.x * 4, r.size.y * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png(dir.path_join(label + ".png"))


# Stands the foe in the middle of `move` at `frame` (frozen), Abarax beside it, at `at`; waves stand still.
func _stage(main: Main, foe: Actor, at: Vector3, move: StringName, frame: int) -> void:
	foe.frozen = 0
	main.player.frozen = 0
	foe.runner.stop()
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), at + Vector3(-1.2, 0.0, 0.0)))
	main.player.place(Transform3D(Basis(Vector3.UP, 0.0), at + Vector3(1.2, 0.0, 0.0)))
	main.camera_rig.snap_now()
	await frames(4)
	foe.runner.start(Registry.fetch(&"moves", move) as MoveData)
	await _advance(main, foe, frame)


# Runs the foe on `frames_to_run` frames, then freezes it (and the waves).
func _advance(main: Main, foe: Actor, frames_to_run: int) -> void:
	foe.frozen = 0
	main.player.frozen = 0
	await frames(frames_to_run)
	foe.freeze(100000)
	main.player.freeze(100000)
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.set_physics_process(false)
	for spark in get_tree().get_nodes_in_group(ActorFx.GROUP):
		spark.free()
	await _draw()


# The foe's pixels and its shadow's: what is not there when it is hidden.
func _body(main: Main, foe: Actor, shown: Image) -> Dictionary:
	foe.visible = false
	await _draw()
	var hidden := _world(main)
	foe.visible = true
	await _draw()
	var body := {}
	for y in shown.get_height():
		for x in shown.get_width():
			var a := shown.get_pixel(x, y)
			var b := hidden.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.02:
				body[Vector2i(x, y)] = true
	return body


func _box(main: Main, foe: Actor, size: Vector2i) -> Rect2i:
	var feet := main.camera_rig.camera.unproject_position(foe.global_position) + Vector2(PixelSnap.MARGIN, PixelSnap.MARGIN)
	return Rect2i(int(feet.x) - 110, int(feet.y) - 110, 220, 150).intersection(Rect2i(Vector2i.ZERO, size))


# The cues of one place, each measured against the same picture without it: `out` gets [cue name, measure, the picture with the cue].
func _cues_at(main: Main, foe: Actor, at: Vector3, out: Array) -> void:
	var fx := foe.get_node("ActorFx") as ActorFx
	# knuckle_jab: the parry's rim at frame 15, then (rim off) the spark and the puff over the same picture.
	await _stage(main, foe, at, &"knuckle_jab", 15)
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.visible = false
	await _draw()
	var with := _world(main)
	fx.end_tell()
	await _draw()
	var without := _world(main)
	var box := _box(main, foe, with.get_size())
	var body := await _body(main, foe, without)
	# What moves in the picture of itself (the water, a banner) is not the cue: the pixels two pictures of the same moment apart differ in.
	var seen: Array[Image] = [without]
	for k in 6:
		for i in 3:
			await RenderingServer.frame_post_draw
		seen.append(_world(main))
	var noise := {}
	for y in without.get_height():
		for x in without.get_width():
			var first := seen[0].get_pixel(x, y)
			for k in range(1, seen.size()):
				var other := seen[k].get_pixel(x, y)
				if absf(first.r - other.r) + absf(first.g - other.g) + absf(first.b - other.b) > 0.02:
					noise[Vector2i(x, y)] = true
					break
	body.merge(noise)
	var still: Dictionary = noise
	out.append(["parry rim", _measure(with, without, body, box), with])
	# A particle effect is sampled at three moments of its life and the fullest picture kept; it is measured over everything (a spark at the chest is
	# over the body, which is where it shows).
	for kind: Array in [["hit spark", &"hit_spark", 1.2], ["dust puff", &"dust_puff", 0.05]]:
		var best: Dictionary = {}
		var best_picture: Image = null
		for k in 3:
			fx.show_fx(kind[1], foe.global_position + Vector3(0.0, kind[2], 0.0))
			for i in 3 + 2 * k:
				await RenderingServer.frame_post_draw
			var shown := _world(main)
			var m := _measure(shown, without, still, box)
			if best.is_empty() or m.n > best.n:
				best = m
				best_picture = shown
			for spark in get_tree().get_nodes_in_group(ActorFx.GROUP):
				spark.free()
			await _draw()
		out.append([kind[0], best, best_picture])
	# knuckle_hook: the heavy's rim at frame 34.
	await _stage(main, foe, at, &"knuckle_hook", 34)
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.visible = false
	await _draw()
	with = _world(main)
	fx.end_tell()
	await _draw()
	without = _world(main)
	body = await _body(main, foe, without)
	body.merge(still)
	out.append(["heavy rim", _measure(with, without, body, box), with])
	# knuckle_sweep: the perilous ground wave at frame 10 (rim off), then the rose rim at frame 25 (waves hidden).
	await _stage(main, foe, at, &"knuckle_sweep", 10)
	foe.rig.clear_aura()
	await _draw()
	with = _world(main)
	var rim_off := with
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.visible = false
	await _draw()
	without = _world(main)
	body = await _body(main, foe, without)
	body.merge(still)
	out.append(["perilous wave", _measure(rim_off, without, body, box), rim_off])
	await _stage(main, foe, at, &"knuckle_sweep", 25)
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.visible = false
	await _draw()
	with = _world(main)
	fx.end_tell()
	await _draw()
	without = _world(main)
	body = await _body(main, foe, without)
	body.merge(still)
	out.append(["perilous rim", _measure(with, without, body, box), with])


func _run(main: Main, foe: Actor, label: String, at: Vector3, lines: PackedStringArray, problems: PackedStringArray, keep: String) -> void:
	var made: Array = []
	await _cues_at(main, foe, at, made)
	for cue: Array in made:
		var m: Dictionary = cue[1]
		var ok := _reads(m)
		lines.append("%s | %s | cue px %d, %d change by 0.35 or more | their mean change %.3f | outline px %d, of them %d carried (%.0f%%) | %s" % [label, cue[0], m.n, m.strong, m.mean, m.edge, m.carried, 100.0 * m.carried / maxf(m.edge, 1.0), "reads" if ok else "LOST"])
		if not ok:
			problems.append("%s at %s: %d px (%d strong), outline %d px of which %d carried (at least %.0f%%)" % [cue[0], label, m.n, m.strong, m.edge, m.carried, 100.0 * EDGE_SHARE])
		if not keep.is_empty():
			_save(main, "%s_%s" % [keep, String(cue[0]).replace(" ", "_")], cue[2], foe)


func test_every_cue_reads_on_every_ground() -> void:
	var lines := PackedStringArray(["place | cue | pixels the cue changes | their mean change in luma | the cue's outline and how much of it differs from the ground by 0.35 or more | verdict"])
	var problems := PackedStringArray()
	var positions: Array = []
	positions.append_array(load("res://tests/render/test_bilibara_readability.gd").POSITIONS)
	positions.append_array(load("res://tests/render/test_bilibara_readability_more.gd").POSITIONS)
	assert_eq(positions.size(), 26, "the 26 reference positions")
	# The stretch.
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(3)
	main.enter_stretch()
	await frames(3)
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.def = load(FOE) as ActorDef
	foe.set_brain(Brain.new())
	main.region.add_child(foe)
	main.player.set_brain(Brain.new())
	var only := OS.get_environment("CUES_ONLY")
	for entry: Array in positions:
		if not only.is_empty() and not String(entry[0]).begins_with(only):
			continue
		await _run(main, foe, entry[0], Vector3(entry[1], 0.0, entry[2]), lines, problems, "stretch" if entry[0] == PICTURE_AT else "")
	main.queue_free()
	await frames(3)
	# The training yard.
	Game.reset()
	Arena.reset_spawn_counts()
	var yard := track((load(MAIN) as PackedScene).instantiate()) as Main
	yard.arena().automatic = false
	await frames(3)
	var yard_foe := yard.arena().enemies()[0]
	yard_foe.set_brain(Brain.new())
	yard.player.set_brain(Brain.new())
	await _run(yard, yard_foe, "training yard (0, 6)", Vector3(0.0, 0.0, 6.0), lines, problems, "yard")
	var full := ProjectSettings.globalize_path("res://").path_join(OUT_TEXT)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	FileAccess.open(full, FileAccess.WRITE).store_string("\n".join(lines) + "\n")
	print("\n".join(lines))
	assert_eq(problems.slice(0, 10), PackedStringArray(), "every cue reads at every position and in the yard (%d lost; the table is %s)" % [problems.size(), OUT_TEXT])
