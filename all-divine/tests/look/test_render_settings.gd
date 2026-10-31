extends TestCase
## The screen look's data (RenderSettings, GradeProfile and their .tres files) and how PixelStage and
## CameraRig carry it to the screen shaders. Headless: here the shaders are checked by their uniforms;
## tests/render/test_screen_post.gd checks their pixels.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const DEFAULT_SETTINGS := "res://data/render/default_settings.tres"
const DUSK := "res://data/render/grades/courtyard_dusk.tres"
const POST := "res://render/shaders/screen_post.gdshader"
const FINAL := "res://render/shaders/screen_final.gdshader"
const TOON_WORLD := "res://render/shaders/toon_world.gdshader"
## The settings that are not strengths: off() keeps them as they are.
const NOT_STRENGTHS := ["focus_band", "bloom_threshold"]
## Every strength the brief names.
const STRENGTHS := ["outline", "dof_strength", "bloom_strength", "fog_strength", "grade_strength", "vignette_strength"]

var stage: PixelStage
var rig: CameraRig
var target: Node3D


func before_each() -> void:
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	target = Node3D.new()
	stage.world.add_child(target)
	rig = CameraRig.new()
	rig.target = target
	rig.stage = stage
	stage.world.add_child(rig)


func test_off_zeroes_every_strength() -> void:
	var s := RenderSettings.new()
	s.focus_band = 3.5
	s.bloom_threshold = 0.6
	var off := s.off()
	assert_true(off != s, "off() is a copy")
	var floats := _float_properties(s)
	for name: String in STRENGTHS:
		assert_true(floats.has(name), "%s is a setting" % name)
	for name: String in floats:
		if NOT_STRENGTHS.has(name):
			assert_eq(off.get(name), s.get(name), "%s is not a strength and is kept" % name)
		else:
			assert_eq(off.get(name), 0.0, "%s is a strength and is 0" % name)
	assert_eq(s.outline, 1.0, "the original is left alone")
	assert_eq(s.vignette_strength, 0.35, "the original is left alone")


func test_render_settings_defaults_are_the_look() -> void:
	var s := RenderSettings.new()
	assert_eq(s.outline, 1.0)
	assert_eq(s.dof_strength, 1.0)
	assert_eq(s.focus_band, 2.0)
	assert_eq(s.bloom_strength, 0.35)
	assert_eq(s.bloom_threshold, 0.8)
	assert_eq(s.fog_strength, 0.5)
	assert_eq(s.grade_strength, 1.0)
	assert_eq(s.vignette_strength, 0.35)


func test_default_settings_file_holds_the_defaults() -> void:
	var file := load(DEFAULT_SETTINGS) as RenderSettings
	assert_ne(file, null, "default_settings.tres is a RenderSettings")
	if file == null:
		return
	var defaults := RenderSettings.new()
	for name: String in _float_properties(defaults):
		assert_eq(file.get(name), defaults.get(name), name)


func test_grade_profile_defaults_are_neutral_with_rose_fog() -> void:
	var g := GradeProfile.new()
	assert_eq(g.lift, Color(0, 0, 0))
	assert_eq(g.gamma, Color(1, 1, 1))
	assert_eq(g.gain, Color(1, 1, 1))
	assert_eq(g.saturation, 1.0)
	assert_eq(g.tint, Color(1, 1, 1))
	assert_eq(g.fog_color, Color("#c9a4a0"))
	assert_eq(g.fog_density, 0.04)
	assert_eq(g.fog_height, 1.5)


func test_courtyard_dusk_is_warm_and_rose() -> void:
	var g := load(DUSK) as GradeProfile
	assert_ne(g, null, "courtyard_dusk.tres is a GradeProfile")
	if g == null:
		return
	assert_eq(g.gain.to_html(false), "fff0e0")
	assert_eq(g.lift.to_html(false), "0a0612")
	assert_eq(g.saturation, 1.05)
	assert_true(g.gain.r > g.gain.b, "the gain is warm")
	assert_true(g.lift.b > g.lift.g and g.lift.r > g.lift.g, "the lift leans rose-violet")


