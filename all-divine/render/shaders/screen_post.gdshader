// The 3D half of the screen look, drawn by the CameraRig's PostQuad over the whole World picture once the
// opaque world is drawn: tilt-shift depth of field, pixel outlines from depth, and depth-and-height fog.
// The other half (bloom, grade, vignette) is screen_final, on the PixelStage. The strengths come from
// RenderSettings and the fog from GradeProfile (PixelStage.apply_settings); `focus` from the CameraRig.
//
// It works in colours as shown (display_colour.gdshaderinc), reading the screen and depth texel by texel,
// so Compatibility and Forward+ do the same sums on the same values and draw the same picture. Depth is
// the linear view depth: each pixel is taken back through INV_PROJECTION_MATRIX to view space, which is
// right for the orthographic gameplay camera and for perspective cameras alike.
//
// Per pixel, in this order:
//   depth of field  coc = smoothstep(band/2, band/2 + 4, |depth - focus|) x dof_strength;
//                   col = mix(sharp, the mean of the 12 taps of a disc of radius 2 px, coc).
//   outline         a silhouette where a 4-neighbour is more than 0.25 m deeper (only the nearer pixel
//                   draws it), in the pixel's colour x 0.35; a crease where the normals rebuilt from the
//                   depths of a pixel and a 4-neighbour less than 0.25 m away differ by more than 40
//                   degrees (the nearer of the two draws it), x 0.7. Nothing at the far plane is outlined.
//                   On a line pixel, col = mix(col, line, outline x (1 - coc)); other pixels are left.
//   fog             f = fog_strength x (1 - exp(-density x max(depth - 8, 0)))
//                       x exp(-max(world_y - fog_height, 0) x 0.5);  col = mix(col, fog_color, f).
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, fog_disabled;

#include "res://render/shaders/display_colour.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

// Every strength starts at 0, so a quad nobody has set up leaves the picture as it was.
uniform float outline = 0.0;
uniform float dof_strength = 0.0;
// Metres from the camera, along its view, that are in focus.
uniform float focus = 20.0;
uniform float focus_band = 2.0;
uniform float fog_strength = 0.0;
// As shown (sRGB).
uniform vec3 fog_color = vec3(0.788235, 0.643137, 0.627451);
uniform float fog_density = 0.04;
uniform float fog_height = 1.5;

// A neighbour this much deeper (m) makes a silhouette; a crease needs the gap to be smaller.
const float SILHOUETTE_GAP = 0.25;
// cos(40 degrees): normals further apart than this make a crease.
const float CREASE_COS = 0.76604444;
const float SILHOUETTE_SHADE = 0.35;
const float CREASE_SHADE = 0.7;
// Metres over which the blur fades in past the sharp band.
const float DOF_RAMP = 4.0;
// The fog starts this far from the camera (m) and thins by this much per metre above fog_height.
const float FOG_START = 8.0;
const float FOG_FALLOFF = 0.5;

// The 4-neighbours.
const ivec2 SIDES[4] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
// The 12 taps of the blur disc, radius 2 px: the 4 sides, the 4 diagonals and the 4 two pixels out.
const ivec2 DISC[12] = ivec2[](
		ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
		ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1),
		ivec2(2, 0), ivec2(-2, 0), ivec2(0, 2), ivec2(0, -2));

