class_name ShotMasks
extends RefCounted
## Pixel sets for the tests that compare two pictures of the world: which pixels changed, a body's silhouette, and a set
## grown or shrunk. A set is a Dictionary of Vector2i -> true.

## The colour a body is drawn in to read its silhouette: nothing in the game is near it.
const FLAT_BODY := Color(1.0, 0.0, 1.0)


## The pixels of `box` where `a` differs from `b`: by more than `threshold`, summed over red, green and blue.
static func diff(a: Image, b: Image, box: Rect2i, threshold := 0.02) -> Dictionary:
	var changed := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > threshold:
				changed[Vector2i(x, y)] = true
	return changed


## The set `mask` shrunk by `r` pixels: a pixel stays when every pixel within r of it is in the set.
static func eroded(mask: Dictionary, r: int) -> Dictionary:
	var kept := {}
	for p: Vector2i in mask:
		var inside := true
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if not mask.has(p + Vector2i(dx, dy)):
					inside = false
					break
			if not inside:
				break
		if inside:
			kept[p] = true
	return kept


## The set `mask` grown by `r` pixels, and moved by `by`.
static func grown(mask: Dictionary, r: int, by := Vector2i.ZERO) -> Dictionary:
	var out := {}
	for p: Vector2i in mask:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				out[p + by + Vector2i(dx, dy)] = true
	return out


## The silhouette of `actor`'s body in `box` of the World picture of `main`: exactly the pixels its body shows on. They are
## the pixels that differ between a picture of the body in one flat colour and one without it, both drawn without the
## screen look. Hiding the body as it is dressed would miss a dark coat on a dark floor; and the look's blur and outlines
## reach a pixel or two past a body, onto the ground and the wall behind it, which are not the body. The world must stand
## still while this draws its four frames; the body and the look are put back as they were.
static func silhouette(main: Main, actor: Actor, box: Rect2i) -> Dictionary:
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = FLAT_BODY
	var meshes := actor.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	var worn := []
	for mesh: MeshInstance3D in meshes:
		worn.append(mesh.material_override)
		mesh.material_override = flat
	var look := main.camera_rig.post_quad
	var look_was := look.visible
	look.visible = false
	for i in 2:
		await RenderingServer.frame_post_draw
	var shown := main.stage.world.get_texture().get_image()
	actor.rig.visible = false
	for i in 2:
		await RenderingServer.frame_post_draw
	var hidden := main.stage.world.get_texture().get_image()
	actor.rig.visible = true
	look.visible = look_was
	for i in meshes.size():
		(meshes[i] as MeshInstance3D).material_override = worn[i]
	return diff(shown, hidden, box)
