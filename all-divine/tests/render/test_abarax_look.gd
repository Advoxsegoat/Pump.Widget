extends TestCase
## Abarax as the game's camera draws him once his model follows the owner's drawing (xvfb, gl_compatibility): the
## bun stands above the head's outline in all eight facings; every Knuckle's picture is what it was before the portrait
## work; and the pictures a person looks at are saved to out/shots/abarax/ (the old ones, taken before, sit beside them
## as old_*.png; the side-by-sides and the close shots are written by test_the_pictures_for_the_owner).

const OUT := "res://out/shots/abarax/"
const FACINGS: Array[int] = [0, 45, 90, 135, 180, 225, 270, 315]
const KNUCKLES: Array[String] = ["knuckle_1", "knuckle_2", "knuckle_3", "knuckle_heavy", "knuckle_blade", "knuckle_drummer"]
## Each Knuckle's picture (the hash of its 640x360 pixels), one facing, idle, drawn with this file's own stage, as it was
## with the model before the portraits. The Knuckles have a model of their own: this says nothing of them has changed.
const KNUCKLE_HASHES := {
	"knuckle_1": 2549057810, "knuckle_2": 4145913693, "knuckle_3": 273983587,
	"knuckle_heavy": 1904001733, "knuckle_blade": 2347767655, "knuckle_drummer": 3278666292,
}
## A pixel is the body's when its colour differs from the empty stage's by more than this (summed over red, green, blue).
const BODY_THRESHOLD := 0.06
## The least the knot adds, at zoom 1 (behind: at zoom 3 nine times that, a pixel being a third as long: area; the others scale
## with the zoom): from the side behind the head, over the skull from ahead, over and beside it from behind.
const MIN_BEHIND := 3
const MIN_AHEAD := 2
const MIN_BESIDE := 2
const PARTS: PackedStringArray = ["Abarax_Topknot", "Abarax_Forelock", "Abarax_Feather", "Abarax_EarRing", "Abarax_Stubble"]

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
	var band := 8 * zoom  # the head's rows: a head is 6 pixels tall at zoom 1
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
			if yaw == 180:
				assert_true(found["above"] >= MIN_AHEAD * zoom, "x%d yaw 180: %d pixels above the outline (at least %d)" % [zoom, found["above"], MIN_AHEAD * zoom])
				assert_true(found["beside"] >= MIN_BESIDE * zoom, "x%d yaw 180: %d pixels beside it (at least %d)" % [zoom, found["beside"], MIN_BESIDE * zoom])
	print("look: what the knot adds, by zoom and facing:\n", "\n".join(report))


func test_every_knuckles_picture_is_what_it_was() -> void:
	var seen := {}
	for id in KNUCKLES:
		var def := load("res://data/actors/%s.tres" % id) as ActorDef
		var image := await shots.shot(def, 0)
		seen[id] = hash(image.get_data())
	assert_eq(seen, KNUCKLE_HASHES, "the six Knuckles' pictures")


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
	# The feather through a dash-step, every two frames, facing us, so that his left ear is on the right.
	var strip: Array[Image] = []
	shots.pose(def, 0)
	for f in range(0, 31, 2):
		for i in 2:
			shots.step(&"dash_step", f + i)
		strip.append(shots.head_crop(await shots.draw(3, -25.0), Vector2i(80, 60), 2))
	var sheet := Image.create(strip[0].get_width() * 8, strip[0].get_height() * 2, false, strip[0].get_format())
	for i in strip.size():
		sheet.blit_rect(strip[i], Rect2i(Vector2i.ZERO, strip[i].get_size()),
				Vector2i((i % 8) * strip[i].get_width(), (i / 8) * strip[i].get_height()))
	_save(sheet, "new_feather_dash_step.png")
	assert_eq(strip.size(), 16)
