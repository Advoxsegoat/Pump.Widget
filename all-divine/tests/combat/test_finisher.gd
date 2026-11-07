extends TestCase
## The Open Hand finisher: a palm pressed with a broken foe (the group `finishable`) within finisher_range (1.6 m)
## and finisher_arc_deg (60 degrees) of Abarax's facing starts his def's finisher, the paired move
## finisher_open_hand, in place of the jab. He plays `finisher` (1.4 s) and the foe `finisher_victim` on one clock,
## the foe held 1.1 m in front of him; his three pair_hit marks (f10, f40, f55) do 15, 15 and 30 to it as HITs with
## no reaction, with their hit-stop (4, 4 and 6 frames). After the pair the foe's posture is full again, and it dies
## where it lies if its HP is gone, or gets up.
##
## Fighters are the Duel's: `a` (PLAYER Abarax) at the origin facing +Z, `b` (an ENEMY copy of Abarax with 60 HP) a
## metre in front facing back. b's posture is broken on frame 1 by a blow that does nothing else (Breaker): no
## damage, no reaction but the break, no hit-stop.

const O := HitResult.Outcome
const PAIR := "res://data/pairs/finisher_open_hand.tres"
const BROKEN_ON := 1


func _foe(hp := 60.0) -> ActorDef:
	var def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	def.max_hp = hp
	return def


func _current(actor: Actor) -> StringName:
	return actor.runner.current.id if actor.runner.current != null else &""


# The Duel of `a_steps` with b a foe of `hp`, whose posture is broken on frame BROKEN_ON; with what each side
# heard from then on: `moments` [[actor name, kind, a's frame]], `got` [[outcome, hp after, frame]] of b's got_hit,
# `landed` [outcome, ...] of a's hit_landed, `died` how often b died.
func _duel(a_steps: Array, hp := 60.0) -> Dictionary:
	var run := Duel.make(self, a_steps, [], 1.0, _foe(hp))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var breaker := Breaker.new()
	breaker.attacker = a
	breaker.target = b
	track(breaker)
	await Duel.play_to(self, b, BROKEN_ON)
	assert_true(b.stats.posture_broken and _current(b) == &"posture_broken", "b is broken")
	assert_eq(b.stats.hp, hp, "and unhurt")
	run["moments"] = []
	run["got"] = []
	run["landed"] = []
	run["died"] = 0
	for actor: Actor in [a, b]:
		actor.combat_moment.connect(func(kind: StringName) -> void: run["moments"].append([String(actor.name), kind, a.frame]))
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: run["got"].append([O.keys()[r.outcome], b.stats.hp, b.frame]))
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: run["landed"].append(O.keys()[r.outcome]))
	b.died.connect(func() -> void: run["died"] += 1)
	return run


# Posts, once, a blow of a's on b that takes all of b's posture and nothing else, in the middle of the next physics
# frame (after Melee's snapshot, before Melee), as a's scanner would.
class Breaker extends Node:
	var attacker: Actor
	var target: Actor

	func _physics_process(_delta: float) -> void:
		if attacker == null:
			return
		var profile := HitProfile.new()
		profile.posture_damage = target.stats.max_posture
		profile.hitstop_frames = 0
		var move := MoveData.new()
		move.id = &"breaker"
		move.hits = {&"break": profile}
		var e := HitEvent.new()
		e.attacker = attacker
		e.target = target
		e.move = move
		e.profile = profile
		e.point = target.global_position + Vector3.UP
		e.direction = (target.global_position - attacker.global_position).normalized()
		Melee.post(e)
		attacker = null


# Plays until the pair a is in has ended (a.paired_with is null again), at most `limit` frames.
func _play_out(a: Actor, limit := 200) -> void:
	var until := a.frame + limit
	while a.paired_with != null and a.frame < until:
		await frames(1)


func test_palm_near_a_broken_foe_starts_the_finisher() -> void:
	var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}])
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await Duel.play_to(self, a, 9)
	assert_eq(a.finishable_target(), b, "b is the one to finish (for the HUD)")
	await Duel.play_to(self, a, 10)
	assert_eq([_current(a), _current(b)], [&"finisher", &"finisher_victim"], "the palm starts the finisher, not the jab")
	assert_eq([a.paired_with, b.paired_with], [b, a], "they are paired")
	assert_eq([a.pair, b.pair], [load(PAIR), load(PAIR)], "in the def's finisher")
	assert_eq(run["moments"], [["A", &"finisher", 10], ["B", &"finisher", 10]], "a combat moment on both, for F4")
	assert_eq(a.finishable_target(), null, "a paired foe is not one to finish")


func test_palm_in_a_cancel_window_starts_the_finisher_too() -> void:
	# a's jab from frame 1 lands on the reeling b on frame 11 (8 HP, and no reaction), and after its 3 frames of
	# hit-stop its cancel window takes palm from its f15, frame 19: the palm pressed on frame 17 comes out there as the
	# finisher, not the cross. (A riposte, palm in a parry's window, is the same.)
	var run := await _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 15}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}])
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var started := []
	a.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	await Duel.play_to(self, a, 20)
	assert_eq(started, [&"finisher"], "the finisher, not palm_cross")
	assert_eq(b.paired_with, a)


