extends TestCase
## Hit-stop: a blow that lands freezes both fighters for the profile's frames. Frozen, a fighter's move runner,
## locomotion, velocity and rig stand still, while its brain goes on thinking and what it presses is buffered.
## Fighters are the Duel's: `a` jabs `b` one metre in front. The jab (profile `palm`, 3 frames) lands on frame
## 11 (Melee, at the end of it); the cross (4 frames) lands on frame 16 when pressed on frame 1.

const JAB_FRAMES := 3
const CROSS_FRAMES := 4


# What the fighters were doing at the end of each frame from the first to `last`: {frame: {a_time, b_time, a_hand,
# b_hand, a_frozen, b_frozen}}.
func _trace(run: Dictionary, last: int) -> Dictionary:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var seen := {}
	while a.frame < last:
		await frames(1)
		seen[a.frame] = {
			a_time = a.runner.time, b_time = b.runner.time, a_frozen = a.frozen, b_frozen = b.frozen,
			a_hand = a.rig.bone_global(&"hand_l"), b_hand = b.rig.bone_global(&"hand_l"),
			a_at = a.global_position, b_at = b.global_position,
		}
	return seen


func test_landed_jab_freezes_both_for_its_frames() -> void:
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 40}])
	var seen := await _trace(run, 20)
	var landed := 11
	assert_eq(seen[landed - 1]["a_frozen"], 0, "nothing is frozen before the blow")
	assert_eq([seen[landed]["a_frozen"], seen[landed]["b_frozen"]], [JAB_FRAMES, JAB_FRAMES], "both frozen 3 frames as the blow lands")
	for f in range(landed + 1, landed + 1 + JAB_FRAMES):
		assert_eq(seen[f]["a_time"], seen[landed]["a_time"], "the jab's time stands still on frame %d" % f)
		assert_eq(seen[f]["b_time"], seen[landed]["b_time"], "and the flinch's, which began as the blow landed (frame %d)" % f)
		assert_vec_near(seen[f]["a_hand"], seen[landed]["a_hand"], 1e-6, "the attacker's pose is held (frame %d)" % f)
		assert_vec_near(seen[f]["b_hand"], seen[landed]["b_hand"], 1e-6, "and the target's (frame %d)" % f)
		assert_vec_near(seen[f]["a_at"], seen[landed]["a_at"], 1e-6, "neither moves (frame %d)" % f)
	assert_eq(seen[landed + JAB_FRAMES]["a_frozen"], 0, "the freeze is over after 3 frames")
	var after := landed + JAB_FRAMES + 1
	assert_true(seen[after]["a_time"] > seen[landed]["a_time"], "the jab runs on again")
	assert_true(seen[after]["b_time"] > seen[landed]["b_time"], "and so does the flinch")
	assert_true(seen[after]["a_hand"].distance_to(seen[landed]["a_hand"]) > 1e-4, "the pose with it")


func test_the_clocks_lose_exactly_the_frozen_frames() -> void:
	# The same jab with and without a target to hit: the jab's own clock is behind by the 3 frozen frames.
	var miss := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 40}], [], 6.0)
	var miss_log := await _trace(miss, 30)
	(miss["arena"] as Node).free()
	var hit := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 40}])
	var hit_log := await _trace(hit, 30)
	assert_near(miss_log[30]["a_time"] - hit_log[30]["a_time"], JAB_FRAMES / 60.0, 1e-6, "3 frames of 1/60 s behind")
	assert_eq(miss_log[30]["a_frozen"], 0)


func test_a_freeze_keeps_the_longer_and_ignores_nothing_and_less() -> void:
	var run := Duel.make(self)
	var a: Actor = run["a"]
	a.freeze(2)
	a.freeze(5)
	a.freeze(3)
	assert_eq(a.frozen, 5, "the longest of 2, 5 and 3, not their sum")
	a.freeze(0)
	a.freeze(-4)
	assert_eq(a.frozen, 5, "no frames, no change")
	await frames(2)
	assert_eq(a.frozen, 3, "two frames pass")
	a.place(Transform3D(Basis.IDENTITY, Vector3.ZERO))
	assert_eq(a.frozen, 0, "a body put somewhere is no longer frozen")


func test_press_during_hit_stop_comes_out_after() -> void:
	# The palm pressed on frame 13, while both are frozen (frames 12 to 14), is buffered, not lost: it starts the
	# cross when the jab's window opens (its f15), which the freeze put 3 frames later than the 16th frame.
	var steps := [{"frames": 1, "press": [&"palm"]}, {"frames": 11}, {"frames": 1, "press": [&"palm"]}, {"frames": 40}]
	# Without a target (nothing frozen) the presses start the cross on frame 16.
	var free := Duel.make(self, steps, [], 6.0)
	var free_started := []
	(free["a"] as Actor).runner.move_started.connect(func(m: MoveData) -> void: free_started.append([m.id, (free["a"] as Actor).frame]))
	await Duel.play_to(self, free["a"], 30)
	assert_eq(free_started, [[&"palm_jab", 1], [&"palm_cross", 16]], "frame 16 when nothing is frozen")
	(free["arena"] as Node).free()
	var run := Duel.make(self, steps)
	var a: Actor = run["a"]
	var started := []
	a.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, a.frame]))
	await Duel.play_to(self, a, 30)
	assert_eq(started, [[&"palm_jab", 1], [&"palm_cross", 19]], "the cross starts on frame 19, which is frame 16 plus 3")


