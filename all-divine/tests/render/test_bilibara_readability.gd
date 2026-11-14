extends TestCase
## Bodies read on every ground (xvfb, gl_compatibility), the stretch a snow town at noon: its ground is pale and every body darker than it.
## In the stretch at 1920 x 1080, the picture a player sees (graded, fogged and outlined), at each of 14 reference positions three bodies
## stand in a row facing south: Abarax with a tier I Knuckle 2.4 m east and a tier III 2.4 m west, and then (Abarax hidden, the camera still
## on him) a Drummer with a heavy 2.4 m east and a blade Knuckle 2.4 m west: six bodies. For each body: the ground is the mean luma of a ring
## 3 to 8 pixels (of the 640 x 360 picture) outside its silhouette, off the other bodies; the body is the mean luma of its silhouette less the
## outermost pixel. The band: the ground 0.62 to 0.74, every body darker than its ground by 0.08 or more, each body's own luma within 0.08
## across the positions. Abarax's white shirt alone (his mean is held down by trousers, boots and hair) differs from the ground by 0.06 or
## more, or his outline carries it. A contact shadow plants a body: the ground in a strip under his feet is 0.06 darker with him there than
## without him (the same picture with every body gone: nothing else differs, in sun or in shade). Every number goes to out/shots/bilibara_readability.txt and the pictures to out/shots/bilibara_readability.png (a sheet) beside it.
## The training yard at its dark ground (0, 3) is measured the same way: the stretch is no worse than it.

const MAIN := "res://main/main.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_3 := "res://data/actors/knuckle_3.tres"
const HEAVY := "res://data/actors/knuckle_heavy.tres"
const BLADE := "res://data/actors/knuckle_blade.tres"
const DRUMMER := "res://data/actors/knuckle_drummer.tres"
const BODY_NAMES := {ABARAX: "Abarax", KNUCKLE_1: "tier I", KNUCKLE_3: "tier III", HEAVY: "heavy", BLADE: "blade", DRUMMER: "drummer"}
const SIZE := Vector2i(1920, 1080)
const OUT_TEXT := "out/shots/bilibara_readability.txt"
const OUT_SHEET := "out/shots/bilibara_readability.png"
## The ground a fighter stands on is pale (trodden snow, pale slate, snow-dusted earth): 0.62 to 0.74 in the final picture.
const GROUND_LOW := 0.62
const GROUND_HIGH := 0.74
## Every body is this much darker than its ground (Abarax is the palest, 0.56 or so: his ground is 0.64 or more).
const LEAST_DARKER := 0.08
const MOST_SPREAD := 0.08
## Abarax's shirt against the ground, or an outline at least this much darker along this share of the shirt's edge.
const SHIRT_LEAST := 0.06
const OUTLINE_DARKER := 0.25
const OUTLINE_SHARE := 0.9
## The ground in the strip under a body's feet is at least this much darker with the body there than without it.
const CONTACT_LEAST := 0.06
const ROW_ONE: Array[String] = [ABARAX, KNUCKLE_1, KNUCKLE_3]
const ROW_TWO: Array[String] = [DRUMMER, HEAVY, BLADE]
## The reference positions (x, z): the plan's twelve and two more in the yard (the stone square's border and a margin).
const POSITIONS := [
	["court A (slate, ShrineLampA's pool)", -35.0, 0.0], ["street (cobble, open)", 0.0, 0.0], ["street lamp pool", -5.0, -3.0],
	["street kerb", 0.0, 4.5], ["lane (earth)", 27.5, -30.0], ["alcove B (slate, pool)", 35.0, -34.0],
	["Rack Walk", -10.0, -22.5], ["loop lane", -32.5, -12.0], ["yard (square centre)", 27.5, -65.0],
	["yard under the north wall", 27.5, -73.0], ["yard by the kerb", 20.0, -56.5], ["lane's mouth", 27.5, -10.0],
	["yard square's border", 27.5, -69.5], ["yard west margin", 21.0, -58.0],
]
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


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


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
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		actor_shown[node] = (node as Node3D).visible
		(node as Node3D).visible = false
	var shadows := region.get_node_or_null(^"ContactShadows") as Node3D
	var shadows_were := shadows.visible if shadows != null else false
	if shadows != null:
		shadows.visible = false
	# Everything but the Walkable plates drawn flat green (so that a kerb or a front hides the ground behind it as it does in the picture), the
	# plates flat magenta.
	var walkable := region.get_node("Walkable")
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
		mesh.material_override = magenta if walkable.is_ancestor_of(mesh) else green
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
func _measure(main: Main, shot: Image, empty: Image, actor: Actor, bodies: Array[Actor]) -> Dictionary:
	var feet := Vector2i(main.camera_rig.camera.unproject_position(actor.global_position).round()) + Vector2i(PixelSnap.MARGIN, PixelSnap.MARGIN)
	var box := Rect2i(feet.x - 62, feet.y - 80, 124, 100).intersection(Rect2i(Vector2i.ZERO, main.stage.world.size))
	var mine := await ShotMasks.silhouette(main, actor, box)
	var others := {}
	for other in bodies:
		if other != actor:
			for p: Vector2i in await ShotMasks.silhouette(main, other, box):
				others[p] = true
	var floor := await _ground_mask(main, box)
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
	return {body = body_sum / maxf(inner.size(), 1.0), ground = ground_sum / maxf(ground_count, 1.0), all = all_sum / maxf(all_count, 1.0), pixels = inner.size(), ring = ground_count, contact = contact, under = under_count}


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
	await frames(20)
	for actor in bodies + [abarax]:
		(actor as Actor).freeze(100000000)
	main.camera_rig.snap_now()
	for i in 4:
		await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
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
	var empty := get_viewport().get_texture().get_image()
	for actor: Actor in was_visible:
		actor.visible = was_visible[actor]
	for i in 3:
		await RenderingServer.frame_post_draw
	var result := {}
	for i in 3:
		result[names[i]] = await _measure(main, shot, empty, bodies[i], bodies)
	if defs[0] == ABARAX:
		result["Abarax"]["shirt"] = await _measure_shirt(main, shot, abarax, result["Abarax"].ground)
	for actor in bodies:
		if actor != abarax:
			actor.queue_free()
	abarax.visible = true
	await frames(2)
	return result


