extends TestCase
## The Open Hand moveset as played: the palm chain (jab, cross, hook), a dodge out of every recovery, and the heavy
## palm that can be held to charge.
##
## Fighters are the Duel's: Abarax (`a`, a PLAYER copy) at the origin facing +Z and a foe (`b`, an ENEMY copy of poise
## 5) a metre in front, which does nothing. A frame is the actor's: the first it lives is 1, and a move pressed on frame
## 1 is at its f0 there, so on frame k it is at f(k - 1). Marks, from the clips:
##   palm_jab    hitbox f10 to f15; opens {palm: palm_cross} at f15 and {palm, dodge} at f20
##   palm_cross  hitbox f15 to f20; opens {palm: palm_hook} at f20 and {palm, dodge} at f25
##   palm_hook   hitbox f40 to f45; opens {palm: palm_jab, dodge} at f55 (F1 Task 12's fix round re-timed it: UAL2
##               Melee_Hook's lunge spread over four 12 fps steps, its contact measured where the hand arrives)
##   palm_heavy  armour from f10 to f20; waits for a hold at f10; hitbox f15 to f20; opens {palm: palm_jab, dodge} at f45
## Held, the heavy's clip stands still at f10 for up to 40 frames; a full charge makes its blow the profile `charged`
## (34 HP and a stagger) in place of `heavy` (22 HP and a stagger).

const HEAVY_HP := 22.0
const CHARGED_HP := 34.0
## The frame the heavy's hold starts on when it is pressed on frame 1: its f10.
const HOLD_FRAME := 11
## How many frames the clip stands still at the mark when the whole charge is held.
const HOLD_FRAMES := 40
## The heavy's time at the mark.
const AT_MARK := 10.0 / 60.0
## A gap at which no blow reaches the foe.
const OUT_OF_REACH := 6.0


## Plays `steps` for `until` frames of a in a duel with b `gap` metres away (out of reach at 6: nothing lands, so
## nothing freezes and a move's frames are the frames it plays) and returns:
##   a, b, arena  the fighters
##   started      [[move id, a's frame], ...] of a's moves
##   b_started    the same for b
##   times        a's frame -> a's runner.time at the end of it
##   armour       a's frame -> whether a was armoured at the end of it
##   charged      the frames on which a's runner said `charged`
func _run(steps: Array, until: int, gap := 1.0) -> Dictionary:
	var run := Duel.make(self, steps, [], gap)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	run["started"] = []
	run["b_started"] = []
	run["times"] = {}
	run["armour"] = {}
	run["charged"] = []
	a.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append([m.id, a.frame]))
	b.runner.move_started.connect(func(m: MoveData) -> void: run["b_started"].append([m.id, a.frame]))
	a.runner.charged.connect(func(_m: MoveData) -> void: run["charged"].append(a.frame))
	while a.frame < until:
		await frames(1)
		run["times"][a.frame] = a.runner.time
		run["armour"][a.frame] = a.runner.hyperarmour
	return run


# Steps of `n` frames of heavy held, the first of them a press.
func _hold_heavy(n: int) -> Array:
	return [{"frames": 1, "press": [&"heavy"], "hold": [&"heavy"]}, {"frames": n - 1, "hold": [&"heavy"]}]


func _hp_lost(run: Dictionary) -> float:
	return 100.0 - (run["b"] as Actor).stats.hp


# The frames, in order, on which the clip stood at the heavy's mark (one, passing it, if it did not wait).
func _frames_at_mark(run: Dictionary) -> Array:
	var found := []
	for f: int in run["times"]:
		if is_equal_approx(run["times"][f], AT_MARK):
			found.append(f)
	found.sort()
	return found


func _current(actor: Actor) -> StringName:
	return actor.runner.current.id if actor.runner.current != null else &""


# --- the chain ---

# Palm pressed on frame 1 (the jab), on 15 (the cross's window opens on 16), on 35 (the hook's opens on 36).
const CHAIN: Array = [
	{"frames": 1, "press": [&"palm"]}, {"frames": 13}, {"frames": 1, "press": [&"palm"]},
	{"frames": 19}, {"frames": 1, "press": [&"palm"]}, {"frames": 70},
]


func test_three_presses_chain_jab_cross_hook() -> void:
	# Each press a frame before its window opens, so each comes out on the window's first frame.
	var run := await _run(CHAIN, 40, OUT_OF_REACH)
	assert_eq(run["started"], [[&"palm_jab", 1], [&"palm_cross", 16], [&"palm_hook", 36]], "in order, on each window's first frame")


func test_the_chain_has_no_idle_frame() -> void:
	var arena := TestArena.make(self)
	var a := TestArena.spawn(arena, load(Duel.ABARAX), ScriptBrain.new(CHAIN))
	var idle := []
	while a.frame < 60:
		await frames(1)
		if not a.runner.busy():
			idle.append(a.frame)
	assert_eq(idle, [], "a move plays on every frame from the first press to well into the hook")


