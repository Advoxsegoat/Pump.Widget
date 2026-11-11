extends TestCase
## Counters and clear-outs (spec 3.4): after a sway or a duck that evaded a blow, the next palm within 24 frames is that dodge's
## counter and the next heavy its clear-out; after one that avoided nothing they are the ordinary jab and heavy. A counter or
## clear-out cashes the chain in: its blow is worth what the tempo the chain had reached says (x1, x1.5, x2), a clear-out
## throws 2, 2.5 or 3 m, and a Flurry counter staggers whatever the poise.
##
## `a` is Abarax (a PLAYER) at the origin facing +Z, `b` an ENEMY copy a metre in front (Duel). A sway pressed on frame P
## has its evade window open for blows on frames P+3 to P+12 and its cancel window from frame P+12 (Slip); a duck's from P+14.
## Blows are posted by hand (Blows). A counter is started either by those presses or, where a test is about the blow and not
## the press, by the runner directly (`a.runner.start`), which cashes the chain as a press would.

const ABARAX := "res://data/actors/abarax.tres"
const TUNING := "res://data/tuning/chain_open_hand.tres"
const ROUND := HitProfile.Line.ROUND
const SWAY := &"sway"
const DUCK := &"duck"
const PALM := &"palm"
const HEAVY := &"heavy"
const T := DodgeChain.Tempo
## The clip's frames, by move: the frame its blow is on by, and the longest the move may be.
const BLOW_BY := {&"counter_hook": 8, &"counter_rise": 9}
const LONGEST := {&"counter_hook": 34, &"counter_rise": 38, &"clear_backpalm": 44, &"clear_wave": 48}
const COUNTERS := {&"counter_hook": 12.0, &"counter_rise": 14.0, &"clear_backpalm": 4.0, &"clear_wave": 3.0}


# A ScriptBrain's steps for `presses`, each [frame, [actions]]: the actions are pressed on that actor frame.
static func _script(presses: Array) -> Array:
	var steps := []
	var at := 0
	for press: Array in presses:
		var gap: int = press[0] - at - 1
		if gap > 0:
			steps.append({"frames": gap})
		steps.append({"frames": 1, "press": press[1]})
		at = press[0]
	return steps


# {arena, a, b, started, hits}: `a` plays `steps`; `started` is [frame, id] of each move it started, `hits` the results of the blows
# of a's that landed ([frame of a, outcome]).
func _world(steps := [], b_def: ActorDef = null) -> Dictionary:
	var run := Duel.make(self, steps, [], 1.0, b_def)
	var a: Actor = run["a"]
	run["started"] = []
	run["hits"] = []
	run["cashed"] = []
	var started: Array = run["started"]
	a.runner.move_started.connect(func(move: MoveData) -> void: started.append([a.frame, move.id]))
	var hits: Array = run["hits"]
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: hits.append([a.frame, r.outcome]))
	var cashed: Array = run["cashed"]
	a.chain.cashed.connect(func(at: DodgeChain.Tempo) -> void: cashed.append(at))
	return run


# Plays until `a` has lived `last` frames, posting the `blows` ([frame to land on, profile fields]) from `b` on the way.
func _play(run: Dictionary, blows: Array, last: int) -> void:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	while a.frame < last:
		for blow: Array in blows:
			if blow[0] == a.frame + 1:
				Blows.post(b, a, blow[1])
		await frames(1)


# Takes `run`'s fighters out of the world: runs of one test stand in one physics space, and bodies of an earlier run left standing at
# the same place would shove the next run's about.
func _free(run: Dictionary) -> void:
	(run["arena"] as Node).queue_free()
	await frames(2)


static func _ids(run: Dictionary) -> Array:
	return (run["started"] as Array).map(func(s: Array) -> StringName: return s[1])


static func _id_at(run: Dictionary, id: StringName) -> int:
	for s: Array in run["started"]:
		if s[1] == id:
			return s[0]
	return -1


# Gives `a` a chain of `count`, made on its frame 0.
func _prime(run: Dictionary, count: int) -> void:
	for i in count:
		(run["a"] as Actor).chain.link(false, 0)


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


# A move's clip, from the library's files (no rig is made: a stray body's hurtbox would stand in the way of a blow).
func _clip(id: StringName) -> Animation:
	return load("res://assets/anim/abarax/%s.tres" % _move(id).clip) as Animation


func _marks(id: StringName) -> Array[Dictionary]:
	return Marks.read(_clip(id))


func _mark_frame(id: StringName, kind: StringName) -> int:
	for m in _marks(id):
		if m["kind"] == kind:
			return roundi(float(m["time"]) * Marks.RATE)
	return -1


