extends TestCase
## The screen look on a real display (xvfb, gl_compatibility, 1920x1080): screen_post on the CameraRig's
## PostQuad (outlines, depth of field, fog) and screen_final on the PixelStage (bloom, grade, vignette).
##
## The scene: a 1 m box floating 0.5 m over a checkered plane, centred on the camera's target, and a far
## checkered box 6 m behind it. Everything is drawn in tests/support/flat_colour.gdshader, which shows
## exact sRGB colours in either renderer, so the raw picture is known and is the same in both. Each test
## renders the 640x360 picture raw (no post quad, no final material) and with some settings, and compares.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const FLAT := preload("res://tests/support/flat_colour.gdshader")
const DUSK := "res://data/render/grades/courtyard_dusk.tres"
const GOLDEN := "res://tests/render/golden/post_scene_compat.png"
const W := 640
const H := 360
## The near box, one colour on every face (so its edges are where its two shades meet the rest).
const NEAR := Color(0.92, 0.40, 0.50)
## The far box's checker, 0.25 m squares.
const FAR_A := Color(0.30, 0.42, 0.78)
const FAR_B := Color(0.95, 0.90, 0.80)
## The plane's checker, 0.5 m squares. The dark one is where Compatibility's colour conversions are
## furthest from each other's inverse (a colour sent straight through comes back 3 to 4 steps off).
const PLANE_A := Color(0.56, 0.62, 0.44)
const PLANE_B := Color(0.20, 0.24, 0.08)
## flat_colour.gdshader's shades of a face toward +Y and toward +Z (the two kinds this camera sees).
const SHADES := [1.0, 0.78]
## One 8-bit step.
const STEP := 1.0 / 255.0

var stage: PixelStage
var rig: CameraRig
var plane: MeshInstance3D
var final_material: Material


func before_each() -> void:
	var window := get_window()
	if window.size != Vector2i(1920, 1080):
		window.size = Vector2i(1920, 1080)
		await get_tree().process_frame
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)
	plane = _flat(plane_mesh, Vector3(0, -1, 0), PLANE_A, PLANE_B, 0.5)
	_flat(BoxMesh.new(), Vector3.ZERO, NEAR, NEAR, 1.0)
	var far_mesh := BoxMesh.new()
	far_mesh.size = Vector3(3, 2, 1)
	_flat(far_mesh, Vector3(-2.5, 0, -6), FAR_A, FAR_B, 0.25)
	# The target at the origin: the camera's snap then takes nothing away, and picture pixel (x, y) is
	# World texel (x + 1, y + 1).
	var target := Node3D.new()
	stage.world.add_child(target)
	rig = CameraRig.new()
	rig.target = target
	rig.stage = stage
	stage.world.add_child(rig)
	rig.snap_now()
	final_material = stage.material


func test_all_off_equals_raw() -> void:
	var raw: Image = await _raw()
	var post: Image = await _with(RenderSettings.new().off(), load(DUSK))
	var bad := _count_differing(raw, post, 1)
	assert_eq(bad["count"], 0, "pixels more than 1/255 from raw: %s" % [bad["examples"]])


