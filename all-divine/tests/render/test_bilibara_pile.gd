extends TestCase
## The pile of petals a death leaves is drawn in the world (a column of pixel petals, no light), and the stretch's picture rules hold with
## it in the picture (xvfb, gl_compatibility). The rose glow of the shrines broke four of them on its first try (a head no longer read
## beside it, and it counted as a lamp lifting the ground), so the pile is held to the same two measures here:
##  - a head: with a pile standing 1.5 m from a tier I Knuckle (behind him, in front of him, beside him), on the slate of court A, the
##    cobble of the street and the tan earth of the lane, every head reads by the stretch's own measure (tests/support/bilibara_read.gd:
##    under half of the head's ring within 0.08 of the head's tone; a ring of under 60 pixels, a head hidden, is a problem too);
##  - a lamp: the ground 2 m from the pile is lifted by no more than 0.06 by it (the pile on against the pile hidden; the lamp test's
##    own bound): it lights nothing.
## And the column is seen: on each ground it is measurably there (petals of its colours over the ground that is not theirs).

const SIZE := BilibaraRead.SIZE
const OUT_TEXT := "out/shots/bilibara_pile_%s.txt"
const OUT_SHEET := "out/shots/bilibara_pile_%s.png"
## Court A's slate, the street's cobble and the lane's tan earth: the same places the readability tests read on.
const GROUNDS := [["slate, court A", -35.0, 0.0], ["cobble, the street", 0.0, 0.0], ["tan earth, the lane", 27.5, -30.0]]
## A pile 1.5 m from the tier I Knuckle: behind him (north: the column rises against his head's background), in front of him (the column
## between the camera and him), and beside him (east).
const PILES := [["behind", Vector3(0.0, 0.0, -1.5)], ["in front", Vector3(0.0, 0.0, 1.5)], ["beside", Vector3(1.5, 0.0, 0.0)]]
const LIFT_AT_MOST := 0.06
const LIFT_AWAY := 2.0
const SHOT_OUT := "out/shots/bilibara_pile_ground_%s.png"


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_a_head_reads_beside_a_pile_on_slate_cobble_and_tan_earth() -> void:
	var all := PackedStringArray()
	for pile: Array in PILES:
		var rig := BilibaraRead.new(self)
		var tag: String = (pile[0] as String).replace(" ", "_")
		var problems: PackedStringArray = await rig.stretch(GROUNDS, OUT_TEXT % tag, OUT_SHEET % tag, {
				head_only = true, strict_head = true, row_one_only = true, pile = pile[1], pile_settle = BilibaraRead.PILE_FILLS})
		for line in problems:
			all.append("pile %s: %s" % [pile[0], line])
	assert_eq(all.slice(0, 12), PackedStringArray(), "every head reads with a pile 1.5 m off (%d problems; the tables are %s)" % [all.size(), OUT_TEXT % "<where>"])


