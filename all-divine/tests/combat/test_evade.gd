extends TestCase
## The evade: a window on a move (evade_on at f2, evade_off later; the move's `evade` says whether it is a SWAY or a
## DUCK) in which every ordinary blow and every grab that would land is EVADED, whoever throws it. A sweep and a thrust
## go on down the rules and land. An evaded blow is spent: nobody freezes, nobody is pushed, no pair starts, the
## scanner does not hand the target back (so the same swing cannot land later), and both sides hear of it. A dodge
## that matches the blow's line (SWAY a STRAIGHT, DUCK a ROUND, either a grab) is perfect.
##
## The rule tests (the first five) are Combat.resolve over hand-made Defense and HitEvent values, as test_combat.gd does.
## The others play fixtures in an arena: an ENEMY copy of Abarax, `b`, at 1 m in front of `a` and `c`, PLAYER
## copies that swing fixture moves (the jab's clip with the hitbox marks given) at it. `b` plays a fixture evade move
## (a clip with evade_on at f8 and evade_off at f18 by default: the swings' hands, the jab's, are in reach of `b`
## only from their f10 to f29, so the window is moved there; the clip checker's frame 2 is its own test). A blow is
## judged against how `b` stood when its frame began, so a hitbox_on at f9 is the first the window avoids, and one
## at f18 the last.

const O := HitResult.Outcome
const R := HitResult.Reaction
const ABARAX := "res://data/actors/abarax.tres"
const SWAY := MoveData.Evade.SWAY
const DUCK := MoveData.Evade.DUCK
const STRAIGHT := HitProfile.Line.STRAIGHT
const ROUND := HitProfile.Line.ROUND
const PERILOUS := HitProfile.Perilous
## The fixture window: evade_on at f8, evade_off at f18.
const WINDOW_ON := 8
const WINDOW_OFF := 18


# --- the rule ---

# A palm (8 HP, 6 poise, 4 posture, 8 guard stamina, a STRAIGHT line) from straight in front, with `p` set on its profile.
func _event(p := {}) -> HitEvent:
	var profile := HitProfile.new()
	profile.damage = 8.0
	profile.poise_damage = 6.0
	profile.posture_damage = 4.0
	profile.guard_stamina = 8.0
	for field: String in p:
		profile.set(field, p[field])
	var e := HitEvent.new()
	e.profile = profile
	e.direction = Vector3(0, 0, -1)
	return e


# A defender facing +Z with poise 10 and 100 stamina, and `fields` set on it.
func _defense(fields := {}) -> Defense:
	var d := Defense.new()
	d.facing = Vector3(0, 0, 1)
	d.poise = 10.0
	d.stamina = 100.0
	for field: String in fields:
		d.set(field, fields[field])
	return d


func _resolve(d: Dictionary, p := {}) -> HitResult:
	return Combat.resolve(_event(p), _defense(d), CombatTuning.new())


func test_an_evading_body_avoids_an_ordinary_blow() -> void:
	var r := _resolve({"evading": SWAY, "poise": 5.0}, {"line": STRAIGHT})
	assert_eq(O.keys()[r.outcome], "EVADED")
	assert_true(r.perfect, "a sway against a jab is perfect")
	assert_eq([r.hp_damage, r.posture_damage, r.stamina_cost, r.attacker_posture_damage], [0.0, 0.0, 0.0, 0.0], "no damage")
	assert_eq(R.keys()[r.reaction], "NONE", "no reaction, though the poise damage reaches the poise")
	var none := _resolve({"poise": 5.0})
	assert_eq(O.keys()[none.outcome], "HIT", "the control: no evade, the blow lands")
	assert_false(none.perfect)


func test_the_other_dodge_still_avoids_but_is_not_perfect() -> void:
	for row in [[DUCK, STRAIGHT], [SWAY, ROUND]]:
		var r := _resolve({"evading": row[0]}, {"line": row[1]})
		assert_eq(O.keys()[r.outcome], "EVADED", str(row))
		assert_false(r.perfect, str(row))
	for row in [[DUCK, ROUND], [SWAY, STRAIGHT]]:
		assert_true(_resolve({"evading": row[0]}, {"line": row[1]}).perfect, str(row))


func test_a_grab_is_slipped_by_either_dodge_and_is_perfect() -> void:
	for evade in [SWAY, DUCK]:
		for line in [STRAIGHT, ROUND]:
			var r := _resolve({"evading": evade}, {"perilous": PERILOUS.GRAB, "line": line})
			assert_eq(O.keys()[r.outcome], "EVADED", "never GRABBED")
			assert_true(r.perfect, "a grab is slipped perfectly by either")
	assert_eq(O.keys()[_resolve({}, {"perilous": PERILOUS.GRAB}).outcome], "GRABBED", "the control")


