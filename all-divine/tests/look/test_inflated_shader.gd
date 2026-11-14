extends TestCase
## InflatedShader.of adds a vertex function and an `inflate` uniform to a shader's source. A base that already has either would not
## compile with them added and the body would be drawn broken: so it says why, once, and hands the base back (drawn thin, not broken).

func _shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader


func test_a_shader_with_its_own_vertex_function_is_handed_back_and_reported() -> void:
	var base := _shader("shader_type spatial;\nvoid vertex() {\n\tVERTEX.y += 1.0;\n}\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n")
	assert_true(InflatedShader.problem_with(base).contains("vertex"), "it names the vertex function: '%s'" % InflatedShader.problem_with(base))
	var got: Shader = quietly(func() -> Shader: return InflatedShader.of(base))
	assert_true(got == base, "the base shader comes back")
	assert_false(InflatedShader.is_inflated(got))
	assert_true((quietly(func() -> Shader: return InflatedShader.of(base)) as Shader) == base, "and again")


func test_a_shader_with_an_inflate_uniform_is_handed_back_and_reported() -> void:
	var base := _shader("shader_type spatial;\nuniform float inflate = 0.5;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n")
	assert_true(InflatedShader.problem_with(base).contains("inflate"), "it names the uniform: '%s'" % InflatedShader.problem_with(base))
	var got: Shader = quietly(func() -> Shader: return InflatedShader.of(base))
	assert_true(got == base, "the base shader comes back")


func test_the_shaders_it_is_used_on_are_safe_and_a_plain_one_is_inflated() -> void:
	for path in ["res://render/shaders/toon_character.gdshader", "res://render/shaders/afterimage.gdshader", "res://render/shaders/toon_rim_mark.gdshader"]:
		assert_eq(InflatedShader.problem_with(load(path) as Shader), "", "%s takes the function" % path)
	var plain := _shader("shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n")
	var thick := InflatedShader.of(plain)
	assert_true(InflatedShader.is_inflated(thick) and thick != plain, "a plain shader is inflated")
	assert_true(InflatedShader.of(plain) == thick, "once")
