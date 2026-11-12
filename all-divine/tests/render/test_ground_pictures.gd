extends TestCase
## The Bilibara grounds as the game draws them (xvfb, gl_compatibility): the stage's 640x360 picture of a field of one stone,
## from the game's camera, in the dim light of the review (sun 0.5, ambient 0.3) with the bodies' fill.
##
## The cobble must not be busier or shimmer more than the yard's flagstone: measured against the picture at camera offset 0,
## moved by the offset's whole pixels, the ground's mean change in luma at 0.19, 0.41 and 0.83 m, north and east (note: the
## stage moves the picture in whole pixels, so a static ground gives about 0 for every stone, flagstone included; the
## bound is the flagstone's plus a little, and it is what catches a texture that is not seen the same from one pixel
## to the next), and how busy it is: the mean change in luma between neighbouring pixels. The snow must leave room for a
## body in white: no pixel of it at 250 or more, and the ground round Abarax darker than his jacket by 0.08 in luma.
## Pictures are saved to out/shots/bilibara/ for a person to look at.

const MAIN := "res://main/main.tscn"
const BUILDER := preload("res://tools/world/build_region.gd")
const SIZE := Vector2i(1920, 1080)
const DIM := "sky #c9d3e0\nambient #b4c3d9 0.3\nsun -50 35 #e8eef8 0.5\nfill -35 25 #e6edff 0.8\n"
const GRADE := "res://data/render/grades/training_yard.tres"
const SHOTS := "out/shots/bilibara/"
## Pixels of picture per metre east, and north (pitch 40 degrees).
const PX_EAST := 32.0
const PX_NORTH := 32.0 * 0.6427876
## The box in the middle (the body) that the ground measures leave out.
const BODY_HALF := Vector2i(70, 90)
const BODY_CENTRE := Vector2i(320, 190)
const OFFSETS: Array[float] = [0.19, 0.41, 0.83]
## How much busier or more shimmering than the flagstone a ground may be, and the slack for a flagstone that gives 0.
const MARGIN := 1.25
const SLACK := 0.05

var _main: Main


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


# A field of `stone`, 30 x 30 m in nine plates, in the dim light.
func _field(stone: String) -> String:
	var out := DIM
	for i in 3:
		for j in 3:
			out += "ground %s %s %s %s %s\n" % [-15 + i * 10, -15 + j * 10, -5 + i * 10, -5 + j * 10, stone]
	return out