func _length(id: StringName) -> int:
	return roundi(_clip(id).length * Marks.RATE)


# --- which move a press starts ---

func test_palm_after_an_evade_is_the_dodges_counter_and_heavy_its_clear_out() -> void:
	# a sway pressed on f10 evades a round blow on f14, a duck pressed on f10 one on f14; the press comes at f16, within the buffer, and
	# starts when the dodge's cancel window opens
	var cases := [[SWAY, PALM, &"counter_hook"], [SWAY, HEAVY, &"clear_backpalm"], [DUCK, PALM, &"counter_rise"], [DUCK, HEAVY, &"clear_wave"]]
	for c: Array in cases:
		var run := _world(_script([[10, [c[0]]], [16, [c[1]]]]))
		await _play(run, [[14, {"line": ROUND}]], 40)
		assert_true(_ids(run).has(c[2]), "%s then %s starts %s (started %s)" % [c[0], c[1], c[2], _ids(run)])
		assert_false(_ids(run).has(&"palm_jab") or _ids(run).has(&"palm_heavy"), "and not the ordinary move")
		await _free(run)
	# every sway and duck move says so in its data: the Slip, Quick and Flurry moves and each side
	for id: StringName in [&"sway_left_slip", &"sway_right_slip", &"sway_back_slip", &"sway_left_quick", &"sway_right_quick",
			&"sway_back_quick", &"sway_left_flurry", &"sway_right_flurry", &"sway_back_flurry"]:
		assert_eq(_move(id).counters, {PALM: &"counter_hook", HEAVY: &"clear_backpalm"}, "%s's counters" % id)
	for id: StringName in [&"duck_slip", &"duck_quick", &"duck_flurry"]:
		assert_eq(_move(id).counters, {PALM: &"counter_rise", HEAVY: &"clear_wave"}, "%s's counters" % id)
	for id: StringName in [&"counter_hook", &"counter_rise", &"clear_backpalm", &"clear_wave"]:
		assert_true(_move(id).cashes, "%s cashes the chain in" % id)
	assert_false(_move(&"palm_jab").cashes, "an ordinary move does not")


func test_palm_after_a_dodge_that_avoided_nothing_is_the_jab() -> void:
	for c: Array in [[SWAY, PALM, &"palm_jab"], [SWAY, HEAVY, &"palm_heavy"], [DUCK, PALM, &"palm_jab"], [DUCK, HEAVY, &"palm_heavy"]]:
		var run := _world(_script([[10, [c[0]]], [16, [c[1]]]]))
		await _play(run, [], 50)
		assert_true(_ids(run).has(c[2]), "%s that avoided nothing, then %s: %s (started %s)" % [c[0], c[1], c[2], _ids(run)])
		for counter: StringName in COUNTERS:
			assert_false(_ids(run).has(counter), "no %s" % counter)
		await _free(run)


func test_the_counter_window_is_twenty_four_frames_and_frozen_frames_do_not_count() -> void:
	assert_eq(MoveRunner.COUNTER_FRAMES, 24, "the window")
	# the blow is evaded on f14 (the chain's link is stamped with the actor's buffer_frame); from rest, a palm pressed 24 frames after
	# is the counter and one 25 frames after is the jab
	for case: Array in [[38, &"counter_hook"], [39, &"palm_jab"]]:
		var run := _world(_script([[10, [SWAY]], [case[0], [PALM]]]))
		await _play(run, [[14, {"line": ROUND}]], 60)
		assert_true(_ids(run).has(case[1]), "a palm on frame %d is %s (started %s)" % [case[0], case[1], _ids(run)])
		await _free(run)
	# ten frames of hit-stop after the evade move both presses ten frames later on the wall clock and no further on the actor's
	for case: Array in [[48, &"counter_hook"], [49, &"palm_jab"]]:
		var run := _world(_script([[10, [SWAY]], [case[0], [PALM]]]))
		var a: Actor = run["a"]
		while a.frame < 70:
			if a.frame + 1 == 14:
				Blows.post(run["b"], a, {"line": ROUND})
			if a.frame == 20:
				a.freeze(10)
			await frames(1)
		assert_true(_ids(run).has(case[1]), "with ten frames frozen, a palm on frame %d is %s (started %s)" % [case[0], case[1], _ids(run)])
		await _free(run)


