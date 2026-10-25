extends TestCase

func test_layout_for_standard_sizes() -> void:
	for c in [[Vector2i(1920, 1080), 3, Vector2i(0, 0)], [Vector2i(2560, 1440), 4, Vector2i(0, 0)], [Vector2i(3840, 2160), 6, Vector2i(0, 0)]]:
		assert_eq(PixelStage.scale_for(c[0]), c[1])
		assert_eq(PixelStage.layout(c[0]).position, c[2])


func test_layout_for_odd_window_sizes() -> void:
	for c in [[Vector2i(1366, 768), 2, Vector2i(43, 24)], [Vector2i(3440, 1440), 4, Vector2i(440, 0)], [Vector2i(1280, 800), 2, Vector2i(0, 40)], [Vector2i(600, 300), 1, Vector2i(-20, -30)]]:
		assert_eq(PixelStage.scale_for(c[0]), c[1])
		assert_eq(PixelStage.layout(c[0]).position, c[2])
		assert_eq(PixelStage.layout(c[0]).size, Vector2i(640, 360) * c[1])


func test_snap_keeps_depth_and_reports_subpixel() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(-40), 0, 0))
	var p := Vector3(0.3 * PixelSnap.TEXEL, 0, 0)
	assert_vec_near(PixelSnap.snap(p, b), Vector3.ZERO, 1e-6)
	assert_near(PixelSnap.subpixel(p, b).x, 0.3, 1e-4)
	var q := b.z * 3.7
	assert_vec_near(PixelSnap.snap(q, b), q, 1e-6)


func test_draw_offset_signs() -> void:
	assert_eq(PixelStage.draw_offset(Vector2.ZERO, 3), Vector2i(-3, -3))
	assert_eq(PixelStage.draw_offset(Vector2(0.3, 0), 3), Vector2i(-4, -3))
	assert_eq(PixelStage.draw_offset(Vector2(0, 0.5), 4), Vector2i(-4, -2))


# The properties that make the picture stable: the snapped point is on the texel grid along the
# screen axes, and what snap took away is exactly what subpixel reports, in [-0.5, 0.5].
func test_snap_lands_on_grid_and_subpixel_is_the_remainder() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(-40), deg_to_rad(25), 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025
	for i in 200:
		var p := Vector3(rng.randf_range(-50, 50), rng.randf_range(-5, 5), rng.randf_range(-50, 50))
		var s := PixelSnap.snap(p, b)
		assert_near(fposmod(s.dot(b.x) / PixelSnap.TEXEL + 0.5, 1.0), 0.5, 2e-3, "x on grid")
		assert_near(fposmod(s.dot(b.y) / PixelSnap.TEXEL + 0.5, 1.0), 0.5, 2e-3, "y on grid")
		assert_near(s.dot(b.z), p.dot(b.z), 1e-4, "depth kept")
		var sub := PixelSnap.subpixel(p, b)
		assert_true(absf(sub.x) <= 0.5 + 1e-3 and absf(sub.y) <= 0.5 + 1e-3, "subpixel in range")
		assert_near((p - s).dot(b.x) / PixelSnap.TEXEL, sub.x, 1e-3)
		assert_near((p - s).dot(b.y) / PixelSnap.TEXEL, sub.y, 1e-3)


func test_snap_uses_the_texel_it_is_given() -> void:
	var p := Vector3(0.7, 0.4, 0.0)
	assert_vec_near(PixelSnap.snap(p, Basis.IDENTITY, 0.5), Vector3(0.5, 0.5, 0.0), 1e-6)
	assert_near(PixelSnap.subpixel(p, Basis.IDENTITY, 0.5).x, 0.4, 1e-5)
