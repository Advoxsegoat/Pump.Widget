extends TestCase
## What the dodge chain's rim and afterimage look like as drawn (xvfb, gl_compatibility; Forward+ draws the same), held to the
## owner's rule for effects: nothing tints or covers a body's interior.
##
## Abarax stands in the open in the training yard, still, and the camera is held on a fixed point so that it stays put when he moves.
## The silhouette of a body is its own pixels exactly (ShotMasks.silhouette).
##   The chain's rim (ChainFx, from Quick on): at Quick and at Flurry it changes no pixel inside his body, eroded by 2 px (the same
##   margin as a tell's rim), it lights his edge, and it is stronger at Flurry than at Quick.
##   The afterimage (Afterimage, behind every body): it is the shape of the silhouette where he stood; after he has moved on and a
##   Knuckle stands behind him in the picture, the pixels it changes are none of Abarax's or the Knuckle's, to the pixel; it shows
##   on the yard's lit floor and on its dark floor; and after its frames it is gone and the picture is the empty yard's.
##   The afterimage must be seen: in real dodges (a sway and a duck, at Quick and at Flurry, with the slow-down on and off) the pixels it
##   shows outside every body are counted on each wall frame, from a run with the afterimage and an identical run without it.
##   The Quick rim has the Flurry rim's gold hue, on the dark ground and the lamplit one.
## Pictures worth a person's look go to out/shots/chain/.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(640, 360)
const GOLD := Color("fff1c8")
const MARGIN_PX := 2
const MAX_INTERIOR_CHANGED := 0.02
const SHEET_SCALE := 3
## Where the fight stands: open ground, the Knuckle behind him (further from the camera, so the two overlap in the picture), and where
## he moves on to for the afterimage.
const OPEN := Vector3(-1.25, 0.0, 2.0)
const BEHIND := Vector3(0.0, 0.0, -0.45)
const MOVED := Vector3(0.7, 0.0, 0.0)
## The yard's lamps light the ground in pools: this is the middle of one, and this a place no lamp reaches (OPEN is one too).
const LIT := Vector3(9.0, 0.0, 9.0)
const DARK := OPEN


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


# The yard with Abarax and one Knuckle, both still and with no brain, no shadows, the camera on a fixed point `at`. Returns
# {main, foe, held}: `held` is the point the camera looks at.
func _yard(at: Vector3) -> Dictionary:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	for light in main.region.find_children("*", "Light3D", true, false):
		(light as Light3D).shadow_enabled = false
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	main.player.set_brain(Brain.new())
	var held := Marker3D.new()
	main.region.add_child(held)
	held.global_position = at
	main.camera_rig.target = held
	_put(main.player, Transform3D(Basis.IDENTITY, at))
	_put(foe, Transform3D(Basis(Vector3.UP, PI), at + BEHIND))
	await frames(Rig.WARM_FRAMES + 3)
	main.camera_rig.snap_now()
	await frames(2)
	main.camera_rig.snap_now()
	main.player.freeze(100000000)
	foe.freeze(100000000)
	return {"main": main, "foe": foe, "held": held}


func _draw(n := 2) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _world(main: Main) -> Image:
	return main.stage.world.get_texture().get_image()


func _put(actor: Actor, to: Transform3D) -> void:
	actor.global_transform = to
	actor.reset_physics_interpolation()


func _feet(main: Main, at: Vector3) -> Vector2i:
	return Vector2i(main.camera_rig.camera.unproject_position(at).round())


func _box(main: Main, at: Vector3) -> Rect2i:
	var feet := _feet(main, at)
	return Rect2i(feet.x - 90, feet.y - 105, 180, 150).intersection(Rect2i(Vector2i.ZERO, SIZE + Vector2i(2, 2)))


# Saves `picture`, enlarged, as out/shots/chain/<name>_<renderer>.png.
func _save(picture: Image, name: String, box := Rect2i()) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("out/shots/chain")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := picture.get_region(box) if box.has_area() else picture.duplicate() as Image
	shot.resize(shot.get_width() * SHEET_SCALE, shot.get_height() * SHEET_SCALE, Image.INTERPOLATE_NEAREST)
	assert_eq(shot.save_png(dir.path_join("%s_%s.png" % [name, RenderingServer.get_current_rendering_method()])), OK)


