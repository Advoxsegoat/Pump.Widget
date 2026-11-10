extends TestCase
## The training yard as the game shows it (xvfb, gl_compatibility): the main scene at 1920x1080 with a tier I Knuckle in
## view, saved to out/shots/yard.png for a person to look at. It renders without errors, is a real picture, shows the HUD
## (its rose HP bar sits at the bottom left, in the HUD's own colour: no grade touches it), and the ground a lantern lights
## is brighter than the ground in the dark between the lanterns.

const MAIN := "res://main/main.tscn"
const SHOT := "out/shots/yard.png"
const SIZE := Vector2i(1920, 1080)
## A lantern's (layout.txt: (-9.5, 8)) and the ground 1.5 m from it toward the middle of the yard, and the dark ground by the
## spawn, which no lamp (range 6 m) reaches.
const LIT := Vector3(-8.0, 0.0, 7.0)
const DARK := Vector3(0.0, 0.0, 3.0)
## The box measured round a ground point, in window pixels.
const PATCH := 24


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_yard_shot() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	# Long enough for the shadows to be drawn and the Knuckle to have walked into view.
	await frames(90)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	assert_eq(img.get_size(), SIZE, "the test needs a 1920x1080 window")
	var path := ProjectSettings.globalize_path("res://").path_join(SHOT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(img.save_png(path), OK, "saved %s" % path)
	var colours := {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			colours[img.get_pixel(x, y).to_rgba32()] = true
	assert_true(colours.size() > 40, "the picture has %d colours" % colours.size())
	var foes := main.arena().enemies()
	assert_eq(foes.size(), 1, "a tier I Knuckle")
	assert_true(main.camera_rig.on_screen(foes[0].global_position), "in view")
	# The HUD's HP bar: its fill is the HUD's rose, exactly, at the bottom left (a 3x3 block of the 6x scale... 3x here).
	var k := PixelStage.scale_for(SIZE)
	var origin := PixelStage.layout(SIZE).position
	var hp := main.hud.hp_rect()
	var at := origin + (hp.position + hp.size / 2) * k
	var shown := img.get_pixelv(at)
	assert_true(absf(shown.r - Hud.ROSE.r) < 0.02 and absf(shown.g - Hud.ROSE.g) < 0.02 and absf(shown.b - Hud.ROSE.b) < 0.02,
			"the HP bar is the HUD's rose, ungraded: %s vs %s" % [shown.to_html(false), Hud.ROSE.to_html(false)])
	var lit := _brightness(img, main, LIT)
	var dark := _brightness(img, main, DARK)
	assert_true(lit > dark * 1.15, "the lantern-lit ground (%.3f) is brighter than the dark ground (%.3f)" % [lit, dark])


# The mean luma of the PATCH box round the ground point `at`, in the picture.
func _brightness(img: Image, main: Main, at: Vector3) -> float:
	var stage := main.stage
	var k := PixelStage.scale_for(SIZE)
	var corner := Vector2(PixelStage.layout(SIZE).position + PixelStage.draw_offset(stage.subpixel, k))
	var pixel := corner + main.camera_rig.camera.unproject_position(at) * k
	var total := 0.0
	var count := 0
	for y in range(int(pixel.y) - PATCH / 2, int(pixel.y) + PATCH / 2):
		for x in range(int(pixel.x) - PATCH / 2, int(pixel.x) + PATCH / 2):
			var c := img.get_pixel(clampi(x, 0, SIZE.x - 1), clampi(y, 0, SIZE.y - 1))
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			count += 1
	return total / count


# The HUD in play: locked on to a Knuckle that has been hit and whose posture is broken, in reach, with the finisher
# prompt up and the unblockable icon of another foe's sweep: saved to out/shots/yard_hud.png for a person to look at.
func test_the_hud_in_a_fight_shot() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().start_wave(3)  # a tier II and a tier I
	var foes := main.arena().enemies()
	for foe in foes:
		foe.set_brain(Brain.new())
	var player := main.player
	player.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 6.0)))
	foes[0].place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, 0.0, 4.9)))
	foes[1].place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(-3.5, 0.0, 3.0)))
	main.camera_rig.snap_now()
	await frames(5)
	player.set_brain(PlayerBrain.new())
	(player.brain as PlayerBrain).lock.target = foes[0]
	foes[0].stats.take_damage(20.0)
	foes[0].stats.damage_posture(foes[0].stats.max_posture)
	foes[0].add_to_group(Actor.FINISHABLE_GROUP)
	foes[0].got_hit.emit(HitResult.new(), _event(foes[0]))
	foes[1].runner.start(Registry.fetch(&"moves", &"knuckle_thrust") as MoveData)
	player.stats.take_damage(35.0)
	player.stats.spend_stamina(30.0)
	player.stats.damage_posture(30.0)
	await frames(12)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://").path_join("out/shots/yard_hud.png")
	assert_eq(img.save_png(path), OK)
	assert_true(main.hud.reticle_at() is Vector2i, "the reticle is up")
	assert_true(main.hud.prompt_at() is Vector2i, "and the finisher prompt")
	assert_eq(main.hud.icons().size(), 1, "and one unblockable icon")