func test_a_sweep_and_a_thrust_land_on_an_evading_body() -> void:
	for evade in [SWAY, DUCK]:
		for perilous in [PERILOUS.SWEEP, PERILOUS.THRUST]:
			var r := _resolve({"evading": evade, "poise": 5.0}, {"perilous": perilous})
			assert_eq(O.keys()[r.outcome], "HIT", "%s against %s" % [evade, perilous])
			assert_eq([r.hp_damage, r.posture_damage], [8.0, 4.0])
			assert_false(r.perfect)


func test_an_evade_beats_a_guard_and_a_parry_loses_to_nothing() -> void:
	var r := _resolve({"evading": SWAY, "guarding": true})
	assert_eq(O.keys()[r.outcome], "EVADED", "evading and guarding at once")
	assert_eq(r.stamina_cost, 0.0, "the guard pays nothing")
	r = _resolve({"evading": DUCK, "guarding": true, "parrying": true})
	assert_eq(O.keys()[r.outcome], "EVADED", "and parrying too")
	assert_eq(r.attacker_posture_damage, 0.0)
	# a sweep goes on down the rules, and the guard does not take it either
	r = _resolve({"evading": SWAY, "guarding": true, "parrying": true}, {"perilous": PERILOUS.SWEEP})
	assert_eq(O.keys()[r.outcome], "HIT")
	# the dead, the paired, the invulnerable and the airborne under a LOW blow are whiffed first
	for d in [{"dead": true}, {"paired": true}, {"invulnerable": true}]:
		d["evading"] = SWAY
		assert_eq(O.keys()[_resolve(d).outcome], "WHIFF", str(d))
	assert_eq(O.keys()[_resolve({"evading": SWAY, "airborne": true}, {"height": HitProfile.Height.LOW}).outcome], "WHIFF")


func test_is_perfect() -> void:
	var round_blow := HitProfile.new()
	round_blow.line = ROUND
	var grab := HitProfile.new()
	grab.perilous = PERILOUS.GRAB
	grab.line = ROUND
	assert_true(Combat.is_perfect(DUCK, round_blow))
	assert_false(Combat.is_perfect(SWAY, round_blow))
	assert_true(Combat.is_perfect(SWAY, grab))
	assert_true(Combat.is_perfect(DUCK, grab))
	assert_false(Combat.is_perfect(MoveData.Evade.NONE, round_blow), "no evade is no perfect dodge")
	assert_false(Combat.is_perfect(MoveData.Evade.NONE, grab))


# --- the window, and what Melee does with an evaded blow ---

# {arena, a, b, c, got, landed}: a and c (PLAYER) 1 m either side of b (ENEMY, poise 5), a to the south facing it and c to the
# north facing it. `got` is what b heard of each blow ([outcome name, b's frame]), `landed` what a and c heard.
func _world() -> Dictionary:
	var run := Duel.make(self, [], [], 1.0)
	var arena: Node = run["arena"]
	var c := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new([]), Vector3(0, 0, 2), "C")
	c.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 2)))
	run["c"] = c
	run["got"] = []
	run["landed"] = []
	var b: Actor = run["b"]
	b.got_hit.connect(func(r: HitResult, e: HitEvent) -> void: run["got"].append([O.keys()[r.outcome], b.frame, r.perfect, e.profile.perilous]))
	for key in ["a", "c"]:
		var actor: Actor = run[key]
		actor.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: run["landed"].append([key, O.keys()[r.outcome], b.frame, r.perfect]))
	return run


# A move for `actor`: the jab's clip carrying `marks` (the clip is 1 s long), added to its rig as `id`, with the jab's data
# and `hits` as its profiles.
func _fixture(actor: Actor, id: StringName, marks: Array, hits := {}, evade := MoveData.Evade.NONE) -> MoveData:
	var clip := actor.rig.tree.get_animation(&"palm_jab").duplicate(true) as Animation
	clip.length = 1.0
	Marks.write(clip, marks)
	actor.rig.tree.get_animation_library(&"").add_animation(id, clip)
	var move := (Registry.fetch(&"moves", &"palm_jab") as MoveData).duplicate() as MoveData
	move.id = id
	move.clip = id
	move.root_motion = false
	move.stamina_cost = 0.0
	move.evade = evade
	if not hits.is_empty():
		move.hits = hits
	return move