func _cross_frame(press_frame: int) -> Array:
	# Where the cross starts when a second palm is pressed on `press_frame` and the jab lands on a target a metre
	# away (frame 11, freezing both until frame 14); the jab is pressed on frame 1. [] if it never does.
	var steps := [{"frames": 1, "press": [&"palm"]}, {"frames": press_frame - 2}, {"frames": 1, "press": [&"palm"]}, {"frames": 40}]
	var run := Duel.make(self, steps)
	var a: Actor = run["a"]
	var started := []
	a.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, a.frame]))
	await Duel.play_to(self, a, 30)
	(run["arena"] as Node).free()
	return started


func test_the_buffer_does_not_age_during_hit_stop() -> void:
	# With no freeze the jab's cross window opens on frame 16, and the oldest press it takes is 9 frames old: the one
	# of frame 7. The jab lands on frame 11 and the freeze puts the window on frame 19, 12 frames after that press,
	# but 3 of them were frozen, so the press has aged 9 and still comes out on the window's first frame.
	assert_eq(await _cross_frame(7), [[&"palm_jab", 1], [&"palm_cross", 19]], "the oldest press the window allows")
	assert_eq(await _cross_frame(6), [[&"palm_jab", 1]], "one frame older is past the 9 and is lost, freeze or not")


func test_the_brain_thinks_while_frozen() -> void:
	var steps := [{"frames": 1, "press": [&"palm"]}, {"frames": 11}, {"frames": 3, "move": Vector2(1, 0)}, {"frames": 10}]
	var run := Duel.make(self, steps)
	var a: Actor = run["a"]
	var brain := a.brain as ScriptBrain
	await Duel.play_to(self, a, 11)
	assert_eq(a.frozen, JAB_FRAMES)
	await Duel.play_to(self, a, 14)
	assert_eq(a.frozen, 0, "the freeze ran its frames")
	assert_false(brain.done(), "the script has frames left")
	await Duel.play_to(self, a, 26)
	assert_true(brain.done(), "and it ran one step a frame all the while, frozen or not")


func test_a_trade_freezes_both_for_the_longer_of_the_two() -> void:
	# a jabs on frame 6 and b crosses on frame 1: both hands reach on frame 16, a's blow freezing for 3 and b's
	# for 4. Each fighter is frozen by both blows, and keeps the longer: 4 frames, not 3 + 4.
	var cross_def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	cross_def.moveset = {&"palm": &"palm_cross"}
	var run := Duel.make(self, [{"frames": 5}, {"frames": 1, "press": [&"palm"]}, {"frames": 40}],
			[{"frames": 1, "press": [&"palm"]}, {"frames": 40}], 1.0, cross_def)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var landed := []
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: landed.append(["a", a.frame, r.outcome]))
	b.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: landed.append(["b", b.frame, r.outcome]))
	var seen := await _trace(run, 26)
	assert_eq(landed.size(), 2, "both blows landed: %s" % [landed])
	if landed.size() != 2:
		return
	var frame: int = landed[0][1]
	assert_eq(landed[1][1], frame, "on the same frame")
	assert_eq([seen[frame]["a_frozen"], seen[frame]["b_frozen"]], [CROSS_FRAMES, CROSS_FRAMES], "both frozen for the 4, the longer")
	for f in range(frame + 1, frame + 1 + CROSS_FRAMES):
		assert_eq(seen[f]["a_time"], seen[frame]["a_time"], "a is still on frame %d" % f)
		assert_eq(seen[f]["b_time"], seen[frame]["b_time"], "b is still on frame %d" % f)
	assert_true(seen[frame + CROSS_FRAMES + 1]["a_time"] > seen[frame]["a_time"], "and runs on after 4, not 7")
	assert_true(seen[frame + CROSS_FRAMES + 1]["b_time"] > seen[frame]["b_time"])


func test_a_blow_that_whiffs_freezes_nobody() -> void:
	# b rolls in on frame 5 and is invulnerable while the jab's hand passes through it: every blow whiffs.
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 40}],
			[{"frames": 4}, {"frames": 1, "press": [&"dodge"], "move": Vector2(0, -1)}, {"frames": 40}], 2.0)
	var a: Actor = run["a"]
	var outcomes := []
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(r.outcome))
	var seen := await _trace(run, 30)
	assert_true(outcomes.has(HitResult.Outcome.WHIFF), "the hand reached the rolling body")
	assert_eq(outcomes.filter(func(o: int) -> bool: return o != HitResult.Outcome.WHIFF), [], "and nothing landed")
	for f in seen:
		assert_eq(seen[f]["a_frozen"], 0, "a is never frozen (frame %d)" % f)
		assert_eq(seen[f]["b_frozen"], 0, "nor b (frame %d)" % f)


func test_melee_freezes_for_a_hit_a_guard_a_parry_and_a_catch() -> void:
	var O := HitResult.Outcome
	assert_eq(Melee.FREEZES, [O.HIT, O.GUARDED, O.PARRIED, O.CAUGHT])