func _images() -> Array[Afterimage]:
	var found: Array[Afterimage] = []
	for node in get_tree().get_nodes_in_group(Afterimage.GROUP):
		found.append(node as Afterimage)
	return found


# Hides the afterimages (and shows them again), so that what is drawn is the bodies' own flat colours.
func _show_images(on: bool) -> void:
	for image in _images():
		image.visible = on


func test_the_afterimage_and_the_chain_rim_change_no_pixel_inside_his_body() -> void:
	var run := await _yard(OPEN)
	var main: Main = run["main"]
	var player := main.player
	var foe: Actor = run["foe"]
	var box := _box(main, OPEN)
	# --- the chain's rim ---
	await _draw()
	var without := _world(main)
	var body := await ShotMasks.silhouette(main, player, box)
	var inside := ShotMasks.eroded(body, MARGIN_PX)
	assert_true(inside.size() > 100, "Abarax has an inside to keep clean (%d pixels)" % inside.size())
	var lit := {}
	for tempo: Array in [["quick", 3], ["flurry", 7]]:
		player.chain.end()
		for i in tempo[1]:
			player.chain.link(false, player.buffer_frame)
		await frames(2)
		await _draw()
		assert_true(player.rig.aura_active(), "the %s rim is on" % tempo[0])
		var with := _world(main)
		var changed := ShotMasks.diff(with, without, box)
		var in_body := 0
		for p: Vector2i in changed:
			if inside.has(p):
				in_body += 1
		assert_true(float(in_body) <= MAX_INTERIOR_CHANGED * inside.size(),
				"%s: %d of the %d pixels inside his body changed (at most %d%%)" % [tempo[0], in_body, inside.size(), roundi(MAX_INTERIOR_CHANGED * 100)])
		assert_true(changed.size() >= 40, "%s: the rim lights his edge (%d pixels)" % [tempo[0], changed.size()])
		lit[tempo[0]] = changed.size()
		_save(with, "rim_%s" % tempo[0], box)
	# half strength is dimmer than full: the same pixels, closer to the ground; compare how far from the picture without the rim
	assert_true(lit["flurry"] >= lit["quick"] * 0.9, "the full rim is no fainter than the half (%s)" % [lit])
	player.chain.end()
	await frames(2)
	# --- the afterimage ---
	await _draw()
	var empty_rim_off := _world(main)
	assert_false(player.rig.aura_active(), "no rim, for the afterimage's own picture")
	# the picture of the yard with Abarax where he will have moved to, and the Knuckle, and no afterimage
	_put(player, Transform3D(Basis.IDENTITY, OPEN + MOVED))
	main.camera_rig.snap_now()
	await frames(2)
	await _draw()
	var moved_alone := _world(main)
	var moved_body := await ShotMasks.silhouette(main, player, box)
	var foe_body := await ShotMasks.silhouette(main, foe, box)
	# the copy where he stood, then he steps aside (the Knuckle stays behind him: its silhouette meets the copy's)
	_put(player, Transform3D(Basis.IDENTITY, OPEN))
	await frames(2)
	var image := Afterimage.spawn(player.rig, ActorFx.TUNING.afterimage_color, 8)
	image.set_physics_process(false)  # held at full strength while it is drawn
	_put(player, Transform3D(Basis.IDENTITY, OPEN + MOVED))
	await frames(2)
	await _draw()
	var with_image := _world(main)
	var changed := ShotMasks.diff(with_image, moved_alone, box)
	var over_abarax := 0
	var over_foe := 0
	for p: Vector2i in changed:
		if moved_body.has(p):
			over_abarax += 1
		if foe_body.has(p):
			over_foe += 1
	assert_true(changed.size() >= 150, "the afterimage shows beside him (%d pixels)" % changed.size())
	assert_eq(over_abarax, 0, "and changes no pixel of Abarax's body, to the pixel")
	assert_eq(over_foe, 0, "or of the Knuckle's, which stands behind him in the picture")
	var overlap_with_foe := 0
	var old_body := {}
	for p: Vector2i in moved_body:
		old_body[p - _feet(main, OPEN + MOVED) + _feet(main, OPEN)] = true
	for p: Vector2i in foe_body:
		if old_body.has(p):
			overlap_with_foe += 1
	assert_true(overlap_with_foe >= 30, "the copy and the Knuckle overlap in the picture, so that 'behind it' was tested (%d pixels)" % overlap_with_foe)
	_save(with_image, "afterimage_behind_the_foe", box)
	_save(moved_alone, "afterimage_none", box)
	image.free()


