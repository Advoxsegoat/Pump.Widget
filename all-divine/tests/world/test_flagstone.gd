extends TestCase
## The courtyard's flagstones (assets/env/textures/flagstone.png), made by tools/art/make_textures.gd: a 2 m
## tile at 32 texels per metre, in four stone greys warmed toward rose and a darker mortar, the same every
## time it is made.

const MAKE_TEXTURES := preload("res://tools/art/make_textures.gd")
const FLAGSTONE := "res://assets/env/textures/flagstone.png"


func _colours(img: Image) -> Dictionary:
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var key := img.get_pixel(x, y).to_html(false)
			counts[key] = counts.get(key, 0) + 1
	return counts


func test_flagstone_is_a_2_m_tile_of_four_stones_and_mortar() -> void:
	var img := MAKE_TEXTURES.flagstone()
	assert_eq(img.get_size(), Vector2i(64, 64), "64 x 64 texels: 2 m at 32 texels per metre")
	var counts := _colours(img)
	assert_eq(counts.size(), 5, "four stone greys and a mortar: %s" % [counts.keys()])
	var by_value := counts.keys()
	by_value.sort_custom(func(a: String, b: String) -> bool: return Color(a).v < Color(b).v)
	if by_value.size() != 5:
		return
	var mortar := Color(by_value[0])
	for key: String in by_value.slice(1):
		var stone := Color(key)
		# Greys warmed toward rose: barely saturated, red the strongest, blue above green.
		assert_true(stone.s < 0.15, "%s is a grey" % key)
		assert_true(stone.r > stone.g and stone.r > stone.b and stone.b >= stone.g, "%s leans rose" % key)
		assert_true(stone.v > mortar.v + 0.1, "the mortar %s is darker than %s" % [mortar.to_html(false), key])
	# The mortar is lines, not the bulk of the tile; every stone grey is well used.
	assert_true(counts[by_value[0]] < 1024, "the mortar covers %d texels" % counts[by_value[0]])
	for key: String in by_value.slice(1):
		assert_true(counts[key] > 256, "%s covers %d texels" % [key, counts[key]])


# Every mortar line is one texel wide, where it crosses the tile's edge too, so the floor shows no seam every
# 2 m: no two full rows of mortar are next to each other (wrapping bottom to top), and along a row of stones no
# two mortar texels are side by side (wrapping right to left).
func test_mortar_lines_are_one_texel_wide_across_the_edges() -> void:
	var img := MAKE_TEXTURES.flagstone()
	var mortar := MAKE_TEXTURES.MORTAR
	var full_rows: Array[int] = []
	for y in 64:
		if range(64).all(func(x: int) -> bool: return img.get_pixel(x, y) == mortar):
			full_rows.append(y)
	assert_true(full_rows.size() >= 2, "rows of stones, with mortar between them (%s)" % [full_rows])
	for y in full_rows:
		assert_false(full_rows.has((y + 1) % 64), "mortar rows %d and %d touch" % [y, (y + 1) % 64])
	var wide := 0
	var joints := 0
	for y in 64:
		if full_rows.has(y):
			continue
		for x in 64:
			if img.get_pixel(x, y) == mortar:
				joints += 1
				if img.get_pixel((x + 1) % 64, y) == mortar:
					wide += 1
	assert_true(joints > 0, "the stones in a row have joints between them")
	assert_eq(wide, 0, "joint texels with mortar beside them")


func test_flagstone_is_made_the_same_every_time() -> void:
	var a := MAKE_TEXTURES.flagstone()
	var b := MAKE_TEXTURES.flagstone()
	assert_eq(a.get_data(), b.get_data(), "two makes are the same")
	var committed := Image.load_from_file(ProjectSettings.globalize_path(FLAGSTONE))
	assert_ne(committed, null, "the committed texture loads")
	if committed != null:
		committed.convert(a.get_format())
		assert_eq(committed.get_data(), a.get_data(), "the committed texture is what make_textures makes")
