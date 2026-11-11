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


func test_cobble_is_a_2_m_tile_of_four_cobbles_with_snow_in_the_joints() -> void:
	var img := MAKE_TEXTURES.cobble()
	assert_eq(img.get_size(), Vector2i(64, 64), "64 x 64 texels: 2 m at 32 texels per metre")
	var counts := _colours(img)
	assert_eq(counts.size(), 5, "four cobbles and a snow joint: %s" % [counts.keys()])
	var joint_key := MAKE_TEXTURES.SNOW_JOINT.to_html(false)
	assert_true(counts.has(joint_key), "the joint is SNOW_JOINT")
	assert_true(MAKE_TEXTURES.SNOW_JOINT.v >= 0.6, "snow is pale")
	for cobble: Color in MAKE_TEXTURES.COBBLES:
		var key := cobble.to_html(false)
		assert_true(cobble.v >= 0.22 and cobble.v <= 0.42, "%s is a dark stone" % key)
		assert_true(cobble.b >= cobble.r, "%s leans blue" % key)
		assert_true(counts.get(key, 0) > 64, "%s covers %d texels" % [key, counts.get(key, 0)])
	var joints: int = counts.get(joint_key, 0)
	assert_true(joints >= 64 * 64 * 0.08 and joints <= 64 * 64 * 0.25, "joints cover %d of 4096 texels" % joints)


# Every joint is one texel wide, where it crosses the tile's edge too: no two full joint rows touch (wrapping bottom to
# top), and along a row of cobbles no two joint texels are side by side (wrapping right to left).
func test_cobble_joints_are_one_texel_wide_across_the_edges() -> void:
	var img := MAKE_TEXTURES.cobble()
	var joint := MAKE_TEXTURES.SNOW_JOINT
	var full_rows: Array[int] = []
	for y in 64:
		if range(64).all(func(x: int) -> bool: return img.get_pixel(x, y) == joint):
			full_rows.append(y)
	assert_true(full_rows.size() >= 2, "rows of cobbles, with a joint between them (%s)" % [full_rows])
	for y in full_rows:
		assert_false(full_rows.has((y + 1) % 64), "joint rows %d and %d touch" % [y, (y + 1) % 64])
	var wide := 0
	var joints := 0
	for y in 64:
		if full_rows.has(y):
			continue
		for x in 64:
			if img.get_pixel(x, y) == joint:
				joints += 1
				if img.get_pixel((x + 1) % 64, y) == joint:
					wide += 1
	assert_true(joints > 0, "the cobbles in a row have joints between them")
	assert_eq(wide, 0, "joint texels with a joint beside them")


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


func test_snow_is_two_whites_and_has_its_material() -> void:
	var img := MAKE_TEXTURES.snow()
	assert_eq(img.get_size(), Vector2i(64, 64), "64 x 64 texels")
	var counts := _colours(img)
	assert_eq(counts.size(), 2, "two whites: %s" % [counts.keys()])
	for snow: Color in MAKE_TEXTURES.SNOWS:
		assert_true(snow.v >= 0.85, "%s is white" % snow.to_html(false))
	var speckle: int = counts.get(MAKE_TEXTURES.SNOWS[1].to_html(false), 0)
	assert_true(speckle >= 4096 * 0.05 and speckle <= 4096 * 0.15, "the second white covers %d of 4096 texels" % speckle)
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
