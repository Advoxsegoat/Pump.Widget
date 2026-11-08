extends TestCase
## CameraRig inside a PixelStage's World, followed by nothing but a plain Node3D. Headless.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")

var stage: PixelStage
var rig: CameraRig
var target: Node3D


func before_each() -> void:
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	target = Node3D.new()
	stage.world.add_child(target)
	rig = CameraRig.new()
	rig.target = target
	rig.stage = stage
	stage.world.add_child(rig)


func test_camera_is_fixed_ortho_three_quarter() -> void:
	rig.snap_now()
	var cam := rig.camera
	assert_eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_near(cam.size, CameraRig.ORTHO_SIZE, 1e-6)
	assert_near(CameraRig.ORTHO_SIZE, 362.0 / 32.0, 1e-6, "11.3125 m: 362 px at 32 texels per metre")
	var euler := cam.global_basis.get_euler()
	assert_near(rad_to_deg(euler.x), -40.0, 1e-3)
	assert_near(rad_to_deg(euler.y), 0.0, 1e-3)
	assert_near(rig.yaw(), 0.0, 1e-6)
	assert_true(cam.current, "the rig's camera is the one World renders")


# One texel is one internal pixel: this is what makes a camera move of 1/32 m a whole-pixel shift.
# The World image has a one-pixel margin on every side, so the ortho size covers 362 px, not 360.
func test_one_texel_is_one_internal_pixel() -> void:
	rig.snap_now()
	var cam := rig.camera
	var b := cam.global_basis
	var origin := cam.global_position - b.z * CameraRig.DISTANCE
	var here := cam.unproject_position(origin)
	var right := cam.unproject_position(origin + b.x * PixelSnap.TEXEL)
	var up := cam.unproject_position(origin + b.y * PixelSnap.TEXEL)
	assert_eq(stage.world.size, Vector2i(642, 362))
	assert_near(right.x - here.x, 1.0, 1e-3, "one texel right is one pixel right")
	assert_near(up.y - here.y, -1.0, 1e-3, "one texel up is one pixel up")
	assert_near(here.x, 321.0, 1e-3, "the follow point is the centre of the 642x362 image")
	assert_near(here.y, 181.0, 1e-3)


func test_camera_follows_and_lands_on_texel_grid() -> void:
	rig.snap_now()
	target.position = Vector3(1, 0, 0)
	await frames(120)
	var cam := rig.camera
	var b := cam.global_basis
	var gx := cam.global_position.dot(b.x) / PixelSnap.TEXEL
	var gy := cam.global_position.dot(b.y) / PixelSnap.TEXEL
	assert_near(gx, roundf(gx), 1e-3, "x on the texel grid")
	assert_near(gy, roundf(gy), 1e-3, "y on the texel grid")
	assert_true(rig.global_position.distance_to(target.global_position) < PixelSnap.TEXEL, "follow point reached the target")
	assert_true(absf(cam.global_position.dot(b.x) - 1.0) <= PixelSnap.TEXEL, "snapped camera is within a texel of the target")


func test_follow_eases_instead_of_jumping() -> void:
	rig.snap_now()
	target.position = Vector3(1, 0, 0)
	await frames(6)
	var x := rig.global_position.x
	assert_true(x > 0.05 and x < 0.95, "partway after 6 frames, got %s" % x)


func test_snap_now_goes_straight_to_the_target() -> void:
	target.position = Vector3(7.3, 0, -2.1)
	target.reset_physics_interpolation()
	rig.snap_now()
	assert_vec_near(rig.global_position, target.global_position, 1e-5)
	var b := rig.camera.global_basis
	assert_near(rig.camera.global_position.dot(b.x) / PixelSnap.TEXEL, roundf(rig.camera.global_position.dot(b.x) / PixelSnap.TEXEL), 1e-3)


func test_rig_reports_what_snapping_took_away() -> void:
	target.position = Vector3(0.3 * PixelSnap.TEXEL, 0, 0)
	target.reset_physics_interpolation()
	rig.snap_now()
	assert_near(stage.subpixel.x, 0.3, 1e-3)
	assert_near(stage.subpixel.y, 0.0, 1e-3)


func test_look_ahead_leans_along_the_velocity_up_to_the_cap() -> void:
	var body := CharacterBody3D.new()
	stage.world.add_child(body)
	rig.target = body
	body.velocity = Vector3(2, 0, 0)
	rig.snap_now()
	assert_near(rig.global_position.x, rig.look_ahead * 0.5, 1e-4, "half speed, half the look-ahead")
	body.velocity = Vector3(10, 0, 0)
	rig.snap_now()
	assert_near(rig.global_position.x, rig.look_ahead, 1e-4, "capped at look_ahead")
	body.velocity = Vector3.ZERO
	rig.snap_now()
	assert_near(rig.global_position.x, 0.0, 1e-6)


func test_camera_survives_having_no_target() -> void:
	rig.target = null
	await frames(3)
	rig.snap_now()
	assert_vec_near(rig.global_position, Vector3.ZERO, 1e-6)


func test_physics_interpolation_enabled() -> void:
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation"))


# --- cursor_ground: a point of the window to a point of the ground ---

# The windows to try: the game's 1920x1080 (3x), a 1366x768 laptop (2x, with bars above and below), and a window
# hardly bigger than the picture (1x, with bars on every side).
const WINDOWS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1366, 768), Vector2i(700, 400)]


