extends TestCase
## What the blade Knuckle looks like in the game's own picture (640x360, the gameplay camera), on a dark floor and a lamplit one:
## the sword is seen when he stands, walks and jogs (not only when he swings), it is the brightest thing on him, and it is broad
## enough to read in a cut, a chop and a lunge. The pixels of the sword are the pixels that change when the model's sword part is
## hidden, so a blade behind his body is not counted. Needs a display (tools/test.sh --render).

const DEF := "res://data/actors/knuckle_blade.tres"
const FISTS := ["res://data/actors/knuckle_1.tres", "res://data/actors/knuckle_2.tres", "res://data/actors/knuckle_3.tres"]
const BLADE_PART := "Knuckle_Blade"
const DARK := Color(0.07, 0.07, 0.085)
const LAMPLIT := Color(0.46, 0.4, 0.3)
## A pixel is the sword's when its picture differs from the picture without the sword by more than this (summed over red, green, blue).
const THRESHOLD := 0.04
## The sword must show this many pixels outside his body, in at least SIX_OF_EIGHT of the eight directions he may face.
const VISIBLE_PIXELS := 20
const SIX_OF_EIGHT := 6
## Clips and the frames (at 60 a second) the carry is measured at.
const CARRY := {&"blade_idle": [0, 75], &"blade_walk": [0, 20, 40, 60], &"blade_jog": [0, 14, 28, 42]}
## The blow frames the breadth is measured at, and how many pixels across the sword must be at least.
const BLOWS := {&"blade_cut": 18, &"blade_chop": 22, &"blade_lunge": 40}
const BREADTH := 2.0
## How bright the sword's lit tone must be (luma, 0 to 1) in the picture on the dark floor.
const BRIGHT := 0.60

var _stage: PixelStage
var _rig: Rig
var _ground: StandardMaterial3D


func _open(def: ActorDef, floor_colour: Color) -> void:
	_stage = (load("res://render/pixel_stage.tscn") as PackedScene).instantiate() as PixelStage
	_stage.visible = false
	add_child(_stage)
	ContactSheet._furnish(_stage.world)
	for child in _stage.world.get_children():
		if child is DirectionalLight3D:
			(child as DirectionalLight3D).shadow_enabled = false
		elif child is MeshInstance3D:
			_ground = (child as MeshInstance3D).material_override as StandardMaterial3D
	_ground.albedo_color = floor_colour
	var middle := Node3D.new()
	_stage.world.add_child(middle)
	_rig = def.rig_scene.instantiate() as Rig
	_stage.world.add_child(_rig)
	_rig.apply_palette(def.palette)
	_rig.hide_parts(def.hidden_parts)
	var camera := CameraRig.new()
	camera.target = middle
	camera.stage = _stage
	_stage.world.add_child(camera)
	camera.snap_now()
	await RenderingServer.frame_post_draw


func _close() -> void:
	_stage.queue_free()
	await frames(1)


