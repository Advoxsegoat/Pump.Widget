class_name BilibaraRead
extends RefCounted
## The measuring rig of the readability tests (tests/render/test_bilibara_readability*.gd): the stretch's final picture at 1280 x 720, bodies
## stood in rows at reference positions, and what the picture shows of each (see the tests' header for the measures).

const MAIN := "res://main/main.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_3 := "res://data/actors/knuckle_3.tres"
const HEAVY := "res://data/actors/knuckle_heavy.tres"
const BLADE := "res://data/actors/knuckle_blade.tres"
const DRUMMER := "res://data/actors/knuckle_drummer.tres"
const BODY_NAMES := {ABARAX: "Abarax", KNUCKLE_1: "tier I", KNUCKLE_3: "tier III", HEAVY: "heavy", BLADE: "blade", DRUMMER: "drummer"}
const SIZE := Vector2i(1280, 720)
const OUT_TEXT := "out/shots/bilibara_readability.txt"
const OUT_SHEET := "out/shots/bilibara_readability.png"
## The ground a fighter stands on is pale (trodden snow, pale slate, snow-dusted earth): 0.62 to 0.74 in the final picture.
const GROUND_LOW := 0.62
const GROUND_HIGH := 0.74
## Every body is this much darker than its ground (Abarax is the palest, 0.56 or so: his ground is 0.64 or more).
const LEAST_DARKER := 0.08
const MOST_SPREAD := 0.08
## The head is the top share of a body's silhouette; the ring round it is within HEAD_NEAR in luma of the head's tone for under HEAD_BLEND_MOST of its
## pixels, ground or front (the plaster, a door, a shutter, a wall behind the head).
const HEAD_SHARE := 0.22
const HEAD_NEAR := 0.08
const HEAD_BLEND_MOST := 0.5
## A head's ring under this many pixels is too small to say anything (the rule passes it); with `strict_head` it is a problem.
const HEAD_RING_LEAST := 60
## Frames for a pile's column of petals to settle (its particles are made filled: they are started a lifetime ahead).
const PILE_FILLS := 40
## Abarax's shirt against the ground, or an outline at least this much darker along this share of the shirt's edge.
const SHIRT_LEAST := 0.06
const OUTLINE_DARKER := 0.25
const OUTLINE_SHARE := 0.9
## The ground in the strip under a body's feet is at least this much darker with the body there than without it.
const CONTACT_LEAST := 0.06
const ROW_ONE: Array[String] = [ABARAX, KNUCKLE_1, KNUCKLE_3]
const ROW_TWO: Array[String] = [DRUMMER, HEAVY, BLADE]
## The strip under the feet (picture pixels about the feet): the soft ellipse under each body is round about them.
const STRIP_LEFT := 16
const STRIP_RIGHT := 16
const STRIP_ABOVE := 4
const STRIP_BELOW := 10
const SHIRT_SLOT := 3  # Abarax's palette slot "main": the white shirt
const SHIRT_SHADER := """
shader_type spatial;
render_mode unshaded;
void fragment() {
	ALBEDO = int(UV2.x * 16.0) == 3 ? vec3(1.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
}
"""



var t: TestCase


func _init(test: TestCase) -> void:
	t = test


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _foe(main: Main, def_path: String) -> Actor:
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.def = load(def_path) as ActorDef
	foe.set_brain(Brain.new())
	main.region.add_child(foe)
	return foe


# Where a pixel of the world picture (with its margin) is in the window's picture: the middle of its block.
func _to_window(main: Main, p: Vector2i) -> Vector2i:
	var k := PixelStage.scale_for(SIZE)
	var corner := PixelStage.layout(SIZE).position + PixelStage.draw_offset(main.stage.subpixel, k)
	return corner + (p - Vector2i(PixelSnap.MARGIN, PixelSnap.MARGIN)) * k + Vector2i(k / 2, k / 2)


