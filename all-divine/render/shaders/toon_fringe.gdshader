// A ragged fringe of one ground laid over the edge of another, along the seam where two grounds meet (the layout's `fringe`): a straight
// join of two stones reads as a sheet of paper laid on another, so the one ground reaches into the other in slabs and tongues of
// uneven length. The strip is a flat quad lying on the ground it reaches into, its edge on the seam (UV.y is 0 there) and its far edge UV.y
// metres out (UV.x runs along the seam in metres); each 0.5 m cell along the seam reaches out a share of the strip's depth that
// is low (up to 0.4 of the depth) in one cell and high (0.65 to 1) in the next, so that no run of its edge is straight for more than half a
// metre, and each texel of its edge is half a texel in or out of its cell's reach. Past the reach a fragment is discarded: the ground under the strip shows.
//
// The strip is drawn as toon_world draws the ground it lies on (the same stone, laid by the world's metres, the same three light
// steps), so that on the seam's own side, where the strip covers the same stone, nothing shows.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform float texels_per_metre = 32.0;
// The strip's depth (how far its far edge is from the seam, m) and the least a cell reaches out (m).
uniform float depth = 0.9;
uniform float least = 0.15;
uniform float seed = 1.0;

const float LAMP_REACH = 0.05;
// A cell along the seam is this long (m).
const float CELL = 0.5;

varying vec3 world_position;

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cell = floor(UV.x / CELL);
	// Even cells reach a little, odd cells far: the edge steps in and out at every cell.
	float share = hash(cell);
	float reach = mod(cell, 2.0) < 0.5 ? mix(least, depth * 0.4, share) : mix(depth * 0.65, depth, share);
	// A texel in or out at the edge, texel by texel.
	float texel = floor(UV.x * texels_per_metre);
	reach += (hash(texel + 17.0) - 0.5) * 1.0 / texels_per_metre;
	if (UV.y > reach) {
		discard;
	}
	vec2 uv = world_position.xz * texels_per_metre / vec2(textureSize(albedo_tex, 0));
	ALBEDO = texture(albedo_tex, uv).rgb;
}

void light() {
	float i = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL || i >= LAMP_REACH) {
		float level = i < 0.15 ? 0.35 : (i < 0.55 ? 0.7 : 1.0);
		DIFFUSE_LIGHT += level * LIGHT_COLOR / PI;
	}
}
