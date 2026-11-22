extends SceneTree
## Makes the textures we draw ourselves:
##   tools/godot.sh -s res://tools/art/make_textures.gd
## writes assets/env/textures/flagstone.png, slate.png, cobble.png, tan_earth.png, snow.png, slate_cold.png, slate_pale.png and flagstone_cold.png
## (the training yard's stones drawn darker and colder for the stretch's grounds) and bilibara_colormap.png (the Kenney kit's colormap
## in Bilibara's colours), the same bytes every time. Run `tools/godot.sh --import`
## afterwards. Exits 0, or 1 if a file could not be written.

const OUT_DIR := "res://assets/env/textures"
const KIT_COLORMAP := "res://assets/env/kenney_town/Textures/colormap.png"
## Texels per metre in the world, and the flagstone tile's side: 2 m, so 64 texels.
const TEXELS_PER_METRE := 32
const FLAGSTONE_SIZE := 2 * TEXELS_PER_METRE
const FLAGSTONE_SEED := 7
## The stone greys, darkest first: greys of value 0.55, 0.61, 0.67 and 0.73, each a tenth of the way toward
## Abarax's rose (#e8607e), so the courtyard's stone is warm without being pink.
const STONES: Array[Color] = [Color8(149, 136, 139), Color8(163, 150, 152), Color8(177, 163, 166), Color8(191, 177, 180)]
## The mortar between them: a grey of 0.38, an eighth of the way toward the rose.
const MORTAR := Color8(113, 97, 100)
## A stone row is about 12 to 20 texels high (0.375 to 0.625 m) and a stone 10 to 26 texels long, the mortar
## included: a one-texel line along each row's bottom and at each stone's right end.
const ROW_MIN := 12
const ROW_MAX := 20
const STONE_MIN := 10
const STONE_MAX := 26
## The share of a stone's texels shown in the next grey up or down, so a stone is not one flat colour.
const SPECKLE := 0.07
## The kerbstones: two dark blue-grey slates and the joint between two stones. They are dark because the training yard's
## kerb is lit by its moon, as the fighters are (the kerb must show in the dark): moonlit, these read as pale stone.
const SLATES: Array[Color] = [Color8(58, 60, 70), Color8(66, 68, 79)]
const SLATE_JOINT := Color8(40, 41, 49)
const SLATE_SIZE := 2 * TEXELS_PER_METRE
const SLATE_SEED := 11
## A kerbstone is this many texels long, its joint included: a metre.
const KERBSTONE := TEXELS_PER_METRE
## Bilibara's street at noon: trodden snow over cobbles, pale cold setts with cool grey joints, told by tone and not by bright lines. A sett is 5 to 9 texels
## wide and 5 to 7 deep, its joint included; the rows wobble (a row's lower edge steps a texel from sett to sett) and are laid
## in an irregular bond, so no straight joint crosses the tile (the camera draws a texel row 0.64 of a pixel tall, and a
## straight bright joint would be dropped and found again as it moves). The joints are a little darker than the darkest
## stone, and a few whole setts are trodden greyer. The grain is soft (the four stones are within 0.05 in luma) and nothing is a
## single bright or dark texel: a pale ground with speckle reads as static. (The colours are tuned in the picture: see the
## readability test.)
const COBBLES: Array[Color] = [Color8(190, 185, 178), Color8(186, 181, 175), Color8(182, 177, 171), Color8(178, 174, 168)]
const COBBLE_JOINT := Color8(145, 146, 147)
## A trodden sett: the whole sett a little greyer than the rest (snow trodden down over it), a patch and never a speck.
const TRODDEN := Color8(169, 168, 165)
const COBBLE_SEED := 13
const COBBLE_DEPTH_MIN := 5
const COBBLE_DEPTH_MAX := 7
const COBBLE_WIDTH_MIN := 5
const COBBLE_WIDTH_MAX := 9
## The share of setts that are trodden.
const TRODDEN_SETTS := 0.25
## The Tanneries' earth under snow: three pale greys (the snow trodden flat) in blotches 4 to 8 texels across, with a warm grey-tan
## showing through in patches (whole blotches, about one in eight): packed earth in tracks and patches, not a brown field.
const EARTHS: Array[Color] = [Color8(174, 169, 161), Color8(171, 165, 158), Color8(167, 162, 155)]
const TAN := Color8(150, 139, 125)
## The share of blotches that are tan: one in twelve, in large patches whose edge is soft (four texels of the way between the tan and the earth beside it).
const TAN_SHARE := 0.08
const EARTH_SEED := 17
const BLOTCH_MIN := 8
const BLOTCH_MAX := 20
## How many texels a tan patch's soft edge is.
const SOFT_EDGE := 4
## The earth's tile is 20 m a side (640 texels): the picture shows 20 m of ground across, so no pattern of it repeats in a picture (a 2 m tile
## showed the same blotches in rows 64 pixels apart: wallpaper).
const EARTH_SIZE := 20 * TEXELS_PER_METRE
## Snow (the drifts and the apron, off the ground a fighter walks on): the palest ground of the stretch, a cold near-white laid so that the stretch's light
## (which lifts a texture by a tenth in red, a seventh in green and a quarter in blue) does not clip it: no channel over SNOW_BRIGHTEST here, 244 or so in the
## picture. SNOW_LIGHT is its brightest tone and SNOW_SHADE the bluer, darker tone in the dips of its grain: wind ripples (a long wave across the tile, bent
## by a slow noise) and footfall dimples (soft noise four texels across), blended between the two, never a single odd texel.
const SNOW_LIGHT := Color8(186, 192, 197)
const SNOW_SHADE := Color8(163, 173, 188)
const SNOW_BRIGHTEST := 200
## The ripples' wave across the tile (whole cycles, so that it wraps), the share of the dip they and the dimples each give, and the cell of the dimples.
const SNOW_WAVE := Vector2i(4, 2)
const SNOW_RIPPLE := 0.45
const SNOW_DIMPLE_CELL := 4
const SNOW_SEED := 19
## The wood of the fronts (doors, shutters, timber, boards) in the colormap: value WOOD_BASE + WOOD_SLOPE * the kit's value; the trim about TRIM_BASE. This is the
## lightest wood that leaves every body's head standing out at every measured place (a tier III's head is 0.28 to 0.29, and a sunlit face of this wood reads up
## to 0.22 in the picture): at WOOD_BASE 0.12 the worst head is 30% of its ring, and a step of 0.005 more takes one place to 64% (the rule is under 50%).
## The saturation is as high as the colormap's cap (0.40, with room for 8-bit rounding), so that a dark wood still reads brown.
const WOOD_BASE := 0.12
const WOOD_SLOPE := 0.132
const TRIM_BASE := 0.168
const WOOD_SAT := 0.36
const TRIM_SAT := 0.36
const TRIM_SLOPE := 0.163


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for made: Array in [["flagstone.png", flagstone()], ["slate.png", slate()], ["cobble.png", cobble()],
			["tan_earth.png", tan_earth()], ["snow.png", snow()], ["slate_cold.png", slate_cold()], ["slate_pale.png", slate_pale()], ["flagstone_cold.png", flagstone_cold()],
			["roof_slate.png", roof(ROOF_SLATE, ROOF_SLATE_SEED)], ["roof_tannery.png", roof(ROOF_TANNERY, ROOF_TANNERY_SEED)],
			["bilibara_colormap.png", bilibara_colormap()], ["bilibara_neon_colormap.png", bilibara_neon_colormap()]]:
		var path := OUT_DIR.path_join(made[0])
		var error := (made[1] as Image).save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			printerr("make_textures: could not write %s (%s)" % [path, error_string(error)])
			quit(1)
			return
		print("make_textures: wrote %s" % path)
	quit(0)