# The jab's palm profile with `fields` set.
func _profile(fields := {}) -> HitProfile:
	var p := (Registry.fetch(&"moves", &"palm_jab") as MoveData).hits[&"palm"].duplicate() as HitProfile
	for field: String in fields:
		p.set(field, fields[field])
	return p


# Marks that turn palm_l on at each frame of `ons` for `live` frames.
func _swings(ons: Array, live := 1, hand := &"palm_l") -> Array:
	var marks := []
	for on: int in ons:
		marks.append({"time": Marks.time_of(on), "kind": &"hitbox_on", "args": {"id": hand, "profile": &"palm"}})
		marks.append({"time": Marks.time_of(on + live), "kind": &"hitbox_off", "args": {"id": hand}})
	return marks


# The evade fixture of `b`: the window from f`on` to f`off`.
func _evade_move(b: Actor, evade := SWAY, on := WINDOW_ON, off := WINDOW_OFF) -> MoveData:
	return _fixture(b, &"evade_fixture", [
		{"time": Marks.time_of(on), "kind": &"evade_on", "args": {}},
		{"time": Marks.time_of(off), "kind": &"evade_off", "args": {}},
	], {}, evade)


func _play_to(actor: Actor, frame: int) -> void:
	while actor.frame < frame:
		await frames(1)


# Plays `b`'s evade fixture from before the first frame and the attackers' `swings` ({actor key: [marks, profile fields]}),
# also from then, for `total` frames. Returns the run with `evading`: the frames (after each frame) the window was open on.
func _play(run: Dictionary, swings: Dictionary, total: int, evade := SWAY, on := WINDOW_ON, off := WINDOW_OFF) -> Dictionary:
	var b: Actor = run["b"]
	var move := _evade_move(b, evade, on, off)
	run["evading"] = []
	for key: String in swings:
		var actor: Actor = run[key]
		var spec: Array = swings[key]
		actor.runner.start(_fixture(actor, StringName("swing_" + key), spec[0], {&"palm": _profile(spec[1])}))
	b.runner.start(move)
	while b.frame < total:
		await frames(1)
		if b.runner.evading != MoveData.Evade.NONE:
			run["evading"].append(b.frame)
	return run


func test_the_window_avoids_only_its_own_frames() -> void:
	var run := _world()
	var b: Actor = run["b"]
	var move := _evade_move(b)
	var seen := []  # [b.frame, runner.evading] after each frame
	b.runner.start(move)
	assert_eq(b.runner.evading, MoveData.Evade.NONE, "f0: not yet")
	while b.frame < 20:
		await frames(1)
		seen.append([b.frame, b.runner.evading])
	var open := seen.filter(func(s: Array) -> bool: return s[1] == SWAY).map(func(s: Array) -> int: return s[0])
	assert_eq(open.size(), 10, "f8 to f17: ten frames, as long as the window between the marks")
	assert_eq(open, range(open[0], open[0] + 10), "in one run: %s" % [open])
	assert_eq(seen.filter(func(s: Array) -> bool: return s[1] != SWAY and s[1] != MoveData.Evade.NONE), [], "and nothing but SWAY")
	assert_eq(Defense.of(b).evading, MoveData.Evade.NONE, "the clip is over a second long: it has closed")
	b.runner.start(_evade_move(b, DUCK))
	await frames(WINDOW_ON + 2)
	assert_eq(b.runner.evading, DUCK, "a duck's move says DUCK")
	assert_eq(Defense.of(b).evading, DUCK, "and Defense.of copies it")
	b.runner.stop()
	assert_eq(b.runner.evading, MoveData.Evade.NONE, "a move that ends takes its window with it")


func test_three_blows_inside_one_window_are_all_evaded_and_a_fourth_after_it_lands() -> void:
	# a swings at f10, f12, f14 and f20, c (round blows) at f11 and f13: the first five are inside the window, which is
	# open for hitboxes that come on from f9 to f18, and the sixth is after it
	var run := _world()
	var b: Actor = run["b"]
	await _play(run, {"a": [_swings([10, 12, 14, 20]), {}], "c": [_swings([11, 13]), {"line": ROUND}]}, 40)
	var outcomes: Array = (run["got"] as Array).map(func(g: Array) -> String: return g[0])
	assert_eq(outcomes, ["EVADED", "EVADED", "EVADED", "EVADED", "EVADED", "HIT"], "the five inside, then the one after: %s" % [run["got"]])
	var perfect: Array = (run["got"] as Array).map(func(g: Array) -> bool: return g[2])
	assert_eq(perfect.count(true), 3, "a's straight blows are perfect against a sway, c's round ones are not: %s" % [run["got"]])
	assert_eq(b.stats.hp, 92.0, "only the last did damage")