# With only the outline on: every pixel of the box with a deeper neighbour is darkened to 0.35 of its
# colour; the deeper side of the edge, and every pixel on a flat stretch, is left alone; where the box's
# two faces meet (a crease) one of the two pixels is darkened to 0.7.
func test_outline_rings_the_silhouette() -> void:
	var raw: Image = await _raw()
	var post: Image = await _with(_only("outline"))
	var raw_ids := _ints(raw)
	var post_ids := _ints(post)
	var near := _near_mask(raw)
	var edge := 0
	var dark_edge := 0
	var beside := 0
	var beside_kept := 0
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			var touches := 0  # 4-neighbours on the other side of the box's outline
			for n in [i - 1, i + 1, i - W, i + W]:
				if near[n] != near[i]:
					touches += 1
			if touches == 0:
				continue
			if near[i]:
				edge += 1
				if _darker_than(post_ids[i], raw_ids[i], 0.5):
					dark_edge += 1
			else:
				beside += 1
				if _diff(post_ids[i], raw_ids[i]) <= 1:
					beside_kept += 1
	assert_true(edge > 120, "the box has an outline to check (%d pixels)" % edge)
	assert_true(dark_edge >= 0.9 * edge, "%d of %d box-edge pixels are darker than raw x 0.5" % [dark_edge, edge])
	assert_true(beside_kept >= 0.95 * beside, "%d of %d pixels beside the box (the deeper side) are kept" % [beside_kept, beside])

	var flat := _flat_mask(raw_ids)
	var flat_count := 0
	var flat_changed := 0
	for i in W * H:
		if flat[i]:
			flat_count += 1
			if _diff(post_ids[i], raw_ids[i]) > 1:
				flat_changed += 1
	assert_true(flat_count > 50000, "enough flat pixels (%d)" % flat_count)
	assert_eq(flat_changed, 0, "flat-face pixels that changed")

	# The crease between the box's top (shade 1.0) and front (shade 0.78): pairs of vertical neighbours, one
	# on each face. One of each pair is darkened to 0.7 of its colour, and neither is a silhouette line.
	var top := _colour_id(NEAR)
	var front := _colour_id(NEAR * 0.78)
	var pairs := 0
	var creased := 0
	for y in range(1, H - 1):
		for x in range(W):
			var i := y * W + x
			if _diff(raw_ids[i], top) <= 1 and _diff(raw_ids[i + W], front) <= 1:
				pairs += 1
				var a := _scaled_to(post_ids[i], raw_ids[i], 0.7)
				var b := _scaled_to(post_ids[i + W], raw_ids[i + W], 0.7)
				if (a and _diff(post_ids[i + W], raw_ids[i + W]) <= 1) or (b and _diff(post_ids[i], raw_ids[i]) <= 1):
					creased += 1
	assert_true(pairs > 20, "the box's top meets its front (%d pairs)" % pairs)
	assert_true(creased >= 0.9 * pairs, "%d of %d crease pairs have exactly one pixel at 0.7" % [creased, pairs])


# The far plane (nothing drawn there) is never outlined: with the ground gone the box floats against the
# background, its edge pixels are darkened and the background around it is not.
func test_far_plane_is_never_outlined() -> void:
	plane.visible = false
	var raw: Image = await _raw()
	var post: Image = await _with(_only("outline"))
	var raw_ids := _ints(raw)
	var post_ids := _ints(post)
	var background := raw_ids[0]
	var near := _near_mask(raw)
	var bg := 0
	var bg_changed := 0
	var edge := 0
	var dark_edge := 0
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if raw_ids[i] == background:
				bg += 1
				if _diff(post_ids[i], raw_ids[i]) > 1:
					bg_changed += 1
			elif near[i] and (not near[i - 1] or not near[i + 1] or not near[i - W] or not near[i + W]):
				edge += 1
				if _darker_than(post_ids[i], raw_ids[i], 0.5):
					dark_edge += 1
	assert_true(bg > 100000, "the background shows (%d pixels)" % bg)
	assert_eq(bg_changed, 0, "background pixels that changed")
	assert_true(edge > 120 and dark_edge >= 0.9 * edge, "%d of %d box-edge pixels against the background are outlined" % [dark_edge, edge])


# With only the depth of field on, focused on the target: the box around it is exactly as it was, and the
# far box, 3.5 to 5 m deeper, is blurred: its colour edges are soft.
func test_dof_keeps_focus_sharp_blurs_far() -> void:
	var raw: Image = await _raw()
	var post: Image = await _with(_only("dof_strength"))
	var raw_ids := _ints(raw)
	var post_ids := _ints(post)
	var near := _near_mask(raw)
	var far := _mask(raw_ids, [FAR_A, FAR_B])
	var near_count := 0
	var near_changed := 0
	var far_edge := 0
	var far_soft := 0
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if near[i]:
				near_count += 1
				if _diff(post_ids[i], raw_ids[i]) > 1:
					near_changed += 1
			elif far[i] and (raw_ids[i - 1] != raw_ids[i] or raw_ids[i + 1] != raw_ids[i] or raw_ids[i - W] != raw_ids[i] or raw_ids[i + W] != raw_ids[i]):
				far_edge += 1
				if _diff(post_ids[i], raw_ids[i]) > 4:
					far_soft += 1
	assert_true(near_count > 1000, "the box in focus shows (%d pixels)" % near_count)
	assert_eq(near_changed, 0, "pixels of the box in focus that changed")
	assert_true(far_edge > 300, "the far box has colour edges (%d)" % far_edge)
	assert_true(far_soft >= 0.9 * far_edge, "%d of %d far colour-edge pixels are blurred" % [far_soft, far_edge])


