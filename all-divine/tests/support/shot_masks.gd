class_name ShotMasks
extends RefCounted
## Pixel sets for the tests that compare two pictures of the world: which pixels changed, a body's silhouette, and a set
## grown or shrunk. A set is a Dictionary of Vector2i -> true.

## The two colours a body is drawn in to read its silhouette: nothing in the game is near either, and they are far apart.
const FLAT_BODY := Color(1.0, 0.0, 1.0)
const FLAT_BODY_OTHER := Color(0.0, 1.0, 0.0)


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
## the pixels that differ between two pictures of the body, each in one flat colour, both drawn without the screen look.
## The body is in both pictures, so its shadow on the floor is too and is no part of the difference (hiding the body
## instead would take its shadow away with it, and count the shadow as body); a dark coat on a dark floor counts, being
## drawn in the flat colours; and the look's blur and outlines, which reach a pixel or two past a body onto the ground and
## the wall behind it, are off. The world must stand still while this draws its frames; the body and the look are put
## back as they were, and the picture drawn again so, before it returns.
static func silhouette(main: Main, actor: Actor, box: Rect2i) -> Dictionary:
	var meshes := actor.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	var worn := []
	for mesh: MeshInstance3D in meshes:
		worn.append(mesh.material_override)
	var look := main.camera_rig.post_quad
	var look_was := look.visible
	look.visible = false
	var pictures: Array[Image] = []
	for colour: Color in [FLAT_BODY, FLAT_BODY_OTHER]:
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.albedo_color = colour
		for mesh: MeshInstance3D in meshes:
			mesh.material_override = flat
		for i in 2:
			await RenderingServer.frame_post_draw
		pictures.append(main.stage.world.get_texture().get_image())
	look.visible = look_was
	for i in meshes.size():
		(meshes[i] as MeshInstance3D).material_override = worn[i]
	for i in 2:
		await RenderingServer.frame_post_draw
	return diff(pictures[0], pictures[1], box.intersection(Rect2i(Vector2i.ZERO, pictures[0].get_size())))