# The pixels of `box` that are ground a fighter can stand on (the region's Walkable plates), as the screen shows them: drawn in one flat colour with
# everything else of the region and every body hidden, the screen look off. A body in a lane stands in front of a front with dark shutters; the ground
# measure is of the ground, not of what the fronts behind it add. The stage's picture is left as it was.
func _ground_mask(main: Main, box: Rect2i) -> Dictionary:
	var region := main.region
	if not region.has_node(^"Walkable"):
		# The training yard is one floor: every pixel of the box counts.
		var all := {}
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				all[Vector2i(x, y)] = true
		return all
	var actor_shown := {}
	for node in t.get_tree().get_nodes_in_group(Actor.GROUP):
		actor_shown[node] = (node as Node3D).visible
		(node as Node3D).visible = false
	var shadows := region.get_node_or_null(^"ContactShadows") as Node3D
	var shadows_were := shadows.visible if shadows != null else false
	if shadows != null:
		shadows.visible = false
	# Everything but the Walkable plates drawn flat green (so that a kerb or a front hides the ground behind it as it does in the picture), the
	# plates flat magenta.
	var walkable := region.get_node("Walkable")
	var fringes := region.get_node_or_null("Fringes")
	var worn: Array[Dictionary] = []
	var magenta := StandardMaterial3D.new()
	magenta.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	magenta.albedo_color = ShotMasks.FLAT_BODY
	var green := StandardMaterial3D.new()
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green.albedo_color = ShotMasks.FLAT_BODY_OTHER
	for mesh: GeometryInstance3D in region.find_children("*", "GeometryInstance3D", true, false):
		if shadows != null and shadows.is_ancestor_of(mesh):
			continue
		var inside_actor := false
		var up := mesh.get_parent()
		while up != null and up != region:
			if up is Actor:
				inside_actor = true
			up = up.get_parent()
		if inside_actor:
			continue
		worn.append({mesh = mesh, was = mesh.material_override})
		mesh.material_override = magenta if walkable.is_ancestor_of(mesh) or (fringes != null and fringes.is_ancestor_of(mesh)) else green
	var look := main.camera_rig.post_quad
	var look_was := look.visible
	look.visible = false
	for i in 2:
		await RenderingServer.frame_post_draw
	var picture := main.stage.world.get_texture().get_image()
	look.visible = look_was
	for entry in worn:
		(entry.mesh as GeometryInstance3D).material_override = entry.was
	if shadows != null:
		shadows.visible = shadows_were
	for node: Node3D in actor_shown:
		node.visible = actor_shown[node]
	for i in 2:
		await RenderingServer.frame_post_draw
	var ground := {}
	var clipped := box.intersection(Rect2i(Vector2i.ZERO, picture.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var c := picture.get_pixel(x, y)
			if c.r > 0.6 and c.b > 0.6 and c.g < 0.4:
				ground[Vector2i(x, y)] = true
	return ground


# {body, ground, all, pixels, ring, contact, under} for `actor` in the window picture `shot`, the silhouettes of all the bodies in `bodies` leaving the
# ring. `ground` is the mean luma of the ring's pixels that are ground (see _ground_mask) and `all` of the whole ring (the fronts behind a body in a lane
# too). `contact` is how much darker the ground in a strip under its feet is with the body there than without it (`empty` is the same picture with
# every body gone): his shadows, the sun's and the ellipse under him, are all that differ.
func _box_of(main: Main, actor: Actor) -> Rect2i:
	var feet := Vector2i(main.camera_rig.camera.unproject_position(actor.global_position).round()) + Vector2i(PixelSnap.MARGIN, PixelSnap.MARGIN)
	return Rect2i(feet.x - 62, feet.y - 80, 124, 100).intersection(Rect2i(Vector2i.ZERO, main.stage.world.size))


# `mine`, `others` (the other bodies' silhouettes together) and `floor` (the ground of the whole picture) are made once for the row by _row.
func _measure(main: Main, shot: Image, empty: Image, actor: Actor, mine: Dictionary, others: Dictionary, floor: Dictionary) -> Dictionary:
	var feet := Vector2i(main.camera_rig.camera.unproject_position(actor.global_position).round()) + Vector2i(PixelSnap.MARGIN, PixelSnap.MARGIN)
	var box := _box_of(main, actor)
	var near := ShotMasks.grown(others, 3)
	var inner := ShotMasks.eroded(mine, 1)
	var ring_outer := ShotMasks.grown(mine, 8)
	var ring_inner := ShotMasks.grown(mine, 2)
	var mine_1 := ShotMasks.grown(mine, 1)
	var strip := Rect2i(feet.x - STRIP_LEFT, feet.y - STRIP_ABOVE, STRIP_LEFT + STRIP_RIGHT, STRIP_ABOVE + STRIP_BELOW)
	var body_sum := 0.0
	for p: Vector2i in inner:
		body_sum += _luma(shot.get_pixelv(_to_window(main, p).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)))
	var ground_sum := 0.0
	var ground_count := 0
	var all_sum := 0.0
	var all_count := 0
	for p: Vector2i in ring_outer:
		if not ring_inner.has(p) and not near.has(p) and box.has_point(p):
			var luma := _luma(shot.get_pixelv(_to_window(main, p).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)))
			all_sum += luma
			all_count += 1
			if floor.has(p):
				ground_sum += luma
				ground_count += 1
	var under_sum := 0.0
	var under_count := 0
	for y in range(strip.position.y, strip.end.y):
		for x in range(strip.position.x, strip.end.x):
			var p := Vector2i(x, y)
			if not box.has_point(p) or not floor.has(p) or mine_1.has(p) or near.has(p):
				continue
			var at := _to_window(main, p).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)
			under_sum += _luma(empty.get_pixelv(at)) - _luma(shot.get_pixelv(at))
			under_count += 1
	var contact := under_sum / maxf(under_count, 1.0)
	# The head (the top share of the silhouette) against what is round it, ground or front: the share of the ring 3 to 6 pixels outside the head that
	# is within HEAD_NEAR of the head's own tone (a head that merges with the front behind it is lost whatever the ground is).
	var top := 100000
	var bottom := -100000
	for p: Vector2i in mine:
		top = mini(top, p.y)
		bottom = maxi(bottom, p.y)
	var head := {}
	for p: Vector2i in inner:
		if p.y <= top + int(HEAD_SHARE * (bottom - top)):
			head[p] = true
	var head_sum := 0.0
	for p: Vector2i in head:
		head_sum += _luma(shot.get_pixelv(_to_window(main, p).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)))
	var head_luma := head_sum / maxf(head.size(), 1.0)
	var head_ring_outer := ShotMasks.grown(head, 6)
	var head_ring_inner := ShotMasks.grown(head, 2)
	var ring_count := 0
	var blend := 0
	var front := 0
	for p: Vector2i in head_ring_outer:
		if not head_ring_inner.has(p) and not mine_1.has(p) and not near.has(p) and box.has_point(p):
			var l := _luma(shot.get_pixelv(_to_window(main, p).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)))
			ring_count += 1
			if absf(l - head_luma) < HEAD_NEAR:
				blend += 1
			if not floor.has(p):
				front += 1
	return {body = body_sum / maxf(inner.size(), 1.0), ground = ground_sum / maxf(ground_count, 1.0), all = all_sum / maxf(all_count, 1.0), pixels = inner.size(), ring = ground_count, contact = contact, under = under_count,
			head = head_luma, head_blend = float(blend) / maxf(ring_count, 1.0), head_front = float(front) / maxf(ring_count, 1.0), head_ring = ring_count}


