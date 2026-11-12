extends TestCase
## The heavy Knuckle (data/actors/knuckle_heavy.tres, F1 Task 14d): a big body that shrugs off light blows (hyper-armour on
## its wind-ups) and a ground slam that is left or hopped and nothing else. Its moves are heavy_haymaker (palm) and
## heavy_slam (gift); its numbers are the brief's, and what its armour does not stop is held here: posture, a broken
## posture's finisher and a clear-out's throw.
##
## A frame is the actor's: the first it lives is 1. A press on frame 1 starts the move there (its f0), so a hitbox that
## comes on at the clip's f38 is live from frame 39, and a blow is judged against how the body stood when the frame began.
## The heavy stands at the origin facing +Z; Abarax (PLAYER) stands `gap` metres off, facing it.

const HEAVY := "res://data/actors/knuckle_heavy.tres"
const HEAVY_BRAIN := "res://data/brains/knuckle_heavy.tres"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const O := HitResult.Outcome
const R := HitResult.Reaction
## The slam reaches a body's centre this far out and no further, and the ring on the ground is drawn at it. Its hitbox is
## smaller by the body's own radius (the hitbox lands on the hurtbox capsule). The brain chooses the slam within CHOSEN.
const RING := 2.0
const HITBOX := 1.65
const CHOSEN := 1.8
const BODY := 0.35
## The slam's blow comes on at its f38 and goes off at its f42 (frames 39 to 42).
const SLAM_ON := 38
const SLAM_OFF := 42
const HAYMAKER_ON := 42
const HAYMAKER_TELL := 4


func after_each() -> void:
	Game.reset()


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


func _heavy_def() -> ActorDef:
	return load(HEAVY) as ActorDef


# The clip of `move` as the rig's library has it (the marks and the length are read from it).
func _clip(move: StringName) -> Animation:
	return (load("res://assets/anim/abarax/library.tres") as AnimationLibrary).get_animation(_move(move).clip)


# The frame of the `nth` mark of `kind` in the move's clip (the move's own frames, from its f0), or -1.
func _mark_frame(move: StringName, kind: StringName, nth := 0) -> int:
	var found := 0
	for m in Marks.read(_clip(move)):
		if m["kind"] == kind:
			if found == nth:
				return Marks.frame_of(m["time"])
			found += 1
	return -1


func _clip_frames(move: StringName) -> int:
	return Marks.frame_of(_clip(move).length)


# A heavy Knuckle at the origin playing `heavy_steps` and Abarax `gap` metres off, `around` radians from straight ahead, playing
# `abarax_steps`: {arena, heavy, abarax, got}, `got` being [[outcome, Abarax's frame, profile, reaction]] of the blows that
# were not whiffs, as Abarax took them.
func _fight(gap: float, abarax_steps: Array, heavy_steps: Array, around := 0.0, heavy_def: ActorDef = null, origin := Vector3.ZERO) -> Dictionary:
	var arena := TestArena.make(self)
	arena.position = origin
	var heavy := TestArena.spawn(arena, heavy_def if heavy_def != null else _heavy_def(), ScriptBrain.new(heavy_steps), Vector3.ZERO, "Heavy")
	heavy.place(Transform3D(Basis.IDENTITY, origin))
	var at := Vector3(sin(around), 0.0, cos(around)) * gap
	var abarax := TestArena.spawn(arena, load(ABARAX) as ActorDef, ScriptBrain.new(abarax_steps), at, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, around + PI), origin + at))
	var run := {"arena": arena, "heavy": heavy, "abarax": abarax, "got": [], "evading": []}
	abarax.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if r.outcome != O.WHIFF:
			run["got"].append([r.outcome, abarax.frame, e.profile, r.reaction])
			run["evading"].append(abarax.runner.evading))
	return run


func _slam_steps() -> Array:
	return [{"frames": 1, "press": [&"gift"]}, {"frames": 200}]


func _haymaker_steps() -> Array:
	return [{"frames": 1, "press": [&"palm"]}, {"frames": 200}]


# Takes the fight's arena out of the world: the next fight of the same test stands where this one did.
func _end(run: Dictionary) -> void:
	(run["arena"] as Node).free()


# The blows of `run` that landed (a HIT, or a guard taking it), as outcome names.
func _outcomes(run: Dictionary) -> Array:
	return (run["got"] as Array).map(func(g: Array) -> String: return O.keys()[g[0]])


# --- the numbers ---

func test_the_heavy_knuckle_has_its_numbers() -> void:
	var def := _heavy_def()
	assert_eq(def.id, &"knuckle_heavy")
	assert_eq(def.team, ActorDef.Team.ENEMY)
	assert_eq(def.hidden_parts, PackedStringArray(["Knuckle_Blade"]), "hood and pauldron on; the blade Knuckle's sword hidden")
	assert_near(def.model_scale, 1.18, 1e-6, "model_scale")
	assert_eq([def.max_hp, def.max_posture, def.poise], [140.0, 120.0, 14.0], "hp, posture, poise")
	assert_eq(def.moveset, {&"palm": &"heavy_haymaker", &"gift": &"heavy_slam"}, "its moveset")
	assert_true(def.palette != null and def.palette.id == &"knuckle_heavy", "its own palette")
	assert_true(def.locomotion.jog_speed < (load("res://data/actors/knuckle_3.tres") as ActorDef).locomotion.jog_speed, "it walks slower")
	assert_near(def.look_height, 1.6 * 1.18, 0.01, "the head is looked at where it is: look_height scales with the body")
	assert_true(def.brain != null, "it has a brain")


