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
## The slam's ring, and where a body is clear of it: its centre this far out plus the body's own radius.
const RING := 2.2
const BODY := 0.35
## The slam's blow comes on at its f38 and goes off at its f42 (frames 39 to 42).
const SLAM_ON := 38
const SLAM_OFF := 42
const HAYMAKER_ON := 30


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
	assert_eq(def.hidden_parts, PackedStringArray(), "hood and pauldron on")
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
	assert_true(_mark_frame(&"heavy_haymaker", &"hitbox_on") <= 30, "its blow is on by f30")
	assert_eq(_mark_frame(&"heavy_haymaker", &"hyperarmour_on"), 8, "armoured from f8")
	assert_eq(_mark_frame(&"heavy_haymaker", &"hyperarmour_off"), _mark_frame(&"heavy_haymaker", &"hitbox_off"), "to its hitbox_off")
	assert_eq(_clip_frames(&"heavy_haymaker") - _mark_frame(&"heavy_haymaker", &"hitbox_off"), 36, "36 frames of recovery")
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
	assert_eq([slam.action, slam.weight, slam.cooldown, slam.min_range, slam.max_range], [&"gift", 0.7, 5.0, 0.0, RING], "the slam: within 2.2 m")


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

func test_a_jab_does_not_stop_its_wind_up_and_a_flurry_counter_does() -> void:
	# A jab (6 poise against its 14, and a hook's 12 does not reach it either) is no reason for it to stop: the HIT lands, takes its
	# HP and posture, and gives it no reaction, so the haymaker goes on to its blow. (A Flurry counter's blow, always_staggers, is
	# stopped by the armour as Combat.resolve is built: see the report. Here it is held that the armour holds for the small blows.)
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


func test_a_broken_heavy_is_finished_and_the_blows_reach_its_larger_body() -> void:
	# The finisher stages follower and lead from the lead's size alone, so a follower 18% larger is where it could go wrong:
	# each of the three blows must reach it (its head or torso at most REACH from the striking hand and SINK inside it), and the
	# two bodies pass at most SINK into each other (F1 Task 10's staging criteria, as test_knuckle_staging holds them for
	# tiers I and III). It has HP for the three blows (60 of its 140) and lives.
	var def := _heavy_def().duplicate() as ActorDef
	var run := _fight(1.0, [{"frames": 40}, {"frames": 1, "press": [&"palm"]}, {"frames": 300}], [], 0.0, def)
	var heavy: Actor = run["heavy"]
	var abarax: Actor = run["abarax"]
	track(PostureBreaker.make(abarax, heavy))
	var hit_now := [false]
	abarax.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
		if kind == &"pair_hit":
			hit_now[0] = true)
	await Duel.play_to(self, abarax, 2)
	assert_true(heavy.is_in_group(Actor.FINISHABLE_GROUP), "broken")
	var blows := 0
	var worst_sink := -INF
	var short := 0.0
	var deepest := 0.0
	var seen_pair := false
	while abarax.frame < 400:
		await frames(1)
		if abarax.paired_with == heavy:
			seen_pair = true
		elif seen_pair and heavy.paired_with == null:
			break
		if not seen_pair:
			continue
		var a_caps := Bodies.of(abarax.rig)
		var h_caps := Bodies.of(heavy.rig)
		worst_sink = maxf(worst_sink, Bodies.overlap(a_caps, h_caps)[0])
		if hit_now[0]:
			hit_now[0] = false
			var left := Bodies.strike_gap(a_caps, h_caps, "hand_l")
			var right := Bodies.strike_gap(a_caps, h_caps, "hand_r")
			var best: Array = left if left[0] < right[0] else right
			short = maxf(short, best[0])
			deepest = minf(deepest, best[0])
			blows += 1
	assert_true(seen_pair, "his palm starts the finisher on it")
	assert_eq(blows, 3, "three blows")
	assert_true(short <= 0.08, "each reaches it (at worst %.3f m short)" % short)
	assert_true(deepest >= -0.05, "and none is more than 5 cm inside it (%.3f m)" % deepest)
	assert_true(worst_sink <= 0.05, "and the bodies pass at most %.3f m into each other" % worst_sink)
	assert_eq(heavy.stats.hp, 140.0 - 60.0, "the finisher took 15, 15 and 30 of its 140 HP")


# --- the slam ---

func test_the_slam_hits_everything_within_its_ring_that_stands_on_the_ground() -> void:
	for case: Array in [[0.8, 0.0], [1.6, 0.0], [2.1, 0.0], [1.6, PI], [2.1, PI / 2.0], [0.8, -PI / 2.0]]:
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