# With only the fog on: pixels move toward the fog colour, the far box more than the near one (0.24 against
# 0.19 at these depths); and with the fog's height lowered to the plane, the top of the box, 1.5 m above it,
# gets less fog than the plane beside it.
func test_fog_shifts_far_pixels_toward_fog_color() -> void:
	var raw: Image = await _raw()
	var grade := GradeProfile.new()
	var post: Image = await _with(_only("fog_strength"), grade)
	var fog := grade.fog_color
	var far := _mask(_ints(raw), [FAR_A, FAR_B])
	var near := _near_mask(raw)
	var far_t := _mean_fog_share(raw, post, far, fog)
	var near_t := _mean_fog_share(raw, post, near, fog)
	assert_true(far_t["toward"] >= 0.99, "%.3f of the far pixels moved toward the fog" % far_t["toward"])
	assert_true(near_t["toward"] >= 0.99, "%.3f of the near pixels moved toward the fog" % near_t["toward"])
	assert_true(far_t["share"] > 0.2 and far_t["share"] < 0.3, "the far box is %.3f of the way to the fog" % far_t["share"])
	assert_true(near_t["share"] > 0.15 and near_t["share"] < 0.23, "the near box is %.3f of the way to the fog" % near_t["share"])
	assert_true(far_t["share"] > near_t["share"] + 0.02, "far %.3f is fogged more than near %.3f" % [far_t["share"], near_t["share"]])

	grade.fog_height = -1.0
	var low: Image = await _with(_only("fog_strength"), grade)
	var top := _mask(_ints(raw), [NEAR], [1.0])
	var ground := _mask(_ints(raw), [PLANE_A, PLANE_B], [1.0])
	# Only the ground beside the box: the same depth band, 1.5 m lower.
	var beside := PackedByteArray()
	beside.resize(W * H)
	for y in range(150, 210):
		for x in range(250, 390):
			beside[y * W + x] = ground[y * W + x]
	var top_t := _mean_fog_share(raw, low, top, fog)
	var ground_t := _mean_fog_share(raw, low, beside, fog)
	assert_true(top_t["share"] < 0.75 * ground_t["share"], "the box top (%.3f) is fogged less than the ground beside it (%.3f)" % [top_t["share"], ground_t["share"]])


func test_vignette_darkens_corners() -> void:
	var raw: Image = await _raw()
	var s := _only("vignette_strength")
	var post: Image = await _with(s)
	var bad := 0
	var examples := []
	var tolerance := _formula_tolerance(1.0)
	for y in H:
		for x in W:
			var uv := (Vector2(x + 1, y + 1) + Vector2(0.5, 0.5)) / Vector2(PixelStage.WORLD_SIZE)
			var k := 1.0 - s.vignette_strength * smoothstep(0.45, 0.85, (uv - Vector2(0.5, 0.5)).length() * 1.414)
			var expected := raw.get_pixel(x, y) * k
			if not _near(post.get_pixel(x, y), expected, tolerance):
				bad += 1
				if examples.size() < 5:
					examples.append("(%d,%d) %s, expected %s" % [x, y, post.get_pixel(x, y).to_html(false), expected.to_html(false)])
	assert_eq(bad, 0, "pixels off the vignette formula: %s" % [examples])
	for corner in [Vector2i(0, 0), Vector2i(W - 1, 0), Vector2i(0, H - 1), Vector2i(W - 1, H - 1)]:
		var r := raw.get_pixel(corner.x, corner.y)
		var p := post.get_pixel(corner.x, corner.y)
		assert_true(p.r < r.r * 0.7 and p.g < r.g * 0.7 and p.b < r.b * 0.7, "corner %s darkened: %s from %s" % [corner, p.to_html(false), r.to_html(false)])
	assert_true(_near(post.get_pixel(W / 2, H / 2), raw.get_pixel(W / 2, H / 2), STEP * 1.01), "the centre is untouched")


