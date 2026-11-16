extends TestCase
## Posture in play: blows wear it down, it mends 1.5 s after the last of them, and a blow that empties it breaks it.
## A broken body plays `posture_broken` (UAL1 Hit_Head held in a standing reel for 2 s, CombatTuning.broken_time) and
## is in the group `finishable` while it reels: open to a finisher (test_finisher.gd). If no finisher comes, the
## reel plays out, its posture is full again and it leaves the group.
##
## Fighters are the Duel's: `a` (PLAYER) at the origin facing +Z, `b` (an ENEMY copy of Abarax, poise 5) a metre in
## front facing back. a's jab pressed on frame 1 lands on frame 11 (palm: 8 HP, 4 posture, 3 frames of hit-stop); a's
## heavy palm lands at its f15 (heavy: 22 posture, 24 guard stamina, 6 frames of hit-stop).

const O := HitResult.Outcome
const JAB := [{"frames": 1, "press": [&"palm"]}, {"frames": 200}]
const LANDS := 11


func _current(actor: Actor) -> StringName:
	return actor.runner.current.id if actor.runner.current != null else &""


func test_guarded_heavies_wear_posture_to_a_break() -> void:
	# Four heavies, 70 frames apart (each plays 57 frames and 6 of hit-stop), on b holding its guard with 80 posture:
	# 22 each, guarded, is 88 in all, and the posture does not mend between them (it waits 90 frames).
	var b_def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	b_def.max_posture = 80.0
	var heavies := []
	for i in 4:
		heavies.append({"frames": 1, "press": [&"heavy"]})
		heavies.append({"frames": 69})
	var run := Duel.make(self, heavies, [{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 400, "hold": [&"guard"]}],
			1.0, b_def)
	var b: Actor = run["b"]
	var outcomes := []
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append([O.keys()[r.outcome], b.stats.posture]))
	for i in 3:
		# Each guarded heavy pushes b back 0.3 m: it is put back in reach before the next.
		await Duel.play_to(self, b, 60 + 70 * i)
		b.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1)))
	await Duel.play_to(self, b, 240)
	assert_eq(outcomes, [["GUARDED", 58.0], ["GUARDED", 36.0], ["GUARDED", 14.0], ["GUARDED", 0.0]], "four guarded heavies")
	assert_true(b.stats.posture_broken, "the fourth breaks the posture")
	assert_eq(_current(b), &"posture_broken", "b reels")
	assert_true(b.is_in_group(Actor.FINISHABLE_GROUP), "open to a finisher")
	assert_false(b.is_guarding(), "with its guard down")


func test_break_lasts_its_clip_then_posture_refills() -> void:
	# b has 4 posture left when a's jab lands on frame 11: it breaks there, and b reels for the clip's 2 s
	# (broken_time), which starts after the jab's 3 frames of hit-stop, so it ends on frame 11 + 3 + 120.
	var run := Duel.make(self, JAB)
	var b: Actor = run["b"]
	var clip := b.rig.tree.get_animation(&"posture_broken")
	assert_near(clip.length, b.stats.tuning.broken_time, 1e-4, "the reel is broken_time long")
	await Duel.play_to(self, b, LANDS - 1)
	b.stats.damage_posture(96.0)
	await Duel.play_to(self, b, LANDS)
	assert_true(b.stats.posture_broken, "broken by the jab")
	assert_eq(_current(b), &"posture_broken", "the break outranks the jab's flinch")
	var ended := b.frame + 3 + Marks.frame_of(clip.length)
	var standing := []
	while b.frame < ended - 1:
		await frames(1)
		if b.global_position.y < -0.01 or b.rig.bone_global(&"Head").y - b.global_position.y < 1.4:
			standing.append(b.frame)
	assert_eq(standing, [], "it reels on its feet")
	assert_true(b.stats.posture_broken and b.is_in_group(Actor.FINISHABLE_GROUP), "still broken a frame before the end")
	assert_eq(b.stats.posture, 0.0, "and the posture does not mend while broken")
	await Duel.play_to(self, b, ended)
	assert_eq(_current(b), &"", "the reel is over")
	assert_false(b.stats.posture_broken, "the break is over")
	assert_eq(b.stats.posture, b.stats.max_posture, "the posture is full again")
	assert_false(b.is_in_group(Actor.FINISHABLE_GROUP), "and it is no longer open to a finisher")


func test_posture_regenerates_after_its_delay() -> void:
	var run := Duel.make(self)
	var b: Actor = run["b"]
	await Duel.play_to(self, b, 5)
	b.stats.damage_posture(50.0)
	await Duel.play_to(self, b, 5 + 90)
	assert_eq(b.stats.posture, 50.0, "nothing comes back for 1.5 s (posture_regen_delay)")
	await Duel.play_to(self, b, 5 + 90 + 30)
	assert_near(b.stats.posture, 60.0, 0.01, "then 20 a second")


func test_a_reeling_body_takes_blows_without_a_new_reaction() -> void:
	# A broken body hit again (a second jab, frame 51) loses the blow's HP but keeps reeling: a flinch would cut the
	# reel short and end the break, and with it the chance of a finisher. (a has no finisher here, or its palm would
	# start that.)
	var a_def := Duel.def(ActorDef.Team.PLAYER, 5.0)
	a_def.finisher = null
	var run := Duel.make(self, JAB.slice(0, 1) + [{"frames": 49}, {"frames": 1, "press": [&"palm"]}, {"frames": 100}], [], 1.0,
			null, a_def)
	var b: Actor = run["b"]
	await Duel.play_to(self, b, LANDS - 1)
	b.stats.damage_posture(96.0)
	await Duel.play_to(self, b, 61)
	assert_eq(b.stats.hp, 100.0 - 8.0 - 8.0, "both jabs land")
	assert_eq(_current(b), &"posture_broken", "and it reels on")
	assert_true(b.stats.posture_broken and b.is_in_group(Actor.FINISHABLE_GROUP), "still open to a finisher")
