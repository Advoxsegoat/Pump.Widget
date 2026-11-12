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
## still hold the shader when the engine exits). `base` must have no vertex function of its own.
static func of(base: Shader) -> Shader:
	if not base.has_meta(META):
		var thick := Shader.new()
		thick.code = base.code + SNIPPET
		base.set_meta(META, thick)
	return base.get_meta(META) as Shader


## Whether `shader` is one this made.
static func is_inflated(shader: Shader) -> bool:
	return shader != null and shader.code.ends_with(SNIPPET)
