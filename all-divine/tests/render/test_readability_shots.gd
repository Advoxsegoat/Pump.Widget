extends TestCase
## The readability pass as drawn (xvfb, gl_compatibility): a tell never tints or covers the body's interior. With a Knuckle
## frozen mid-tell in front of the camera, the frame with its aura is compared with the frame without it: pixels on the body's
## edge change and pixels inside it (the silhouette eroded by 2 px) change in at most 2% of cases, for the parry rim (a glint
## tell) and for the perilous rim; and the ground wave changes no pixel of any body above its feet line.
##
## The frames are the World viewport's own image (642x362, the picture and its margin), taken one after another with both
## fighters frozen (hit-stop holds their poses), their shadows off and the waves held still. Each tell's frame is also saved
## to out/shots/ at 640x360 and, with the HUD and the grade, at the window's scale, for a person to look at.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(1920, 1080)
## The two bodies stand side by side in front of the camera: the foe to the west, Abarax to the east, 2.4 m apart.
const FOE_AT := Vector3(-1.2, 0.0, 6.0)
const PLAYER_AT := Vector3(1.2, 0.0, 6.0)
## A pixel counts as changed when its channels differ by more than this, summed.
const CHANGED := 0.02
## How far inside the silhouette the interior starts, and how far outside the edge band reaches, in pixels.
const MARGIN_PX := 2
const MAX_INTERIOR_CHANGED := 0.02
const MIN_EDGE_CHANGED := 40


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


# The yard with the foe and Abarax in front of the camera, no shadows, the foe playing `move_id` for `frame` frames; both
# frozen then, and the waves held. Returns {main, foe, player}.
func _scene(move_id: StringName, frame: int) -> Dictionary:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	for light in main.region.find_children("*", "Light3D", true, false):
		(light as Light3D).shadow_enabled = false
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), FOE_AT))
	main.player.set_brain(Brain.new())
	main.player.place(Transform3D(Basis(Vector3.UP, 0.0), PLAYER_AT))
	main.camera_rig.snap_now()
	await frames(3)
	foe.runner.start(Registry.fetch(&"moves", move_id) as MoveData)
	await frames(frame)
	foe.freeze(100000)
	main.player.freeze(100000)
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.set_physics_process(false)
	# The tell's sparks are particles that move from frame to frame: they are not what is measured, and would be noise.
	for spark in get_tree().get_nodes_in_group(ActorFx.GROUP):
		spark.free()
	await _draw()
	return {"main": main, "foe": foe, "player": main.player}


func _draw() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw


func _world(main: Main) -> Image:
	return main.stage.world.get_texture().get_image()


# Whether a pixel differs between two images, by more than CHANGED.
func _differs(a: Image, b: Image, x: int, y: int) -> bool:
	var p := a.get_pixel(x, y)
	var q := b.get_pixel(x, y)
	return absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > CHANGED


# The box of the World image around the foot of a body, wide enough for the body and the rings.
func _box(main: Main, actor: Actor, image: Image) -> Rect2i:
	var feet := main.camera_rig.camera.unproject_position(actor.global_position)
	return Rect2i(int(feet.x) - 110, int(feet.y) - 110, 220, 150).intersection(Rect2i(Vector2i.ZERO, image.get_size()))


# The pixels of `box` where `with` differs from `without`, as a set of Vector2i -> true.
func _diff(with: Image, without: Image, box: Rect2i) -> Dictionary:
	var changed := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if _differs(with, without, x, y):
				changed[Vector2i(x, y)] = true
	return changed


# The set `mask` shrunk by `r` pixels (a pixel stays when every pixel within r of it is in the set), or grown by `r`.
func _eroded(mask: Dictionary, r: int) -> Dictionary:
	var kept := {}
	for p: Vector2i in mask:
		var inside := true
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if not mask.has(p + Vector2i(dx, dy)):
					inside = false
					break
			if not inside:
				break
		if inside:
			kept[p] = true
	return kept


func _grown(mask: Dictionary, r: int) -> Dictionary:
	var grown := {}
	for p: Vector2i in mask:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				grown[p + Vector2i(dx, dy)] = true
	return grown


# The foe's silhouette: where hiding its body changes the frame (aura and wave off, no shadows).
func _silhouette(main: Main, actor: Actor, reference: Image) -> Dictionary:
	actor.rig.visible = false
	await _draw()
	var hidden := _world(main)
	actor.rig.visible = true
	return _diff(reference, hidden, _box(main, actor, reference))


func _save(main: Main, name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	# The picture at 640x360: the World image less its one-pixel margin.
	var world := _world(main)
	var picture := world.get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))
	assert_eq(picture.save_png(dir.path_join("readability_%s_640.png" % name)), OK)
	# And the window as the game shows it, HUD and grade and all.
	assert_eq(get_viewport().get_texture().get_image().save_png(dir.path_join("readability_%s_window.png" % name)), OK)


