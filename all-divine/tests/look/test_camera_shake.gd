extends TestCase
## Camera shake (CameraRig.shake): trauma that decays, an offset that grows with its square, along smooth noise,
## put into the camera's wanted place before the texel snap, so the picture still moves in whole texels. Headless.

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


# How far the camera is from `calm` along its own right and up, in metres.
func _off(calm: Vector3) -> Vector2:
	var b := rig.camera.global_basis
	var d := rig.camera.global_position - calm
	return Vector2(d.dot(b.x), d.dot(b.y))


func test_the_rig_is_found_in_its_group() -> void:
	assert_eq(CameraRig.GROUP, &"camera_rig")
	assert_eq(get_tree().get_first_node_in_group(&"camera_rig"), rig, "others find the one camera there")


func test_trauma_is_added_and_clamped_to_one() -> void:
	assert_eq(rig.trauma, 0.0)
	rig.shake(0.3)
	rig.shake(0.3)
	assert_near(rig.trauma, 0.6, 1e-6, "shakes add up")
	rig.shake(0.9)
	assert_eq(rig.trauma, 1.0, "to 1 and no more")
	rig.shake(-0.5)
	assert_eq(rig.trauma, 1.0, "a negative strength takes nothing off")


func test_shake_is_bounded_decays_and_stays_on_the_texel_grid() -> void:
	rig.snap_now()
	var calm := rig.camera.global_position
	rig.shake(1.0)
	var bound_of_last := 1.0
	var widest := 0.0
	var time := 0.0
	var trauma_at := {}  # the frame -> trauma after it, to see it fall at 2.5 a second
	for i in 40:
		await get_tree().process_frame
		var off := _off(calm)
		# The camera is snapped to the grid, so it is within half a texel (each way) of where it wanted to be: the
		# shake of the trauma it had this frame, which is no more than last frame's.
		var bound := CameraRig.MAX_SHAKE * bound_of_last * bound_of_last + PixelSnap.TEXEL
		assert_true(absf(off.x) <= bound and absf(off.y) <= bound, "frame %d: %s is within %s of calm" % [i, off, bound])
		widest = maxf(widest, maxf(absf(off.x), absf(off.y)))
		var b := rig.camera.global_basis
		var gx := rig.camera.global_position.dot(b.x) / PixelSnap.TEXEL
		var gy := rig.camera.global_position.dot(b.y) / PixelSnap.TEXEL
		assert_near(gx, roundf(gx), 1e-3, "x on the texel grid, frame %d" % i)
		assert_near(gy, roundf(gy), 1e-3, "y on the texel grid, frame %d" % i)
		trauma_at[i] = rig.trauma
		bound_of_last = rig.trauma
	assert_true(widest > 0.1, "at full trauma it really moves (%s m)" % widest)
	assert_true(widest <= CameraRig.MAX_SHAKE + PixelSnap.TEXEL, "and never past the 0.25 m of full trauma")
	assert_eq(CameraRig.MAX_SHAKE, 0.25)
	assert_eq(CameraRig.TRAUMA_DECAY, 2.5)
	assert_eq(rig.trauma, 0.0, "the shake is over after 0.4 s (40 frames is 0.67)")
	assert_vec_near(rig.camera.global_position, calm, 1e-5, "and the camera is back where it was")
	assert_eq(rig.shake_offset(), Vector2.ZERO)


func test_trauma_falls_by_two_and_a_half_a_second() -> void:
	rig.shake(1.0)
	for i in 12:  # --fixed-fps 60: 12 frames are 0.2 s
		await get_tree().process_frame
	assert_near(rig.trauma, 0.5, 0.05, "half the trauma goes in 0.2 s")
	for i in 20:
		await get_tree().process_frame
	assert_eq(rig.trauma, 0.0, "and it is gone by 0.4 s, and stays 0 (it does not go below)")


func test_the_offset_grows_with_the_square_of_the_trauma_along_smooth_noise() -> void:
	var full := 0.0
	var half := 0.0
	var previous := CameraRig.shake_at(1.0, 0.0)
	var biggest_step := 0.0
	for i in 6000:
		var t := i / 600.0
		var at_full := CameraRig.shake_at(1.0, t)
		full = maxf(full, at_full.length())
		half = maxf(half, CameraRig.shake_at(0.5, t).length())
		assert_vec_near(Vector3(CameraRig.shake_at(0.5, t).x, CameraRig.shake_at(0.5, t).y, 0.0),
				Vector3(at_full.x, at_full.y, 0.0) * 0.25, 1e-6, "half the trauma is a quarter of the offset, at the same moment")
		biggest_step = maxf(biggest_step, (at_full - previous).length())
		previous = at_full
	assert_true(full > 0.15 and full <= CameraRig.MAX_SHAKE + 1e-6, "full trauma shakes up to 0.25 m: %s" % full)
	assert_near(half, full * 0.25, 1e-6, "so half the trauma is a quarter of the shake")
	assert_true(biggest_step < 0.04, "smooth noise: no jump between samples a tenth of a frame apart (the biggest was %s m)" % biggest_step)
	assert_eq(CameraRig.shake_at(0.0, 3.0), Vector2.ZERO, "no trauma, no shake")


func test_with_no_trauma_the_view_is_the_follow() -> void:
	target.position = Vector3(3.3, 0, -1.7)
	target.reset_physics_interpolation()
	rig.snap_now()
	var still := rig.camera.global_position
	for i in 5:
		await get_tree().process_frame
	assert_vec_near(rig.camera.global_position, still, 1e-5, "an unshaken camera is where it always was")
