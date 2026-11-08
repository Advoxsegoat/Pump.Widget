extends TestCase
## Paired moves (PairedMove, Actor.start_paired): two fighters playing matched moves on one clock, the follower held
## at the pair's offset from the lead. Neither can be paired again while in one, nor paired at all while dead or
## invulnerable; no one else's blow lands on either while it lasts; their brains are ignored; and a grab that takes
## hold (GRABBED) starts its attacker's grab pair.
##
## The pairs here are made in code from the finisher's moves (finisher and finisher_victim, 1.4 s, three pair_hits of
## 15, 15 and 30): the Knuckle's grab pair comes with the Knuckle (F1 Task 12). `a` is a PLAYER Abarax at the origin
## facing +Z and `b` an ENEMY copy of him a metre in front facing back, as in the Duel.

const O := HitResult.Outcome
const FINISHER := "res://data/pairs/finisher_open_hand.tres"


# A pair of the finisher's moves, hits and staging, announced as `moment`.
func _pair(moment := &"grab") -> PairedMove:
	var pair := (load(FINISHER) as PairedMove).duplicate() as PairedMove
	pair.id = &"test_pair"
	pair.moment = moment
	return pair


func _current(actor: Actor) -> StringName:
	return actor.runner.current.id if actor.runner.current != null else &""


# A jab's palm from `attacker` on `target`, as a scanner would make it.
func _jab_on(attacker: Actor, target: Actor) -> HitEvent:
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var e := HitEvent.new()
	e.attacker = attacker
	e.target = target
	e.move = jab
	e.profile = jab.hits[&"palm"]
	e.hitbox = &"palm_l"
	e.point = target.global_position + Vector3.UP
	e.direction = (target.global_position - attacker.global_position).normalized()
	return e


# Runs in the middle of every physics frame, as an actor does (after Melee's snapshot, before Melee): first calls
# `then` once, if it is set, then posts to Melee those of `events` whose target is paired (all of them, if `always`),
# every frame.
class MidFrame extends Node:
	var then := Callable()
	var events: Array[HitEvent] = []
	var always := false

	func _physics_process(_delta: float) -> void:
		if then.is_valid():
			then.call()
			then = Callable()
		for e in events:
			if always or e.target.paired_with != null:
				Melee.post(e)


# Presses palm, dodge and guard every frame, holds guard and pushes the stick, and counts how often it is asked.
class Masher extends Brain:
	var thought := 0

	func think(_actor: Actor, _delta: float) -> Intent:
		thought += 1
		var intent := Intent.new()
		intent.move = Vector2(1, 0)
		intent.pressed = [&"palm", &"dodge", &"guard"]
		intent.held = [&"guard"]
		return intent


func test_cannot_pair_with_the_dead_or_the_already_paired() -> void:
	var run := Duel.make(self)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var arena: Node3D = run["arena"]
	var c := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(2, 0, 0), "C")
	var dead := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(-2, 0, 0), "Dead")
	await frames(1)
	dead.die()
	assert_false(a.start_paired(dead, _pair()), "not with the dead")
	assert_false(dead.start_paired(a, _pair()), "nor the dead with anyone")
	assert_false(a.start_paired(a, _pair()), "nor with itself")
	b.runner.iframes = true
	assert_false(a.start_paired(b, _pair()), "nor with the invulnerable (mid-roll)")
	assert_false(b.start_paired(a, _pair()), "nor the invulnerable with anyone")
	b.runner.iframes = false
	assert_eq([a.paired_with, b.paired_with], [null, null], "nothing was paired")
	assert_true(a.start_paired(b, _pair()), "a and b pair")
	assert_false(c.start_paired(b, _pair()), "not with one already paired (the follower)")
	assert_false(c.start_paired(a, _pair()), "not with one already paired (the lead)")
	assert_false(b.start_paired(c, _pair()), "nor one already paired with another")
	assert_eq([a.paired_with, b.paired_with, c.paired_with], [b, a, null])
	assert_true(Defense.of(a).paired and Defense.of(b).paired, "a Defense says so")
	assert_false(Defense.of(c).paired)
	await frames(1)
	assert_eq([_current(a), _current(b)], [&"finisher", &"finisher_victim"], "both moves start on the next frame")