func test_its_moves_have_their_numbers() -> void:
	var h := _move(&"heavy_haymaker")
	var hook: HitProfile = h.hits.values()[0]
	assert_eq(h.hits.size(), 1)
	assert_eq([hook.damage, hook.posture_damage, hook.knockback, hook.staggers, hook.line, hook.height, hook.perilous],
			[26.0, 24.0, 3.0, true, HitProfile.Line.ROUND, HitProfile.Height.MID, HitProfile.Perilous.NONE], "the haymaker's blow")
	var on := _mark_frame(&"heavy_haymaker", &"hitbox_on")
	var off := _mark_frame(&"heavy_haymaker", &"hitbox_off")
	assert_eq(on, HAYMAKER_ON, "its blow comes at f42")
	assert_eq(_mark_frame(&"heavy_haymaker", &"tell"), HAYMAKER_TELL, "the glint at f4: 38 frames of warning")
	assert_eq(off - on, 5, "its hitbox is on for 5 frames")
	assert_eq(_mark_frame(&"heavy_haymaker", &"hyperarmour_on"), 8, "armoured from f8")
	assert_eq(_mark_frame(&"heavy_haymaker", &"hyperarmour_off"), on + 2, "to two frames after the blow comes, so a counter after a dodge is not under it")
	assert_true(_clip_frames(&"heavy_haymaker") - off >= 40, "at least 40 frames of recovery")
	assert_true(_clip_frames(&"heavy_haymaker") <= 96, "and at most 96 frames in all")
	for id: StringName in [&"heavy_haymaker", &"heavy_slam"]:
		var windows := Marks.read(_clip(id)).filter(func(m: Dictionary) -> bool: return m["kind"] == &"cancel_open")
		assert_eq(windows.size(), 1, "%s has the one cancel window the clip checker asks of an attack" % id)
		assert_true(Marks.frame_of(windows[0]["time"]) >= _mark_frame(id, &"recovery") + 30, "%s's is late in its recovery, and his brain never presses into it" % id)
	var s := _move(&"heavy_slam")
	var slam: HitProfile = s.hits.values()[0]
	assert_eq(s.hits.size(), 1)
	assert_eq([slam.damage, slam.posture_damage, slam.knockback, slam.staggers, slam.height, slam.perilous],
			[22.0, 20.0, 2.5, true, HitProfile.Height.LOW, HitProfile.Perilous.SWEEP], "the slam's blow")
	assert_eq(_mark_frame(&"heavy_slam", &"hitbox_on"), SLAM_ON, "the slam lands at f38")
	assert_eq(_mark_frame(&"heavy_slam", &"hitbox_off"), SLAM_OFF, "to f42")
	assert_eq(_clip_frames(&"heavy_slam") - SLAM_OFF, 44, "44 frames of recovery")
	var ring := _mark_frame(&"heavy_slam", &"hyperarmour_on")
	assert_true(ring >= 0 and ring <= 4, "armoured from the start of the wind-up (f%d)" % ring)
	assert_true(_mark_frame(&"heavy_slam", &"hyperarmour_off") >= SLAM_ON, "and through it")


func test_the_brain_is_data_and_has_its_numbers() -> void:
	var brain := load(HEAVY_BRAIN) as BrainDef
	assert_eq(_heavy_def().brain, brain)
	assert_near(brain.preferred_range, 2.0, 1e-6)
	assert_near(brain.attack_rest, 1.4, 1e-6)
	assert_eq(brain.feint_chance, 0.0, "no feint")
	assert_eq(brain.attacks.size(), 2)
	var haymaker: AttackOption = brain.attacks[0]
	var slam: AttackOption = brain.attacks[1]
	assert_eq([haymaker.action, haymaker.weight, haymaker.combo], [&"palm", 1.0, PackedStringArray()], "the haymaker")
	assert_eq([slam.action, slam.weight, slam.cooldown, slam.min_range, slam.max_range], [&"gift", 0.7, 5.0, 0.0, CHOSEN], "the slam: within 1.8 m")


func test_the_clip_checker_passes_it() -> void:
	assert_eq(ClipChecker.new().check_actor(_heavy_def()), PackedStringArray(), "no problem with the heavy Knuckle")


func test_its_clips_do_not_pop_and_the_haymaker_strikes_as_its_hand_arrives() -> void:
	var rig := (load("res://actors/knuckle/knuckle_rig.tscn") as PackedScene).instantiate() as Rig
	rig.position = Vector3(500, 0, 500)  # away from every fight: a bare rig has a hurtbox that has no actor
	track(rig)
	for clip: StringName in [&"heavy_haymaker", &"heavy_slam"]:
		var worst: Array = ClipMotion.worst_pop(rig, clip)
		assert_true(worst[0] <= worst[3], "%s: the %s moves %.3f m to f%d (at most %.2f)" % [clip, worst[1], worst[0], worst[2], worst[3]])
		var limb: Array = ClipMotion.worst_join(rig, clip)
		assert_true(limb[0] <= limb[3], "%s: across a join the %s moves %.3f m to f%d (at most %.2f)" % [clip, limb[1], limb[0], limb[2], limb[3]])
	var arrives: Array = ClipMotion.reach_peak(rig, &"heavy_haymaker", &"hand_r", 0.06)
	var on := _mark_frame(&"heavy_haymaker", &"hitbox_on")
	assert_true(absi(on - arrives[0]) <= 5, "the haymaker's hitbox comes on at f%d, its hand is out from f%d" % [on, arrives[0]])


