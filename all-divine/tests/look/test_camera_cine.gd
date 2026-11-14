extends TestCase
## CameraRig's cine layer: a pose the Director blends the game's camera toward. Headless.
##
## As test_camera_rig.gd: a rig in a stage, followed by a plain Node3D.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")

var stage: PixelStage
var rig: CameraRig
var target: Node3D


func before_each() -> void:
	var made := _make_rig(Vector3(3, 0, 2))
	stage = made[0]
	rig = made[1]
	target = made[2]


# A stage with a rig on a target at `at`, snapped to it.
func _make_rig(at: Vector3) -> Array:
	var new_stage := track(STAGE_SCENE.instantiate()) as PixelStage
	var new_target := Node3D.new()
	new_stage.world.add_child(new_target)
	new_target.position = at
	var new_rig := CameraRig.new()
	new_rig.target = new_target
	new_rig.stage = new_stage
	new_stage.world.add_child(new_rig)
	new_target.reset_physics_interpolation()
	new_rig.snap_now()
	return [new_stage, new_rig, new_target]


func _pose(aim: Vector3, yaw := 0.0, pitch := -40.0, zoom := 1.0) -> CinePose:
	var pose := CinePose.new()
	pose.aim = aim
	pose.yaw_deg = yaw
	pose.pitch_deg = pitch
	pose.zoom = zoom
	pose.focus = aim
	return pose


# Two transforms the same to float rounding (placing a camera in a rig that was turned leaves 1e-7 in its basis).
func _close(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 1e-4 and (a.basis.x - b.basis.x).length() < 1e-5 \
		and (a.basis.y - b.basis.y).length() < 1e-5 and (a.basis.z - b.basis.z).length() < 1e-5


func test_with_no_cine_the_rig_is_exactly_as_before() -> void:
	var other := _make_rig(Vector3(3, 0, 2))
	var control_stage: PixelStage = other[0]
	var control: CameraRig = other[1]
	var control_target: Node3D = other[2]
	rig.cine = _pose(Vector3(9, 1, 9), 90.0, -20.0, 3.0)
	rig.cine_weight = 0.0
	for i in 30:
		var at := Vector3(3.0 + i * 0.13, 0.0, 2.0 - i * 0.07)
		target.position = at
		control_target.position = at
		await frames(1)
		assert_true(rig.camera.global_transform == control.camera.global_transform, "the camera is the same on frame %d" % i)
		assert_true(rig.global_transform == control.global_transform, "and the rig")
		assert_eq(rig.camera.size, control.camera.size)
		assert_eq(stage.subpixel, control_stage.subpixel, "and the sub-pixel")
		if i == 0:
			assert_eq(rig.camera.size, CameraRig.ORTHO_SIZE)


func test_full_weight_looks_at_the_pose_and_zoom_two_halves_the_view() -> void:
	var aim := Vector3(5.3, 1.0, -2.7)
	rig.cine = _pose(aim, 0.0, -40.0, 2.0)
	rig.cine_weight = 1.0
	await frames(2)
	assert_near(rig.camera.size, CameraRig.ORTHO_SIZE / 2.0, 1e-6, "zoom 2 halves the view")
	var middle := rig.camera.unproject_position(aim)
	# The snap moves the camera by up to half a picture pixel each way; one picture pixel is 1/zoom of a texel.
	assert_true(absf(middle.x - 321.0) <= 0.51 and absf(middle.y - 181.0) <= 0.51, "the aim is in the middle of the picture: %s" % middle)
	var yawed := _pose(aim, 90.0, -40.0, 1.0)
	rig.cine = yawed
	await frames(2)
	middle = rig.camera.unproject_position(aim)
	assert_true(absf(middle.x - 321.0) <= 0.51 and absf(middle.y - 181.0) <= 0.51, "and so it is when the camera is turned: %s" % middle)
	assert_near(rad_to_deg(rig.camera.global_basis.get_euler(EULER_ORDER_YXZ).y), 90.0, 1e-3)


func test_at_a_whole_zoom_the_camera_sits_on_the_zoomed_pixel_grid() -> void:
	for zoom: int in [1, 2, 3, 4]:
		rig.cine = _pose(Vector3(1.234, 0.7, -3.217), 35.0, -30.0, float(zoom))
		rig.cine_weight = 1.0
		await frames(2)
		var b := rig.camera.global_basis
		var grid: float = PixelSnap.TEXEL / zoom
		var gx: float = rig.camera.global_position.dot(b.x) / grid
		var gy: float = rig.camera.global_position.dot(b.y) / grid
		assert_near(gx, roundf(gx), 1e-3, "x on the grid at zoom %d" % zoom)
		assert_near(gy, roundf(gy), 1e-3, "y on the grid at zoom %d" % zoom)
		assert_true(absf(stage.subpixel.x) <= 0.5 + 1e-4 and absf(stage.subpixel.y) <= 0.5 + 1e-4, "the loss is under half a pixel at zoom %d" % zoom)
		assert_near(rig.camera.size, CameraRig.ORTHO_SIZE / zoom, 1e-6)


func test_yaw_is_the_gameplay_yaw_through_a_glide() -> void:
	rig.cine = _pose(Vector3(1, 1, 1), 90.0)
	for weight in [0.0, 0.5, 1.0]:
		rig.cine_weight = weight
		await frames(2)
		assert_near(rig.yaw(), deg_to_rad(CameraRig.YAW_DEG), 1e-6, "weight %s" % weight)
	rig.cine_weight = 0.5
	await frames(2)
	assert_true(absf(rig.camera.global_basis.get_euler(EULER_ORDER_YXZ).y) > 0.1, "though the picture has turned")


func test_the_weight_returning_to_zero_restores_the_gameplay_pose_exactly() -> void:
	var other := _make_rig(Vector3(3, 0, 2))
	var fresh_stage: PixelStage = other[0]
	var fresh: CameraRig = other[1]
	rig.cine = _pose(Vector3(8, 1, -4), 90.0, -25.0, 3.0)
	rig.cine_weight = 1.0
	await frames(3)
	rig.cine_weight = 0.0
	await frames(3)
	assert_true(_close(rig.camera.global_transform, fresh.camera.global_transform), "the camera is the fresh rig's")
	assert_true(_close(rig.global_transform, fresh.global_transform), "no leftover rotation")
	assert_eq(rig.camera.size, fresh.camera.size, "no leftover size")
	assert_true(stage.subpixel.distance_to(fresh_stage.subpixel) < 1e-3, "no leftover offset")
	assert_true(rig.basis == fresh.basis, "the very same basis")


func test_focus_follows_the_cine_focus_point() -> void:
	var aim := Vector3(0, 1, 0)
	var pose := _pose(aim, 20.0, -40.0, 2.0)
	pose.focus = Vector3(4, 1, 3)
	rig.cine = pose
	rig.cine_weight = 1.0
	await frames(2)
	var view := -rig.camera.global_basis.z
	var expected := (pose.focus - rig.camera.global_position).dot(view)
	assert_near(rig.focus_distance(), expected, 1e-4, "the distance to the focus point along the view")
	var material := rig.post_quad.material_override as ShaderMaterial
	assert_near(float(material.get_shader_parameter(&"focus")), expected, 1e-4, "which is what the post quad is given")
	pose.focus = Vector3(-6, 1, -5)
	await frames(2)
	assert_true(absf(rig.focus_distance() - expected) > 0.5, "and a different point is a different distance")
