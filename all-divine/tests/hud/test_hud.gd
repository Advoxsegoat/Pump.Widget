extends TestCase
## The HUD (hud/hud.gd), drawn in the PixelStage's `hud` viewport: the player's bars, a foe's bars, the lock reticle, the
## finisher prompt, the wave pips and the controls. The queries (hp_rect, reticle_at, ...) say what is drawn, in picture
## pixels, and the drawing uses the same, so these test what a player would see.

const MAIN := "res://main/main.tscn"
const MAX_BAR := 120


var _saved_bindings := {}


func before_each() -> void:
	_saved_bindings = Bindings.current()
	Arena.reset_spawn_counts()
	Game.reset()


func after_each() -> void:
	Bindings.apply(_saved_bindings)
	Game.reset()


func _main() -> Main:
	return track((load(MAIN) as PackedScene).instantiate()) as Main


func _press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		get_viewport().push_input(event)


func _foe(main: Main) -> Actor:
	return main.arena().enemies()[0]


func test_the_hud_is_a_transparent_640_by_360_viewport_over_the_world() -> void:
	var main := _main()
	var stage := main.stage
	assert_eq(stage.hud.size, Vector2i(640, 360), "640 x 360")
	assert_true(stage.hud.transparent_bg, "transparent")
	assert_true(main.hud is Hud, "a Hud in it")
	assert_eq(main.hud.get_viewport(), stage.hud, "the Hud is drawn in that viewport")
	assert_eq(stage.hud_view.get_parent(), stage, "drawn by a child of the stage")
	assert_true(stage.hud_view.get_index() > stage.world.get_index() and stage.hud_view.get_index() > stage.hud.get_index(), "after the world and the HUD viewport (so over the world)")
	assert_true(stage.hud_view.material == null, "with no grade of its own")
	assert_true(stage.hud_view.texture == stage.hud.get_texture(), "showing the HUD's picture")
	assert_true(stage.material != null and stage.hud_view.material != stage.material, "and not the stage's final material")


func test_bars_track_the_stats() -> void:
	var main := _main()
	var hud := main.hud
	var stats := main.player.stats
	assert_eq(hud.hp_rect().size.x, 100, "full HP is 1 px per HP: 100 px")
	assert_eq(hud.stamina_rect().size.x, 100, "full stamina: 100 px")
	assert_eq(hud.posture_rect().size, Vector2i.ZERO, "the posture bar is not shown while full")
	assert_true(hud.stamina_rect().position.y > hud.hp_rect().position.y, "stamina is below HP")
	assert_true(hud.posture_rect().position.y <= hud.hp_rect().position.y, "(posture above it)")
	stats.take_damage(25.0)
	assert_eq(hud.hp_rect().size.x, 75, "HP 75: 75 px")
	stats.spend_stamina(40.0)
	assert_eq(hud.stamina_rect().size.x, 60, "stamina 60: 60 px")
	stats.damage_posture(30.0)
	assert_eq(hud.posture_rect().size.x, 70, "posture 70: shown, 70 px")
	assert_true(hud.posture_rect().position.y < hud.hp_rect().position.y, "above the HP bar")
	assert_true(hud.posture_rect().size.y < hud.hp_rect().size.y, "and thinner")
	assert_true(hud.hp_rect().position.x < 20 and hud.hp_rect().position.y > 300, "bottom left")
	# A bar longer than the cap is the cap, and the fill its share of it.
	stats.max_hp = 240.0
	stats.hp = 120.0
	assert_eq(hud.hp_rect().size.x, MAX_BAR / 2, "past 120 HP the bar stops growing: half of 240 is 60 px of 120")
	stats.hp = 0.0
	assert_eq(hud.hp_rect().size.x, 0, "empty")
	stats.hp = 1.0
	assert_true(hud.hp_rect().size.x >= 1, "a sliver is still one pixel")


func test_the_colours_are_rose_and_gold() -> void:
	assert_eq(Hud.ROSE.to_html(false), "e8607e", "HP is rose")
	assert_eq(Hud.GOLD.to_html(false), "e8c170", "stamina is gold")