# --- hyper-armour ---

func test_a_jab_does_not_stop_its_wind_up() -> void:
	# A jab (6 poise against its 14, and a hook's 12 does not reach it either) is no reason for it to stop: the HIT lands, takes its
	# HP and posture, and gives it no reaction, so the haymaker goes on to its blow. (A counter that lands in the wind-up does not
	# stagger it either: test_a_counter_into_his_wind_up_does_not_stagger_him_and_still_hurts.)
	var run := _fight(1.8, [], _haymaker_steps())
	var heavy: Actor = run["heavy"]
	var abarax: Actor = run["abarax"]
	await Duel.play_to(self, heavy, 14)
	assert_true(heavy.runner.hyperarmour, "armoured in its wind-up")
	var posture := heavy.stats.posture
	var hp := heavy.stats.hp
	var results: Array = []
	heavy.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: results.append(r))
	Blows.post(abarax, heavy)
	await frames(2)
	assert_eq(results.size(), 1)
	assert_eq(results[0].outcome, O.HIT, "the jab lands")
	assert_eq(results[0].reaction, R.NONE, "and starts nothing")
	assert_true(heavy.stats.hp < hp, "it takes the damage")
	assert_true(heavy.stats.posture < posture, "and the posture damage counts")
	assert_eq(heavy.runner.current.id, &"heavy_haymaker", "the haymaker plays on")
	await Duel.play_to(self, heavy, HAYMAKER_ON + 8)
	assert_true(run["got"].any(func(g: Array) -> bool: return g[0] == O.HIT and g[2].damage == 26.0), "and its blow lands on Abarax")


func test_posture_still_breaks_it_through_hyper_armour() -> void:
	var run := _fight(1.0, [{"frames": 1}, {"frames": 400, "press": []}], _slam_steps())
	var heavy: Actor = run["heavy"]
	var abarax: Actor = run["abarax"]
	await Duel.play_to(self, heavy, 10)
	assert_true(heavy.runner.hyperarmour, "armoured in the slam's wind-up")
	track(PostureBreaker.make(abarax, heavy))
	await Duel.play_to(self, heavy, 11)
	assert_true(heavy.stats.posture_broken, "its posture is broken")
	assert_eq(heavy.runner.current.id, &"posture_broken", "it reels, whatever the armour")
	assert_true(heavy.is_in_group(Actor.FINISHABLE_GROUP), "and is finishable")
	assert_false(heavy.runner.hyperarmour, "the armour went with the move it cut off")


# Abarax's finisher on `def` (a broken posture, his palm on frame 10): {blows (each the striking hand's gap to the body, in metres:
# negative is inside it), sink (the deepest the two bodies pass into each other), seen (the pair began), hp}.
func _finisher_on(def: ActorDef) -> Dictionary:
	var run := _fight(1.0, [{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 300}], [], 0.0, def)
	var heavy: Actor = run["heavy"]
	var abarax: Actor = run["abarax"]
	track(PostureBreaker.make(abarax, heavy))
	var hit_now := [false]
	abarax.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
		if kind == &"pair_hit":
			hit_now[0] = true)
	var out := {"blows": [], "sink": -INF, "seen": false, "hp": 0.0}
	while abarax.frame < 400:
		await frames(1)
		if abarax.paired_with == heavy:
			out["seen"] = true
		elif out["seen"] and heavy.paired_with == null:
			break
		if not out["seen"]:
			continue
		var a_caps := Bodies.of(abarax.rig)
		var h_caps := Bodies.of(heavy.rig)
		out["sink"] = maxf(out["sink"], Bodies.overlap(a_caps, h_caps)[0])
		if hit_now[0]:
			hit_now[0] = false
			var left := Bodies.strike_gap(a_caps, h_caps, "hand_l")
			var right := Bodies.strike_gap(a_caps, h_caps, "hand_r")
			out["blows"].append(minf(left[0], right[0]))
	out["hp"] = heavy.stats.hp
	_end(run)
	return out


func test_a_broken_heavy_is_finished_and_the_blows_reach_its_larger_body() -> void:
	# The finisher stages the pair from the lead's size, and the def's own pair_reach for a follower that is not the model's
	# size: each of the three blows must reach the heavy (its head or torso at most 8 cm from the striking hand and 5 cm inside
	# it), and the bodies pass at most 5 cm into each other (F1 Task 10's staging criteria). It has HP for the three blows (60 of
	# its 140) and lives.
	var def := _heavy_def().duplicate() as ActorDef
	var out := await _finisher_on(def)
	assert_true(out["seen"], "his palm starts the finisher on it")
	assert_eq(out["blows"].size(), 3, "three blows")
	for gap: float in out["blows"]:
		assert_true(gap <= 0.08 and gap >= -0.05, "a blow reaches it (%.3f m from the body)" % gap)
	assert_true(out["sink"] <= 0.05, "and the bodies pass at most %.3f m into each other" % out["sink"])
	assert_eq(out["hp"], 140.0 - 60.0, "the finisher took 15, 15 and 30 of its 140 HP")


func test_the_finisher_on_tier_three_is_as_it_was_before_the_heavy() -> void:
	# Tier III (1.04) is not the heavy's to change: its three blows' gaps are what they were at the base commit.
	var out := await _finisher_on((load("res://data/actors/knuckle_3.tres") as ActorDef).duplicate() as ActorDef)
	var base := [0.0396, 0.0149, 0.077]  # measured on the code at 19fc53a with this fixture
	assert_eq(out["blows"].size(), 3)
	for i in mini(3, out["blows"].size()):
		assert_near(out["blows"][i], base[i], 0.004, "blow %d: %.3f m, as at the base (%.3f)" % [i + 1, out["blows"][i], base[i]])
	assert_eq(load("res://data/actors/knuckle_3.tres").pair_reach, 1.0, "tier III has the model's reach")


