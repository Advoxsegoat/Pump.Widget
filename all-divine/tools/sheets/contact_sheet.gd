class_name ContactSheet
extends SceneTree
## Contact sheets: an actor's clips frame by frame, as the game camera shows them, laid out on one
## picture for reviewing clips and their marks.
##
##   tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- --def res://data/actors/abarax.tres \
##       --out out/sheets/abarax.png [--clips a,b]
##
## Give the actor's definition (--def), or a bare rig scene (--rig <rig.tscn>), not both. Needs a display
## (--render): a headless run cannot draw. --clips defaults to every clip of the rig. A relative --out is
## taken from the project folder (all-divine/), wherever the command is run from.
## Exits 0 when the sheet is written, 1 if it could not be made, 2 for a wrong command line.
##
## Each clip gets a cell for every frame that has a mark, or, if it has none, six frames spread evenly
## over it. A cell is cut around the actor out of the 640x360 picture of a PixelStage, framed by the
## gameplay CameraRig, so it shows exactly the pixels a player would see. Cells are drawn at twice their
## size, six to a row, each with a label "<clip> f<frame>" (frames at 60 per second, counted the way
## marks are), and the whole sheet is captured from a SubViewport.
##
## Each cell's pose is held for SETTLE_TICKS physics ticks before it is drawn, so what hangs off the body
## (Abarax's scarf, a spring bone that only moves as time passes) has come to rest for it, the way it
## would if the actor stood in that pose. The ticks run in the physics step, as the actor's do (see
## Rig.tick): outside it the engine's modifiers would aim at where their targets were a frame before.
##
## Given a def, the actor is drawn in the def's palette, under a white sun of energy 1, so every pixel of
## him is one of its tones. A bare rig keeps the materials its model was imported with, as an actor
## without a palette does in the game.

const PIXEL_STAGE := preload("res://render/pixel_stage.tscn")
const COLUMNS := 6
## How many times larger than the game's pixels the cells are drawn.
const ZOOM := 2
## A clip without marks gets this many cells.
const EVEN_CELLS := 6
## Mark times are counted in frames at this rate (the physics rate).
const FRAME_RATE := 60
## Where the cell is centred: this far above the actor's feet, in metres.
const BODY_CENTRE := 0.9
## How many ticks (at FRAME_RATE) each cell's pose is held before it is drawn: 0.75 s.
const SETTLE_TICKS := 45


func _initialize() -> void:
	quit(await _run(OS.get_cmdline_user_args()))


## Renders the sheet for the rig in `def_or_rig` (a rig scene, or anything with a `rig_scene`, like an
## actor's definition, whose `palette` it is then drawn in) and the given clips, or every clip of the rig
## if `clips` is empty. `cell` is the size of a cell in game pixels. Takes a few frames, so it must be
## awaited. Needs a display. Returns null, after an error, if there is no rig, no display or no clip to
## draw.
static func render(def_or_rig: Variant, clips: PackedStringArray, cell := Vector2i(160, 120)) -> Image:
	var scene := _rig_scene(def_or_rig)
	if scene == null:
		push_error("ContactSheet: expected a rig scene or something with a rig_scene, got %s" % [def_or_rig])
		return null
	if DisplayServer.get_name() == "headless":
		push_error("ContactSheet: needs a display; run it with tools/godot.sh --render")
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if not tree.root.is_inside_tree():
		await tree.process_frame  # Called from a main loop's _initialize, before the root is in the tree.

	var stage := PIXEL_STAGE.instantiate() as PixelStage
	stage.visible = false  # Only its World viewport is wanted, not the upscaled picture in the window.
	tree.root.add_child(stage)
	_furnish(stage.world)
	var rig := scene.instantiate() as Rig
	stage.world.add_child(rig)
	var palette := _palette(def_or_rig)
	if palette != null:
		rig.apply_palette(palette)
	var camera := CameraRig.new()
	camera.target = rig
	camera.stage = stage
	stage.world.add_child(camera)
	camera.snap_now()
	var centre := camera.camera.unproject_position(rig.global_position + Vector3.UP * BODY_CENTRE)
	var crop := Rect2i((Vector2i(centre.round()) - cell / 2).clamp(Vector2i.ZERO, PixelStage.WORLD_SIZE - cell), cell)

	var names := clips if not clips.is_empty() else PackedStringArray(rig.tree.get_animation_list())
	var images: Array[Image] = []
	var labels := PackedStringArray()
	await RenderingServer.frame_post_draw  # Let the new World draw once before the first cell.
	for clip in names:
		if not rig.tree.has_animation(clip):
			push_error("ContactSheet: the rig has no clip '%s'" % clip)
			continue
		for frame in cell_frames(rig.tree.get_animation(clip)):
			await tree.physics_frame
			rig.play_move(clip, 0.0)
			rig.set_move_time(float(frame) / FRAME_RATE)
			for i in SETTLE_TICKS:
				rig.tick(1.0 / FRAME_RATE)
			# The skin follows the skeleton at the end of the frame, then the frame is drawn.
			await RenderingServer.frame_post_draw
			images.append(stage.world.get_texture().get_image().get_region(crop))
			labels.append(cell_label(clip, frame))
	stage.queue_free()
	if images.is_empty():
		push_error("ContactSheet: none of the clips %s could be drawn" % [names])
		return null
	return await _compose(images, labels, cell)


