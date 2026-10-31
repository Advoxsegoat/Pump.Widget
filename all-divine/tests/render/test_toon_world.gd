extends TestCase
## The world's toon shader (render/shaders/toon_world.gdshader) on a real display (xvfb, gl_compatibility).
## Each scene is drawn in its own SubViewport and read back as the sRGB picture: a black background, tonemap
## linear at exposure 1, no glow or fog, one white sun of energy 1 without shadows, and no ambient light
## unless a test adds it.

const TOON_WORLD := preload("res://render/shaders/toon_world.gdshader")
## How far a pixel may be from what it should be, per channel: two 8-bit steps.
const TOLERANCE := 2.0 / 255.0
## The shader's light steps: 0.35 of the light below N.L = 0.15, 0.7 below 0.55, else all of it.
const STEPS := [0.35, 0.7, 1.0]


# With world_uv the texture is laid on the ground by world position, 32 texels to the metre, texel by
# texel (nearest, not filtered): looking straight down at 32 pixels per metre, every pixel is the texel
# under it, and the 4x4 texture repeats every 1/8 m.
func test_world_uv_lays_one_texel_per_thirty_second_of_a_metre() -> void:
	var view := _stage(Vector2i(64, 64), false)
	# Built from bytes: Image.set_pixel truncates, and these must be exact 8-bit colours.
	var bytes := PackedByteArray()
	for y in 4:
		for x in 4:
			bytes.append_array([120 + 40 * x, 110 + 45 * y, 200 - 30 * x + 10 * y])
	var texture := Image.create_from_data(4, 4, false, Image.FORMAT_RGB8, bytes)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8, 8)
	var ground := MeshInstance3D.new()
	ground.mesh = floor_mesh
	ground.material_override = _toon(ImageTexture.create_from_image(texture), true)
	view.add_child(ground)
	var camera := _camera(view, 2.0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	# A quarter texel off the grid, so every pixel centre is three quarters into its texel: a filtered
	# read would blend in the next texel.
	camera.position = Vector3(0.25 / 32.0, 5, 0.25 / 32.0)
	var sun := view.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-90, 0, 0)  # straight down: N.L = 1, the full step
	var img: Image = await _capture(view)

	var off := 0
	var examples := []
	for j in 64:
		for i in 64:
			# Pixel i's centre is at x = 0.25/32 - 1 + (i + 0.5) / 32 m, so x * 32 is in texel i - 32; rows
			# run along +Z the same way.
			var expected := texture.get_pixel(posmod(i - 32, 4), posmod(j - 32, 4))
			var got := img.get_pixel(i, j)
			if not _near(got, expected):
				off += 1
				if examples.size() < 5:
					examples.append("(%d,%d) %s, expected %s" % [i, j, got.to_html(false), expected.to_html(false)])
	assert_eq(off, 0, "pixels that are not the texel under them: %s" % [examples])


# A wall's face is laid by its own plane: a face toward +Z shows the texture by world x and y (y down the
# texture), texel by texel, rather than the ground's x and z, which would smear each column of texels into
# a stripe down the face.
func test_world_uv_lays_a_wall_by_its_own_plane() -> void:
	var view := _stage(Vector2i(64, 64), false)
	var bytes := PackedByteArray()
	for y in 4:
		for x in 4:
			bytes.append_array([120 + 40 * x, 110 + 45 * y, 200 - 30 * x + 10 * y])
	var texture := Image.create_from_data(4, 4, false, Image.FORMAT_RGB8, bytes)
	var wall_mesh := QuadMesh.new()  # faces +Z
	wall_mesh.size = Vector2(8, 8)
	var wall := MeshInstance3D.new()
	wall.mesh = wall_mesh
	wall.material_override = _toon(ImageTexture.create_from_image(texture), true)
	view.add_child(wall)
	var camera := _camera(view, 2.0)
	# A quarter texel off the grid, as in the ground's test; looking along -Z at the wall.
	camera.position = Vector3(0.25 / 32.0, 0.25 / 32.0, 5)
	var sun := view.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3.ZERO  # shining along -Z, straight at the wall: the full step
	var img: Image = await _capture(view)

	var off := 0
	var examples := []
	for j in 64:
		for i in 64:
			# Pixel i's centre is at x = 0.25/32 - 1 + (i + 0.5) / 32 m, in texel i - 32 along x; pixel j's at
			# y = 0.25/32 + 1 - (j + 0.5) / 32 m, so -y x 32 = j - 31.75, in texel j - 32 down the texture.
			var expected := texture.get_pixel(posmod(i - 32, 4), posmod(j - 32, 4))
			var got := img.get_pixel(i, j)
			if not _near(got, expected):
				off += 1
				if examples.size() < 5:
					examples.append("(%d,%d) %s, expected %s" % [i, j, got.to_html(false), expected.to_html(false)])
	assert_eq(off, 0, "pixels that are not the texel under them: %s" % [examples])


