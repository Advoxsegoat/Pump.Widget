// The rim light on a character's silhouette (Rig.aura): the hull pass. render/rim_marks.gd says how it works with the
// mark pass (toon_rim_mark.gdshader), which is drawn first.
//
// The body's own pass (toon_character.gdshader) is drawn as it always is. This pass draws the same mesh again with every
// vertex pushed outward, in the picture's own pixels, by rim_width: the body grown by a pixel or two, at the body's own
// depth. It is lit only where the stencil buffer does not carry the body's own mark, which the mark pass wrote on every
// pixel of the body that shows. So the rim is the edge outside the silhouette, 1 to 2 pixels wide, and never the body's
// inside, in any pose: a tell must not tint the outfit. A limb in front of the torso gets no rim across the torso, since
// those pixels are the body's too.
//
// Against everything else it takes the ordinary depth test: a wall, a post or another body in front of it hides the rim as
// it hides the body, and what is behind the body, however near, does not. Both sides of every face are drawn (the front
// faces are the nearest, the back faces fill in where a thin piece has no front toward the camera), and each lit pixel
// takes the body's mark as it is lit, so a pixel that several faces reach is lit once and a rim at half strength is even.
//
// rim_color's alpha is the colour's own; rim_strength (0 to 1) is how much of it shows. The pass is unshaded.
//
// The number that ends the stencil_mode line is the body's mark. This file is written for mark 1; RimMarks makes a copy
// of it for each other mark, changing that number only.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
stencil_mode read, write, compare_not_equal, 1;

uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
// In pixels of the viewport the world is drawn in (the 642x362 picture's: one of them is one picture pixel).
uniform float rim_width = 1.5;
// The body's own pass is drawn thicker by this much (toon_character.gdshader's inflate): the rim grows from that body.
uniform float inflate = 0.0;

void vertex() {
	VERTEX += NORMAL * inflate;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Which way the surface faces in the picture: its normal across the view, taken through the projection like the vertex
	// itself (the projection turns the view's up into the picture's, which is not the same way up in every renderer and
	// render target), and measured in pixels. A face turned straight at the camera faces no way, and is not moved.
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 away = vec2(0.0);
	if (length(view_normal.xy) > 0.0001) {
		away = normalize((PROJECTION_MATRIX * vec4(view_normal.xy, 0.0, 0.0)).xy * VIEWPORT_SIZE);
	}
	// One pixel is 2 / VIEWPORT_SIZE of clip space (before the perspective divide, which an orthographic view leaves be).
	POSITION = vec4(clip.xy + away * rim_width * 2.0 / VIEWPORT_SIZE * clip.w, clip.zw);
}

void fragment() {
	ALBEDO = rim_color.rgb;
	ALPHA = rim_color.a * rim_strength;
}
