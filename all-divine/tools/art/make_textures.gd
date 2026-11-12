extends SceneTree
## Makes the textures we draw ourselves:
##   tools/godot.sh -s res://tools/art/make_textures.gd
## writes assets/env/textures/flagstone.png, slate.png, cobble.png, tan_earth.png and snow.png, the same bytes every time. Run `tools/godot.sh --import`
## afterwards. Exits 0, or 1 if a file could not be written.

const OUT_DIR := "res://assets/env/textures"
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
## Bilibara's street: a calm mosaic of cold blue-grey setts, told by tone and not by bright lines. A sett is 5 to 9 texels
## wide and 5 to 7 deep, its joint included; the rows wobble (a row's lower edge steps a texel from sett to sett) and are laid
## in an irregular bond, so no straight joint crosses the tile (the camera draws a texel row 0.64 of a pixel tall, and a
## straight bright joint would be dropped and found again as it moves). The joints are a little darker than the darkest
## stone, and a few setts carry frost: the snow that lies on the street is the `snow` ground. (The colours are first
## values: the snow-noon light may move them.)
const COBBLES: Array[Color] = [Color8(80, 84, 100), Color8(86, 90, 106), Color8(92, 96, 112), Color8(98, 102, 118)]
const COBBLE_JOINT := Color8(66, 70, 86)
const FROST := Color8(120, 130, 148)
const COBBLE_SEED := 13
const COBBLE_DEPTH_MIN := 5
const COBBLE_DEPTH_MAX := 7
const COBBLE_WIDTH_MIN := 5
const COBBLE_WIDTH_MAX := 9
## The share of setts that carry frost, and of such a sett's texels that are frost (about 4% of the tile in all).
const FROSTED_SETTS := 0.35
const FROST_SHARE := 0.12
## The Tanneries' earth: warm browns in blotches 4 to 8 texels across, with a few texels of lime.
const EARTHS: Array[Color] = [Color8(86, 72, 60), Color8(94, 80, 66), Color8(78, 66, 56)]
const LIME := Color8(124, 114, 100)
const EARTH_SEED := 17
const BLOTCH_MIN := 4
const BLOTCH_MAX := 8
## The share of the earth's texels that are lime.
const LIME_SHARE := 0.04
## Snow: a cold blue-grey light ground, not white (a man in white must stand out on it), with a tenth of its texels in a
## bluer shadow tone, in soft clumps of two to five texels.
const SNOWS: Array[Color] = [Color8(150, 162, 172), Color8(130, 144, 160)]
const SNOW_SEED := 19
const SNOW_SHADOW := 0.10
const CLUMP_MIN := 2
const CLUMP_MAX := 5


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for made: Array in [["flagstone.png", flagstone()], ["slate.png", slate()], ["cobble.png", cobble()],
			["tan_earth.png", tan_earth()], ["snow.png", snow()]]:
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
	var rng := RandomNumberGenerator.new()
	rng.seed = FLAGSTONE_SEED
	var size := FLAGSTONE_SIZE
	# Each texel's colour: an index into STONES, or -1 for mortar.
	var grey := PackedInt32Array()
	grey.resize(size * size)
	grey.fill(-1)
	var y0 := 0
	for height in _split(rng, size, ROW_MIN, ROW_MAX):
		# Each row's joints start somewhere else, so no joint lines up with the row above's.
		var x0 := rng.randi_range(0, size - 1)
		var last := -1
		for length in _split(rng, size, STONE_MIN, STONE_MAX):
			var g := rng.randi_range(0, STONES.size() - 1)
			if g == last:
				g = (g + 1 + rng.randi_range(0, STONES.size() - 2)) % STONES.size()
			last = g
			# The stone, less its mortar: its last column and its row's last line.
			for dy in height - 1:
				for dx in length - 1:
					var speckled := g
					if rng.randf() < SPECKLE:
						speckled = clampi(g + (1 if rng.randf() < 0.5 else -1), 0, STONES.size() - 1)
					grey[(y0 + dy) * size + (x0 + dx) % size] = speckled
			x0 += length
		y0 += height
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	for i in size * size:
		var c := MORTAR if grey[i] < 0 else STONES[grey[i]]
		bytes[i * 3] = c.r8
		bytes[i * 3 + 1] = c.g8
		bytes[i * 3 + 2] = c.b8
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)


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
	# Each row's setts: {x, length, tone, step, frosted}, and the joint's y under the row at every column.
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
			setts.append({x = x, length = length, tone = tone, step = step, frosted = rng.randf() < FROSTED_SETTS})
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
					elif sett.frosted and rng.randf() < FROST_SHARE:
						c = FROST
					colours[posmod(y, size) * size + column] = c
	return _image(colours, size)


## The Tanneries' ground: a 2 m tile of earth in blotches 4 to 8 texels across, laid as a lattice (each band of blotches
## cut at its own places, so no seam runs the tile's length), one of the three EARTHS each, with LIME_SHARE of the texels
## lime. Every band and every column is cut so that the tile's edge falls inside a blotch: it tiles seamlessly. The same
## seeded random numbers (EARTH_SEED) make the same tile.
static func tan_earth() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = EARTH_SEED
	var size := FLAGSTONE_SIZE
	var colours: Array[Color] = []
	colours.resize(size * size)
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
			for dy in height:
				for dx in length:
					colours[posmod(y0 + dy, size) * size + posmod(x0 + dx, size)] = EARTHS[e]
			x0 += length
		above = earths
		y0 += height
	for i in size * size:
		if rng.randf() < LIME_SHARE:
			colours[i] = LIME
	return _image(colours, size)


## Snow: a 2 m tile of a cold light blue-grey with SNOW_SHADOW of its texels in a bluer tone, in clumps of CLUMP_MIN to
## CLUMP_MAX texels that do not touch one another (not even at a corner), so each is seen as one soft patch. It wraps. The
## same seeded random numbers (SNOW_SEED) make the same tile.
static func snow() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = SNOW_SEED
	var size := FLAGSTONE_SIZE
	var shadowed := PackedByteArray()
	shadowed.resize(size * size)
	var taken := PackedByteArray()  # a clump's texels and the ring round them
	taken.resize(size * size)
	var left := roundi(size * size * SNOW_SHADOW)
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while left > 0:
		var at := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		var cells: Array[Vector2i] = [at]
		for i in rng.randi_range(CLUMP_MIN, CLUMP_MAX) - 1:
			var next: Vector2i = cells[rng.randi_range(0, cells.size() - 1)] + steps[rng.randi_range(0, 3)]
			next = Vector2i(posmod(next.x, size), posmod(next.y, size))
			if not cells.has(next):
				cells.append(next)
		var free := cells.size() >= CLUMP_MIN
		for cell in cells:
			free = free and taken[cell.y * size + cell.x] == 0
		if not free:
			continue
		for cell in cells:
			shadowed[cell.y * size + cell.x] = 1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					taken[posmod(cell.y + dy, size) * size + posmod(cell.x + dx, size)] = 1
		left -= cells.size()
	var colours: Array[Color] = []
	for i in size * size:
		colours.append(SNOWS[1] if shadowed[i] == 1 else SNOWS[0])
	return _image(colours, size)


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
