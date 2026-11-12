extends TestCase
## CinePose: what a shot solves to at a moment of it, and how two poses blend. Pure arithmetic, headless.


# The row of the picture a world point is on, from a pose: the camera looks along its pitch and yaw at pose.aim, which is the
# middle row, and a pixel is TEXEL / zoom of a metre along the camera's up.
func _row(pose: CinePose, point: Vector3) -> float:
	var up := Basis.from_euler(Vector3(deg_to_rad(pose.pitch_deg), deg_to_rad(pose.yaw_deg), 0.0)).y
	return PixelSnap.INTERNAL.y / 2.0 - (point - pose.aim).dot(up) * pose.zoom / PixelSnap.TEXEL


# A world of three named places on the floor (an actor is its feet, a mark is where it is).
func _world(places := {}) -> Callable:
	var found: Dictionary = {&"a": Vector3(2, 0, 0), &"b": Vector3(6, 0, 4), &"fg": Vector3(0, 0, 0)}
	found.merge(places, true)
	return func(name: StringName) -> Variant: return found.get(name, null)


func _shot(framing := Shot.Framing.WIDE, move := Shot.CamMove.STATIC) -> Shot:
	var shot := Shot.new()
	shot.framing = framing
	shot.move = move
	shot.length = 60
	shot.aim = &"a"
	return shot


func test_blend_returns_its_ends_exactly_and_eases_between() -> void:
	var a := CinePose.new()
	a.aim = Vector3(0, 1, 0)
	a.yaw_deg = 350.0
	a.pitch_deg = -30.0
	a.zoom = 1.0
	a.focus = Vector3(0, 1, 0)
	var b := CinePose.new()
	b.aim = Vector3(4, 1, 8)
	b.yaw_deg = 10.0
	b.pitch_deg = -50.0
	b.zoom = 3.0
	b.focus = Vector3(4, 1, 8)
	var start := CinePose.blend(a, b, 0.0)
	var end := CinePose.blend(a, b, 1.0)
	assert_true(start.aim == a.aim and start.yaw_deg == a.yaw_deg and start.pitch_deg == a.pitch_deg and start.zoom == a.zoom and start.focus == a.focus, "t 0 is a, exactly")
	assert_true(end.aim == b.aim and end.yaw_deg == b.yaw_deg and end.pitch_deg == b.pitch_deg and end.zoom == b.zoom and end.focus == b.focus, "t 1 is b, exactly")
	var mid := CinePose.blend(a, b, 0.5)
	assert_vec_near(mid.aim, Vector3(2, 1, 4), 1e-5, "smoothstep(0.5) is 0.5: the midpoint of the aim")
	assert_near(mid.zoom, 2.0, 1e-5)
	assert_near(mid.pitch_deg, -40.0, 1e-5)
	assert_near(absf(angle_difference(deg_to_rad(mid.yaw_deg), 0.0)), 0.0, 1e-5, "350 to 10 turns through 0, not through 180")
	var early := CinePose.blend(a, b, 0.25)
	assert_true(early.zoom < 1.0 + 2.0 * 0.25, "eased: slower than linear at the start (%s)" % early.zoom)
	assert_true(CinePose.blend(a, b, -1.0).zoom == 1.0 and CinePose.blend(a, b, 2.0).zoom == 3.0, "t is clamped")
	start.zoom = 9.0
	assert_eq(a.zoom, 1.0, "a blend is a new pose, never one of its ends")


func test_framing_defaults_set_the_zoom() -> void:
	var expected := {
		Shot.Framing.WIDE: 1.0, Shot.Framing.MEDIUM: 2.0, Shot.Framing.CLOSE: 3.0,
		Shot.Framing.OVER_SHOULDER: 2.0, Shot.Framing.INSERT: 4.0,
	}
	for framing in expected:
		var shot := _shot(framing)
		shot.over_shoulder = &"fg"
		assert_eq(CinePose.solve(shot, 0.0, _world()).zoom, expected[framing], "framing %d" % framing)
	var explicit := _shot(Shot.Framing.WIDE)
	explicit.zoom = 3
	assert_eq(CinePose.solve(explicit, 0.0, _world()).zoom, 3.0, "an explicit zoom wins")


