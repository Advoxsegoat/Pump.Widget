extends TestCase
## The petals on the Hud, drawn (xvfb, gl_compatibility), in a fight: a tier I Knuckle stands with his head exactly where the gain popup
## would stand and another with his head where the pile's marker would hang. The picture is saved (out/shots/petal_hud_fight.png) and read:
## the count is drawn in the corner (gold pixels), the popup and the marker are drawn (rose and white pixels), and neither stands over a
## living fighter's head (the picture's own pixels at each head are the fighter's, not the Hud's).

const MAIN := "res://main/main.tscn"
const FOE := "res://data/actors/knuckle_1.tres"
const SIZE := Vector2i(1280, 720)
const OUT := "out/shots/petal_hud_fight.png"


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func _foe(main: Main) -> Actor:
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.def = load(FOE) as ActorDef
	foe.set_brain(Brain.new())
	main.region.add_child(foe)
	return foe


# Puts `foe` where his head is drawn at the picture point `target`.
func _head_to(main: Main, foe: Actor, target: Vector2) -> void:
	var sub := main.stage.subpixel
	var on_screen := target + Vector2(PixelSnap.MARGIN + sub.x, PixelSnap.MARGIN - sub.y)
	var camera := main.camera_rig.camera
	var hit: Variant = Plane(Vector3.UP, foe.def.look_height).intersects_ray(camera.project_ray_origin(on_screen), camera.project_ray_normal(on_screen))
	var at: Vector3 = hit
	foe.place(Transform3D(Basis(), Vector3(at.x, 0.0, at.z)))


func _head(main: Main, foe: Actor) -> Vector2:
	return main.hud.picture_point(foe.global_position + Vector3.UP * foe.def.look_height)


# How many pixels of the window within the picture rectangle `rect` (the Hud's 640 x 360, shown at 2 x) are near `color`.
func _pixels_near(image: Image, rect: Rect2, color: Color, within: float) -> int:
	var k := SIZE.x / int(Hud.PICTURE.x)
	var found := 0
	for y in range(int(rect.position.y) * k, int(rect.end.y) * k + 1):
		for x in range(int(rect.position.x) * k, int(rect.end.x) * k + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var c := image.get_pixel(x, y)
			if absf(c.r - color.r) + absf(c.g - color.g) + absf(c.b - color.b) <= within:
				found += 1
	return found


func test_in_a_fight_the_count_popup_and_marker_are_drawn_and_clear_of_every_head() -> void:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.stretch_start = "new"
	track(main)
	await frames(5)
	var hud := main.hud.find_child("StretchHud", true, false) as StretchHud
	assert_true(hud != null, "the stretch has a stretch hud")
	if hud == null:
		return
	main.player.place(Transform3D(Basis(), Vector3(0, 0, 0)))
	await frames(3)
	main.camera_rig.snap_now()
	await frames(3)
	var run := main.stretch
	run.petals.gain(120)
	var popup_base := hud.popup_rect()
	var one := _foe(main)
	_head_to(main, one, popup_base.get_center())
	run.petals.fall_at(Vector3(2.0, 0.0, -1.0))
	run.petals.gain(30)
	await frames(2)
	var two := _foe(main)
	_head_to(main, two, Vector2(hud.pile_marker().point))
	await frames(4)
	var popup := hud.popup_rect()
	var marker := hud.pile_marker()
	for i in 4:
		await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	assert_eq(shot.save_png(ProjectSettings.globalize_path("res://").path_join(OUT)), OK, "saved the picture")
	for foe: Actor in [one, two]:
		var head := _head(main, foe)
		var square := Rect2(head - Vector2.ONE * StretchHud.HEAD_RADIUS, Vector2.ONE * 2.0 * StretchHud.HEAD_RADIUS)
		assert_false(popup.intersects(square), "the popup (%s) is clear of the head at %s" % [popup, head])
		var mark := Rect2(Vector2(marker.point) - Vector2.ONE * 3.0, Vector2.ONE * 7.0)
		assert_false(mark.intersects(square), "the marker (%s) is clear of the head at %s" % [marker.point, head])
	assert_true(_pixels_near(shot, hud.count_rect(), Hud.GOLD, 0.25) >= 6, "the count is drawn in gold in the corner")
	assert_true(_pixels_near(shot, popup, Color.WHITE, 0.3) >= 6, "the popup is drawn (white)")
	var mark_area := Rect2(Vector2(marker.point) - Vector2.ONE * 3.0, Vector2.ONE * 7.0)
	assert_true(_pixels_near(shot, mark_area, Hud.ROSE, 0.3) >= 4, "the marker is drawn (rose)")