## The courtyard's floor: a 2 m tile of flagstones laid in rows, each stone one of the four STONES greys
## (speckled with the next grey up or down), set in MORTAR. It tiles seamlessly: the rows and the stones in
## each row wrap around the tile's edges. The same seeded random numbers (FLAGSTONE_SEED) make the same tile.
static func flagstone() -> Image:
	var grey := _slabs(FLAGSTONE_SEED, FLAGSTONE_SIZE, ROW_MIN, ROW_MAX, STONE_MIN, STONE_MAX, STONES.size(), SPECKLE)
	var bytes := PackedByteArray()
	bytes.resize(FLAGSTONE_SIZE * FLAGSTONE_SIZE * 3)
	for i in FLAGSTONE_SIZE * FLAGSTONE_SIZE:
		var c := MORTAR if grey[i] < 0 else STONES[grey[i]]
		bytes[i * 3] = c.r8
		bytes[i * 3 + 1] = c.g8
		bytes[i * 3 + 2] = c.b8
	return Image.create_from_data(FLAGSTONE_SIZE, FLAGSTONE_SIZE, false, Image.FORMAT_RGB8, bytes)


# A size x size tile of stones laid in rows (see flagstone), each texel the index of its stone's tone (of `tones`) or -1 for a joint: rows
# `row_min` to `row_max` texels high, stones `stone_min` to `stone_max` long, each row's joints somewhere else, `speckle` the share of a stone's
# texels in the next tone up or down. The same seeded random numbers make the same tile.
static func _slabs(seed_value: int, size: int, row_min: int, row_max: int, stone_min: int, stone_max: int, tones: int, speckle: float) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Each texel's colour: an index into the tones, or -1 for mortar.
	var grey := PackedInt32Array()
	grey.resize(size * size)
	grey.fill(-1)
	var y0 := 0
	for height in _split(rng, size, row_min, row_max):
		# Each row's joints start somewhere else, so no joint lines up with the row above's.
		var x0 := rng.randi_range(0, size - 1)
		var last := -1
		for length in _split(rng, size, stone_min, stone_max):
			var g := rng.randi_range(0, tones - 1)
			if g == last:
				g = (g + 1 + rng.randi_range(0, tones - 2)) % tones
			last = g
			# The stone, less its mortar: its last column and its row's last line.
			for dy in height - 1:
				for dx in length - 1:
					var speckled := g
					if rng.randf() < speckle:
						speckled = clampi(g + (1 if rng.randf() < 0.5 else -1), 0, tones - 1)
					grey[(y0 + dy) * size + (x0 + dx) % size] = speckled
			x0 += length
		y0 += height
	return grey


