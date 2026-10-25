extends TestCase
## Contact sheets (tools/sheets/contact_sheet.gd) on a real display (xvfb, gl_compatibility): a cell
## per frame, six to a row, each cell 160x120 internal pixels drawn x2.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const LIB := "res://assets/anim/abarax/library.tres"
const CELL := Vector2i(320, 240)


func test_sheet_has_a_cell_per_frame_and_content() -> void:
	var img: Image = await ContactSheet.render(load(RIG), ["idle", "palm_jab"])
	assert_ne(img, null, "the sheet rendered")
	if img == null:
		return
	# Six cells for idle, plus one per unique palm_jab mark frame (or six when it has no marks yet). Width is 6 x 320.
	var jab := (load(LIB) as AnimationLibrary).get_animation(&"palm_jab")
	var jab_cells := _mark_frames(jab).size()
	if jab_cells == 0:
		jab_cells = 6
	var cells := 6 + jab_cells
	assert_eq(img.get_width(), 6 * CELL.x)
	assert_eq(img.get_height(), ceili(cells / 6.0) * CELL.y)
	# Each cell has more than 4 distinct colours.
	var looks := []
	for i in cells:
		var at := Vector2i(i % 6, i / 6) * CELL
		var colours := {}
		# Every internal pixel is a 2x2 block, so its top-left output pixel stands for it.
		for y in range(0, CELL.y, 2):
			for x in range(0, CELL.x, 2):
				colours[img.get_pixelv(at + Vector2i(x, y)).to_rgba32()] = true
		assert_true(colours.size() > 4, "cell %d has %d colours" % [i, colours.size()])
		looks.append(img.get_region(Rect2i(at, CELL)).get_data())
	var jab_poses := {}
	for i in range(6, cells):
		jab_poses[looks[i]] = true
	assert_true(jab_poses.size() > 1, "the palm_jab cells show different poses")


func test_cells_are_mark_frames_or_six_even_frames() -> void:
	var plain := Animation.new()
	plain.length = 0.5
	assert_eq(ContactSheet.cell_frames(plain), PackedInt32Array([0, 6, 12, 18, 24, 30]), "a one-shot: from the first frame to the last")
	plain.loop_mode = Animation.LOOP_LINEAR
	plain.length = 1.0
	assert_eq(ContactSheet.cell_frames(plain), PackedInt32Array([0, 10, 20, 30, 40, 50]), "a loop: its last frame is its first")
	var marked := Animation.new()
	marked.length = 0.5
	var t := marked.add_track(Animation.TYPE_METHOD)
	marked.track_set_path(t, NodePath("Marks"))
	for f in [10, 5, 10, 15]:
		marked.track_insert_key(t, f / 60.0, {"method": &"sfx", "args": [{}]})
	assert_eq(ContactSheet.cell_frames(marked), PackedInt32Array([5, 10, 15]), "one cell per mark frame, in order")


func test_label_names_clip_and_frame() -> void:
	assert_eq(ContactSheet.cell_label(&"palm_jab", 10), "palm_jab f10")


# The frames (at 60 Hz) of the keys on the clip's Marks method track, each once, in order.
func _mark_frames(anim: Animation) -> PackedInt32Array:
	var found := {}
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_METHOD and anim.track_get_path(t) == NodePath("Marks"):
			for k in anim.track_get_key_count(t):
				found[roundi(anim.track_get_key_time(t, k) * 60.0)] = true
	var frames := PackedInt32Array(found.keys())
	frames.sort()
	return frames