func test_a_refused_press_blinks_the_stamina_bar_twice() -> void:
	var main := _main()
	var hud := main.hud
	var player := main.player
	await frames(2)
	assert_false(hud.stamina_blink_on(), "not blinking")
	player.stats.spend_stamina(1000.0)
	assert_false(player.stats.can_act(), "exhausted")
	var refusals: Array = []
	player.move_refused.connect(func(m: MoveData, why: StringName) -> void: refusals.append([m.id, why]))
	player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	assert_eq(refusals, [[&"palm_jab", &"stamina"]], "the actor said it refused, and why")
	var seen: Array[bool] = [hud.stamina_blink_on()]
	for i in 10:
		await frames(1)
		seen.append(hud.stamina_blink_on())
	assert_eq(seen, [true, true, false, false, true, true, false, false, false, false, false] as Array[bool],
			"2 frames lit, 2 dark, twice, then done")


func test_a_refused_press_plays_a_cue() -> void:
	var main := _main()
	await frames(2)
	assert_false(Sfx.last_played().has(&"stamina_refused"), "quiet before")
	main.player.stats.spend_stamina(1000.0)
	main.player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	assert_true(Sfx.last_played().has(&"stamina_refused"), "the soft cue sounds")
	assert_true(Registry.ids(&"sounds").has("stamina_refused"), "it is a cue in data/sounds")


func test_an_evaded_blow_does_not_show_the_foes_bars() -> void:
	var main := _main()
	await frames(2)
	var foe := _foe(main)
	var evaded := _hit_result()
	evaded.outcome = HitResult.Outcome.EVADED
	foe.got_hit.emit(evaded, _hit_event(foe))
	assert_eq(main.hud.foe_bars().size(), 0, "a blow that was avoided shows no bars")
	for outcome in [HitResult.Outcome.HIT, HitResult.Outcome.GUARDED, HitResult.Outcome.PARRIED, HitResult.Outcome.CAUGHT]:
		var r := _hit_result()
		r.outcome = outcome
		foe.got_hit.emit(r, _hit_event(foe))
		assert_eq(main.hud.foe_bars().size(), 1, "%s shows them" % HitResult.Outcome.keys()[outcome])
		main.hud._hit_at.erase(foe)


func test_foe_bars_show_while_locked_or_for_three_seconds_after_a_hit() -> void:
	var main := _main()
	var hud := main.hud
	await frames(2)
	var foe := _foe(main)
	assert_eq(hud.foe_bars().size(), 0, "no bars on a foe nobody is looking at")
	# Hit it: the bars show, 24 px wide at most, the posture above the HP.
	foe.got_hit.emit(_hit_result(), _hit_event(foe))
	var bars := hud.foe_bars()
	assert_eq(bars.size(), 1, "a blow shows them")
	if bars.size() == 1:
		assert_eq(bars[0].actor, foe)
		assert_eq((bars[0].hp as Rect2i).size.x, 24, "HP: 24 px at full")
		assert_true((bars[0].posture as Rect2i).position.y < (bars[0].hp as Rect2i).position.y, "posture over HP")
		var head := hud.picture_point(foe.get_global_transform_interpolated().origin + Vector3.UP * foe.def.look_height)
		assert_true((bars[0].hp as Rect2i).position.y < head.y, "over its head")
	foe.stats.take_damage(foe.stats.max_hp / 2.0)
	assert_eq((hud.foe_bars()[0].hp as Rect2i).size.x, 12, "half its HP: 12 px")
	await frames(175)
	assert_eq(hud.foe_bars().size(), 1, "still there 2.9 s on")
	await frames(10)
	assert_eq(hud.foe_bars().size(), 0, "gone after three seconds")
	# Locked on: always.
	(main.player.brain as PlayerBrain).lock.target = foe
	assert_eq(hud.foe_bars().size(), 1, "locked on, they show")
	foe.die()
	assert_eq(hud.foe_bars().size(), 0, "and not on the dead")


func _hit_result() -> HitResult:
	var r := HitResult.new()
	r.outcome = HitResult.Outcome.HIT
	return r


