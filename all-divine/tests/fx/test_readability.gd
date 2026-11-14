extends TestCase
## The readability pass (spec 3.5 and 4.4; data/tuning/readability.tres): what an attack's tell and Abarax's parry show,
## kept off the body's inside. A rim on the silhouette from a tell to its end mark, a ground wave under heavy and perilous
## attacks, the unblockable icon over a perilous attacker's head, and Abarax's rim burst and ring on a parry or catch.
## Each element has a switch in the tuning; one that is off shows nothing.
##
## The fixtures are a clip of Abarax's jab with marks written on it: a tell at frame 2, the blow's hitbox on at 12 and off at
## 16, and (for the second blow) on at 17 and off at 20. The actor's frame k is where a mark at frame k is passed.

const TUNING_PATH := "res://data/tuning/readability.tres"
const BLUE_WHITE := Color("bfe6ff")
const ROSE := Color("e8607e")
const GOLD_WHITE := Color("fff1c8")
const MAIN := "res://main/main.tscn"


func before_each() -> void:
	Arena.reset_spawn_counts()


func after_each() -> void:
	Game.reset()


func _tuning() -> ReadabilityTuning:
	return (load(TUNING_PATH) as ReadabilityTuning).duplicate() as ReadabilityTuning


func _fx(a: Actor) -> ActorFx:
	return a.get_node("ActorFx") as ActorFx


func _waves() -> Array[GroundWave]:
	var found: Array[GroundWave] = []
	for node in get_tree().get_nodes_in_group(GroundWave.GROUP):
		found.append(node as GroundWave)
	return found


func _mark(frame: int, kind: StringName, args := {}) -> Dictionary:
	return {"time": Marks.time_of(frame), "kind": kind, "args": args}


func _profile(perilous: HitProfile.Perilous, hitstop := 3, staggers := false) -> HitProfile:
	var p := HitProfile.new()
	p.perilous = perilous
	p.hitstop_frames = hitstop
	p.staggers = staggers
	p.damage = 5.0
	return p


# An attack move on `a` whose clip carries `marks`, with `profile` as the blow `p`.
func _attack(a: Actor, marks: Array, profile: HitProfile, id := &"fixture") -> MoveData:
	var clip := a.rig.tree.get_animation(&"palm_jab").duplicate(true) as Animation
	clip.length = 1.0
	Marks.write(clip, marks)
	a.rig.tree.get_animation_library(&"").add_animation(id, clip)
	var move := MoveData.new()
	move.id = id
	move.kind = MoveData.Kind.ATTACK
	move.clip = id
	move.root_motion = false
	move.hits = {&"p": profile}
	return move


func _blow_marks(kind: StringName, second_blow := false) -> Array:
	var marks := [_mark(2, &"tell", {"kind": kind}), _mark(12, &"hitbox_on", {"id": &"palm_l", "profile": &"p"}),
			_mark(16, &"hitbox_off", {"id": &"palm_l"})]
	if second_blow:
		marks.append_array([_mark(17, &"hitbox_on", {"id": &"palm_r", "profile": &"p"}), _mark(20, &"hitbox_off", {"id": &"palm_r"})])
	marks.append(_mark(30, &"recovery"))
	return marks


func _fighter(tuning: ReadabilityTuning = null) -> Actor:
	var run := Duel.make(self, [{"frames": 120}], [], 6.0)
	var a: Actor = run["a"]
	if tuning != null:
		_fx(a).tuning = tuning
	return a


# Plays `a` to its frame `frame` and returns whether its aura is on there.
func _aura_at(a: Actor, frame: int) -> bool:
	await Duel.play_to(self, a, frame)
	return a.rig.aura_active()