# The afterimage is Abarax's own silhouette where he stood: with him taken out of the picture it changes the pixels his body covered.
func test_the_afterimage_is_the_shape_of_his_silhouette() -> void:
	var run := await _yard(OPEN)
	var main: Main = run["main"]
	var player := main.player
	var foe: Actor = run["foe"]
	_put(foe, Transform3D(Basis(Vector3.UP, PI), Vector3(-9.0, 0.0, 9.0)))  # out of the picture
	var box := _box(main, OPEN)
	await _draw()
	var empty := await _picture_without(main, player)
	var body := await ShotMasks.silhouette(main, player, box)
	var image := Afterimage.spawn(player.rig, ActorFx.TUNING.afterimage_color, 8)
	image.set_physics_process(false)
	player.rig.visible = false
	await _draw()
	var with_image := _world(main)
	player.rig.visible = true
	var changed := ShotMasks.diff(with_image, empty, box)
	var outside := 0
	var missing := 0
	for p: Vector2i in changed:
		if not body.has(p):
			outside += 1
	for p: Vector2i in body:
		if not changed.has(p):
			missing += 1
	assert_true(body.size() > 500, "his silhouette (%d pixels)" % body.size())
	assert_true(float(outside) <= 0.02 * body.size(), "%d pixels of the copy are outside his silhouette (of %d)" % [outside, body.size()])
	assert_true(float(missing) <= 0.03 * body.size(), "%d pixels of his silhouette are missing from the copy (of %d)" % [missing, body.size()])
	image.free()


# The picture of the world with `actor` hidden and no afterimage: the empty yard.
func _picture_without(main: Main, actor: Actor) -> Image:
	actor.rig.visible = false
	_show_images(false)
	await _draw()
	var empty := _world(main)
	actor.rig.visible = true
	_show_images(true)
	return empty


func test_the_afterimage_is_gone_after_its_frames() -> void:
	var run := await _yard(OPEN)
	var main: Main = run["main"]
	var player := main.player
	var foe: Actor = run["foe"]
	_put(foe, Transform3D(Basis(Vector3.UP, PI), Vector3(-9.0, 0.0, 9.0)))
	var box := _box(main, OPEN)
	# Stepping aside and back changes his picture a little by itself (the body settles where it is put), so the picture to compare is
	# the one after a first such step with no afterimage, and the second step is the one that leaves a copy behind.
	var before := await _step_aside_and_back(main, null)
	var image := Afterimage.spawn(player.rig, ActorFx.TUNING.afterimage_color, 8)
	var seen := []
	_put(player, Transform3D(Basis.IDENTITY, OPEN + MOVED))
	for i in 10:
		await frames(1)
		seen.append(_images().size())
	assert_eq(seen.slice(0, 7), [1, 1, 1, 1, 1, 1, 1], "it stands for its frames")
	assert_eq(seen[9], 0, "and is gone after them")
	assert_false(is_instance_valid(image) and not image.is_queued_for_deletion(), "freed")
	_put(player, Transform3D(Basis.IDENTITY, OPEN))
	await frames(2)
	await _draw()
	var after := _world(main)
	var left_over := ShotMasks.diff(after, before, box, 0.0)
	assert_eq(left_over.size(), 0, "the picture is the one it was without a copy, to the pixel")


# The world's picture after Abarax has stepped to MOVED and back to OPEN, 10 frames each way, with `image` (an afterimage made before
# he moved, or none) left to its own devices.
func _step_aside_and_back(main: Main, image: Afterimage) -> Image:
	_put(main.player, Transform3D(Basis.IDENTITY, OPEN + MOVED))
	await frames(10)
	_put(main.player, Transform3D(Basis.IDENTITY, OPEN))
	await frames(2)
	await _draw()
	return _world(main)


