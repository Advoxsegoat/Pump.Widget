extends TestCase
## What the stretch costs to draw (xvfb, gl_compatibility): the container has no GPU, so the spec's 60 fps at 1920 x 1080 on a GTX 1060 class
## machine is held by proxies, and this is the drawing half (tests/perf/test_bilibara_budget.gd is the physics step). At every one of the views, with two
## bodies in it (Abarax and a tier I Knuckle, as the owner's pictures) and with eight (Abarax and seven foes), and a pile of petals 3 m off (and the count on the Hud), the frame's draw calls are at most 450
## and its primitives at most 400,000: the whole of the frame as the renderer counts it (RENDERING_INFO_TOTAL_*_IN_FRAME: the stage's world, the
## shadow pass, the screen's own quads). The views are the nine of test_bilibara_view and its four more (the loop lane, the lane's north end, the street's
## middle, the colonnade), and the 26 reference positions of the readability tests (14 and 12 more): read from those files' constants, so that a place added
## there is measured here. Every number goes to out/shots/bilibara_cost.txt, the heaviest view named.

const MAIN := "res://main/main.tscn"
const FOE := "res://data/actors/knuckle_1.tres"
const VIEW_TEST := "res://tests/render/test_bilibara_view.gd"
const READ_TESTS: Array[String] = ["res://tests/render/test_bilibara_readability.gd", "res://tests/render/test_bilibara_readability_more.gd"]
const OUT := "out/shots/bilibara_cost.txt"
const MOST_DRAWS := 450
const MOST_PRIMITIVES := 400000
const CROWD := 7
## Frames a view is given to settle (the camera snaps, the picture is drawn) before the frame is counted.
const SETTLE := 10


func after_each() -> void:
	Game.reset()


func _constants(path: String) -> Dictionary:
	return (load(path) as GDScript).get_script_constant_map()


## The views as {name, at (a Transform3D)}: markers of the scene by name, and the places given as points.
func _views(region: Region) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var view := _constants(VIEW_TEST)
	for marker_name: String in view["VIEWS"]:
		list.append({name = marker_name, at = (region.find_child(marker_name, true, false) as Marker3D).global_transform})
	for view_name: String in view["EXTRA_VIEWS"]:
		list.append({name = view_name, at = Transform3D(Basis(), view["EXTRA_VIEWS"][view_name])})
	for path in READ_TESTS:
		for entry: Array in _constants(path)["POSITIONS"]:
			list.append({name = String(entry[0]), at = Transform3D(Basis(), Vector3(entry[1], 0.0, entry[2]))})
	return list


func _count() -> Vector2i:
	return Vector2i(
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))


func test_every_reference_view_is_inside_the_draw_budget() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	var region := main.region
	main.player.set_brain(Brain.new())
	var foes: Array[Actor] = []
	for i in 1 + CROWD:
		var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
		foe.def = load(FOE) as ActorDef
		foe.set_brain(Brain.new())
		region.add_child(foe)
		foes.append(foe)
	var views := _views(region)
	assert_true(views.size() >= 39, "the views are found (%d)" % views.size())
	var lines := PackedStringArray(["view | draw calls / primitives with two bodies | with eight bodies"])
	var problems := PackedStringArray()
	var heaviest := {name = "", draws = 0, primitives = 0, bodies = 0}
	for view: Dictionary in views:
		var row := PackedStringArray()
		for bodies: int in [2, 8]:
			var at: Transform3D = view.at
			main.player.place(at)
			# A pile of petals lies three metres off (a death's: the run draws it, the count is on the Hud): the frame is counted with it in.
			main.stretch.data.petals = 120
			main.stretch.petals.fall_at(at.origin + Vector3(-3.0, 0.0, -1.5))
			# The foes: the first two metres east of Abarax; the rest in a ring 1.5 m round him (as test_bilibara_view's eight).
			for i in foes.size():
				var shown: bool = i < int(bodies) - 1
				foes[i].visible = shown
				var spot := at.origin + Vector3(0.0, -50.0, 0.0)  # a foe not in this view stands far under the ground, hidden
				if shown:
					spot = at.origin + (Vector3(2.0, 0.0, 0.0) if i == 0 else Vector3(1.5, 0.0, 0.0).rotated(Vector3.UP, TAU * i / float(CROWD) + 0.4))
				foes[i].place(Transform3D(Basis(Vector3.UP, -PI / 2), spot))
			main.camera_rig.snap_now()
			await frames(SETTLE)
			await RenderingServer.frame_post_draw
			var got := _count()
			row.append("%d / %d" % [got.x, got.y])
			if got.x > heaviest.draws:
				heaviest = {name = view.name, draws = got.x, primitives = got.y, bodies = bodies}
			if got.x <= 0 or got.x > MOST_DRAWS:
				problems.append("%s with %d bodies: %d draw calls (at most %d)" % [view.name, bodies, got.x, MOST_DRAWS])
			if got.y <= 0 or got.y > MOST_PRIMITIVES:
				problems.append("%s with %d bodies: %d primitives (at most %d)" % [view.name, bodies, got.y, MOST_PRIMITIVES])
		lines.append("%s | %s | %s" % [view.name, row[0], row[1]])
	lines.append("heaviest by draw calls: %s with %d bodies: %d draw calls, %d primitives" % [heaviest.name, heaviest.bodies, heaviest.draws, heaviest.primitives])
	var path := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_true(file != null, "%s can be written" % path)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	print("bilibara cost: %s" % "; ".join(lines))
	assert_eq(problems.slice(0, 12), PackedStringArray(), "every view is inside %d draw calls and %d primitives (%d problems; the table is %s)" % [MOST_DRAWS, MOST_PRIMITIVES, problems.size(), OUT])