func test_a_glint_tell_lights_the_rim_blue_white_until_the_blow_begins() -> void:
	var a := _fighter()
	a.runner.start(_attack(a, _blow_marks(&"glint"), _profile(HitProfile.Perilous.NONE)))
	assert_false(await _aura_at(a, 1), "nothing before the tell")
	assert_true(await _aura_at(a, 2), "the tell lights it")
	assert_eq(a.rig.aura_color(), BLUE_WHITE, "blue-white")
	assert_near(a.rig.rim_width_px, 1.5, 1e-6, "a pixel and a half wide")
	var early := a.rig.aura_level()
	assert_true(await _aura_at(a, 11), "still on in the last frame before the blow")
	var late := a.rig.aura_level()
	assert_true(late > early, "strongest in the last frames before it (%.2f at the tell, %.2f at the blow)" % [early, late])
	assert_true(late > 0.95, "nearly full")
	assert_false(await _aura_at(a, 12), "gone at the first hitbox_on")
	assert_eq(a.rig.aura_level(), 0.0)
	assert_eq(a.rig.rim_material().get_shader_parameter(&"rim_strength"), 0.0, "and the shader's strength is 0")
	assert_eq(_waves().size(), 0, "an ordinary blow has no wave")
	assert_eq(_fx(a).icon_shape, HitProfile.Perilous.NONE, "and no icon")


