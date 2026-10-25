extends TestCase
## Palettes (render/palette.gd): the four tones a base colour ramps to, dyes, the 4x16 texture the toon
## shader reads, Abarax's palette (data/palettes/abarax.tres), and the rig and actor wearing it. Headless;
## tests/render/test_toon_palette.gd checks the pixels the shader draws.

const ABARAX := "res://data/palettes/abarax.tres"
const ABARAX_DEF := "res://data/actors/abarax.tres"
const RIG := "res://actors/abarax/abarax_rig.tscn"
const TOON := "res://render/shaders/toon_character.gdshader"
## Slots 0-8 of Abarax's palette: name and base colour (from Between the Rooms, plus Tactics' rose).
const ABARAX_SLOTS := [
	["skin", "#c98a5a"], ["hair", "#4a2e1e"], ["eyes", "#5a2e14"], ["main", "#efe6d6"], ["sec", "#3a4a7a"],
	["pants", "#3a3a4a"], ["boots", "#5a3a2a"], ["rose", "#e8607e"], ["gold", "#e8c170"],
]
## Tones other than the base are rounded to whole 8-bit steps.
const ROUNDING := 0.5 / 255.0 + 1e-6


func test_ramp_keeps_base_and_darkens_shades() -> void:
	var r := Palette.ramp_from_base(Color("#c98a5a"))
	assert_eq(r[1], Color("#c98a5a"))
	assert_near(r[2].v, Color("#c98a5a").v * 0.72, 0.005); assert_near(r[3].v, Color("#c98a5a").v * 0.48, 0.005)
	assert_true(_hue_dist(r[2].h, 240.0 / 360) < _hue_dist(Color("#c98a5a").h, 240.0 / 360))


# Each tone against the rules worked in HSV: highlight hue toward 60 by <= 8 degrees, s x 0.85,
# v = min(1, v x 1.18); shade toward 240 by <= 12, s = min(1, s x 1.1), v x 0.72; deep toward 240 by
# <= 20, s = min(1, s x 1.2), v x 0.48; along the shorter way round, which for rose crosses 0.
func test_ramp_follows_the_hsv_rules() -> void:
	var skin := Color("#c98a5a")  # hue 25.9: up to the highlight, down (the short way) to 240
	_assert_ramp(skin, [skin.h * 360 + 8, skin.h * 360 - 12, skin.h * 360 - 20])
	var rose := Color("#e8607e")  # hue 346.4: the highlight goes up through 360 to 354.4
	_assert_ramp(rose, [rose.h * 360 + 8 - 360, rose.h * 360 - 12, rose.h * 360 - 20])
	# 4 degrees short of 60, and 6 short of 240: the shift stops there, it never overshoots.
	var near := Color.from_hsv(56.0 / 360, 0.5, 0.6)
	var near_blue := Color.from_hsv(234.0 / 360, 0.5, 0.6)
	_assert_ramp(near, [60.0, 44.0, 36.0])
	_assert_ramp(near_blue, [226.0, 240.0, 240.0])
	var bright := Color.from_hsv(0.5, 0.9, 0.95)  # v x 1.18 and s x 1.2 clamp at 1
	var r := Palette.ramp_from_base(bright)
	assert_near(r[0].v, 1.0, ROUNDING, "the highlight's v stops at 1")
	assert_near(r[3].s, 1.0, 0.01, "the deep tone's s stops at 1")


func test_tones_are_whole_8_bit_steps() -> void:
	var r := Palette.ramp_from_base(Color(0.3, 0.5, 0.7))
	for t in [0, 2, 3]:
		for c in [r[t].r, r[t].g, r[t].b]:
			assert_near(c * 255.0, roundf(c * 255.0), 1e-4, "tone %d channel %s" % [t, c])
		assert_eq(r[t].a, 1.0)
	assert_eq(r[1], Color(0.3, 0.5, 0.7), "the base is kept as given")


func test_texture_layout() -> void:
	var p := load(ABARAX) as Palette
	var img := p.to_texture().get_image()
	assert_eq(img.get_size(), Vector2i(4, 16))
	assert_eq(img.get_format(), Image.FORMAT_RGBA8)
	assert_eq(img.get_pixel(1, 3), p.tone(3, 1))
	for slot in Palette.SLOTS:
		for t in Palette.TONES:
			assert_eq(img.get_pixel(t, slot), p.tone(slot, t), "x is the tone (%d), y the slot (%d)" % [t, slot])


func test_texture_rounds_to_the_nearest_step() -> void:
	var p := Palette.new()
	p.tones.resize(Palette.SLOTS * Palette.TONES)
	p.tones.fill(Color(200.6 / 255.0, 0.4 / 255.0, 1.0, 1.0))
	assert_eq(p.to_texture().get_image().get_pixel(0, 0), Color8(201, 0, 255))


func test_dye_copies() -> void:
	var p := load(ABARAX) as Palette
	var before := p.tones.duplicate()
	var dyed := p.with_dye(7, Color.RED)
	assert_ne(dyed, p, "a new palette")
	var red := Palette.ramp_from_base(Color.RED)
	for t in Palette.TONES:
		assert_eq(dyed.tone(7, t), red[t], "slot 7 tone %d is the red ramp" % t)
	for slot in Palette.SLOTS:
		if slot != 7:
			for t in Palette.TONES:
				assert_eq(dyed.tone(slot, t), p.tone(slot, t), "slot %d is untouched" % slot)
	assert_eq(p.tones, before, "the original is left alone")
	assert_eq(dyed.id, p.id)
	assert_eq(dyed.slot_names, p.slot_names)