# With only the bloom on: each pixel gains bloom_strength x the weighted 3x3 (2 texels apart) of what its
# neighbours have above the threshold. The far box's cream top and the near box's top are above it. The
# strength is turned up to 1 here, so the shape of the weights shows clearly at the edges of bright areas.
func test_bloom_adds_what_is_above_the_threshold() -> void:
	var raw: Image = await _raw()
	var s := _only("bloom_strength")
	s.bloom_strength = 1.0
	var post: Image = await _with(s)
	var tolerance := _formula_tolerance(1.0 + s.bloom_strength)
	# What each raw pixel has above the threshold, channel by channel.
	var above: Array[Vector3] = []
	above.resize(W * H)
	for i in W * H:
		var t := raw.get_pixel(i % W, i / W)
		above[i] = Vector3(maxf(t.r - s.bloom_threshold, 0.0), maxf(t.g - s.bloom_threshold, 0.0), maxf(t.b - s.bloom_threshold, 0.0))
	var bad := 0
	var bloomed := 0
	var examples := []
	for y in range(2, H - 2):
		for x in range(2, W - 2):
			var glow := Vector3.ZERO
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var w := 0.25 if dx == 0 and dy == 0 else (0.125 if dx == 0 or dy == 0 else 0.0625)
					glow += w * above[(y + dy * 2) * W + x + dx * 2]
			var r := raw.get_pixel(x, y)
			var expected := Color(minf(r.r + s.bloom_strength * glow.x, 1.0), minf(r.g + s.bloom_strength * glow.y, 1.0), minf(r.b + s.bloom_strength * glow.z, 1.0))
			if not _near(post.get_pixel(x, y), expected, tolerance):
				bad += 1
				if examples.size() < 5:
					examples.append("(%d,%d) %s, expected %s" % [x, y, post.get_pixel(x, y).to_html(false), expected.to_html(false)])
			if not _near(post.get_pixel(x, y), r, STEP * 1.01):
				bloomed += 1
	assert_eq(bad, 0, "pixels off the bloom formula: %s" % [examples])
	assert_true(bloomed > 1000, "the bright tops bloom (%d pixels changed)" % bloomed)


# With only the grade on, in courtyard_dusk: every pixel is the brief's lift/gamma/gain, saturation and tint
# of its raw colour, and the picture is warmer.
func test_grade_follows_the_formula() -> void:
	var raw: Image = await _raw()
	var g := load(DUSK) as GradeProfile
	var post: Image = await _with(_only("grade_strength"), g)
	var bad := 0
	var examples := []
	var tolerance := _formula_tolerance(g.saturation)
	var warmth_raw := 0.0
	var warmth_post := 0.0
	for y in H:
		for x in W:
			var expected := _graded(raw.get_pixel(x, y), g)
			var p := post.get_pixel(x, y)
			if not _near(p, expected, tolerance):
				bad += 1
				if examples.size() < 5:
					examples.append("(%d,%d) %s, expected %s" % [x, y, p.to_html(false), expected.to_html(false)])
			warmth_raw += raw.get_pixel(x, y).r - raw.get_pixel(x, y).b
			warmth_post += p.r - p.b
	assert_eq(bad, 0, "pixels off the grade formula: %s" % [examples])
	assert_true(warmth_post > warmth_raw, "the grade warms the picture")


# With the whole look on, every internal pixel is still a clean 3x3 block of the window: both passes work
# texel by texel.
func test_the_look_keeps_pixels_crisp() -> void:
	stage.apply_settings(RenderSettings.new(), load(DUSK))
	await frames(5)
	var shot := get_viewport().get_texture().get_image()
	assert_eq(shot.get_size(), Vector2i(1920, 1080), "the test needs a 1920x1080 window")
	var mixed := 0
	for by in range(0, H, 7):
		for bx in range(0, W, 5):
			var first := shot.get_pixel(bx * 3, by * 3)
			for dy in 3:
				for dx in 3:
					if shot.get_pixel(bx * 3 + dx, by * 3 + dy) != first:
						mixed += 1
	assert_eq(mixed, 0, "pixels that differ from their block's first pixel")


# The look as the game has it (default settings, courtyard dusk) must come out of Forward+ as it does out
# of Compatibility. A Compatibility run with --update-golden writes the picture; a Forward+ run compares.
func test_forward_plus_matches_compatibility() -> void:
	var method := RenderingServer.get_current_rendering_method()
	if method != "forward_plus" and not (method == "gl_compatibility" and update_golden()):
		return
	var post: Image = await _with(RenderSettings.new(), load(DUSK))
	if method == "gl_compatibility":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GOLDEN.get_base_dir()))
		assert_eq(post.save_png(ProjectSettings.globalize_path(GOLDEN)), OK, "wrote the golden picture")
		return
	var golden := Image.load_from_file(ProjectSettings.globalize_path(GOLDEN))
	assert_ne(golden, null, "the golden picture loads; write it with tools/test.sh --render --update-golden")
	if golden == null:
		return
	golden.convert(Image.FORMAT_RGB8)
	assert_eq(golden.get_size(), post.get_size())
	var total := 0.0
	var within := 0
	for y in H:
		for x in W:
			var a := golden.get_pixel(x, y)
			var b := post.get_pixel(x, y)
			var d := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if d <= 8.0 * STEP + 1e-6:
				within += 1
	var mean := total / (W * H * 3)
	assert_true(mean <= 3.0 * STEP, "mean |diff| %.2f/255 is at most 3/255" % (mean * 255.0))
	assert_true(within >= 0.99 * W * H, "%.2f%% of pixels are within 8/255" % (100.0 * within / (W * H)))