# The picture (640x360, the stage's own) with Abarax at `at` and the camera on him, in `layout`.
func _picture(layout: String, at: Vector3, name: String) -> Image:
	if _main == null:
		Game.reset()
		_main = track((load(MAIN) as PackedScene).instantiate()) as Main
		_main.look_on = false
		await frames(5)
	var builder := BUILDER.Builder.new()
	builder.layout = name
	var region := builder.build(layout + "marker Spawn %s %s 180\n" % [at.x, at.z], "Region") as Region
	assert_eq(builder.problems, PackedStringArray(), name)
	var old := _main.region
	var world := old.get_parent()
	if old is Arena:
		(old as Arena).clear_foes()
	world.remove_child(old)
	old.queue_free()
	_main.region = region
	world.add_child(region)
	world.move_child(region, 0)
	region.grade = load(GRADE)
	_main.player.set_brain(Brain.new())
	_main.player.place(Transform3D(Basis(Vector3.UP, PI), at))
	_main._apply_look()
	_main.camera_rig.snap_now()
	await frames(12)
	for i in 4:
		await RenderingServer.frame_post_draw
	var full := _main.stage.world.get_texture().get_image()
	var pic := full.get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
	var path := ProjectSettings.globalize_path("res://").path_join(SHOTS + name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	pic.save_png(path)
	return pic


func _luma(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(640 * 360)
	for y in 360:
		for x in 640:
			var c := img.get_pixel(x, y)
			out[y * 640 + x] = 0.2126 * c.r8 + 0.7152 * c.g8 + 0.0722 * c.b8
	return out


func _in_body(x: int, y: int) -> bool:
	return absi(x - BODY_CENTRE.x) < BODY_HALF.x and absi(y - BODY_CENTRE.y) < BODY_HALF.y


# The mean change in luma of picture `b` against `a` moved by (shift_x, shift_y) whole pixels, off the body.
func _shimmer(a: PackedFloat32Array, b: PackedFloat32Array, shift_x: int, shift_y: int) -> float:
	var total := 0.0
	var n := 0
	for y in 360:
		for x in 640:
			var ax := x + shift_x
			var ay := y - shift_y
			if _in_body(x, y) or ax < 0 or ax >= 640 or ay < 0 or ay >= 360:
				continue
			total += absf(b[y * 640 + x] - a[ay * 640 + ax])
			n += 1
	return total / n


# The mean absolute luma step between neighbouring pixels, x and y, off the body.
func _busy(a: PackedFloat32Array) -> float:
	var total := 0.0
	var n := 0
	for y in range(1, 360):
		for x in range(1, 640):
			if _in_body(x, y):
				continue
			total += absf(a[y * 640 + x] - a[y * 640 + x - 1]) + absf(a[y * 640 + x] - a[(y - 1) * 640 + x])
			n += 1
	return total / n


# {shimmer: mean over the six offsets, busy: at offset 0} of the stone's field.
func _measure(stone: String) -> Dictionary:
	var layout := _field(stone)
	var zero := {}
	var sum := 0.0
	var count := 0
	for direction in ["east", "north"]:
		var base := _luma(await _picture(layout, Vector3.ZERO, "shimmer_%s_%s_0" % [stone, direction]))
		zero[direction] = base
		for d in OFFSETS:
			var at := Vector3(d, 0, 0) if direction == "east" else Vector3(0, 0, -d)
			var moved := _luma(await _picture(layout, at, "shimmer_%s_%s_%d" % [stone, direction, roundi(d * 100)]))
			if direction == "east":
				sum += _shimmer(base, moved, roundi(d * PX_EAST), 0)
			else:
				sum += _shimmer(base, moved, 0, roundi(d * PX_NORTH))
			count += 1
	return {shimmer = sum / count, busy = _busy(zero["east"])}


func test_the_cobble_is_no_busier_and_shimmers_no_more_than_the_flagstone() -> void:
	var flagstone: Dictionary = await _measure("flagstone")
	var cobble: Dictionary = await _measure("cobble")
	print("ground pictures: flagstone shimmer %.3f busy %.2f; cobble shimmer %.3f busy %.2f" % [
			flagstone.shimmer, flagstone.busy, cobble.shimmer, cobble.busy])
	assert_true(cobble.shimmer <= MARGIN * flagstone.shimmer + SLACK, "the cobble's shimmer %.3f against the flagstone's %.3f" % [cobble.shimmer, flagstone.shimmer])
	assert_true(cobble.busy <= MARGIN * flagstone.busy, "the cobble's busyness %.2f against the flagstone's %.2f" % [cobble.busy, flagstone.busy])


func test_a_body_in_white_stands_out_on_the_snow() -> void:
	var at := Vector3(0.5, 0, 0.5)
	var picture := await _picture(_field("snow"), at, "snow_dim")
	var luma := _luma(picture)
	var brightest := 0.0
	var jacket: Array[float] = []
	var ring := 0.0
	var ring_count := 0
	for y in 360:
		for x in 640:
			var c := picture.get_pixel(x, y)
			var inside := absi(x - 320) < 22 and y > 120 and y < 196
			if inside:
				jacket.append(luma[y * 640 + x])
			elif not _in_body(x, y):
				brightest = maxf(brightest, maxf(c.r8, maxf(c.g8, c.b8)))
			if not inside and absi(x - 320) < 110 and y > 80 and y < 260:
				ring += luma[y * 640 + x]
				ring_count += 1
	jacket.sort()
	var white: float = jacket[int(jacket.size() * 0.98)]
	var ground := ring / ring_count
	assert_true(brightest < 250.0, "the snow's brightest channel is %d" % brightest)
	assert_true(white - ground >= 0.08 * 255.0, "his jacket (%.0f) is %.0f over the ground round him (%.0f), at least %.0f" % [white, white - ground, ground, 0.08 * 255.0])