# The afterimage on the yard's lit floor and on its dark floor: it shows on both (a pale copy that vanished against one of them would
# be an effect nobody sees). The picture of each goes to out/shots/chain/.
func test_the_afterimage_shows_on_the_lit_floor_and_the_dark() -> void:
	for place: Array in [["lit", LIT], ["dark", DARK]]:
		var run := await _yard(place[1])
		var main: Main = run["main"]
		var player := main.player
		var foe: Actor = run["foe"]
		_put(foe, Transform3D(Basis(Vector3.UP, PI), place[1] + Vector3(-8.0, 0.0, -8.0)))
		var box := _box(main, place[1])
		await _draw()
		var empty := await _picture_without(main, player)
		var image := Afterimage.spawn(player.rig, ActorFx.TUNING.afterimage_color, 8)
		image.set_physics_process(false)
		player.rig.visible = false
		await _draw()
		var with_image := _world(main)
		player.rig.visible = true
		var changed := ShotMasks.diff(with_image, empty, box, 0.06)
		var contrast := 0.0
		for p: Vector2i in changed:
			var a := with_image.get_pixelv(p)
			var b := empty.get_pixelv(p)
			contrast += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		var mean := contrast / maxf(changed.size(), 1.0)
		assert_true(changed.size() >= 300, "%s floor: the copy shows (%d pixels)" % [place[0], changed.size()])
		assert_true(mean >= 0.12, "%s floor: and clearly (its pixels differ from the floor by %.2f on average, summed over red, green, blue)" % [place[0], mean])
		_save(with_image, "afterimage_%s_floor" % place[0], box)
		image.free()
		main.queue_free()
		await frames(2)


# --- the afterimage in a real dodge ---

## The frames a dodge is followed for, and the floors: this many pixels outside every body on at least this many wall frames.
const FOLLOW := 45
const SEEN_PX := 60
const SEEN_FRAMES_SLOW := 6
const SEEN_FRAMES_FREE := 3


# One real dodge in the yard with `at` under the camera, Abarax's chain primed to `prime` plain links, the foe a metre in front of him
# throwing a blow (a straight one for a sway, a round one for a duck) that his press on wall frame 10 slips on frame 14; the pictures
# of the World viewport at each of the FOLLOW wall frames from the first, the slow-down and the afterimage as asked.
func _dodge_run(at: Vector3, action: StringName, prime: int, slow_on: bool, image_on: bool) -> Array[Image]:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	for light in main.region.find_children("*", "Light3D", true, false):
		(light as Light3D).shadow_enabled = false
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	var player := main.player
	player.set_brain(Brain.new())
	var held := Marker3D.new()
	main.region.add_child(held)
	held.global_position = at
	main.camera_rig.target = held
	_put(player, Transform3D(Basis.IDENTITY, at))
	_put(foe, Transform3D(Basis(Vector3.UP, PI), at + Vector3(0.0, 0.0, 1.0)))
	await frames(Rig.WARM_FRAMES + 3)
	main.camera_rig.snap_now()
	await frames(2)
	main.camera_rig.snap_now()
	var fx := player.get_node("ChainFx") as ChainFx
	fx.tuning = fx.tuning.duplicate() as ReadabilityTuning
	fx.tuning.afterimage_on = image_on
	player.chain_slow.tuning = fx.tuning
	fx.tuning.slowdown_on = slow_on
	for i in prime:
		player.chain.link(false, player.buffer_frame)
	Melee.slow(0, 1.0)
	await frames(2)
	for node in get_tree().get_nodes_in_group(Afterimage.GROUP):
		node.free()
	player.set_brain(ScriptBrain.new([{"frames": 9}, {"frames": 1, "press": [action]}, {"frames": 200}]))
	var pictures: Array[Image] = []
	for k in FOLLOW:
		if k == 12:
			Blows.post(foe, player, {"line": HitProfile.Line.ROUND} if action == &"duck" else {})
		await frames(1)
		await RenderingServer.frame_post_draw
		pictures.append(_world(main))
	assert_eq(player.chain.count, prime + 2, "the dodge was a perfect one (the chain: %d)" % player.chain.count)
	main.queue_free()
	await frames(2)
	return pictures


# The pixels each wall frame shows of the afterimage outside every body: the picture of a run with it less the picture of the same run without.
func _seen(with: Array[Image], without: Array[Image], box: Rect2i) -> Array[int]:
	var counts: Array[int] = []
	for k in with.size():
		counts.append(ShotMasks.diff(with[k], without[k], box).size())
	return counts


