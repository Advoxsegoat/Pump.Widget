extends TestCase
## The stretch's grounds are pale (trodden snow over cobbles, pale slate, snow-dusted earth, pale stone): the texture a fighter stands on is
## 0.50 to 0.80 in luma (the light and the grade bring it to 0.62 to 0.74 in the picture: see test_bilibara_readability), its grain is soft
## (neighbouring texels within 0.05 in luma), and what is darker than the grain (the joints, the trodden setts, the tan patches) is shapes of
## at least three texels, never a lone texel: no static. The yard's own flagstone and slate are untouched (test_bilibara_textures).

const MAKE_TEXTURES := preload("res://tools/art/make_textures.gd")
const SOFT := 0.05
const MOST_ALONE := 0


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# The ground textures: name, the image, the colours that are not grain (joints, trodden setts, tan patches), and its mean luma's range.
func _grounds() -> Array:
	return [
		["cobble", MAKE_TEXTURES.cobble(), [MAKE_TEXTURES.COBBLE_JOINT, MAKE_TEXTURES.TRODDEN], 0.55, 0.80],
		["tan_earth", MAKE_TEXTURES.tan_earth(), [MAKE_TEXTURES.TAN], 0.55, 0.80],
		["slate_cold", MAKE_TEXTURES.slate_cold(), [MAKE_TEXTURES.SLATE_COLD_JOINT], 0.50, 0.80],
		["slate_pale", MAKE_TEXTURES.slate_pale(), [MAKE_TEXTURES.SLATE_PALE_JOINT], 0.50, 0.80],
		["flagstone_cold", MAKE_TEXTURES.flagstone_cold(), [MAKE_TEXTURES.FLAGSTONE_COLD_MORTAR], 0.55, 0.80],
	]


func test_every_ground_is_pale() -> void:
	for ground: Array in _grounds():
		var img := ground[1] as Image
		var sum := 0.0
		for y in img.get_height():
			for x in img.get_width():
				sum += _luma(img.get_pixel(x, y))
		var mean := sum / (img.get_width() * img.get_height())
		assert_true(mean >= ground[3] and mean <= ground[4], "%s: mean luma %.3f, expected %.2f to %.2f" % [ground[0], mean, ground[3], ground[4]])


func test_the_grain_is_soft() -> void:
	for ground: Array in _grounds():
		var img := ground[1] as Image
		var features := {}
		for c: Color in ground[2]:
			features[c.to_html(false)] = true
		var worst := 0.0
		var at := Vector2i.ZERO
		for y in img.get_height():
			for x in img.get_width():
				var here := img.get_pixel(x, y)
				if features.has(here.to_html(false)):
					continue
				for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var other := img.get_pixel(posmod(x + step.x, img.get_width()), posmod(y + step.y, img.get_height()))
					if features.has(other.to_html(false)):
						continue
					var d := absf(_luma(here) - _luma(other))
					if d > worst:
						worst = d
						at = Vector2i(x, y)
		assert_true(worst <= SOFT + 1e-6, "%s: grain texels differ by %.3f at %s (at most %.2f)" % [ground[0], worst, at, SOFT])


func test_what_is_darker_than_the_grain_is_a_shape_never_a_speck() -> void:
	for ground: Array in _grounds():
		var img := ground[1] as Image
		var features := {}
		for c: Color in ground[2]:
			features[c.to_html(false)] = true
		var w := img.get_width()
		var h := img.get_height()
		var seen := {}
		var smallest := 9999
		var count := 0
		for y in h:
			for x in w:
				var start := Vector2i(x, y)
				if seen.has(start) or not features.has(img.get_pixelv(start).to_html(false)):
					continue
				var stack: Array[Vector2i] = [start]
				seen[start] = true
				var size := 0
				while not stack.is_empty():
					var p: Vector2i = stack.pop_back()
					size += 1
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var q := Vector2i(posmod(p.x + dx, w), posmod(p.y + dy, h))
							if not seen.has(q) and features.has(img.get_pixelv(q).to_html(false)):
								seen[q] = true
								stack.append(q)
				smallest = mini(smallest, size)
				count += 1
		assert_true(count > 0, "%s has its joints or patches" % ground[0])
		assert_true(smallest >= 3, "%s: a shape of %d texel(s) among %d (at least 3)" % [ground[0], smallest, count])


func test_no_texel_is_a_light_speck() -> void:
	for ground: Array in _grounds():
		var img := ground[1] as Image
		var specks := 0
		var w := img.get_width()
		var h := img.get_height()
		for y in h:
			for x in w:
				var here := _luma(img.get_pixel(x, y))
				var brighter_than_all := true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if (dx != 0 or dy != 0) and here - _luma(img.get_pixel(posmod(x + dx, w), posmod(y + dy, h))) <= SOFT:
							brighter_than_all = false
				if brighter_than_all:
					specks += 1
		assert_true(specks <= MOST_ALONE, "%s has %d texels brighter than all eight neighbours by over %.2f" % [ground[0], specks, SOFT])
