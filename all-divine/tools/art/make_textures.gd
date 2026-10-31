extends SceneTree
## Makes the textures we draw ourselves:
##   tools/godot.sh -s res://tools/art/make_textures.gd
## writes assets/env/textures/flagstone.png, the same bytes every time. Run `tools/godot.sh --import`
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


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR.path_join("flagstone.png")
	var error := flagstone().save_png(ProjectSettings.globalize_path(path))
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
