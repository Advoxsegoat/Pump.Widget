extends TestCase
## The Bilibara stretch's three ground textures (assets/env/textures/{cobble,tan_earth,snow}.png), made by
## tools/art/make_textures.gd, and the four materials that lay them (world/materials/): each a 2 m tile at 32 texels per
## metre, the same every time it is made. The colours are first values (the light task may move them); these tests hold
## the structure and the ranges.

const MAKE_TEXTURES := preload("res://tools/art/make_textures.gd")
const TEXTURES := "res://assets/env/textures/%s.png"
const MATERIALS := "res://world/materials/%s.tres"
const TOON := "res://render/shaders/toon_world.gdshader"


func _colours(img: Image) -> Dictionary:
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var key := img.get_pixel(x, y).to_html(false)
			counts[key] = counts.get(key, 0) + 1
	return counts


func _same_as_committed(maker: Callable, texture: String) -> void:
	var made := maker.call() as Image
	assert_eq(made.get_data(), (maker.call() as Image).get_data(), "%s: two makes are the same" % texture)
	var committed := Image.load_from_file(ProjectSettings.globalize_path(TEXTURES % texture))
	assert_true(committed != null, "%s: the committed texture loads" % texture)
	if committed != null:
		committed.convert(made.get_format())
		assert_eq(committed.get_data(), made.get_data(), "%s: the committed texture is what make_textures makes" % texture)


func _world_material(name: String, uv: bool) -> ShaderMaterial:
	var material := load(MATERIALS % name) as ShaderMaterial
	assert_true(material != null, "world/materials/%s.tres" % name)
	if material != null:
		assert_eq(material.shader.resource_path, TOON, "%s is drawn as the world is" % name)
		assert_eq(material.get_shader_parameter(&"world_uv"), uv, "%s: world_uv" % name)
	return material


func _ground_material(name: String) -> void:
	var material := _world_material(name, true)
	if material != null:
		assert_eq((material.get_shader_parameter(&"albedo_tex") as Texture2D).resource_path, TEXTURES % name)
		assert_eq(material.get_shader_parameter(&"texels_per_metre"), 32.0, "%s: 32 texels per metre" % name)


# The runs of texels that are not `joint` along a line of `length` texels, wrapping: the stones' lengths along it. A line
# with no joint at all is one run of the whole line.
func _runs(img: Image, joint: Color, vertical: bool, fixed: int) -> Array[int]:
	var length := 64
	var at := func(i: int) -> Color:
		return img.get_pixel(fixed, i) if vertical else img.get_pixel(i, fixed)
	var start := -1
	for i in length:
		if at.call(i) == joint:
			start = i
			break
	var runs: Array[int] = []
	if start < 0:
		return [length]
	var run := 0
	for k in length:
		var i := (start + 1 + k) % length
		if at.call(i) == joint:
			if run > 0:
				runs.append(run)
			run = 0
		else:
			run += 1
	if run > 0:
		runs.append(run)
	return runs


func test_cobble_is_a_calm_mosaic_of_setts_told_by_tone() -> void:
	var img := MAKE_TEXTURES.cobble()
	assert_eq(img.get_size(), Vector2i(64, 64), "64 x 64 texels: 2 m at 32 texels per metre")
	var counts := _colours(img)
	var joint := MAKE_TEXTURES.COBBLE_JOINT
	var frost := MAKE_TEXTURES.FROST
	var allowed := {joint.to_html(false): true, frost.to_html(false): true}
	var lowest := 1.0
	var highest := 0.0
	for cobble: Color in MAKE_TEXTURES.COBBLES:
		allowed[cobble.to_html(false)] = true
		lowest = minf(lowest, cobble.v)
		highest = maxf(highest, cobble.v)
		assert_true(cobble.b >= cobble.r, "%s leans blue" % cobble.to_html(false))
		assert_true(counts.get(cobble.to_html(false), 0) > 64, "%s covers %d texels" % [cobble.to_html(false), counts.get(cobble.to_html(false), 0)])
	for key: String in counts:
		assert_true(allowed.has(key), "%s is a stone, a joint or frost" % key)
	assert_true(highest - lowest <= 0.12 + 1e-6, "the stones span %.3f in value, at most 0.12" % (highest - lowest))
	assert_true(joint.v < lowest and joint.v >= lowest - 0.10 - 1e-6, "the joint (%.3f) is darker than every stone (%.3f) by at most 0.10" % [joint.v, lowest])
	assert_true(frost.v <= 0.62, "frost is no brighter than 0.62 (%.3f)" % frost.v)
	assert_true(frost.b > frost.r, "frost is cold")
	var frosted: int = counts.get(frost.to_html(false), 0)
	assert_true(frosted > 0 and frosted <= 4096 * 0.06, "frost covers %d texels, at most 6%%" % frosted)
	# No snow: nothing in the tile is brighter than frost.
	for y in 64:
		for x in 64:
			assert_true(img.get_pixel(x, y).v <= 0.62 + 1e-6, "(%d, %d) is not bright" % [x, y])


