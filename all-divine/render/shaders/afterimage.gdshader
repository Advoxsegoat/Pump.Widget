// The afterimage (fx/afterimage.gd): a still copy of a body's silhouette, one flat colour, fading. It is drawn behind every body
// and over none, and never inside one.
//
// The bodies' own shader (toon_character.gdshader) writes 255 into the stencil buffer on every pixel it draws, and a rim's mark
// pass writes its own mark over that on its body's pixels, so wherever any body shows the stencil is not 0. This pass is drawn
// after every opaque thing and every rim (render_priority), and only where the stencil is 0, so it covers the ground, the walls
// and the air behind them, and no pixel of a body, however near or far it stands from the copy. It takes the ordinary depth test
// against the world, so a wall in front of the copy hides it.
//
// A body's mesh is many overlapping pieces (an arm over the chest), and a translucent colour laid on twice is darker where
// they overlap. So the copy is drawn twice, the first time (`depth_only`) writing only the depth of its nearest surface, the
// second time laying the colour only where its own surface is that nearest one, which is once on every pixel.
//
// Unshaded, so it is the colour whatever the light does.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix, shadows_disabled;
stencil_mode read, compare_equal, 0;

uniform vec4 tint : source_color = vec4(1.0);
// How much of the copy shows, 0 to 1: it fades as the frames go.
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// 1 for the pass that writes only the depth.
uniform float depth_only = 0.0;

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = depth_only > 0.5 ? 0.0 : tint.a * strength;
}