func _write(path: String, text: String) -> void:
	var full := ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var file := FileAccess.open(full, FileAccess.WRITE)
	file.store_string(text)


func test_a_body_reads_on_every_ground_in_every_light() -> void:   # Review Focus 3
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	await frames(5)
	var lines := PackedStringArray(["position | x z | per body: ground / body luma / ground less body / contact shadow (the strip under the feet without the body less with it)"])
	var problems := PackedStringArray()
	var lowest := {}
	var highest := {}
	var worst_margin := 9.0
	var worst_of := {}
	var shirts := PackedStringArray()
	var shots: Array[Image] = []
	for entry: Array in POSITIONS:
		if OS.get_environment("BILIBARA_ONE") != "" and entry[0] != POSITIONS[int(OS.get_environment("BILIBARA_ONE"))][0]:
			continue
		var at := Vector3(entry[1], 0.0, entry[2])
		var seen := {}
		for defs: Array[String] in [ROW_ONE, ROW_TWO]:
			var one: Array = []
			seen.merge(await _row(main, at, defs, one))
			shots.append(one[0])
		var cells := PackedStringArray()
		for who: String in seen:
			var m: Dictionary = seen[who]
			var margin: float = m.ground - m.body
			cells.append("%s %.3f/%.3f/%.3f/%.3f (ring with fronts %.3f)" % [who, m.ground, m.body, margin, m.contact, m.all])
			worst_margin = minf(worst_margin, margin)
			worst_of[who] = minf(worst_of.get(who, 9.0), margin)
			lowest[who] = minf(lowest.get(who, 9.0), m.body)
			highest[who] = maxf(highest.get(who, -9.0), m.body)
			if m.pixels < 100:
				problems.append("%s at %s shows only %d pixels" % [who, entry[0], m.pixels])
			if m.ring < 150:
				problems.append("%s at %s: only %d ground pixels in the ring" % [who, entry[0], m.ring])
			if m.ground < GROUND_LOW or m.ground > GROUND_HIGH:
				problems.append("%s at %s: ground %.3f outside %.2f..%.2f" % [who, entry[0], m.ground, GROUND_LOW, GROUND_HIGH])
			if margin < LEAST_DARKER:
				problems.append("%s at %s: darker than the ground by %.3f, under %.2f (body %.3f, ground %.3f)" % [who, entry[0], margin, LEAST_DARKER, m.body, m.ground])
			if m.under < 40:
				problems.append("%s at %s: the strip under the feet shows only %d ground pixels (at least 40)" % [who, entry[0], m.under])
			elif m.contact < CONTACT_LEAST:
				problems.append("%s at %s: the contact shadow is %.3f, under %.2f" % [who, entry[0], m.contact, CONTACT_LEAST])
		lines.append("%s | %.1f %.1f | %s" % [entry[0], entry[1], entry[2], " | ".join(cells)])
		var shirt: Dictionary = seen["Abarax"].shirt
		shirts.append("%s: shirt %.3f, ground %.3f, differs by %.3f, outline darker along %.0f%% of %d edge pixels (%d shirt pixels)" % [entry[0], shirt.luma, seen["Abarax"].ground, shirt.diff, 100.0 * shirt.outline, shirt.edge, shirt.pixels])
		if shirt.pixels < 20:
			problems.append("Abarax's shirt at %s shows only %d pixels" % [entry[0], shirt.pixels])
		elif shirt.diff < SHIRT_LEAST and shirt.outline < OUTLINE_SHARE:
			problems.append("Abarax's shirt at %s: differs from the ground by %.3f (at least %.2f) and the outline is dark along only %.0f%% of its edge (%.0f%%)" % [entry[0], shirt.diff, SHIRT_LEAST, 100.0 * shirt.outline, 100.0 * OUTLINE_SHARE])
	for who: String in lowest:
		var spread: float = highest[who] - lowest[who]
		lines.append("%s's own luma varies by %.3f across the positions (%.3f to %.3f)" % [who, spread, lowest[who], highest[who]])
		if spread > MOST_SPREAD:
			problems.append("%s's own luma varies by %.3f across the positions (at most %.2f)" % [who, spread, MOST_SPREAD])
	lines.append_array(shirts)
	var parts := PackedStringArray()
	for who: String in worst_of:
		parts.append("%s %.3f" % [who, worst_of[who]])
	lines.append("worst margin (ground less body) in the stretch: %.3f (%s)" % [worst_margin, ", ".join(parts)])
	_write(OUT_TEXT, "\n".join(lines) + "\n")
	print("\n".join(lines))
	# The sheet: 4 columns of 480 x 270, one row's picture a cell (two for each position: the first row of bodies, then the second).
	var sheet := Image.create(4 * 480, 7 * 270, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var small := shots[i].duplicate() as Image
		small.convert(Image.FORMAT_RGB8)
		small.resize(480, 270, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, 480, 270), Vector2i((i % 4) * 480, (i / 4) * 270))
	sheet.save_png(ProjectSettings.globalize_path("res://").path_join(OUT_SHEET))
	assert_eq(problems.slice(0, 12), PackedStringArray(), "every body reads on every ground (%d problems; the table is %s)" % [problems.size(), OUT_TEXT])


