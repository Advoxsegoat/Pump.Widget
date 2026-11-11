extends TestCase
## The hop: the dodge button with the stick at rest. The dash-step's neutral variant is `hop`, a short jump on the spot
## whose marks (airborne_on f2, airborne_off f28) take the body off the ground, so a LOW sweep passes under it
## (Combat.resolve, rule 2) while a MID blow still lands. The hop has no iframes, costs 12 stamina, and is
## refused where a dash-step would be (an actor that cannot act).
##
## The hop's airborne marks are on the frames its feet are really off the ground (f2 to f28: it leaps at once, hangs
## at the apex and comes down over four frames to f28, as F1 Task 12's fix round re-timed it so the landing does not
## drop the body 0.3 m in one frame; the tail of the clip is the landing crouch), not at the f6 and f26 the plan first
## guessed. The hang is what lets it out-last a 20-frame sweep.
##
## A frame is the actor's: the first it lives is 1. A dodge pressed on frame 1 starts its move there (its f0), so
## the hop's airborne marks are on frames 3 and 29, and a blow is judged against the airborne state as it stood
## when the frame began: airborne for the blows of frames 4 to 29. The sweep fixture is the jab's clip with its
## palm_l live from f10 to f50 (frames 10 to 50: the move starts before the sweeper's first frame), 0.6 m in front of the sweeper (the hand draws back, so it stays in reach), which started on frame 1 too (live from frame 11).

const ABARAX := "res://data/actors/abarax.tres"
const EAST := Vector2(1, 0)
const GAP := 0.6
const O := HitResult.Outcome


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


## Abarax in a new arena playing `steps`, recording `started` ([[move id, frame], ...]) and, per frame,
## `iframes` (the frames the actor was invulnerable on) and `airborne` (the frames it was off the ground on).
func _solo(steps: Array) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var run := {"actor": actor, "started": [], "iframes": [], "airborne": [], "arena": arena}
	actor.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append([m.id, actor.frame]))
	return run


func _play_to(run: Dictionary, frame: int) -> void:
	var actor: Actor = run["actor"]
	while actor.frame < frame:
		await frames(1)
		if actor.runner.iframes:
			run["iframes"].append(actor.frame)
		if actor.runner.airborne:
			run["airborne"].append(actor.frame)


func test_neutral_dodge_hops_and_pushed_dodge_dash_steps() -> void:
	var neutral := _solo([{"frames": 1, "press": [&"dodge"]}, {"frames": 5}])
	await _play_to(neutral, 6)
	assert_eq(neutral["started"], [[&"hop", 1]], "the stick at rest: a hop")
	assert_near((neutral["actor"] as Actor).stats.stamina, 88.0, 1e-6, "which costs its own 12")
	var pushed := _solo([{"frames": 1, "press": [&"dodge"], "move": EAST}, {"frames": 5}])
	await _play_to(pushed, 6)
	assert_eq(pushed["started"], [[&"dash_step_left", 1]], "the stick pushed: a dash-step")
	assert_near((pushed["actor"] as Actor).stats.stamina, 92.0, 1e-6, "which costs 8")


func test_hop_from_cancel_windows_too() -> void:
	# A jab's window takes dodge at its f20 (frame 21): at rest it starts the hop, with the stick pushed a dash-step.
	var jab := _solo([{"frames": 1, "press": [&"palm"]}, {"frames": 19}, {"frames": 1, "press": [&"dodge"]}, {"frames": 5}])
	await _play_to(jab, 26)
	assert_eq(jab["started"], [[&"palm_jab", 1], [&"hop", 21]], "the jab's window, at rest")
	var pushed := _solo([{"frames": 1, "press": [&"palm"]}, {"frames": 19}, {"frames": 1, "press": [&"dodge"], "move": EAST}, {"frames": 5, "move": EAST}])
	await _play_to(pushed, 26)
	assert_eq(pushed["started"], [[&"palm_jab", 1], [&"dash_step_left", 21]], "and with the stick pushed")


func test_hop_is_refused_where_a_dash_step_would_be() -> void:
	var run := _solo([{"frames": 1, "press": [&"dodge"]}, {"frames": 5}])
	var actor: Actor = run["actor"]
	actor.stats.stamina = 0.0
	await _play_to(run, 6)
	assert_eq(run["started"], [], "no stamina: no hop")
	var exhausted := _solo([{"frames": 1, "press": [&"dodge"]}, {"frames": 5}])
	(exhausted["actor"] as Actor).stats.exhausted = true
	await _play_to(exhausted, 6)
	assert_eq(exhausted["started"], [], "exhausted: no hop")