func test_a_counter_started_after_another_move_is_the_ordinary_move() -> void:
	# a dash-step between the evade and the palm: the counter was the sway's, and the dash-step has taken its place
	var run := _world(_script([[10, [SWAY]], [22, [&"dodge"]], [110, [PALM]]]))
	await _play(run, [[14, {"line": ROUND}]], 130)
	assert_true(_ids(run).has(&"hop") or _ids(run).has(&"dash_step"), "the dash-step started (%s)" % [_ids(run)])
	assert_true(_ids(run).has(&"palm_jab"), "and the palm after it is the jab, not the counter (started %s)" % [_ids(run)])
	assert_false(_ids(run).has(&"counter_hook"), "no counter")


# --- the blow comes at once ---

func test_each_counters_blow_comes_by_its_frame() -> void:
	for id: StringName in BLOW_BY:
		var on := _mark_frame(id, &"hitbox_on")
		assert_true(on > 0 and on <= int(BLOW_BY[id]), "%s: hitbox_on on f%d, by f%d" % [id, on, BLOW_BY[id]])
	assert_eq(_mark_frame(&"clear_backpalm", &"hitbox_on"), 12, "the back palm's blow starts on f12")
	assert_eq(_mark_frame(&"clear_backpalm", &"hitbox_off"), 16, "and ends on f16")
	assert_eq(_mark_frame(&"clear_wave", &"hitbox_on"), 14, "the wave's starts on f14")
	assert_eq(_mark_frame(&"clear_wave", &"hitbox_off"), 18, "and ends on f18")
	for id: StringName in LONGEST:
		var length := _length(id)
		assert_true(length > 0 and length <= int(LONGEST[id]), "%s is %d frames, at most %d" % [id, length, LONGEST[id]])
		assert_true(_mark_frame(id, &"recovery") > 0, "%s has a recovery mark" % id)
		var window := {}
		for m in _marks(id):
			if m["kind"] == &"cancel_open":
				window = m["args"]["into"]
		assert_eq(window.get(&"dodge"), &"dash_step", "%s's window: dash-step" % id)
		assert_eq(window.get(&"guard"), &"guard_raise", "guard")
		assert_eq(window.get(&"palm"), &"palm_jab", "a string goes on with the jab")
		assert_eq(window.get(&"sway"), &"sway_left_slip", "a sway")
		assert_eq(window.get(&"duck"), &"duck_slip", "a duck")
		assert_eq(_move(id).stamina_cost, 8.0 if id == &"counter_hook" or id == &"counter_rise" else 20.0, "%s's stamina" % id)
	# in play: from the press that starts it, the hook lands on a body in reach within its frames
	var run := _world([])
	var a: Actor = run["a"]
	a.runner.start(_move(&"counter_hook"))
	var started := a.frame
	await frames(1)
	var seen := []
	a.hit_landed.connect(func(_r: HitResult, _e: HitEvent) -> void: seen.append(a.frame))
	await frames(20)
	var landed: int = seen[0] if not seen.is_empty() else -1
	assert_true(landed > 0 and landed - started <= 10, "the hook lands by its f%d (landed %d frames after it started)" % [BLOW_BY[&"counter_hook"], landed - started])


# --- what it is worth ---

func test_a_counter_is_worth_what_its_tempo_says() -> void:
	for id: StringName in [&"counter_hook", &"counter_rise"]:
		var damage := (_move(id).hits.values()[0] as HitProfile).damage
		var posture := (_move(id).hits.values()[0] as HitProfile).posture_damage
		for tempo in 3:
			var run := _world([], Duel.def(ActorDef.Team.ENEMY, 1000.0))
			var a: Actor = run["a"]
			var b: Actor = run["b"]
			_prime(run, [0, 3, 7][tempo])
			a.runner.start(_move(id))
			await frames(30)
			var scale: float = [1.0, 1.5, 2.0][tempo]
			assert_eq(a.cashed_tempo, tempo, "%s cashes at tempo %d" % [id, tempo])
			assert_near(b.stats.max_hp - b.stats.hp, damage * scale, 0.01, "%s at tempo %d: damage x%s" % [id, tempo, scale])
			assert_near(b.stats.max_posture - b.stats.posture, posture * scale, 0.01, "%s at tempo %d: posture damage x%s" % [id, tempo, scale])
			assert_eq(a.chain.count, 0, "the chain is spent")
			await _free(run)