# Setts 5 to 9 texels wide and 5 to 7 deep (the joint included), of at least three widths; the rows wobble and are laid
# in an irregular bond, so no straight joint crosses the tile.
func test_cobble_setts_are_irregular_and_no_joint_runs_straight() -> void:
	var img := MAKE_TEXTURES.cobble()
	var joint := MAKE_TEXTURES.COBBLE_JOINT
	var widths := {}
	var firsts := {}
	var runs_seen := 0
	var runs_fit := 0
	for y in 64:
		var joints := 0
		var first := -1
		for x in 64:
			if img.get_pixel(x, y) == joint:
				joints += 1
				if first < 0:
					first = x
		assert_true(joints <= 64 * 0.7, "texture row %d is %d texels of joint" % [y, joints])
		if joints < 16:
			firsts[first] = true
		for run in _runs(img, joint, false, y):
			runs_seen += 1
			if run >= 4 and run <= 8:
				runs_fit += 1
				widths[run + 1] = true
	assert_true(runs_fit >= runs_seen * 0.8, "%d of %d runs between joints are 4 to 8 texels (a joint line's edge cuts the rest short)" % [runs_fit, runs_seen])
	assert_true(widths.size() >= 3, "setts of at least three widths: %s" % [widths.keys()])
	assert_true(firsts.size() >= 4, "at least four different row offsets: %s" % [firsts.keys()])
	for x in 64:
		var joints := 0
		for y in 64:
			joints += int(img.get_pixel(x, y) == joint)
		assert_true(joints <= 64 * 0.7, "texture column %d is %d texels of joint" % [x, joints])
		for run in _runs(img, joint, true, x):
			assert_true(run >= 2 and run <= 8, "column %d: a sett %d texels deep" % [x, run])


func test_cobble_is_made_the_same_every_time_and_has_its_material() -> void:
	_same_as_committed(MAKE_TEXTURES.cobble, "cobble")
	_ground_material("cobble")


# The texel changes between column `a` and column `b` (and likewise rows): how many rows differ.
func _column_changes(img: Image, a: int, b: int) -> int:
	var n := 0
	for y in 64:
		n += int(img.get_pixel(a, y) != img.get_pixel(b, y))
	return n


func _row_changes(img: Image, a: int, b: int) -> int:
	var n := 0
	for x in 64:
		n += int(img.get_pixel(x, a) != img.get_pixel(x, b))
	return n


func test_tan_earth_is_three_earths_with_lime_stains_that_wrap() -> void:
	var img := MAKE_TEXTURES.tan_earth()
	assert_eq(img.get_size(), Vector2i(64, 64), "64 x 64 texels")
	var counts := _colours(img)
	assert_eq(counts.size(), 4, "three earths and a lime: %s" % [counts.keys()])
	for earth: Color in MAKE_TEXTURES.EARTHS:
		var key := earth.to_html(false)
		assert_true(earth.r > earth.g and earth.g > earth.b, "%s is warm" % key)
		assert_true(earth.v >= 0.25 and earth.v <= 0.45, "%s is a mid-dark earth" % key)
		assert_true(counts.get(key, 0) > 4096 / 8, "%s covers %d texels" % [key, counts.get(key, 0)])
	var lime: int = counts.get(MAKE_TEXTURES.LIME.to_html(false), 0)
	assert_true(lime >= 4096 * 0.02 and lime <= 4096 * 0.08, "lime covers %d of 4096 texels" % lime)
	# The seam is no busier than the tile's inside.
	var inner_columns := 0
	var inner_rows := 0
	for i in 63:
		inner_columns += _column_changes(img, i, i + 1)
		inner_rows += _row_changes(img, i, i + 1)
	assert_true(_column_changes(img, 63, 0) <= 1.5 * inner_columns / 63.0, "the seam between columns 63 and 0 has %d changes (average %.1f)" % [_column_changes(img, 63, 0), inner_columns / 63.0])
	assert_true(_row_changes(img, 63, 0) <= 1.5 * inner_rows / 63.0, "the seam between rows 63 and 0 has %d changes (average %.1f)" % [_row_changes(img, 63, 0), inner_rows / 63.0])


