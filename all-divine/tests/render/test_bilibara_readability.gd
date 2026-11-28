extends TestCase
## Bodies read on every ground (xvfb, gl_compatibility), the stretch a snow town at noon: its ground is pale and every body darker than it.
## In the stretch at 1280 x 720 (the 640 x 360 picture at twice the size), the picture a player sees (graded, fogged and outlined), at each of 14 reference positions three bodies
## stand in a row facing south: Abarax with a tier I Knuckle 2.4 m east and a tier III 2.4 m west, and then (Abarax hidden, the camera still
## on him) a Drummer with a heavy 2.4 m east and a blade Knuckle 2.4 m west: six bodies. For each body: the ground is the mean luma of a ring
## 3 to 8 pixels (of the 640 x 360 picture) outside its silhouette, off the other bodies; the body is the mean luma of its silhouette less the
## outermost pixel. The band: the ground 0.62 to 0.74, every body darker than its ground by 0.08 or more, each body's own luma within 0.08
## across the positions. Abarax's white shirt alone (his mean is held down by trousers, boots and hair) differs from the ground by 0.06 or
## more, or his outline carries it. A contact shadow plants a body: the ground in a strip under his feet is 0.06 darker with him there than
## without him (the same picture with every body gone: nothing else differs, in sun or in shade). Every number goes to out/shots/bilibara_readability.txt and the pictures to out/shots/bilibara_readability.png (a sheet) beside it.
## The training yard at its dark ground (0, 3) is measured the same way: the stretch is no worse than it.

const OUT_TEXT := "out/shots/bilibara_readability.txt"
const OUT_SHEET := "out/shots/bilibara_readability.png"
## The reference positions (x, z): the plan's twelve and two more in the yard (the stone square's border and a margin). The reviewer's twelve more
## are in test_bilibara_readability_more.
const POSITIONS := [
	["court A (slate, ShrineLampA's pool)", -35.0, 0.0], ["street (cobble, open)", 0.0, 0.0], ["street lamp pool", -5.0, -3.0],
	["street kerb", 0.0, 4.5], ["lane (earth)", 27.5, -30.0], ["alcove B (slate, pool)", 35.0, -34.0],
	["Rack Walk", -10.0, -22.5], ["loop lane", -32.5, -12.0], ["yard (square centre)", 27.5, -65.0],
	["yard under the north wall", 27.5, -73.0], ["yard by the kerb", 20.0, -56.5], ["lane's mouth", 27.5, -10.0],
	["yard square's border", 27.5, -69.5], ["yard west margin", 21.0, -58.0],
]
const SIZE := BilibaraRead.SIZE


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_a_body_reads_on_every_ground_in_every_light() -> void:   # Review Focus 3
	var rig := BilibaraRead.new(self)
	var problems: PackedStringArray = await rig.stretch(POSITIONS, OUT_TEXT, OUT_SHEET)
	assert_eq(problems.slice(0, 12), PackedStringArray(), "every body reads on every ground (%d problems; the table is %s)" % [problems.size(), OUT_TEXT])


func test_the_yard_is_the_floor() -> void:
	var rig := BilibaraRead.new(self)
	var made: Dictionary = await rig.yard()
	var worst: float = made.worst
	print(made.text)
	var full := ProjectSettings.globalize_path("res://").path_join(OUT_TEXT)
	var previous := FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""
	rig._write(OUT_TEXT, previous + made.text)
	# The stretch is no worse than the yard: every body of the six is darker than its ground by at least min(0.08, the yard's worst contrast);
	# the worst margin is read from the file the other test wrote.
	var stretch := -9.0
	var found := false
	for line in previous.split("\n"):
		if line.begins_with("worst margin (ground less body) in the stretch: "):
			stretch = line.get_slice(": ", 1).get_slice(" ", 0).to_float()
			found = true
	assert_true(found, "the stretch's table is in the file (run the whole file)")
	assert_true(stretch >= minf(BilibaraRead.LEAST_DARKER, worst), "the stretch's worst margin (%.3f) is at least min(%.2f, the yard's worst contrast %.3f)" % [stretch, BilibaraRead.LEAST_DARKER, worst])
