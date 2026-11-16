extends TestCase
## The Bilibara stretch as the game draws it (xvfb, gl_compatibility): the stage's 640x360 picture from the game's camera at six
## places, Abarax standing at each marker with a tier I Knuckle two metres east of him, saved to out/shots/bilibara/ for a
## person to look at (bilibara_<marker>.png). Each is a real picture, and none takes more draw calls than the plan's budget of 450.

const MAIN := "res://main/main.tscn"
const ABARAX_FOE := "res://data/actors/knuckle_1.tres"
const SHOTS := "out/shots/bilibara/"
const SIZE := Vector2i(1920, 1080)
const MARKERS: Array[String] = ["Spawn", "StreetEast", "LaneMid", "RackWest", "GateFar", "YardEntry"]
## The plan's most draw calls in any frame (its Global Constraints), and the least colours a drawn picture has.
const MOST_DRAWS := 450
const LEAST_COLOURS := 12


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_six_views_of_the_stretch() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	var region := main.region
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.def = load(ABARAX_FOE) as ActorDef
	foe.set_brain(Brain.new())
	region.add_child(foe)
	main.player.set_brain(Brain.new())
	var worst := 0
	for marker_name in MARKERS:
		var at := (region.get_node(marker_name) as Marker3D).global_transform
		main.player.place(at)
		foe.place(Transform3D(Basis(Vector3.UP, -PI / 2), at.origin + Vector3(2.0, 0.0, 0.0)))
		main.camera_rig.snap_now()
		await frames(12)
		for i in 4:
			await RenderingServer.frame_post_draw
		var full := main.stage.world.get_texture().get_image()
		var picture := full.get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
		var path := ProjectSettings.globalize_path("res://").path_join(SHOTS + "bilibara_%s.png" % marker_name.to_snake_case())
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		assert_eq(picture.save_png(path), OK, "saved %s" % path)
		var colours := {}
		for y in range(0, 360, 2):
			for x in range(0, 640, 2):
				colours[picture.get_pixel(x, y).to_rgba32()] = true
		assert_true(colours.size() >= LEAST_COLOURS, "%s: a real picture (%d colours)" % [marker_name, colours.size()])
		var draws := RenderingServer.viewport_get_render_info(main.stage.world.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		worst = maxi(worst, draws)
		print("bilibara shot %s: %d draw calls" % [marker_name, draws])
		assert_true(draws > 0 and draws <= MOST_DRAWS, "%s: %d draw calls (at most %d)" % [marker_name, draws, MOST_DRAWS])


## Two pictures for a person to look at beside the nine views (out/shots/bilibara/): court A from the spawn (court_a_x3.png: the first ground the owner sees) and the
## yard's middle with three foes in a fight and a parry rim showing (yard_fight_x3.png), at 1920 x 1080 (the 640 x 360 picture at three times its size).
func test_court_a_and_a_fight_in_the_yard() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	var region := main.region
	main.player.set_brain(Brain.new())
	var foes: Array[Actor] = []
	for i in 3:
		var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
		foe.def = load(ABARAX_FOE) as ActorDef
		foe.set_brain(Brain.new())
		region.add_child(foe)
		foes.append(foe)
	# Court A from the spawn: Abarax at the Spawn marker, the foes far off.
	var spawn := (region.get_node("Spawn") as Marker3D).global_transform
	main.player.place(spawn)
	for foe in foes:
		foe.place(Transform3D(Basis(), Vector3(0.0, 0.0, 3.0)))
	main.camera_rig.snap_now()
	await frames(10)
	for i in 4:
		await RenderingServer.frame_post_draw
	_save_x3(main, "court_a")
	# The yard's middle, Abarax and three foes round him, one in its parry tell (the rim).
	var centre := Vector3(27.5, 0.0, -65.0)
	main.player.place(Transform3D(Basis(Vector3.UP, PI / 2), centre))
	var spots := [Vector3(-1.6, 0.0, -0.3), Vector3(1.3, 0.0, -1.5), Vector3(1.2, 0.0, 1.4)]
	for i in 3:
		foes[i].place(Transform3D(Basis(Vector3.UP, PI / 2 if i == 0 else (-PI / 2 if i == 1 else PI)), centre + spots[i]))
	main.camera_rig.snap_now()
	await frames(8)
	foes[0].runner.start(Registry.fetch(&"moves", &"knuckle_jab") as MoveData)
	await frames(15)
	for foe in foes:
		foe.freeze(100000)
	main.player.freeze(100000)
	await frames(2)
	for i in 4:
		await RenderingServer.frame_post_draw
	_save_x3(main, "yard_fight")


func _save_x3(main: Main, file: String) -> void:
	var full := main.stage.world.get_texture().get_image()
	var picture := full.get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
	var base := ProjectSettings.globalize_path("res://").path_join(SHOTS + file)
	DirAccess.make_dir_recursive_absolute(base.get_base_dir())
	assert_eq(picture.save_png(base + ".png"), OK, "saved %s.png" % file)
	var big := picture.duplicate() as Image
	big.resize(1920, 1080, Image.INTERPOLATE_NEAREST)
	assert_eq(big.save_png(base + "_x3.png"), OK, "saved %s_x3.png" % file)
