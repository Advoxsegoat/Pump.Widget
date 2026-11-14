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
		assert_true(earth.v >= 0.05 and earth.v <= 0.20, "%s is a dark earth (the grade lifts it into the readability band)" % key)
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


# --- Bilibara's own colours for the kit ---

const KIT_COLORMAP := "res://assets/env/kenney_town/Textures/colormap.png"
const BILIBARA_COLORMAP := "res://assets/env/textures/bilibara_colormap.png"


func _kit_colormap() -> Image:
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(KIT_COLORMAP))
	img.convert(Image.FORMAT_RGB8)
	return img


# The kit's colormap drawn in Bilibara's colours: every one of its colours (1,900-odd, swatches and their shading) is
# given a colour, none loud: saturation at most 0.40, value at most 0.72. Roofs are slate-indigo, plaster a cold stone of
# value 0.50 to 0.66, timber and trim a dull rose-gold, boards dark wood.
func test_bilibara_colormap_gives_every_kit_colour_a_quiet_one() -> void:
	var kit := _kit_colormap()
	var made := MAKE_TEXTURES.bilibara_colormap()
	assert_eq(made.get_size(), kit.get_size(), "the same size as the kit's")
	var seen := {}
	for y in kit.get_height():
		for x in kit.get_width():
			var from := kit.get_pixel(x, y)
			var to := made.get_pixel(x, y)
			if seen.has(from.to_html(false)):
				assert_eq(to, seen[from.to_html(false)], "a colour is always mapped to the same colour")
				continue
			seen[from.to_html(false)] = to
			assert_true(to.s <= 0.40 + 1e-3 and to.v <= 0.72 + 1e-3, "%s becomes %s: saturation %.2f, value %.2f" % [from.to_html(false), to.to_html(false), to.s, to.v])
			if from != Color.BLACK:
				assert_ne(to, from, "%s is changed" % from.to_html(false))
	assert_true(seen.size() > 1500, "the kit's map has %d colours" % seen.size())
	var roof: Color = seen["45a087"]
	var roof_red: Color = seen["c74a5c"]
	var plaster: Color = seen["adb5d9"]
	var shade: Color = seen["8d93b1"]
	var trim: Color = seen["cc8665"]
	var board: Color = seen["794939"]
	assert_true(roof.v <= 0.40 and roof.b > roof.g and roof.b > roof.r, "the cyan roof is slate-indigo (%s)" % roof.to_html(false))
	assert_true(roof_red.v <= 0.32 and roof_red.b > roof_red.g, "the pink roof is a dark plum-indigo (%s)" % roof_red.to_html(false))
	assert_true(plaster.v >= 0.50 and plaster.v <= 0.66 and plaster.b >= plaster.r, "plaster is a cold stone (%s)" % plaster.to_html(false))
	assert_true(shade.v >= 0.45 and shade.v < plaster.v, "and its shade a little darker (%s)" % shade.to_html(false))
	assert_true(trim.r > trim.g and trim.g > trim.b and trim.v >= 0.40 and trim.v <= 0.66, "trim is a dull rose-gold (%s)" % trim.to_html(false))
	assert_true(board.v <= 0.46 and board.r >= board.b, "boards are dark wood (%s)" % board.to_html(false))


func test_bilibara_colormap_is_made_the_same_every_time_and_has_its_material() -> void:
	var made := MAKE_TEXTURES.bilibara_colormap()
	assert_eq(made.get_data(), MAKE_TEXTURES.bilibara_colormap().get_data(), "two makes are the same")
	var committed := Image.load_from_file(ProjectSettings.globalize_path(BILIBARA_COLORMAP))
	assert_true(committed != null, "the committed colormap loads")
	if committed != null:
		committed.convert(made.get_format())
		assert_eq(committed.get_data(), made.get_data(), "the committed colormap is what make_textures makes")
	var material := _world_material("kenney_town_bilibara", false)
	if material != null:
		assert_eq((material.get_shader_parameter(&"albedo_tex") as Texture2D).resource_path, BILIBARA_COLORMAP)
		assert_eq(material.get_shader_parameter(&"texels_per_metre"), 32.0)


# --- The cold stones (the stretch's court, alcove and yard square) and the training yard's own stones, left alone ---

## The md5 of the training yard's flagstone.png and slate.png as they were before this task: the stretch draws its own darker copies.
const FLAGSTONE_MD5 := "1e21e11f7a445c0ad64a2326a41f80c3"
const SLATE_MD5 := "63708a753dbadb81215e45ab74672665"


