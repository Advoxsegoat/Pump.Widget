extends TestCase
## The parry and the catch: guard_raise's first ten frames (f0 to f9, 167 ms) are a parry window. A blow judged
## while it is open, from inside the guard arc, is turned back: an ordinary blow is PARRIED (the attacker plays
## `parried` and loses twice the blow's posture damage), a perilous thrust is CAUGHT (the attacker plays `caught`
## and loses catch_posture, 50), and a perilous sweep goes through. The defender plays `parry` or `catch`, whose
## cancel window into palm or heavy (f8, f14) is the riposte.
##
## Fighters are the Duel's: `a` (PLAYER) at the origin facing +Z jabs on frame 1, and its hand lands on frame 11 (its
## f10; palm: 8 HP, 6 poise, 4 posture, 3 frames of hit-stop). `b` (an ENEMY copy of Abarax, poise 5) a metre in front
## facing back answers. A blow is judged against how b stood when the frame began, so a guard pressed on frame g is
## a parry for blows judged on frames g + 1 to g + 10.

const O := HitResult.Outcome
const JAB := [{"frames": 1, "press": [&"palm"]}, {"frames": 80}]
const LANDS := 11


# The Duel of `a_steps` and `b_steps` with what each side heard of every blow (see test_guard.gd), and the sounds
# of each of b's frames: `heard` {frame: [cue ids]}.
func _duel(a_steps: Array, b_steps: Array) -> Dictionary:
	var run := Duel.make(self, a_steps, b_steps)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	for key in ["landed", "got", "a_started", "b_started"]:
		run[key] = []
	run["heard"] = {}
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: run["landed"].append([O.keys()[r.outcome], a.frame]))
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: run["got"].append([O.keys()[r.outcome], b.frame]))
	a.runner.move_started.connect(func(m: MoveData) -> void: run["a_started"].append([m.id, a.frame]))
	b.runner.move_started.connect(func(m: MoveData) -> void: run["b_started"].append([m.id, b.frame]))
	return run


# Plays to b's frame `frame`, noting the sounds of each frame in run.heard.
func _play_to(run: Dictionary, frame: int) -> void:
	var b: Actor = run["b"]
	while b.frame < frame:
		await frames(1)
		run["heard"][b.frame] = Sfx.last_played().duplicate()


# A tap of guard on frame `frame`.
func _tap_guard(frame: int, then := []) -> Array:
	return [{"frames": frame - 1}, {"frames": 1, "press": [&"guard"], "hold": [&"guard"]}] + then + [{"frames": 80}]


func _current(actor: Actor) -> StringName:
	return actor.runner.current.id if actor.runner.current != null else &""