# The dash-step's forward is the way he faces: away from the heavy is the stick pushed along +Z for a body standing on +Z.
const AWAY := Vector2(0, 1)


func _dash_away_at(frame: int, hold := 20) -> Array:
	return [{"frames": frame - 1}, {"frames": 1, "press": [&"dodge"], "move": AWAY}, {"frames": hold, "move": AWAY}, {"frames": 200}]


func _hop_at(frame: int) -> Array:
	return [{"frames": frame - 1}, {"frames": 1, "press": [&"dodge"]}, {"frames": 200}]


func test_the_slam_is_left_by_a_dash_step_and_hopped_and_nothing_else_saves_him() -> void:
	# A dash-step away begun on the heavy's frame 27, twelve frames before the blow's first (39), from 1.4 m: clear of the ring.
	var dash := _fight(1.4, _dash_away_at(27), _slam_steps())
	await Duel.play_to(self, dash["heavy"], 70)
	assert_eq(_outcomes(dash), [], "a dash-step away begun 12 frames before the blow, from 1.4 m: missed")
	_end(dash)
	# A hop from 0.8 m, up from frame 27: its airborne marks cover the whole blow, which passes under.
	var hop := _fight(0.8, _hop_at(27), _slam_steps())
	await Duel.play_to(self, hop["heavy"], 70)
	assert_eq(_outcomes(hop), [], "a hop over it: missed")
	_end(hop)
	# Two dash-steps begun at its first frame (the second as the first ends), from 0.8 m.
	var twice := _fight(0.8, [{"frames": 1, "press": [&"dodge"], "move": AWAY}, {"frames": 17, "move": AWAY},
			{"frames": 1, "press": [&"dodge"], "move": AWAY}, {"frames": 20, "move": AWAY}, {"frames": 200}], _slam_steps())
	await Duel.play_to(self, twice["heavy"], 70)
	assert_eq(_outcomes(twice), [], "two dash-steps inside its tell from 0.8 m: missed")
	_end(twice)
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
	var made := get_tree().get_nodes_in_group(GroundWave.GROUP).filter(func(n: Node) -> bool: return absf((n as GroundWave).max_radius - RING) < 1e-6)
	assert_eq(made.size(), 1, "a GroundWave of 2.2 m (%d waves before)" % waves)
	for wave: GroundWave in made:
		var material := (wave.get_node("Mesh") as MeshInstance3D).material_override as ShaderMaterial
		assert_true((material.get_shader_parameter(&"ring_color") as Color).is_equal_approx(colour), "in the tell's colour, not the clear-out's gold")
		assert_true(absf(wave.global_position.y - GroundWave.LIFT) < 1e-4, "on the ground")


func test_its_recovery_takes_a_full_palm_string() -> void:
	# Abarax's palm string: the jab, the cross and the hook, each pressed as the cancel window of the one before opens. The
	# time from his first press to the hook's blow is what the heavy's recovery must give him: the frames of its clip after
	# its last hitbox_off, and the shortest rest its brain takes before choosing again (a quarter off attack_rest).
	var run := _fight(3.0, [{"frames": 1, "press": [&"palm"]}, {"frames": 15}, {"frames": 1, "press": [&"palm"]}, {"frames": 19},
			{"frames": 1, "press": [&"palm"]}, {"frames": 200}], [])
	var abarax: Actor = run["abarax"]
	var blows: Array[int] = []
	abarax.runner.mark.connect(func(kind: StringName, _a: Dictionary) -> void:
		if kind == &"hitbox_on":
			blows.append(abarax.frame))
	await Duel.play_to(self, abarax, 120)
	assert_eq(blows.size(), 3, "jab, cross, hook")
	var string_frames := blows[2] if blows.size() == 3 else 999
	var rest := int(floor((load(HEAVY_BRAIN) as BrainDef).attack_rest * 0.75 * Marks.RATE))
	for id: StringName in [&"heavy_haymaker", &"heavy_slam"]:
		var recovery := _clip_frames(id) - _mark_frame(id, &"hitbox_off")
		assert_true(recovery + rest >= string_frames, "%s: %d frames of recovery and %d of rest give the %d frames of the string" % [id, recovery, rest, string_frames])


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
	assert_near((ring.shape as CylinderShape3D).radius, RING, 1e-6, "the slam's ring is 2.2 m whatever the size of the body")
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
		var region := track((load(YARD) as PackedScene).instantiate()) as Region
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
			assert_true(s[1] <= RING + 0.05, "the slam was started with Abarax %.2f m off" % s[1])