func _counter_after_dodge(evade: StringName, links: int, counter_at: int, duck_at: int) -> Dictionary:
	# Abarax stands 1.4 m off, dodges the haymaker (the evade started on the heavy's frame `duck_at`), and presses palm on frame
	# `counter_at`, with the chain at `links` links: the counter's own blow (a rising palm after a duck, a hook after a sway).
	var run := _fight(1.4, [{"frames": counter_at - 1}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}], _haymaker_steps())
	var heavy: Actor = run["heavy"]
	var abarax: Actor = run["abarax"]
	abarax.chain_slow.tuning = abarax.chain_slow.tuning.duplicate() as ReadabilityTuning
	abarax.chain_slow.tuning.slowdown_on = false
	for i in links:
		abarax.chain.link(false, 0)
	var info := {"run": run, "armoured_until": -1, "landed": -1, "reaction": &"", "evaded": false}
	var was := [false]
	heavy.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if e.attacker == abarax and r.outcome == O.HIT and info["landed"] < 0:
			info["landed"] = heavy.frame
			info["reaction"] = r.reaction)
	abarax.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
		if r.outcome == O.EVADED:
			info["evaded"] = true)
	await Duel.play_to(self, heavy, duck_at)
	abarax.runner.start(_move(evade))
	while heavy.frame < 100:
		await frames(1)
		if heavy.runner.hyperarmour:
			was[0] = true
		elif was[0] and info["armoured_until"] < 0:
			info["armoured_until"] = heavy.frame
	return info


func test_a_counter_after_a_dodged_haymaker_staggers_him() -> void:
	# The duck's evade window is its frames 2 to 14 and the sway's 2 to 12, started on the heavy's frame given (the blow's contact
	# is about frame 44).
	for case: Array in [[&"duck_slip", &"counter_rise", 0, 30], [&"duck_slip", &"counter_rise", 3, 30], [&"duck_slip", &"counter_rise", 7, 30],
			[&"sway_left_slip", &"counter_hook", 7, 34]]:
		var info := await _counter_after_dodge(case[0], case[2], 46, case[3])
		assert_true(info["evaded"], "%s evaded the haymaker (links %d)" % [case[0], case[2]])
		assert_true(info["landed"] > 0, "the counter landed (%s, links %d)" % [case[1], case[2]])
		assert_true(info["armoured_until"] > 0 and info["landed"] - info["armoured_until"] >= 3,
				"at least 3 frames after his armour ended (it ended on %d, the counter landed on %d)" % [info["armoured_until"], info["landed"]])
		if case[2] == 7:
			assert_eq(info["reaction"], R.STAGGER, "a Flurry counter staggers him (%s)" % case[1])
		_end(info["run"])


func test_a_counter_into_his_wind_up_does_not_stagger_him_and_still_hurts() -> void:
	var run := _fight(1.0, [], _haymaker_steps())
	var heavy: Actor = run["heavy"]
	var abarax: Actor = run["abarax"]
	abarax.chain_slow.tuning = abarax.chain_slow.tuning.duplicate() as ReadabilityTuning
	abarax.chain_slow.tuning.slowdown_on = false
	for i in 7:
		abarax.chain.link(false, 0)
	var seen: Array = []
	heavy.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if e.attacker == abarax:
			seen.append([r.outcome, r.reaction, heavy.runner.hyperarmour]))
	await Duel.play_to(self, heavy, 8)
	var hp := heavy.stats.hp
	abarax.runner.start(_move(&"counter_rise"))
	await Duel.play_to(self, heavy, 24)
	assert_true(not seen.is_empty() and seen[0][0] == O.HIT, "the counter landed: %s" % [seen])
	assert_eq(seen[0][1], R.NONE, "and starts nothing while he is armoured")
	assert_eq(heavy.runner.current.id, &"heavy_haymaker", "the haymaker plays on")
	assert_true(heavy.stats.hp < hp - 20.0, "it still hurts (%.0f HP)" % (hp - heavy.stats.hp))


func test_a_player_who_ducks_twenty_five_frames_after_the_tell_is_missed() -> void:
	# The tell (the glint) is on frame 5 of the actor's life; a duck pressed 25 frames later, on frame 30, is evaded.
	for gap: float in [1.4, 1.8, 2.2]:
		var run := _fight(gap, [], _haymaker_steps())
		var heavy: Actor = run["heavy"]
		var abarax: Actor = run["abarax"]
		await Duel.play_to(self, heavy, HAYMAKER_TELL + 1 + 25)
		abarax.runner.start(_move(&"duck_slip"))
		await Duel.play_to(self, heavy, 80)
		var outcomes := _outcomes(run)
		assert_false(outcomes.has("HIT"), "ducked 25 frames after the tell from %.1f m: not hit (%s)" % [gap, outcomes])
		_end(run)


# --- the slam ---