# --- the scene ---

# A MeshInstance3D of `mesh` at `at` in flat_colour.gdshader.
func _flat(mesh: Mesh, at: Vector3, a: Color, b: Color, cell: float) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = FLAT
	material.set_shader_parameter(&"colour_a", Vector3(a.r, a.g, a.b))
	material.set_shader_parameter(&"colour_b", Vector3(b.r, b.g, b.b))
	material.set_shader_parameter(&"cell", cell)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	stage.world.add_child(instance)
	return instance


# Settings with every strength off but `strength`, which is at its default.
func _only(strength: String) -> RenderSettings:
	var s := RenderSettings.new().off()
	s.set(strength, RenderSettings.new().get(strength))
	return s


# The 640x360 picture with no post quad and no final material.
func _raw() -> Image:
	rig.post_quad.visible = false
	stage.material = null
	var img: Image = await _picture()
	rig.post_quad.visible = true
	stage.material = final_material
	return img


func _with(s: RenderSettings, g: GradeProfile = null) -> Image:
	stage.apply_settings(s, g)
	return await _picture()


# The 640x360 picture: the window's 1920x1080, one pixel of each 3x3 block.
func _picture() -> Image:
	await frames(5)
	var shot := get_viewport().get_texture().get_image()
	assert_eq(shot.get_size(), Vector2i(1920, 1080), "the test needs a 1920x1080 window")
	var img := shot.get_region(PixelStage.layout(shot.get_size()))
	img.resize(W, H, Image.INTERPOLATE_NEAREST)
	img.convert(Image.FORMAT_RGB8)
	return img


# --- comparing pictures ---

# Each pixel as 0xRRGGBB.
func _ints(img: Image) -> PackedInt32Array:
	var data := img.get_data()
	var ids := PackedInt32Array()
	ids.resize(W * H)
	for i in W * H:
		ids[i] = (data[i * 3] << 16) | (data[i * 3 + 1] << 8) | data[i * 3 + 2]
	return ids


# The largest channel difference between two 0xRRGGBB pixels, in 8-bit steps.
func _diff(a: int, b: int) -> int:
	return maxi(maxi(absi(((a >> 16) & 255) - ((b >> 16) & 255)), absi(((a >> 8) & 255) - ((b >> 8) & 255))), absi((a & 255) - (b & 255)))


# Whether every channel of `post` is at most `k` x that of `raw` (with one step of rounding).
func _darker_than(post: int, raw: int, k: float) -> bool:
	for shift in [16, 8, 0]:
		if float((post >> shift) & 255) > float((raw >> shift) & 255) * k + 1.0:
			return false
	return true


# Whether every channel of `post` is `k` x that of `raw`, give or take two steps.
func _scaled_to(post: int, raw: int, k: float) -> bool:
	for shift in [16, 8, 0]:
		if absf(float((post >> shift) & 255) - float((raw >> shift) & 255) * k) > 2.0:
			return false
	return true


func _colour_id(c: Color) -> int:
	return (roundi(c.r * 255.0) << 16) | (roundi(c.g * 255.0) << 8) | roundi(c.b * 255.0)


# 1 where the raw pixel is (within a step in each channel) one of `colours` under one of `shades`, else 0.
func _mask(ids: PackedInt32Array, colours: Array, shades: Array = SHADES) -> PackedByteArray:
	var wanted := {}
	for c: Color in colours:
		for s: float in shades:
			var id := _colour_id(c * s)
			for dr in [-1, 0, 1]:
				for dg in [-1, 0, 1]:
					for db in [-1, 0, 1]:
						wanted[id + (dr << 16) + (dg << 8) + db] = true
	var mask := PackedByteArray()
	mask.resize(W * H)
	for i in W * H:
		if wanted.has(ids[i]):
			mask[i] = 1
	return mask