func test_airborne_follows_the_marks() -> void:
	var run := _solo([{"frames": 1, "press": [&"dodge"]}, {"frames": 40}])
	var actor: Actor = run["actor"]
	await _play_to(run, 45)
	assert_eq(run["airborne"], range(3, 29), "from airborne_on at f2 to airborne_off at f28 (frames 3 to 28)")
	assert_false(actor.rig.airborne)
	assert_false(actor.runner.airborne)
	assert_eq(run["iframes"], [], "a hop has no iframes")


func test_airborne_ends_with_a_cancelled_hop() -> void:
	var run := _solo([{"frames": 1, "press": [&"dodge"]}, {"frames": 40}])
	var actor: Actor = run["actor"]
	await _play_to(run, 12)
	assert_true(actor.runner.airborne and actor.rig.airborne)
	actor.runner.start(_move(&"palm_jab"))
	assert_false(actor.runner.airborne, "a move that takes over lands him")
	assert_false(actor.rig.airborne)


func test_feet_are_not_planted_while_airborne() -> void:
	# On a slope the feet are planted (offsets away from 0); from the hop's airborne mark they let go.
	var arena := TestArena.make(self)
	TestTerrain.slope(arena, 20.0)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new([{"frames": 61}, {"frames": 1, "press": [&"dodge"]}, {"frames": 40}]),
			Vector3(2.0, 2.0 * tan(deg_to_rad(20.0)) + 0.03, 0))
	while actor.frame < 61:
		await frames(1)
	assert_true(absf(actor.rig.foot_planter.offsets[&"foot_l"]) > 0.03, "planted on the slope before the hop")
	assert_true(actor.rig.foot_planter.planting)
	while actor.frame < 61 + 2:  # the hop starts on frame 62: its f1
		await frames(1)
	assert_true(actor.rig.foot_planter.planting, "still planted before airborne_on")
	while actor.frame < 61 + 17:  # its f16, a frame before airborne_off
		await frames(1)
	assert_false(actor.rig.foot_planter.planting, "not planting between the marks")
	for foot in [&"foot_l", &"foot_r"]:
		assert_near(actor.rig.foot_planter.offsets[foot], 0.0, 0.02, "%s has let go" % foot)
	while actor.frame < 61 + 40:  # its f39
		await frames(1)
	assert_true(actor.rig.foot_planter.planting, "and plants again on landing")


## A sweeper (ENEMY) at the origin facing +Z and Abarax (PLAYER) GAP in front facing back, playing `steps`.
## Records `got` ([[outcome name, frame], ...]) on the hopper. The sweeper's fixture move is started on frame 1.
func _duel(steps: Array, profile: HitProfile.Height, on := 10, live := 40) -> Dictionary:
	var arena := TestArena.make(self)
	var foe := (load(ABARAX) as ActorDef).duplicate() as ActorDef
	foe.team = ActorDef.Team.ENEMY
	var sweeper := TestArena.spawn(arena, foe, ScriptBrain.new([]), Vector3.ZERO, "SWEEPER")
	sweeper.place(Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var hopper := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps), Vector3(0, 0, GAP), "HOPPER")
	hopper.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, GAP)))
	var run := {"arena": arena, "sweeper": sweeper, "actor": hopper, "got": [], "started": [], "iframes": [], "airborne": []}
	hopper.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: run["got"].append([O.keys()[r.outcome], hopper.frame]))
	hopper.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append([m.id, hopper.frame]))
	sweeper.runner.start(_long_swing(sweeper, profile, on, live))
	return run


