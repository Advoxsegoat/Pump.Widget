extends TestCase
## Abarax as the game's camera draws him once his model follows the owner's drawing (xvfb, gl_compatibility): the knot at the
## back of the head shows behind it from the sides and over it from ahead, the feather shows from every facing, and the pictures a
## person looks at are saved to out/shots/abarax/ (the old ones, taken before the portrait work, sit beside them as old_*.png and
## round one's in r1/). The Knuckles are guarded by their model file's hash (test_abarax_portrait.gd) and the byte-identical rebuild in
## test_build_knuckle.py, not by pictures: a picture's pixels depend on the renderer.

const OUT := "res://out/shots/abarax/"
const FACINGS: Array[int] = [0, 45, 90, 135, 180, 225, 270, 315]
## A pixel is the body's when its colour differs from the empty stage's by more than this (summed over red, green, blue).
const BODY_THRESHOLD := 0.06
## The least the knot adds, at zoom 1 (behind: at zoom 3 nine times that, a pixel being a third as long: area; the others scale
## with the zoom): from the side behind the head and over the skull from ahead.
const MIN_BEHIND := 2
const MIN_AHEAD := 2
const PARTS: PackedStringArray = ["Abarax_Topknot", "Abarax_Forelock", "Abarax_Feather", "Abarax_EarRing"]

var shots: AbaraxShots


func before_each() -> void:
	shots = AbaraxShots.new()
	await shots.open(self)


func after_each() -> void:
	shots.close()


func _mask(image: Image, empty: Image) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y)
			var b := empty.get_pixel(x, y)
			mask[y * image.get_width() + x] = 1 if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > BODY_THRESHOLD else 0
	return mask


# The pixels of the body's silhouette in `image` against the empty stage.
func _silhouette(image: Image, empty: Image) -> PackedByteArray:
	return _mask(image, empty)


func _top_row(mask: PackedByteArray) -> int:
	for i in mask.size():
		if mask[i] == 1:
			return i / 640
	return -1


## What the new parts add to the bare head's outline in one facing at one zoom: `above` (pixels over the old outline's top
## row), `behind` (pixels past the old outline's behind side, in the head's rows; the two side facings only: yaw 90 faces
## screen right and so has its back to the left) and `beside` (past either side, for the view from behind). `bare` has the
## parts hidden, `empty` is the stage without him.
func _added(def: ActorDef, bare: ActorDef, yaw: int, zoom: int, empty: Image) -> Dictionary:
	shots.pose(bare, yaw)
	var old := _mask(await shots.draw(zoom, -40.0), empty)
	shots.pose(def, yaw)
	var now := _mask(await shots.draw(zoom, -40.0), empty)
	var top := _top_row(old)
	var band := 4 * zoom  # the top of the head: its first rows (a head is 6 pixels tall at zoom 1)
	var lo := 640
	var hi := -1
	for y in range(top, top + band):
		for x in 640:
			if old[y * 640 + x] == 1:
				lo = mini(lo, x)
				hi = maxi(hi, x)
	var found := {"above": 0, "behind": 0, "beside": 0}
	for y in range(maxi(top - 12 * zoom, 0), top + band):
		for x in 640:
			if now[y * 640 + x] == 1 and old[y * 640 + x] == 0:
				if y < top:
					found["above"] += 1
				if x < lo:
					found["behind" if yaw == 90 else "beside"] += 1
				elif x > hi:
					found["behind" if yaw == 270 else "beside"] += 1
	return found


func test_the_bun_shows_behind_the_head_from_the_side_and_over_it_from_ahead() -> void:
	var def := load("res://data/actors/abarax.tres") as ActorDef
	var bare := def.duplicate() as ActorDef
	bare.hidden_parts = PARTS
	shots.pose(def, 0)
	shots.rig.visible = false
	var empty := {1: await shots.draw(1), 3: await shots.draw(3, -40.0)}
	var report := PackedStringArray()
	for zoom in [1, 3]:
		for yaw in FACINGS:
			var found := await _added(def, bare, yaw, zoom, empty[zoom])
			report.append("x%d yaw %d: %s" % [zoom, yaw, found])
			if yaw == 90 or yaw == 270:
				assert_true(found["behind"] >= MIN_BEHIND * zoom * zoom, "x%d yaw %d: the knot adds %d pixels behind the head's outline (at least %d)" % [zoom, yaw, found["behind"], MIN_BEHIND * zoom * zoom])
			if yaw == 0:
				assert_true(found["above"] >= MIN_AHEAD * zoom, "x%d yaw 0: the top of the knot adds %d pixels over the skull (at least %d)" % [zoom, found["above"], MIN_AHEAD * zoom])
			# From behind the knot is seen against the hair of the head it stands on, so it adds nothing to the outline there
			# (7 pixels over it at zoom 3 and none beside); it shows as a lump of shading, which the pictures are for.
	print("look: what the knot adds, by zoom and facing:\n", "\n".join(report))


