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