func test_the_yard_is_the_floor() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	main.arena().clear_foes()
	await frames(5)
	var shots: Array = []
	var seen := await _row(main, Vector3(0.0, 0.0, 3.0), ROW_ONE, shots)
	var worst := 9.0
	var parts := PackedStringArray()
	for who: String in seen:
		var m: Dictionary = seen[who]
		var contrast := absf(m.body - m.ground)
		worst = minf(worst, contrast)
		parts.append("%s: body %.3f, ground %.3f, contrast %.3f" % [who, m.body, m.ground, contrast])
	var text := "training yard at (0, 3): %s; worst contrast %.3f\n" % ["; ".join(parts), worst]
	print(text)
	var full := ProjectSettings.globalize_path("res://").path_join(OUT_TEXT)
	var previous := FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""
	_write(OUT_TEXT, previous + text)
	# The stretch is no worse than the yard: every body of the six is darker than its ground by at least min(0.08, the yard's worst contrast);
	# the worst margin is read from the file the other test wrote.
	var stretch := -9.0
	var found := false
	for line in previous.split("\n"):
		if line.begins_with("worst margin (ground less body) in the stretch: "):
			stretch = line.get_slice(": ", 1).get_slice(" ", 0).to_float()
			found = true
	assert_true(found, "the stretch's table is in the file (run the whole file)")
	assert_true(stretch >= minf(LEAST_DARKER, worst), "the stretch's worst margin (%.3f) is at least min(%.2f, the yard's worst contrast %.3f)" % [stretch, LEAST_DARKER, worst])
