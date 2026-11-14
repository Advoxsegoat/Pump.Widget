// The 2D half of the screen look: bloom, colour grade and vignette, drawn by the PixelStage as it scales
// the World picture up. The other half (depth of field, outlines, fog) is screen_post, on the CameraRig.
// The strengths come from RenderSettings and the grade from GradeProfile (PixelStage.apply_settings).
//
// Each output pixel works on the World texel under it, read at the texel itself (texelFetch), with every
// tap a whole number of texels away, so all the pixels of a k x k block come out the same and the picture
// stays crisp. Canvas drawing is in colours as shown (sRGB) in every renderer, so this pass is the same
// in Compatibility and Forward+. Whatever else the stage draws with this material (its black bars) has a
// texture of another size and is left as it is.
//
//   bloom     c += bloom_strength x the sum of w x max(s - threshold, 0) over a 3x3 of taps 2 texels
//             apart (w 0.25 at the centre, 0.125 at the sides, 0.0625 at the corners).
//   grade     g = pow(max(c x gain + lift x (1 - c), 0), 1 / gamma); g = mix(luma(g), g, saturation)
//             x tint, the luma with Rec. 709 weights; c = mix(c, g, grade_strength).
//   vignette  c *= 1 - vignette_strength x smoothstep(0.45, 0.85, length(uv - 0.5) x 1.414), uv being
//             the texel's centre on the World picture.
shader_type canvas_item;

// Every strength starts at 0, so a stage nobody has set up shows the picture as it was.
uniform float bloom_strength = 0.0;
uniform float bloom_threshold = 0.8;
uniform float grade_strength = 0.0;
uniform vec3 lift = vec3(0.0);
uniform vec3 gamma = vec3(1.0);
uniform vec3 gain = vec3(1.0);
uniform float saturation = 1.0;
uniform vec3 tint = vec3(1.0);
uniform float vignette_strength = 0.0;
// The size of the World picture, the one texture this pass works on.
uniform ivec2 picture_size = ivec2(642, 362);

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// The colour the picture is drawn in (the stage's modulate), before the texture is multiplied in.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

// The World texel at p, or the nearest one to it on the picture. (A macro: a canvas shader cannot hand
// TEXTURE to a function.)
#define TEXEL(p) texelFetch(TEXTURE, clamp(p, ivec2(0), size - 1), 0).rgb

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	if (all(equal(size, picture_size))) {
		ivec2 p = clamp(ivec2(floor(UV * vec2(size))), ivec2(0), size - 1);
		vec3 c = TEXEL(p);

		if (bloom_strength > 0.0) {
			vec3 glow = vec3(0.0);
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					float w = (x == 0 && y == 0) ? 0.25 : ((x == 0 || y == 0) ? 0.125 : 0.0625);
					glow += w * max(TEXEL(p + ivec2(x, y) * 2) - bloom_threshold, vec3(0.0));
				}
			}
			c += bloom_strength * glow;
		}

		if (grade_strength > 0.0) {
			vec3 g = pow(max(c * gain + lift * (1.0 - c), vec3(0.0)), 1.0 / max(gamma, vec3(0.001)));
			g = mix(vec3(dot(g, LUMA)), g, saturation) * tint;
			c = mix(c, g, grade_strength);
		}

		vec2 uv = (vec2(p) + 0.5) / vec2(size);
		c *= 1.0 - vignette_strength * smoothstep(0.45, 0.85, length(uv - 0.5) * 1.414);

		COLOR = vec4(c, 1.0) * modulate;
	}
}