## What the feather (link, ring, beads and blade) changes in the picture at the game's camera (a pixel counts when it differs from the
## one without the feather), idle. The brief's floors (6 pixels long from the front and behind, 3 from each side) are withdrawn: a 12 cm
## feather is a few pixels at 32 pixels to the metre, and a side view looks along it. What it comes to, by facing (yaw 0, 45, ... 315):
## 1, 0, 0, 1, 3, 2, 1, 2 pixels. Held: it shows from behind (3 pixels, 3 long), from at least five of the eight facings, and 8 pixels in all;
## the zoomed pictures (out/shots/abarax/) are where it is looked at.
func test_the_feather_shows_from_every_facing_at_the_games_camera() -> void:
	var def := load("res://data/actors/abarax.tres") as ActorDef
	var without := def.duplicate() as ActorDef
	without.hidden_parts = PackedStringArray(["Abarax_Feather"])
	var report := PackedStringArray()
	var total := 0
	var seen := 0
	for yaw in FACINGS:
		shots.pose(without, yaw)
		var a := await shots.draw(1)
		shots.pose(def, yaw)
		var b := await shots.draw(1)
		var count := 0
		var low := Vector2i(640, 360)
		var high := Vector2i(-1, -1)
		for y in 360:
			for x in 640:
				var p := a.get_pixel(x, y)
				var q := b.get_pixel(x, y)
				if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > BODY_THRESHOLD:
					count += 1
					low = Vector2i(mini(low.x, x), mini(low.y, y))
					high = Vector2i(maxi(high.x, x), maxi(high.y, y))
		var longest := maxi(high.x - low.x, high.y - low.y) + 1 if count > 0 else 0
		report.append("yaw %d: %d px, %d long" % [yaw, count, longest])
		total += count
		seen += 1 if count > 0 else 0
		if yaw == 180:
			assert_true(longest >= 3, "yaw %d: the feather is %d pixels long (at least 3)" % [yaw, longest])
	assert_true(seen >= 5, "the feather shows from %d of the eight facings (at least 5)" % seen)
	assert_true(total >= 8, "the feather changes %d pixels over the eight facings (at least 8)" % total)
	print("look: the feather by facing (pixels changed by it): ", "; ".join(report))


# --- the pictures a person looks at (out/shots/abarax/) ---

func _save(image: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT).path_join(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(image.save_png(path), OK, "saved %s" % name)


# The old picture of `name` (taken before the portrait work, with the old model) beside `new_full`, both cut round the head
# and enlarged, the old on the left: pair_<name>.png.
func _side_by_side(name: String, new_full: Image, size: Vector2i, scale: int) -> void:
	var path := ProjectSettings.globalize_path(OUT).path_join("old_%s.png" % name)
	if not FileAccess.file_exists(path):
		return
	var old := shots.head_crop(Image.load_from_file(path), size, scale)
	var new := shots.head_crop(new_full, size, scale)
	var pair := Image.create(new.get_width() * 2 + 8, new.get_height(), false, new.get_format())
	pair.fill(Color(0.1, 0.1, 0.1))
	pair.blit_rect(old, Rect2i(Vector2i.ZERO, old.get_size()), Vector2i.ZERO)
	pair.blit_rect(new, Rect2i(Vector2i.ZERO, new.get_size()), Vector2i(new.get_width() + 8, 0))
	_save(pair, "pair_%s.png" % name)


func test_the_pictures_for_the_owner() -> void:
	var def := load("res://data/actors/abarax.tres") as ActorDef
	# The game's camera, eight facings, idle and mid-jab: the 640x360 picture itself, and the head enlarged five times
	# (the old head, taken the same way, is old_head_*.png: see the side-by-sides pair_*.png).
	for yaw in FACINGS:
		for kind in ["idle", "jab"]:
			shots.pose(def, yaw, &"palm_jab" if kind == "jab" else &"", 12 if kind == "jab" else 0)
			var image := await shots.draw(1)
			_save(image, "new_z1_%s_%03d.png" % [kind, yaw])
			_side_by_side("z1_%s_%03d" % [kind, yaw], image, Vector2i(48, 36), 6)
	# The close shots (zoom 3 at the Director's close pitch), four ways round.
	for yaw in [0, -90, 90, 180]:
		shots.pose(def, yaw)
		var close := await shots.draw(3, -25.0)
		_save(close, "new_z3_idle_%d.png" % yaw)
		_side_by_side("z3_idle_%d" % yaw, close, Vector2i(100, 75), 4)
	# The face as close as the cine layer goes (zoom 4, the insert's pitch), for the stubble and the mole.
	shots.pose(def, 0)
	var face := await shots.draw(4, -25.0)
	_save(shots.head_crop(face, Vector2i(80, 60), 6, 0.0), "new_face_z4.png")
	# The feather through a dash-step and through the guard, every two frames, facing us, so that his left ear is on the right.
	for clip in [&"dash_step", &"guard_hold"]:
		var strip: Array[Image] = []
		shots.pose(def, 0)
		for f in range(0, 31, 2):
			for i in 2:
				shots.step(clip, f + i)
			strip.append(shots.head_crop(await shots.draw(3, -25.0), Vector2i(80, 60), 2))
		var sheet := Image.create(strip[0].get_width() * 8, strip[0].get_height() * 2, false, strip[0].get_format())
		for i in strip.size():
			sheet.blit_rect(strip[i], Rect2i(Vector2i.ZERO, strip[i].get_size()),
					Vector2i((i % 8) * strip[i].get_width(), (i / 8) * strip[i].get_height()))
		_save(sheet, "new_feather_%s.png" % clip)
		assert_eq(strip.size(), 16)