func test_paired_actors_are_not_hit_by_others() -> void:
	# c (PLAYER) jabs b and d (ENEMY) jabs a on every frame each is paired, from the frame the pair begins (when Melee's
	# snapshot has them unpaired still): every one of those blows comes to nothing, and only the pair's own blows land on
	# b. a is free once its clip is over; b, once it lies down.
	var run := Duel.make(self)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var arena: Node3D = run["arena"]
	var c := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new([]), Vector3(1, 0, 1), "C")
	var d := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(-1, 0, 0), "D")
	var outcomes := {"a": [], "b": []}
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes["a"].append(O.keys()[r.outcome]))
	b.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if e.attacker != a:
			outcomes["b"].append(O.keys()[r.outcome]))
	await frames(1)
	var mid := MidFrame.new()
	mid.then = func() -> void: a.start_paired(b, _pair(&"finisher"))
	mid.events = [_jab_on(c, b), _jab_on(d, a)]
	track(mid)
	await frames(1)
	assert_eq([outcomes["a"], outcomes["b"]], [["WHIFF"], ["WHIFF"]], "the frame the pair begins")
	while a.paired_with != null or b.paired_with != null:
		await frames(1)
	mid.events.clear()
	assert_true(outcomes["a"].size() > 60, "a blow on a, every frame it was paired (%d)" % outcomes["a"].size())
	assert_true(outcomes["b"].size() > outcomes["a"].size(), "and on b, for longer (%d)" % outcomes["b"].size())
	assert_eq(outcomes["a"].filter(func(o: String) -> bool: return o != "WHIFF"), [], "none lands on the lead")
	assert_eq(outcomes["b"].filter(func(o: String) -> bool: return o != "WHIFF"), [], "none lands on the follower")
	assert_eq(a.stats.hp, 100.0)
	assert_eq(b.stats.hp, 40.0, "the follower took only the pair's 60")


func test_brains_are_ignored_while_paired() -> void:
	var run := Duel.make(self)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var a_brain := Masher.new()
	var b_brain := Masher.new()
	await frames(1)
	assert_true(a.start_paired(b, _pair()))
	a.set_brain(a_brain)
	b.set_brain(b_brain)
	var started := []
	for actor: Actor in [a, b]:
		actor.runner.move_started.connect(func(m: MoveData) -> void: started.append([String(actor.name), m.id]))
	var guarded := false
	while a.paired_with != null:
		await frames(1)
		guarded = guarded or a.is_guarding() or b.is_guarding()
	assert_eq(started, [["A", &"finisher"], ["B", &"finisher_victim"]], "nothing the brains pressed started")
	assert_false(guarded, "nor did a guard come up")
	assert_eq([a_brain.thought, b_brain.thought], [0, 0], "they were not asked")
	await frames(2)
	assert_true(a_brain.thought > 0, "once its clip is over, a's brain is asked again")
	assert_true(started.size() > 2 and started[2][0] == "A", "and its presses start moves: %s" % [started])
	assert_eq(b_brain.thought, 0, "while b plays on to the ground, still paired")
	while b.paired_with != null:
		await frames(1)
	assert_eq(started.filter(func(s: Array) -> bool: return s[0] == "B"), [["B", &"finisher_victim"], ["B", &"getup"]],
			"b only gets up when it is free")


func test_a_lead_that_chains_a_second_pair_keeps_it_when_the_first_ends() -> void:
	# a finishes b; two frames after its clip frees it, while b still plays on to the ground, it finishes c with the
	# same pair. b's pair ends (its follower is down) halfway through a's second clip: a is c's lead, and no one else's
	# blow lands on it, until that clip is over. d jabs a on every frame of it.
	var run := Duel.make(self)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var arena: Node3D = run["arena"]
	var c := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(4, 0, 0), "C")
	var d := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), Vector3(-4, 0, 0), "D")
	var pair := load(FINISHER) as PairedMove
	await frames(1)
	assert_true(a.start_paired(b, pair))
	while a.paired_with == b:
		await frames(1)
	assert_eq(b.paired_with, a, "a is free, and b plays on")
	await frames(2)
	c.place(Transform3D(Basis(Vector3.UP, -PI / 2.0), a.global_position + Vector3(1.0, 0, 0)))
	assert_true(a.start_paired(c, pair), "a starts a second pair on c")
	var outcomes := []
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(O.keys()[r.outcome]))
	var mid := MidFrame.new()
	mid.always = true
	mid.events = [_jab_on(d, a)]
	track(mid)
	var unpaired := []
	var b_freed := -1
	await frames(1)
	var second := a.runner.current
	assert_eq(_current(a), &"finisher", "its second finisher plays")
	while a.runner.current == second and a.frame < 400:
		if a.paired_with != c:
			unpaired.append(a.frame)
		if b_freed < 0 and b.paired_with == null:
			b_freed = a.frame
		await frames(1)
	mid.events.clear()
	assert_true(b_freed > 0, "b's pair ended during a's second clip")
	assert_eq(unpaired, [], "a is c's lead to the end of its clip (b's pair ended on frame %d)" % b_freed)
	assert_true(outcomes.size() > 40, "d's blow came on every frame (%d)" % outcomes.size())
	assert_eq(outcomes.filter(func(o: String) -> bool: return o != "WHIFF"), [], "and none landed on a")
	await frames(2)
	assert_eq([a.paired_with, a.pair], [null, null], "a is free once its own clip is over")