## The training yard's kerb: a 2 m tile of two kerbstones, each a metre long and one of the two SLATES (speckled with
## the other), with a SLATE_JOINT one texel wide at its right end. There is no line across the stones: laid by the world's
## metres on a kerb's top and on its face, the joints of the two meet at the kerb's edge. It tiles seamlessly; the same
## seeded random numbers (SLATE_SEED) make the same tile.
static func slate() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = SLATE_SEED
	var size := SLATE_SIZE
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	for y in size:
		for x in size:
			var c := SLATE_JOINT
			if x % KERBSTONE != KERBSTONE - 1:
				@warning_ignore("integer_division")
				var stone := (x / KERBSTONE) % SLATES.size()
				if rng.randf() < SPECKLE:
					stone = (stone + 1) % SLATES.size()
				c = SLATES[stone]
			var i := (y * size + x) * 3
			bytes[i] = c.r8
			bytes[i + 1] = c.g8
			bytes[i + 2] = c.b8
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)


## Bilibara's street: a 2 m tile of setts (see COBBLES), each a row's sett of one of the four tones, with a one-texel joint
## under it and at its end; the rows' lower edges sit a texel above, on or below their line, sett by sett. It tiles seamlessly; the same seeded
## random numbers (COBBLE_SEED) make the same tile.
static func cobble() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = COBBLE_SEED
	var size := FLAGSTONE_SIZE
	var depths := _split_within(rng, size, COBBLE_DEPTH_MIN, COBBLE_DEPTH_MAX)
	# Each row's setts: {x, length, tone, step, trodden}, and the joint's y under the row at every column.
	var rows: Array[Array] = []
	var edges: Array[PackedInt32Array] = []
	var bottom := 0
	for depth in depths:
		bottom += depth
		var setts: Array = []
		var x := rng.randi_range(0, size - 1)
		var last_tone := -1
		var edge := PackedInt32Array()
		edge.resize(size)
		# The steps are dealt like cards (every three setts hold one of each), so that no line of the row holds most of the
		# joints, which would be a straight joint across the tile.
		var deal: Array[int] = []
		for length in _split_within(rng, size, COBBLE_WIDTH_MIN, COBBLE_WIDTH_MAX):
			if deal.is_empty():
				deal = [-1, 0, 1]
				for i in [2, 1]:
					var j := rng.randi_range(0, i)
					var held := deal[i]
					deal[i] = deal[j]
					deal[j] = held
			var step: int = deal.pop_back()
			var tone := rng.randi_range(0, COBBLES.size() - 1)
			if tone == last_tone:
				tone = (tone + 1 + rng.randi_range(0, COBBLES.size() - 2)) % COBBLES.size()
			last_tone = tone
			setts.append({x = x, length = length, tone = tone, step = step, trodden = rng.randf() < TRODDEN_SETTS})
			for dx in length:
				edge[(x + dx) % size] = bottom + step
			x += length
		rows.append(setts)
		edges.append(edge)
	var colours: Array[Color] = []
	colours.resize(size * size)
	colours.fill(COBBLE_JOINT)
	for r in rows.size():
		var above := edges[r - 1] if r > 0 else edges[rows.size() - 1]
		var above_shift := 0 if r > 0 else size
		for sett: Dictionary in rows[r]:
			for dx in sett.length:
				var column: int = (sett.x + dx) % size
				var joint_here: int = edges[r][column]
				for y in range(above[column] - above_shift + 1, joint_here):
					var c := COBBLES[sett.tone]
					if dx == sett.length - 1:
						c = COBBLE_JOINT
					elif sett.trodden:
						c = TRODDEN
					colours[posmod(y, size) * size + column] = c
	return _image(colours, size)


