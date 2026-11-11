extends TestCase
## What the dodge chain looks and sounds like (ChainFx, a child of every actor whose def has a chain; spec section 5): the whoosh
## that climbs a semitone a link, the afterimage on a perfect dodge and on every dodge at Flurry, the white-gold rim from Quick
## on (half) and at Flurry (full), the slow-down on the chain's first perfect dodge and on the link that enters Flurry, the hard
## cue when he is knocked out, and the counter's palm trail that grows with the tempo it cashed in. Each effect has a switch in
## the readability tuning.
##
## `a` is Abarax (a PLAYER) at the origin facing +Z, `b` an ENEMY copy a metre in front (Duel). Most tests give the chain its links
## by hand and report the evade the way HitIntake does (got_hit with an EVADED result), so that what is under test is what ChainFx
## makes of them; the first test sends real blows at a real sway. After a frame the test is at the start of the next, where Sfx
## still holds what the last one played.

const TUNING_PATH := "res://data/tuning/readability.tres"
const GOLD := Color("fff1c8")
const T := DodgeChain.Tempo
const ROUND := HitProfile.Line.ROUND
const SWAY := &"sway"


func before_each() -> void:
	Melee.slow(0, 1.0)


func after_each() -> void:
	Melee.slow(0, 1.0)


func _tuning() -> ReadabilityTuning:
	return (load(TUNING_PATH) as ReadabilityTuning).duplicate() as ReadabilityTuning


# {arena, a, b, fx}: `a` stands idle, its ChainFx using `tuning` (the data's own with none).
func _world(tuning: ReadabilityTuning = null, steps := []) -> Dictionary:
	var run := Duel.make(self, steps)
	var a: Actor = run["a"]
	var fx := a.get_node("ChainFx") as ChainFx
	if tuning != null:
		fx.tuning = tuning
		(a.chain_slow as ChainSlow).tuning = tuning
	run["fx"] = fx
	return run


func _afterimages() -> Array[Node]:
	var found: Array[Node] = []
	for node in get_tree().get_nodes_in_group(Afterimage.GROUP):
		if not node.is_queued_for_deletion():
			found.append(node)
	return found


# Gives the chain `links` plain links (no blow behind them: a parry's, say).
func _links(a: Actor, links: int) -> void:
	for i in links:
		a.chain.link(false, a.buffer_frame)


# One blow evaded by `a` the way HitIntake reports it: a link in the chain, and got_hit with an EVADED result.
func _evade(run: Dictionary, perfect := false) -> void:
	var a: Actor = run["a"]
	var result := HitResult.new()
	result.outcome = HitResult.Outcome.EVADED
	result.perfect = perfect
	a.chain.link(perfect, a.buffer_frame)
	a.got_hit.emit(result, Blows.event(run["b"], a, Blows.profile()))


# The pitches the evade whoosh was played at, over the frames from now to the one after `n` frames.
func _whooshes(n: int) -> Array[float]:
	var pitches: Array[float] = []
	for i in n:
		await frames(1)
		var played := Sfx.last_played()
		for j in played.size():
			if played[j] == &"evade_whoosh":
				pitches.append(Sfx.last_pitches()[j])
	return pitches


