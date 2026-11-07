// A test surface whose pixels are exactly the sRGB colours it is given, in either renderer, so a picture
// of it is the same in Compatibility and Forward+ and only what is drawn over it can differ.
//
// A checker of colour_a and colour_b in cells of `cell` metres, laid out on each face by the face's own
// two axes, and each face shaded by which way it faces: up 1.0, toward +Z 0.78, toward +X or -X 0.62,
// anything else 0.5. The shade multiplies the sRGB colour, so the colours are plain to work out.
shader_type spatial;
render_mode unshaded, fog_disabled;

#include "res://render/shaders/display_colour.gdshaderinc"

uniform vec3 colour_a = vec3(1.0);
uniform vec3 colour_b = vec3(1.0);
uniform float cell = 1.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = mat3(MODEL_MATRIX) * NORMAL;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 a = abs(n);
	// The face's own axes: x and z on a floor or ceiling, x and y on a face toward Z, z and y toward X.
	vec2 along = a.y >= a.x && a.y >= a.z ? world_position.xz : (a.z >= a.x ? world_position.xy : world_position.zy);
	ivec2 square = ivec2(floor(along / cell + 0.0001));
	vec3 colour = ((square.x + square.y) & 1) == 0 ? colour_a : colour_b;
	float shade = n.y > 0.5 ? 1.0 : (n.z > 0.5 ? 0.78 : (a.x > 0.5 ? 0.62 : 0.5));
	ALBEDO = albedo_for_display(colour * shade);
}
