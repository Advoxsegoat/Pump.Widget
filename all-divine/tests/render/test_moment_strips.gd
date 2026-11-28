extends TestCase
## The finisher's camera dip and the F10 fixture as the game draws them (xvfb, gl_compatibility), on a real Main, saved as contact
## sheets in out/story/ for a person to look at; what is checked here is only what a machine can (no black frame, the dip at its top
## and gone at its end, a scene that plays to its end and hands the game back).
##
##   moment_<foes>_<size>.png  the dip: a frame every 6 of its 90 (0 to 90), with one foe (the finisher's own) or three (two more
##                             Knuckles with their own brains, two to three metres off, as the yard's wave sends them), at the game's
##                             640x360 (tiles 320x180, five a row) and at x3 (1920x1080 frames, tiles 480x270, four a row).
##   f10_<start>.png           F10 in the yard: a frame every 15 from the press to 60 frames after control is Abarax's again, with
##                             him standing, in the middle of a jab, in the middle of a hop, and with the wave on (its Knuckle
##                             at its own business); 640x360 frames, tiles 320x180, five a row.
## The frames themselves are in out/story/<sheet name>/. A run shoots the DEFAULT sheets (to keep the render job short);
## MOMENT_STRIPS_ONLY=<comma list> shoots those, MOMENT_STRIPS_ONLY=all shoots every one.

const MAIN := "res://main/main.tscn"
const KNUCKLE := "res://data/actors/knuckle_1.tres"
const OUT := "out/story"
const DEFAULT := ["dip_one_foe_640", "dip_three_foes_640", "f10_standing"]
const BIG := Vector2i(1920, 1080)
const SMALL := Vector2i(640, 360)

var main: Main


func after_each() -> void:
	Game.reset()
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	get_window().size = BIG


func _wanted(name: String) -> bool:
	var only := OS.get_environment("MOMENT_STRIPS_ONLY")
	if only == "all":
		return true
	return (only.split(",") if only != "" else PackedStringArray(DEFAULT)).has(name)


# Main in the yard at `size`, the first foe gone (the arena sends nothing by itself unless `wave`), Abarax without hands, the look warm.
func _scene(size: Vector2i, wave := false) -> void:
	Game.reset()
	Inputs._device = Inputs.Device.GAMEPAD
	Arena.reset_spawn_counts()
	Director.reset_spawn_counts()
	StoryLog.forget_all()
	get_window().size = size
	main = track((load(MAIN) as PackedScene).instantiate()) as Main
	if not wave:
		main.arena().automatic = false
		for old in main.arena().enemies():
			old.queue_free()
	main.player.set_brain(Brain.new())
	await frames(Rig.WARM_FRAMES + 6)


