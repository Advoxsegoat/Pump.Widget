class_name Palette
extends Resource
## A character's colours: 16 slots, each with four tones (highlight, base, shade, deep). The model says
## which slot each face is in (UV2.x = (slot + 0.5) / 16), and the toon shader
## (render/shaders/toon_character.gdshader) draws every pixel in one of that slot's tones, picked by how
## much light falls there; under one white light of energy 1, exactly that tone. Abarax's is
## data/palettes/abarax.tres.
##
## Tones are authored as sRGB colours. A slot's tones are usually its base colour's ramp
## (ramp_from_base); a dye swaps one slot's ramp for another's (with_dye). Unused slots are magenta in
## every tone, so a face in the wrong slot shows at once.

const SLOTS := 16
const TONES := 4
## Tone indices, brightest first.
const HIGHLIGHT := 0
const BASE := 1
const SHADE := 2
const DEEP := 3
## The colour of every tone of an unused slot.
const UNUSED := Color(1, 0, 1)

@export var id: StringName
## What each of the 16 slots is for ("skin", "main", ...); "" for an unused slot.
@export var slot_names := PackedStringArray()
## 64 colours: slot `s`'s tone `t` is at s * 4 + t.
@export var tones := PackedColorArray()


## Slot `slot`'s tone `t` (HIGHLIGHT, BASE, SHADE or DEEP).
func tone(slot: int, t: int) -> Color:
	return tones[slot * TONES + t]


## The four tones of a slot whose base colour is `base`, worked in HSV ("toward" a hue is along the
## shorter way round the hue circle, by at most that many degrees):
##   highlight  hue toward 60 by <= 8, s x 0.85, v = min(1, v x 1.18)
##   base       `base` itself
##   shade      hue toward 240 by <= 12, s = min(1, s x 1.1), v x 0.72
##   deep       hue toward 240 by <= 20, s = min(1, s x 1.2), v x 0.48
## All but the base are rounded to whole 8-bit steps, so they are exactly what the palette texture holds.
static func ramp_from_base(base: Color) -> PackedColorArray:
	var hue := base.h * 360.0
	return PackedColorArray([
		_tone(_hue_toward(hue, 60.0, 8.0), base.s * 0.85, minf(1.0, base.v * 1.18)),
		base,
		_tone(_hue_toward(hue, 240.0, 12.0), minf(1.0, base.s * 1.1), base.v * 0.72),
		_tone(_hue_toward(hue, 240.0, 20.0), minf(1.0, base.s * 1.2), base.v * 0.48),
	])


## A palette whose slot i is named `names[i]` and ramps from `bases[i]` (see ramp_from_base); the slots
## past the end of `bases` are unused (no name, magenta).
static func from_bases(palette_id: StringName, names: PackedStringArray, bases: PackedColorArray) -> Palette:
	var p := Palette.new()
	p.id = palette_id
	p.slot_names.resize(SLOTS)
	p.tones.resize(SLOTS * TONES)
	p.tones.fill(UNUSED)
	for slot in mini(bases.size(), SLOTS):
		p.slot_names[slot] = names[slot] if slot < names.size() else ""
		p._set_ramp(slot, ramp_from_base(bases[slot]))
	return p


## A copy of this palette with slot `slot` dyed: its tones become the ramp of `base`.
func with_dye(slot: int, base: Color) -> Palette:
	var dyed := duplicate() as Palette
	# duplicate() hands the copy these very arrays (packed arrays are shared, not copied), so it gets its own.
	dyed.slot_names = slot_names.duplicate()
	dyed.tones = tones.duplicate()
	dyed._set_ramp(slot, ramp_from_base(base))
	return dyed


## The palette as the toon shader reads it: a 4x16 RGBA8 image, x the tone and y the slot.
func to_texture() -> ImageTexture:
	var data := PackedByteArray()
	data.resize(SLOTS * TONES * 4)
	for i in mini(tones.size(), SLOTS * TONES):
		var c := tones[i]
		data[i * 4] = roundi(clampf(c.r, 0.0, 1.0) * 255.0)
		data[i * 4 + 1] = roundi(clampf(c.g, 0.0, 1.0) * 255.0)
		data[i * 4 + 2] = roundi(clampf(c.b, 0.0, 1.0) * 255.0)
		data[i * 4 + 3] = roundi(clampf(c.a, 0.0, 1.0) * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(TONES, SLOTS, false, Image.FORMAT_RGBA8, data))


func _set_ramp(slot: int, ramp: PackedColorArray) -> void:
	for t in TONES:
		tones[slot * TONES + t] = ramp[t]


# `hue` (degrees) moved toward `goal` the shorter way round, by at most `most` degrees.
static func _hue_toward(hue: float, goal: float, most: float) -> float:
	return fposmod(hue + clampf(wrapf(goal - hue, -180.0, 180.0), -most, most), 360.0)


# The opaque colour of hue `hue` (degrees), saturation `s` and value `v`, rounded to whole 8-bit steps.
static func _tone(hue: float, s: float, v: float) -> Color:
	var c := Color.from_hsv(hue / 360.0, s, v)
	return Color8(roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0))