func test_finisher_is_at_most_one_and_a_half_seconds() -> void:
	# Spec 4.4: a finisher is 1.5 s at most. The pair's clock (the frames it was not frozen) runs the lead's 1.4 s
	# clip; its three blows' hit-stop (4, 4 and 6 frames) stops that clock and adds to the time it takes.
	var pair := load(PAIR) as PairedMove
	assert_eq(pair.max_length, 1.5)
	var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}])
	var a: Actor = run["a"]
	var lead := a.rig.tree.get_animation(&"finisher")
	assert_true(lead.length <= pair.max_length, "the lead's clip is %.3f s" % lead.length)
	await Duel.play_to(self, a, 10)
	var started := [a.frame, a.buffer_frame]
	await _play_out(a)
	var clock: int = a.buffer_frame - int(started[1])
	assert_true(clock <= 90, "the pair ran %d frames of its clock" % clock)
	assert_eq(clock, Marks.frame_of(lead.length), "the lead's clip, to the frame")
	assert_eq(a.frame - started[0], clock + 4 + 4 + 6, "and its hit-stop")


func test_follower_holds_the_offset_after_aligning() -> void:
	var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}])
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var pair := load(PAIR) as PairedMove
	await Duel.play_to(self, a, 10)
	var from := a.global_position
	var worst := 0.0
	var worst_facing := 1.0
	var frame := 1
	while a.paired_with != null:
		var goal := a.global_transform * pair.follow_offset
		if frame >= pair.align_frames:
			worst = maxf(worst, b.global_position.distance_to(goal.origin))
			var toward := a.global_position - b.global_position
			toward.y = 0.0
			worst_facing = minf(worst_facing, b.facing().dot(toward.normalized()))
		await frames(1)
		frame += 1
	assert_true(frame > 80, "the pair lasted %d frames" % frame)
	assert_true(a.global_position.distance_to(from) > 0.1, "a travels in the finisher (%.2f m)" % a.global_position.distance_to(from))
	assert_true(worst <= 0.05, "from the 4th frame on b is within %.3f m of the offset" % worst)
	assert_true(worst_facing > 0.99, "and faces a (%.3f)" % worst_facing)


func test_three_pair_hits_kill_a_sixty_hp_foe() -> void:
	var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}])
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var frozen := []
	await Duel.play_to(self, a, 10)
	while a.paired_with != null:
		await frames(1)
		if b.frozen > 0 and (frozen.is_empty() or frozen.back()[1] != b.frame - 1):
			frozen.append([a.frozen, b.frame])
		elif b.frozen > 0:
			frozen.back()[1] = b.frame
	var hits := (run["got"] as Array).map(func(g: Array) -> Array: return g.slice(0, 2))
	assert_eq(hits, [["HIT", 45.0], ["HIT", 30.0], ["HIT", 0.0]], "15, 15 and 30, as HITs")
	assert_eq(run["landed"], ["HIT", "HIT", "HIT"], "and a hears each land")
	assert_eq(frozen.map(func(f: Array) -> int: return f[0]), [4, 4, 6], "each with its hit-stop, on both")
	assert_eq(run["died"], 1, "b dies once, when the pair is over")
	assert_true(b.dead)
	assert_ne(_current(b), &"death", "without the death clip")
	assert_eq(b.rig.hurtbox.collision_layer, 0, "its hurtbox is off")
	assert_eq(b.collision_layer & Layers.ACTOR, 0, "and it is off the actor layer")
	var head := b.rig.bone_global(&"Head").y - b.global_position.y
	assert_true(head < 0.4, "it lies where the finisher left it (head at %.2f m)" % head)
	await frames(30)
	head = b.rig.bone_global(&"Head").y - b.global_position.y
	assert_true(head < 0.4, "and stays down (head at %.2f m)" % head)
	assert_false(b.is_in_group(Actor.FINISHABLE_GROUP), "nothing to finish now")


func test_a_foe_that_survives_the_finisher_gets_up() -> void:
	var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}], 100.0)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await Duel.play_to(self, a, 10)
	await _play_out(a)
	assert_eq(b.stats.hp, 40.0, "60 taken")
	assert_false(b.dead)
	assert_eq(_current(b), &"getup", "it gets up")
	assert_false(b.stats.posture_broken, "with its posture full again")
	assert_eq(b.stats.posture, b.stats.max_posture)
	assert_false(b.is_in_group(Actor.FINISHABLE_GROUP))
	assert_eq([a.pair, b.pair, b.paired_with], [null, null, null], "the pair is over")
	var getup := b.rig.tree.get_animation(&"getup")
	await frames(Marks.frame_of(getup.length) + 20)
	var head := b.rig.bone_global(&"Head").y - b.global_position.y
	assert_true(head > 1.4, "and stands (head at %.2f m)" % head)


func test_palm_behind_or_far_from_a_broken_foe_is_a_jab() -> void:
	for spot: Array in [["behind a", Vector3(0, 0, -1.0)], ["2 m off", Vector3(0, 0, 2.0)], ["70 degrees off", Vector3(0.94, 0, 0.34)]]:
		var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 60}])
		var a: Actor = run["a"]
		var b: Actor = run["b"]
		b.place(Transform3D(Basis(Vector3.UP, PI), spot[1]))
		await Duel.play_to(self, a, 9)
		assert_eq(a.finishable_target(), null, "no one to finish %s" % spot[0])
		await Duel.play_to(self, a, 10)
		assert_eq(_current(a), &"palm_jab", "the palm is a jab (%s)" % spot[0])
		assert_eq(a.paired_with, null, spot[0])
		(run["arena"] as Node).free()
