extends TestCase
## The guard: guard_raise (its guard is up from f4 to its end, f14), then, while guard is held, the guard stance
## (Actor.guarding): the guard_hold clip on the upper body over a slow walk. A guard facing the blow takes it for
## stamina and posture (GUARDED, the defender plays guard_hit), unless it has too little stamina (GUARD_BREAK, it
## plays guard_break with its stamina emptied). A blow from outside the arc, a perilous sweep or a thrust lands.
##
## Fighters are the Duel's: `a` (PLAYER) at the origin facing +Z, `b` (an ENEMY copy of Abarax, poise 5) a metre in
## front facing back. b raises its guard on frame 1 and holds it: the raise plays frames 1 to 15 and the stance is
## up from frame 15. a's jab, pressed on frame 20, lands on frame 30 (its f10): palm, 8 HP, 6 poise, 4 posture,
## 8 guard stamina, 3 frames of hit-stop, a push of 1 m/s.

const O := HitResult.Outcome
const GUARD_HELD := [{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 200, "hold": [&"guard"]}]
const JAB_AT_20 := [{"frames": 19}, {"frames": 1, "press": [&"palm"]}, {"frames": 60}]
const LANDS := 30


# The Duel of `a_steps` and `b_steps` (b's def `b_def`, or the Duel's), with what each side heard of every blow:
#   landed  [[outcome name, frame], ...] from a's hit_landed
#   got     [[outcome name, frame], ...] from b's got_hit
#   b_started / a_started  [[move id, frame], ...]
func _duel(a_steps: Array, b_steps: Array, b_def: ActorDef = null) -> Dictionary:
	var run := Duel.make(self, a_steps, b_steps, 1.0, b_def)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	for key in ["landed", "got", "a_started", "b_started"]:
		run[key] = []
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: run["landed"].append([O.keys()[r.outcome], a.frame]))
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: run["got"].append([O.keys()[r.outcome], b.frame]))
	a.runner.move_started.connect(func(m: MoveData) -> void: run["a_started"].append([m.id, a.frame]))
	b.runner.move_started.connect(func(m: MoveData) -> void: run["b_started"].append([m.id, b.frame]))
	return run


func _current(actor: Actor) -> StringName:
	return actor.runner.current.id if actor.runner.current != null else &""