func test_the_training_yards_stones_are_unchanged_pixel_for_pixel() -> void:
	for pair: Array in [["flagstone", FLAGSTONE_MD5], ["slate", SLATE_MD5]]:
		var bytes := FileAccess.get_file_as_bytes(TEXTURES % pair[0])
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_MD5)
		hash.update(bytes)
		assert_eq(hash.finish().hex_encode(), pair[1], "%s.png is the file the training yard was made with" % pair[0])
	_same_as_committed(MAKE_TEXTURES.flagstone, "flagstone")
	_same_as_committed(MAKE_TEXTURES.slate, "slate")


func test_the_cold_stones_are_the_yards_stones_drawn_darker_and_cooler() -> void:
	for pair: Array in [["slate_cold", MAKE_TEXTURES.slate_cold, MAKE_TEXTURES.slate, MAKE_TEXTURES.SLATE_COLD], ["flagstone_cold", MAKE_TEXTURES.flagstone_cold, MAKE_TEXTURES.flagstone, MAKE_TEXTURES.FLAGSTONE_COLD]]:
		var cold := (pair[1] as Callable).call() as Image
		var warm := (pair[2] as Callable).call() as Image
		assert_eq(cold.get_size(), Vector2i(64, 64), "%s: a 2 m tile" % pair[0])
		var by: Vector3 = pair[3]
		assert_true(by.x < by.z and by.z <= 1.0, "%s is drawn cooler (blue at least red) and no brighter" % pair[0])
		for at in [Vector2i(0, 0), Vector2i(17, 5), Vector2i(40, 33), Vector2i(63, 63)]:
			var a := warm.get_pixelv(at)
			var b := cold.get_pixelv(at)
			assert_true(absf(b.r8 - a.r8 * by.x) <= 1.0 and absf(b.g8 - a.g8 * by.y) <= 1.0 and absf(b.b8 - a.b8 * by.z) <= 1.0, "%s at %s is the yard's stone times %s" % [pair[0], at, by])
		_same_as_committed(pair[1], pair[0])
		_ground_material(pair[0])


# --- The roofs: shingles in two tones, a dark eave, snow along the ridge ---

const TOON_ROOF := "res://render/shaders/toon_roof.gdshader"


func _is_snow(c: Color) -> bool:
	return c.v >= 0.62 and c.s <= 0.06


# Row `row`'s shingle part at `dy` down it (0 to 15), column x.
func _at(img: Image, row: int, dy: int, x: int) -> Color:
	return img.get_pixel(x, row * 16 + dy)


func test_a_roof_tile_is_five_rows_of_shingles_in_two_tones() -> void:
	for pair: Array in [[MAKE_TEXTURES.ROOF_SLATE, MAKE_TEXTURES.ROOF_SLATE_SEED], [MAKE_TEXTURES.ROOF_TANNERY, MAKE_TEXTURES.ROOF_TANNERY_SEED]]:
		var tones: Array[Color] = []
		tones.assign(pair[0])
		var img := MAKE_TEXTURES.roof(tones, pair[1])
		assert_eq(img.get_size(), Vector2i(80, 80), "80 x 80 texels: 2.5 m across, five rows of 16 texels")
		# The two tones both show among the shingles' middle lines of the three lowest rows, and nothing else but their speckle does.
		var seen := {}
		for row in range(2, 5):
			for x in 80:
				seen[_at(img, row, 6, x).to_html(false)] = true
		for tone in tones:
			assert_true(seen.has(tone.to_html(false)), "tone %s is among the shingles" % tone.to_html(false))
		assert_eq(seen.size(), 2, "and only the two (%s)" % [seen.keys()])
		# The lower three texels of a row are in the shadow of the row above (0.78 of a tone); the lowest row ends in a dark eave (0.55).
		var shaded := {}
		var eaves := {}
		for tone in tones:
			shaded[Color8(roundi(tone.r8 * MAKE_TEXTURES.ROOF_UNDER), roundi(tone.g8 * MAKE_TEXTURES.ROOF_UNDER), roundi(tone.b8 * MAKE_TEXTURES.ROOF_UNDER)).to_html(false)] = true
			eaves[Color8(roundi(tone.r8 * MAKE_TEXTURES.ROOF_EAVE), roundi(tone.g8 * MAKE_TEXTURES.ROOF_EAVE), roundi(tone.b8 * MAKE_TEXTURES.ROOF_EAVE)).to_html(false)] = true
		for row in range(2, 4):
			for x in [3, 20, 41, 60]:
				assert_true(shaded.has(_at(img, row, 14, x).to_html(false)), "row %d x %d: its lower edge is a tone at 0.78 (%s)" % [row, x, _at(img, row, 14, x).to_html(false)])
		for x in [3, 20, 41, 60]:
			assert_true(eaves.has(_at(img, 4, 14, x).to_html(false)), "the eave at x %d is a tone at 0.55 (%s)" % [x, _at(img, 4, 14, x).to_html(false)])
		# Alternate rows are shifted half a shingle: the joints (where the tone most of a column of a row shows changes) of rows 2 and 3 never
		# fall in the same columns.
		var edges := func(row: int) -> Array[int]:
			var majority := PackedInt32Array()
			for x in 80:
				var first := 0
				for dy in 13:
					if _at(img, row, dy, x) == tones[0]:
						first += 1
				majority.append(1 if first >= 7 else 0)
			var found: Array[int] = []
			for x in 80:
				if majority[x] != majority[(x + 79) % 80]:
					found.append(x)
			return found
		var even: Array[int] = edges.call(2)
		var odd: Array[int] = edges.call(3)
		assert_true(even.size() >= 1 and odd.size() >= 1, "each row changes tone between shingles (%d, %d places)" % [even.size(), odd.size()])
		for x in odd:
			assert_false(even.has(x), "a joint of row 3 at x %d is not under a joint of row 2" % x)
		# It tiles across: the seam between columns 79 and 0 is no busier than twice the tile's inside (the random speckle makes any one pair of
		# columns differ in 6 to 18 texels).
		var inner := 0
		for i in 79:
			inner += _column_changes(img, i, i + 1)
		assert_true(_column_changes(img, 79, 0) <= 2.0 * inner / 79.0, "the seam has %d changes (average %.1f)" % [_column_changes(img, 79, 0), inner / 79.0])