func test_the_slam_hits_everything_within_its_ring_that_stands_on_the_ground() -> void:
	for case: Array in [[0.8, 0.0], [1.6, 0.0], [1.95, 0.0], [1.6, PI], [1.95, PI / 2.0], [0.8, -PI / 2.0]]:
		var run := _fight(case[0], [], _slam_steps(), case[1])
		await Duel.play_to(self, run["heavy"], 70)
		assert_eq(_outcomes(run), ["HIT"], "a body %.1f m off, %.0f degrees round, is hit once" % [case[0], rad_to_deg(case[1])])
		if not run["got"].is_empty():
			var blow: HitProfile = run["got"][0][2]
			assert_eq([blow.perilous, blow.height, blow.damage], [HitProfile.Perilous.SWEEP, HitProfile.Height.LOW, 22.0], "it is the slam's blow")
			assert_true(run["got"][0][1] >= SLAM_ON + 1 and run["got"][0][1] <= SLAM_OFF + 1, "on frames 39 to 43 (it was on %d)" % run["got"][0][1])
		_end(run)
	var far := _fight(2.7, [], _slam_steps())
	await Duel.play_to(self, far["heavy"], 70)
	assert_eq(_outcomes(far), [], "a body 2.7 m off is clear of it")


func test_the_ring_drawn_is_the_ring_that_hits() -> void:
	# A body whose centre is at 1.95 m is hit and one at 2.05 m is not, all round; and the ring drawn (the warning, and the wave
	# as it starts) is the reach, to 3 cm.
	for i in 8:
		var around := TAU * i / 8.0
		var near := _fight(1.95, [], _slam_steps(), around)
		await Duel.play_to(self, near["heavy"], 70)
		assert_eq(_outcomes(near), ["HIT"], "1.95 m off at %.0f degrees: hit" % rad_to_deg(around))
		_end(near)
		var out := _fight(2.05, [], _slam_steps(), around)
		await Duel.play_to(self, out["heavy"], 70)
		assert_eq(_outcomes(out), [], "2.05 m off at %.0f degrees: not hit" % rad_to_deg(around))
		_end(out)
	var run := _fight(4.0, [], _slam_steps())
	var heavy: Actor = run["heavy"]
	await Duel.play_to(self, heavy, 20)
	var warning := _rings().filter(func(n: Node) -> bool: return n.is_in_group(&"slam_warning"))
	assert_eq(warning.size(), 1)
	assert_near((warning[0] as SlamRing).shown_radius(), RING, 0.03, "the warning is drawn at the reach")
	await Duel.play_to(self, heavy, SLAM_ON + 1)
	var waves := get_tree().get_nodes_in_group(GroundWave.GROUP).filter(func(n: Node) -> bool: return n.get_parent().is_in_group(&"slam_wave"))
	assert_eq(waves.size(), 1, "the wave")
	assert_near((waves[0] as GroundWave).radius(), RING, 0.1, "starts at the reach (%.2f m)" % (waves[0] as GroundWave).radius())


func test_the_ring_goes_when_the_slam_is_cut() -> void:
	var run := _fight(4.0, [], _slam_steps())
	var heavy: Actor = run["heavy"]
	await Duel.play_to(self, heavy, 9)
	assert_eq(_rings().filter(func(n: Node) -> bool: return n.is_in_group(&"slam_warning")).size(), 1, "the ring is lit")
	track(PostureBreaker.make(run["abarax"], heavy))
	await Duel.play_to(self, heavy, 13)
	assert_eq(heavy.runner.current.id, &"posture_broken", "the slam was cut")
	assert_eq(_rings().filter(func(n: Node) -> bool: return n.is_in_group(&"slam_warning")).size(), 0, "and the ring went with it")


func test_the_ring_is_full_through_the_live_frames() -> void:
	var run := _fight(4.0, [], _slam_steps())
	var heavy: Actor = run["heavy"]
	for frame in range(SLAM_ON + 1, SLAM_OFF + 2):
		await Duel.play_to(self, heavy, frame)
		var warning := _rings().filter(func(n: Node) -> bool: return n.is_in_group(&"slam_warning"))
		assert_eq(warning.size(), 1, "the full ring is lit on frame %d" % frame)
		if warning.size() == 1:
			assert_near((warning[0] as SlamRing).shown_radius(), RING, 0.03, "at the reach, frame %d" % frame)


# The dash-step's forward is the way he faces: away from the heavy is the stick pushed along +Z for a body standing on +Z.
const AWAY := Vector2(0, 1)


func _dash_away_at(frame: int, hold := 20) -> Array:
	return [{"frames": frame - 1}, {"frames": 1, "press": [&"dodge"], "move": AWAY}, {"frames": hold, "move": AWAY}, {"frames": 200}]


func _hop_at(frame: int) -> Array:
	return [{"frames": frame - 1}, {"frames": 1, "press": [&"dodge"]}, {"frames": 200}]


