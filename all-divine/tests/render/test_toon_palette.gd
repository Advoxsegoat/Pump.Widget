extends TestCase
## The toon shader (render/shaders/toon_character.gdshader) on a real display (xvfb, gl_compatibility):
## under one white light of energy 1, with shadows, every pixel it draws is one of the four tones of
## the palette slot it was given; under other lights it follows the same maths as in Forward+. Each scene
## is drawn in its own SubViewport and read back as the sRGB picture: a black background, no ambient
## light, tonemap linear, exposure 1, and no glow, fog or other post effect.

const PALETTE := "res://data/palettes/abarax.tres"
const RIG := "res://actors/abarax/abarax_rig.tscn"
## How far a pixel may be from a tone, per channel: two 8-bit steps.
const TOLERANCE := 2.0 / 255.0
## Where the sun shines from: above, to the left of and in front of what it lights.
const SUN_ROTATION := Vector3(-40.0, -35.0, 0.0)
## Abarax's slots with a part big enough to show from the game's angle: skin, hair, main, sec, pants,
## boots, rose.
const ABARAX_SHOWN := [0, 1, 3, 4, 5, 6, 7]


func test_sphere_pixels_are_palette_tones() -> void:
	var palette := load(PALETTE) as Palette
	var view := _stage(Vector2i(128, 128))
	_sphere_scene(view, palette)
	var img: Image = await _capture(view)

	var found := _match_pixels(img, _tones(palette, [3]))
	assert_true(found["drawn"] > img.get_width() * img.get_height() / 2, "the sphere fills the view (%d pixels)" % found["drawn"])
	assert_eq(found["off"], 0, "pixels that are not a tone of slot 3: %s" % [found["examples"]])
	assert_true((found["seen"] as Dictionary).size() >= 3, "slot 3's tones that show: %s" % [(found["seen"] as Dictionary).keys()])


# Other lights follow the Forward+ maths, where a light adds its colour times the step from the deep tone
# up to the tone it picks. Under a dimmer, warmer sun every pixel is, worked in linear,
# deep + max(0, (tone - deep) x light colour x energy) for one of slot 3's tones.
func test_a_dim_warm_light_follows_the_forward_plus_maths() -> void:
	var palette := load(PALETTE) as Palette
	var view := _stage(Vector2i(128, 128))
	var sun := view.get_node("Sun") as DirectionalLight3D
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 0.75
	_sphere_scene(view, palette)
	var img: Image = await _capture(view)

	var light := sun.light_color.srgb_to_linear() * sun.light_energy
	var deep := palette.tone(3, Palette.DEEP).srgb_to_linear()
	var lit := PackedColorArray()
	for t in Palette.TONES:
		var tone := palette.tone(3, t).srgb_to_linear()
		lit.append(Color(
			deep.r + maxf(0.0, (tone.r - deep.r) * light.r),
			deep.g + maxf(0.0, (tone.g - deep.g) * light.g),
			deep.b + maxf(0.0, (tone.b - deep.b) * light.b)).linear_to_srgb())
	var found := _match_pixels(img, lit)
	assert_true(found["drawn"] > img.get_width() * img.get_height() / 2, "the sphere fills the view (%d pixels)" % found["drawn"])
	assert_eq(found["off"], 0, "pixels that are not slot 3 under this light: %s" % [found["examples"]])
	assert_true((found["seen"] as Dictionary).size() >= 3, "lit tones that show: %s" % [(found["seen"] as Dictionary).keys()])


# A lamp (an omni light) near enough that its range touches the body, but too weak where it reaches to lift any
# pixel above the deep tone, changes nothing: every pixel is still one of slot 3's tones under the sun. (In
# Compatibility every light in reach of an object runs for all its pixels, in the pass that also draws the
# ambient and the other lamps; a lamp that gave the deep tone there would add it under the sun's own pass.)
func test_a_lamp_that_lifts_nothing_changes_nothing() -> void:
	var palette := load(PALETTE) as Palette
	var view := _stage(Vector2i(128, 128))
	_sphere_scene(view, palette)
	var lamp := OmniLight3D.new()
	lamp.omni_range = 2.6
	lamp.position = Vector3(0, 0, -3)  # behind the sphere, its range reaching 0.4 m into it
	view.add_child(lamp)
	var img: Image = await _capture(view)

	var found := _match_pixels(img, _tones(palette, [3]))
	assert_true(found["drawn"] > img.get_width() * img.get_height() / 2, "the sphere fills the view (%d pixels)" % found["drawn"])
	assert_eq(found["off"], 0, "pixels that are not a tone of slot 3: %s" % [found["examples"]])