func test_abarax_palette_slots() -> void:
	var p := load(ABARAX) as Palette
	assert_eq(p.id, &"abarax")
	assert_eq(p.slot_names.size(), Palette.SLOTS)
	assert_eq(p.tones.size(), Palette.SLOTS * Palette.TONES)
	for slot in ABARAX_SLOTS.size():
		var base := Color(ABARAX_SLOTS[slot][1])
		assert_eq(p.slot_names[slot], ABARAX_SLOTS[slot][0])
		assert_eq(p.tone(slot, Palette.BASE), base, "slot %d's base is %s" % [slot, ABARAX_SLOTS[slot][1]])
		var ramp := Palette.ramp_from_base(base)
		for t in Palette.TONES:
			assert_eq(p.tone(slot, t), ramp[t], "slot %d tone %d is its base's ramp" % [slot, t])
	for slot in range(ABARAX_SLOTS.size(), Palette.SLOTS):
		assert_eq(p.slot_names[slot], "", "slot %d is unused" % slot)
		for t in Palette.TONES:
			assert_eq(p.tone(slot, t), Color("#ff00ff"), "unused slot %d is magenta in tone %d" % [slot, t])


# The shader adds a lit tone's light on top of the deep tone, so a tone shows exactly only where none of
# its channels is darker than the deep tone's.
func test_abarax_tones_never_dip_below_deep() -> void:
	var p := load(ABARAX) as Palette
	for slot in ABARAX_SLOTS.size():
		var deep := p.tone(slot, Palette.DEEP)
		for t in Palette.TONES:
			var c := p.tone(slot, t)
			assert_true(c.r >= deep.r and c.g >= deep.g and c.b >= deep.b, "slot %d tone %d %s against deep %s" % [slot, t, c, deep])


func test_from_bases_fills_unused_slots_with_magenta() -> void:
	var p := Palette.from_bases(&"test", PackedStringArray(["a", "b"]), PackedColorArray([Color("#204060"), Color("#806040")]))
	assert_eq(p.id, &"test")
	assert_eq(p.slot_names, PackedStringArray(["a", "b", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]))
	assert_eq(p.tone(1, Palette.BASE), Color("#806040"))
	assert_eq(p.tone(0, Palette.DEEP), Palette.ramp_from_base(Color("#204060"))[3])
	assert_eq(p.tone(15, Palette.HIGHLIGHT), Color.MAGENTA)


# The shader has a branch for Compatibility and one for Forward+ and Mobile. A headless run still compiles
# shaders (the dummy renderer does, as Forward+), so this checks the Forward+ branch, which the render tests,
# drawing in Compatibility, cannot.
func test_the_toon_shader_compiles_for_this_renderer() -> void:
	var shader := Shader.new()
	shader.code = (load(TOON) as Shader).code
	var names := shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
	assert_eq(names, ["palette", "ramp"], "compiled for %s" % RenderingServer.get_current_rendering_method())


func test_rig_wears_one_shared_toon_material() -> void:
	var rig := track(load(RIG).instantiate()) as Rig
	var p := load(ABARAX) as Palette
	rig.apply_palette(p)
	assert_eq(rig.palette, p)
	var meshes := rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 9)
	var shared: Material = (meshes[0] as MeshInstance3D).material_override
	assert_true(shared is ShaderMaterial, "a ShaderMaterial")
	for mi: MeshInstance3D in meshes:
		assert_true(mi.material_override == shared, "%s shares the one material" % mi.name)
	if shared is ShaderMaterial:
		assert_eq((shared as ShaderMaterial).shader.resource_path, TOON)
		var tex := (shared as ShaderMaterial).get_shader_parameter(&"palette") as Texture2D
		assert_ne(tex, null, "the palette texture is set")
		if tex != null:
			assert_eq(tex.get_image().get_data(), p.to_texture().get_image().get_data())
	# Dyeing re-dresses the same rig in the new colours.
	rig.apply_palette(p.with_dye(7, Color.RED))
	var after := (meshes[0] as MeshInstance3D).material_override as ShaderMaterial
	var dyed := after.get_shader_parameter(&"palette") as Texture2D
	assert_eq(dyed.get_image().get_pixel(Palette.BASE, 7), Color.RED)
	for mi: MeshInstance3D in meshes:
		assert_true(mi.material_override == after, "%s still shares one material" % mi.name)


func test_actor_wears_its_def_palette() -> void:
	var def := load(ABARAX_DEF) as ActorDef
	assert_eq(def.palette, load(ABARAX) as Palette)
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, def, Brain.new())
	assert_eq(actor.rig.palette, def.palette)
	for mi: MeshInstance3D in actor.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		assert_true(mi.material_override is ShaderMaterial, "%s is drawn by the toon shader" % mi.name)


# The tones of the ramp of `base`, against the rules with these hues (degrees) for highlight, shade, deep.
func _assert_ramp(base: Color, hues: Array) -> void:
	var r := Palette.ramp_from_base(base)
	var want := [
		Color.from_hsv(fposmod(hues[0], 360.0) / 360, base.s * 0.85, minf(1.0, base.v * 1.18)),
		base,
		Color.from_hsv(fposmod(hues[1], 360.0) / 360, minf(1.0, base.s * 1.1), base.v * 0.72),
		Color.from_hsv(fposmod(hues[2], 360.0) / 360, minf(1.0, base.s * 1.2), base.v * 0.48),
	]
	assert_eq(r.size(), 4)
	for t in 4:
		var d := maxf(maxf(absf(r[t].r - want[t].r), absf(r[t].g - want[t].g)), absf(r[t].b - want[t].b))
		assert_true(d <= ROUNDING, "base %s tone %d: %s, want %s" % [base.to_html(false), t, r[t], want[t]])


# How far apart two hues are, in turns, the shorter way round.
func _hue_dist(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)