func _hit_event(foe: Actor) -> HitEvent:
	var e := HitEvent.new()
	e.target = foe
	e.profile = HitProfile.new()
	e.point = foe.global_position + Vector3.UP
	return e


func test_reticle_follows_the_lock_target() -> void:
	var main := _main()
	var hud := main.hud
	await frames(2)
	assert_eq(hud.reticle_at(), null, "no reticle without a lock")
	var foe := _foe(main)
	(main.player.brain as PlayerBrain).lock.target = foe
	var at: Variant = hud.reticle_at()
	assert_true(at is Vector2i, "a reticle")
	var head := hud.picture_point(foe.get_global_transform_interpolated().origin + Vector3.UP * foe.def.look_height)
	assert_eq(Vector2(at as Vector2i), head, "at the foe's projected head point")
	foe.place(Transform3D(Basis(), foe.global_position + Vector3(2.0, 0.0, 0.0)))
	var moved: Variant = hud.reticle_at()
	assert_true((moved as Vector2i).x > (at as Vector2i).x, "and it follows the foe (%s -> %s)" % [at, moved])
	var other := main.arena().enemies()[0]
	main.arena().start_wave(1)
	var second := main.arena().enemies().filter(func(a: Actor) -> bool: return a != other)[0] as Actor
	(main.player.brain as PlayerBrain).lock.target = second
	var switched: Variant = hud.reticle_at()
	assert_eq(Vector2((switched as Vector2i)), hud.picture_point(second.get_global_transform_interpolated().origin + Vector3.UP * second.def.look_height), "a switched lock moves it")
	(main.player.brain as PlayerBrain).lock.target = null
	assert_eq(hud.reticle_at(), null, "let go, it goes")


func test_prompt_shows_only_for_a_finishable_foe_in_reach() -> void:
	var main := _main()
	var hud := main.hud
	var player := main.player
	await frames(2)
	var foe := _foe(main)
	assert_eq(hud.prompt_at(), null, "no prompt for a foe with its posture whole")
	# Break the foe's posture and stand it in front of Abarax, facing him.
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), player.global_position + Vector3(0, 0, -1.2)))
	foe.stats.damage_posture(1000.0)
	foe.add_to_group(Actor.FINISHABLE_GROUP)
	player.snap_facing(PI)
	assert_true(player.finishable_target() == foe, "the foe is finishable")
	var at: Variant = hud.prompt_at()
	assert_true(at is Vector2i, "the prompt shows")
	var head := hud.picture_point(foe.get_global_transform_interpolated().origin + Vector3.UP * foe.def.look_height)
	assert_true((at as Vector2i).y < head.y, "over the foe's head (%s vs %s)" % [at, head])
	assert_true(absi((at as Vector2i).x - int(head.x)) <= 1, "on its line")
	foe.got_hit.emit(_hit_result(), _hit_event(foe))
	var bars := hud.foe_bars()
	assert_eq(bars.size(), 1, "the broken foe shows its bars")
	assert_true((bars[0].posture as Rect2i).end.y < (at as Vector2i).y - 3, "above the prompt, not over it")
	# Out of reach: no prompt.
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), player.global_position + Vector3(0, 0, -4.0)))
	assert_eq(hud.prompt_at(), null, "too far: none")
	# In reach but not broken: none.
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), player.global_position + Vector3(0, 0, -1.2)))
	foe.remove_from_group(Actor.FINISHABLE_GROUP)
	assert_eq(hud.prompt_at(), null, "not reeling: none")


func test_the_wave_shows_as_pips() -> void:
	var main := _main()
	var hud := main.hud
	assert_eq(hud.pip_states(), [Hud.Pip.ON, Hud.Pip.COMING, Hud.Pip.COMING, Hud.Pip.COMING, Hud.Pip.COMING, Hud.Pip.COMING, Hud.Pip.COMING, Hud.Pip.COMING] as Array[int], "eight waves, the first on")
	_foe(main).die()
	assert_eq(hud.pip_states()[0], Hud.Pip.CLEARED, "the first cleared")
	await frames(190)
	assert_eq(hud.pip_states().slice(0, 3), [Hud.Pip.CLEARED, Hud.Pip.ON, Hud.Pip.COMING] as Array[int], "then the second on")