func _event(target: Actor) -> HitEvent:
	var e := HitEvent.new()
	e.target = target
	e.profile = HitProfile.new()
	e.point = target.global_position + Vector3.UP
	return e


# How many pixels Abarax's body shows on in the World image with him at `at` (idle, frozen): his silhouette, exactly.
func _body_pixels(at: Vector3) -> int:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	for light in main.region.find_children("*", "Light3D", true, false):
		(light as Light3D).shadow_enabled = false
	main.arena().clear_foes()
	main.arena().automatic = false
	main.player.place(Transform3D(Basis(Vector3.UP, PI), at))
	main.camera_rig.snap_now()
	await frames(10)
	main.player.freeze(100000)
	for i in 3:
		await RenderingServer.frame_post_draw
	var feet := Vector2i(main.camera_rig.camera.unproject_position(main.player.global_position).round())
	var box := Rect2i(feet.x - 40, feet.y - 80, 80, 100).intersection(Rect2i(Vector2i.ZERO, main.stage.world.size))
	var count := (await ShotMasks.silhouette(main, main.player, box)).size()
	main.queue_free()
	await frames(1)
	return count


func test_the_south_edge_hides_no_more_than_the_feet() -> void:
	var open := await _body_pixels(Vector3(0.0, 0.0, 6.0))
	assert_true(open > 300, "Abarax shows %d pixels in the open" % open)
	# In the gate, between its pillars, and along the kerb away from it.
	for x: float in [0.0, -5.0]:
		var at_edge := await _body_pixels(Vector3(x, 0.0, 12.5 - 0.36))
		assert_true(at_edge >= 0.9 * open, "at 0.36 m from the south edge (x %.0f) %d of his %d pixels show" % [x, at_edge, open])


# The south edge is a barrier to see: its kerb stands out from the floor before it all along, in the dark of the middle and
# in the lamps' pools toward the corners, by 20 luma or more in the World picture (in the dark it is the paler, under a
# lamp the darker of the two).
func test_the_south_kerb_shows_against_the_floor() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().clear_foes()
	main.arena().automatic = false
	main.player.set_brain(Brain.new())
	for x: float in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		main.player.place(Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.0, 9.5)))
		main.camera_rig.snap_now()
		await frames(10)
		main.camera_rig.snap_now()
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := main.stage.world.get_texture().get_image()
		if is_zero_approx(x):
			assert_eq(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("out/shots/yard_south_edge.png")), OK)
		# Two spots a metre and a half either side of him: the kerb's top there, and the floor 1.2 m before it.
		for side: float in [-1.5, 1.5]:
			var kerb := _patch_luma(img, main, Vector3(x + side, 0.3, 12.7))
			var ground := _patch_luma(img, main, Vector3(x + side, 0.0, 11.3))
			assert_true(absf(kerb - ground) >= 20.0, "at x %.1f the kerb (luma %.1f) differs from the floor before it (%.1f) by 20 or more" % [x + side, kerb, ground])


# The mean luma of the 5 x 3 pixels of the World picture round the world point `at`.
func _patch_luma(img: Image, main: Main, at: Vector3) -> float:
	var centre := Vector2i(main.camera_rig.camera.unproject_position(at).round())
	var sum := 0.0
	var count := 0
	for dy in range(-1, 2):
		for dx in range(-2, 3):
			var p := (centre + Vector2i(dx, dy)).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)
			sum += _luma(img.get_pixelv(p))
			count += 1
	return sum / count


# The mean colour of the PATCH box round the ground point `at`.
func _mean_colour(img: Image, main: Main, at: Vector3) -> Color:
	var k := PixelStage.scale_for(SIZE)
	var corner := Vector2(PixelStage.layout(SIZE).position + PixelStage.draw_offset(main.stage.subpixel, k))
	var pixel := corner + main.camera_rig.camera.unproject_position(at) * k
	var sum := Vector3.ZERO
	var count := 0
	for y in range(int(pixel.y) - PATCH / 2, int(pixel.y) + PATCH / 2):
		for x in range(int(pixel.x) - PATCH / 2, int(pixel.x) + PATCH / 2):
			var c := img.get_pixel(clampi(x, 0, SIZE.x - 1), clampi(y, 0, SIZE.y - 1))
			sum += Vector3(c.r, c.g, c.b)
			count += 1
	sum /= count
	return Color(sum.x, sum.y, sum.z)