func test_the_slam_is_left_by_a_dash_step_and_hopped_and_nothing_else_saves_him() -> void:
	# A dash-step straight away begun on the heavy's frame 27, twelve frames before the blow's first (39), is clear of the ring
	# from contact outward: 1.3 m takes a body from 0.8 m to 2.1 m.
	for gap: float in [0.8, 1.2, 1.6, 1.9]:
		var dash := _fight(gap, _dash_away_at(27), _slam_steps())
		await Duel.play_to(self, dash["heavy"], 70)
		assert_eq(_outcomes(dash), [], "a dash-step away begun 12 frames before the blow, from %.1f m: missed" % gap)
		_end(dash)
	# A hop, up from frame 27: its airborne marks cover the whole blow, which passes under, from any distance.
	for gap: float in [0.8, 1.4, 1.9]:
		var hop := _fight(gap, _hop_at(27), _slam_steps())
		await Duel.play_to(self, hop["heavy"], 70)
		assert_eq(_outcomes(hop), [], "a hop over it from %.1f m: missed" % gap)
		_end(hop)
	# Nothing else: a guard is broken through, a sway and a duck do not evade a low blow, and standing still is hit.
	var guard := _fight(1.0, [{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 200, "hold": [&"guard"]}], _slam_steps())
	await Duel.play_to(self, guard["heavy"], SLAM_ON)
	assert_true((guard["abarax"] as Actor).is_guarding(), "his guard is up")
	await Duel.play_to(self, guard["heavy"], 70)
	assert_eq(_outcomes(guard), ["HIT"], "a guard is broken through: the blow lands whole, not guarded")
	_end(guard)
	for evade: StringName in [&"sway_left_slip", &"duck_slip"]:
		var run := _fight(1.0, [{"frames": 33}, {"frames": 200}], _slam_steps())
		var abarax: Actor = run["abarax"]
		await Duel.play_to(self, abarax, 33)
		abarax.runner.start(_move(evade))
		await Duel.play_to(self, run["heavy"], SLAM_ON)
		assert_true(abarax.runner.evading != MoveData.Evade.NONE, "%s's evade window is open at the blow" % evade)
		await Duel.play_to(self, run["heavy"], 70)
		assert_eq(_outcomes(run), ["HIT"], "%s does not evade a low blow" % evade)
		_end(run)
	var still := _fight(1.0, [], _slam_steps())
	await Duel.play_to(self, still["heavy"], 70)
	assert_eq(_outcomes(still), ["HIT"], "standing there is hit")
	_end(still)
	# And a hop that is not over it: up too early (down before the blow) or too late.
	var early := _fight(0.8, _hop_at(1), _slam_steps())
	await Duel.play_to(self, early["heavy"], 70)
	assert_eq(_outcomes(early), ["HIT"], "a hop that has landed before the blow does not save him")


func test_the_slam_gives_at_least_thirty_frames_of_tell() -> void:
	var tell := _mark_frame(&"heavy_slam", &"tell")
	assert_true(tell >= 0 and SLAM_ON - tell >= 30, "the tell at f%d, the blow at f%d" % [tell, SLAM_ON])
	# And it shows for the whole of it: the icon over the head and the armour from the tell to the last hitbox_off.
	var run := _fight(3.5, [], _slam_steps())
	var heavy: Actor = run["heavy"]
	var fx := heavy.get_node("ActorFx") as ActorFx
	var shown := 0
	for frame in range(1, SLAM_OFF + 3):
		await Duel.play_to(self, heavy, frame)
		if frame > tell + 1 and frame <= SLAM_OFF:
			assert_eq(fx.icon_shape, HitProfile.Perilous.SWEEP, "the sweep's icon is up on frame %d" % frame)
			shown += 1
		if frame >= 3 and frame <= SLAM_ON:
			assert_true(heavy.runner.hyperarmour, "armoured on frame %d" % frame)
	assert_true(shown >= 30, "for %d frames" % shown)
	assert_eq(fx.icon_shape, HitProfile.Perilous.NONE, "gone after the blow")


func _rings() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"slam_ring").filter(func(n: Node) -> bool: return is_instance_valid(n))


func test_the_slam_shows_its_ring_on_the_ground_before_it_hits_and_a_wave_at_the_blow() -> void:
	var run := _fight(4.0, [], _slam_steps())
	var heavy: Actor = run["heavy"]
	var colour := ActorFx.TUNING.wave_color
	await Duel.play_to(self, heavy, SLAM_ON - 10)
	var warnings := _rings().filter(func(n: Node) -> bool: return n.is_in_group(&"slam_warning"))
	assert_eq(warnings.size(), 1, "a ring lies on the ground before the blow")
	if not warnings.is_empty():
		var ring := warnings[0] as SlamRing
		assert_near(ring.radius, RING, 1e-6, "of the slam's own reach")
		assert_vec_near(Vector3(ring.global_position.x, 0, ring.global_position.z), Vector3.ZERO, 1e-3, "from his feet")
		var lie := (ring.get_node("Mesh") as Node3D).global_position.y
		assert_true(lie > 0.0 and lie < 0.1, "on the ground, not in the air (y %.3f)" % lie)
		assert_true(ring.shown_radius() >= RING - 1e-6, "all the way out at once: it shows where the blow will land (%.2f m)" % ring.shown_radius())
		assert_true(ring.shown_colour().is_equal_approx(colour), "in the sweep's tell colour")
	var waves := get_tree().get_nodes_in_group(GroundWave.GROUP).size()
	await Duel.play_to(self, heavy, SLAM_ON + 2)
	var wave_rings := _rings().filter(func(n: Node) -> bool: return n.is_in_group(&"slam_wave"))
	assert_eq(wave_rings.size(), 1, "a wave goes out at the blow")
	var made := get_tree().get_nodes_in_group(GroundWave.GROUP).filter(func(n: Node) -> bool: return n.get_parent().is_in_group(&"slam_wave"))
	assert_eq(made.size(), 1, "a GroundWave from the ring outward (%d waves before)" % waves)
	for wave: GroundWave in made:
		var material := (wave.get_node("Mesh") as MeshInstance3D).material_override as ShaderMaterial
		assert_true((material.get_shader_parameter(&"ring_color") as Color).is_equal_approx(colour), "in the tell's colour, not the clear-out's gold")
		assert_true(absf(wave.global_position.y - GroundWave.LIFT) < 1e-4, "on the ground")