func test_a_perilous_tell_lights_the_rim_rose_until_the_last_hitbox_off() -> void:
	var a := _fighter()
	a.runner.start(_attack(a, _blow_marks(&"perilous", true), _profile(HitProfile.Perilous.SWEEP, 5, true)))
	assert_false(await _aura_at(a, 1))
	assert_true(await _aura_at(a, 2), "the tell lights it")
	assert_eq(a.rig.aura_color(), ROSE, "rose")
	assert_true(await _aura_at(a, 12), "on through the blow's start")
	assert_true(await _aura_at(a, 16), "and through its first hitbox_off")
	assert_true(await _aura_at(a, 19), "to the last")
	assert_false(await _aura_at(a, 20), "gone at the last hitbox_off")
	var material := (a.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override as ShaderMaterial
	assert_near(material.get_shader_parameter(&"flash_amount"), 0.0, 1e-6, "the body is never flashed rose any more")


func test_a_move_cut_off_takes_the_rim_and_the_icon_with_it() -> void:
	var a := _fighter()
	a.runner.start(_attack(a, _blow_marks(&"perilous"), _profile(HitProfile.Perilous.GRAB)))
	assert_true(await _aura_at(a, 5))
	assert_eq(_fx(a).icon_shape, HitProfile.Perilous.GRAB, "the icon's shape is on")
	a.runner.start(Registry.fetch(&"moves", &"flinch") as MoveData)
	assert_false(a.rig.aura_active(), "a flinch ends the rim")
	assert_eq(_fx(a).icon_shape, HitProfile.Perilous.NONE, "and the icon")
	a = _fighter()
	a.runner.start(_attack(a, _blow_marks(&"glint"), _profile(HitProfile.Perilous.NONE)))
	assert_true(await _aura_at(a, 5))
	a.die()
	assert_false(a.rig.aura_active(), "and so does dying")


func test_the_icon_shape_follows_the_answer_and_lives_from_the_tell_to_the_last_hitbox_off() -> void:
	for answer: HitProfile.Perilous in [HitProfile.Perilous.SWEEP, HitProfile.Perilous.THRUST, HitProfile.Perilous.GRAB]:
		var a := _fighter()
		a.runner.start(_attack(a, _blow_marks(&"perilous", true), _profile(answer, 5, true)))
		await Duel.play_to(self, a, 1)
		assert_eq(_fx(a).icon_shape, HitProfile.Perilous.NONE, "no icon before the tell")
		await Duel.play_to(self, a, 2)
		assert_eq(_fx(a).icon_shape, answer, "the icon is the answer's")
		await Duel.play_to(self, a, 19)
		assert_eq(_fx(a).icon_shape, answer, "still there at the second blow")
		await Duel.play_to(self, a, 20)
		assert_eq(_fx(a).icon_shape, HitProfile.Perilous.NONE, "gone at the last hitbox_off")


func test_waves_have_the_radius_their_kind_names_lie_on_the_ground_and_free_themselves() -> void:
	# A perilous attack: 1.8 m.
	var a := _fighter()
	a.runner.start(_attack(a, _blow_marks(&"perilous"), _profile(HitProfile.Perilous.SWEEP, 5, true)))
	await Duel.play_to(self, a, 2)
	var waves := _waves()
	assert_eq(waves.size(), 1, "a wave at the perilous tell")
	assert_near(waves[0].max_radius, 1.8, 1e-6, "1.8 m")
	assert_true(absf(waves[0].global_position.y - GroundWave.LIFT) < 1e-4, "on the ground (%s)" % waves[0].global_position)
	assert_vec_near(Vector3(waves[0].global_position.x, 0, waves[0].global_position.z), Vector3(a.global_position.x, 0, a.global_position.z), 1e-4, "from the attacker's feet")
	assert_eq(waves[0].billboard, false, "lying flat")
	assert_true(waves[0].radius() < 0.1, "it starts small")
	await frames(12)
	assert_true(waves[0].radius() > 1.2 and waves[0].visibility() > 0.9, "half way it has grown (%.2f m) and still shows in full (%.2f)" % [waves[0].radius(), waves[0].visibility()])
	var wave := waves[0]
	await frames(8)
	assert_true(wave.radius() > 1.6 and wave.visibility() < 0.6 and wave.visibility() > 0.0, "then it fades (%.2f)" % wave.visibility())
	await frames(12)
	assert_false(is_instance_valid(wave), "and frees itself after 0.4 s")
	# A heavy attack: 1.1 m, no icon. A light one: none.
	var b := _fighter()
	b.runner.start(_attack(b, _blow_marks(&"glint"), _profile(HitProfile.Perilous.NONE, 5)))
	await Duel.play_to(self, b, 2)
	assert_eq(_waves().size(), 1, "a heavy blow (5 frames of hit-stop) has a wave")
	assert_near(_waves()[0].max_radius, 1.1, 1e-6, "1.1 m")
	assert_eq(_fx(b).icon_shape, HitProfile.Perilous.NONE, "and no icon")
	for stale in _waves():
		stale.queue_free()
	await frames(2)
	var c := _fighter()
	c.runner.start(_attack(c, _blow_marks(&"glint"), _profile(HitProfile.Perilous.NONE, 3, true)))
	await Duel.play_to(self, c, 2)
	assert_eq(_waves().size(), 1, "one that staggers is heavy too")
	for stale in _waves():
		stale.queue_free()
	await frames(2)
	var d := _fighter()
	d.runner.start(_attack(d, _blow_marks(&"glint"), _profile(HitProfile.Perilous.NONE, 4)))
	await Duel.play_to(self, d, 2)
	assert_eq(_waves().size(), 0, "a light blow (4 frames, no stagger) has none")


func test_a_switch_that_is_off_shows_nothing_of_its_element() -> void:
	# parry aura off: no rim on a glint tell.
	var t := _tuning()
	t.parry_aura_on = false
	var a := _fighter(t)
	a.runner.start(_attack(a, _blow_marks(&"glint"), _profile(HitProfile.Perilous.NONE, 5)))
	assert_false(await _aura_at(a, 5), "no parry aura")
	assert_eq(_waves().size(), 1, "(the heavy wave is its own switch)")
	for stale in _waves():
		stale.queue_free()
	await frames(2)
	# heavy wave off.
	t = _tuning()
	t.heavy_wave_on = false
	a = _fighter(t)
	a.runner.start(_attack(a, _blow_marks(&"glint"), _profile(HitProfile.Perilous.NONE, 5)))
	assert_true(await _aura_at(a, 5), "the rim stays")
	assert_eq(_waves().size(), 0, "no heavy wave")
	# perilous elements, one at a time.
	t = _tuning()
	t.perilous_rim_on = false
	a = _fighter(t)
	a.runner.start(_attack(a, _blow_marks(&"perilous"), _profile(HitProfile.Perilous.THRUST, 5, true)))
	assert_false(await _aura_at(a, 5), "no perilous rim")
	assert_eq(_fx(a).icon_shape, HitProfile.Perilous.THRUST, "the icon is its own switch")
	for stale in _waves():
		stale.queue_free()
	await frames(2)
	t = _tuning()
	t.perilous_wave_on = false
	a = _fighter(t)
	a.runner.start(_attack(a, _blow_marks(&"perilous"), _profile(HitProfile.Perilous.THRUST, 5, true)))
	assert_true(await _aura_at(a, 5))
	assert_eq(_waves().size(), 0, "no perilous wave")
	t = _tuning()
	t.perilous_icon_on = false
	a = _fighter(t)
	a.runner.start(_attack(a, _blow_marks(&"perilous"), _profile(HitProfile.Perilous.THRUST, 5, true)))
	await Duel.play_to(self, a, 5)
	assert_eq(_fx(a).icon_shape, HitProfile.Perilous.NONE, "no icon")
	assert_true(a.rig.aura_active(), "(its rim is still there)")


func test_abarax_parry_and_catch_start_his_burst_a_guard_does_not() -> void:
	for outcome: HitResult.Outcome in [HitResult.Outcome.PARRIED, HitResult.Outcome.CAUGHT]:
		var a := _fighter()
		await frames(2)
		a.got_hit.emit(_result(outcome), _event(a))
		assert_true(a.rig.aura_active(), "%s: a rim on Abarax" % HitResult.Outcome.keys()[outcome])
		assert_eq(a.rig.aura_color(), GOLD_WHITE, "white-gold")
		await frames(1)
		assert_true(a.rig.aura_level() > 0.3, "rising")
		var rings := _waves().filter(func(w: GroundWave) -> bool: return w.billboard)
		assert_eq(rings.size(), 1, "and a small ring at the meeting point")
		assert_near(rings[0].max_radius, 0.5, 1e-6)
		assert_vec_near(rings[0].global_position, _event(a).point, 1e-4, "where the blows met")
		await frames(5)
		assert_true(a.rig.aura_active(), "still there 6 frames on")
		await frames(4)
		assert_false(a.rig.aura_active(), "gone about 8 frames after it began")
		for stale in _waves():
			stale.queue_free()
		await frames(2)
	var guarded := _fighter()
	await frames(2)
	guarded.got_hit.emit(_result(HitResult.Outcome.GUARDED), _event(guarded))
	assert_false(guarded.rig.aura_active(), "a guard starts no burst")
	assert_eq(_waves().size(), 0, "and no ring")
	# A parried attacker: nothing new on the enemy whose blow was turned back, nor on an enemy that parries.
	var foe := Duel.make(self, [], [], 6.0)["b"] as Actor
	await frames(2)
	foe.got_hit.emit(_result(HitResult.Outcome.PARRIED), _event(foe))
	assert_false(foe.rig.aura_active(), "an enemy's own parry shows no burst: it is Abarax's")
	# Switched off.
	var t := _tuning()
	t.parry_burst_on = false
	var off := _fighter(t)
	await frames(2)
	off.got_hit.emit(_result(HitResult.Outcome.PARRIED), _event(off))
	assert_false(off.rig.aura_active(), "switched off, no burst")
	assert_eq(_waves().size(), 0)


func _result(outcome: HitResult.Outcome) -> HitResult:
	var r := HitResult.new()
	r.outcome = outcome
	return r


func _event(target: Actor) -> HitEvent:
	var e := HitEvent.new()
	e.target = target
	e.profile = HitProfile.new()
	e.point = Vector3(0.3, 1.2, 0.5)
	return e


func test_the_tuning_is_data_with_a_switch_for_each_element() -> void:
	var t := load(TUNING_PATH) as ReadabilityTuning
	assert_true(t != null, "data/tuning/readability.tres is a ReadabilityTuning")
	for element in [&"parry_aura_on", &"perilous_rim_on", &"heavy_wave_on", &"perilous_wave_on", &"perilous_icon_on", &"parry_burst_on"]:
		assert_eq(t.get(element), true, "%s is on" % element)
	assert_eq(t.parry_rim_color, BLUE_WHITE)
	assert_eq(t.perilous_rim_color, ROSE)
	assert_eq(t.burst_color, GOLD_WHITE)
	assert_eq(t.icon_size, 9)
	assert_near(t.perilous_wave_radius, 1.8, 1e-6)
	assert_near(t.heavy_wave_radius, 1.1, 1e-6)
	assert_near(t.wave_seconds, 0.4, 1e-6)
	assert_eq(t.burst_frames, 8)
	assert_true(t.rim_width_px >= 1.0 and t.rim_width_px <= 2.0, "a rim is 1 to 2 px")


# --- the Hud's icon ---

func _yard_with_a_sweeper() -> Dictionary:
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(-2.0, 0.0, 2.0)))
	main.player.place(Transform3D(Basis(Vector3.UP, PI), Vector3(2.0, 0.0, 5.0)))
	return {"main": main, "foe": foe}


