extends TestCase
## Bodies read on every ground (the reviewer's twelve more positions: the second half of the readability tests, a file of its own so that each stays under three minutes) (xvfb, gl_compatibility), the stretch a snow town at noon: its ground is pale and every body darker than it.
## In the stretch at 1280 x 720 (the 640 x 360 picture at twice the size), the picture a player sees (graded, fogged and outlined), at each of 14 reference positions three bodies
## stand in a row facing south: Abarax with a tier I Knuckle 2.4 m east and a tier III 2.4 m west, and then (Abarax hidden, the camera still
## on him) a Drummer with a heavy 2.4 m east and a blade Knuckle 2.4 m west: six bodies. For each body: the ground is the mean luma of a ring
## 3 to 8 pixels (of the 640 x 360 picture) outside its silhouette, off the other bodies; the body is the mean luma of its silhouette less the
## outermost pixel. The band: the ground 0.62 to 0.74, every body darker than its ground by 0.08 or more, each body's own luma within 0.08
## across the positions. Abarax's white shirt alone (his mean is held down by trousers, boots and hair) differs from the ground by 0.06 or
## more, or his outline carries it. A contact shadow plants a body: the ground in a strip under his feet is 0.06 darker with him there than
## without him (the same picture with every body gone: nothing else differs, in sun or in shade). Every number goes to out/shots/bilibara_readability.txt and the pictures to out/shots/bilibara_readability.png (a sheet) beside it.
## The training yard at its dark ground (0, 3) is measured the same way: the stretch is no worse than it.

const OUT_TEXT := "out/shots/bilibara_readability_more.txt"
const OUT_SHEET := "out/shots/bilibara_readability_more.png"
## The reviewer's twelve more positions (x, z): in a front's shade, under the colonnade, on the yard's slate border, beside a low wall, at the street's
## kerb on the water side, beside each vat, at both sides of the gate's board, in alcove B, where two grounds meet, at the street's far end.
const POSITIONS := [
	["front's shade, street", 3.0, -4.2], ["under the colonnade", -5.0, -23.2], ["slate border, yard W", 21.75, -62.5], ["beside the low wall", 27.5, -50.0],
	["street kerb, water side", 20.0, 4.8], ["beside the vat, yard W", 24.5, -66.25], ["gate far, north of the board", -32.5, -7.2], ["alcove B", 36.0, -31.5],
	["two grounds meet, lane mouth", 27.5, -5.0], ["street's far east end", 31.0, 1.0], ["beside the vat, yard E", 30.7, -66.25], ["gate near, south of the board", -32.5, -3.5],
]
const SIZE := BilibaraRead.SIZE


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_a_body_reads_at_the_twelve_more_places() -> void:
	var rig := BilibaraRead.new(self)
	var problems: PackedStringArray = await rig.stretch(POSITIONS, OUT_TEXT, OUT_SHEET)
	assert_eq(problems.slice(0, 12), PackedStringArray(), "every body reads on every ground (%d problems; the table is %s)" % [problems.size(), OUT_TEXT])
