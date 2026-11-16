// The mark pass of the rim light on a character's silhouette (Rig.aura; render/rim_marks.gd says how the passes work
// together): the body drawn once more, over itself, while its rim is on. It shows nothing (its alpha is 0) and writes
// nothing to the depth buffer; what it does is write the body's mark into the stencil buffer on every pixel of the body
// that shows (the ordinary depth test: where the body's own pass was the nearest thing drawn). The hull pass
// (toon_rim.gdshader) then lights only pixels that do not carry this mark, so the rim can never fall on the body's inside.
//
// It is a transparent pass so that it is drawn after every opaque thing, when the depth buffer is whole, and its
// material's render_priority puts it before every hull pass (Rig): each body's mark is written before any rim reads it.
//
// The number that ends the stencil_mode line is the body's mark. This file is written for mark 1; RimMarks makes a copy
// of it for each other mark, changing that number only.
shader_type spatial;
render_mode unshaded, depth_draw_never, blend_mix, shadows_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