func test_a_dolly_is_a_zoom_ramp_that_is_whole_at_its_ends_and_a_crane_a_pitch_ramp() -> void:
	var dolly := _shot(Shot.Framing.MEDIUM, Shot.CamMove.DOLLY)
	dolly.zoom = 2
	dolly.zoom_to = 4
	var world := _world()
	assert_true(CinePose.solve(dolly, 0.0, world).zoom == 2.0, "whole at the start")
	assert_true(CinePose.solve(dolly, 1.0, world).zoom == 4.0, "whole at the end")
	assert_near(CinePose.solve(dolly, 0.5, world).zoom, 3.0, 1e-6, "linear between")
	assert_near(CinePose.solve(dolly, 0.25, world).zoom, 2.5, 1e-6)
	var crane := _shot(Shot.Framing.WIDE, Shot.CamMove.CRANE)
	crane.pitch_deg = -30.0
	crane.pitch_to_deg = -60.0
	assert_near(CinePose.solve(crane, 0.0, world).pitch_deg, -30.0, 1e-6)
	assert_near(CinePose.solve(crane, 0.5, world).pitch_deg, -45.0, 1e-6)
	assert_near(CinePose.solve(crane, 1.0, world).pitch_deg, -60.0, 1e-6)
	assert_near(CinePose.solve(crane, 0.5, world).zoom, 1.0, 1e-6, "a crane does not zoom")


func test_a_pan_ramps_the_aim_and_an_orbit_the_yaw() -> void:
	var pan := _shot(Shot.Framing.WIDE, Shot.CamMove.PAN)
	pan.aim = &"a"
	pan.aim_to = &"b"
	pan.aim_height = 1.5
	var world := _world()
	assert_vec_near(CinePose.solve(pan, 0.0, world).aim, Vector3(2, 1.5, 0), 1e-6, "the aim is raised by aim_height")
	assert_vec_near(CinePose.solve(pan, 0.5, world).aim, Vector3(4, 1.5, 2), 1e-6, "the midpoint, linear")
	assert_vec_near(CinePose.solve(pan, 0.25, world).aim, Vector3(3, 1.5, 1), 1e-6)
	assert_vec_near(CinePose.solve(pan, 1.0, world).aim, Vector3(6, 1.5, 4), 1e-6)
	var orbit := _shot(Shot.Framing.WIDE, Shot.CamMove.ORBIT)
	orbit.yaw_deg = 0.0
	orbit.yaw_to_deg = 90.0
	assert_near(CinePose.solve(orbit, 0.5, world).yaw_deg, 45.0, 1e-6)
	assert_near(CinePose.solve(orbit, 0.25, world).yaw_deg, 22.5, 1e-6)
	orbit.yaw_to_deg = 270.0
	assert_near(CinePose.solve(orbit, 0.5, world).yaw_deg, 135.0, 1e-6, "an orbit turns the way its numbers say, not by the shortest turn")


func test_over_the_shoulder_puts_the_camera_behind_the_foreground_actor() -> void:
	var shot := _shot(Shot.Framing.OVER_SHOULDER)
	shot.aim = &"b"
	shot.over_shoulder = &"fg"
	# fg at the origin, the aim 6 m east and 4 m south: the camera looks that way along the ground.
	var pose := CinePose.solve(shot, 0.0, _world())
	var forward := Vector3(-sin(deg_to_rad(pose.yaw_deg)), 0, -cos(deg_to_rad(pose.yaw_deg)))
	var want := Vector3(6, 0, 4).normalized()
	assert_vec_near(forward, want, 1e-5, "the view runs from the foreground actor toward the aim")
	var north := _shot(Shot.Framing.OVER_SHOULDER)
	north.aim = &"a"
	north.over_shoulder = &"fg"
	var along_x := CinePose.solve(north, 0.0, _world({&"a": Vector3(0, 0, -3)}))
	assert_near(along_x.yaw_deg, 0.0, 1e-5, "an aim due north of him is the gameplay yaw")
	var nobody := _shot(Shot.Framing.OVER_SHOULDER)
	nobody.yaw_deg = 33.0
	nobody.over_shoulder = &"ghost"
	assert_near(CinePose.solve(nobody, 0.0, _world()).yaw_deg, 33.0, 1e-6, "with no foreground actor the shot's own yaw stands")


func test_pitch_is_clamped_and_a_missing_target_falls_back_to_the_last_aim() -> void:
	var steep := _shot()
	steep.pitch_deg = -80.0
	assert_near(CinePose.solve(steep, 0.0, _world()).pitch_deg, -65.0, 1e-6)
	var flat := _shot()
	flat.pitch_deg = -5.0
	assert_near(CinePose.solve(flat, 0.0, _world()).pitch_deg, -15.0, 1e-6)
	var crane := _shot(Shot.Framing.WIDE, Shot.CamMove.CRANE)
	crane.pitch_deg = -40.0
	crane.pitch_to_deg = -90.0
	assert_near(CinePose.solve(crane, 1.0, _world()).pitch_deg, -65.0, 1e-6, "the ramp's end is clamped too")
	var lost := _shot()
	lost.aim = &"gone"
	var last := CinePose.new()
	last.aim = Vector3(7, 1, 7)
	last.focus = Vector3(7, 1, 7)
	var pose := CinePose.solve(lost, 0.5, _world(), last)
	assert_vec_near(pose.aim, Vector3(7, 1, 7), 1e-6, "a name that resolves to nothing keeps the last aim")
	assert_vec_near(pose.focus, Vector3(7, 1, 7), 1e-6)
	var first := CinePose.solve(lost, 0.5, _world())
	assert_vec_near(first.aim, Vector3.ZERO, 1e-6, "and with none before it, the origin: never an error")


