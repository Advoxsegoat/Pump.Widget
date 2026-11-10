extends TestCase
## The training yard's kerbstones (assets/env/textures/slate.png), made by tools/art/make_textures.gd: a 2 m tile at 32
## texels per metre of two kerbstones a metre long, in two dark slates with a darker joint between them, the same every
## time it is made. It is a stone that is not the floor's: dark and blue-grey where the flagstones are pale and warm.

const MAKE_TEXTURES := preload("res://tools/art/make_textures.gd")
const SLATE := "res://assets/env/textures/slate.png"
const MATERIAL := "res://world/materials/slate.tres"


func test_slate_is_a_2_m_tile_of_two_kerbstones_with_a_joint_after_each() -> void:
	var img := MAKE_TEXTURES.slate()
	assert_eq(img.get_size(), Vector2i(64, 64), "64 x 64 texels: 2 m at 32 texels per metre")
	var joint := MAKE_TEXTURES.SLATE_JOINT
	for y in 64:
		for x in 64:
			var is_joint := x % 32 == 31
			assert_eq(img.get_pixel(x, y) == joint, is_joint, "(%d, %d): a joint one texel wide ends each metre, and only there" % [x, y])
			if not is_joint:
				assert_true(MAKE_TEXTURES.SLATES.has(img.get_pixel(x, y)), "(%d, %d) is a slate" % [x, y])
	# Each stone is mostly one slate, speckled with the other; the two stones are not the same slate.
	var first := img.get_pixel(8, 8)
	var counts := [0, 0]
	for y in 64:
		for x in 31:
			counts[0] += int(img.get_pixel(x, y) == MAKE_TEXTURES.SLATES[0])
			counts[1] += int(img.get_pixel(x + 32, y) == MAKE_TEXTURES.SLATES[0])
	assert_true(counts[0] > 31 * 64 * 0.8 and counts[1] < 31 * 64 * 0.2, "one stone of each slate (%s of %d texels are the first)" % [counts, 31 * 64])
	assert_true(first == MAKE_TEXTURES.SLATES[0] or first == MAKE_TEXTURES.SLATES[1])


func test_slate_is_darker_and_bluer_than_the_flagstones() -> void:
	for slate: Color in MAKE_TEXTURES.SLATES:
		assert_true(slate.b > slate.r, "%s is a blue-grey" % slate.to_html(false))
		for stone: Color in MAKE_TEXTURES.STONES:
			assert_true(slate.v < stone.v - 0.2, "%s is well darker than the flagstone %s" % [slate.to_html(false), stone.to_html(false)])
		assert_true(MAKE_TEXTURES.SLATE_JOINT.v < slate.v - 0.04, "the joint is darker than %s" % slate.to_html(false))


func test_slate_is_made_the_same_every_time_and_has_its_material() -> void:
	var a := MAKE_TEXTURES.slate()
	assert_eq(a.get_data(), MAKE_TEXTURES.slate().get_data(), "two makes are the same")
	var committed := Image.load_from_file(ProjectSettings.globalize_path(SLATE))
	assert_true(committed != null, "the committed texture loads")
	if committed != null:
		committed.convert(a.get_format())
		assert_eq(committed.get_data(), a.get_data(), "the committed texture is what make_textures makes")
	var material := load(MATERIAL) as ShaderMaterial
	assert_true(material != null, "world/materials/slate.tres")
	if material != null:
		assert_eq(material.shader.resource_path, "res://render/shaders/toon_world.gdshader", "drawn as the world is")
		assert_eq((material.get_shader_parameter(&"albedo_tex") as Texture2D).resource_path, SLATE)
		assert_true(material.get_shader_parameter(&"world_uv"), "laid by the world's metres, as the floor is")
		assert_eq(material.get_shader_parameter(&"texels_per_metre"), 32.0)