# A copy of the jab whose palm profile is `perilous`, for `a` to start itself.
func _perilous_jab(perilous: HitProfile.Perilous) -> MoveData:
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var move := jab.duplicate() as MoveData
	move.id = &"perilous_jab"
	var palm := (jab.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	palm.perilous = perilous
	move.hits = {&"palm": palm}
	return move


func test_holding_guard_raises_it_then_holds_the_stance() -> void:
	var run := _duel([], GUARD_HELD)
	var b: Actor = run["b"]
	var guarded := {}
	while b.frame < 20:
		await frames(1)
		guarded[b.frame] = [b.is_guarding(), b.guarding]
	assert_eq(run["b_started"], [[&"guard_raise", 1]], "guard raises the guard")
	assert_eq([guarded[4], guarded[5], guarded[14]], [[false, false], [true, false], [true, false]],
			"the raise guards from its f4 (frame 5), by its mark")
	assert_eq([guarded[15], guarded[19]], [[true, true], [true, true]], "and when it ends with guard held, the stance takes over")
	assert_eq(_current(b), &"", "the stance is no move: locomotion runs")
	assert_near(float(b.rig.tree.get(Rig.STANCE_BLEND)), 1.0, 1e-6, "guard_hold is on the upper body")
	assert_eq((b.rig.tree.tree_root.get_node(Rig.STANCE_NODE) as AnimationNodeAnimation).animation, &"guard_hold")


func test_a_tapped_guard_raises_no_stance() -> void:
	var run := _duel([], [{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 40}])
	var b: Actor = run["b"]
	await Duel.play_to(self, b, 20)
	assert_eq(run["b_started"], [[&"guard_raise", 1]])
	assert_false(b.is_guarding(), "let go before the raise ended: no guard after it")
	assert_near(float(b.rig.tree.get(Rig.STANCE_BLEND)), 0.0, 1e-6)


func test_frontal_jab_is_blocked() -> void:
	var run := _duel(JAB_AT_20, GUARD_HELD)
	var b: Actor = run["b"]
	await Duel.play_to(self, b, LANDS)
	assert_eq(run["landed"], [["GUARDED", LANDS]], "the jab is guarded")
	assert_eq(run["got"], run["landed"])
	assert_eq([b.stats.hp, b.stats.stamina, b.stats.posture], [100.0, 92.0, 96.0], "no HP; 8 stamina and 4 posture")
	assert_eq(run["b_started"], [[&"guard_raise", 1], [&"guard_hit", LANDS]], "guard_hit plays")
	assert_true(b.is_guarding(), "and the guard is still up through it")
	assert_true(b.frozen > 0 and (run["a"] as Actor).frozen > 0, "a guarded blow has weight: both freeze")
	# guard_hit is 21 frames, after 3 of hit-stop: it ends on frame 54, and guard is still held.
	await Duel.play_to(self, b, 56)
	assert_eq(_current(b), &"", "guard_hit is over")
	assert_true(b.guarding, "and the stance is up again, guard still held")


func test_a_guarded_blow_rings_on_the_guard_not_the_body() -> void:
	var run := _duel(JAB_AT_20, GUARD_HELD)
	var heard := []
	while (run["b"] as Actor).frame < LANDS:
		await frames(1)
		heard = Sfx.last_played().duplicate()
	assert_true(heard.has(&"guard_block"), "guard_block: %s" % [heard])
	assert_false(heard.has(&"impact_palm") or heard.has(&"surface_cloth"), "and no flesh: %s" % [heard])


func test_a_raise_cancelled_into_a_jab_leaves_no_guard_up() -> void:
	# Guard held from frame 1, palm on frame 11: the raise's window at f10 takes the jab, and the guard its mark held
	# up goes with the raise, guard held or not.
	var steps := [{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 9, "hold": [&"guard"]},
			{"frames": 1, "press": [&"palm"], "hold": [&"guard"]}, {"frames": 30, "hold": [&"guard"]}]
	var run := _duel([], steps)
	var b: Actor = run["b"]
	await Duel.play_to(self, b, 10)
	assert_true(b.is_guarding(), "the raise's guard is up")
	await Duel.play_to(self, b, 11)
	assert_eq(run["b_started"], [[&"guard_raise", 1], [&"palm_jab", 11]])
	assert_false(b.is_guarding(), "the jab holds no guard")
	assert_false(Defense.of(b).parrying, "and no parry")


func test_jab_from_behind_hits_a_guard() -> void:
	var run := _duel(JAB_AT_20, GUARD_HELD)
	var b: Actor = run["b"]
	b.place(Transform3D(Basis.IDENTITY, b.global_position))  # facing +Z: its back to a
	await Duel.play_to(self, b, LANDS)
	assert_eq(run["landed"], [["HIT", LANDS]], "a guard does not cover the back")
	assert_eq(b.stats.hp, 92.0)
	assert_eq(_current(b), &"flinch", "it flinches")
	assert_false(b.is_guarding(), "and the flinch drops the guard")


func test_guard_walks_slower_with_the_stance_on_the_upper_body() -> void:
	# Guard held with the stick pushed east all the way: the raise stands still, then the stance walks at the walk
	# times guard_speed_scale (1.0 x 0.45 m/s), never faster, with no sprint even with dodge held. The legs walk
	# (the feet swap ahead of each other) under a chest that shows guard_hold.
	var east := Vector2(1, 0)
	var steps := [{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "move": east},
			{"frames": 120, "hold": [&"guard", &"dodge"], "move": east}]
	var run := _duel([], steps)
	var b: Actor = run["b"]
	b.global_position = Vector3(5, 0, 5)  # well away from a
	await Duel.play_to(self, b, 60)
	assert_true(b.guarding)
	assert_near(b.locomotion.speed, 1.0 * 0.45, 1e-4, "walk x 0.45")
	assert_false(b.locomotion.sprinting, "dodge held does not sprint")
	var from := b.global_position
	var ahead := []  # which foot is ahead along the walk, each frame
	var hold: Animation = b.rig.tree.get_animation(&"guard_hold")
	var spine := hold.find_track(NodePath("%s:spine_03" % b.rig.get_path_to(b.rig.skeleton)), Animation.TYPE_ROTATION_3D)
	var worst := 0.0
	for i in 60:
		await frames(1)
		var feet := b.rig.bone_global(&"foot_l").x - b.rig.bone_global(&"foot_r").x
		ahead.append(signf(feet))
		var chest := b.rig.skeleton.get_bone_pose_rotation(b.rig.skeleton.find_bone("spine_03"))
		worst = maxf(worst, _nearest_angle(chest, hold, spine))
	assert_near(b.global_position.x - from.x, 0.45, 0.01, "0.45 m in a second")
	assert_true(ahead.has(1.0) and ahead.has(-1.0), "the feet take turns ahead: the legs walk")
	assert_true(worst < 0.01, "spine_03 is guard_hold's all along (at worst %.4f rad off)" % worst)


func test_letting_go_or_attacking_ends_the_stance() -> void:
	var let_go := _duel([], [{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 24, "hold": [&"guard"]},
			{"frames": 20}])
	var b: Actor = let_go["b"]
	await Duel.play_to(self, b, 25)
	assert_true(b.guarding, "up while held")
	await Duel.play_to(self, b, 26)
	assert_false(b.guarding, "down the frame it is let go")
	await Duel.play_to(self, b, 31)
	assert_near(float(b.rig.tree.get(Rig.STANCE_BLEND)), 0.0, 1e-6, "and the stance fades out within 0.08 s")
	(let_go["arena"] as Node).free()
	for attack: StringName in [&"palm", &"heavy"]:
		var run := _duel([], [{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 24, "hold": [&"guard"]},
				{"frames": 1, "press": [attack], "hold": [&"guard", attack]}, {"frames": 20, "hold": [&"guard"]}])
		var c: Actor = run["b"]
		await Duel.play_to(self, c, 26)
		assert_eq(run["b_started"].back(), [Registry.fetch(&"actors", &"abarax").moveset[attack], 26], "%s attacks out of the guard" % attack)
		assert_false(c.guarding, "and the stance is gone (%s)" % attack)
		(run["arena"] as Node).free()


func test_stamina_comes_back_slower_under_a_guard() -> void:
	var run := _duel([], GUARD_HELD)
	var b: Actor = run["b"]
	await Duel.play_to(self, b, 20)
	b.stats.spend_stamina(50.0)
	await Duel.play_to(self, b, 20 + 36 + 60)  # the 0.6 s wait, then a second
	assert_near(b.stats.stamina, 50.0 + 45.0 * 0.4, 0.5, "45 a second times 0.4")


func test_empty_stamina_breaks_the_guard() -> void:
	var run := _duel(JAB_AT_20, GUARD_HELD)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await Duel.play_to(self, b, LANDS - 1)
	b.stats.stamina = 5.0  # less than the jab's 8
	await Duel.play_to(self, b, LANDS)
	assert_eq(run["landed"], [["GUARD_BREAK", LANDS]])
	assert_eq([b.stats.hp, b.stats.stamina, b.stats.posture], [100.0, 0.0, 96.0], "the guard pays all it has, and its posture")
	assert_true(b.stats.exhausted, "which leaves it exhausted")
	assert_eq(_current(b), &"guard_break")
	assert_false(b.is_guarding(), "the guard is broken")
	assert_eq([a.frozen, b.frozen], [3, 3], "both freeze for the blow's hit-stop")
	var at := b.global_position
	await Duel.play_to(self, b, LANDS + 20)
	assert_true(b.global_position.z - at.z > 0.05, "and the blow pushes it back (%.3f m)" % (b.global_position.z - at.z))


func test_perilous_sweep_is_not_blocked() -> void:
	# The Combat row "a guard against a sweep", in play: a sweep comes through a held guard.
	var run := _duel([{"frames": 60}], GUARD_HELD)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await Duel.play_to(self, a, 19)
	a.runner.start(_perilous_jab(HitProfile.Perilous.SWEEP))
	await Duel.play_to(self, a, 28)
	assert_true(b.guarding, "the guard is up")
	await Duel.play_to(self, a, LANDS)
	assert_eq(run["landed"], [["HIT", 29]], "the sweep lands")
	assert_eq(b.stats.hp, 92.0)
	assert_eq(_current(b), &"flinch")


func test_guard_and_palm_same_frame_guard_wins() -> void:
	# Pressed together from rest (the brain lists palm before guard, as Inputs.GAMEPLAY does): the later press wins
	# the input buffer, so the guard comes up, and the palm is not used up.
	var run := _duel([], [{"frames": 1, "press": [&"palm", &"guard"]}, {"frames": 10}])
	var b: Actor = run["b"]
	await Duel.play_to(self, b, 1)
	assert_eq(run["b_started"], [[&"guard_raise", 1]], "guard wins")
	assert_eq(b.buffer.consume([&"palm"], b.buffer_frame), &"palm", "the palm is still buffered")


# The smallest angle between `rotation` and the rotation track `track` of `anim` anywhere in the clip.
func _nearest_angle(rotation: Quaternion, anim: Animation, track: int) -> float:
	var best := INF
	var t := 0.0
	while t <= anim.length:
		var d := rotation.normalized().inverse() * anim.rotation_track_interpolate(track, t).normalized()
		best = minf(best, 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w)))
		t += 1.0 / 240.0
	return best