func _grab() -> Image:
	for i in 2:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _brightness(image: Image) -> float:
	var small := image.duplicate() as Image
	small.resize(32, 18, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in 18:
		for x in 32:
			var c := small.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
	return total / (32.0 * 18.0)


func _save(name: String, images: Array[Image], tile: Vector2i, columns: int) -> void:
	var folder := ProjectSettings.globalize_path("res://").path_join(OUT).path_join(name)
	DirAccess.make_dir_recursive_absolute(folder)
	var rows := ceili(float(images.size()) / columns)
	var sheet := Image.create(tile.x * mini(images.size(), columns), tile.y * rows, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var image := images[i].duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(folder.path_join("%03d.png" % i))
		image.resize(tile.x, tile.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, tile), Vector2i((i % columns) * tile.x, (i / columns) * tile.y))
		assert_true(_brightness(images[i]) > 0.04, "%s: frame %d is not black (%.3f)" % [name, i, _brightness(images[i])])
	assert_eq(sheet.save_png(ProjectSettings.globalize_path("res://").path_join(OUT).path_join("%s.png" % name)), OK, "saved the sheet %s" % name)


# --- the dip ---

# A finisher on the first Knuckle's stand-in, a metre in front of Abarax, with `extra` more Knuckles (their own brains) near him.
func _stage_finisher(extra: int) -> Actor:
	var player := main.player
	var def := load(KNUCKLE) as ActorDef
	var forward := Basis(Vector3.UP, player.rotation.y) * Vector3(0, 0, 1)
	var at := player.global_position + forward
	var victim := TestArena.spawn(main.region, def, Brain.new(), at, "Victim")
	victim.place(Transform3D(Basis(Vector3.UP, player.rotation.y + PI), at))
	track(PostureBreaker.make(player, victim))
	for k in extra:
		var side := -1.0 if k == 0 else 1.0
		var offset := Basis(Vector3.UP, side * deg_to_rad(110.0 - 40.0 * k)) * forward * (2.6 + 0.4 * k)
		var spot := player.global_position + offset
		var foe := TestArena.spawn(main.region, def, EnemyBrain.new(def.brain, k + 1), spot, "Foe%d" % k)
		foe.place(Transform3D(Basis(Vector3.UP, Locomotion.yaw_of(Vector2(-offset.x, -offset.z))), spot))
	player.set_brain(ScriptBrain.new([{frames = 9}, {frames = 1, press = [&"palm"]}, {frames = 600}]))
	return victim


# The dip every 6th frame of its 90 (0 to 90): the picture the frame it is at, from a Main with `extra` foes besides the finisher's.
func _dip(name: String, size: Vector2i, extra: int, tile: Vector2i, columns: int) -> void:
	if not _wanted(name):
		return
	await _scene(size)
	_stage_finisher(extra)
	var cam := main.camera_rig.get_node(NodePath(MomentCam.NAME)) as MomentCam
	var guard := 0
	while cam.director == null and guard < 120:
		await frames(1)
		guard += 1
	assert_true(cam.director != null, "%s: the dip began" % name)
	var images: Array[Image] = []
	var top := 0.0
	for target in range(0, 91, 6):
		while cam.director != null and cam.director.frame < target:
			await frames(1)
			top = maxf(top, main.camera_rig.cine_weight)
		images.append(await _grab())
	assert_eq(top, 1.0, "%s: the camera was wholly in the dip at the top" % name)
	await frames(4)
	assert_eq(main.camera_rig.cine_weight, 0.0, "%s: and it is the game's again" % name)
	_save(name, images, tile, columns)
	main.free()
	await frames(2)


func test_the_dip_with_one_foe_and_with_three() -> void:
	await _dip("dip_one_foe_640", SMALL, 0, Vector2i(320, 180), 5)
	await _dip("dip_three_foes_640", SMALL, 2, Vector2i(320, 180), 5)
	await _dip("dip_one_foe_x3", BIG, 0, Vector2i(480, 270), 4)
	await _dip("dip_three_foes_x3", BIG, 2, Vector2i(480, 270), 4)


# --- F10 ---

# F10 in the yard: a picture every 15 frames from the press to 60 frames after control is back.
func _f10(start: String, wave: bool) -> void:
	var name := "f10_%s" % start
	if not _wanted(name):
		return
	await _scene(SMALL, wave)
	if start == "mid_jab" or start == "hop":
		var move := Registry.fetch(&"moves", &"palm_jab" if start == "mid_jab" else &"hop") as MoveData
		main.player.runner.start(move, true)
		await frames(7)
	var pressed := Engine.get_physics_frames()
	var director := main.play_fixture()
	assert_true(director != null, "%s: F10 plays the scene (%s)" % [name, Director.last_refusal])
	if director == null:
		main.free()
		await frames(2)
		return
	var state := {ended = -1}
	director.finished.connect(func(_skipped: bool) -> void: state.ended = Engine.get_physics_frames())
	var images: Array[Image] = []
	var next := 0
	while Engine.get_physics_frames() - pressed < 1500 and (state.ended < 0 or Engine.get_physics_frames() - state.ended <= 60):
		if Engine.get_physics_frames() - pressed >= next:
			images.append(await _grab())
			next += 15
		await frames(1)
	assert_true(state.ended >= 0, "%s: the scene played to its end" % name)
	assert_eq(Game.state, Game.State.PLAY, "%s: and the game is in PLAY" % name)
	_save(name, images, Vector2i(320, 180), 5)
	main.free()
	await frames(2)


func test_f10_standing_mid_jab_mid_hop_and_with_the_wave_on() -> void:
	await _f10("standing", false)
	await _f10("mid_jab", false)
	await _f10("hop", false)
	await _f10("wave", true)
