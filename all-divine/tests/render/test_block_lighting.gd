extends TestCase
## A long block beside a street's lanterns is lit along its whole length (xvfb, gl_compatibility). This renderer lights a mesh
## as a whole with at most eight omni lights, so a 60 m run beside fifteen lanterns is lit by the first eight and dark
## beyond them; the builder splits a block's runs to at most 12.5 m (tools/world/region_blocks.gd) so that each stretch
## is reached by the lamps beside it. Drawn from the game's camera (orthographic, pitched -40 degrees) in a viewport of the
## picture's size; the luma of the wall's face a little west of each lantern, above it (past the top of its post, which would hide the wall behind it) is compared along the block.
## Also the cost of that place: the draw calls of its worst view.

const BUILDER := preload("res://tools/world/build_region.gd")
const ORTHO_SIZE := 362.0 / 32.0
const PITCH := -40.0
const DISTANCE := 20.0
## How far the face's luma beside a lantern may be from the median of them all, as a share of it.
const EVEN := 0.15
## The most draw calls the place may take at its worst view, measured on this layout (the cost layout of Task 2's addendum).
const MOST_DRAWS := 220


# A 60 m street front of three plain storeys on z -5..0, a lantern every 4 m before it (15 of them, world lamps), the
# ground before it and a few vats.
func _layout() -> String:
	var text := "sky #000000\nambient #303844 0.3\nkit bilibara\nground -5 0 7.5 10 cobble\n"
	for i in 5:
		text += "ground %s 0 %s 10 cobble\nground %s 10 %s 20 cobble\n" % [7.5 + i * 12.5, 20.0 + i * 12.5, 7.5 + i * 12.5, 20.0 + i * 12.5]
	text += "block 0 -5 60 0 3 plain flat solid\nblock 0 -25 60 -10 2 tannery slope\nblock -10 -5 0 25 3 plain flat solid\nblock 60 -5 70 25 3 plain flat solid\n"
	text += "lamps #ffc468 6 3.0 3.45 world\n"
	for i in 15:
		text += "lantern %s 1.5\n" % (2.0 + i * 4.0)
	text += "vat 20 8\nvat 40 8\n"
	return text


func _view(world_root: Node3D, target: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHO_SIZE
	camera.rotation_degrees = Vector3(PITCH, 0, 0)
	camera.position = target + Vector3(0, DISTANCE * 0.6428, DISTANCE * 0.766)
	camera.current = true
	world_root.add_child(camera)
	return camera


func test_a_long_block_is_lit_along_its_whole_length_and_the_place_is_cheap_to_draw() -> void:
	var builder := BUILDER.Builder.new()
	builder.layout = "T.txt"
	var region := builder.build(_layout(), "T")
	assert_eq(builder.problems, PackedStringArray())
	var view := track(SubViewport.new()) as SubViewport
	view.size = Vector2i(640, 360)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(region)
	var lumas := {}
	var worst_draws := 0
	for target_x: float in [10.0, 30.0, 50.0]:
		var camera := _view(region, Vector3(target_x, 0, 0))
		await frames(3)
		for i in 3:
			await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		var draws := RenderingServer.viewport_get_render_info(view.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		worst_draws = maxi(worst_draws, draws)
		for i in 15:
			var lamp_x := 2.0 + i * 4.0
			if absf(lamp_x - target_x) > 8.0:
				continue
			var at := camera.unproject_position(Vector3(lamp_x - 0.6, 5.5, 0.0))
			var total := 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var c := image.get_pixel(clampi(int(at.x) + dx, 0, 639), clampi(int(at.y) + dy, 0, 359))
					total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lumas[i] = total / 25.0
		camera.queue_free()
		await frames(1)
	assert_eq(lumas.size(), 15, "every lantern was measured")
	# The wall's own tones repeat every 10 m (a tile is 2.5 m and a lantern stands every 4 m), so the lanterns come in five
	# kinds, a lantern's every fifth the same; each is compared with the others of its kind, three along the block.
	for phase in 5:
		var kind: Array = []
		for i in range(phase, 15, 5):
			kind.append(lumas[i])
		kind.sort()
		var median: float = kind[1]
		assert_true(median > 0.05, "the face is lit (kind %d: median luma %.3f)" % [phase + 1, median])
		for i in range(phase, 15, 5):
			assert_true(absf(lumas[i] - median) <= EVEN * median, "lantern %d (x %.0f): the face's luma %.3f is within 15%% of its kind's median %.3f" % [i + 1, 2.0 + i * 4.0, lumas[i], median])
	print("block lighting: lumas ", lumas.values().map(func(v: float) -> String: return "%.3f" % v), "; worst view %d draw calls" % worst_draws)
	assert_true(worst_draws > 0 and worst_draws <= MOST_DRAWS, "the worst view takes %d draw calls (at most %d)" % [worst_draws, MOST_DRAWS])