# Abarax's shirt alone: the pixels of slot SHIRT_SLOT (drawn flat, with the rest of him in another flat colour, the screen look off), their mean luma
# in the final picture `shot` (less the outermost pixel), and the share of the shirt's outer edge (its pixels next to no body, and the pixel outside
# them) that is `OUTLINE_DARKER` darker than `ground`, where an outline would be. {luma, diff, pixels, outline}
func _measure_shirt(main: Main, shot: Image, abarax: Actor, ground: float) -> Dictionary:
	var feet := Vector2i(main.camera_rig.camera.unproject_position(abarax.global_position).round()) + Vector2i(PixelSnap.MARGIN, PixelSnap.MARGIN)
	var box := Rect2i(feet.x - 40, feet.y - 80, 80, 100).intersection(Rect2i(Vector2i.ZERO, main.stage.world.size))
	var meshes := abarax.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	var worn := []
	for mesh: MeshInstance3D in meshes:
		worn.append(mesh.material_override)
	var flat := ShaderMaterial.new()
	flat.shader = Shader.new()
	flat.shader.code = SHIRT_SHADER
	var look := main.camera_rig.post_quad
	var look_was := look.visible
	look.visible = false
	for mesh: MeshInstance3D in meshes:
		mesh.material_override = flat
	for i in 2:
		await RenderingServer.frame_post_draw
	var flat_picture := main.stage.world.get_texture().get_image()
	look.visible = look_was
	for i in meshes.size():
		(meshes[i] as MeshInstance3D).material_override = worn[i]
	for i in 2:
		await RenderingServer.frame_post_draw
	var shirt := {}
	var body := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var c := flat_picture.get_pixel(x, y)
			if c.r > 0.6 and c.b > 0.6 and c.g < 0.4:
				shirt[Vector2i(x, y)] = true
				body[Vector2i(x, y)] = true
			elif c.g > 0.6 and c.r < 0.4 and c.b < 0.4:
				body[Vector2i(x, y)] = true
	var inner := ShotMasks.eroded(shirt, 1)
	var sum := 0.0
	for p: Vector2i in inner:
		sum += _luma(shot.get_pixelv(_to_window(main, p).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)))
	var luma := sum / maxf(inner.size(), 1.0)
	var edge := 0
	var dark := 0
	for p: Vector2i in shirt:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not body.has(p + step):
				var outside := p + step
				var low := minf(_luma(shot.get_pixelv(_to_window(main, p).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE))),
						_luma(shot.get_pixelv(_to_window(main, outside).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE))))
				edge += 1
				if ground - low >= OUTLINE_DARKER:
					dark += 1
				break
	return {luma = luma, diff = absf(luma - ground), pixels = inner.size(), outline = float(dark) / maxf(edge, 1.0), edge = edge}