# A stage and a rig nobody has given settings to pass the picture through: every strength is 0.
func test_stage_and_rig_start_with_every_effect_off() -> void:
	var final := stage.material as ShaderMaterial
	assert_ne(final, null, "the stage draws with a ShaderMaterial")
	if final != null:
		assert_eq(final.shader.resource_path, FINAL)
		for name in ["bloom_strength", "grade_strength", "vignette_strength"]:
			assert_eq(_param(final, name), 0.0, "final %s" % name)
		assert_eq(_param(final, "picture_size"), PixelStage.WORLD_SIZE)
	var post := rig.post_quad.material_override as ShaderMaterial
	for name in ["outline", "dof_strength", "fog_strength"]:
		assert_eq(_param(post, name), 0.0, "post %s" % name)
	assert_eq(stage.settings, null, "no settings yet")


func test_apply_settings_reaches_the_final_material_and_every_post_quad() -> void:
	var second := CameraRig.new()
	second.target = target
	stage.world.add_child(second)
	var s := RenderSettings.new()
	s.outline = 0.5
	s.dof_strength = 0.25
	s.focus_band = 3.0
	s.bloom_strength = 0.2
	s.bloom_threshold = 0.7
	s.fog_strength = 0.4
	s.grade_strength = 0.75
	s.vignette_strength = 0.1
	var g := load(DUSK) as GradeProfile
	stage.apply_settings(s, g)
	assert_eq(stage.settings, s)
	assert_eq(stage.grade, g)

	var final := stage.material as ShaderMaterial
	assert_near(_param(final, "bloom_strength"), 0.2, 1e-6)
	assert_near(_param(final, "bloom_threshold"), 0.7, 1e-6)
	assert_near(_param(final, "grade_strength"), 0.75, 1e-6)
	assert_near(_param(final, "vignette_strength"), 0.1, 1e-6)
	assert_near(_param(final, "saturation"), 1.05, 1e-6)
	assert_vec_near(_param(final, "lift"), _rgb(g.lift), 1e-6, "lift")
	assert_vec_near(_param(final, "gamma"), _rgb(g.gamma), 1e-6, "gamma")
	assert_vec_near(_param(final, "gain"), _rgb(g.gain), 1e-6, "gain")
	assert_vec_near(_param(final, "tint"), _rgb(g.tint), 1e-6, "tint")

	var quads := get_tree().get_nodes_in_group(&"post_quad")
	assert_true(quads.has(rig.post_quad) and quads.has(second.post_quad), "both rigs' quads are in group post_quad")
	for quad: GeometryInstance3D in [rig.post_quad, second.post_quad]:
		var post := quad.material_override as ShaderMaterial
		assert_near(_param(post, "outline"), 0.5, 1e-6)
		assert_near(_param(post, "dof_strength"), 0.25, 1e-6)
		assert_near(_param(post, "focus_band"), 3.0, 1e-6)
		assert_near(_param(post, "fog_strength"), 0.4, 1e-6)
		assert_vec_near(_param(post, "fog_color"), _rgb(g.fog_color), 1e-6, "fog_color")
		assert_near(_param(post, "fog_density"), g.fog_density, 1e-6)
		assert_near(_param(post, "fog_height"), g.fog_height, 1e-6)

	# Turning the look off turns every strength off, on both passes.
	stage.apply_settings(s.off(), g)
	for name in ["bloom_strength", "grade_strength", "vignette_strength"]:
		assert_eq(_param(final, name), 0.0, "final %s after off()" % name)
	for name in ["outline", "dof_strength", "fog_strength"]:
		assert_eq(_param(rig.post_quad.material_override, name), 0.0, "post %s after off()" % name)


# Another stage's quads keep their own settings, and a rig that arrives later gets this stage's.
func test_apply_settings_stays_inside_its_stage_and_reaches_late_rigs() -> void:
	var other := track(STAGE_SCENE.instantiate()) as PixelStage
	var other_rig := CameraRig.new()
	other.world.add_child(other_rig)
	stage.apply_settings(RenderSettings.new(), null)
	assert_eq(_param(other_rig.post_quad.material_override, "outline"), 0.0, "the other stage's rig is untouched")
	assert_ne(stage.grade, null, "a null grade is a neutral one")
	if stage.grade != null:
		assert_eq(stage.grade.gain, Color(1, 1, 1))
		assert_eq(stage.grade.lift, Color(0, 0, 0))
	var late := CameraRig.new()
	late.target = target
	late.stage = stage
	stage.world.add_child(late)
	assert_eq(_param(late.post_quad.material_override, "outline"), 1.0, "a rig added later gets the stage's settings")
	assert_eq(_param(late.post_quad.material_override, "dof_strength"), 1.0)
	# No settings at all is the look off.
	stage.apply_settings(null, null)
	assert_eq(_param(late.post_quad.material_override, "outline"), 0.0, "null settings turn the outline off")
	assert_eq(_param(stage.material, "vignette_strength"), 0.0, "null settings turn the vignette off")