func test_a_flurry_counter_staggers_a_foe_whose_poise_would_shrug_it_off() -> void:
	for id: StringName in [&"counter_hook", &"counter_rise"]:
		for tempo in 3:
			var run := _world([], Duel.def(ActorDef.Team.ENEMY, 1000.0))
			var a: Actor = run["a"]
			var b: Actor = run["b"]
			_prime(run, [0, 3, 7][tempo])
			a.runner.start(_move(id))
			await frames(14)
			var staggered := b.runner.current != null and b.runner.current.id == &"stagger"
			assert_eq(staggered, tempo == T.FLURRY, "%s at tempo %d: staggered %s" % [id, tempo, staggered])
			await _free(run)
	# the hook, which only flinches at Slip and Quick, flinches a weak foe; the rise staggers at every tempo (its profile says so)
	var run := _world([], Duel.def(ActorDef.Team.ENEMY, 5.0))
	(run["a"] as Actor).runner.start(_move(&"counter_rise"))
	await frames(14)
	assert_eq((run["b"] as Actor).runner.current.id, &"stagger", "the rising palm staggers a foe of poise 5")
	await _free(run)
	run = _world([], Duel.def(ActorDef.Team.ENEMY, 5.0))
	(run["a"] as Actor).runner.start(_move(&"counter_hook"))
	await frames(14)
	assert_eq((run["b"] as Actor).runner.current.id, &"flinch", "the hook flinches a foe of poise 5")


# --- the clear-outs ---

func test_the_rig_has_the_clear_outs_two_hitboxes_at_its_root() -> void:
	var run := _world([])
	var a: Actor = run["a"]
	for case: Array in [[&"clear_arc", 1.8], [&"clear_ring", 2.0]]:
		var shape := a.rig.hitbox_shape(case[0])
		assert_true(shape != null and shape.shape is CylinderShape3D, "%s is a cylinder" % case[0])
		if shape == null or not shape.shape is CylinderShape3D:
			continue
		var cylinder := shape.shape as CylinderShape3D
		assert_near(cylinder.radius, case[1], 1e-6, "%s's radius" % case[0])
		assert_near(cylinder.height, 1.4, 1e-6, "%s is 1.4 m high" % case[0])
		var holder := a.rig.get_node("Hitboxes/%s" % case[0]) as Node3D
		assert_false(holder is BoneAttachment3D, "%s rides no bone: it stands at his root" % case[0])
		assert_vec_near(holder.global_position, a.global_position, 1e-4, "%s is centred on his feet (its shape stands 0.7 m up)" % case[0])
		assert_near(shape.position.y, 0.7, 1e-6, "so it spans the knee to the head")
	assert_eq(a.rig.active_hitboxes(), [], "and neither is on until a move turns it on")
	await _free(run)


func test_a_clear_out_throws_two_two_and_a_half_and_three_metres() -> void:
	# in the open, within 0.1 m: the wave throws straight away from him (+Z), the back palm to his right (-X for a body facing +Z)
	for id: StringName in [&"clear_wave", &"clear_backpalm"]:
		for tempo in 3:
			var run := _world([], Duel.def(ActorDef.Team.ENEMY, 5.0))
			var a: Actor = run["a"]
			var b: Actor = run["b"]
			_prime(run, [0, 3, 7][tempo])
			var from := b.global_position
			a.runner.start(_move(id))
			await frames(150)
			var moved := b.global_position - from
			var want: float = [2.0, 2.5, 3.0][tempo]
			var along := moved.z if id == &"clear_wave" else -moved.x
			var across := absf(moved.x) if id == &"clear_wave" else absf(moved.z)
			assert_near(along, want, 0.1, "%s at tempo %d throws %s m (moved %s)" % [id, tempo, want, moved])
			assert_true(across < 0.15, "%s throws straight (off by %.2f)" % [id, across])
			await _free(run)


func test_the_back_palm_hits_only_inside_its_arc_and_the_wave_all_round() -> void:
	# three bodies 1.2 m from him at 0, 60 and 120 degrees off his facing (the back palm's arc is 150, 75 either side), and for the
	# wave at 0, 120 and 180
	for case: Array in [[&"clear_backpalm", [0.0, 60.0, 120.0], [true, true, false]], [&"clear_wave", [0.0, 120.0, 180.0], [true, true, true]]]:
		var run := _world([], Duel.def(ActorDef.Team.ENEMY, 5.0))
		var a: Actor = run["a"]
		(run["b"] as Actor).queue_free()
		await frames(1)
		var bodies: Array[Actor] = []
		var hit := {}
		for angle: float in case[1]:
			var at := Vector3(sin(deg_to_rad(angle)), 0.0, cos(deg_to_rad(angle))) * 1.2
			var body := TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), at, "T%d" % int(angle))
			bodies.append(body)
			body.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: hit[body] = r.outcome)
		await frames(2)
		a.runner.start(_move(case[0]))
		await frames(30)
		for i in bodies.size():
			assert_eq(hit.has(bodies[i]), case[2][i], "%s: the body at %d degrees is hit: %s" % [case[0], case[1][i], case[2][i]])
		await _free(run)