## The frames (at 60 per second) a clip gets a cell for: each frame that has a mark, once and in order;
## or, for a clip without marks, six frames spread evenly from its start to its end (to just before the
## end for a loop, whose end is its start).
static func cell_frames(anim: Animation) -> PackedInt32Array:
	var frames := PackedInt32Array()
	for t in anim.get_track_count():
		if not Marks.is_marks_track(anim, t):
			continue
		for k in anim.track_get_key_count(t):
			var frame := Marks.frame_of(anim.track_get_key_time(t, k))
			if not frames.has(frame):
				frames.append(frame)
	if not frames.is_empty():
		frames.sort()
		return frames
	var last := roundi(anim.length * FRAME_RATE)
	var spans := EVEN_CELLS if anim.loop_mode != Animation.LOOP_NONE else EVEN_CELLS - 1
	for i in EVEN_CELLS:
		var frame := roundi(float(i * last) / spans)
		if not frames.has(frame):
			frames.append(frame)
	return frames


## The label of a cell: the clip and the frame.
static func cell_label(clip: StringName, frame: int) -> String:
	return "%s f%d" % [clip, frame]


# --- helpers ---

static func _rig_scene(def_or_rig: Variant) -> PackedScene:
	if def_or_rig is PackedScene:
		return def_or_rig
	if def_or_rig is Object and (def_or_rig as Object).get(&"rig_scene") is PackedScene:
		return (def_or_rig as Object).get(&"rig_scene")
	return null


# The palette of `def_or_rig` when it has one (an actor's definition), else null (a rig scene has none).
static func _palette(def_or_rig: Variant) -> Palette:
	if def_or_rig is Object:
		return (def_or_rig as Object).get(&"palette") as Palette
	return null


# A plain stage for the actor: a ground to stand on, a white sun of energy 1 from the camera's side (the
# light the toon shader holds to the palette) and some sky light for the ground.
static func _furnish(world: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.63, 0.7)
	env.ambient_light_energy = 0.35
	var environment := WorldEnvironment.new()
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 20.0
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.42, 0.4, 0.36)
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	world.add_child(ground)


# Lays the cells out, ZOOM times their size and COLUMNS to a row, each with its label, and captures them.
static func _compose(images: Array[Image], labels: PackedStringArray, cell: Vector2i) -> Image:
	var tree := Engine.get_main_loop() as SceneTree
	var shown := cell * ZOOM
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(mini(images.size(), COLUMNS), ceili(images.size() / float(COLUMNS))) * shown
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 0)
	grid.add_theme_constant_override(&"v_separation", 0)
	for i in images.size():
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(images[i])
		picture.custom_minimum_size = shown
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var label := Label.new()
		label.text = labels[i]
		label.position = Vector2(6, 2)
		label.add_theme_color_override(&"font_color", Color.WHITE)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 4)
		picture.add_child(label)
		grid.add_child(picture)
	viewport.add_child(grid)
	tree.root.add_child(viewport)
	# One frame lays the grid out and draws it; the second is to be sure the capture has it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var sheet := viewport.get_texture().get_image()
	viewport.queue_free()
	return sheet


func _run(args: PackedStringArray) -> int:
	var rig_path := ""
	var def_path := ""
	var out := ""
	var clips := PackedStringArray()
	var i := 0
	while i < args.size():
		var arg := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		match arg:
			"--rig":
				rig_path = value
			"--def":
				def_path = value
			"--out":
				out = value
			"--clips":
				clips = value.split(",", false)
			_:
				printerr("contact_sheet.gd: unknown argument '%s'" % arg)
				return _usage()
		if value == "":
			printerr("contact_sheet.gd: %s needs a value" % arg)
			return _usage()
		i += 2
	if (rig_path == "") == (def_path == "") or out == "":
		return _usage()
	var source_path := def_path if def_path != "" else rig_path
	var source: Resource = load(source_path) if def_path != "" else (load(source_path) as PackedScene)
	if source == null:
		printerr("contact_sheet.gd: cannot load '%s'" % source_path)
		return 1
	var sheet: Image = await render(source, clips)
	if sheet == null:
		return 1
	var path := out
	if path.is_relative_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err == OK:
		err = sheet.save_png(path)
	if err != OK:
		printerr("contact_sheet.gd: cannot write '%s': %s" % [path, error_string(err)])
		return 1
	print("contact_sheet.gd: wrote %s (%dx%d)" % [path, sheet.get_width(), sheet.get_height()])
	return 0


func _usage() -> int:
	printerr("usage: tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- (--def <actor.tres> | --rig <rig.tscn>) --out <file.png> [--clips a,b]")
	return 2
