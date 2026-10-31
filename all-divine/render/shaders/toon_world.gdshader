// The world's toon look: a texture read texel by texel (nearest), lit in three flat steps. Characters have
// their own shader (toon_character); this one is for the ground, walls and props.
//
// The UV is the mesh's own (a Kenney piece's, on its colormap), or with world_uv the world position laid
// on the face's own plane: the ground's x and z for a face that looks most up or down, else x and y (a face
// toward +-Z) or z and y (toward +-X), y running down the texture; times texels_per_metre / the texture's
// size, so at 32 texels per metre one texel is one internal pixel across, whatever the mesh, and a wall or a
// stair's riser shows the stone laid on it rather than each column of texels smeared down it.
//
// Each light picks a step by i = N.L x attenuation (shadow included): below 0.15 it gives 0.35 of itself,
// below 0.55 0.7, else all of it, times LIGHT_COLOR / PI (so a white light of energy 1 at the full step
// shows the texture's own colour). The sun (a directional light) gives its 0.35 everywhere, its shadow and
// the faces turned from it included. A lamp (an omni or spot light) lights a pool: where i is below
// LAMP_REACH (past its range, in its shadow, on faces turned from it) it gives nothing. Lights add up, and
// the ambient light is kept.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform bool world_uv = false;
uniform float texels_per_metre = 32.0;

// Below this i a lamp gives nothing.
const float LAMP_REACH = 0.05;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = mat3(MODEL_MATRIX) * NORMAL;
}

void fragment() {
	vec2 uv = UV;
	if (world_uv) {
		vec3 n = abs(world_normal);
		vec2 plane = world_position.xz;
		if (n.y < max(n.x, n.z)) {
			plane = n.z >= n.x ? vec2(world_position.x, -world_position.y) : vec2(world_position.z, -world_position.y);
		}
		uv = plane * texels_per_metre / vec2(textureSize(albedo_tex, 0));
	}
	ALBEDO = texture(albedo_tex, uv).rgb;
}

void light() {
	float i = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL || i >= LAMP_REACH) {
		float level = i < 0.15 ? 0.35 : (i < 0.55 ? 0.7 : 1.0);
		DIFFUSE_LIGHT += level * LIGHT_COLOR / PI;
	}
}
