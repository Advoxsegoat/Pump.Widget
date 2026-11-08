extends TestCase
## The Open Hand finisher: a palm pressed with a broken foe (the group `finishable`) within finisher_range (1.6 m)
## and finisher_arc_deg (60 degrees) of Abarax's facing starts his def's finisher, the paired move
## finisher_open_hand, in place of the jab. He plays `finisher` (0.83 s: a jab, a second jab and a cross, each landing
## in one 12 fps step) and the foe `finisher_victim` on one clock, the foe 1.02 m in front of him once they are aligned;
## his three pair_hit marks (f10, f25, f40) do 15, 15 and 30 to it as HITs with no reaction, with their hit-stop (4, 4
## and 6 frames). He is free when
## his clip is over; the foe plays on to the ground, and then its posture is full again, and it dies where it lies if
## its HP is gone, or gets up. How the two are staged (reach, contact, skating, alignment, walls) is
## test_finisher_staging.gd.
##
## Fighters are the Duel's: `a` (PLAYER Abarax) at the origin facing +Z, `b` (an ENEMY copy of Abarax with 60 HP) a
## metre in front facing back. b's posture is broken on frame 1 by a blow that does nothing else (PostureBreaker): no
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
	track(PostureBreaker.make(a, b))
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


# Plays until the pair of `run` is over (neither a nor b is paired), at most `limit` frames.
func _play_out(run: Dictionary, limit := 200) -> void:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var until := a.frame + limit
	while (a.paired_with != null or b.paired_with != null) and a.frame < until:
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


func test_the_lead_is_free_when_its_clip_and_its_hit_stop_are_over() -> void:
	# The lead's clock (the frames it was not frozen) runs its 0.83 s clip; the three blows' hit-stop (4, 4 and 6
	# frames) stops that clock and adds to the time it takes: 64 frames, under the 90 of spec 4.4. The foe plays on, paired.
	var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}])
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var lead := a.rig.tree.get_animation(&"finisher")
	await Duel.play_to(self, a, 10)
	var started := [a.frame, a.buffer_frame]
	while a.paired_with != null and a.frame < 200:
		await frames(1)
	var clock: int = a.buffer_frame - int(started[1])
	assert_eq(clock, Marks.frame_of(lead.length), "the lead's clip, to the frame")
	assert_eq(a.frame - started[0], clock + 4 + 4 + 6, "and its hit-stop")
	assert_eq(b.paired_with, a, "the foe is still paired: it plays on to the ground")
	assert_eq(_current(b), &"finisher_victim")


func test_three_pair_hits_kill_a_sixty_hp_foe() -> void:
	var run := await _duel([{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}])
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var frozen := []
	await Duel.play_to(self, a, 10)
	while a.paired_with != null or b.paired_with != null:
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
	await _play_out(run)
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


func test_a_riposte_on_a_foe_the_parry_broke_is_the_finisher() -> void:
	# The whole of it in play: b (8 posture left) jabs on frame 1, a parries it with a guard tapped on frame 6 (the jab
	# lands on frame 11), and the parry breaks b's posture. a's palm, pressed in the hit-stop, comes out in the parry's
	# riposte window as the finisher.
	var run := Duel.make(self, [{"frames": 5}, {"frames": 1, "press": [&"guard"]}, {"frames": 6}, {"frames": 1, "press": [&"palm"]},
			{"frames": 100}], [{"frames": 1, "press": [&"palm"]}, {"frames": 100}], 1.0, _foe())
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var started := []
	a.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	await Duel.play_to(self, a, 10)
	b.stats.damage_posture(92.0)
	await Duel.play_to(self, a, 11)
	assert_true(b.stats.posture_broken and b.is_in_group(Actor.FINISHABLE_GROUP), "the parry breaks b")
	await Duel.play_to(self, a, 30)
	assert_eq(started, [&"guard_raise", &"parry", &"finisher"], "the riposte is the finisher")
	assert_eq(b.paired_with, a)