## The Tanneries' ground: a 2 m tile of earth in blotches 4 to 8 texels across, laid as a lattice (each band of blotches
## cut at its own places, so no seam runs the tile's length), one of the three EARTHS each or, one in eight, TAN. Every band and every column is cut so that the tile's edge falls inside a blotch: it tiles seamlessly. The same
## seeded random numbers (EARTH_SEED) make the same tile.
static func tan_earth() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = EARTH_SEED
	var size := EARTH_SIZE
	var colours: Array[Color] = []
	colours.resize(size * size)
	var base: Array[Color] = []  # the earth under a tan blotch: what its edge softens toward
	base.resize(size * size)
	var rows := _split(rng, size, BLOTCH_MIN, BLOTCH_MAX)
	# The bands start half a blotch before row 0, so that the last row meets the first inside one band.
	var y0 := -(rows[0] >> 1)
	var above := PackedInt32Array()
	for height in rows:
		var columns := _split(rng, size, BLOTCH_MIN, BLOTCH_MAX)
		var x0 := -(columns[0] >> 1)
		var earths := PackedInt32Array()
		for length in columns:
			var e := rng.randi_range(0, EARTHS.size() - 1)
			# Not the earth to its left, nor the one above it, so that every blotch shows.
			while (not earths.is_empty() and e == earths[-1]) or (above.size() > earths.size() and e == above[earths.size()]):
				e = rng.randi_range(0, EARTHS.size() - 1)
			earths.append(e)
			var tan := rng.randf() < TAN_SHARE
			for dy in height:
				for dx in length:
					colours[posmod(y0 + dy, size) * size + posmod(x0 + dx, size)] = TAN if tan else EARTHS[e]
					base[posmod(y0 + dy, size) * size + posmod(x0 + dx, size)] = EARTHS[e]
			x0 += length
		above = earths
		y0 += height
	# A soft edge: the earth texels one to four texels from a tan one go four fifths, three fifths, two fifths and a fifth of the way to the tan,
	# so that no two neighbouring texels of the patch differ by more than 0.05 in luma (two earths differ by 0.03 themselves).
	var softened := colours.duplicate()
	for y in size:
		for x in size:
			var i := y * size + x
			if colours[i] == TAN:
				continue
			var nearest := SOFT_EDGE + 1
			for dy in range(-SOFT_EDGE, SOFT_EDGE + 1):
				for dx in range(-SOFT_EDGE, SOFT_EDGE + 1):
					if colours[posmod(y + dy, size) * size + posmod(x + dx, size)] == TAN:
						nearest = mini(nearest, maxi(absi(dy), absi(dx)))
			if nearest <= SOFT_EDGE:
				softened[i] = base[i].lerp(TAN, 1.0 - nearest / float(SOFT_EDGE + 1))
	return _image(softened, size)


