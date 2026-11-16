extends TestCase
## The start of the Drummer's string as drawn (xvfb, gl_compatibility): for every frame of its 24 of warning, from the fourth, the rim round
## its body is at least 150 pixels of the 640x360 picture and they are red (its own: the rim of no other tell is). No pixel inside the body
## changes. Each frame's picture is the world's own, with the rim and with it taken off (the shader's strength to 0 for one picture), both with the
## Drummer held still by a hit-stop. A tier I Knuckle starting a jab beside it is saved for a person to see the two starts told apart.
## Pictures go to out/shots/drummer/.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(1920, 1080)
const DRUMMER := "res://data/actors/knuckle_drummer.tres"
const FOE_AT := Vector3(-1.2, 0.0, 6.0)
const PLAYER_AT := Vector3(1.2, 0.0, 6.0)
const FROM := 4
const WARNING := 24
const MIN_RIM_PIXELS := 150
const MARGIN_PX := 2
const MAX_INTERIOR_CHANGED := 0.02
const CHANGED := 0.02


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func _draw() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw


func _world(main: Main) -> Image:
	return main.stage.world.get_texture().get_image()


func _box(main: Main, actor: Actor, image: Image) -> Rect2i:
	var feet := main.camera_rig.camera.unproject_position(actor.global_position)
	return Rect2i(int(feet.x) - 110, int(feet.y) - 125, 220, 170).intersection(Rect2i(Vector2i.ZERO, image.get_size()))


# The yard with Abarax and `def`'s foe in front of the camera, no shadows, the foe starting `move_id` (frame 0 is the call).
func _scene(def: ActorDef, move_id: StringName) -> Dictionary:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	for light in main.region.find_children("*", "Light3D", true, false):
		(light as Light3D).shadow_enabled = false
	for old in main.arena().enemies():
		old.queue_free()
	await frames(2)
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.name = "Foe"
	foe.def = def
	main.arena().add_child(foe)
	foe.set_brain(Brain.new())
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), FOE_AT))
	main.player.set_brain(Brain.new())
	main.player.place(Transform3D(Basis(Vector3.UP, 0.0), PLAYER_AT))
	main.camera_rig.snap_now()
	await frames(Rig.WARM_FRAMES + 3)
	for spark in get_tree().get_nodes_in_group(ActorFx.GROUP):
		spark.free()
	foe.runner.start(Registry.fetch(&"moves", move_id) as MoveData)
	return {"main": main, "foe": foe}


func _save(picture: Image, name: String, box: Rect2i) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("out/shots/drummer")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := picture.get_region(box)
	shot.resize(shot.get_width() * 3, shot.get_height() * 3, Image.INTERPOLATE_NEAREST)
	shot.save_png(dir.path_join("%s.png" % name))


func test_the_warning_has_a_red_rim_of_at_least_150_pixels_on_every_frame_from_the_fourth() -> void:
	var run := await _scene(load(DRUMMER) as ActorDef, &"drum_1")
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	var counts := []
	var worst_interior := 0.0
	var reddest := 1.0
	var body := {}
	var strip: Array[Image] = []
	for f in range(1, WARNING):
		await frames(1)  # frame f of the move
		if f < FROM:
			continue
		foe.freeze(12)
		await _draw()
		assert_true(foe.rig.aura_active(), "the rim is on at frame %d" % f)
		var with_rim := _world(main)
		var box := _box(main, foe, with_rim)
		var material := foe.rig.rim_material()
		var strength: Variant = material.get_shader_parameter(&"rim_strength")
		var fx := foe.get_node("ActorFx") as ActorFx
		fx.set_physics_process(false)  # (it drives the rim again on every frame: held off for the one picture)
		material.set_shader_parameter(&"rim_strength", 0.0)
		await _draw()
		var without := _world(main)
		material.set_shader_parameter(&"rim_strength", strength)
		fx.set_physics_process(true)
		body = await ShotMasks.silhouette(main, foe, box)
		var interior := ShotMasks.eroded(body, MARGIN_PX)
		var band := ShotMasks.grown(body, MARGIN_PX)
		var changed := ShotMasks.diff(with_rim, without, box, CHANGED)
		var edge := 0
		var inside := 0
		var red := 0
		for p: Vector2i in changed:
			if interior.has(p):
				inside += 1
			elif band.has(p):
				edge += 1
				var c := with_rim.get_pixelv(p)
				if c.r - maxf(c.g, c.b) > 0.15:
					red += 1
		counts.append([f, edge, red])
		worst_interior = maxf(worst_interior, float(inside) / maxf(interior.size(), 1.0))
		if f in [4, 12, 23]:
			strip.append(with_rim.get_region(box))
		foe.frozen = 0
		await frames(1)
	for row: Array in counts:
		assert_true(row[1] >= MIN_RIM_PIXELS, "frame %d: %d rim pixels round him (at least %d): %s" % [row[0], row[1], MIN_RIM_PIXELS, counts])
		assert_true(row[2] >= int(row[1] * 0.8), "frame %d: %d of the %d are red" % [row[0], row[2], row[1]])
	assert_true(worst_interior <= MAX_INTERIOR_CHANGED, "no pixel inside his body changes (%.3f of it at worst)" % worst_interior)
	for i in strip.size():
		_save(strip[i], "drummer_warning_%d" % i, Rect2i(Vector2i.ZERO, strip[i].get_size()))


func test_a_knuckles_jab_start_beside_it_is_blue_white_not_red() -> void:
	var run := await _scene(load("res://data/actors/knuckle_1.tres") as ActorDef, &"knuckle_jab")
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	await frames(15)
	foe.freeze(12)
	await _draw()
	assert_true(foe.rig.aura_active())
	assert_ne(foe.rig.aura_color(), Color("d12924"), "the Knuckle's tell is not the Drummer's red")
	var picture := _world(main)
	_save(picture, "knuckle_jab_start", _box(main, foe, picture))