func test_the_hook_goes_back_to_the_jab() -> void:
	# The hook's window (f55, frame 91) takes palm into the jab. This press is a frame early.
	var steps := CHAIN.slice(0, 5) + [{"frames": 54}, {"frames": 1, "press": [&"palm"]}, {"frames": 40}]
	var run := await _run(steps, 120, OUT_OF_REACH)
	assert_eq(run["started"].map(func(s: Array) -> StringName: return s[0]), [&"palm_jab", &"palm_cross", &"palm_hook", &"palm_jab"])
	assert_eq(run["started"][3][1], 91, "at the hook's f55")


func test_every_recovery_takes_a_dodge() -> void:
	# Each move is started before frame 1 (so it is at f(k) on frame k) and a dodge is pressed a frame before the
	# window that carries it opens: it dash-steps on the window's first frame, out of the move.
	var windows := {&"palm_jab": 20, &"palm_cross": 25, &"palm_hook": 55, &"palm_heavy": 45}
	for id: StringName in windows:
		var arena := TestArena.make(self)
		var steps := [{"frames": windows[id] - 2}, {"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)}, {"frames": 40, "move": Vector2(1, 0)}]
		var a := TestArena.spawn(arena, load(Duel.ABARAX), ScriptBrain.new(steps))
		var started := []
		a.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, a.frame]))
		a.runner.start(Registry.fetch(&"moves", id) as MoveData)
		await Duel.play_to(self, a, windows[id] + 3)
		assert_eq(started, [[id, 0], [&"dash_step_left", windows[id]]], "%s: a dash-step on the frame its window opens" % id)
		arena.free()


func test_every_recovery_takes_a_sway_and_a_duck() -> void:
	# The same, pressing a sway (toward his right) and then, in a fresh run, a duck.
	var windows := {&"palm_jab": 20, &"palm_cross": 25, &"palm_hook": 55, &"palm_heavy": 45}
	for press: Array in [[&"sway", &"sway_right_slip"], [&"duck", &"duck_slip"]]:
		for id: StringName in windows:
			var arena := TestArena.make(self)
			var steps := [{"frames": windows[id] - 2}, {"frames": 1, "press": [press[0]], "evade_dir": Vector2(-1, 0)}, {"frames": 40}]
			var a := TestArena.spawn(arena, load(Duel.ABARAX), ScriptBrain.new(steps))
			var started := []
			a.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, a.frame]))
			a.runner.start(Registry.fetch(&"moves", id) as MoveData)
			await Duel.play_to(self, a, windows[id] + 3)
			assert_eq(started, [[id, 0], [press[1], windows[id]]], "%s: a %s on the frame its window opens" % [id, press[0]])
			arena.free()


func test_the_last_window_of_each_blow_is_the_next_blow_and_the_dash_step_sway_and_duck() -> void:
	var want := {
		&"palm_jab": {&"palm": &"palm_cross", &"dodge": &"dash_step", &"sway": &"sway_left_slip", &"duck": &"duck_slip"},
		&"palm_cross": {&"palm": &"palm_hook", &"dodge": &"dash_step", &"sway": &"sway_left_slip", &"duck": &"duck_slip"},
		&"palm_hook": {&"palm": &"palm_jab", &"dodge": &"dash_step", &"sway": &"sway_left_slip", &"duck": &"duck_slip"},
		&"palm_heavy": {&"palm": &"palm_jab", &"dodge": &"dash_step", &"sway": &"sway_left_slip", &"duck": &"duck_slip"},
	}
	for id: StringName in want:
		var move := Registry.fetch(&"moves", id) as MoveData
		var anim := load("res://assets/anim/abarax/%s.tres" % move.clip) as Animation
		var last := {}
		for mark in Marks.read(anim):
			if mark["kind"] == &"cancel_open":
				last = mark["args"]["into"]
		assert_eq(last, want[id], "%s's last window" % id)


# --- the heavy ---

func test_the_moveset_starts_the_heavy_from_heavy() -> void:
	var def := load(Duel.ABARAX) as ActorDef
	assert_eq(def.moveset.get(&"heavy"), &"palm_heavy")


func test_heavy_released_early_uses_heavy() -> void:
	# Heavy pressed and let go at once: no hold at f10, and the blow at f15 (frame 16) is the plain heavy.
	var run := await _run([{"frames": 1, "press": [&"heavy"]}, {"frames": 40}], 40)
	assert_eq(_hp_lost(run), HEAVY_HP, "22 HP")
	assert_eq(run["charged"], [], "never charged")
	assert_eq(run["b_started"], [[&"stagger", 16]], "and the foe staggers on the frame it lands")
	assert_eq(_frames_at_mark(run), [HOLD_FRAME], "the clip passed the mark on frame 11 and did not stay")