func test_the_hud_draws_the_icon_only_for_a_perilous_attack_above_the_head() -> void:
	var run := _yard_with_a_sweeper()
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	var hud := main.hud
	await frames(3)
	assert_eq(hud.icons().size(), 0, "no icon while nothing is wrong")
	# An ordinary blow: none. 
	foe.runner.start(Registry.fetch(&"moves", &"knuckle_jab") as MoveData)
	await frames(20)
	assert_eq(hud.icons().size(), 0, "a parryable jab gets no icon")
	foe.runner.start(Registry.fetch(&"moves", &"knuckle_sweep") as MoveData)
	await frames(3)
	var icons := hud.icons()
	assert_eq(icons.size(), 1, "a perilous sweep gets one")
	assert_eq(icons[0].shape, HitProfile.Perilous.SWEEP, "the sweep's shape")
	var head := hud.picture_point(foe.get_global_transform_interpolated().origin + Vector3.UP * foe.def.look_height)
	var rect := icons[0].rect as Rect2i
	assert_eq(rect.size, Vector2i(9, 9), "9 x 9")
	assert_true(head.y - rect.end.y >= 4, "its bottom edge is at least 4 px above the head point (%d)" % (head.y - rect.end.y))
	assert_true(absf(rect.get_center().x - head.x) <= 1.0, "over the head")
	# It follows the head.
	var before := rect.position
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), foe.global_position + Vector3(1.0, 0.0, 0.0)))
	foe.runner.start(Registry.fetch(&"moves", &"knuckle_sweep") as MoveData)
	await frames(3)
	assert_true((hud.icons()[0].rect as Rect2i).position.x > before.x + 20, "it follows the foe as it walks")
	# Not shifted by the sub-pixel: it moves by whole picture pixels and no more than the head does.
	main.stage.subpixel = Vector2.ZERO
	var plain: Rect2i = hud.icons()[0].rect
	main.stage.subpixel = Vector2(0.45, -0.35)
	var shifted: Rect2i = hud.icons()[0].rect
	assert_true(absi(shifted.position.x - plain.position.x) <= 1 and absi(shifted.position.y - plain.position.y) <= 1, "within a pixel (%s, %s)" % [plain, shifted])
	assert_eq(Vector2(shifted.position), Vector2(shifted.position).round(), "on whole pixels")
	# The foe's bars sit above the icon, not over it.
	foe.stats.take_damage(5.0)
	foe.got_hit.emit(_result(HitResult.Outcome.HIT), _event(foe))
	var bars := hud.foe_bars()
	assert_true(bars.size() == 1 and (bars[0].posture as Rect2i).end.y <= (hud.icons()[0].rect as Rect2i).position.y, "the bars are above it")
	# It goes when the blow's last hitbox is off.
	await frames(90)
	assert_eq(hud.icons().size(), 0, "gone when the sweep is over")


