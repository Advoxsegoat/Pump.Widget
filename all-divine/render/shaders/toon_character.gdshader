// Characters' toon look: every pixel is one of the four tones of its palette slot, picked by a light
// ramp. Under one white light of energy 1, every pixel is exactly a palette tone.
//
// The model puts each face in a slot with UV2.x = (slot + 0.5) / 16. The palette is render/palette.gd's
// 4x16 texture (x the tone: 0 highlight, 1 base, 2 shade, 3 deep; y the slot), read texel by texel.
// For each light, i = N.L x attenuation picks the tone: deep below ramp.x, shade below ramp.y, base
// below ramp.z, the highlight above.
//
// Forward+ and Mobile light in linear and encode to sRGB once, exactly. There the deep tone is the
// emission, the floor where no light reaches, and a light adds the step from deep up to its tone times
// its colour and energy (ALBEDO x DIFFUSE_LIGHT = (tone - deep) x LIGHT_COLOR / PI), so a white light of
// energy 1 lands on the tone itself.
//
// Compatibility cannot do it that way. It decodes ALBEDO and EMISSION from sRGB with a cubic and encodes
// with 1.055 x^(1/2.4) - 0.055, which are not each other's inverse: a dark tone sent through the emission
// comes back as much as 7/255 off. And a light that casts shadows is drawn in a pass of its own, encoded
// alone and added to the rest in sRGB, so a step on top of the emission comes out too bright. So in
// Compatibility there is no emission and each light carries the whole colour: what Forward+ shows for it,
// handed over as the linear value that Compatibility's encoder turns into exactly that. Lit pixels match
// Forward+ for any one light; only where no light reaches at all is Compatibility black, not deep.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform sampler2D palette : source_color, filter_nearest;
uniform vec3 ramp = vec3(0.1, 0.4, 0.85);

// Tone t of palette slot `slot` as the texture gives it: linear in Forward+ and Mobile (source_color
// decodes it there), and the stored sRGB in Compatibility (which decodes ALBEDO and EMISSION instead).
vec3 tone(int slot, int t) {
	return texelFetch(palette, ivec2(t, slot), 0).rgb;
}

int slot_of(vec2 uv2) {
	return int(uv2.x * 16.0);
}

// The tone a light of intensity i (N.L x attenuation) picks.
int ramp_tone(float i) {
	return i < ramp.x ? 3 : (i < ramp.y ? 2 : (i < ramp.z ? 1 : 0));
}

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec3 linear_to_srgb(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}

// The linear value that Compatibility's encoder turns into the sRGB colour c.
vec3 compatibility_linear(vec3 c) {
	return pow((c + 0.055) / 1.055, vec3(2.4));
}
#endif

void fragment() {
	int slot = slot_of(UV2);
	ALBEDO = tone(slot, 1);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	EMISSION = tone(slot, 3);
#endif
}

void light() {
	int slot = slot_of(UV2);
	float i = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	int t = ramp_tone(i);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// What Forward+ shows for this light, in linear: the deep tone plus the light's step up to tone t.
	vec3 deep = srgb_to_linear(tone(slot, 3));
	vec3 lit = deep + max((srgb_to_linear(tone(slot, t)) - deep) * LIGHT_COLOR / PI, vec3(0.0));
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, compatibility_linear(linear_to_srgb(lit)) / max(ALBEDO, vec3(0.001)));
#else
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, (tone(slot, t) - tone(slot, 3)) / max(ALBEDO, vec3(0.001)) * LIGHT_COLOR / PI);
#endif
}
