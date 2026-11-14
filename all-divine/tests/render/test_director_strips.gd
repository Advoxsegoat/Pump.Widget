extends TestCase
## The Director's scenes as the game draws them (xvfb, gl_compatibility): the fixture played on a real Main with Abarax scripted
## (standing, in the middle of a jab, in a hop), as a MINI and as a CUTSCENE, a frame every 15 scene frames; the glide in every 3
## frames to a wide first shot, to a close one, and to a close one with a longer lead-in; the glide out from a last shot at yaw 90
## and at yaw 180 every 3 frames. Each is saved as a contact sheet in out/story/ (director_<name>.png, 320x180 a frame, five to a
## row, in order) for a person to look at, with the frames themselves at 640x360 in out/story/director_<name>/. What is checked
## here is only what a machine can: no black frame, and the picture never changes by more than a limit between two frames 3 apart.

const MAIN := "res://main/main.tscn"
const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const OUT := "out/story"
const TILE := Vector2i(320, 180)
const COLUMNS := 5

var main: Main


func after_each() -> void:
	Game.reset()
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	get_window().size = Vector2i(1920, 1080)


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# Main in the yard at 640x360, its foes gone and its arena quiet, Abarax without hands (a scripted body), the look warmed up.
func _scene() -> void:
	Game.reset()
	Inputs._device = Inputs.Device.GAMEPAD
	Arena.reset_spawn_counts()
	get_window().size = Vector2i(640, 360)
	main = track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	for old in main.arena().enemies():
		old.queue_free()
	main.player.set_brain(Brain.new())
	await frames(Rig.WARM_FRAMES + 6)


func _grab() -> Image:
	for i in 2:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Plays `scene` and takes the picture on each scene frame of `at` (director.frame values, ascending). Returns the images.
func _shoot(scene: SceneShots, at: Array[int]) -> Array[Image]:
	var director := Director.new()
	assert_true(director.begin(scene, main.region, main.camera_rig, main.hud, main), "the scene is taken: %s" % Director.last_refusal)
	var images: Array[Image] = []
	for target in at:
		while is_instance_valid(director) and director.frame < target and director.phase != Director.Phase.DONE:
			await frames(1)
		images.append(await _grab())
	return images


func _brightness(image: Image) -> float:
	var small := image.duplicate() as Image
	small.resize(32, 18, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in 18:
		for x in 32:
			var c := small.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
	return total / (32.0 * 18.0)


# The mean absolute difference between two pictures, 0 to 1, on a coarse grid.
func _difference(a: Image, b: Image) -> float:
	var x := a.duplicate() as Image
	var y := b.duplicate() as Image
	x.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	y.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for j in 36:
		for i in 64:
			var p := x.get_pixel(i, j)
			var q := y.get_pixel(i, j)
			total += (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
	return total / (64.0 * 36.0)


func _save(name: String, images: Array[Image]) -> void:
	var folder := ProjectSettings.globalize_path("res://").path_join(OUT).path_join("director_%s" % name)
	DirAccess.make_dir_recursive_absolute(folder)
	var rows := ceili(float(images.size()) / COLUMNS)
	var sheet := Image.create(TILE.x * mini(images.size(), COLUMNS), TILE.y * rows, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var image := images[i].duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(folder.path_join("%03d.png" % i))
		image.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % COLUMNS) * TILE.x, (i / COLUMNS) * TILE.y))
	assert_eq(sheet.save_png(ProjectSettings.globalize_path("res://").path_join(OUT).path_join("director_%s.png" % name)), OK, "saved the sheet %s" % name)


func _no_black_frames(name: String, images: Array[Image]) -> void:
	for i in images.size():
		assert_true(_brightness(images[i]) > 0.04, "%s: frame %d is not black (%.3f)" % [name, i, _brightness(images[i])])


func _every(from: int, to: int, step: int) -> Array[int]:
	var out: Array[int] = []
	var f := from
	while f <= to:
		out.append(f)
		f += step
	return out


# --- the whole scene, as the owner will see it ---

func test_the_scene_every_15_frames_standing_mid_jab_and_in_a_hop_as_a_mini_and_a_cutscene() -> void:
	var only := OS.get_environment("DIRECTOR_STRIPS_ONLY")  # a comma list of sheet names, to shoot only those again
	for start: String in ["standing", "mid_jab", "hop"]:
		for kind: SceneShots.Kind in [SceneShots.Kind.MINI, SceneShots.Kind.CUTSCENE]:
			var wanted := "%s_%s" % [start, "cutscene" if kind == SceneShots.Kind.CUTSCENE else "mini"]
			if only != "" and not only.split(",").has(wanted):
				continue
			await _scene()
			var scene := _fixture()
			scene.kind = kind
			scene.letterbox = kind == SceneShots.Kind.CUTSCENE
			if start != "standing":
				var move := Registry.fetch(&"moves", &"palm_jab" if start == "mid_jab" else &"hop") as MoveData
				main.player.runner.start(move, true)
				await frames(7)
			var name := "%s_%s" % [start, "cutscene" if kind == SceneShots.Kind.CUTSCENE else "mini"]
			var images := await _shoot(scene, _every(0, 360, 15))
			_no_black_frames(name, images)
			_save(name, images)
			main.free()
			await frames(2)


# --- the glide in, every 3 frames ---

func test_the_glide_in_to_a_wide_first_shot_and_to_a_close_one() -> void:
	await _scene()
	var wide := await _shoot(_fixture(), _every(0, 33, 3))
	_no_black_frames("glide_in_wide", wide)
	_save("glide_in_wide", wide)
	main.free()
	await frames(2)
	for lead in [30, 45]:
		await _scene()
		var scene := _fixture()
		scene.lead_in = lead
		var first := scene.shots[0]
		first.framing = Shot.Framing.CLOSE
		first.move = Shot.CamMove.STATIC
		first.aim = &"abarax"
		first.aim_to = &""
		first.aim_height = 1.5
		var images := await _shoot(scene, _every(0, lead + 3, 3))
		_no_black_frames("glide_in_close_%d" % lead, images)
		for i in range(1, images.size()):
			var step := _difference(images[i - 1], images[i])
			print("glide in to a close shot, lead_in %d: frames %d to %d differ by %.3f" % [lead, (i - 1) * 3, i * 3, step])
		_save("glide_in_close_%d" % lead, images)
		main.free()
		await frames(2)


# --- the glide out, every 3 frames ---

func test_the_glide_out_from_a_shot_at_yaw_90_and_at_yaw_180() -> void:
	for yaw in [90.0, 180.0]:
		await _scene()
		var scene := _fixture()
		var last := scene.shots[scene.shots.size() - 1]
		last.framing = Shot.Framing.MEDIUM
		last.over_shoulder = &""
		last.yaw_deg = yaw
		var turn := TimelineBuilder.return_frames(scene)
		var images := await _shoot(scene, _every(297, 300 + 63, 3))
		_no_black_frames("glide_out_yaw_%d" % yaw, images)
		for i in range(1, images.size()):
			print("glide out from yaw %d: frames %d to %d differ by %.3f" % [yaw, 297 + (i - 1) * 3, 297 + i * 3, _difference(images[i - 1], images[i])])
		_save("glide_out_yaw_%d" % int(yaw), images)
		assert_true(turn >= 30)
		main.free()
		await frames(2)
