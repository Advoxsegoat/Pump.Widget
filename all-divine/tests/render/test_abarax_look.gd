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


func test_the_bun_stands_above_the_old_outline_in_all_eight_facings() -> void:
	var def := load("res://data/actors/abarax.tres") as ActorDef
	var bare := def.duplicate() as ActorDef
	bare.hidden_parts = PARTS
	shots.pose(def, 0)
	shots.rig.visible = false
	var empty := await shots.draw(1)
	var report := PackedStringArray()
	for yaw in FACINGS:
		shots.pose(bare, yaw)
		var old := _mask(await shots.draw(1), empty)
		shots.pose(def, yaw)
		var now := _mask(await shots.draw(1), empty)
		var top := _top_row(old)
		var above := 0
		for i in now.size():
			if now[i] == 1 and i / 640 < top:
				above += 1
		report.append("%d: %d" % [yaw, above])
		assert_true(above >= 6, "facing %d: the bun adds %d pixels above the head's outline (at least 6)" % [yaw, above])
	print("look: bun pixels above the outline by facing: ", ", ".join(report))


func test_every_knuckles_picture_is_what_it_was() -> void:
	var seen := {}
	for id in KNUCKLES:
		var def := load("res://data/actors/%s.tres" % id) as ActorDef
		var image := await shots.shot(def, 0)
		seen[id] = hash(image.get_data())
	assert_eq(seen, KNUCKLE_HASHES, "the six Knuckles' pictures")