# A copy of the jab whose palm profile is `perilous`.
func _perilous_jab(perilous: HitProfile.Perilous) -> MoveData:
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var move := jab.duplicate() as MoveData
	move.id = &"perilous_jab"
	var palm := (jab.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	palm.perilous = perilous
	move.hits = {&"palm": palm}
	return move


func test_the_parry_window_is_the_raises_first_ten_frames() -> void:
	var run := _duel([], [{"frames": 1, "press": [&"guard"]}, {"frames": 30}])
	var b: Actor = run["b"]
	var parrying := []
	while b.frame < 20:
		await frames(1)
		if Defense.of(b).parrying:
			parrying.append(b.frame)
	assert_eq(parrying, range(1, 11), "frames 1 to 10: the raise's f0 to f9, 167 ms")


func test_guard_tapped_five_frames_before_the_hit_parries() -> void:
	# Guard on frame 6: the jab is judged on frame 11 against the raise at its f4. The palm b presses on frame 12
	# (in the hit-stop) waits in its buffer for the parry's riposte window at f8: frame 22, after the 3 frozen frames.
	var run := _duel(JAB, _tap_guard(6, [{"frames": 5}, {"frames": 1, "press": [&"palm"]}]))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await _play_to(run, LANDS)
	assert_eq(run["landed"], [["PARRIED", LANDS]], "parried")
	assert_eq(run["got"], run["landed"])
	assert_eq(a.stats.posture, 100.0 - 2 * 4.0, "the attacker loses twice the palm's posture")
	assert_eq([b.stats.hp, b.stats.stamina, b.stats.posture], [100.0, 100.0, 100.0], "the parry costs b nothing")
	assert_eq([_current(a), _current(b)], [&"parried", &"parry"], "a recoils, b parries")
	assert_true(run["heard"][LANDS].has(&"parry_ring"), "it rings: %s" % [run["heard"][LANDS]])
	assert_false(run["heard"][LANDS].has(&"impact_palm"), "and no blow lands on flesh")
	var sparks := get_tree().get_nodes_in_group(ActorFx.GROUP).filter(func(n: Node) -> bool: return n.get_meta(&"fx") == &"hit_spark")
	assert_eq(sparks.size(), 1, "a spark where the hand met the parry")
	assert_eq([a.frozen, b.frozen], [3, 3], "both freeze")
	await _play_to(run, 22)
	assert_eq(run["b_started"].back(), [&"palm_jab", 22], "b's palm comes out at the parry's f8, 8 frames after the hit-stop")
	assert_eq(_current(a), &"parried", "while a is still recoiling")
	await _play_to(run, 34)
	assert_eq(a.stats.hp, 92.0, "and the riposte lands")


func test_guard_pressed_twelve_frames_early_only_guards() -> void:
	# a's jab on frame 13 lands on frame 23; b's guard, pressed on frame 11 and held, is at its f11 then: past the
	# parry window, inside the guard.
	var run := _duel([{"frames": 12}] + JAB, _tap_guard(11, [{"frames": 30, "hold": [&"guard"]}]))
	var b: Actor = run["b"]
	await _play_to(run, 23)
	assert_eq(run["landed"], [["GUARDED", 23]], "guarded, not parried")
	assert_eq(_current(b), &"guard_hit")
	assert_eq((run["a"] as Actor).stats.posture, 100.0, "the attacker loses nothing")


func test_mashing_guard_does_not_reopen_the_window() -> void:
	# Guard pressed on frames 1, 4, 7, 10 and 13: the raise from frame 1 cannot cancel into itself, so the later
	# presses neither restart it nor reopen its window. a's jab, pressed on frame 3, is judged on frame 13 against the
	# raise at its f11: guarded.
	var mash := []
	for f in [1, 4, 7, 10, 13]:
		mash.append({"frames": 1 if f == 1 else 2})
		mash.append({"frames": 1, "press": [&"guard"]})
	mash.pop_front()
	var run := _duel([{"frames": 2}] + JAB, mash + [{"frames": 30}])
	await _play_to(run, 13)
	assert_eq(run["b_started"], [[&"guard_raise", 1], [&"guard_hit", 13]], "one raise, then the blow")
	assert_eq(run["landed"], [["GUARDED", 13]], "guarded, not parried")


func test_guard_spammed_every_ten_frames_parries_at_most_the_first_blow() -> void:
	# Guard tapped every 10 frames for 2 s chains fresh raises, one as each ends (about every 14 frames). A blow is
	# judged at the f5 of every raise, where its window would be open and its guard is up. Only a raise that starts parry_refresh_frames
	# (20) or more after the one before opens its window, so the first blow is parried and every later one guarded.
	# b's def leaves out the parry and guard_hit reactions, so no reaction cuts a raise short and spaces them out.
	var b_def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	b_def.reactions = b_def.reactions.duplicate()
	b_def.reactions.erase(&"parry")
	b_def.reactions.erase(&"guard_hit")
	var taps := []
	for i in 12:
		taps.append({"frames": 1, "press": [&"guard"]})
		taps.append({"frames": 9})
	var run := Duel.make(self, [], taps + [{"frames": 40}], 1.0, b_def)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var outcomes := []
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(O.keys()[r.outcome]))
	var stream := Stream.new()
	stream.target = b
	stream.event = _jab_on(a, b)
	track(stream)
	await Duel.play_to(self, b, 165)  # the taps end on frame 120; every raise has played out by then
	assert_true(stream.raises >= 7, "the taps chained %d raises" % stream.raises)
	assert_eq(outcomes.size(), stream.raises, "a blow met every raise: %s" % [outcomes])
	assert_true(outcomes.count("PARRIED") <= 1 and (outcomes.find("PARRIED") <= 0), "at most the first is parried: %s" % [outcomes])
	assert_eq(outcomes.slice(1).filter(func(o: String) -> bool: return o != "GUARDED"), [], "the rest are guarded: %s" % [outcomes])