# Three bodies in a row at `at` (Abarax in the middle), measured; the window picture is returned in `shot`.
func _row(main: Main, at: Vector3, defs: Array[String], shot_out: Array) -> Dictionary:
	# `defs` are the bodies' def paths, centre then east then west. Abarax is the centre when his path is given; else he stands at the centre
	# hidden (the camera follows him) and the centre def stands there in his place.
	var abarax := main.player
	var bodies: Array[Actor] = []
	var names: Array[String] = []
	abarax.set_brain(Brain.new())
	abarax.place(Transform3D(Basis.IDENTITY, at))
	var offsets := [0.0, 2.4, -2.4]
	for i in 3:
		var actor: Actor = abarax if defs[i] == ABARAX else _foe(main, defs[i])
		actor.place(Transform3D(Basis.IDENTITY, at + Vector3(offsets[i], 0.0, 0.0)))
		bodies.append(actor)
		names.append(BODY_NAMES[defs[i]])
	abarax.visible = defs[0] == ABARAX
	main.camera_rig.snap_now()
	await t.frames(12)
	for actor in bodies + [abarax]:
		(actor as Actor).freeze(100000000)
	main.camera_rig.snap_now()
	for i in 4:
		await RenderingServer.frame_post_draw
	var shot := t.get_viewport().get_texture().get_image()
	shot_out.append(shot)
	# The same picture with the bodies gone, and their shadows with them: what a body's shadows (the sun's and the ellipse under him) take from
	# the ground is the difference.
	var was_visible := {}
	for actor in bodies + [abarax]:
		if not was_visible.has(actor):
			was_visible[actor] = (actor as Actor).visible
		(actor as Actor).visible = false
	for i in 4:
		await RenderingServer.frame_post_draw
	var empty := t.get_viewport().get_texture().get_image()
	for actor: Actor in was_visible:
		actor.visible = was_visible[actor]
	for i in 3:
		await RenderingServer.frame_post_draw
	# A body's silhouette is the difference of two pictures a frame apart: petals that fade between them would be part of it. The masks are made
	# without particles (the pictures above, the ones the rule is read from, have them).
	var particles: Array[GPUParticles3D] = []
	for node in main.find_children("*", "GPUParticles3D", true, false):
		if (node as GPUParticles3D).visible:
			particles.append(node as GPUParticles3D)
			(node as GPUParticles3D).visible = false
	var silhouettes: Array[Dictionary] = []
	for i in 3:
		silhouettes.append(await ShotMasks.silhouette(main, bodies[i], _box_of(main, bodies[i])))
	var floor := await _ground_mask(main, Rect2i(Vector2i.ZERO, main.stage.world.size))
	var result := {}
	for i in 3:
		var others := {}
		for j in 3:
			if j != i:
				others.merge(silhouettes[j])
		result[names[i]] = await _measure(main, shot, empty, bodies[i], silhouettes[i], others, floor)
	if defs[0] == ABARAX:
		result["Abarax"]["shirt"] = await _measure_shirt(main, shot, abarax, result["Abarax"].ground)
	for node in particles:
		node.visible = true
	for actor in bodies:
		if actor != abarax:
			actor.queue_free()
	abarax.visible = true
	await t.frames(2)
	return result


