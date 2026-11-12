class_name StandBeside
extends SceneTree
## Actors standing side by side in the game's own picture (640x360, the gameplay camera, no screen look), on a dark floor and a
## lamplit one, to see what a body looks like next to the others: a heavy man standing still, a wind-up beside another's.
##
##   tools/godot.sh --render -s res://tools/sheets/stand_beside.gd -- --out out/shots/heavy/x.png \
##       --actors abarax,knuckle_1:knuckle_jab@12,knuckle_heavy:heavy_haymaker@30+0.03 [--floors dark,lit] [--zoom 2] [--turn 0]
##
## Each actor is `<def>[:<clip>[@<frame>]][+<inflate>]`: the def's id (data/actors/<id>.tres), the clip it holds (idle by default) at the
## frame (0), and a body_inflate in metres that replaces the def's own (`+0` draws the model as built). A row per floor, each cell
## the whole group cut out of the picture and drawn ZOOM times larger, one to a column per `--frames a,b,c`: with several frames the
## clips are shown at each of them in turn (a wind-up from its glint to its blow), the frame numbers counting from each clip's own
## start, and an actor's `@frame` is then an offset added to each. `--turn` turns every actor that many eighths of a turn about the
## vertical (0 faces the camera's side as the game's actors do at rest). Exits 0 when the picture is written.

const STAGE := preload("res://render/pixel_stage.tscn")
const FLOORS := {"dark": Color(0.07, 0.07, 0.085), "lit": Color(0.46, 0.4, 0.3)}
## The settling ticks before a frame is drawn: what hangs off the body (a scarf) has come to rest.
const SETTLE_TICKS := 30
## Where the group is cut out: the picture around its middle, this size in game pixels.
const CELL := Vector2i(300, 150)
## How far apart the actors stand, in metres.
const SPACING := 1.7


func _initialize() -> void:
	var code := await _run(OS.get_cmdline_user_args())
	quit(code)


func _run(args: PackedStringArray) -> int:
	var out := ""
	var specs := PackedStringArray()
	var floors := PackedStringArray(["dark", "lit"])
	var frames := PackedInt32Array([0])
	var zoom := 2
	var turn := 0
	var cell := CELL
	var i := 0
	while i + 1 < args.size():
		match args[i]:
			"--out":
				out = args[i + 1]
			"--actors":
				specs = args[i + 1].split(",", false)
			"--floors":
				floors = args[i + 1].split(",", false)
			"--frames":
				frames = PackedInt32Array(Array(args[i + 1].split(",", false)).map(func(s: String) -> int: return int(s)))
			"--zoom":
				zoom = int(args[i + 1])
			"--turn":
				turn = int(args[i + 1])
			"--cell":
				var parts := args[i + 1].split("x")
				cell = Vector2i(int(parts[0]), int(parts[1]))
			_:
				printerr("stand_beside.gd: unknown argument '%s'" % args[i])
				return 2
		i += 2
	if out == "" or specs.is_empty():
		printerr("usage: tools/godot.sh --render -s res://tools/sheets/stand_beside.gd -- --out <file.png> --actors <def[:clip[@frame]][+inflate]>,... [--floors dark,lit] [--frames 0,10,20] [--zoom 2] [--turn 0] [--cell 300x150]")
		return 2
	if DisplayServer.get_name() == "headless":
		printerr("stand_beside.gd: needs a display; run it with tools/godot.sh --render")
		return 1
	if not root.is_inside_tree():
		await process_frame
	var rows: Array[Image] = []
	for floor_id in floors:
		var row: Array[Image] = []
		for frame in frames:
			row.append(await _picture(specs, FLOORS[floor_id], frame, turn, cell))
		rows.append(_join(row, zoom))
	var sheet := Image.create(rows[0].get_width(), rows[0].get_height() * rows.size(), false, Image.FORMAT_RGB8)
	for r in rows.size():
		sheet.blit_rect(rows[r], Rect2i(Vector2i.ZERO, rows[r].get_size()), Vector2i(0, r * rows[0].get_height()))
	var path := out
	if path.is_relative_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if sheet.save_png(path) != OK:
		printerr("stand_beside.gd: cannot write '%s'" % path)
		return 1
	print("stand_beside.gd: wrote %s (%dx%d)" % [path, sheet.get_width(), sheet.get_height()])
	return 0


# One picture of the group on a floor of `floor_colour`, each held `offset` frames past its own start.
func _picture(specs: PackedStringArray, floor_colour: Color, offset: int, turn: int, cell: Vector2i) -> Image:
	var stage := STAGE.instantiate() as PixelStage
	stage.visible = false
	root.add_child(stage)
	ContactSheet._furnish(stage.world)
	var ground: StandardMaterial3D = null
	for child in stage.world.get_children():
		if child is DirectionalLight3D:
			(child as DirectionalLight3D).shadow_enabled = true
		elif child is MeshInstance3D:
			ground = (child as MeshInstance3D).material_override as StandardMaterial3D
	ground.albedo_color = floor_colour
	var middle := Node3D.new()
	stage.world.add_child(middle)
	var rigs: Array[Rig] = []
	var clips: Array[StringName] = []
	var starts: Array[int] = []
	for n in specs.size():
		var spec := specs[n]
		var inflate := NAN
		if "+" in spec:
			inflate = float(spec.get_slice("+", 1))
			spec = spec.get_slice("+", 0)
		var clip := &"idle"
		var at := 0
		if ":" in spec:
			var rest := spec.get_slice(":", 1)
			spec = spec.get_slice(":", 0)
			clip = StringName(rest.get_slice("@", 0))
			at = int(rest.get_slice("@", 1)) if "@" in rest else 0
		var def := load("res://data/actors/%s.tres" % spec) as ActorDef
		var rig := def.rig_scene.instantiate() as Rig
		stage.world.add_child(rig)
		rig.global_transform = Transform3D(Basis(Vector3.UP, turn * PI / 4.0), Vector3((n - (specs.size() - 1) * 0.5) * SPACING, 0, 0))
		rig.apply_palette(def.palette)
		rig.hide_parts(def.hidden_parts)
		rig.set_model_scale(def.model_scale)
		rig.set_body_inflate(def.body_inflate if is_nan(inflate) else inflate)
		rigs.append(rig)
		clips.append(clip)
		starts.append(at)
	var camera := CameraRig.new()
	camera.target = middle
	camera.stage = stage
	stage.world.add_child(camera)
	camera.snap_now()
	var centre := camera.camera.unproject_position(middle.global_position + Vector3.UP * 0.9)
	var crop := Rect2i((Vector2i(centre.round()) - cell / 2).clamp(Vector2i.ZERO, PixelStage.WORLD_SIZE - cell), cell)
	await RenderingServer.frame_post_draw
	await physics_frame
	for n in rigs.size():
		rigs[n].play_move(clips[n], 0.0)
		rigs[n].set_move_time(float(starts[n] + offset) / 60.0)
	for tick in SETTLE_TICKS:
		for rig in rigs:
			rig.tick(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := stage.world.get_texture().get_image().get_region(crop)
	stage.queue_free()
	await process_frame
	return image


# The pictures side by side, each drawn `zoom` times larger.
static func _join(images: Array[Image], zoom: int) -> Image:
	var size := images[0].get_size() * zoom
	var sheet := Image.create(size.x * images.size(), size.y, false, Image.FORMAT_RGB8)
	for n in images.size():
		var big := images[n].duplicate() as Image
		big.convert(Image.FORMAT_RGB8)
		big.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(big, Rect2i(Vector2i.ZERO, size), Vector2i(n * size.x, 0))
	return sheet