func _near_mask(raw: Image) -> PackedByteArray:
	return _mask(_ints(raw), [NEAR])


# 1 where the raw pixel's whole 5x5 neighbourhood is one colour.
func _flat_mask(ids: PackedInt32Array) -> PackedByteArray:
	var rows := PackedByteArray()  # 1 where the five pixels from x-2 to x+2 are one colour
	rows.resize(W * H)
	for y in H:
		for x in range(2, W - 2):
			var i := y * W + x
			var c := ids[i]
			rows[i] = 1 if ids[i - 2] == c and ids[i - 1] == c and ids[i + 1] == c and ids[i + 2] == c else 0
	var flat := PackedByteArray()
	flat.resize(W * H)
	for y in range(2, H - 2):
		for x in range(2, W - 2):
			var i := y * W + x
			var c := ids[i]
			var all := true
			for dy in [-2, -1, 0, 1, 2]:
				var j: int = i + dy * W
				if rows[j] == 0 or ids[j] != c:
					all = false
					break
			flat[i] = 1 if all else 0
	return flat


func _count_differing(a: Image, b: Image, steps: int) -> Dictionary:
	var ia := _ints(a)
	var ib := _ints(b)
	var count := 0
	var examples := []
	for i in W * H:
		if _diff(ia[i], ib[i]) > steps:
			count += 1
			if examples.size() < 5:
				examples.append("(%d,%d) %06x, raw %06x" % [i % W, i / W, ib[i], ia[i]])
	return {"count": count, "examples": examples}


# Over the masked pixels: {toward: the share that moved toward `fog`, share: how far toward it they moved on
# average, as a fraction of the way from the raw colour to the fog colour}.
func _mean_fog_share(raw: Image, post: Image, mask: PackedByteArray, fog: Color) -> Dictionary:
	var count := 0
	var toward := 0
	var share := 0.0
	for i in W * H:
		if mask[i] == 0:
			continue
		var r := raw.get_pixel(i % W, i / W)
		var p := post.get_pixel(i % W, i / W)
		var to_fog := Vector3(fog.r - r.r, fog.g - r.g, fog.b - r.b)
		var moved := Vector3(p.r - r.r, p.g - r.g, p.b - r.b)
		if to_fog.length() < 0.1:
			continue
		count += 1
		if moved.dot(to_fog) > 0.0 and Vector3(fog.r - p.r, fog.g - p.g, fog.b - p.b).length() < to_fog.length():
			toward += 1
		share += moved.dot(to_fog) / to_fog.length_squared()
	if count == 0:
		return {"toward": 0.0, "share": 0.0}
	return {"toward": float(toward) / count, "share": share / count}


# How far a pixel may be from a final-pass formula worked from the raw picture, for a formula that
# multiplies small changes in its input by at most `gain`. In Compatibility the World picture the final
# pass reads holds more than 8 bits and the test sees it rounded to 8, so the input is known to half a
# step (times the gain), and the output is rounded to half a step again.
func _formula_tolerance(gain: float) -> float:
	return (0.5 * gain + 0.5 + 0.05) * STEP


func _near(a: Color, b: Color, eps: float) -> bool:
	return absf(a.r - b.r) <= eps and absf(a.g - b.g) <= eps and absf(a.b - b.b) <= eps


# The brief's grade of `c`, at full strength: pow(max(c x gain + lift x (1 - c), 0), 1 / gamma), then
# saturation around the luma (Rec. 709 weights), then x tint.
func _graded(c: Color, g: GradeProfile) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	var gain := Vector3(g.gain.r, g.gain.g, g.gain.b)
	var lift := Vector3(g.lift.r, g.lift.g, g.lift.b)
	var gamma := Vector3(g.gamma.r, g.gamma.g, g.gamma.b)
	var o := (v * gain + lift * (Vector3.ONE - v)).max(Vector3.ZERO)
	o = Vector3(pow(o.x, 1.0 / gamma.x), pow(o.y, 1.0 / gamma.y), pow(o.z, 1.0 / gamma.z))
	var luma := o.dot(Vector3(0.2126, 0.7152, 0.0722))
	o = Vector3(luma, luma, luma).lerp(o, g.saturation) * Vector3(g.tint.r, g.tint.g, g.tint.b)
	return Color(clampf(o.x, 0.0, 1.0), clampf(o.y, 0.0, 1.0), clampf(o.z, 0.0, 1.0))