func test_heavy_held_forty_frames_charges() -> void:
	var run := await _run(_hold_heavy(70), 70)
	assert_eq(_frames_at_mark(run), range(HOLD_FRAME, HOLD_FRAME + HOLD_FRAMES), "the clip stands at f10 for 40 frames, 11 to 50")
	assert_true(run["times"][HOLD_FRAME + HOLD_FRAMES] > AT_MARK, "and goes on from the 41st")
	assert_eq(run["charged"], [HOLD_FRAME + HOLD_FRAMES], "charged as the wait ends, once")
	assert_eq(_hp_lost(run), CHARGED_HP, "34 HP")
	assert_eq(run["b_started"], [[&"stagger", 55]], "and a stagger, at f15 (frame 55)")
	assert_eq((run["a"] as Actor).runner.charge_profile, &"charged")


func test_a_heavy_held_to_the_end_does_not_wait_again() -> void:
	# The button stays down through the whole move: it waits at the mark once.
	var run := await _run(_hold_heavy(90), 90)
	assert_eq(_frames_at_mark(run).size(), HOLD_FRAMES)


func test_a_charge_let_go_halfway_is_a_plain_heavy() -> void:
	# Held for frames 1 to 20: the wait that began on frame 11 is cut short, and the clip goes on at once on frame 21.
	var run := await _run([{"frames": 1, "press": [&"heavy"], "hold": [&"heavy"]}, {"frames": 19, "hold": [&"heavy"]}, {"frames": 60}], 70)
	assert_eq(_frames_at_mark(run), range(HOLD_FRAME, 21), "frames 11 to 20 at the mark")
	assert_true(run["times"][21] > AT_MARK, "and on the frame the button is let go, it moves")
	assert_eq(run["charged"], [])
	assert_eq(_hp_lost(run), HEAVY_HP)


func test_the_heavy_is_armoured_from_its_hold_to_its_hitbox_off() -> void:
	# Held through frame 30 (the wait is frames 11 to 30), it goes on at frame 31 and f20 is frame 40.
	var run := await _run(_hold_heavy(30) + [{"frames": 60}], 70, OUT_OF_REACH)
	var armoured := []
	for f: int in run["armour"]:
		if run["armour"][f]:
			armoured.append(f)
	armoured.sort()
	assert_eq(armoured, range(HOLD_FRAME, 40), "on at its f10, standing through the wait, off at its f20")


func test_flinch_clears_a_charge() -> void:
	# Heavy held on through a flinch, once while the wait is building (frame 30) and once after it is full but before
	# the blow (frame 52): the flinch ends the move and the charge with it, the held button charges nothing across the
	# reaction, and the next heavy, tapped, does 22 (Review Focus 2). Heavy's armour holds off an ordinary blow, so the
	# flinch is handed over as Melee would hand one that got through.
	for flinch_on in [30, 52]:
		var steps := _hold_heavy(100) + [{"frames": 1}, {"frames": 1, "press": [&"heavy"]}, {"frames": 40}]
		var run := Duel.make(self, steps)
		var a: Actor = run["a"]
		var b: Actor = run["b"]
		var started := []
		a.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, a.frame]))
		await Duel.play_to(self, a, flinch_on)
		_flinch(a, b)
		assert_eq(_current(a), &"flinch", "the flinch took the move (on frame %d)" % flinch_on)
		assert_eq(a.runner.charge_profile, &"", "and the charge")
		assert_false(a.runner.charging, "and the wait")
		await Duel.play_to(self, a, 100)
		assert_eq(started, [[&"palm_heavy", 1], [&"flinch", flinch_on]], "the button held on to frame 100 starts nothing (flinch on %d)" % flinch_on)
		assert_eq(b.stats.hp, 100.0, "and the heavy it had begun never struck")
		await Duel.play_to(self, a, 140)
		assert_eq(100.0 - b.stats.hp, HEAVY_HP, "the next heavy, tapped, is a plain one (flinch on %d)" % flinch_on)
		(run["arena"] as Node).free()


# A flinch on `a` from `b`'s jab, handed over as Melee hands over a blow.
func _flinch(a: Actor, b: Actor) -> void:
	var e := HitEvent.new()
	e.attacker = b
	e.target = a
	e.move = Registry.fetch(&"moves", &"palm_jab") as MoveData
	e.profile = e.move.hits[&"palm"]
	e.hitbox = &"palm_l"
	e.point = a.global_position + Vector3.UP
	e.direction = Vector3(0, 0, -1)
	var r := HitResult.new()
	r.outcome = HitResult.Outcome.HIT
	r.reaction = HitResult.Reaction.FLINCH
	a.apply_hit(e, r)