func test_the_back_palm_parts_those_in_front_of_him() -> void:
	# three bodies 1.2 m from him at 70 degrees to his left (+X), dead ahead and 70 degrees to his right: each is thrown square to his
	# facing, to the side it stands on (dead ahead, to his right), so nobody is dragged across his front
	var run := _world([], Duel.def(ActorDef.Team.ENEMY, 5.0))
	var a: Actor = run["a"]
	(run["b"] as Actor).queue_free()
	await frames(1)
	var bodies: Array[Actor] = []
	var starts: Array[Vector3] = []
	for angle: float in [70.0, 0.0, -70.0]:
		var at := Vector3(sin(deg_to_rad(angle)), 0.0, cos(deg_to_rad(angle))) * 1.2
		bodies.append(TestArena.spawn(run["arena"], Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), at, "T%d" % int(angle)))
		starts.append(at)
	await frames(2)
	a.runner.start(_move(&"clear_backpalm"))
	var crossed := [false, false, false]
	for i in 150:
		await frames(1)
		if i < 20:
			continue
		for x in 3:
			# left body must stay at x >= 0 (his left is +X), the others at x <= 0
			var side := bodies[x].global_position.x
			if (x == 0 and side < -0.05) or (x > 0 and side > 0.05):
				crossed[x] = true
	var names := ["left", "ahead", "right"]
	for x in 3:
		var moved := bodies[x].global_position - starts[x]
		assert_near(moved.length(), 2.0, 0.1, "the body %s travelled 2 m (moved %s)" % [names[x], moved])
		assert_false(crossed[x], "the body %s never crossed to the other side of him" % names[x])
		var far := Vector2(bodies[x].global_position.x - a.global_position.x, bodies[x].global_position.z - a.global_position.z).length()
		assert_true(far >= 2.2, "the body %s ends %.2f m from him (at least 2.2)" % [names[x], far])
		assert_true((bodies[x].global_position.x > 0.0) == (x == 0), "the body %s ends on its own side (x %.2f)" % [names[x], bodies[x].global_position.x])
	await _free(run)


# --- presses at awkward moments, and a miss ---

func test_a_counter_refused_for_stamina_cashes_nothing() -> void:
	# the same press with stamina to pay for it is the counter and cashes the chain in (the control)
	var control := _world(_script([[10, [SWAY]], [16, [PALM]]]))
	await _play(control, [[14, {"line": ROUND}]], 40)
	assert_true(_ids(control).has(&"counter_hook"), "with stamina the palm is the counter (started %s)" % [_ids(control)])
	assert_eq((control["cashed"] as Array).size(), 1, "and it cashed the chain")
	await _free(control)
	# exhausted when the palm is taken: nothing starts, the press is used up, and the chain he had is still his
	var run := _world(_script([[10, [SWAY]], [16, [PALM]]]))
	var a: Actor = run["a"]
	while a.frame < 40:
		if a.frame + 1 == 14:
			Blows.post(run["b"], a, {"line": ROUND})
		if a.frame == 15:
			a.stats.stamina = 0.0
			a.stats.exhausted = true
		await frames(1)
	assert_false(_ids(run).has(&"counter_hook") or _ids(run).has(&"palm_jab"), "no counter and no jab (started %s)" % [_ids(run)])
	assert_eq((run["cashed"] as Array).size(), 0, "nothing was cashed")
	assert_eq(a.chain.count, 1, "the chain is still one evade long")
	assert_eq(a.cashed_tempo, T.SLIP, "and nothing is held as cashed")
	await _free(run)


func test_a_counter_that_misses_leaves_him_open() -> void:
	# thrown at nobody (b is five metres off), the hook cannot be cancelled before its recovery, and a blow on him meanwhile lands
	var run := _world(_script([[5, [&"dodge"]]]))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	b.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 5)))
	await frames(1)
	a.runner.start(_move(&"counter_hook"))
	var began := a.frame
	var taken := []
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: taken.append(r.outcome))
	while a.frame < began + 6:
		await frames(1)
	assert_true(a.runner.window.is_empty(), "no cancel window open before the recovery")
	assert_eq(a.runner.current.id, &"counter_hook", "the dash-step pressed on f5 waits for it")
	assert_false(_ids(run).has(&"dash_step"), "and has not started")
	var hp := a.stats.hp
	Blows.post(b, a, {})
	await frames(2)
	assert_eq(taken, [HitResult.Outcome.HIT], "a blow in the middle of it lands on him")
	assert_true(a.stats.hp < hp, "and hurts")