func test_snow_lies_along_the_ridge_as_a_band_with_a_broken_edge_and_no_blue() -> void:
	var tones: Array[Color] = []
	tones.assign(MAKE_TEXTURES.ROOF_SLATE)
	var img := MAKE_TEXTURES.roof(tones, MAKE_TEXTURES.ROOF_SLATE_SEED)
	var snow := 0
	var lowest := PackedInt32Array()
	var top_row_snow := 0
	var below_snow := 0
	for x in 80:
		var bottom := -1
		for y in 80:
			var c := img.get_pixel(x, y)
			if _is_snow(c):
				snow += 1
				bottom = y
				assert_true(c.b - c.r <= 6.0 / 255.0, "snow at (%d, %d) has no blue cast (%s)" % [x, y, c.to_html(false)])
				if y < 16:
					top_row_snow += 1
				if y >= 48:
					below_snow += 1
		lowest.append(bottom)
	assert_true(snow >= 80 * 80 * 0.12 and snow <= 80 * 80 * 0.35, "snow covers %d of 6400 texels" % snow)
	assert_true(top_row_snow >= 80 * 16 * 0.9, "the top row is snow (%d of 1280)" % top_row_snow)
	assert_eq(below_snow, 0, "no snow on the lower rows")
	var least := 99
	var most := -1
	for y in lowest:
		least = mini(least, y)
		most = maxi(most, y)
	assert_true(most - least >= 8, "the band's edge is not straight: its lowest texel runs from row %d to %d" % [least, most])
	# Dithered: in the edge zone there are snow texels with the roof's tone beside and under them, and roof texels in among the snow.
	var strays := 0
	for y in range(8, 40):
		for x in range(1, 79):
			if _is_snow(img.get_pixel(x, y)) and not _is_snow(img.get_pixel(x, y + 1)) and not _is_snow(img.get_pixel(x - 1, y)) and not _is_snow(img.get_pixel(x + 1, y)):
				strays += 1
	assert_true(strays >= 8, "the edge is broken into single texels (%d)" % strays)
	# Two snow tones: lit and shaded.
	var tones_seen := {}
	for y in 40:
		for x in 80:
			if _is_snow(img.get_pixel(x, y)):
				tones_seen[img.get_pixel(x, y).to_html(false)] = true
	assert_true(tones_seen.has(MAKE_TEXTURES.ROOF_SNOW_LIT.to_html(false)) and tones_seen.has(MAKE_TEXTURES.ROOF_SNOW_SHADE.to_html(false)), "snow has a lit and a shaded tone (%s)" % [tones_seen.keys()])


