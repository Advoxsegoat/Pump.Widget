extends TestCase
## ShotMasks.silhouette (tests/support/shot_masks.gd), as drawn: the pixels a body shows on, and nothing else. In the yard
## a body casts a shadow on the floor beside it; the shadow is not the body.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(640, 360)


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_a_bodys_silhouette_leaves_out_its_shadow() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	main.player.set_brain(Brain.new())
	foe.place(Transform3D(Basis.IDENTITY, Vector3(-1.2, 0.0, 3.0)))
	main.player.place(Transform3D(Basis.IDENTITY, Vector3(1.2, 0.0, 3.0)))
	main.camera_rig.snap_now()
	await frames(30)
	foe.freeze(100000000)
	main.player.freeze(100000000)
	main.camera_rig.snap_now()
	for i in 3:
		await RenderingServer.frame_post_draw
	var feet := Vector2i(main.camera_rig.camera.unproject_position(foe.global_position).round())
	var box := Rect2i(feet.x - 40, feet.y - 80, 80, 100)
	var with_shadows := await ShotMasks.silhouette(main, foe, box)
	for light in main.region.find_children("*", "Light3D", true, false):
		(light as Light3D).shadow_enabled = false
	for i in 3:
		await RenderingServer.frame_post_draw
	var without := await ShotMasks.silhouette(main, foe, box)
	assert_true(without.size() > 200, "the body shows (%d pixels)" % without.size())
	var extra := 0
	for p: Vector2i in with_shadows:
		if not without.has(p):
			extra += 1
	assert_eq(extra, 0, "with the lights casting shadows the silhouette has %d pixels that are not the body's (of %d; the body is %d)" % [
			extra, with_shadows.size(), without.size()])
	assert_eq(with_shadows.size(), without.size(), "the same pixels either way")