func test_a_held_guard_mashed_against_real_blows_guards_every_one_after_the_first() -> void:
	# As above, but with guard held all along, and each blow judged at the raise's f2: before the raise's guard_on
	# mark (f4). Only the first raise opens a parry window; every later one still guards from its start, because
	# guard is held, so no blow lands.
	var b_def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	b_def.reactions = b_def.reactions.duplicate()
	b_def.reactions.erase(&"parry")
	b_def.reactions.erase(&"guard_hit")
	var taps := []
	for i in 12:
		taps.append({"frames": 1, "press": [&"guard"], "hold": [&"guard"]})
		taps.append({"frames": 9, "hold": [&"guard"]})
	var run := Duel.make(self, [], taps + [{"frames": 40, "hold": [&"guard"]}], 1.0, b_def)
	var b: Actor = run["b"]
	var outcomes := []
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(O.keys()[r.outcome]))
	var stream := Stream.new()
	stream.target = b
	stream.event = _jab_on(run["a"], b)
	stream.at = 2
	track(stream)
	await Duel.play_to(self, b, 165)
	assert_true(stream.raises >= 7, "the presses chained %d raises" % stream.raises)
	assert_eq(outcomes.size(), stream.raises, "a blow met every raise: %s" % [outcomes])
	assert_eq(outcomes.slice(0, 1), ["PARRIED"], "the first is parried: %s" % [outcomes])
	assert_eq(outcomes.slice(1).filter(func(o: String) -> bool: return o != "GUARDED"), [], "and the rest guarded: %s" % [outcomes])


func test_an_honest_tap_twenty_frames_after_the_last_raise_still_parries() -> void:
	# A raise on frame 1, then a second tapped `gap` frames after it; a's jab lands 5 frames into the second. 20 frames
	# (parry_refresh_frames) after the first, its window is open; 19, it only guards.
	for gap: int in [20, 19]:
		var second := 1 + gap
		var run := _duel([{"frames": second - 6}] + JAB, [{"frames": 1, "press": [&"guard"]}, {"frames": gap - 1},
				{"frames": 1, "press": [&"guard"]}, {"frames": 40}])
		await _play_to(run, second + 5)
		assert_eq(run["b_started"].slice(0, 2), [[&"guard_raise", 1], [&"guard_raise", second]], "two raises (gap %d)" % gap)
		assert_eq(run["landed"], [["PARRIED" if gap >= 20 else "GUARDED", second + 5]], "gap %d" % gap)
		(run["arena"] as Node).free()


# Posts the event `event` (a's jab on b) once per raise of b's, judged at the raise's frame `at`: it runs after
# Melee's snapshot and before the actors, so it sees b as the snapshot did.
class Stream extends Node:
	var target: Actor
	var event: HitEvent
	var at := 5
	var raises := 0
	var _posted_for := -1

	func _ready() -> void:
		process_physics_priority = -50
		target.runner.move_started.connect(func(m: MoveData) -> void:
			if m.id == &"guard_raise":
				raises += 1)

	func _physics_process(_delta: float) -> void:
		var runner := target.runner
		if runner.current != null and runner.current.id == &"guard_raise" and Marks.frame_of(runner.time) == at \
				and _posted_for != raises:
			_posted_for = raises
			Melee.post(event)


func test_parried_thrust_is_caught() -> void:
	var run := _duel([{"frames": 80}], _tap_guard(6))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	a.runner.start(_perilous_jab(HitProfile.Perilous.THRUST))
	await _play_to(run, 10)
	assert_eq(run["landed"], [["CAUGHT", 10]], "the thrust is caught")
	assert_eq(a.stats.posture, 50.0, "the attacker loses catch_posture, 50")
	assert_eq(b.stats.hp, 100.0)
	assert_eq([_current(a), _current(b)], [&"caught", &"catch"], "a is caught, b catches")
	assert_true(run["heard"][10].has(&"catch_snap"), "it snaps: %s" % [run["heard"][10]])