func test_each_answer_has_its_own_glyph_of_nine_by_nine() -> void:
	var seen := {}
	for shape: int in Hud.ICON_CELLS:
		var rows: Array = Hud.ICON_CELLS[shape]
		assert_eq(rows.size(), 9, "9 rows")
		for row: String in rows:
			assert_eq(row.length(), 9, "9 cells a row")
		seen[str(rows)] = true
	assert_eq(seen.size(), 3, "three different shapes")
	assert_true(Hud.ICON_CELLS.has(HitProfile.Perilous.SWEEP) and Hud.ICON_CELLS.has(HitProfile.Perilous.THRUST) and Hud.ICON_CELLS.has(HitProfile.Perilous.GRAB))


# --- the parry rim peaks with the blow, and a feint wears its model's rim ---

# The rim's level on each frame a Knuckle (tier II, thinking with `steps`) has it on, from the frame it first shows to the last
# before it goes out: plays up to `until` frames.
func _rim_levels(steps: Array, until := 60) -> Array[float]:
	var arena := TestArena.make(self)
	var k := TestArena.spawn(arena, load("res://data/actors/knuckle_2.tres") as ActorDef, ScriptBrain.new(steps), Vector3.ZERO, "K")
	k.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var levels: Array[float] = []
	var seen := false
	for i in until:
		await frames(1)
		if k.rig.aura_active():
			seen = true
			levels.append(k.rig.aura_level())
		elif seen:
			break
	arena.free()
	return levels


