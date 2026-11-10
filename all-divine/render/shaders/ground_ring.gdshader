// A ring (and a faint disc inside it) lying on the ground, or standing as a billboard: the readability pass's ground
// waves and Abarax's parry ring (fx/ground_wave.gd sets `radius` and `fade` each frame).
//
// It is drawn on a flat quad `extent` metres from its middle to its side; `radius` is where the ring is now, `ring_width`
// how thick it is. The edge is hard, not smoothed: it is pixel art. Unshaded, transparent, never written to the depth
// buffer and read from it, so a body standing in it is drawn over it, and `render_priority` puts it before the other
// transparent things.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 ring_color : source_color = vec4(1.0);
uniform float extent = 2.0;
uniform float radius = 0.0;
uniform float ring_width = 0.14;
uniform float fill_alpha = 0.16;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0 * extent);
	float inside = step(d, radius);
	float band = inside * step(radius - ring_width, d);
	float alpha = max(band, inside * fill_alpha) * fade * ring_color.a;
	ALBEDO = ring_color.rgb;
	ALPHA = alpha;
}