# A lamp (an omni light) lights a pool: only what it reaches, in its steps. Past its range, where its
# attenuation is 0, it gives nothing, not the 0.35 step the sun gives what it does not reach (Compatibility
# runs a light's code for every pixel of an object its range touches). The sun is off and there is no ambient
# light, so what the lamp does not light is black.
func test_a_lamp_lights_only_what_it_reaches() -> void:
	var view := _stage(Vector2i(64, 64), false)
	(view.get_node("Sun") as DirectionalLight3D).visible = false
	var white := Image.create(1, 1, false, Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20, 20)
	var ground := MeshInstance3D.new()
	ground.mesh = floor_mesh
	ground.material_override = _toon(ImageTexture.create_from_image(white), false)
	view.add_child(ground)
	var lamp := OmniLight3D.new()
	lamp.omni_range = 3.0
	lamp.position = Vector3(0, 1, 0)
	view.add_child(lamp)
	var camera := _camera(view, 20.0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.position = Vector3(0, 10, 0)
	var img: Image = await _capture(view)

	var lit_under := 0
	var lit_beyond := 0
	var beyond := 0
	for y in 64:
		for x in 64:
			# The pixel's centre on the ground, in metres from the lamp's foot (20 m across 64 pixels).
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(32, 32)) / 64.0 * 20.0
			var c := img.get_pixel(x, y)
			var lit := c.r > 0.0 or c.g > 0.0 or c.b > 0.0
			if p.length() < 1.0 and lit:
				lit_under += 1
			elif p.length() > 3.2:
				beyond += 1
				if lit:
					lit_beyond += 1
	assert_true(lit_under > 20, "the ground under the lamp is lit (%d pixels)" % lit_under)
	assert_true(beyond > 3000, "pixels beyond the lamp's range: %d" % beyond)
	assert_eq(lit_beyond, 0, "pixels lit beyond the lamp's range")


# Lit by one white sun of energy 1, a white sphere shows the light's three steps, each as Forward+ shows
# it (the linear step, encoded to sRGB), each where N.L puts it: below 0.15 the 0.35 step, below 0.55 the
# 0.7 step, else the full light. The camera looks straight at the sphere, so the normal under each pixel is
# known; pixels within 0.03 of a threshold are skipped (the mesh's normals are interpolated).
func test_light_steps_at_0_15_and_0_55() -> void:
	var view := _stage(Vector2i(96, 96), false)
	_white_sphere(view)
	var img: Image = await _capture(view)
	var to_light := (view.get_node("Sun") as DirectionalLight3D).global_basis.z
	var seen := {}
	var checked := 0
	var off := 0
	var examples := []
	for y in img.get_height():
		for x in img.get_width():
			# The pixel's centre in metres on the camera plane (2.2 m across 96 pixels, y up).
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(48, 48)) / 96.0 * 2.2
			p.y = -p.y
			if p.length_squared() > 0.9:
				continue
			var normal := Vector3(p.x, p.y, sqrt(1.0 - p.length_squared()))
			var i := clampf(normal.dot(to_light), 0.0, 1.0)
			if absf(i - 0.15) < 0.03 or absf(i - 0.55) < 0.03:
				continue
			var step := 0 if i < 0.15 else (1 if i < 0.55 else 2)
			var k: float = STEPS[step]
			var expected := Color(k, k, k).linear_to_srgb()
			var got := img.get_pixel(x, y)
			checked += 1
			if _near(got, expected):
				seen[step] = true
			else:
				off += 1
				if examples.size() < 5:
					examples.append("(%d,%d) N.L %.2f: %s, expected %s" % [x, y, i, got.to_html(false), expected.to_html(false)])
	assert_true(checked > 4000, "pixels checked: %d" % checked)
	assert_eq(off, 0, "pixels not at the step N.L gives them: %s" % [examples])
	assert_eq(seen.size(), 3, "steps that show: %s" % [seen.keys()])


# The world keeps its ambient light (only characters drop it): with a grey ambient, the sphere's darkest
# step is brighter than without.
func test_ambient_light_is_kept() -> void:
	var dark := _stage(Vector2i(96, 96), false)
	_white_sphere(dark)
	var without: Image = await _capture(dark)
	var lit := _stage(Vector2i(96, 96), true)
	_white_sphere(lit)
	var with_ambient: Image = await _capture(lit)
	var a := _darkest(without)
	var b := _darkest(with_ambient)
	assert_true(b > a + 0.05, "the darkest step goes from %.3f to %.3f with ambient light" % [a, b])


# --- helpers ---

# A SubViewport of `size` with its own world: black, tonemap linear at exposure 1, no glow or fog, ambient
# light off (or a grey of 0.5 if `ambient`), and one white DirectionalLight3D "Sun" of energy 1, no shadows.
func _stage(size: Vector2i, ambient: bool) -> SubViewport:
	var view := SubViewport.new()
	view.size = size
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if ambient else Environment.AMBIENT_SOURCE_DISABLED
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.ambient_light_energy = 1.0
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
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-40, -35, 0)
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


func _toon(texture: Texture2D, world_uv: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TOON_WORLD
	material.set_shader_parameter(&"albedo_tex", texture)
	material.set_shader_parameter(&"world_uv", world_uv)
	return material


# A white sphere of radius 1 filling a camera 2.2 m high.
func _white_sphere(view: SubViewport) -> void:
	var white := Image.create(1, 1, false, Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var ball := MeshInstance3D.new()
	ball.mesh = sphere
	ball.material_override = _toon(ImageTexture.create_from_image(white), false)
	view.add_child(ball)
	var camera := _camera(view, 2.2)
	camera.position = Vector3(0, 0, 5)


func _capture(view: SubViewport) -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= TOLERANCE and absf(a.g - b.g) <= TOLERANCE and absf(a.b - b.b) <= TOLERANCE


# The darkest drawn (non-black) pixel's red channel.
func _darkest(img: Image) -> float:
	var darkest := 1.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.0 or c.g > 0.0 or c.b > 0.0:
				darkest = minf(darkest, c.r)
	return darkest