func test_grab_connects_into_the_grab_pair() -> void:
	# An enemy whose def has a grab pair grabs Abarax, who does nothing about it: its perilous GRAB jab takes hold on
	# frame 10. The grab's own numbers are not dealt: the pair starts instead, and its blows are what hurt him. Abarax
	# survives the 60 and gets up.
	var grabber_def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	grabber_def.grab_pair = _pair()
	var run := _grab(grabber_def)
	var e: Actor = run["grabber"]
	var abarax: Actor = run["abarax"]
	await Duel.play_to(self, e, 10)
	assert_eq([e.paired_with, abarax.paired_with], [abarax, e], "the grab pairs them")
	assert_eq(run["moments"], [["Grabber", &"grab", 10], ["Abarax", &"grab", 10]], "a grab moment on both")
	assert_eq(run["got"], [], "the grab itself is no blow")
	assert_eq(abarax.stats.hp, 100.0, "and deals nothing")
	assert_eq([_current(e), _current(abarax)], [&"finisher", &"finisher_victim"], "the grab pair's moves start on that frame")
	while abarax.paired_with != null:
		await frames(1)
	assert_eq(run["got"], ["HIT", "HIT", "HIT"], "its three blows land")
	assert_eq(abarax.stats.hp, 40.0)
	assert_eq(_current(abarax), &"getup", "and he gets up")


func test_a_grab_with_no_grab_pair_is_a_staggering_hit() -> void:
	var run := _grab(Duel.def(ActorDef.Team.ENEMY, 5.0))
	var e: Actor = run["grabber"]
	var abarax: Actor = run["abarax"]
	await Duel.play_to(self, e, 10)
	assert_eq(run["got"], ["GRABBED"], "it takes hold")
	assert_eq(abarax.stats.hp, 92.0, "for the blow's damage")
	assert_eq(_current(abarax), &"stagger", "and a stagger, as before")
	assert_eq([e.paired_with, abarax.paired_with], [null, null], "with no pair")


func test_walls_hold_abarax_grabbed_and_he_gets_up_in_the_open() -> void:
	# Abarax as the follower of a grab pair (the finisher's staging), with a wall's face 0.6 m behind him (z 1.6) and
	# another's 0.4 m to his side (x 0.4): neither capsule ends a frame in a wall, and he gets up in the open.
	var grabber_def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	grabber_def.grab_pair = _pair()
	var run := _grab(grabber_def)
	var e: Actor = run["grabber"]
	var abarax: Actor = run["abarax"]
	var arena: Node3D = run["arena"]
	for wall: Array in [[Vector3(0, 1.5, 1.6 + 0.25), Vector3(8, 3, 0.5)], [Vector3(0.4 + 0.25, 1.5, 0), Vector3(0.5, 3, 8)]]:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		(shape.shape as BoxShape3D).size = wall[1]
		body.add_child(shape)
		body.position = wall[0]  # before it is in the tree, so that it is never anywhere else
		arena.add_child(body)
	var deepest := -INF
	var paired := false
	var got_up := false
	for i in 260:
		await frames(1)
		paired = paired or abarax.paired_with == e
		got_up = got_up or _current(abarax) == &"getup"
		for actor: Actor in [e, abarax]:
			var p := actor.global_position
			deepest = maxf(deepest, maxf(p.z + 0.35 - 1.6, p.x + 0.35 - 0.4))
	assert_true(paired, "the grab pairs them")
	assert_true(got_up, "he gets up")
	assert_true(deepest <= 0.01, "no capsule ends a frame in a wall (deepest %.3f m)" % deepest)
	assert_eq([e.paired_with, abarax.paired_with], [null, null], "the pair is over")
	assert_true(abarax.rig.bone_global(&"Head").y - abarax.global_position.y > 1.4, "and he stands")


# An enemy `Grabber` of `grabber_def` at the origin facing +Z that starts a perilous GRAB jab before its first frame
# (so the jab is at its f1 on frame 1, and its hand reaches at its f10 on frame 10), and Abarax (PLAYER, his own def)
# a metre in front facing back, doing nothing: {arena, grabber, abarax, moments [[name, kind, the grabber's frame]],
# got [outcome names of Abarax's got_hit]}.
func _grab(grabber_def: ActorDef) -> Dictionary:
	var arena := TestArena.make(self)
	var e := TestArena.spawn(arena, grabber_def, ScriptBrain.new([]), Vector3.ZERO, "Grabber")
	e.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var abarax := TestArena.spawn(arena, load(Duel.ABARAX) as ActorDef, ScriptBrain.new([]), Vector3(0, 0, 1), "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1)))
	var run := {"arena": arena, "grabber": e, "abarax": abarax, "moments": [], "got": []}
	for actor: Actor in [e, abarax]:
		actor.combat_moment.connect(func(kind: StringName) -> void: run["moments"].append([String(actor.name), kind, e.frame]))
	abarax.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: run["got"].append(O.keys()[r.outcome]))
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var grab := jab.duplicate() as MoveData
	grab.id = &"grab_jab"
	var palm := (jab.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	palm.perilous = HitProfile.Perilous.GRAB
	grab.hits = {&"palm": palm}
	e.runner.start(grab)
	return run
