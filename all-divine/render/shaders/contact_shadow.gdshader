// The dark under a fighter's feet (world/bilibara/bilibara_region.gd): a soft ellipse lying flat on the ground, in three hard
// steps (it is pixel art), darkest under the feet. Unshaded, transparent, read from the depth buffer and never written to it, so a
// body standing on it is drawn over it. It plants a fighter on pale snow where the sun's own shadow is short, or gone because a front
// already shades the ground.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec3 shade : source_color = vec3(0.18, 0.22, 0.32);
// How much of the ground's colour the darkest step takes away (0 to 1); the middle step takes 0.6 of it, the outer 0.3.
uniform float strength : hint_range(0.0, 1.0) = 0.26;
// The ellipse's radius in the quad's own metres (half its side is 1).
uniform float inner = 0.42;
uniform float middle = 0.7;

void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0);
	float alpha = d < inner ? 1.0 : (d < middle ? 0.6 : (d < 1.0 ? 0.3 : 0.0));
	ALBEDO = shade;
	ALPHA = alpha * strength;
}