func test_the_afterimage_is_seen_in_real_dodges_through_the_slow_down() -> void:
	var lines := PackedStringArray()
	for case: Array in [[&"sway", 3, "quick"], [&"sway", 7, "flurry"], [&"duck", 3, "quick"], [&"duck", 7, "flurry"]]:
		for slow_on in [true, false]:
			var at := DARK
			var with := await _dodge_run(at, case[0], case[1], slow_on, true)
			var without := await _dodge_run(at, case[0], case[1], slow_on, false)
			var main_box := Rect2i(231, 60, 180, 170)
			var counts := _seen(with, without, main_box)
			var enough := counts.filter(func(n: int) -> bool: return n >= SEEN_PX).size()
			var label := "%s at %s, slow-down %s" % [case[0], case[2], "on" if slow_on else "off"]
			lines.append("%-34s px per wall frame: %s  (frames with >= %d px: %d)" % [label, str(counts), SEEN_PX, enough])
			assert_true(enough >= (SEEN_FRAMES_SLOW if slow_on else SEEN_FRAMES_FREE),
					"%s: the afterimage shows %d px or more on %d wall frames (at least %d): %s" % [label, SEEN_PX, enough, SEEN_FRAMES_SLOW if slow_on else SEEN_FRAMES_FREE, counts])
			if case[2] == "flurry" and slow_on:
				_save_strip(with, "dodge_%s_flurry_slow_dark" % case[0], main_box)
	var dir := ProjectSettings.globalize_path("res://").path_join("out/shots/chain")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("afterimage_pixels.txt"), FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")


func test_the_flurry_dodge_strip_on_the_lamplit_floor() -> void:
	for action: StringName in [&"sway", &"duck"]:
		var with := await _dodge_run(LIT, action, 7, true, true)
		_save_strip(with, "dodge_%s_flurry_slow_lit" % action, Rect2i(231, 60, 180, 170))


# Every second wall frame of `pictures`, the crop of `box` round the fighters, side by side, enlarged, to out/shots/chain/.
func _save_strip(pictures: Array[Image], name: String, box: Rect2i) -> void:
	var tile := Rect2i(box.position + Vector2i(45, 25), Vector2i(90, 100))
	var tiles := 12
	var strip := Image.create(tile.size.x * 6, tile.size.y * 2, false, Image.FORMAT_RGBA8)
	for i in tiles:
		var crop := pictures[10 + i * 2].get_region(tile)
		crop.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((i % 6) * tile.size.x, (i / 6) * tile.size.y))
	_save(strip, name)


# The Quick rim keeps the gold of the Flurry rim, on the dark ground and on the lamplit one, at about half its brightness.
func test_the_quick_rim_keeps_its_gold_hue_on_the_dark_floor_and_the_lamplit() -> void:
	for place: Array in [["dark", DARK], ["lit", LIT]]:
		var run := await _yard(place[1])
		var main: Main = run["main"]
		var player := main.player
		var foe: Actor = run["foe"]
		_put(foe, Transform3D(Basis(Vector3.UP, PI), place[1] + Vector3(-8.0, 0.0, -8.0)))
		var box := _box(main, place[1])
		await _draw()
		var without := _world(main)
		var rims := {}
		for tempo: Array in [["quick", 3], ["flurry", 7]]:
			player.chain.end()
			for i in tempo[1]:
				player.chain.link(false, player.buffer_frame)
			await frames(2)
			await _draw()
			var with := _world(main)
			var changed := ShotMasks.diff(with, without, box)
			var sum := Vector3.ZERO
			var n := 0
			for p: Vector2i in changed:
				var c := with.get_pixelv(p)
				if maxf(c.r, maxf(c.g, c.b)) > 0.12:
					sum += Vector3(c.r, c.g, c.b)
					n += 1
			assert_true(n >= 30, "%s floor, %s: the rim has pixels (%d)" % [place[0], tempo[0], n])
			var mean := Color(sum.x / maxf(n, 1.0), sum.y / maxf(n, 1.0), sum.z / maxf(n, 1.0))
			rims[tempo[0]] = mean
			var hue_off := absf(wrapf(mean.h * 360.0 - GOLD.h * 360.0, -180.0, 180.0))
			assert_true(hue_off <= 15.0, "%s floor, %s: the rim's hue is %.0f deg, the gold's is %.0f (within 15)" % [place[0], tempo[0], mean.h * 360.0, GOLD.h * 360.0])
		var quick: Color = rims["quick"]
		var flurry: Color = rims["flurry"]
		assert_true(quick.v < flurry.v * 0.8 and quick.v > flurry.v * 0.3, "%s floor: the Quick rim is dimmer than the Flurry's (%.2f against %.2f)" % [place[0], quick.v, flurry.v])
		main.queue_free()
		await frames(2)