func test_the_jabs_rim_climbs_to_its_peak_at_the_blow_plain_or_held() -> void:
	for held in [0, 6, 12]:
		var steps: Array = [{frames = 1, press = [&"palm"], hold = [&"palm"]}] if held > 0 else [{frames = 1, press = [&"palm"]}]
		if held > 0:
			steps = [{frames = held + 12, press = [&"palm"], hold = [&"palm"]}]
		var levels := await _rim_levels(steps)
		assert_true(levels.size() >= 12, "the rim shows for the tell (%d frames, held %d)" % [levels.size(), held])
		for i in range(1, levels.size()):
			assert_true(levels[i] >= levels[i - 1] - 1e-4, "never falls (held %d, frame %d: %.2f then %.2f)" % [held, i, levels[i - 1], levels[i]])
		assert_true(levels.back() >= 0.9, "at least 0.9 on the frame before the blow (held %d: %.2f)" % [held, levels.back()])
		var tail := levels.slice(levels.size() - 8)
		for i in range(1, tail.size()):
			assert_true(tail[i] > tail[i - 1], "and climbs frame over frame in the last frames (held %d: %s)" % [held, tail])
		assert_true(levels[0] < 0.6, "from a lower start (held %d: %.2f)" % [held, levels[0]])


func test_a_feints_rim_is_the_jabs_frame_for_frame_and_ends_where_the_blow_would_be() -> void:
	var jab := await _rim_levels([{frames = 1, press = [&"palm"]}])
	var feint := await _rim_levels([{frames = 1, press = [&"dodge"]}])
	assert_eq(Registry.fetch(&"moves", &"knuckle_feint").imitates, &"knuckle_jab", "the data says which blow the feint imitates")
	assert_true(jab.size() >= 12 and feint.size() >= 12, "both show a rim (%d, %d)" % [jab.size(), feint.size()])
	assert_eq(feint.size(), jab.size(), "for as many frames")
	for i in mini(jab.size(), feint.size()):
		assert_near(feint[i], jab[i], 1e-3, "frame %d" % i)


func test_the_hud_places_an_icon_by_its_actors_own_tuning() -> void:
	var run := _yard_with_a_sweeper()
	var main: Main = run["main"]
	var foe: Actor = run["foe"]
	await frames(3)
	var fx := _fx(foe)
	fx.tuning = _tuning()
	fx.tuning.icon_above = 12
	fx.icon_shape = HitProfile.Perilous.SWEEP
	var head := main.hud.picture_point(foe.get_global_transform_interpolated().origin + Vector3.UP * foe.def.look_height)
	var rect := main.hud.icons()[0].rect as Rect2i
	assert_eq(int(head.y) - rect.end.y, 12, "the icon sits 12 px above the head, as this actor's tuning says (not the default's 6)")