# Poses him in `clip` at `frame` facing `facing` eighths of a turn (the same body for both pictures that follow).
func _pose(clip: StringName, frame: int, facing: int) -> void:
	await _rig.get_tree().physics_frame
	_rig.global_transform = Transform3D(Basis(Vector3.UP, facing * PI / 4.0), Vector3.ZERO)
	_rig.play_move(clip, 0.0)
	_rig.set_move_time(frame / 60.0)
	_rig.reset_physics_interpolation()
	for tick in 12:
		_rig.tick(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


# The picture of the pose now, the sword shown or hidden.
func _picture(sword: bool) -> Image:
	for mesh in _rig.get_node(^"Model").find_children(BLADE_PART, "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visible = sword
	await RenderingServer.frame_post_draw
	return _stage.world.get_texture().get_image()


# The pictures of `clip` at `frame` facing `facing`, the sword shown, then hidden.
func _shot(clip: StringName, frame: int, facing: int, sword: bool) -> Image:
	await _pose(clip, frame, facing)
	return await _picture(sword)


# The sword's pixels in `clip` at `frame` facing `facing`: {pixel: luma}, the pixels that change when the sword is hidden.
func _sword(clip: StringName, frame: int, facing: int) -> Dictionary:
	await _pose(clip, frame, facing)
	var with: Image = await _picture(true)
	var without: Image = await _picture(false)
	var found := {}
	for y in with.get_height():
		for x in with.get_width():
			var a := with.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > THRESHOLD:
				found[Vector2i(x, y)] = a.get_luminance()
	return found


# How many pixels across a set of pixels is on average: its area over its length along its longest direction.
static func _breadth(pixels: Dictionary) -> float:
	if pixels.size() < 3:
		return 0.0
	var mean := Vector2.ZERO
	for p: Vector2i in pixels:
		mean += Vector2(p)
	mean /= pixels.size()
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	for p: Vector2i in pixels:
		var d := Vector2(p) - mean
		xx += d.x * d.x
		xy += d.x * d.y
		yy += d.y * d.y
	var angle := 0.5 * atan2(2.0 * xy, xx - yy)
	var axis := Vector2(cos(angle), sin(angle))
	var lo := INF
	var hi := -INF
	for p: Vector2i in pixels:
		var along := Vector2(p).dot(axis)
		lo = minf(lo, along)
		hi = maxf(hi, along)
	return float(pixels.size()) / maxf(hi - lo + 1.0, 1.0)


func test_he_is_seen_to_be_armed_when_he_stands_walks_and_jogs() -> void:
	# For each clip, the sword's pixels in each of the eight directions he may face, averaged over the frames of the clip given
	# (a stride moves the arm, and the body turns through it): at least VISIBLE_PIXELS in at least SIX_OF_EIGHT of the directions.
	var def := load(DEF) as ActorDef
	for floor_colour: Color in [DARK, LAMPLIT]:
		await _open(def, floor_colour)
		for clip: StringName in CARRY:
			var mean := []
			for facing in 8:
				var total := 0
				for frame: int in CARRY[clip]:
					total += (await _sword(clip, frame, facing)).size()
				mean.append(snappedf(float(total) / (CARRY[clip] as Array).size(), 0.1))
			var enough := mean.filter(func(n: float) -> bool: return n >= VISIBLE_PIXELS).size()
			assert_true(enough >= SIX_OF_EIGHT, "%s on the %s floor: the sword shows %d pixels or more in %d of 8 directions (%s)" % [clip, "dark" if floor_colour == DARK else "lamplit", VISIBLE_PIXELS, enough, mean])
		await _close()


func test_the_sword_is_the_brightest_thing_on_him_and_broad_in_a_blow() -> void:
	# At each blow frame, in each direction: how bright the middle of the sword's pixels are (luma, on the dark floor) in the
	# direction that shows most of it, and how many pixels across it is. A flat blade seen edge-on is thin, so the breadth is held
	# in FOUR of the eight directions, not six.
	var def := load(DEF) as ActorDef
	await _open(def, DARK)
	for clip: StringName in BLOWS:
		var broad := 0
		var shown := []
		var best := {}
		for facing in 8:
			var pixels: Dictionary = await _sword(clip, BLOWS[clip], facing)
			if pixels.size() > best.size():
				best = pixels
			var b := _breadth(pixels)
			shown.append("%.1f" % b)
			if b >= BREADTH:
				broad += 1
		var lumas := best.values()
		lumas.sort()
		var median: float = lumas[lumas.size() / 2]
		assert_true(median >= BRIGHT, "%s at its blow: the middle of the sword's pixels has luma %.2f (at least %.2f)" % [clip, median, BRIGHT])
		assert_true(broad >= 4, "%s at its blow: the sword is %.0f px across or more in %d of 8 directions (%s)" % [clip, BREADTH, broad, shown])
	await _close()
	var palette := def.palette
	assert_true(palette.tone(9, Palette.DEEP).get_luminance() >= BRIGHT, "even the steel's darkest tone has luma %.2f" % palette.tone(9, Palette.DEEP).get_luminance())


func test_no_other_knuckles_picture_changes_with_him_in_the_game() -> void:
	# A fist Knuckle drawn standing and walking, then again on a fresh stage after a blade Knuckle has been made (his carry, his
	# palette and his sword are his alone): the same pixels, and no sword on it.
	var fist := load(FISTS[0]) as ActorDef
	var before := []
	await _open(fist, DARK)
	for clip: StringName in [&"idle", &"walk"]:
		before.append((await _shot(clip, 20, 3, false)).get_data())
	await _close()
	var arena := TestArena.make(self)
	TestArena.spawn(arena, load(DEF) as ActorDef, Brain.new(), Vector3(30, 0, 30), "Blade")
	await frames(2)
	await _open(fist, DARK)
	var i := 0
	for clip: StringName in [&"idle", &"walk"]:
		var after: Image = await _shot(clip, 20, 3, false)
		assert_true(after.get_data() == before[i], "%s: the fist Knuckle is drawn as it was" % clip)
		i += 1
	await _close()