func test_each_framing_has_its_own_pitch() -> void:
	var expected := {
		Shot.Framing.WIDE: -40.0, Shot.Framing.MEDIUM: -30.0, Shot.Framing.CLOSE: -25.0,
		Shot.Framing.OVER_SHOULDER: -20.0, Shot.Framing.INSERT: -25.0,
	}
	for framing in expected:
		var shot := _shot(framing)
		shot.over_shoulder = &"fg"
		assert_eq(shot.pitch_deg, 0.0, "a shot's pitch is 0, the framing's own, until set")
		assert_near(CinePose.solve(shot, 0.0, _world()).pitch_deg, expected[framing], 1e-6, "framing %d" % framing)
	var explicit := _shot(Shot.Framing.CLOSE)
	explicit.pitch_deg = -50.0
	assert_near(CinePose.solve(explicit, 0.0, _world()).pitch_deg, -50.0, 1e-6, "an explicit pitch wins")
	var crane := _shot(Shot.Framing.MEDIUM, Shot.CamMove.CRANE)
	crane.pitch_to_deg = -50.0
	assert_near(CinePose.solve(crane, 0.0, _world()).pitch_deg, -30.0, 1e-6, "a crane starts at the framing's own")
	assert_near(CinePose.solve(crane, 1.0, _world()).pitch_deg, -50.0, 1e-6)
	var still := _shot(Shot.Framing.MEDIUM, Shot.CamMove.CRANE)
	assert_near(CinePose.solve(still, 1.0, _world()).pitch_deg, -30.0, 1e-6, "pitch_to 0 is no crane")


func _line_shot(framing := Shot.Framing.CLOSE) -> Shot:
	var shot := _shot(framing)
	shot.aim_height = 1.5
	shot.lines.append(DialogueLine.new())
	return shot


func test_a_shot_with_a_line_puts_its_aim_in_the_middle_of_the_free_band_for_its_whole_length() -> void:
	var world := _world()
	var truth := Vector3(2, 1.5, 0)
	for bars in [true, false]:
		var band := CineOverlay.free_band(bars)
		for progress in [0.0, 0.3, 1.0]:
			var pose := CinePose.solve(_line_shot(), progress, world, null, bars)
			assert_near(_row(pose, truth), (band.x + band.y) / 2.0, 1e-3, "the aim is mid-band at %s (bars %s)" % [progress, bars])
	var plain := CinePose.solve(_shot(Shot.Framing.CLOSE), 0.0, world, null, true)
	assert_vec_near(plain.aim, Vector3(2, 1.0, 0), 1e-6, "a shot with no line is framed in the middle of the picture as before")
	var dolly := _line_shot(Shot.Framing.MEDIUM)
	dolly.move = Shot.CamMove.DOLLY
	dolly.zoom = 2
	dolly.zoom_to = 4
	var band := CineOverlay.free_band(true)
	for progress in [0.0, 0.5, 1.0]:
		var pose := CinePose.solve(dolly, progress, world, null, true)
		assert_near(_row(pose, truth), (band.x + band.y) / 2.0, 1e-3, "and through a dolly (%s)" % progress)
	var focused := CinePose.solve(_line_shot(), 0.0, world, null, true)
	assert_vec_near(focused.focus, truth, 1e-6, "the focus stays on the person, not the offset aim")


func test_an_over_the_shoulder_aim_is_a_third_of_the_way_down_the_free_band() -> void:
	var shot := _shot(Shot.Framing.OVER_SHOULDER)
	shot.aim = &"b"
	shot.over_shoulder = &"fg"
	var band := CineOverlay.free_band(true)
	var pose := CinePose.solve(shot, 0.0, _world(), null, true)
	assert_near(_row(pose, Vector3(6, 1.0, 4)), band.x + (band.y - band.x) / 3.0, 1e-3)
	var forward := Vector3(-sin(deg_to_rad(pose.yaw_deg)), 0, -cos(deg_to_rad(pose.yaw_deg)))
	assert_vec_near(forward, Vector3(6, 0, 4).normalized(), 1e-5, "and the camera still looks from the foreground actor toward it")