void vertex() {
	// The 2x2 quad becomes the whole screen, whatever the camera.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

bool on_screen(ivec2 p, ivec2 size) {
	return p.x >= 0 && p.y >= 0 && p.x < size.x && p.y < size.y;
}

// The colour of pixel p as shown (the nearest pixel on screen, for a p just off it).
vec3 colour_at(ivec2 p, ivec2 size) {
	return display_from_screen(texelFetch(screen_tex, clamp(p, ivec2(0), size - 1), 0).rgb);
}

// Whether nothing was drawn at pixel p, so it shows the far plane (the depth buffer is reversed, and
// cleared to 0).
bool is_far(ivec2 p) {
	return texelFetch(depth_tex, p, 0).r <= 0.0;
}

// The view-space position of what pixel p (on screen) shows.
vec3 view_position(ivec2 p, ivec2 size, mat4 inv_projection) {
	float depth = texelFetch(depth_tex, p, 0).r;
	vec2 uv = (vec2(p) + 0.5) / vec2(size);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

// The step along the surface at pixel p, one pixel in direction d: to p + d or from p - d, on whichever
// side the surface carries on straight through p, judged by how far p's depth is from the line through
// the two pixels on that side (|2 d(p +- d) - d(p +- 2d) - d(p)|). That side is on p's own face, so near a
// crease the step stays on it wherever the crease falls within the pixel. (Picking the neighbour nearer
// in depth instead takes the chord across the crease about as often, which blends the two faces' normals:
// creases then flicker between missing and 2 px wide as things move by less than a pixel.)
vec3 surface_step(vec3 at, ivec2 p, ivec2 d, ivec2 size, mat4 inv_projection) {
	vec3 ahead = at;
	vec3 behind = at;
	float ahead_miss = 1e30;
	float behind_miss = 1e30;
	if (on_screen(p + 2 * d, size)) {
		ahead = view_position(p + d, size, inv_projection);
		ahead_miss = abs(2.0 * ahead.z - view_position(p + 2 * d, size, inv_projection).z - at.z);
	}
	if (on_screen(p - 2 * d, size)) {
		behind = view_position(p - d, size, inv_projection);
		behind_miss = abs(2.0 * behind.z - view_position(p - 2 * d, size, inv_projection).z - at.z);
	}
	return ahead_miss <= behind_miss ? ahead - at : at - behind;
}

// The surface normal at pixel p rebuilt from the depths around it (not normalised; its direction is
// what counts).
vec3 rebuilt_normal(ivec2 p, ivec2 size, mat4 inv_projection) {
	vec3 at = view_position(p, size, inv_projection);
	return cross(surface_step(at, p, ivec2(1, 0), size, inv_projection), surface_step(at, p, ivec2(0, 1), size, inv_projection));
}

void fragment() {
	ivec2 size = ivec2(VIEWPORT_SIZE);
	ivec2 p = clamp(ivec2(SCREEN_UV * VIEWPORT_SIZE), ivec2(0), size - 1);
	vec3 sharp = colour_at(p, size);
	vec3 here = view_position(p, size, INV_PROJECTION_MATRIX);
	float depth = -here.z;
	bool far_here = is_far(p);

	// Depth of field.
	float half_band = focus_band * 0.5;
	float coc = smoothstep(half_band, half_band + DOF_RAMP, abs(depth - focus)) * dof_strength;
	vec3 col = sharp;
	if (coc > 0.0) {
		vec3 blur = vec3(0.0);
		for (int i = 0; i < 12; i++) {
			blur += colour_at(p + DISC[i], size);
		}
		col = mix(sharp, blur / 12.0, coc);
	}

	// Outline.
	float weight = outline * (1.0 - coc);
	if (weight > 0.0 && !far_here) {
		float shade = 1.0;
		vec3 normal_here = vec3(0.0);
		bool have_normal = false;
		for (int i = 0; i < 4; i++) {
			ivec2 q = p + SIDES[i];
			if (!on_screen(q, size)) {
				continue;
			}
			float gap = -view_position(q, size, INV_PROJECTION_MATRIX).z - depth;
			if (gap > SILHOUETTE_GAP) {
				shade = SILHOUETTE_SHADE;
				break;
			}
			// A crease: the neighbour is on a surface that meets this one (no gap), is not the far plane,
			// is further away (so the nearer pixel draws it), and faces another way.
			if (gap > 0.0 && !is_far(q)) {
				if (!have_normal) {
					normal_here = rebuilt_normal(p, size, INV_PROJECTION_MATRIX);
					have_normal = true;
				}
				vec3 normal_there = rebuilt_normal(q, size, INV_PROJECTION_MATRIX);
				float lengths = sqrt(dot(normal_here, normal_here) * dot(normal_there, normal_there));
				if (lengths > 0.0 && dot(normal_here, normal_there) < CREASE_COS * lengths) {
					shade = CREASE_SHADE;
				}
			}
		}
		// Only where there is a line: everywhere else the colour is left as the depth of field made it.
		if (shade < 1.0) {
			col = mix(col, sharp * shade, weight);
		}
	}

	// Fog.
	if (fog_strength > 0.0) {
		float world_y = (INV_VIEW_MATRIX * vec4(here, 1.0)).y;
		float f = fog_strength * (1.0 - exp(-fog_density * max(depth - FOG_START, 0.0)))
				* exp(-max(world_y - fog_height, 0.0) * FOG_FALLOFF);
		col = mix(col, fog_color, f);
	}

	ALBEDO = albedo_for_display(col);
}