func _string_after(heavy_steps: Array, gap: float, evade: StringName, evade_at: int, string_at: int) -> Dictionary:
	# Abarax evades the heavy's move (the evade started on its frame `evade_at`), and presses his palm string from frame
	# `string_at`: jab, cross and hook, each pressed as the window of the one before opens. {landed: the frames of the heavy on which
	# his blows landed on it, run}.
	var steps := [{"frames": string_at - 1}, {"frames": 1, "press": [&"palm"]}, {"frames": 15}, {"frames": 1, "press": [&"palm"]},
			{"frames": 19}, {"frames": 1, "press": [&"palm"]}, {"frames": 300}]
	var run := _fight(gap, steps, heavy_steps)
	var heavy: Actor = run["heavy"]
	var abarax: Actor = run["abarax"]
	var landed: Array[int] = []
	heavy.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if e.attacker == abarax and r.outcome == O.HIT:
			landed.append(heavy.frame))
	await Duel.play_to(self, heavy, evade_at)
	abarax.runner.start(_move(evade))
	await Duel.play_to(self, heavy, 260)
	return {"landed": landed, "run": run}


func test_its_recovery_takes_a_full_palm_string() -> void:
	# The string is counted by its blows that land, not by how long it takes. After a dodged slam (a hop on frame 27; the heavy is
	# in the slam until frame 86 and rests at least a quarter off attack_rest after it) all three land before the heavy can act
	# again; after a dodged haymaker (a duck, whose counter window is over before the jab) at least the jab and the cross do.
	var rest := int(floor((load(HEAVY_BRAIN) as BrainDef).attack_rest * 0.75 * Marks.RATE))
	var slam := await _string_after(_slam_steps(), 1.0, &"hop", 27, 62)
	var free_at := _clip_frames(&"heavy_slam") + rest
	assert_eq(slam["landed"].size(), 3, "after a hopped slam all three blows land (%s)" % [slam["landed"]])
	assert_true(slam["landed"].is_empty() or slam["landed"][slam["landed"].size() - 1] <= free_at,
			"and by frame %d, when he can act again (%s)" % [free_at, slam["landed"]])
	_end(slam["run"])
	var hay := await _string_after(_haymaker_steps(), 1.4, &"duck_slip", 30, 72)
	var hay_free := _clip_frames(&"heavy_haymaker") + rest
	assert_true(hay["landed"].size() >= 2, "after a ducked haymaker at least the jab and the cross land (%s)" % [hay["landed"]])
	assert_true(hay["landed"].is_empty() or hay["landed"][1] <= hay_free, "by frame %d (%s)" % [hay_free, hay["landed"]])
	_end(hay["run"])


# --- a big body ---

func test_a_big_body_keeps_its_spacing_and_stays_in_the_yard() -> void:
	# The body capsule, the spacing radius, does not grow with the model: 0.35 m, as Abarax's. The hurtbox and the model do.
	var arena := TestArena.make(self)
	var heavy := TestArena.spawn(arena, _heavy_def(), ScriptBrain.new([]), Vector3.ZERO, "Heavy")
	var abarax := TestArena.spawn(arena, load(ABARAX) as ActorDef, ScriptBrain.new([]), Vector3(0, 0, 3.0), "Abarax")
	await frames(2)
	assert_near(heavy.spacing.radius(), BODY, 1e-6, "its body capsule is the usual 0.35 m")
	var hurt := heavy.rig.hurtbox.get_node(^"shape") as CollisionShape3D
	assert_near(hurt.global_basis.get_scale().y, 1.18, 1e-4, "its hurtbox grew with it")
	var model := heavy.rig.get_node(^"Model") as Node3D
	assert_near(model.scale.y, 1.18, 1e-6, "and the model")
	var ring := heavy.rig.get_node(^"Hitboxes/slam_ring/zone/shape") as CollisionShape3D
	assert_near((ring.shape as CylinderShape3D).radius, HITBOX, 1e-6, "the slam's hitbox is 1.65 m (2.0 m to a body's centre) whatever the size of the body")
	assert_near((ring.shape as CylinderShape3D).height, 0.5, 1e-6, "and 0.5 m high")
	assert_near(ring.global_basis.get_scale().x, 1.0, 1e-6, "it is not scaled with the model")
	assert_true(ring.global_position.y < 0.3, "at the feet")
	var palm := heavy.rig.get_node(^"Hitboxes/palm_r/zone/shape") as CollisionShape3D
	assert_near(palm.global_basis.get_scale().x, 1.18, 1e-4, "the hands' hitboxes ride the model and reach further")
	# It walks into Abarax and stops at his body.
	abarax.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.5)))
	for i in 90:
		heavy.push(Vector3(0, 0, 4.0))
		await frames(1)
	var gap := Vector2(heavy.global_position.x - abarax.global_position.x, heavy.global_position.z - abarax.global_position.z).length()
	assert_true(gap >= 2.0 * BODY - 0.02, "shoved into Abarax it stops at his body (%.2f m)" % gap)


func test_a_big_body_is_held_in_the_yard() -> void:
	const YARD := "res://world/training_yard/training_yard.tscn"
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]:
		var region: Node = track((load(YARD) as PackedScene).instantiate())  # not `as Region`: that cast keeps the script alive at exit
		var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
		actor.def = _heavy_def()
		actor.position = Vector3(corner.x * 11.5, 0.0, corner.y * 11.5)
		actor.set_brain(Brain.new())
		region.add_child(actor)
		await frames(2)
		for i in 60:
			actor.push(Vector3(corner.x, 0.0, corner.y) * 5.0)
			await frames(1)
		assert_true(absf(actor.global_position.x) < 12.5 and absf(actor.global_position.z) < 12.5, "the heavy at the corner %s stays inside (%s)" % [corner, actor.global_position])
		region.queue_free()
		await frames(1)