func test_parried_sweep_still_hits() -> void:
	var run := _duel([{"frames": 80}], _tap_guard(6))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	a.runner.start(_perilous_jab(HitProfile.Perilous.SWEEP))
	await _play_to(run, 10)
	assert_eq(run["landed"], [["HIT", 10]], "a sweep cannot be parried")
	assert_eq(b.stats.hp, 92.0)
	assert_eq(_current(b), &"flinch")
	assert_eq(a.stats.posture, 100.0)


func test_a_parry_that_empties_the_posture_staggers_the_attacker() -> void:
	# a has 8 posture left; the parry takes 8. Its posture breaks, which plays its posture_broken reaction, or until
	# there is one, its stagger, over `parried`.
	var run := _duel(JAB, _tap_guard(6))
	var a: Actor = run["a"]
	await _play_to(run, LANDS - 1)
	a.stats.damage_posture(92.0)  # 8 left, and the wait before it mends starts over
	await _play_to(run, LANDS)
	assert_eq(run["landed"], [["PARRIED", LANDS]])
	assert_true(a.stats.posture_broken, "broken")
	assert_eq(_current(a), &"stagger")


func test_a_broken_posture_plays_the_defs_posture_broken_when_it_has_one() -> void:
	var a_def := Duel.def(ActorDef.Team.PLAYER, 5.0)
	a_def.reactions = a_def.reactions.duplicate()
	a_def.reactions[&"posture_broken"] = &"guard_break"  # any move will do, until Task 10 brings its own
	var run := Duel.make(self, JAB, _tap_guard(6), 1.0, null, a_def)
	var a: Actor = run["a"]
	await Duel.play_to(self, a, LANDS - 1)
	a.stats.damage_posture(92.0)
	await Duel.play_to(self, a, LANDS)
	assert_true(a.stats.posture_broken)
	assert_eq(_current(a), &"guard_break", "the def's posture_broken")


func test_a_blow_turned_back_twice_on_one_frame_is_taken_once_in_either_order() -> void:
	# a's palm, posted at two parrying foes on one frame (as a wide swing would find both), whichever of them runs
	# and is posted first: a loses the posture of both parries and starts `parried` once.
	for c_first in [false, true]:
		var arena := TestArena.make(self)
		var specs := [["c", Vector3(0.6, 0, 1.0)], ["b", Vector3(-0.6, 0, 1.0)]]
		if not c_first:
			specs.reverse()
		var foes := {}
		for spec: Array in specs:
			var foe := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([]), spec[1], spec[0].to_upper())
			foe.place(Transform3D(Basis(Vector3.UP, PI), spec[1]))
			foes[spec[0]] = foe
		var a := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new([]), Vector3.ZERO, "A")
		var started := []
		a.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
		await frames(1)
		var poster := Poster.new()
		for key in (["c", "b"] if c_first else ["b", "c"]):
			var foe: Actor = foes[key]
			foe.runner.parry_window = true
			poster.events.append(_jab_on(a, foe))
		track(poster)
		await frames(1)
		var order := "c first" if c_first else "b first"
		assert_eq(a.stats.posture, 100.0 - 2 * 2 * 4.0, "both parries' posture (%s)" % order)
		assert_eq(started, [&"parried"], "one recoil (%s)" % order)
		assert_eq([_current(foes["b"]), _current(foes["c"])], [&"parry", &"parry"], order)
		arena.free()


# Posts its events to Melee in the middle of the next physics frame, after the snapshot that saw the foes parrying.
class Poster extends Node:
	var events: Array[HitEvent] = []

	func _physics_process(_delta: float) -> void:
		for e in events:
			Melee.post(e)
		events.clear()


# A jab's palm from `a` on `b`, as a scanner would make it.
func _jab_on(a: Actor, b: Actor) -> HitEvent:
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var e := HitEvent.new()
	e.attacker = a
	e.target = b
	e.move = jab
	e.profile = jab.hits[&"palm"]
	e.hitbox = &"palm_l"
	e.point = b.global_position + Vector3.UP
	e.direction = (b.global_position - a.global_position).normalized()
	return e