## Snow: a 2 m tile of SNOW_LIGHT with grain: where the ripples and the dimples dip, the tone goes toward SNOW_SHADE. It wraps. The same seeded random
## numbers (SNOW_SEED) make the same tile.
static func snow() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = SNOW_SEED
	var size := FLAGSTONE_SIZE
	var bend := _soft_noise(rng, size, 16)
	var dimples := _soft_noise(rng, size, SNOW_DIMPLE_CELL)
	var colours: Array[Color] = []
	for y in size:
		for x in size:
			var i := y * size + x
			var wave := TAU * (SNOW_WAVE.x * x + SNOW_WAVE.y * y) / size + (bend[i] - 0.5) * 3.0
			var ripple := 0.5 + 0.5 * sin(wave)
			var dip := clampf(SNOW_RIPPLE * ripple + (1.0 - SNOW_RIPPLE) * dimples[i] * 0.9, 0.0, 1.0)
			colours.append(SNOW_LIGHT.lerp(SNOW_SHADE, dip))
	return _image(colours, size)


## The stretch's court and alcove slate: the training yard's kerbstones (slate()) redrawn pale and cold, stone for stone (the same
## shapes, each of slate()'s colours replaced by its cold one), so that the ground under the fighters is pale (see the readability test).
## slate() itself is unchanged.
## The court's slate is laid in slabs of uneven size (0.45 to 0.75 m by 0.7 to 1.4 m, in rows), five cool greys of which the last is the darker slab
## (one slab in five), with a soft grain, the joints a cool grey and a little trodden snow lying in them (the yard's flagstone is laid the same way).
const SLATE_COLD_SIZE := 2 * TEXELS_PER_METRE
const SLATE_COLD_SEED := 31
const SLATE_COLD_TONES: Array[Color] = [Color8(163, 165, 169), Color8(169, 171, 175), Color8(175, 177, 181), Color8(181, 183, 186), Color8(149, 152, 157)]
const SLATE_COLD_JOINT := Color8(130, 134, 140)
const SLATE_COLD_SNOW := Color8(186, 191, 196)
## The alcove's slate is half in the shade of the works beside it: the same slate a hand paler (1.08 of the court's), so that its ground is in
## the readability band in the shade as the court's is in the sun.
const SLATE_PALE_STONES: Array[Color] = [Color8(166, 166, 166), Color8(170, 170, 170)]
const SLATE_PALE_JOINT := Color8(133, 136, 139)
## The yard's stone square in the same way (flagstone() unchanged): pale stone, a step paler than the slate border.
const FLAGSTONE_COLD_STONES: Array[Color] = [Color8(161, 156, 150), Color8(165, 160, 153), Color8(169, 163, 155), Color8(172, 166, 158)]
const FLAGSTONE_COLD_MORTAR := Color8(137, 134, 133)


## The roofs: one tile of a roof is 2.5 m across and 2.5 m up its piece, drawn from the ridge (the top of the picture) to the eave (the
## bottom): ROOF_ROWS rows of shingles, each ROOF_ROW texels (about 0.6 m up the slope) deep and ROOF_SHINGLE texels wide, alternate rows
## shifted half a shingle, each shingle one of two tones of the roof's colour. The lower ROOF_UNDER_TEXELS of a row are in the shadow of
## the row above, the lowest row ends in a dark eave, and snow lies along the ridge as a band with a broken, dithered edge (the roof's tone
## showing through), in a lit tone with shaded pockets under its edge and no blue in it. It tiles across (the snow's edge wraps).
const ROOF_SIZE := 80
const ROOF_ROWS := 5
const ROOF_ROW := 16
const ROOF_SHINGLE := 16
const ROOF_UNDER_TEXELS := 3
const ROOF_UNDER := 0.78
const ROOF_EAVE_TEXELS := 5
const ROOF_EAVE := 0.55
## The slate-blue of the stone fronts' roofs and the brown-red of the tannery works': two tones each.
const ROOF_SLATE: Array[Color] = [Color8(91, 108, 139), Color8(106, 124, 158)]
const ROOF_TANNERY: Array[Color] = [Color8(147, 100, 91), Color8(164, 113, 101)]
const ROOF_SLATE_SEED := 23
const ROOF_TANNERY_SEED := 29
## Snow on a roof: lit, and in the shade of its own edge; neutral, a hair cool, never blue.
const ROOF_SNOW_LIT := Color8(214, 217, 219)
const ROOF_SNOW_SHADE := Color8(204, 207, 210)


