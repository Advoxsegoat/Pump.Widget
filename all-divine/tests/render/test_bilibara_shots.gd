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