## A pile of petals at `at`, as a death leaves it (the run's own: `Petals.fall_at`, which the run draws), and `settle` frames for its column to
## fill (it takes a lifetime of its petals).
func lay_pile(main: Main, at: Vector3, settle: int) -> void:
	main.stretch.data.petals = 120
	main.stretch.petals.fall_at(at)
	await t.frames(settle)


func _write(path: String, text: String) -> void:
	var full := ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var file := FileAccess.open(full, FileAccess.WRITE)
	file.store_string(text)




## Measures the bodies at `positions` ([name, x, z]) in the stretch; writes the table to `out_text` and the sheet to `out_sheet`; returns the problems found.
## `options`: `pile` (an offset from the tier I Knuckle's place, 2.4 m east of each position: a pile of petals lies there, as it does where a
## fighter fell, and `pile_settle` frames pass for its column to settle), `row_one_only` (only Abarax, a tier I and a tier III Knuckle: not the second row of bodies), `settle` (frames to wait after entering the stretch, so that a glow of petals has filled: it takes about 4 s), `head_only` (only
## the head's ring is held: beside a shrine the question is whether the glow hides a head), `strict_head` (a head ring under HEAD_RING_LEAST
## pixels is a problem line too: a body the glow hides reports a ring of 0 and would otherwise pass)).
func stretch(positions: Array, out_text: String, out_sheet: String, options: Dictionary = {}) -> PackedStringArray:
	var head_only: bool = options.get("head_only", false)
	var strict_head: bool = options.get("strict_head", false)
	Game.reset()
	var main := t.track((load(MAIN) as PackedScene).instantiate()) as Main
	await t.frames(5)
	main.enter_stretch()
	if options.get("open_gates", false):
		for door: GateDoor in main.stretch.gates:  # Task 5: every gate open (the boards gone), as after the shortcut and the toll are won
			door.open(false)
	await t.frames(5 + int(options.get("settle", 0)))
	var lines := PackedStringArray(["position | x z | per body: ground / body luma / ground less body / contact shadow (the strip under the feet without the body less with it)"])
	var problems := PackedStringArray()
	var lowest := {}
	var highest := {}
	var worst_margin := 9.0
	var worst_of := {}
	var shirts := PackedStringArray()
	var shots: Array[Image] = []
	for entry: Array in positions:
		var at := Vector3(entry[1], 0.0, entry[2])
		if options.has("pile"):
			await lay_pile(main, at + Vector3(2.4, 0.0, 0.0) + (options["pile"] as Vector3), int(options.get("pile_settle", PILE_FILLS)))
		var seen := {}
		for defs: Array[String] in ([ROW_ONE] if options.get("row_one_only", false) else [ROW_ONE, ROW_TWO]):
			var one: Array = []
			seen.merge(await _row(main, at, defs, one))
			shots.append(one[0])
		var cells := PackedStringArray()
		var headline := PackedStringArray()
		for who: String in seen:
			var m: Dictionary = seen[who]
			var margin: float = m.ground - m.body
			cells.append("%s %.3f/%.3f/%.3f/%.3f (ring with fronts %.3f)" % [who, m.ground, m.body, margin, m.contact, m.all])
			worst_margin = minf(worst_margin, margin)
			worst_of[who] = minf(worst_of.get(who, 9.0), margin)
			lowest[who] = minf(lowest.get(who, 9.0), m.body)
			highest[who] = maxf(highest.get(who, -9.0), m.body)
			if m.pixels < 100 and not head_only:
				problems.append("%s at %s shows only %d pixels" % [who, entry[0], m.pixels])
			if m.ring < 150 and not head_only:
				problems.append("%s at %s: only %d ground pixels in the ring" % [who, entry[0], m.ring])
			if (m.ground < GROUND_LOW or m.ground > GROUND_HIGH) and not head_only:
				problems.append("%s at %s: ground %.3f outside %.2f..%.2f" % [who, entry[0], m.ground, GROUND_LOW, GROUND_HIGH])
			if margin < LEAST_DARKER and not head_only:
				problems.append("%s at %s: darker than the ground by %.3f, under %.2f (body %.3f, ground %.3f)" % [who, entry[0], margin, LEAST_DARKER, m.body, m.ground])
			headline.append("%s head %.3f, %.0f%% of its ring within %.2f of it (%.0f%% of the ring a front), %d ring px" % [who, m.head, 100.0 * m.head_blend, HEAD_NEAR, 100.0 * m.head_front, m.head_ring])
			if strict_head and m.head_ring < HEAD_RING_LEAST:
				problems.append("%s at %s: the head's ring is only %d pixels (at least %d): the head is hidden or has no ring to read against" % [who, entry[0], m.head_ring, HEAD_RING_LEAST])
			elif m.head_ring >= HEAD_RING_LEAST and m.head_blend >= HEAD_BLEND_MOST:
				problems.append("%s at %s: %.0f%% of the head's ring is within %.2f of the head's tone (under %.0f%%)" % [who, entry[0], 100.0 * m.head_blend, HEAD_NEAR, 100.0 * HEAD_BLEND_MOST])
			if head_only:
				pass
			elif m.under < 40:
				problems.append("%s at %s: the strip under the feet shows only %d ground pixels (at least 40)" % [who, entry[0], m.under])
			elif m.contact < CONTACT_LEAST:
				problems.append("%s at %s: the contact shadow is %.3f, under %.2f" % [who, entry[0], m.contact, CONTACT_LEAST])
		lines.append("%s | %.1f %.1f | %s" % [entry[0], entry[1], entry[2], " | ".join(cells)])
		lines.append("HEAD %s | %s" % [entry[0], " | ".join(headline)])
		var shirt: Dictionary = seen["Abarax"].shirt
		shirts.append("%s: shirt %.3f, ground %.3f, differs by %.3f, outline darker along %.0f%% of %d edge pixels (%d shirt pixels)" % [entry[0], shirt.luma, seen["Abarax"].ground, shirt.diff, 100.0 * shirt.outline, shirt.edge, shirt.pixels])
		if head_only:
			pass
		elif shirt.pixels < 20:
			problems.append("Abarax's shirt at %s shows only %d pixels" % [entry[0], shirt.pixels])
		elif shirt.diff < SHIRT_LEAST and shirt.outline < OUTLINE_SHARE:
			problems.append("Abarax's shirt at %s: differs from the ground by %.3f (at least %.2f) and the outline is dark along only %.0f%% of its edge (%.0f%%)" % [entry[0], shirt.diff, SHIRT_LEAST, 100.0 * shirt.outline, 100.0 * OUTLINE_SHARE])
	for who: String in lowest:
		var spread: float = highest[who] - lowest[who]
		lines.append("%s's own luma varies by %.3f across the positions (%.3f to %.3f)" % [who, spread, lowest[who], highest[who]])
		if spread > MOST_SPREAD and not head_only:
			problems.append("%s's own luma varies by %.3f across the positions (at most %.2f)" % [who, spread, MOST_SPREAD])
	lines.append_array(shirts)
	var parts := PackedStringArray()
	for who: String in worst_of:
		parts.append("%s %.3f" % [who, worst_of[who]])
	lines.append("worst margin (ground less body) in the stretch: %.3f (%s)" % [worst_margin, ", ".join(parts)])
	_write(out_text, "\n".join(lines) + "\n")
	print("\n".join(lines))
	# The sheet: 4 columns of 480 x 270, one row's picture a cell (two for each position: the first row of bodies, then the second).
	var sheet := Image.create(4 * 480, ((positions.size() * 2 + 3) / 4) * 270, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var small := shots[i].duplicate() as Image
		small.convert(Image.FORMAT_RGB8)
		small.resize(480, 270, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, 480, 270), Vector2i((i % 4) * 480, (i / 4) * 270))
	sheet.save_png(ProjectSettings.globalize_path("res://").path_join(out_sheet))
	return problems




## The training yard at (0, 3), measured as the stretch is: {worst contrast, text}.
func yard() -> Dictionary:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := t.track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	main.arena().clear_foes()
	await t.frames(5)
	var shots: Array = []
	var seen := await _row(main, Vector3(0.0, 0.0, 3.0), ROW_ONE, shots)
	var worst := 9.0
	var parts := PackedStringArray()
	for who: String in seen:
		var m: Dictionary = seen[who]
		var contrast := absf(m.body - m.ground)
		worst = minf(worst, contrast)
		parts.append("%s: body %.3f, ground %.3f, contrast %.3f, head %.3f with %.0f%% of its ring within %.2f" % [who, m.body, m.ground, contrast, m.head, 100.0 * m.head_blend, HEAD_NEAR])
	return {worst = worst, text = "training yard at (0, 3): %s; worst contrast %.3f\n" % ["; ".join(parts), worst]}