# Checks one tell's rim: frame `frame` of `move_id` with its aura against the same frame without it.
func _check_rim(move_id: StringName, frame: int, name: String, color: Color) -> void:
	var run := await _scene(move_id, frame)
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	assert_true(foe.rig.aura_active(), "the aura is on mid-tell (%s frame %d)" % [move_id, frame])
	assert_eq(foe.rig.aura_color(), color)
	assert_true(foe.rig.aura_level() > 0.4, "and strong (%.2f)" % foe.rig.aura_level())
	# The waves are not what is measured here: take them away from the frames altogether.
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.visible = false
	await _draw()
	var with_aura := _world(main)
	_save(main, name)
	var level := foe.rig.aura_level()
	foe.rig.clear_aura()
	await _draw()
	var without := _world(main)
	var box := _box(main, foe, with_aura)
	var changed := _diff(with_aura, without, box)
	var body := await _silhouette(main, foe, without)
	assert_true(body.size() > 300, "the foe's silhouette is %d pixels" % body.size())
	var interior := _eroded(body, MARGIN_PX)
	var inside_changed := 0
	for p: Vector2i in changed:
		if interior.has(p):
			inside_changed += 1
	var band := _grown(body, MARGIN_PX)
	var edge_changed := 0
	for p: Vector2i in changed:
		if band.has(p) and not interior.has(p):
			edge_changed += 1
	assert_true(edge_changed >= MIN_EDGE_CHANGED, "%s: pixels on the body's edge change (%d, at strength %.2f)" % [name, edge_changed, level])
	assert_true(float(inside_changed) <= MAX_INTERIOR_CHANGED * interior.size(),
			"%s: %d of the %d interior pixels changed (at most %d%% may)" % [name, inside_changed, interior.size(), roundi(MAX_INTERIOR_CHANGED * 100)])
	assert_true(changed.size() - edge_changed - inside_changed <= 2, "%s: and nothing far from the body changed (%d pixels)" % [name, changed.size() - edge_changed - inside_changed])


func test_the_parry_rim_is_on_the_edge_and_not_in_the_body() -> void:
	await _check_rim(&"knuckle_jab", 15, "parry_rim", Color("bfe6ff"))


func test_the_heavy_attack_rim_is_on_the_edge_and_not_in_the_body() -> void:
	await _check_rim(&"knuckle_hook", 34, "heavy_rim", Color("bfe6ff"))


func test_the_perilous_rim_is_on_the_edge_and_not_in_the_body() -> void:
	await _check_rim(&"knuckle_sweep", 25, "perilous_rim", Color("e8607e"))


func test_the_ground_wave_changes_no_pixel_of_a_body_above_its_feet() -> void:
	var run := await _scene(&"knuckle_sweep", 10)
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	var player: Actor = run["player"]
	var waves := get_tree().get_nodes_in_group(GroundWave.GROUP)
	assert_eq(waves.size(), 1, "the perilous wave is out")
	foe.rig.clear_aura()
	await _draw()
	var with_wave := _world(main)
	_save(main, "perilous_wave")
	for wave in waves:
		wave.visible = false
	await _draw()
	var without := _world(main)
	var box := _box(main, foe, with_wave).merge(_box(main, player, with_wave))
	var changed := _diff(with_wave, without, box)
	assert_true(changed.size() > 400, "the wave is something to see (%d pixels)" % changed.size())
	for who: Actor in [foe, player]:
		var body := await _silhouette(main, who, without)
		assert_true(body.size() > 300, "%s's silhouette is %d pixels" % [who.name, body.size()])
		var feet_y := int(main.camera_rig.camera.unproject_position(who.global_position).y)
		# (Less the silhouette's own outermost pixel: the screen look's outline draws a halo there, which is ground.)
		var wrong := 0
		for p: Vector2i in _eroded(body, 1):
			if p.y < feet_y - 2 and changed.has(p):
				wrong += 1
		assert_eq(wrong, 0, "%s: the wave changes no pixel of the body above its feet line (%d)" % [who.name, wrong])


func test_abarax_parry_burst_is_a_rim_and_a_ring_and_no_tint() -> void:
	var run := await _scene(&"knuckle_jab", 2)
	var main: Main = run["main"]
	var player: Actor = run["player"]
	var foe: Actor = run["foe"]
	foe.rig.clear_aura()
	foe.get_node("ActorFx").end_tell()
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.free()
	var result := HitResult.new()
	result.outcome = HitResult.Outcome.PARRIED
	var event := HitEvent.new()
	event.target = player
	event.profile = HitProfile.new()
	event.point = player.global_position + Vector3(0.4, 1.2, 0.3)
	player.got_hit.emit(result, event)
	player.rig.tick(2.0 / 60)  # two frames into it: the rim has risen
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.set_physics_process(false)
	assert_true(player.rig.aura_level() > 0.5, "the burst is strong (%.2f)" % player.rig.aura_level())
	await _draw()
	_save(main, "parry_burst")
	for wave in get_tree().get_nodes_in_group(GroundWave.GROUP):
		wave.visible = false
	await _draw()
	var with_aura := _world(main)
	player.rig.clear_aura()
	await _draw()
	var without := _world(main)
	var changed := _diff(with_aura, without, _box(main, player, with_aura))
	var body := await _silhouette(main, player, without)
	var interior := _eroded(body, MARGIN_PX)
	var inside_changed := 0
	for p: Vector2i in changed:
		if interior.has(p):
			inside_changed += 1
	assert_true(changed.size() >= MIN_EDGE_CHANGED, "the rim shows on his edge (%d pixels)" % changed.size())
	assert_true(float(inside_changed) <= MAX_INTERIOR_CHANGED * interior.size(), "%d of %d interior pixels changed" % [inside_changed, interior.size()])