# A copy of the jab whose palm_l is live for `live` frames from f`on` (f10 to f50 by default), on a copy of its clip added to `a`'s rig, with a profile
# of `height` (a LOW one is a perilous sweep).
func _long_swing(a: Actor, height: HitProfile.Height, on := 10, live := 40) -> MoveData:
	var clip := a.rig.tree.get_animation(&"palm_jab").duplicate(true) as Animation
	clip.length = 1.2
	Marks.write(clip, [
		{"time": Marks.time_of(on), "kind": &"hitbox_on", "args": {"id": &"palm_l", "profile": &"palm"}},
		{"time": Marks.time_of(on + live), "kind": &"hitbox_off", "args": {"id": &"palm_l"}},
	])
	a.rig.tree.get_animation_library(&"").add_animation(&"long_swing", clip)
	var move := _move(&"palm_jab").duplicate() as MoveData
	move.id = &"long_swing"
	move.clip = &"long_swing"
	var profile := (move.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	profile.height = height
	if height == HitProfile.Height.LOW:
		profile.perilous = HitProfile.Perilous.SWEEP
	move.hits = {&"palm": profile}
	return move


func test_low_sweep_through_the_airborne_frames_whiffs() -> void:
		# whiff (a whiff leaves the target to be struck), and the first one after he comes down lands, once.
	var run := _duel([{"frames": 1, "press": [&"dodge"]}, {"frames": 60}], HitProfile.Height.LOW)
	await _play_to(run, 45)
	var got: Array = run["got"]
	var whiffs := got.filter(func(g: Array) -> bool: return g[0] == "WHIFF")
	var hits := got.filter(func(g: Array) -> bool: return g[0] == "HIT")
	assert_eq(run["started"].front(), [&"hop", 1])
	assert_eq(whiffs.map(func(g: Array) -> int: return g[1]), range(10, 30), "every blow under him whiffs: %s" % [got])
	assert_eq(hits.size(), 1, "and one lands once he is down: %s" % [got])
	assert_eq(hits[0][1], 30, "the first frame judged against him on the ground (he came down on frame 29)")
	assert_eq((run["actor"] as Actor).stats.hp, 92.0, "the sweep did its 8")


func test_the_same_sweep_lands_on_a_standing_target() -> void:
	var run := _duel([{"frames": 60}], HitProfile.Height.LOW)
	await _play_to(run, 20)
	assert_eq(run["got"].front(), ["HIT", 10], "the control: no hop, the sweep lands at once")


func test_mid_hit_during_the_hop_lands() -> void:
	var run := _duel([{"frames": 1, "press": [&"dodge"]}, {"frames": 60}], HitProfile.Height.MID)
	await _play_to(run, 20)
	assert_eq(run["got"].front(), ["HIT", 10], "a MID blow does not pass under him")
	assert_true((run["actor"] as Actor).runner.airborne, "he is still in the air")


func test_mashing_dodge_never_makes_him_invulnerable() -> void:
	# Pushed, the dodge dash-steps, which is never invulnerable. At rest it hops, with none either.
	var mash := []
	for i in 12:
		mash.append({"frames": 1, "press": [&"dodge"], "move": EAST})
		mash.append({"frames": 3, "move": EAST})
	var steps := _solo(mash)
	await _play_to(steps, 60)
	assert_true(steps["started"].any(func(s: Array) -> bool: return s[0] == &"dash_step_left"))
	assert_eq(steps["iframes"], [], "no iframes at all, however it is mashed")
	var hops := []
	for i in 12:
		hops.append({"frames": 1, "press": [&"dodge"]})
		hops.append({"frames": 3})
	var rest := _solo(hops)
	await _play_to(rest, 60)
	assert_true(rest["started"].any(func(s: Array) -> bool: return s[0] == &"hop"))
	assert_eq(rest["iframes"], [], "mashing at rest never makes him invulnerable")


func test_the_hop_is_airborne_longer_than_a_sweep_is_active() -> void:
	# The perilous sweep is live for 20 frames, on purpose longer than a dodge could cover by itself; the hop must be off the
	# ground longer than that. Counted twice: from the airborne marks, and from the feet themselves (both ankles well
	# above the 0.08 to 0.12 m they stand at). Then a 20-frame LOW sweep whose first live frame is the first one judged
	# against the hop in the air (frame 4: the lift-off mark of frame 3 shows in the next frame's snapshot) whiffs
	# every frame of it.
	var run := _duel([{"frames": 1, "press": [&"dodge"]}, {"frames": 60}], HitProfile.Height.LOW, 4, 20)
	var actor: Actor = run["actor"]
	var feet := []
	while actor.frame < 45:
		await frames(1)
		if actor.runner.airborne:
			run["airborne"].append(actor.frame)
		var ankles: Dictionary = actor.rig.foot_planter.animated
		if ankles[&"foot_l"].y > 0.25 and ankles[&"foot_r"].y > 0.25:
			feet.append(actor.frame)
	assert_true(run["airborne"].size() >= 22, "airborne %d frames by the marks" % run["airborne"].size())
	assert_true(feet.size() >= 22, "and %d frames by the feet" % feet.size())
	assert_eq(feet, run["airborne"], "the marks sit on the frames the feet are up")
	var got: Array = run["got"]
	var whiffs := got.filter(func(g: Array) -> bool: return g[0] == "WHIFF").map(func(g: Array) -> int: return g[1])
	assert_eq(whiffs, range(4, 24), "all 20 live frames of the sweep whiff: %s" % [got])
	assert_eq(got.filter(func(g: Array) -> bool: return g[0] == "HIT"), [], "and none lands")
	assert_eq(actor.stats.hp, 100.0)