# --- a clear-out and friends ---

func test_a_clear_out_throws_it_and_does_not_stagger_it() -> void:
	# Abarax's clear-out lands on it in the slam's wind-up (armoured): it goes the whole way it would go unarmoured and the
	# slam plays on from where it lands. The control is the same body in no move at all.
	var armoured := _fight(0.9, [{"frames": 1}], _slam_steps())
	var heavy: Actor = armoured["heavy"]
	var abarax: Actor = armoured["abarax"]
	var elsewhere := Vector3(60, 0, 0)
	var control := _fight(0.9, [], [{"frames": 200}], 0.0, null, elsewhere)
	var still: Actor = control["heavy"]
	await Duel.play_to(self, abarax, 2)
	abarax.runner.start(_move(&"clear_wave"))
	(control["abarax"] as Actor).runner.start(_move(&"clear_wave"))
	var reactions: Array[StringName] = []
	heavy.runner.move_started.connect(func(m: MoveData) -> void: reactions.append(m.id))
	await Duel.play_to(self, heavy, 34)
	assert_true(heavy.runner.hyperarmour, "armoured as it is thrown")
	var thrown := Vector2(heavy.global_position.x, heavy.global_position.z).length()
	var control_thrown := Vector2(still.global_position.x - elsewhere.x, still.global_position.z - elsewhere.z).length()
	assert_true(control_thrown > 1.0, "the control was thrown (%.2f m)" % control_thrown)
	assert_near(thrown, control_thrown, 0.15, "it was thrown its full distance, armoured (%.2f m against %.2f m)" % [thrown, control_thrown])
	assert_eq(reactions, [], "and no reaction began")
	assert_eq(heavy.runner.current.id, &"heavy_slam", "the slam plays on where it landed")
	assert_false(heavy.is_in_group(Actor.FINISHABLE_GROUP), "it does not reel")


func test_the_slam_does_not_hit_other_knuckles() -> void:
	var arena := TestArena.make(self)
	var heavy := TestArena.spawn(arena, _heavy_def(), ScriptBrain.new(_slam_steps()), Vector3.ZERO, "Heavy")
	heavy.place(Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var friends: Array[Actor] = []
	for at: Vector3 in [Vector3(0.9, 0, 0.3), Vector3(-1.7, 0, -0.5)]:
		var friend := TestArena.spawn(arena, load(KNUCKLE_1) as ActorDef, ScriptBrain.new([]), at, "Friend")
		friend.place(Transform3D(Basis(Vector3.UP, PI), at))
		friends.append(friend)
	var seen: Array[Array] = []
	for friend in friends:
		friend.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
			if r.outcome != O.WHIFF:
				seen.append([friend.name, r.outcome]))
	# Abarax, 1.5 m off, is hit: the ring is live and reaches the player's side.
	var abarax := TestArena.spawn(arena, load(ABARAX) as ActorDef, ScriptBrain.new([]), Vector3(0, 0, 1.6), "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.6)))
	var got: Array[int] = []
	abarax.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
		if r.outcome != O.WHIFF:
			got.append(r.outcome))
	await Duel.play_to(self, heavy, 70)
	assert_eq(got, [O.HIT], "the ring was live: it hit Abarax")
	assert_eq(seen, [], "and no Knuckle inside it")
	for friend in friends:
		assert_eq(friend.stats.hp, friend.def.max_hp, "%s is unhurt" % friend.name)


func test_the_brain_chooses_the_slam_only_with_abarax_inside_its_ring() -> void:
	# Real brain, real fight: Abarax stands still at 1.2 m. Whenever it starts the slam he is within 2.2 m; and over a long
	# fight both moves are thrown.
	var arena := TestArena.make(self)
	var abarax_def := (load(ABARAX) as ActorDef).duplicate() as ActorDef
	abarax_def.max_hp = 100000.0
	var abarax := TestArena.spawn(arena, abarax_def, Brain.new(), Vector3.ZERO, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var def := _heavy_def().duplicate() as ActorDef
	var heavy := TestArena.spawn(arena, def, EnemyBrain.new(def.brain, 11), Vector3(0, 0, 3.0), "Heavy")
	heavy.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 3.0)))
	var started: Array = []
	heavy.runner.move_started.connect(func(m: MoveData) -> void:
		started.append([m.id, Vector2(heavy.global_position.x - abarax.global_position.x, heavy.global_position.z - abarax.global_position.z).length()]))
	while heavy.frame < 60 * 40:
		await frames(1)
		if started.any(func(s: Array) -> bool: return s[0] == &"heavy_slam") and started.any(func(s: Array) -> bool: return s[0] == &"heavy_haymaker"):
			break
	assert_true(started.any(func(s: Array) -> bool: return s[0] == &"heavy_haymaker"), "it throws the haymaker: %s" % [started])
	assert_true(started.any(func(s: Array) -> bool: return s[0] == &"heavy_slam"), "and the slam: %s" % [started])
	for s: Array in started:
		if s[0] == &"heavy_slam":
			assert_true(s[1] <= CHOSEN + 0.05, "the slam was started with Abarax %.2f m off" % s[1])