func _heard(n: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for i in n:
		await frames(1)
		ids.append_array(Sfx.last_played())
	return ids


func test_a_real_sway_through_a_real_blow_whooshes_leaves_an_afterimage_and_lights_nothing_at_slip() -> void:
	var run := _world(null, [{"frames": 9}, {"frames": 1, "press": [SWAY]}, {"frames": 60}])
	var a: Actor = run["a"]
	var heard := []
	var seen_images := [0]
	while a.frame < 30:
		if a.frame + 1 == 14:
			Blows.post(run["b"], a, {})  # a straight jab, slipped in the window's first frames: a perfect dodge
		await frames(1)
		heard.append_array(Sfx.last_played())
		seen_images[0] = maxi(seen_images[0], _afterimages().size())
	assert_eq(a.chain.count, 2, "a perfect dodge links twice")
	assert_eq(heard.count(&"evade_whoosh"), 1, "one whoosh for the one blow")
	assert_eq(heard.count(&"perfect_dodge"), 1, "and the perfect dodge's cue")
	assert_eq(seen_images[0], 1, "and an afterimage, though the chain is only at Slip")
	assert_false(a.rig.aura_active(), "no rim at Slip")


func test_the_whoosh_climbs_a_semitone_a_link() -> void:
	var run := _world()
	var a: Actor = run["a"]
	var pitches: Array[float] = []
	for link in 14:
		_evade(run)
		pitches.append_array(await _whooshes(1))
	assert_eq(pitches.size(), 14, "a whoosh for each of 14 evades, on its own frame")
	for i in 12:
		assert_near(pitches[i], pow(2.0, float(i + 1) / 12.0), 1e-5, "link %d is %d semitones up" % [i + 1, i + 1])
	assert_near(pitches[11], 2.0, 1e-5, "the twelfth is an octave up")
	assert_near(pitches[12], 2.0, 1e-5, "and it climbs no further")
	assert_near(pitches[13], 2.0, 1e-5)
	assert_eq(a.chain.count, 14)


func test_one_sway_through_three_blows_is_one_whoosh_one_afterimage_and_one_perfect_cue() -> void:
	var run := _world()
	var a: Actor = run["a"]
	_links(a, 6)  # Quick, on the edge of Flurry
	await frames(1)
	_evade(run, true)
	_evade(run, true)
	_evade(run)
	var heard := await _heard(2)
	assert_eq(heard.count(&"evade_whoosh"), 1, "three blows on a frame, one whoosh")
	assert_eq(heard.count(&"perfect_dodge"), 1, "one cue")
	assert_eq(_afterimages().size(), 1, "one afterimage")
	assert_eq(a.chain.count, 6 + 2 + 2 + 1, "though the chain counted each blow")


func test_a_whoosh_is_at_the_pitch_of_the_count_after_the_frames_last_link() -> void:
	var run := _world()
	_evade(run)
	_evade(run)
	_evade(run)
	var pitches := await _whooshes(1)
	assert_eq(pitches.size(), 1)
	assert_near(pitches[0], pow(2.0, 3.0 / 12.0), 1e-5, "three links, three semitones")


func test_a_parry_links_the_chain_but_is_no_evade_and_whooshes_not() -> void:
	var run := _world()
	var a: Actor = run["a"]
	_links(a, 1)
	var heard := await _heard(2)
	assert_false(heard.has(&"evade_whoosh"), "a link with no evade behind it makes no whoosh")
	assert_eq(_afterimages().size(), 0)


func test_the_slow_down_comes_on_the_first_perfect_dodge_and_on_entering_flurry_and_no_other_time() -> void:
	var run := _world()
	var a: Actor = run["a"]
	# a non-perfect link first: no slow-down
	_links(a, 1)
	assert_false(Melee.slowed(), "an ordinary link slows nothing")
	# the chain's first perfect dodge
	a.chain.link(true, a.buffer_frame)
	assert_true(Melee.slowed(), "the first perfect dodge of the chain slows the fight")
	assert_eq(a.chain.count, 3)
	Melee.slow(0, 1.0)
	# a second perfect dodge in the same chain does not
	a.chain.link(true, a.buffer_frame)
	assert_false(Melee.slowed(), "the second perfect dodge does not")
	assert_eq(a.chain.count, 5)
	# the link that enters Flurry (count 7)
	a.chain.link(false, a.buffer_frame)
	assert_false(Melee.slowed(), "count 6 is Quick")
	a.chain.link(false, a.buffer_frame)
	assert_eq(a.chain.count, 7)
	assert_true(Melee.slowed(), "the link that enters Flurry slows it")
	Melee.slow(0, 1.0)
	# further links, perfect or not, in Flurry: no
	a.chain.link(true, a.buffer_frame)
	a.chain.link(false, a.buffer_frame)
	assert_false(Melee.slowed(), "and nothing after")
	# a chain that is over starts afresh: its first perfect dodge slows again, and so does its own way into Flurry
	a.chain.end()
	a.chain.link(true, a.buffer_frame)
	assert_true(Melee.slowed(), "a new chain's first perfect dodge")
	Melee.slow(0, 1.0)
	a.chain.knock_out()
	a.chain.link(false, a.buffer_frame)
	a.chain.link(true, a.buffer_frame)
	assert_true(Melee.slowed(), "the first perfect dodge of the chain after a knock-out, though it is not the chain's first link")
	Melee.slow(0, 1.0)
	# a perfect dodge that carries the chain into Flurry slows it once (one call: it would restart, never stack)
	a.chain.end()
	_links(a, 5)
	a.chain.link(true, a.buffer_frame)
	a.chain.link(true, a.buffer_frame)
	assert_true(Melee.slowed(), "a first perfect dodge that also enters Flurry")
	# the numbers are the tuning's: 12 frames, 40%
	Melee.slow(0, 1.0)
	a.chain.end()
	var seen := []
	for i in 12:
		seen.append(a.buffer_frame)
		await frames(1)
	var before := a.buffer_frame
	a.chain.link(true, a.buffer_frame)
	var acted := 0
	for i in 12:
		var was := a.buffer_frame
		await frames(1)
		acted += a.buffer_frame - was
	assert_eq(acted, 5, "twelve frames of which forty percent are acted on")
	assert_false(Melee.slowed())
	assert_true(before >= 0)


func test_a_blow_that_lands_the_same_frame_still_gives_the_slow_down_only_by_the_chains_own_links() -> void:
	# a knocked-out chain gives no slow-down: the evades of a frame that a blow landed on do not count (HitIntake), so no link comes
	var run := _world()
	var a: Actor = run["a"]
	_links(a, 3)
	a.chain.knock_out()
	assert_false(Melee.slowed(), "being knocked out slows nothing")


func test_afterimages_mark_perfect_dodges_and_every_flurry_dodge() -> void:
	# [the chain before the dodge, perfect?, afterimages expected]: the tempo is the chain's after the dodge's links
	for case: Array in [[0, false, 0], [0, true, 1], [2, false, 0], [3, false, 0], [3, true, 1], [5, false, 0], [6, false, 1], [7, false, 1], [9, true, 1]]:
		var run := _world()
		var a: Actor = run["a"]
		_links(a, case[0])
		Melee.slow(0, 1.0)
		await frames(1)
		var before := _afterimages().size()
		_evade(run, case[1])
		await frames(1)
		var label := "chain %d, %s" % [case[0], "perfect" if case[1] else "plain"]
		assert_eq(_afterimages().size() - before, case[2], "%s: afterimages" % label)
		(run["arena"] as Node).queue_free()
		await frames(1)
		for node in _afterimages():
			node.free()
	# the cue of a perfect dodge, and only of a perfect dodge
	var run := _world()
	_evade(run)
	assert_false((await _heard(2)).has(&"perfect_dodge"), "an ordinary evade has no perfect cue")
	_evade(run, true)
	assert_true((await _heard(2)).has(&"perfect_dodge"), "a perfect dodge has it")


func test_an_afterimage_is_behind_where_he_stood_and_fades_over_its_frames() -> void:
	var run := _world()
	var a: Actor = run["a"]
	_evade(run, true)
	await frames(1)
	var images := _afterimages()
	assert_eq(images.size(), 1)
	var image := images[0] as Afterimage
	assert_eq(image.frames, 12, "the tuning's 12 frames")
	var first := image.alpha()
	assert_true(first > 0.0 and first <= 1.0, "it starts visible (%.2f)" % first)
	a.global_position += Vector3(0.0, 0.0, 0.5)  # he moves on; it stays where he stood
	await frames(4)
	assert_true(image.alpha() < first, "it fades")
	assert_near(image.global_position.z, 0.0, 1e-4, "where he stood")
	var waited := 5
	while not _afterimages().is_empty() and waited < 60:
		await frames(1)
		waited += 1
	assert_eq(_afterimages().size(), 0, "and is gone after its frames")
	assert_true(waited >= 12 and waited <= 12 + 7 + 5, "which are the 12 he acts on (the slow-down of this first perfect dodge held him 7 more): gone after %d" % waited)


func test_the_afterimage_is_the_stance_he_left_and_ages_on_his_clock() -> void:
	var run := _world(null, [{"frames": 9}, {"frames": 1, "press": [SWAY]}, {"frames": 80}])
	var a: Actor = run["a"]
	var left := {}
	a.runner.move_started.connect(func(move: MoveData) -> void:
		if move.evade != MoveData.Evade.NONE:
			left["head"] = a.rig.bone_global(&"Head")
			left["at"] = a.global_position)
	var image: Afterimage = null
	var ticks := []  # per wall frame: [the image's drop in life, the actor's own clock's rise]
	while a.frame < 60:
		if a.frame + 1 == 14:
			Blows.post(run["b"], a, {})  # a perfect dodge of a straight blow: the first perfect dodge slows the fight
		var life_before := image.left if image != null and is_instance_valid(image) else -1
		var clock_before := a.buffer_frame
		await frames(1)
		if image == null and not _afterimages().is_empty():
			image = _afterimages()[0] as Afterimage
			left["image"] = true
			left["image_head"] = image.bone_global(&"Head")
			left["now_head"] = a.rig.bone_global(&"Head")
		elif image != null and is_instance_valid(image) and life_before >= 0 and not image.is_queued_for_deletion():
			ticks.append([life_before - image.left, a.buffer_frame - clock_before])
	assert_true(left.has("image"), "the dodge left an afterimage")
	assert_true(left.has("head"), "the sway started")
	assert_true((left["image_head"] as Vector3).distance_to(left["head"]) < 0.02, "its head is where his head was when the dodge began (%s against %s)" % [left["image_head"], left["head"]])
	assert_true((left["now_head"] as Vector3).distance_to(left["head"]) > 0.03, "and he has moved on from it by the time it shows (%s)" % [left["now_head"]])
	assert_true(ticks.size() >= 8, "it lived a while (%d frames)" % ticks.size())
	for t: Array in ticks:
		assert_eq(t[0], t[1], "it ages on the frames he acts on and on none he is held on (aged %d while his clock rose %d)" % [t[0], t[1]])
	assert_true(ticks.any(func(t: Array) -> bool: return t[1] == 0), "and the slow-down did hold him while it hung")


func test_an_enemy_with_a_chain_does_not_slow_the_fight() -> void:
	var def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	var run := Duel.make(self, [], [], 1.0, def)
	var b: Actor = run["b"]
	assert_ne(b.chain, null, "it has a chain")
	assert_eq(b.chain_slow, null, "but the rule that slows the fight is the player's alone")
	b.chain.link(true, b.buffer_frame)
	for i in 8:
		b.chain.link(false, b.buffer_frame)
	assert_false(Melee.slowed(), "its first perfect dodge and its way into Flurry slow nothing")


func test_the_rim_is_off_at_slip_half_at_quick_full_at_flurry_and_gone_when_knocked_out() -> void:
	var run := _world()
	var a: Actor = run["a"]
	var rig := a.rig
	_links(a, 2)
	await frames(1)
	assert_false(rig.aura_active(), "no rim at Slip")
	_links(a, 1)
	await frames(1)
	assert_true(rig.aura_active(), "a rim at Quick (count 3)")
	assert_near(rig.aura_level(), 1.0, 1e-5, "the hull is drawn solid: half strength is half the brightness, not half the opacity, which would grey on the dark ground")
	assert_true(rig.aura_color().is_equal_approx(Color(GOLD.r * 0.5, GOLD.g * 0.5, GOLD.b * 0.5)), "white-gold at half the brightness (%s)" % rig.aura_color())
	_links(a, 3)
	await frames(1)
	assert_true(rig.aura_color().is_equal_approx(Color(GOLD.r * 0.5, GOLD.g * 0.5, GOLD.b * 0.5)), "still half at count 6")
	_links(a, 1)
	await frames(1)
	assert_near(rig.aura_level(), 1.0, 1e-5, "full at Flurry")
	assert_true(rig.aura_color().is_equal_approx(GOLD), "in the full gold")
	a.chain.knock_out()
	await frames(1)
	assert_false(rig.aura_active(), "gone when he is knocked out")
	# and when the chain ends any other way
	_links(a, 4)
	await frames(1)
	assert_true(rig.aura_active())
	a.chain.end()
	await frames(1)
	assert_false(rig.aura_active(), "gone when the chain ends")
	_links(a, 8)
	await frames(1)
	a.chain.cash()
	await frames(1)
	assert_false(rig.aura_active(), "and when it is cashed in")


func test_the_rim_gives_way_to_his_parry_burst_and_to_a_tell_and_comes_back() -> void:
	var run := _world()
	var a: Actor = run["a"]
	_links(a, 7)
	await frames(1)
	assert_near(a.rig.aura_level(), 1.0, 1e-5)
	# his parry's burst replaces the rim for its frames and is not overwritten by it
	var fx := a.get_node("ActorFx") as ActorFx
	a.rig.aura(fx.tuning.burst_color, 8.0 / 60.0, 1.0)
	await frames(2)
	assert_false(a.rig.aura_held(), "the burst is still the aura, not the chain's held rim")
	await frames(14)
	assert_true(a.rig.aura_held(), "the rim comes back when the burst is over")
	assert_near(a.rig.aura_level(), 1.0, 1e-5)
	# a tell on his own body (none exists today: a fixture move gives him one) keeps the rim, and the rim does not fight it
	var clip := a.rig.tree.get_animation(&"palm_jab").duplicate(true) as Animation
	clip.length = 1.0
	Marks.write(clip, [{"time": Marks.time_of(2), "kind": &"tell", "args": {"kind": &"glint"}},
			{"time": Marks.time_of(12), "kind": &"hitbox_on", "args": {"id": &"palm_l", "profile": &"p"}},
			{"time": Marks.time_of(16), "kind": &"hitbox_off", "args": {"id": &"palm_l"}},
			{"time": Marks.time_of(30), "kind": &"recovery", "args": {}}])
	a.rig.tree.get_animation_library(&"").add_animation(&"fixture_tell", clip)
	var move := MoveData.new()
	move.id = &"fixture_tell"
	move.kind = MoveData.Kind.OTHER
	move.clip = &"fixture_tell"
	move.root_motion = false
	move.hits = {&"p": HitProfile.new()}
	a.runner.start(move)
	await frames(6)
	assert_true(fx.rim_busy(), "the tell is showing")
	assert_eq(a.rig.aura_color(), fx.tuning.parry_rim_color, "while a tell is showing on him the rim is the tell's, not the chain's")
	assert_eq(a.chain.count, 7, "(a move that is no attack leaves the chain alone)")
	await frames(20)
	assert_false(fx.rim_busy(), "the tell is over")
	assert_eq(a.rig.aura_color(), GOLD, "and the chain's rim is back")


func test_knocked_out_cuts_the_rim_sounds_the_hard_cue_and_leaves_no_afterimage() -> void:
	var run := _world()
	var a: Actor = run["a"]
	_links(a, 8)
	await frames(1)
	assert_true(a.rig.aura_active())
	# a blow lands on the frame a blow is evaded (HitIntake gives the evades of that frame no link): no afterimage, no whoosh
	var result := HitResult.new()
	result.outcome = HitResult.Outcome.EVADED
	result.perfect = true
	a.chain.knock_out()
	a.got_hit.emit(result, Blows.event(run["b"], a, Blows.profile()))
	var heard := await _heard(2)
	assert_eq(heard.count(&"knocked_out"), 1, "the hard cue, once")
	assert_false(heard.has(&"evade_whoosh") or heard.has(&"perfect_dodge"), "no whoosh or perfect cue on the frame he is knocked out")
	assert_eq(_afterimages().size(), 0, "no afterimage")
	assert_false(a.rig.aura_active(), "the rim is off")
	# no knock-out cue for a chain that had nothing to lose
	var empty := _world()
	(empty["a"] as Actor).chain.knock_out()
	assert_false((await _heard(2)).has(&"knocked_out"), "an empty chain loses nothing")


func test_the_knock_out_cue_is_for_a_knock_out_at_quick_or_flurry() -> void:
	for case: Array in [[2, false], [3, true], [6, true], [7, true]]:
		var run := _world()
		var a: Actor = run["a"]
		_links(a, case[0])
		Melee.slow(0, 1.0)
		a.chain.knock_out()
		var heard := await _heard(2)
		assert_eq(heard.has(&"knocked_out"), case[1], "a chain of %d knocked out: the cue is %s" % [case[0], "heard" if case[1] else "not heard (at Slip the blow is an ordinary hit)"])
		(run["arena"] as Node).queue_free()
		await frames(2)


func test_a_real_blow_that_lands_on_a_flurry_knocks_him_out_with_the_cue_and_no_rim() -> void:
	var run := _world(null, [{"frames": 60}])
	var a: Actor = run["a"]
	_links(a, 8)
	await frames(2)
	assert_true(a.rig.aura_active())
	Blows.post(run["b"], a, {"damage": 10.0})
	var heard := await _heard(3)
	assert_true(heard.has(&"knocked_out"), "he is hit: the hard cue (heard %s)" % [heard])
	assert_eq(a.chain.count, 0)
	assert_false(a.rig.aura_active(), "no rim")


func test_the_counters_trail_grows_with_the_tempo_cashed_in() -> void:
	# the four moves that cash the chain in, started by the runner as a press would (cash, then the move): the trail they show is 1,
	# 1.25 or 1.5 times its size by the tempo, and an ordinary jab's is not scaled at all
	var sizes := {}
	for case: Array in [[1, T.SLIP], [3, T.QUICK], [7, T.FLURRY]]:
		var run := _world(null, [{"frames": 90}])
		var a: Actor = run["a"]
		_links(a, case[0])
		var live := [Registry.fetch(&"moves", &"counter_hook")]
		a.runner.start(live[0] as MoveData)
		var found: Array[float] = []
		while a.runner.current != null and a.runner.current.id == &"counter_hook" and a.frame < 60:
			await frames(1)
			for node in get_tree().get_nodes_in_group(ActorFx.GROUP):
				if node.get_meta(&"fx", &"") == &"palm_trail":
					var material := (node as GPUParticles3D).process_material as ParticleProcessMaterial
					found.append(material.scale_min)
		assert_true(found.size() > 0, "the counter showed its trail at tempo %d" % case[1])
		sizes[case[1]] = found[0]
		for node in get_tree().get_nodes_in_group(ActorFx.GROUP):
			node.free()
		(run["arena"] as Node).queue_free()
		await frames(2)
	assert_near(sizes[T.SLIP], 1.0, 1e-5, "Slip: its own size")
	assert_near(sizes[T.QUICK], 1.25, 1e-5, "Quick: a quarter larger")
	assert_near(sizes[T.FLURRY], 1.5, 1e-5, "Flurry: half again")
	# the shared material is not changed under every other trail: an ordinary jab is the scene's own size
	var run := _world(null, [{"frames": 1, "press": [&"palm"]}, {"frames": 60}])
	var a: Actor = run["a"]
	_links(a, 7)
	var jab_sizes: Array[float] = []
	while a.frame < 30:
		await frames(1)
		for node in get_tree().get_nodes_in_group(ActorFx.GROUP):
			if node.get_meta(&"fx", &"") == &"palm_trail":
				jab_sizes.append(((node as GPUParticles3D).process_material as ParticleProcessMaterial).scale_min)
	assert_true(jab_sizes.size() > 0, "the jab showed its trail")
	for size in jab_sizes:
		assert_near(size, 1.0, 1e-5, "a plain jab's trail is not scaled, whatever tempo it cashed in")


func test_each_switch_turns_its_effect_off() -> void:
	# every switch alone is off; the other effects are still on
	for switch: String in ["afterimage_on", "slowdown_on", "chain_rim_on"]:
		var t := _tuning()
		t.set(switch, false)
		var run := _world(t)
		var a: Actor = run["a"]
		_links(a, 6)
		Melee.slow(0, 1.0)
		await frames(1)
		_evade(run, true)  # a perfect dodge that enters Flurry (chain 6 + 2): a first perfect dodge, the way into Flurry, an afterimage, full rim
		var heard := await _heard(2)
		assert_eq(_afterimages().size(), 0 if switch == "afterimage_on" else 1, "%s off: afterimages" % switch)
		assert_eq(Melee.slowed(), switch != "slowdown_on", "%s off: the slow-down" % switch)
		assert_eq(a.rig.aura_active(), switch != "chain_rim_on", "%s off: the rim" % switch)
		assert_true(heard.has(&"evade_whoosh") and heard.has(&"perfect_dodge"), "%s off: the sounds are not a switch's" % switch)
		for node in _afterimages():
			node.free()
		(run["arena"] as Node).queue_free()
		await frames(2)
		Melee.slow(0, 1.0)


func test_the_tuning_is_data_for_the_chain() -> void:
	var t := load(TUNING_PATH) as ReadabilityTuning
	for switch in [&"afterimage_on", &"slowdown_on", &"chain_rim_on"]:
		assert_eq(t.get(switch), true, "%s is on" % switch)
	assert_eq(t.chain_rim_color, GOLD)
	assert_eq(t.afterimage_frames, 12)
	assert_eq(t.slow_frames, 12)
	assert_near(t.slow_share, 0.4, 1e-6)
	assert_near(t.chain_rim_quick, 0.5, 1e-6)
	assert_near(t.chain_rim_flurry, 1.0, 1e-6)
	assert_eq(t.trail_scales, PackedFloat32Array([1.0, 1.25, 1.5]))
	assert_true(t.afterimage_color.a > 0.0 and t.afterimage_color.a <= 1.0, "the afterimage has an opacity")


func test_an_actor_without_a_chain_has_no_chain_fx() -> void:
	var def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	def.chain = null
	var run := Duel.make(self, [], [], 1.0, def)
	assert_eq((run["b"] as Actor).get_node_or_null("ChainFx"), null)
	assert_ne((run["a"] as Actor).get_node_or_null("ChainFx"), null, "Abarax has one")


func test_the_first_chain_rim_builds_no_shader_in_the_yard() -> void:
	# The yard warms the rims a fight goes round as it loads (Rig.warm_rim): the chain's is one more user of Abarax's, and builds nothing.
	Game.reset()
	var main := track((load("res://main/main.tscn") as PackedScene).instantiate()) as Main
	await frames(Rig.WARM_FRAMES + 3)
	var made := RimMarks.made()
	var player := main.player
	for i in 7:
		player.chain.link(false, player.buffer_frame)
	await frames(3)
	assert_true(player.rig.aura_active(), "the rim is on at Flurry")
	assert_eq(RimMarks.made(), made, "and made no shader")
	Game.reset()