func test_hud_is_not_shifted_by_the_subpixel() -> void:
	var main := _main()
	var stage := main.stage
	var hud := main.hud
	await frames(3)
	var view_before := Rect2(stage.hud_view.position, stage.hud_view.size)
	var window := Vector2i(stage.size)
	assert_eq(view_before, Rect2(PixelStage.layout(window)), "the HUD's picture is exactly the world's layout rect, whole pixels")
	(main.player.brain as PlayerBrain).lock.target = _foe(main)
	stage.subpixel = Vector2.ZERO
	var plain: Vector2i = hud.reticle_at()
	stage.subpixel = Vector2(0.4, -0.3)
	await frames(1)
	assert_eq(Rect2(stage.hud_view.position, stage.hud_view.size), view_before, "a sub-pixel shift does not move the HUD's picture")
	assert_eq(stage.hud.size, Vector2i(640, 360))
	var shifted: Vector2i = hud.reticle_at()
	assert_true(absi(shifted.x - plain.x) <= 1 and absi(shifted.y - plain.y) <= 1, "what it points at stays within a pixel (%s, %s)" % [plain, shifted])
	assert_eq(Vector2(shifted), Vector2(shifted).round(), "on whole picture pixels")
	# The final material shifts the world's draw; the HUD view has none.
	assert_true(stage.hud_view.material == null)
	# The hud view's rect at another window scale is that scale's layout.
	var bigger := Vector2i(1280, 720)
	stage.size = Vector2(bigger)
	await get_tree().process_frame
	assert_eq(Rect2(stage.hud_view.position, stage.hud_view.size), Rect2(PixelStage.layout(bigger)), "at 2x too")


func test_the_controls_come_from_the_bindings_and_f1_hides_them() -> void:
	var main := _main()
	var hud := main.hud
	var text := hud.controls_text()
	for part in ["LMB", "RMB", "Space", "Tab", "RB", "RT", "LB", "Esc"]:
		assert_true(text.contains(part), "the controls name %s: %s" % [part, text])
	var rebound: Dictionary = {&"guard": [Bindings.event_from_data({"type": "key", "code": KEY_Z})]}
	Bindings.apply(rebound)
	assert_true(hud.controls_text().contains("Z"), "a rebound key shows")
	assert_true(hud.hints_visible, "the list starts shown")
	hud.advance(7.0)
	assert_true(hud.hints_visible, "still shown at 7 s")
	hud.advance(2.0)
	assert_false(hud.hints_visible, "gone after 8 s")
	_press_key(KEY_F1)
	assert_true(hud.hints_visible, "F1 shows it again")
	hud.advance(20.0)
	assert_true(hud.hints_visible, "and then it stays until F1 hides it")
	_press_key(KEY_F1)
	assert_false(hud.hints_visible, "F1 hides it")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_BACK
	back.pressed = true
	main.get_viewport().push_input(back)
	assert_true(hud.hints_visible, "a pad's Select toggles it too")


func test_a_mashed_refused_press_gives_one_cue_and_one_blink_every_eight_frames() -> void:
	var main := _main()
	var hud := main.hud
	var player := main.player
	await frames(2)
	player.stats.spend_stamina(1000.0)
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var cues := 0
	var lit: Array[bool] = []
	for i in 40:
		if i % 2 == 0:
			player.runner.start(jab)  # a press every other frame, refused each time
		lit.append(hud.stamina_blink_on())
		if Sfx.last_played().has(&"stamina_refused"):
			cues += 1
		await frames(1)
	assert_true(cues <= 5 and cues >= 4, "a cue at most every 8 frames (%d in 40 frames)" % cues)
	var pattern := [true, true, false, false, true, true, false, false]
	for i in 40:
		assert_eq(lit[i], pattern[i % 8], "the blink repeats cleanly once per 8 frames (frame %d)" % i)