static func roof(tones: Array[Color], seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := ROOF_SIZE
	var per_row := size / ROOF_SHINGLE
	# Each shingle's tone, row by row (never the tone of the one before it in its row).
	var picks: Array[PackedInt32Array] = []
	for row in ROOF_ROWS:
		var line := PackedInt32Array()
		for k in per_row:
			var pick := rng.randi_range(0, tones.size() - 1)
			if k > 0 and per_row % 2 == 0 and pick == line[k - 1] and rng.randf() < 0.5:
				pick = (pick + 1) % tones.size()
			line.append(pick)
		picks.append(line)
	var colours: Array[Color] = []
	colours.resize(size * size)
	for row in ROOF_ROWS:
		var shift := (row % 2) * (ROOF_SHINGLE / 2)
		for dy in ROOF_ROW:
			for x in size:
				var k := ((x + size - shift) % size) / ROOF_SHINGLE
				var pick: int = picks[row][k]
				if rng.randf() < SPECKLE:
					pick = (pick + 1) % tones.size()
				var c := tones[pick]
				if row == ROOF_ROWS - 1 and dy >= ROOF_ROW - ROOF_EAVE_TEXELS:
					c = Color8(roundi(c.r8 * ROOF_EAVE), roundi(c.g8 * ROOF_EAVE), roundi(c.b8 * ROOF_EAVE))
				elif dy >= ROOF_ROW - ROOF_UNDER_TEXELS:
					c = Color8(roundi(c.r8 * ROOF_UNDER), roundi(c.g8 * ROOF_UNDER), roundi(c.b8 * ROOF_UNDER))
				colours[(row * ROOF_ROW + dy) * size + x] = c
	# The snow: a band along the ridge, dithered over six texels at its lower edge so that the shingles show through, with shaded pockets just
	# inside the edge. The edge is a row of level runs (8 to 24 columns, each a level of its own within three rows of the middle, a little ragged), not a wave:
	# a wave read as a row of pointed teeth. It wraps with the tile.
	var runs := _split(rng, size, 8, 24)
	var levels := PackedFloat32Array()
	for r in runs.size():
		var level := 19.0 + rng.randi_range(-3, 3)
		if r > 0 and absf(level - levels[r - 1]) < 1.0:
			level += 2.0
		levels.append(level)
	var edges := PackedFloat32Array()
	for r in runs.size():
		for k in runs[r]:
			edges.append(levels[r] + rng.randf_range(-0.5, 0.5))
	for x in size:
		var edge := edges[x]
		for y in 40:
			var snowy := false
			if y < edge - 3.0:
				snowy = true
			elif y < edge + 3.0:
				snowy = rng.randf() < (edge + 3.0 - y) / 6.0
			if snowy:
				# Snow lies in rows over the shingles' rows: the lower texels of each row are in its shade, as the shingles' are.
				var shaded := y % ROOF_ROW >= ROOF_ROW - ROOF_UNDER_TEXELS or (y >= edge - 6.0 and rng.randf() < 0.45)
				colours[y * size + x] = ROOF_SNOW_SHADE if shaded else ROOF_SNOW_LIT
	return _image(colours, size)


## The banners' own colormap (world/materials/kenney_town_neon.tres): the town's colours with the kit's reds drawn as hot pink and its teal as a
## pale violet-pink: the neon, the one hot colour of the street. Only the banner pieces wear it (KitDresser.banner_material).
static func bilibara_neon_colormap() -> Image:
	var kit := Image.new()
	kit.load_png_from_buffer(FileAccess.get_file_as_bytes(KIT_COLORMAP))
	kit.convert(Image.FORMAT_RGB8)
	var made := {}
	var colours: Array[Color] = []
	for y in kit.get_height():
		for x in kit.get_width():
			var from := kit.get_pixel(x, y)
			var key := from.to_rgba32()
			if not made.has(key):
				made[key] = bilibara_neon_colour(from)
			colours.append(made[key])
	return _image(colours, kit.get_width())


## What the kit's colour `c` becomes on a banner: the reds hot pink, the teals pale violet-pink, everything else as bilibara_colour.
static func bilibara_neon_colour(c: Color) -> Color:
	if c.v > 0.0 and c.s > 0.5:
		if c.h >= 0.95 or c.h < 0.02:
			return Color.from_hsv(0.92, 0.66, 0.84 + 0.15 * c.v)
		if c.h >= 0.40 and c.h < 0.55:
			return Color.from_hsv(0.85, 0.5, 0.80 + 0.15 * c.v)
	return bilibara_colour(c)


static func slate_cold() -> Image:
	var size := SLATE_COLD_SIZE
	var grey := _slabs(SLATE_COLD_SEED, size, 14, 24, 22, 44, SLATE_COLD_TONES.size(), 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = SLATE_COLD_SEED + 1
	var grain := _soft_noise(rng, size, 8)
	var snow := _soft_noise(rng, size, 6)
	var colours: Array[Color] = []
	for y in size:
		for x in size:
			var i := y * size + x
			var c: Color
			if grey[i] < 0:
				# A joint: a cool grey shape, with a little trodden snow lying in it here and there.
				c = SLATE_COLD_SNOW if snow[i] > 0.72 else SLATE_COLD_JOINT
			else:
				# A slab: its tone and a soft grain (slow waves and a very little noise, neighbours within 0.02).
				var shade := (grain[i] - 0.5) * 0.045 + (rng.randf() - 0.5) * 0.012
				c = SLATE_COLD_TONES[grey[i]]
				c = Color(c.r + shade, c.g + shade, c.b + shade)
			colours.append(c)
	# Snow lies in runs, never as a lone pale texel (that reads as static): a snow texel with no snow beside it is joint again.
	var checked := colours.duplicate()
	for y in size:
		for x in size:
			if checked[y * size + x] != SLATE_COLD_SNOW:
				continue
			var company := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if (dx != 0 or dy != 0) and checked[posmod(y + dy, size) * size + posmod(x + dx, size)] == SLATE_COLD_SNOW:
						company += 1
			if company == 0:
				colours[y * size + x] = SLATE_COLD_JOINT
	return _image(colours, size)


# A size x size field of smooth noise from 0 to 1, tiling, from random values on a grid `cell` texels apart, blended between (smoothstep).
static func _soft_noise(rng: RandomNumberGenerator, size: int, cell: int) -> PackedFloat32Array:
	@warning_ignore("integer_division")
	var n := size / cell
	var lattice := PackedFloat32Array()
	for i in n * n:
		lattice.append(rng.randf())
	var out := PackedFloat32Array()
	out.resize(size * size)
	for y in size:
		for x in size:
			var gx := float(x) / cell
			var gy := float(y) / cell
			var x0 := floori(gx)
			var y0 := floori(gy)
			var fx := smoothstep(0.0, 1.0, gx - x0)
			var fy := smoothstep(0.0, 1.0, gy - y0)
			var v00 := lattice[posmod(y0, n) * n + posmod(x0, n)]
			var v10 := lattice[posmod(y0, n) * n + posmod(x0 + 1, n)]
			var v01 := lattice[posmod(y0 + 1, n) * n + posmod(x0, n)]
			var v11 := lattice[posmod(y0 + 1, n) * n + posmod(x0 + 1, n)]
			out[y * size + x] = lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)
	return out


static func slate_pale() -> Image:
	return _recoloured(slate(), SLATES + [SLATE_JOINT], SLATE_PALE_STONES + [SLATE_PALE_JOINT])


static func flagstone_cold() -> Image:
	return _recoloured(flagstone(), STONES + [MORTAR], FLAGSTONE_COLD_STONES + [FLAGSTONE_COLD_MORTAR])


# `img` with each colour of `from` replaced by the one at the same place in `to` (a new image; a colour not in `from` is kept).
static func _recoloured(img: Image, from: Array, to: Array) -> Image:
	var map := {}
	for i in from.size():
		map[from[i].to_html(false)] = to[i]
	var colours: Array[Color] = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			colours.append(map.get(c.to_html(false), c))
	return _image(colours, img.get_width())


## The Kenney kit's colormap drawn in Bilibara's colours: each of its colours (the flat swatches and their shading) is
## replaced by bilibara_colour's, so a kit piece keeps its light and dark parts and loses its toy-town colours. A pure
## mapping: the same bytes every time. The kit has one colormap, so a layout that says `kit bilibara` draws every piece in
## the result (world/materials/kenney_town_bilibara.tres).
static func bilibara_colormap() -> Image:
	var kit := Image.new()
	kit.load_png_from_buffer(FileAccess.get_file_as_bytes(KIT_COLORMAP))
	kit.convert(Image.FORMAT_RGB8)
	var made := {}
	var colours: Array[Color] = []
	for y in kit.get_height():
		for x in kit.get_width():
			var from := kit.get_pixel(x, y)
			var key := from.to_rgba32()
			if not made.has(key):
				made[key] = bilibara_colour(from)
			colours.append(made[key])
	return _image(colours, kit.get_width())


## What the kit's colour `c` becomes in Bilibara (the book's slate-indigo mansards, cold Beaux-Arts stone and dull
## rose-gold trim). The kit's colours fall in a few families, by hue; each family keeps its own light and dark, laid on a
## narrow range of value, so that walls are mid-value (a white jacket and a dark coat both stand out against them) and nothing
## is loud: saturation never over 0.40 and value never over 0.72. First values: the snow-noon light may move them.
##   blue-greys and neutrals (plaster, stone, white): cold stone, value 0.30 + 0.45 v (a pale plaster 0.68: the fronts stand between the roofs and the pale ground)
##   warm oranges and peaches (trim, frames, shutters): dull rose-gold, the darker browns (boards) dark wood
##   cyan and teal (the roofs), and the saturated blues and violets: slate-indigo
##   reds and pinks (the other roof): a dark plum
##   greens (trees, hedges): a dark muted green
static func bilibara_colour(c: Color) -> Color:
	if c.v <= 0.0:
		return c
	var h := c.h
	var s := c.s
	var v := c.v
	if s < 0.04:
		return Color.from_hsv(0.63, 0.08, 0.30 + 0.45 * v)
	if h >= 0.93 or h < 0.02:
		return Color.from_hsv(0.77, 0.31, 0.10 + 0.17 * v)
	if h < 0.12:
		# Boards, doors and the tannery's walls: brown wood, lighter than the near black it was (0.155 to 0.175 in the picture, against 0.13 to 0.14; a black front was
		# the first thing seen in the lane). Trim and shutters: the same brown a hand paler, never paler than the plaster they sit in. A head's tone is 0.28 to
		# 0.55 (the darkest a tier III's): the wood is no lighter than the readability tests allow beside a head (see WOOD_BASE).
		if v < 0.66:
			return Color.from_hsv(0.07, WOOD_SAT, WOOD_BASE + WOOD_SLOPE * v)
		return Color.from_hsv(0.05, TRIM_SAT, clampf(TRIM_BASE + TRIM_SLOPE * (v - 0.70), TRIM_BASE - 0.02, TRIM_BASE + 0.03))
	if h < 0.445:
		return Color.from_hsv(0.40, 0.25, 0.20 + 0.30 * v)
	if h < 0.55 or s >= 0.35:
		return Color.from_hsv(0.64, 0.38, 0.16 + 0.26 * v)
	return Color.from_hsv(0.63, minf(0.10 + 0.3 * s, 0.20), 0.30 + 0.45 * v)


# A size x size RGB image of `colours`, row by row.
static func _image(colours: Array[Color], size: int) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	for i in size * size:
		bytes[i * 3] = colours[i].r8
		bytes[i * 3 + 1] = colours[i].g8
		bytes[i * 3 + 2] = colours[i].b8
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)


# `total` split into random lengths that add up to it exactly, each from `low` to `high`, except that a last
# part that cannot be split in two within those may be up to `low` longer than `high`.
static func _split(rng: RandomNumberGenerator, total: int, low: int, high: int) -> PackedInt32Array:
	var parts := PackedInt32Array()
	var left := total
	while left > 0:
		if left <= high or left < 2 * low:
			parts.append(left)
			break
		# Leave at least `low` for the rest.
		var length := rng.randi_range(low, mini(high, left - low))
		parts.append(length)
		left -= length
	return parts


# `total` split into random lengths that add up to it exactly, every one from `low` to `high` (tried again until they do).
static func _split_within(rng: RandomNumberGenerator, total: int, low: int, high: int) -> PackedInt32Array:
	while true:
		var parts := PackedInt32Array()
		var left := total
		while left > 0:
			if left <= high:
				if left >= low:
					parts.append(left)
					left = 0
				else:
					break
			else:
				var length := rng.randi_range(low, high)
				parts.append(length)
				left -= length
		if left == 0:
			return parts
	return PackedInt32Array()
