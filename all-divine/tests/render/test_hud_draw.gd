extends TestCase
## What the Hud really draws (xvfb, gl_compatibility): the HUD viewport's own picture (640x360, transparent) is read back and the
## pixels each element should paint are checked at the places the Hud's queries say: the lock reticle, the finisher prompt, each
## unblockable icon's glyph (sweep, thrust, grab) and the wave pips. A drawing that is left out leaves its pixels transparent
## and fails here, which no query can tell.

const MAIN := "res://main/main.tscn"
const TOLERANCE := 0.02


func after_each() -> void:
	Game.reset()


# A fight set up to show everything: foe 0 locked on, broken and in reach (reticle and finisher prompt); foe 1 apart, its icon set
# by hand to the shape each test asks for.
func _fight() -> Dictionary:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().start_wave(3)
	var foes := main.arena().enemies()
	for foe in foes:
		foe.set_brain(Brain.new())
	var player := main.player
	player.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 6.0)))
	foes[0].place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, 0.0, 4.9)))
	foes[1].place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(-4.0, 0.0, 3.0)))
	main.camera_rig.snap_now()
	await frames(5)
	player.set_brain(PlayerBrain.new())
	(player.brain as PlayerBrain).lock.target = foes[0]
	foes[0].stats.damage_posture(foes[0].stats.max_posture)
	foes[0].add_to_group(Actor.FINISHABLE_GROUP)
	return {"main": main, "foes": foes}


func _picture(main: Main) -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	return main.stage.hud.get_texture().get_image()


func _is(img: Image, at: Vector2i, want: Color) -> bool:
	if at.x < 0 or at.y < 0 or at.x >= img.get_width() or at.y >= img.get_height():
		return false
	var c := img.get_pixelv(at)
	return c.a > 0.8 and absf(c.r - want.r) < TOLERANCE and absf(c.g - want.g) < TOLERANCE and absf(c.b - want.b) < TOLERANCE


func _clear(img: Image, at: Vector2i) -> bool:
	return img.get_pixelv(at).a < 0.05


func test_the_reticle_is_a_rose_diamond_at_the_locked_foes_head() -> void:
	var run := await _fight()
	var main: Main = run["main"]
	await frames(2)
	var img := await _picture(main)
	var at: Vector2i = main.hud.reticle_at()
	for offset in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 1), Vector2i(-1, -1)]:
		assert_true(_is(img, at + offset, Hud.ROSE), "the reticle is rose at %s (%s)" % [at + offset, img.get_pixelv(at + offset)])
	for corner in [Vector2i(2, 2), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2)]:
		assert_false(_is(img, at + corner, Hud.ROSE), "and a diamond has no corner at %s" % corner)


func test_the_finisher_prompt_is_a_rose_glyph_with_a_bright_heart_over_the_head() -> void:
	var run := await _fight()
	var main: Main = run["main"]
	await frames(2)
	var img := await _picture(main)
	var at: Vector2i = main.hud.prompt_at()
	assert_true(_is(img, at, Hud.WHITE), "the prompt's heart is bright at %s (%s)" % [at, img.get_pixelv(at)])
	for offset in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(2, 2)]:
		assert_true(_is(img, at + offset, Hud.ROSE), "rose at %s" % (at + offset))
	assert_true(_clear(img, at + Vector2i(5, 0)) or not _is(img, at + Vector2i(5, 0), Hud.ROSE), "and nothing rose beyond it")


func test_each_unblockable_icon_is_drawn_cell_for_cell() -> void:
	for shape: int in Hud.ICON_CELLS:
		var run := await _fight()
		var main: Main = run["main"]
		var foe: Actor = run["foes"][1]
		var fx := foe.get_node("ActorFx") as ActorFx
		fx.icon_shape = shape
		await frames(2)
		var img := await _picture(main)
		var icons: Array[Dictionary] = main.hud.icons()
		assert_eq(icons.size(), 1, "one icon")
		var rect: Rect2i = icons[0].rect
		var rows: Array = Hud.ICON_CELLS[shape]
		var drawn := 0
		var wrong := 0
		for y in 9:
			for x in 9:
				var cell := rect.position + Vector2i(x, y)
				if (rows[y] as String)[x] == "X":
					if _is(img, cell, ActorFx.TUNING.icon_color):
						drawn += 1
					else:
						wrong += 1
		var filled := 0
		for row: String in rows:
			filled += row.count("X")
		assert_eq(drawn, filled, "shape %d: every filled cell is rose (%d wrong)" % [shape, wrong])
		# The glyph's outline: a dark pixel one beyond a filled cell that is not itself filled (the row above the first X).
		var top_x := (rows[0] as String).find("X")
		if top_x >= 0:
			assert_true(_is(img, rect.position + Vector2i(top_x, -1), Hud.INK), "shape %d: with its dark outline above it" % shape)
		main.queue_free()
		await frames(1)


func test_the_wave_pips_are_drawn_cleared_on_and_coming() -> void:
	var run := await _fight()
	var main: Main = run["main"]
	main.arena().start_wave(2)  # waves 0 and 1 are behind it
	await frames(2)
	var img := await _picture(main)
	var states: Array[int] = main.hud.pip_states()
	assert_eq(states, [Hud.Pip.CLEARED, Hud.Pip.CLEARED, Hud.Pip.ON, Hud.Pip.COMING, Hud.Pip.COMING, Hud.Pip.COMING] as Array[int])
	var width := states.size() * Hud.PIP + (states.size() - 1) * Hud.PIP_GAP
	var x0 := (640 - width) / 2
	for i in states.size():
		var centre := Vector2i(x0 + i * (Hud.PIP + Hud.PIP_GAP) + Hud.PIP / 2, Hud.PIP_TOP + Hud.PIP / 2)
		match states[i]:
			Hud.Pip.CLEARED:
				assert_true(_is(img, centre, Hud.ROSE), "pip %d (cleared) is rose" % i)
			Hud.Pip.ON:
				assert_true(_is(img, centre, Hud.GOLD), "pip %d (on) is gold" % i)
			_:
				assert_true(_is(img, centre, Color(0.35, 0.25, 0.38)) or img.get_pixelv(centre).a > 0.8, "pip %d (coming) is drawn dim" % i)
				assert_false(_is(img, centre, Hud.ROSE) or _is(img, centre, Hud.GOLD), "and not lit")
