// A roof, drawn as the world is (toon_world's three flat steps) with the roof's own picture laid on it: shingles from the eave up to
// the ridge, a dark eave, snow along the ridge (assets/env/textures/roof_*.png, made by tools/art/make_textures.gd).
//
// A roof piece is a tile 2.5 m across, its eave low on the side its plane faces and its ridge high on the other; the picture is one tile:
// its top row at the ridge, its bottom at the eave. It is read texel by texel (nearest). Each piece starts the picture somewhere along its
// width, by where it stands, so that the snow's edge does not repeat every tile; the picture wraps across and is held at its ends up the
// slope. (Found from the world position and the plane's normal, not from the mesh's own axes.)
//
// Two planes of one roof differ in tone: the plane that faces the camera's side (south, or east when the ridge runs north to south) keeps
// the picture's colours, the plane that faces away from it is `dark` of them, in the shading too, so a gable reads as two planes and a flat
// roof's top (which faces up, not aside) is the lighter. Lit as toon_world is: three steps below and above 0.15 and 0.55 of N.L, the sun's
// lowest step everywhere, a lamp a pool.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
// The tone of the plane that faces away from the camera's side, as a share of the lit plane's.
uniform float dark : hint_range(0.0, 1.0) = 0.72;
// The horizontal way the lighter plane faces (x east, y south); a plane whose horizontal normal points less than this way is the darker.
uniform vec2 toward = vec2(0.3, 0.95);

const float LAMP_REACH = 0.05;

varying vec3 around;
varying float height;
varying vec3 world_normal;
varying float across_shift;

void vertex() {
	// Where this point is from the middle of its tile's foot, in the world's axes (the piece's origin is that middle).
	around = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz;
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vec2 at = MODEL_MATRIX[3].xz;
	across_shift = fract(sin(dot(floor(at * 0.4 + 0.5), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Down the slope is the way the plane's normal leans (south on a flat roof's top, whose planes lean 0.23 at most: the kit's flat tile is a shallow trough): the tile is 2.5 m of it, the eave at its
	// downhill edge, the ridge at its uphill edge, the picture's top at the ridge. A vertical face (a rim) is all eave.
	vec2 lean = world_normal.xz;
	vec2 down = length(lean) > 0.3 ? normalize(lean) : vec2(0.0, 1.0);
	// (A vertical face, a rim or a gable's end, is shingles in rows by its height, with no snow on it: the rows below the snow's.)
	float up = world_normal.y < 0.2 ? 0.05 + 0.5 * fract(height / 2.9) : clamp(0.5 - dot(around.xz, down) / 2.5, 0.0, 0.999);
	float across = fract(dot(around.xz, vec2(-down.y, down.x)) / 2.5 + 0.5 + across_shift);
	vec3 picture = texture(albedo_tex, vec2(across, min(1.0 - up, 0.999))).rgb;
	vec2 side = world_normal.xz;
	float lit = smoothstep(-0.25, 0.05, dot(side, toward));
	float tone = mix(dark, 1.0, lit);
	ALBEDO = picture * tone;
}

void light() {
	float i = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL || i >= LAMP_REACH) {
		float level = i < 0.15 ? 0.35 : (i < 0.55 ? 0.7 : 1.0);
		DIFFUSE_LIGHT += level * LIGHT_COLOR / PI;
	}
}
