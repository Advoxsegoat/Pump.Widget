// The rim light on a character's silhouette (Rig.aura): a second pass over the toon body, an inverted hull.
//
// The body's own pass (toon_character.gdshader) is drawn as it always is. This pass draws the same mesh's back faces
// pushed outward, in the picture's own pixels, by rim_width, and pushed back from the camera by rim_push metres: only
// what is outside the body's silhouette shows, since the body's front faces are nearer and hide the rest. The push is what
// keeps the rim off the inside: a back face moved sideways by a pixel and a half would otherwise slip in front of a slanted
// or thin front face (a sleeve, a jacket) and light it. So the rim lights the edge 1 to 2 pixels wide and never the body's
// interior: a tell must not tint the outfit.
//
// rim_color's alpha is the colour's own; rim_strength (0 to 1) is how much of it shows. The pass is unshaded.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
// In pixels of the viewport the world is drawn in (the 642x362 picture's: one of them is one picture pixel).
uniform float rim_width = 1.5;
// How far the hull is pushed away from the camera, in metres: more than a front face's depth changes over the rim's width
// and than one limb stands in front of another. The push dies away toward the ground (over push_ramp metres above
// ground_y, the floor under the body, which Rig.tick keeps up to date), where it would sink the hull into the floor and
// leave the feet with no rim.
uniform float rim_push = 1.2;
uniform float push_ramp = 1.1;
uniform float ground_y = 0.0;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - ground_y;
	view.z -= rim_push * clamp(height / push_ramp, 0.3, 1.0);
	vec4 clip = PROJECTION_MATRIX * view;
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 away = view_normal.xy;
	away = length(away) > 0.0001 ? normalize(away) : vec2(0.0);
	// One pixel is 2 / VIEWPORT_SIZE of clip space (before the perspective divide, which an orthographic view leaves be).
	POSITION = vec4(clip.xy + away * rim_width * 2.0 / VIEWPORT_SIZE * clip.w, clip.zw);
}

void fragment() {
	ALBEDO = rim_color.rgb;
	ALPHA = rim_color.a * rim_strength;
}
