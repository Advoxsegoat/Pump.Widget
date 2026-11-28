extends TestCase
## The stretch's line on the Hud: what pressing the interact button would do, at the bottom centre, and nothing while a scene has the
## Hud (it draws only when the Hud does).

const MAIN := "res://main/main.tscn"
const SETTINGS_PATH := "user://settings_test.cfg"


func before_each() -> void:
	Settings.path = SETTINGS_PATH


func after_each() -> void:
	InputFeed.release()
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func _main() -> Main:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.stretch_start = "new"
	return track(main) as Main


func _hud_of(main: Main) -> StretchHud:
	return main.hud.find_child("StretchHud", true, false) as StretchHud


func test_the_prompt_line_is_the_interactors_and_is_empty_with_nothing_near() -> void:
	var main := _main()
	await frames(3)
	var hud := _hud_of(main)
	assert_true(hud != null, "the stretch has a stretch hud")
	if hud == null:
		return
	main.player.place(Transform3D(Basis(), Vector3.ZERO))  # (he starts a step from the first shrine: the street is nowhere near one)
	await frames(3)
	assert_eq(hud.prompt_line(), "", "nothing near, no line")
	var plinth := main.stretch.def.shrines[1].plinth
	main.player.place(Transform3D(Basis(), plinth + Vector3(0, 0, 1.5)))
	await frames(3)
	assert_eq(hud.prompt_line(), "%s  Rest" % ControlsList.shown(&"interact", false), "near a shrine: the key and what it does")
	assert_eq(hud.prompt_line(), main.stretch.interactor.prompt_line(), "and it is the interactor's line")


func test_it_draws_nothing_while_the_hud_is_hidden_by_a_scene() -> void:
	var main := _main()
	await frames(3)
	var hud := _hud_of(main)
	if hud == null:
		fail("no stretch hud")
		return
	var plinth := main.stretch.def.shrines[1].plinth
	main.player.place(Transform3D(Basis(), plinth + Vector3(0, 0, 1.5)))
	await frames(3)
	assert_true(hud.draws(), "it draws a line near a shrine")
	main.hud.suppressed = true
	assert_eq(main.hud.shown_alpha(), 0.0, "the Hud is hidden")
	assert_false(hud.draws(), "and the stretch hud's draw list is empty")


# --- Task 3: the petals on the Hud ---

func _foe_at(main: Main, at: Vector3) -> Actor:
	var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.def = load("res://data/actors/knuckle_1.tres") as ActorDef
	foe.set_brain(Brain.new())
	main.region.add_child(foe)
	foe.place(Transform3D(Basis(), at))
	return foe


func _overlaps_head(main: Main, hud: StretchHud, rect: Rect2, actor: Actor) -> bool:
	var head := main.hud.picture_point(actor.global_position + Vector3.UP * actor.def.look_height)
	return rect.grow(2.0).intersects(Rect2(head - Vector2.ONE * StretchHud.HEAD_RADIUS, Vector2.ONE * 2.0 * StretchHud.HEAD_RADIUS))


func test_petal_text_popup_and_marker() -> void:
	var main := _main()
	await frames(3)
	var hud := _hud_of(main)
	if hud == null:
		fail("no stretch hud")
		return
	var run := main.stretch
	assert_eq(hud.petal_text(), "0", "none carried: a plain 0")
	run.petals.gain(120)
	assert_eq(hud.petal_text(), "120", "carried 120: the plain number")
	assert_eq(hud.gain_popup(), "+120", "and a popup of the gain")
	await frames(91)
	assert_eq(hud.gain_popup(), "", "the popup is gone after 90 play frames")
	run.petals.gain(20)
	assert_eq(hud.gain_popup(), "+20", "a gain of 20 shows +20")
	await frames(60)
	run.petals.gain(10)
	assert_eq(hud.gain_popup(), "+30", "a gain while the popup shows adds to it")
	await frames(85)
	assert_eq(hud.gain_popup(), "+30", "and the 90 frames start again")
	await frames(10)
	assert_eq(hud.gain_popup(), "", "gone")
	# a pause does not run the popup out
	run.petals.gain(5)
	Game.change(Game.State.PAUSE)
	await frames(200)
	assert_eq(hud.gain_popup(), "+5", "in a pause it stays")
	Game.change(Game.State.PLAY)
	assert_eq(hud.pile_marker(), {}, "no pile, no marker")
	# a pile in the picture
	main.player.place(Transform3D(Basis(), Vector3(0, 0, 0)))
	await frames(3)
	main.camera_rig.snap_now()
	await frames(2)
	var near := Vector3(1.2, 0, -0.8)  # (the picture is a few metres wide: this is in it)
	run.petals.fall_at(near)
	var marker := hud.pile_marker()
	assert_false(marker.is_empty(), "a pile on screen has a marker")
	if not marker.is_empty():
		assert_false(marker.arrow, "no arrow while it is on screen")
		var want := main.hud.picture_point(near + Vector3.UP * 0.8)
		assert_true(Vector2(marker.point).distance_to(want) <= 14.0, "the marker is by the pile's picture point (%s for %s)" % [marker.point, want])
	# off the picture
	run.petals.take_back()
	run.petals.gain(10)
	run.petals.fall_at(Vector3(-30, 0, 0))
	marker = hud.pile_marker()
	assert_false(marker.is_empty(), "a pile off screen has a marker too")
	if not marker.is_empty():
		assert_true(marker.arrow, "an arrow, since it is off the picture")
		var inset := Rect2(6.0, 6.0, Hud.PICTURE.x - 12.0, Hud.PICTURE.y - 12.0)
		assert_true(inset.has_point(Vector2(marker.point)), "its point is inside the picture's 6 px inset (%s)" % [marker.point])
		assert_true(marker.point.x <= StretchHud.ARROW_INSET + 1, "at the left edge, where the pile lies")
		# the arrow is a mark worth seeing: at least 12 picture pixels long and across (24 px at 1280 x 720), all of it inside the picture
		var corners := StretchHud.arrow_points(Vector2(marker.point), marker.dir, 0.0)
		var dir: Vector2 = marker.dir
		var along: Array = []
		var across: Array = []
		for corner in corners:
			along.append((corner - Vector2(marker.point)).dot(dir))
			across.append((corner - Vector2(marker.point)).dot(Vector2(-dir.y, dir.x)))
		assert_true(along.max() - along.min() >= 11.9, "the arrow is at least 12 pixels long (%s)" % [along.max() - along.min()])
		assert_true(across.max() - across.min() >= 11.9, "and 12 across (%s)" % [across.max() - across.min()])
		for corner in corners:
			assert_true(Rect2(Vector2.ZERO, Hud.PICTURE).has_point(corner), "every corner of it is inside the picture (%s)" % [corner])