func test_abarax_pixels_are_his_palette() -> void:
	var palette := load(PALETTE) as Palette
	var view := _stage(Vector2i(200, 200))
	var camera := _camera(view, 2.0)
	# The game's view (CameraRig): 40 degrees down, from in front of him.
	camera.rotation_degrees = Vector3(CameraRig.PITCH_DEG, CameraRig.YAW_DEG, 0)
	camera.position = Vector3(0, 0.9, 0) + camera.basis.z * 10.0
	var rig := (load(RIG) as PackedScene).instantiate() as Rig
	view.add_child(rig)
	rig.apply_palette(palette)
	rig.set_locomotion(0.0, false)
	rig.tick(0.0)  # Idle, posed; the skin follows at the end of the frame.
	var img: Image = await _capture(view)

	var slots := range(9)
	var tones := _tones(palette, slots)
	var found := _match_pixels(img, tones)
	assert_true(found["drawn"] > 3000, "Abarax is drawn (%d pixels)" % found["drawn"])
	assert_eq(found["off"], 0, "pixels that are not a tone of slots 0-8: %s" % [found["examples"]])
	var shown := {}
	for index: int in found["seen"]:
		shown[slots[index / Palette.TONES]] = true
	for slot in ABARAX_SHOWN:
		assert_true(shown.has(slot), "slot %d (%s) shows" % [slot, palette.slot_names[slot]])


# A SubViewport of `size` with its own world, under this test: black, no ambient light, linear tonemap at
# exposure 1, no post effects, and one white DirectionalLight3D "Sun" of energy 1 that casts shadows.
func _stage(size: Vector2i) -> SubViewport:
	var view := SubViewport.new()
	view.size = size
	view.own_world_3d = true
	view.transparent_bg = false
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.fog_enabled = false
	var environment := WorldEnvironment.new()
	environment.environment = env
	view.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color.WHITE
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 20.0
	sun.rotation_degrees = SUN_ROTATION
	view.add_child(sun)
	track(view)
	return view


func _camera(view: SubViewport, ortho_size: float) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ortho_size
	camera.near = 0.1
	camera.far = 50.0
	view.add_child(camera)
	camera.make_current()
	return camera


# A sphere in slot 3, filling a camera 2.2 m high, and a box out of the camera's view between the sun and
# part of the sphere's lit side, so some of the lit side is in shadow.
func _sphere_scene(view: SubViewport, palette: Palette) -> void:
	var camera := _camera(view, 2.2)
	camera.position = Vector3(0, 0, 5)
	var sphere := MeshInstance3D.new()
	sphere.mesh = _sphere_in_slot(3)
	sphere.material_override = Rig.toon_material(palette)
	view.add_child(sphere)
	var sun := view.get_node("Sun") as DirectionalLight3D
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	blocker.mesh = box
	view.add_child(blocker)
	blocker.global_position = sun.global_basis.z * 3.0 + sun.global_basis.x * 0.7


# A sphere of radius 1 whose every corner is in palette slot `slot` (UV2.x = (slot + 0.5) / 16).
func _sphere_in_slot(slot: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var arrays := sphere.get_mesh_arrays()
	var uv2 := PackedVector2Array()
	uv2.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	uv2.fill(Vector2((slot + 0.5) / Palette.SLOTS, 0.5))
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# The picture, once the world has drawn a few times (shadows and skinning are in place by then).
func _capture(view: SubViewport) -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


# Every tone of the given slots, slot by slot: index slot_index * 4 + tone.
func _tones(palette: Palette, slots: Array) -> PackedColorArray:
	var tones := PackedColorArray()
	for slot: int in slots:
		for t in Palette.TONES:
			tones.append(palette.tone(slot, t))
	return tones


# Looks at every pixel that is not the black background: {drawn: how many, off: how many are not within
# TOLERANCE of any of `tones`, examples: the first few of those with the nearest tone, seen: the indices
# into `tones` of those that matched}.
func _match_pixels(img: Image, tones: PackedColorArray) -> Dictionary:
	var drawn := 0
	var off := 0
	var examples := []
	var seen := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
				continue
			drawn += 1
			var best := -1
			var best_d := INF
			for i in tones.size():
				var d := maxf(maxf(absf(c.r - tones[i].r), absf(c.g - tones[i].g)), absf(c.b - tones[i].b))
				if d < best_d:
					best_d = d
					best = i
			if best_d <= TOLERANCE:
				seen[best] = true
			else:
				off += 1
				if examples.size() < 5:
					examples.append("(%d,%d) %s is %d/255 from tone %d %s" % [x, y, c.to_html(false), roundi(best_d * 255), best, tones[best].to_html(false)])
	return {"drawn": drawn, "off": off, "examples": examples, "seen": seen}