func test_a_pile_lifts_the_ground_two_metres_away_by_no_more_than_a_lamp_may() -> void:
	Game.reset()
	var main := track((load(BilibaraRead.MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	await frames(5)
	var rig := BilibaraRead.new(self)
	var report := PackedStringArray()
	var worst := 0.0
	for ground: Array in GROUNDS:
		var at := Vector3(ground[1], 0.0, ground[2])
		main.player.set_brain(Brain.new())
		main.player.place(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.0, 3.0)))
		main.player.visible = false
		main.camera_rig.snap_now()
		await frames(8)
		var pile_at := at + Vector3(0.0, 0.0, 0.0)
		await rig.lay_pile(main, pile_at, BilibaraRead.PILE_FILLS)
		var piles := main.stretch.find_children("*", "PetalPile", true, false)
		assert_eq(piles.size(), 1, "%s: one pile is drawn" % ground[0])
		if piles.size() != 1:
			continue
		var pile := piles[0] as Node3D
		for i in 4:
			await RenderingServer.frame_post_draw
		var with_pile := get_viewport().get_texture().get_image()
		pile.visible = false
		for i in 4:
			await RenderingServer.frame_post_draw
		var without := get_viewport().get_texture().get_image()
		pile.visible = true
		# the patch of ground LIFT_AWAY metres to the east of the pile, as wide as the column's drift and a little more
		var lift := 0.0
		var mean := 0.0
		var seen := 0
		var centre := main.camera_rig.camera.unproject_position(pile_at + Vector3(LIFT_AWAY, 0.0, 0.0))
		var edge := main.camera_rig.camera.unproject_position(pile_at + Vector3(LIFT_AWAY + 0.6, 0.0, 0.0))
		var half := maxi(int(absf(edge.x - centre.x)), 3)
		for dy in range(-half / 2, half / 2 + 1):
			for dx in range(-half, half + 1):
				var p := Vector2i(centre.round()) + Vector2i(PixelSnap.MARGIN, PixelSnap.MARGIN) + Vector2i(dx, dy)
				var w := rig._to_window(main, p)
				var d := rig._luma(with_pile.get_pixelv(w)) - rig._luma(without.get_pixelv(w))
				lift = maxf(lift, d)
				mean += d
				seen += 1
		mean /= maxf(seen, 1.0)
		report.append("%s: lift at %.0f m east, most %.3f, mean %.3f over %d px" % [ground[0], LIFT_AWAY, lift, mean, seen])
		worst = maxf(worst, lift)
		with_pile.save_png(ProjectSettings.globalize_path("res://").path_join(SHOT_OUT % str(ground[0]).get_slice(",", 0).replace(" ", "_")))
		assert_true(seen > 20, "%s: the patch has pixels (%d)" % [ground[0], seen])
	print("pile lift: %s" % [report])
	assert_true(worst <= LIFT_AT_MOST, "a pile lifts the ground 2 m away by %.3f (at most %.2f): %s" % [worst, LIFT_AT_MOST, report])


func test_the_column_is_seen_on_each_ground() -> void:
	# with the pile and without it, the pixels over the pile's own column differ: petals of its colours, rose and gold, are drawn there
	Game.reset()
	var main := track((load(BilibaraRead.MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	main.enter_stretch()
	await frames(5)
	var rig := BilibaraRead.new(self)
	var report := PackedStringArray()
	for ground: Array in GROUNDS:
		var at := Vector3(ground[1], 0.0, ground[2])
		main.player.set_brain(Brain.new())
		main.player.place(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.0, 3.0)))
		main.player.visible = false
		main.camera_rig.snap_now()
		await frames(8)
		await rig.lay_pile(main, at, BilibaraRead.PILE_FILLS)
		var piles := main.stretch.find_children("*", "PetalPile", true, false)
		if piles.size() != 1:
			fail("%s: %d piles" % [ground[0], piles.size()])
			continue
		var pile := piles[0] as Node3D
		for i in 4:
			await RenderingServer.frame_post_draw
		var with_pile := get_viewport().get_texture().get_image()
		pile.visible = false
		for i in 4:
			await RenderingServer.frame_post_draw
		var without := get_viewport().get_texture().get_image()
		pile.visible = true
		var foot := main.camera_rig.camera.unproject_position(at).round() + Vector2(PixelSnap.MARGIN, PixelSnap.MARGIN)
		var top := main.camera_rig.camera.unproject_position(at + Vector3.UP * 2.4).round() + Vector2(PixelSnap.MARGIN, PixelSnap.MARGIN)
		var changed := 0
		var strong := 0
		var area := 0
		for y in range(int(top.y), int(foot.y) + 1):
			for x in range(int(foot.x) - 14, int(foot.x) + 15):
				var w := rig._to_window(main, Vector2i(x, y))
				var d := absf(rig._luma(with_pile.get_pixelv(w)) - rig._luma(without.get_pixelv(w)))
				area += 1
				if d > 0.03:
					changed += 1
				if d > 0.15:
					strong += 1
		report.append("%s: %d of %d px over the column differ by more than 0.03, %d by more than 0.15" % [ground[0], changed, area, strong])
		assert_true(changed >= 24, "%s: the column is there (%s)" % [ground[0], report[-1]])
		assert_true(strong >= 6, "%s: and some of it plainly (%s)" % [ground[0], report[-1]])
	print("pile seen: %s" % [report])