func test_the_lantern_lit_ground_is_warm() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(60)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var lit := _mean_colour(img, main, LIT)
	var dark := _mean_colour(img, main, DARK)
	assert_true(lit.h * 360.0 >= 20.0 and lit.h * 360.0 <= 50.0, "the lantern-lit ground is warm: hue %.0f (want 20 to 50), colour %s" % [lit.h * 360.0, lit.to_html(false)])
	assert_true(lit.s > 0.15, "and not grey (saturation %.2f)" % lit.s)
	assert_true(dark.h * 360.0 > 190.0 and dark.h * 360.0 < 250.0, "while the dark ground stays a cool blue (hue %.0f)" % (dark.h * 360.0))


# The Rec. 709 luma of a colour as stored in the picture, 0 to 255.
func _luma(c: Color) -> float:
	return 255.0 * (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)


# How `actor`'s body stands out in the World picture `img`: {body, ground, spread}. `body` is the mean luma of its pixels
# (its silhouette less the outermost pixel, which the screen look draws as an outline); `ground` the median luma of the
# ground beside it, 3 to 8 pixels from its silhouette, off `other`'s body (the median leaves out its own shadow and the
# lines between the stones); `spread` how far apart the body's lit and dark sides are, its 90th less its 10th percentile.
func _standing_out(main: Main, img: Image, actor: Actor, other: Actor) -> Dictionary:
	var feet := Vector2i(main.camera_rig.camera.unproject_position(actor.global_position).round())
	var box := Rect2i(feet.x - 40, feet.y - 80, 80, 100).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var body := await ShotMasks.silhouette(main, actor, box)
	var other_body := await ShotMasks.silhouette(main, other, box)
	var inner: Array[float] = []
	for p: Vector2i in ShotMasks.eroded(body, 1):
		inner.append(_luma(img.get_pixelv(p)))
	inner.sort()
	var near := ShotMasks.grown(body, 2)
	var beside: Array[float] = []
	for p: Vector2i in ShotMasks.grown(body, 8):
		if not near.has(p) and not other_body.has(p) and box.has_point(p):
			beside.append(_luma(img.get_pixelv(p)))
	beside.sort()
	var sum := 0.0
	for l in inner:
		sum += l
	return {body = sum / maxf(inner.size(), 1.0), ground = beside[beside.size() / 2], pixels = inner.size(),
			spread = inner[inner.size() * 9 / 10] - inner[inner.size() / 10]}


# Between the lantern pools the fighters must not sink into the floor: the outfits are the first thing to see. Mid-yard,
# where no lamp reaches, a Knuckle's and Abarax's bodies each differ from the ground beside them by 30 luma or more in the
# World picture, and still have a lit and a dark side (the toon shading is not flattened into one tone).
func test_the_fighters_stand_out_between_the_lantern_pools() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	main.player.set_brain(Brain.new())
	foe.place(Transform3D(Basis.IDENTITY, DARK + Vector3(-1.2, 0.0, 0.0)))
	main.player.place(Transform3D(Basis.IDENTITY, DARK + Vector3(1.2, 0.0, 0.0)))
	main.camera_rig.snap_now()
	await frames(30)
	foe.freeze(100000000)
	main.player.freeze(100000000)
	main.camera_rig.snap_now()
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := main.stage.world.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://").path_join("out/shots/yard_between_pools.png")
	assert_eq(get_viewport().get_texture().get_image().save_png(path), OK)
	var world_640 := img.get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
	assert_eq(world_640.save_png(path.replace(".png", "_640.png")), OK)
	for pair: Array in [["the Knuckle", foe, main.player], ["Abarax", main.player, foe]]:
		var seen := await _standing_out(main, img, pair[1], pair[2])
		assert_true(seen.pixels > 200, "%s shows (%d pixels)" % [pair[0], seen.pixels])
		assert_true(absf(seen.body - seen.ground) >= 30.0, "%s differs from the ground beside by 30 luma or more: body %.1f, ground %.1f (%+.1f)" % [
				pair[0], seen.body, seen.ground, seen.body - seen.ground])
		assert_true(seen.body > seen.ground, "%s is the brighter of the two: an outfit to see, not a dark shape" % pair[0])
		assert_true(seen.spread >= 30.0, "%s has a lit side and a dark side still (its luma spreads over %.1f)" % [pair[0], seen.spread])
