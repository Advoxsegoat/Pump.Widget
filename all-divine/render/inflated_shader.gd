class_name InflatedShader
extends RefCounted
## A body drawn thicker (ActorDef.body_inflate, Rig.set_body_inflate): the character shader, the rim's mark pass and the afterimage's
## shader with a vertex function added that pushes every vertex out along its normal by the uniform `inflate`, in the model's own units,
## after the skeleton has posed it. The hull pass of the rim (toon_rim.gdshader) has a vertex function of its own and takes the same
## uniform in its file.
##
## It is added to the code of the shader at run time, only for a body that is thicker, and not written into the shaders' files: a
## vertex function in the file would draw every body through another vertex path, and a pixel at the edge of a body, where two
## faces meet, came out a tone off on the heavy Knuckle at an inflate of 0 (the same source, with and without a function that adds
## nothing). So a body with no inflate is drawn by the shaders exactly as they were, and one with it by the same code with the function.
## The code the function is added to is whatever the shader's is, in both renderers: the function is outside their branches.

const SNIPPET := "\n// Added by InflatedShader: the body drawn thicker.\nuniform float inflate = 0.0;\nvoid vertex() {\n\tVERTEX += NORMAL * inflate;\n}\n"

const META := &"inflated"


## `base` with the inflating vertex function added (made once per shader and kept on it, as its metadata: a cache in a static would
## still hold the shader when the engine exits). If the function cannot be added safely (problem_with) it reports why, once, and
## returns `base` itself: the body is drawn thin, not broken.
static func of(base: Shader) -> Shader:
	if not base.has_meta(META):
		var why := problem_with(base)
		if not why.is_empty():
			push_error("InflatedShader: %s: %s; the body is drawn without its inflate" % [base.resource_path if not base.resource_path.is_empty() else "a shader", why])
			base.set_meta(META, false)  # refused, and said so: not the shader itself (a cycle would leak)
		else:
			var thick := Shader.new()
			thick.code = base.code + SNIPPET
			base.set_meta(META, thick)
	var made: Variant = base.get_meta(META)
	return made as Shader if made is Shader else base


## Why the function cannot be added to `base`'s source (it has a vertex function of its own, or a uniform called `inflate`), or "".
static func problem_with(base: Shader) -> String:
	if RegEx.create_from_string("\\bvoid\\s+vertex\\s*\\(").search(base.code) != null:
		return "it already has a vertex function, so the added one would not compile"
	if RegEx.create_from_string("\\buniform\\s+\\w+\\s+inflate\\b").search(base.code) != null:
		return "it already has a uniform called inflate"
	return ""


## Whether `shader` is one this made (the base handed back for a refusal is not).
static func is_inflated(shader: Shader) -> bool:
	return shader != null and shader.code.ends_with(SNIPPET)