func test_an_evaded_blow_does_not_land_later_in_the_same_swing() -> void:
	# a hitbox on for 5 frames from f18: it meets the window on its first live frame, which is the window's last
	var run := _world()
	var b: Actor = run["b"]
	await _play(run, {"a": [_swings([WINDOW_OFF], 5), {}]}, 40)
	assert_eq(run["got"].map(func(g: Array) -> String: return g[0]), ["EVADED"], "evaded once, and nothing after: %s" % [run["got"]])
	assert_eq(b.stats.hp, 100.0)
	assert_eq(run["landed"].size(), 1, "the attacker heard of it once")


func test_a_blow_on_the_frame_after_the_windows_last_lands() -> void:
	var run := _world()
	var b: Actor = run["b"]
	await _play(run, {"a": [_swings([WINDOW_OFF + 1]), {}]}, 40)
	assert_eq(run["got"].map(func(g: Array) -> String: return g[0]), ["HIT"], "the first blow after the window: %s" % [run["got"]])
	assert_eq(b.stats.hp, 92.0)


func test_a_sweep_and_a_jab_on_the_same_frame_one_evaded_one_lands() -> void:   # Review Focus 1
	var run := _world()
	var b: Actor = run["b"]
	await _play(run, {"a": [_swings([14]), {}], "c": [_swings([14]), {"perilous": PERILOUS.SWEEP, "height": HitProfile.Height.LOW}]}, 40)
	var got: Array = run["got"]
	assert_eq(got.size(), 2, "both blows reached him: %s" % [got])
	var by_kind := {}
	for g: Array in got:
		by_kind[g[3]] = g
	assert_eq(by_kind[PERILOUS.NONE][0], "EVADED", "the jab is evaded")
	assert_eq(by_kind[PERILOUS.SWEEP][0], "HIT", "the sweep lands")
	assert_eq(by_kind[PERILOUS.NONE][1], by_kind[PERILOUS.SWEEP][1], "on the same frame")
	assert_eq(b.stats.hp, 92.0, "only the sweep's 8")
	assert_eq(b.runner.current.id if b.runner.current != null else &"", &"flinch", "and the landed blow is the one he reacts to")


func test_an_evade_freezes_and_pushes_no_one_and_sets_evaded() -> void:
	var run := _world()
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	assert_false(b.runner.evaded)
	var frozen := []
	var moved := []
	var before := b.global_position
	a.hit_landed.connect(func(_r: HitResult, _e: HitEvent) -> void: frozen.append([a.frozen, b.frozen]))
	await _play(run, {"a": [_swings([14]), {"knockback": 6.0, "hitstop_frames": 6}]}, 40)
	assert_eq(run["got"].map(func(g: Array) -> String: return g[0]), ["EVADED"])
	assert_eq(frozen, [[0, 0]], "nobody freezes")
	assert_eq(b.global_position, before, "nobody is pushed")
	assert_true(b.runner.evaded, "the move's evaded flag is set")
	assert_eq(b.runner.current.id, &"evade_fixture", "and no reaction started")
	b.runner.start(_fixture(b, &"another", []))
	assert_false(b.runner.evaded, "the next move's start clears it")
	assert_eq(run["landed"], [["a", "EVADED", run["got"][0][1], true]], "the attacker heard it, perfect")


func test_an_evaded_grab_starts_no_pair() -> void:   # Review Focus 5: a grab slipped on the frame its pair would start
	var run := _world()
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await _play(run, {"a": [_swings([14]), {"perilous": PERILOUS.GRAB}]}, 40, DUCK)
	assert_eq(run["got"].map(func(g: Array) -> String: return g[0]), ["EVADED"], "slipped, not GRABBED: %s" % [run["got"]])
	assert_eq(run["landed"].map(func(l: Array) -> bool: return l[3]), [true], "a perfect dodge")
	assert_true(b.paired_with == null and a.paired_with == null, "no pair started")


func test_a_thrust_thrown_into_an_evade_lands() -> void:   # Review Focus 5
	var run := _world()
	var b: Actor = run["b"]
	await _play(run, {"a": [_swings([14]), {"perilous": PERILOUS.THRUST}]}, 40)
	assert_eq(run["got"].map(func(g: Array) -> String: return g[0]), ["HIT"])
	assert_eq(b.stats.hp, 92.0)