func test_the_count_stands_at_the_top_right_and_the_popup_under_it() -> void:
	var main := _main()
	await frames(3)
	var hud := _hud_of(main)
	if hud == null:
		fail("no stretch hud")
		return
	main.stretch.petals.gain(1234)
	var count := hud.count_rect()
	assert_true(count.end.x <= Hud.PICTURE.x - 4.0 and count.end.x >= Hud.PICTURE.x - 24.0, "the count's right edge is by the picture's right edge (%s)" % [count])
	assert_true(count.position.y >= 2.0 and count.end.y <= 30.0, "near the top (%s)" % [count])
	var popup := hud.popup_rect()
	assert_true(popup.position.y >= count.end.y, "the popup is under the count (%s under %s)" % [popup, count])
	assert_true(popup.end.x <= Hud.PICTURE.x, "and inside the picture")


# Puts `foe` where his head (look_height up) is drawn at the picture point `target`.
func _head_to(main: Main, foe: Actor, target: Vector2) -> void:
	var sub := main.stage.subpixel
	var on_screen := target + Vector2(PixelSnap.MARGIN + sub.x, PixelSnap.MARGIN - sub.y)
	var camera := main.camera_rig.camera
	var hit: Variant = Plane(Vector3.UP, foe.def.look_height).intersects_ray(camera.project_ray_origin(on_screen), camera.project_ray_normal(on_screen))
	var at: Vector3 = hit
	foe.place(Transform3D(Basis(), Vector3(at.x, 0.0, at.z)))


func test_the_popup_and_the_marker_never_cover_a_fighters_head() -> void:
	var main := _main()
	await frames(3)
	var hud := _hud_of(main)
	if hud == null:
		fail("no stretch hud")
		return
	main.player.place(Transform3D(Basis(), Vector3(0, 0, 0)))
	await frames(3)
	main.camera_rig.snap_now()
	await frames(3)
	var run := main.stretch
	run.petals.gain(30)
	var foe := _foe_at(main, Vector3(0, 0, 0))
	# his head exactly where the popup stands without him
	var base := hud.popup_rect()
	_head_to(main, foe, base.get_center())
	var head := main.hud.picture_point(foe.global_position + Vector3.UP * foe.def.look_height)
	assert_true(head.distance_to(base.get_center()) <= 2.0, "(his head is drawn at the popup: %s for %s)" % [head, base.get_center()])
	await frames(1)
	var moved := hud.popup_rect()
	assert_false(_overlaps_head(main, hud, moved, foe), "the popup does not cover his head (it stands at %s, his head at %s)" % [moved, head])
	assert_eq(hud.gain_popup(), "+30", "(and it still says what it says)")
	# the marker, with his head where it would stand
	run.petals.fall_at(Vector3(1.2, 0, -0.8))
	foe.place(Transform3D(Basis(), Vector3(8, 0, 8)))
	await frames(1)
	var plain := Vector2(hud.pile_marker().point)
	_head_to(main, foe, plain)
	await frames(1)
	var marker := hud.pile_marker()
	var rect := Rect2(Vector2(marker.point) - Vector2.ONE * 4.0, Vector2.ONE * 8.0)
	assert_false(_overlaps_head(main, hud, rect, foe), "the marker does not cover his head (it stands at %s, was %s, his head at %s)" % [marker.point, plain, main.hud.picture_point(foe.global_position + Vector3.UP * foe.def.look_height)])
	# and none of this is drawn while a scene has the Hud
	main.hud.suppressed = true
	assert_false(hud.draws_petals(), "nothing of the petals is drawn while the Hud is hidden")