# Makes the stage fill a window of `window` pixels with its top-left corner at the origin.
func _fit_stage(window: Vector2i) -> void:
	stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stage.size = Vector2(window)


# Where the window shows the ground point `ground`, the way the stage draws it: the camera's pixel in the 642x362
# World image, scaled up and placed at the layout's corner, moved by the draw offset the sub-pixel shift gives.
func _window_point_of(ground: Vector3, window: Vector2i) -> Vector2:
	var k := PixelStage.scale_for(window)
	var corner := Vector2(PixelStage.layout(window).position + PixelStage.draw_offset(stage.subpixel, k))
	return corner + rig.camera.unproject_position(ground) * k


func test_cursor_ground_finds_a_ground_point_it_was_shown_at() -> void:
	target.position = Vector3(0.013, 0, 0.021)   # off the texel grid: the stage is drawn shifted
	target.reset_physics_interpolation()
	rig.snap_now()
	assert_true(stage.subpixel.length() > 0.1, "the camera snapped away from where it looks, so the picture is shifted")
	for window in WINDOWS:
		_fit_stage(window)
		for ground in [Vector3(0, 0, 0), Vector3(3.5, 0, -2.0), Vector3(-5.25, 0, 4.0), Vector3(1.1, 0, 6.3)]:
			var found: Variant = rig.cursor_ground(_window_point_of(ground, window), 0.0)
			assert_true(found is Vector3, "a ray meets the ground (%s, %s)" % [ground, window])
			if found is Vector3:
				assert_vec_near(found, ground, 1e-3, "the point shown at %s in a %s window" % [ground, window])


func test_cursor_ground_reads_the_picture_not_the_window() -> void:
	# The middle of the picture shows what the camera looks at: the target. A metre east of it is 32 texels right
	# of the middle, k pixels each; a metre north is sin(40 degrees) of a metre up the screen. Not the same
	# formulas as the stage's, so this catches a layout that is wrong the same way in both directions.
	target.position = Vector3(0.013, 0, 0.021)
	target.reset_physics_interpolation()
	rig.snap_now()
	for window in WINDOWS:
		_fit_stage(window)
		var k := PixelStage.scale_for(window)
		var tolerance := PixelSnap.TEXEL / k   # the stage rounds its shift to whole output pixels
		var middle := Vector2(window) / 2.0
		var here: Variant = rig.cursor_ground(middle, 0.0)
		assert_true(here is Vector3)
		if here is Vector3:
			assert_vec_near(here, target.position, tolerance, "the middle of a %s window is the target" % window)
		var east: Variant = rig.cursor_ground(middle + Vector2(32.0 * k, 0), 0.0)
		var north: Variant = rig.cursor_ground(middle + Vector2(0, -32.0 * k * sin(deg_to_rad(40.0))), 0.0)
		assert_true(east is Vector3 and north is Vector3)
		if east is Vector3 and north is Vector3:
			assert_vec_near(east, target.position + Vector3(1, 0, 0), tolerance, "a metre of picture to the right is a metre east")
			assert_vec_near(north, target.position + Vector3(0, 0, -1), tolerance, "and one up is a metre away from the camera")


func test_cursor_ground_meets_the_plane_it_is_given() -> void:
	rig.snap_now()
	_fit_stage(WINDOWS[0])
	var up := Vector3(2.0, 1.5, -1.0)   # a point at head height: the plane through it is 1.5 m up
	var found: Variant = rig.cursor_ground(_window_point_of(up, WINDOWS[0]), 1.5)
	assert_true(found is Vector3)
	if found is Vector3:
		assert_vec_near(found, up, 1e-3, "the same ray meets a higher plane further along it")
		assert_near((found as Vector3).y, 1.5, 1e-4)


func test_cursor_ground_is_null_for_a_ray_parallel_to_the_plane() -> void:
	rig.snap_now()
	_fit_stage(WINDOWS[0])
	rig.rotation.x = 0.0   # looking level: every ray runs along the ground
	assert_eq(rig.cursor_ground(Vector2(960, 540), 0.0), null)


func test_cursor_ground_is_null_without_a_stage() -> void:
	rig.snap_now()
	rig.stage = null
	assert_eq(rig.cursor_ground(Vector2(960, 540), 0.0), null, "with no stage there is no telling how the window maps")


func test_lock_leans_the_camera_toward_the_target_at_most_three_metres() -> void:
	rig.snap_now()
	var base := rig.global_position
	var foe := Node3D.new()
	stage.world.add_child(foe)
	foe.global_position = Vector3(4, 0, 0)
	rig.lock_target = foe
	rig.snap_now()
	assert_vec_near(rig.global_position - base, Vector3(1.4, 0, 0), 1e-3, "35% of the way to a foe 4 m off")
	foe.global_position = Vector3(30, 0, 0)
	rig.snap_now()
	assert_vec_near(rig.global_position - base, Vector3(3, 0, 0), 1e-3, "but never more than 3 m")
	rig.lock_target = null
	rig.snap_now()
	assert_vec_near(rig.global_position, base, 1e-3, "no lock, no lean")
	rig.lock_target = foe
	foe.free()
	rig.snap_now()
	assert_vec_near(rig.global_position, base, 1e-3, "a target that is gone leans nothing, and nothing errors")
