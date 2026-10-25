// The world's toon look: a texture read texel by texel (nearest), lit in three flat steps. Characters have
// their own shader (toon_character); this one is for the ground, walls and props.
//
// The UV is the mesh's own (a Kenney piece's, on its colormap), or with world_uv the world position laid
// on the ground: world XZ x texels_per_metre / the texture's size, so at 32 texels per metre one texel is
// one internal pixel across, whatever the mesh.
//
// Each light picks a step by i = N.L x attenuation (shadow included): below 0.15 it gives 0.35 of itself,
// below 0.55 0.7, else all of it, times LIGHT_COLOR / PI (so a white light of energy 1 at the full step
// shows the texture's own colour). Lights add up, and the ambient light is kept.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform bool world_uv = false;
uniform float texels_per_metre = 32.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	if (world_uv) {
		uv = world_position.xz * texels_per_metre / vec2(textureSize(albedo_tex, 0));
	}
	ALBEDO = texture(albedo_tex, uv).rgb;
}

void light() {
	float i = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float level = i < 0.15 ? 0.35 : (i < 0.55 ? 0.7 : 1.0);
	DIFFUSE_LIGHT += level * LIGHT_COLOR / PI;
}