func test_roofs_are_slate_blue_and_brown_red_and_made_the_same_every_time_with_their_materials() -> void:
	var slate: Color = MAKE_TEXTURES.ROOF_SLATE[0]
	var tannery: Color = MAKE_TEXTURES.ROOF_TANNERY[0]
	assert_true(slate.b - slate.r >= 25.0 / 255.0, "slate is blue (%s)" % slate.to_html(false))
	assert_true(tannery.r - tannery.b >= 25.0 / 255.0 and tannery.r > tannery.g, "the tannery's roof is brown-red (%s)" % tannery.to_html(false))
	for pair: Array in [["roof_slate", MAKE_TEXTURES.ROOF_SLATE, MAKE_TEXTURES.ROOF_SLATE_SEED], ["roof_tannery", MAKE_TEXTURES.ROOF_TANNERY, MAKE_TEXTURES.ROOF_TANNERY_SEED]]:
		var tones: Array[Color] = []
		tones.assign(pair[1])
		_same_as_committed(func() -> Image: return MAKE_TEXTURES.roof(tones, pair[2]), pair[0])
		var material := load(MATERIALS % pair[0]) as ShaderMaterial
		assert_true(material != null, "world/materials/%s.tres" % pair[0])
		if material != null:
			assert_eq(material.shader.resource_path, TOON_ROOF, "%s is drawn by the roof shader" % pair[0])
			assert_eq((material.get_shader_parameter(&"albedo_tex") as Texture2D).resource_path, TEXTURES % pair[0], "%s has its texture" % pair[0])


# --- Brown wood, darker trim, and the pink neon of the banners ---

const NEON_COLORMAP := "res://assets/env/textures/bilibara_neon_colormap.png"


func test_wood_reads_brown_and_trim_and_doors_are_darker_than_the_plaster_they_sit_in() -> void:
	var made := MAKE_TEXTURES.bilibara_colormap()
	var kit := _kit_colormap()
	var find := func(hex: String) -> Color:
		for y in kit.get_height():
			for x in kit.get_width():
				if kit.get_pixel(x, y).to_html(false) == hex:
					return made.get_pixel(x, y)
		return Color.BLACK
	var plaster: Color = find.call("adb5d9")
	var shade: Color = find.call("8d93b1")
	for hex: String in ["9c5e48", "85503e", "794939"]:
		var wood: Color = find.call(hex)
		assert_true(wood.h >= 0.04 and wood.h <= 0.11 and wood.s >= 0.30 and wood.r > wood.g and wood.g > wood.b, "%s is a brown (%s: hue %.2f, saturation %.2f), not a mauve plaster" % [hex, wood.to_html(false), wood.h, wood.s])
		assert_true(wood.v <= 0.46 and wood.v < shade.v - 0.10, "%s is darker than the plaster's shade (%.2f against %.2f)" % [hex, wood.v, shade.v])
	for hex: String in ["cc8665", "b87758", "c27f5f"]:
		var trim: Color = find.call(hex)
		assert_true(trim.v <= shade.v - 0.04 and trim.v >= 0.40, "%s (trim, shutters) is darker than the plaster's shade (%.2f against %.2f)" % [hex, trim.v, shade.v])
	assert_true(plaster.v >= 0.50, "and the plaster is still pale")


func test_the_banners_are_hot_pink_and_glow() -> void:
	var neon := MAKE_TEXTURES.bilibara_neon_colormap()
	var kit := _kit_colormap()
	var plain := MAKE_TEXTURES.bilibara_colormap()
	var seen_pink := 0
	for hex: String in ["ee535a", "c74a5c", "df4f5b", "d74d5b"]:
		for y in kit.get_height():
			var found := false
			for x in kit.get_width():
				if kit.get_pixel(x, y).to_html(false) == hex:
					var c := neon.get_pixel(x, y)
					assert_true(c.h >= 0.88 and c.h <= 0.96 and c.s >= 0.55 and c.v >= 0.85, "banner red %s is hot pink (%s: hue %.2f, saturation %.2f, value %.2f)" % [hex, c.to_html(false), c.h, c.s, c.v])
					seen_pink += 1
					found = true
					break
			if found:
				break
	assert_eq(seen_pink, 4, "all four reds were found")
	# Everything else the banner carries (its rose-gold trim) is as the town's colours are.
	for y in kit.get_height():
		for x in kit.get_width():
			var from := kit.get_pixel(x, y)
			if from.h > 0.02 and from.h < 0.12 and from.s > 0.3:
				assert_eq(neon.get_pixel(x, y), plain.get_pixel(x, y), "%s keeps the town's trim colour" % from.to_html(false))
	var material := _world_material("kenney_town_neon", false)
	if material != null:
		assert_eq((material.get_shader_parameter(&"albedo_tex") as Texture2D).resource_path, NEON_COLORMAP)
		assert_true(float(material.get_shader_parameter(&"glow")) >= 0.5, "the neon glows (it adds its own colour to what the light gives)")
	var committed := Image.load_from_file(ProjectSettings.globalize_path(NEON_COLORMAP))
	assert_true(committed != null, "the committed neon colormap loads")
	if committed != null:
		committed.convert(neon.get_format())
		assert_eq(committed.get_data(), neon.get_data(), "the committed neon colormap is what make_textures makes")