func test_tan_earth_is_made_the_same_every_time_and_has_its_material() -> void:
	_same_as_committed(MAKE_TEXTURES.tan_earth, "tan_earth")
	_ground_material("tan_earth")


# The connected pieces of `colour` in the image (four-neighbour, wrapping): their sizes.
func _clumps(img: Image, colour: Color) -> Array[int]:
	var seen := {}
	var sizes: Array[int] = []
	for y in 64:
		for x in 64:
			if img.get_pixel(x, y) != colour or seen.has(Vector2i(x, y)):
				continue
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[Vector2i(x, y)] = true
			var size := 0
			while not stack.is_empty():
				var at: Vector2i = stack.pop_back()
				size += 1
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next := Vector2i(posmod(at.x + step.x, 64), posmod(at.y + step.y, 64))
					if img.get_pixel(next.x, next.y) == colour and not seen.has(next):
						seen[next] = true
						stack.append(next)
			sizes.append(size)
	return sizes


func test_snow_is_a_cold_blue_grey_with_clumps_of_shadow_and_has_its_material() -> void:
	var img := MAKE_TEXTURES.snow()
	assert_eq(img.get_size(), Vector2i(64, 64), "64 x 64 texels")
	var counts := _colours(img)
	assert_eq(counts.size(), 2, "two tones: %s" % [counts.keys()])
	var light: Color = MAKE_TEXTURES.SNOWS[0]
	var shadow: Color = MAKE_TEXTURES.SNOWS[1]
	assert_true(light.v <= 0.72 and light.v > 0.62, "the light tone is %.3f: a light ground, not white" % light.v)
	assert_true(shadow.v >= 0.58 and shadow.v <= 0.66 and shadow.v < light.v, "the shadow tone is %.3f" % shadow.v)
	assert_true(shadow.b - shadow.r > light.b - light.r, "and bluer")
	assert_true(light.b > light.r, "cold")
	var share: int = counts.get(shadow.to_html(false), 0)
	assert_true(share >= 4096 * 0.05 and share <= 4096 * 0.15, "the shadow covers %d of 4096 texels" % share)
	var clumps := _clumps(img, shadow)
	assert_true(clumps.size() > 10, "%d clumps" % clumps.size())
	for size in clumps:
		assert_true(size >= 2 and size <= 5, "a clump of %d texels, not 2 to 5" % size)
	_same_as_committed(MAKE_TEXTURES.snow, "snow")
	_ground_material("snow")


func test_liquor_is_a_dark_brown_flat_material() -> void:
	var material := _world_material("liquor", false)
	if material == null:
		return
	var texture := material.get_shader_parameter(&"albedo_tex") as GradientTexture2D
	assert_true(texture != null, "a gradient texture")
	if texture == null:
		return
	assert_eq(Vector2i(texture.width, texture.height), Vector2i(1, 1), "1 x 1")
	var colour := texture.gradient.colors[0]
	assert_eq(colour.to_html(false), "4a3a2e", "the liquor's brown")
	assert_true(colour.v <= 0.35, "dark")


# F0 set every ground texture's import so that the editor never switches it to lossy VRAM compression when it is drawn in
# 3D: that would blur the exact colours (and leave a dirty tree after the first editor session).
func test_no_ground_texture_is_recompressed_by_the_editor() -> void:
	var seen := 0
	for file in DirAccess.get_files_at("res://assets/env/textures"):
		if not file.ends_with(".png.import"):
			continue
		seen += 1
		var config := ConfigFile.new()
		assert_eq(config.load("res://assets/env/textures/" + file), OK, file)
		assert_eq(config.get_value("params", "detect_3d/compress_to", -1), 0, "%s: detect_3d/compress_to" % file)
	assert_true(seen >= 5, "the textures' imports were found (%d)" % seen)
