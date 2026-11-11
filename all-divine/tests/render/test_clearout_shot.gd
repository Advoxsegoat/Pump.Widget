extends TestCase
## A clear-out in the game's picture (xvfb, gl_compatibility): Abarax in the training yard with three Knuckles round him, his
## wave at Flurry. Saved to out/shots/counters/ for a person to look at: before it, as its ring spreads from his feet, and 20
## frames after the blow, when the room it made shows. The foes must stand clear of him then, and the ring is two metres across, on the
## ground at his feet.

const MAIN := "res://main/main.tscn"
const DIR := "out/shots/counters"
const SIZE := Vector2i(1920, 1080)
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
## The wave's blow starts on its frame 14: the ring is shown then, and the picture after is 20 frames on.
const BLOW := 14
const AFTER := 20


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func _shoot(name_: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://").path_join(DIR).path_join(name_ + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(img.save_png(path), OK, "saved %s" % path)


func test_a_clear_out_among_three_knuckles() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().clear_foes()
	main.arena().automatic = false
	var player := main.player
	player.set_brain(Brain.new())
	var at := Vector3(0.0, 0.0, 2.0)
	player.place(Transform3D(Basis(Vector3.UP, PI), at))
	var foes: Array[Actor] = []
	for offset: Vector3 in [Vector3(-1.2, 0, -0.8), Vector3(0.0, 0.0, -1.3), Vector3(1.2, 0.0, -0.8)]:
		var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
		foe.def = load(KNUCKLE_1) as ActorDef
		foe.set_brain(Brain.new())
		foe.position = at + offset
		main.region.add_child(foe)
		foe.place(Transform3D(Basis(Vector3.UP, 0.0), at + offset))
		foes.append(foe)
	for i in 7:
		player.chain.link(false, 0)
	Melee.slow(0, 1.0)  # the way into Flurry slows the fight (ChainFx); this one is timed to the frame
	main.camera_rig.snap_now()
	await frames(30)
	await _shoot("clearout_before")
	var from: Array[Vector3] = []
	for foe in foes:
		from.append(foe.global_position)
	player.runner.start(Registry.fetch(&"moves", &"clear_wave") as MoveData)
	while player.runner.time < (BLOW + 1) / 60.0:
		await frames(1)
	var waves := get_tree().get_nodes_in_group(GroundWave.GROUP)
	assert_eq(waves.size(), 1, "the wave's ring is shown from his feet at its blow")
	if waves.size() == 1:
		var ring := waves[0] as GroundWave
		assert_near(ring.max_radius, 2.0, 1e-4, "two metres across")
		assert_vec_near(ring.global_position, Vector3(player.global_position.x, GroundWave.LIFT, player.global_position.z), 0.05, "from his feet, on the ground")
	await _shoot("clearout_ring")
	await frames(AFTER - 3)
	await _shoot("clearout_after")
	for i in foes.size():
		var far := Vector2(foes[i].global_position.x - player.global_position.x, foes[i].global_position.z - player.global_position.z).length()
		assert_true(far > 2.9, "Knuckle %d stands %.2f m from him 20 frames after the blow (it started %.2f m off)" % [i, far,
				Vector2(from[i].x - at.x, from[i].z - at.z).length()])
