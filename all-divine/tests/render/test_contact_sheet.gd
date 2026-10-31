extends TestCase
## Contact sheets (tools/sheets/contact_sheet.gd) on a real display (xvfb, gl_compatibility): a cell
## per frame, six to a row, each cell 160x120 internal pixels drawn x2.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const DEF := "res://data/actors/abarax.tres"
const LIB := "res://assets/anim/abarax/library.tres"
const CELL := Vector2i(320, 240)
## The top of a cell, where its label is drawn. Everything below it is the picture of the actor.
const LABEL_BAND := 40
## A pixel is part of the actor (or its shadow) when a channel is this far from the ground's colour.
## The empty ground varies by about 1/255 across a cell; the actor and its shadow differ by far more.
const BACKGROUND_TOLERANCE := 0.03
## Fewest game pixels of actor and shadow a cell must show. Abarax and his shadow cover 500 to 1,000 of
## the 160x100 below the label in every clip, so this is far above a stray pixel and far below a figure.
const MIN_DRAWN := 200


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
	# Below the label, each cell shows the actor: a good number of pixels that are not the ground, in more
	# than 4 distinct colours, around the middle of the cell (the crop is centred on him).
	var looks := []
	for i in cells:
		var region := img.get_region(Rect2i(Vector2i(i % 6, i / 6) * CELL + Vector2i(0, LABEL_BAND), CELL - Vector2i(0, LABEL_BAND)))
		var drawn := _drawn(region)
		assert_true(drawn["count"] >= MIN_DRAWN, "cell %d shows %d pixels of actor" % [i, drawn["count"]])
		assert_true(drawn["colours"] > 4, "cell %d: the actor has %d colours" % [i, drawn["colours"]])
		var middle := CELL / 2 - Vector2i(0, LABEL_BAND)  # The centre of the cell, where the region starts.
		assert_true((drawn["box"] as Rect2i).grow(1).has_point(middle), "cell %d: the actor (%s) is around the middle %s" % [i, drawn["box"], middle])
		looks.append(region.get_data())
	var jab_poses := {}
	for i in range(6, cells):
		jab_poses[looks[i]] = true
	assert_true(jab_poses.size() > 1, "the palm_jab cells show different poses")


# Given an actor's def, the sheet draws the actor in the def's own palette: under its white sun every pixel
# of him is one of the palette's tones, so a good number of game pixels below the label are. Abarax shows
# his cream shirt (main), blue (sec) and rose scarf; with slot 7 dyed green in his def, the green shows and
# the rose is gone, so the palette comes from the def and from nothing else.
func test_a_def_draws_the_actor_in_its_palette() -> void:
	var def := load(DEF) as ActorDef
	var dyed := def.duplicate() as ActorDef
	dyed.palette = def.palette.with_dye(7, Color("#40c040"))
	var plain_img: Image = await ContactSheet.render(def, ["idle"])
	var dyed_img: Image = await ContactSheet.render(dyed, ["idle"])
	assert_ne(plain_img, null, "the sheet rendered")
	assert_ne(dyed_img, null, "the dyed sheet rendered")
	if plain_img == null or dyed_img == null:
		return
	var plain := _palette_pixels(plain_img, def.palette)
	assert_true(plain["count"] >= MIN_DRAWN / 2, "%d game pixels of the first cell are his tones" % plain["count"])
	for slot in [3, 4, 7]:
		assert_true((plain["slots"] as Dictionary).has(slot), "slot %d (%s) shows" % [slot, def.palette.slot_names[slot]])
	var with_dye := _palette_pixels(dyed_img, dyed.palette)
	assert_true(with_dye["count"] >= MIN_DRAWN / 2, "%d game pixels of the dyed cell are its tones" % with_dye["count"])
	assert_true((with_dye["slots"] as Dictionary).has(7), "the green dye of slot 7 shows")
	assert_false((_palette_pixels(dyed_img, def.palette, [7])["slots"] as Dictionary).has(7), "no rose is left")


# A bare rig scene, with no def, keeps the materials its model was imported with, as an actor without a
# palette does in the game: it is not drawn in Abarax's palette (or any other).
func test_a_bare_rig_keeps_its_own_materials() -> void:
	var def := load(DEF) as ActorDef
	var dressed: Image = await ContactSheet.render(def, ["idle"])
	var bare: Image = await ContactSheet.render(load(RIG), ["idle"])
	assert_ne(bare, null, "the sheet rendered")
	if dressed == null or bare == null:
		return
	assert_false(bare.get_data() == dressed.get_data(), "the bare rig's sheet is not the dressed one")
	var found := _palette_pixels(bare, def.palette)
	var rose := _palette_pixels(bare, def.palette, [7])
	assert_true(found["count"] * 4 < _palette_pixels(dressed, def.palette)["count"], "only %d game pixels happen to match his tones" % found["count"])
	assert_false((rose["slots"] as Dictionary).has(7), "no rose scarf")


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


# What of `region` is not the ground: {count, colours, box} of the pixels whose colour is more than
# BACKGROUND_TOLERANCE from the region's most common colour (the ground). Every game pixel is a 2x2 block
# on the sheet, so only the top-left pixel of each block is looked at, and count is in game pixels.
func _drawn(region: Image) -> Dictionary:
	var seen := {}
	for y in range(0, region.get_height(), 2):
		for x in range(0, region.get_width(), 2):
			var c := region.get_pixel(x, y)
			seen[c] = seen.get(c, 0) + 1
	var ground := Color()
	var most := 0
	for c: Color in seen:
		if seen[c] > most:
			most = seen[c]
			ground = c
	var count := 0
	var colours := {}
	var box := Rect2i()
	for c: Color in seen:
		if maxf(maxf(absf(c.r - ground.r), absf(c.g - ground.g)), absf(c.b - ground.b)) > BACKGROUND_TOLERANCE:
			count += seen[c]
			colours[c] = true
	for y in range(0, region.get_height(), 2):
		for x in range(0, region.get_width(), 2):
			var c := region.get_pixel(x, y)
			if colours.has(c):
				box = Rect2i(x, y, 1, 1) if box.size == Vector2i.ZERO else box.expand(Vector2i(x, y))
	return {"count": count, "colours": colours.size(), "box": box}


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


# How much of the first cell, below its label, is drawn in `palette`'s tones of `slots` (default 0-8):
# {count: game pixels within 2/255 of one of them, slots: the slots seen}. Every game pixel is a 2x2 block
# on the sheet, so only the top-left pixel of each block is looked at.
func _palette_pixels(sheet: Image, palette: Palette, slots: Array = range(9)) -> Dictionary:
	var seen := {}
	var count := 0
	for y in range(LABEL_BAND, CELL.y, 2):
		for x in range(0, CELL.x, 2):
			var c := sheet.get_pixel(x, y)
			for slot: int in slots:
				var hit := false
				for t in Palette.TONES:
					var tone := palette.tone(slot, t)
					if maxf(maxf(absf(c.r - tone.r), absf(c.g - tone.g)), absf(c.b - tone.b)) <= 2.0 / 255.0:
						hit = true
						break
				if hit:
					count += 1
					seen[slot] = true
					break
	return {"count": count, "slots": seen}