func test_rig_builds_the_post_quad() -> void:
	var quad := rig.get_node_or_null("PostQuad") as MeshInstance3D
	assert_ne(quad, null, "the rig has a child PostQuad")
	if quad == null:
		return
	assert_eq(quad, rig.post_quad)
	assert_true(quad.is_in_group(&"post_quad"))
	var mesh := quad.mesh as QuadMesh
	assert_ne(mesh, null, "a QuadMesh")
	if mesh != null:
		assert_eq(mesh.size, Vector2(2, 2))
		assert_true(mesh.flip_faces, "flip_faces")
	assert_eq(quad.extra_cull_margin, 16384.0)
	assert_eq(quad.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var post := quad.material_override as ShaderMaterial
	assert_ne(post, null, "a ShaderMaterial")
	if post != null:
		assert_eq(post.shader.resource_path, POST)
		# Drawn first among the transparent things, right after the opaque pass the screen copy is taken
		# from, so anything transparent is drawn over the look rather than wiped by it.
		assert_eq(post.render_priority, Material.RENDER_PRIORITY_MIN)
	var code := (load(POST) as Shader).code
	for mode in ["unshaded", "depth_draw_never", "depth_test_disabled", "fog_disabled"]:
		assert_true(_render_modes(code).has(mode), "screen_post renders %s" % mode)
	assert_true(code.contains("POSITION = vec4(VERTEX.xy, 1.0, 1.0)"), "the quad covers the screen whatever the camera")


# The focus is the target's distance from the camera, along the view (the depth the shader compares with).
func test_focus_is_the_camera_distance_to_its_target() -> void:
	rig.snap_now()
	var post := rig.post_quad.material_override as ShaderMaterial
	assert_near(_param(post, "focus"), CameraRig.DISTANCE, 1e-3, "the target at the follow point is DISTANCE away")
	# A target that leads the follow point (look-ahead) is nearer or further than DISTANCE.
	var body := CharacterBody3D.new()
	stage.world.add_child(body)
	body.position = Vector3(0, 0, -2)
	body.reset_physics_interpolation()
	rig.target = body
	rig.snap_now()
	body.velocity = Vector3(0, 0, -4)
	rig.snap_now()
	var to_body := body.global_position - rig.camera.global_position
	var expected := to_body.dot(-rig.camera.global_basis.z)
	assert_near(_param(post, "focus"), expected, 1e-3, "the body's own depth, not the leaning follow point's")
	assert_true(absf(expected - CameraRig.DISTANCE) > 0.3, "the look-ahead moved the follow point away from the body")


# Each shader compiles for this renderer (headless runs compile them, as Forward+, so this also checks the
# branches the Compatibility render tests cannot see) and has the uniforms the wiring sets.
func test_the_look_shaders_compile_for_this_renderer() -> void:
	var expected := {
		POST: ["outline", "dof_strength", "focus", "focus_band", "fog_strength", "fog_color", "fog_density", "fog_height"],
		FINAL: ["bloom_strength", "bloom_threshold", "grade_strength", "lift", "gamma", "gain", "saturation", "tint", "vignette_strength", "picture_size"],
		TOON_WORLD: ["albedo_tex", "world_uv", "texels_per_metre"],
	}
	for path: String in expected:
		var shader := Shader.new()
		shader.code = (load(path) as Shader).code
		var names := shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
		for name: String in expected[path]:
			assert_true(names.has(name), "%s has %s (compiled for %s: %s)" % [path.get_file(), name, RenderingServer.get_current_rendering_method(), names])


# --- helpers ---

# The names of the script's float properties.
func _float_properties(o: Object) -> PackedStringArray:
	var names := PackedStringArray()
	for p in o.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["type"] == TYPE_FLOAT:
			names.append(p["name"])
	return names


func _param(m: Material, name: String) -> Variant:
	return (m as ShaderMaterial).get_shader_parameter(name)


func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


# The words of the shader's render_mode line.
func _render_modes(code: String) -> PackedStringArray:
	for line in code.split("\n"):
		if line.strip_edges().begins_with("render_mode"):
			var modes := PackedStringArray()
			for word in line.strip_edges().trim_prefix("render_mode").trim_suffix(";").split(","):
				modes.append(word.strip_edges())
			return modes
	return PackedStringArray()
