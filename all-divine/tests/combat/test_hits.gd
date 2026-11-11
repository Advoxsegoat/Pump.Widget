extends TestCase
## Blows landing in play: Abarax-def actors in an arena, scanning their hitboxes every frame, with Melee
## judging every hit of a frame against the defenders as they stood when the frame began and then handing
## each side its result. The attacker stands at the origin facing +Z; the target 1.0 m in front of it, facing
## back. The target's def is a copy of Abarax's of team ENEMY with its own poise: Abarax's own poise (10) is
## more than the jab's poise damage (6), so a copy of poise 5 is one the jab flinches. Blows land only on the
## other team, so where both sides must be hit, one is a PLAYER copy and the other an ENEMY one.
##
## A frame is the actor's: the first it lives is 1. A palm pressed on frame 1 starts the jab there (its f0);
## its hitbox palm_l is on from f10 to f14 (frames 11 to 15), and its profile `palm` does 8 HP and 6 poise.
## The fixture dodge (Duel.untouchable_dash: the dash-step with iframes) is invulnerable from its f3 to f15. The death clip is 2.4 s (144 frames).

const ABARAX := "res://data/actors/abarax.tres"
const GAP := 1.0
## How far off the target of the late-swing test stands, so that the fixture dodge brings it into reach on frame 19.
const GAP_LATE := 2.3
const O := HitResult.Outcome


# Runs in the middle of a physics frame, as an actor does (after Melee's snapshot, before Melee): sets the
# target of `event` invulnerable or not, as `invulnerable` says (and kills it first, with `kill`), then posts
# the event, once.
class MidFrame extends Node:
	var event: HitEvent
	var invulnerable := false
	var kill := false

	func _physics_process(_delta: float) -> void:
		if event != null:
			if kill:
				event.target.die()
			event.target.runner.iframes = invulnerable
			Melee.post(event)
			event = null


## A copy of Abarax's def of team ENEMY, with `poise`.
func _foe(poise: float) -> ActorDef:
	return _copy(ActorDef.Team.ENEMY, poise)


## A copy of Abarax's def of `team`, with `poise`.
func _copy(team: ActorDef.Team, poise: float) -> ActorDef:
	var def := (load(ABARAX) as ActorDef).duplicate() as ActorDef
	def.team = team
	def.poise = poise
	return def


## Spawns, in a new arena, an attacker `a` at the origin facing +Z playing `a_steps` and a target `b` `gap`
## metres in front of it facing back playing `b_steps`, of `b_def` (and `a_def`; Abarax's if null). With
## `b_first`, `b` comes first in the tree, so it runs first in every frame. Records, per actor (a, b):
##   <x>_landed  [[outcome name, frame], ...] from hit_landed
##   <x>_got     [[outcome name, frame], ...] from got_hit
##   <x>_died    how many times died was emitted
##   <x>_started [[move id, frame], ...] from move_started
func _duel(a_steps: Array, b_steps: Array, b_def: ActorDef, a_def: ActorDef = null, b_first := false, gap := GAP) -> Dictionary:
	var arena := TestArena.make(self)
	var run := {"arena": arena}
	var specs := [["a", a_def if a_def != null else load(ABARAX), a_steps, Vector3.ZERO, 0.0],
			["b", b_def, b_steps, Vector3(0, 0, gap), PI]]
	if b_first:
		specs.reverse()
	for spec: Array in specs:
		var actor := TestArena.spawn(arena, spec[1], ScriptBrain.new(spec[2]), spec[3], spec[0].to_upper())
		actor.place(Transform3D(Basis(Vector3.UP, spec[4]), spec[3]))
		_watch(run, spec[0], actor)
	return run


## Spawns, in a new arena, a target `b` (an ENEMY copy of poise 5, with `b_hp` HP) between two PLAYER attackers
## facing it, `a` GAP in front of it at the origin and `c` GAP behind it, with `c` before `a` in the tree when
## `c_first`. Both start their move at once, `a` the jab and `c` `c_move`, so both hands come on and reach the
## target on the same frame (frame 10: the moves start before the actors' first frame). Records as _duel does,
## for a, b and c.
func _pincer(c_move: MoveData, b_hp: float, c_first: bool) -> Dictionary:
	var arena := TestArena.make(self)
	var run := {"arena": arena}
	var specs := [["a", Vector3.ZERO, 0.0], ["c", Vector3(0, 0, 2 * GAP), PI]]
	if c_first:
		specs.reverse()
	specs.append(["b", Vector3(0, 0, GAP), PI])
	for spec: Array in specs:
		var def: ActorDef = _foe(5.0) if spec[0] == "b" else load(ABARAX)
		var actor := TestArena.spawn(arena, def, ScriptBrain.new([]), spec[1], spec[0].to_upper())
		actor.place(Transform3D(Basis(Vector3.UP, spec[2]), spec[1]))
		_watch(run, spec[0], actor)
	(run["b"] as Actor).stats.hp = b_hp
	(run["a"] as Actor).runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	(run["c"] as Actor).runner.start(c_move)
	return run


## A copy of the jab whose palm profile staggers.
func _staggering_jab() -> MoveData:
	var jab := Registry.fetch(&"moves", &"palm_jab") as MoveData
	var move := jab.duplicate() as MoveData
	move.id = &"staggering_jab"
	var palm := (jab.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	palm.staggers = true
	move.hits = {&"palm": palm}
	return move


func _watch(run: Dictionary, key: String, actor: Actor) -> void:
	run[key] = actor
	for list in ["landed", "got", "started"]:
		run["%s_%s" % [key, list]] = []
	run[key + "_died"] = 0
	actor.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: run[key + "_landed"].append([O.keys()[r.outcome], actor.frame]))
	actor.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: run[key + "_got"].append([O.keys()[r.outcome], actor.frame]))
	actor.died.connect(func() -> void: run[key + "_died"] += 1)
	actor.runner.move_started.connect(func(m: MoveData) -> void: run[key + "_started"].append([m.id, actor.frame]))


# Plays until `actor` has lived `frame` frames.
func _play_to(actor: Actor, frame: int) -> void:
	while actor.frame < frame:
		await frames(1)


func _current(actor: Actor) -> StringName:
	return actor.runner.current.id if actor.runner.current != null else &""


func test_jab_lands_damage_and_flinches() -> void:
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 40}], [], _foe(5.0))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await _play_to(a, 10)
	assert_eq(b.stats.hp, 100.0, "the hand is not live before its f10")
	await _play_to(a, 12)
	assert_eq(run["a_landed"], [["HIT", 11]], "the jab lands once, on its f10")
	assert_eq(run["b_got"], [["HIT", 11]])
	assert_eq(b.stats.hp, 92.0)
	assert_eq(_current(b), &"flinch", "6 poise damage reaches poise 5")
	assert_eq(b.stats.posture, 96.0, "and the palm's 4 posture")
	await _play_to(a, 20)
	assert_eq(run["a_landed"].size(), 1, "the rest of the swing does not hit it again")
	assert_eq(a.stats.hp, 100.0)


func test_every_hit_kicks_the_additive_flinch() -> void:
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 40}], [], _foe(20.0))
	var b: Actor = run["b"]
	var kick := []
	b.got_hit.connect(func(_r: HitResult, _e: HitEvent) -> void: kick.append(b.rig.hit_reaction.tilt_velocity))
	assert_eq(b.rig.hit_reaction.tilt_velocity, Vector2.ZERO, "at rest before")
	await _play_to(run["a"], 20)
	assert_eq(b.stats.hp, 92.0, "the jab lands")
	assert_eq(run["b_started"], [], "but 6 poise damage is short of 20: no reaction move")
	assert_eq(kick.size(), 1)
	if kick.size() == 1:
		assert_true((kick[0] as Vector2).length() > 0.0, "and the upper body is kicked all the same: %s" % kick[0])


func test_iframes_whiff() -> void:
	# The target, 1.6 m off, starts the fixture dodge toward the attacker at the end of frame 5. It is invulnerable on frames 8
	# to 20 (the dodge's f3 to f15; judged a frame later, as it stood when each frame began), which take in all of the jab's
	# live frames, 11 to 15, and the step carries it through the hand's reach over just those frames. A whiff leaves the
	# body to be struck later in the swing, so each live frame in reach whiffs.
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 40}], [{"frames": 45}], _foe(5.0), null, false, 1.6)
	var b: Actor = run["b"]
	await _play_to(b, 5)
	b.runner.start(Duel.untouchable_dash(b))
	await _play_to(run["a"], 30)
	assert_eq(run["b_started"], [[&"untouchable_dash", 5]], "the dodge, and no reaction")
	assert_eq(b.stats.hp, 100.0)
	var outcomes: Array = run["a_landed"].map(func(l: Array) -> String: return l[0])
	assert_true(not outcomes.is_empty() and run["a_landed"][0] == ["WHIFF", 11], "the hand reached the dodging body on its first live frame: %s" % [run["a_landed"]])
	assert_eq(outcomes.filter(func(o: String) -> bool: return o != "WHIFF"), [], "and every blow whiffed: %s" % [run["a_landed"]])
	assert_eq(run["b_got"], run["a_landed"], "the target heard of each")


func test_a_swing_still_active_after_the_iframes_end_lands() -> void:
	# A fixture attack whose hitbox is live for 20 frames (the jab's clip, its palm_l on from f10 to f29, the hand
	# drawing back from 0.70 m to 0.30 m in front). The target, `GAP_LATE` m off, starts the fixture dodge toward the attacker
	# at the end of frame 5; it comes into the hand's reach on frame 19, the hitbox's first live frame, and
	# comes to rest in front, still in reach. Judged as it stood when each frame began, it is
	# invulnerable to frame 21: the blows of frames 19 to 21 whiff and leave it to be struck, and the one of
	# frame 22 lands, once.
	var run := _duel([], [{"frames": 70}], _foe(5.0), null, false, GAP_LATE)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var on := []
	a.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
		if kind == &"hitbox_on":
			on.append(a.frame))
	await _play_to(a, 5)
	b.runner.start(Duel.untouchable_dash(b))
	await _play_to(a, 9)
	a.runner.start(_long_jab(a))
	await _play_to(a, 45)
	assert_eq(on, [19], "the hitbox came on on frame 19")
	assert_eq(run["b_got"], [["WHIFF", 19], ["WHIFF", 20], ["WHIFF", 21], ["HIT", 22]],
			"stepped into it on its first frame, whiffed while invulnerable, struck once the iframes were over")
	assert_eq(run["a_landed"], run["b_got"])
	assert_eq(b.stats.hp, 92.0, "struck once")
	assert_eq(run["b_started"], [[&"untouchable_dash", 5], [&"flinch", 22]])


# A copy of the jab whose palm_l is live from f10 to f29, on a copy of its clip added to `a`'s rig.
func _long_jab(a: Actor) -> MoveData:
	var clip := a.rig.tree.get_animation(&"palm_jab").duplicate(true) as Animation
	Marks.write(clip, [
		{"time": Marks.time_of(10), "kind": &"hitbox_on", "args": {"id": &"palm_l", "profile": &"palm"}},
		{"time": Marks.time_of(30), "kind": &"hitbox_off", "args": {"id": &"palm_l"}},
	])
	a.rig.tree.get_animation_library(&"").add_animation(&"long_jab", clip)
	var move := (Registry.fetch(&"moves", &"palm_jab") as MoveData).duplicate() as MoveData
	move.id = &"long_jab"
	move.clip = &"long_jab"
	return move


func test_trade_lands_both_ways_in_either_order() -> void:
	# Both press palm on frame 1, so both hands come on and reach on frame 11. Each is judged against the
	# other as it stood when the frame began (both mid-jab), so both land and both flinch, whichever runs first.
	# Both are poise 5, on opposite teams.
	for b_first in [false, true]:
		var both := [{"frames": 1, "press": [&"palm"]}, {"frames": 30}]
		var run := _duel(both, both, _foe(5.0), _copy(ActorDef.Team.PLAYER, 5.0), b_first)
		var a: Actor = run["a"]
		var b: Actor = run["b"]
		await _play_to(a, 14)
		var order := "b first" if b_first else "a first"
		assert_eq([run["a_landed"], run["b_landed"]], [[["HIT", 11]], [["HIT", 11]]], "both land (%s)" % order)
		assert_eq([a.stats.hp, b.stats.hp], [92.0, 92.0], order)
		assert_eq([_current(a), _current(b)], [&"flinch", &"flinch"], order)
		(run["arena"] as Node).free()


func test_allies_do_not_hit_each_other() -> void:
	# Two of team ENEMY, the one jabbing the other: the hand passes through the body, and nothing comes of it.
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 30}], [], _foe(5.0), _foe(5.0))
	await _play_to(run["a"], 30)
	assert_eq(run["a_started"], [[&"palm_jab", 1]], "the jab is swung")
	assert_eq([run["a_landed"], run["b_got"]], [[], []], "but no blow is found, not even a whiff")
	assert_eq((run["b"] as Actor).stats.hp, 100.0)
	assert_eq(run["b_started"], [], "and no reaction")


func test_a_blow_is_judged_as_the_target_stood_when_the_frame_began() -> void:
	# A blow posted in the middle of a frame, on a target whose invulnerability changed earlier in that frame (as
	# a dodge's does in its own tick), is judged by what the target was when the frame began.
	var run := _duel([], [], _foe(5.0))
	var b: Actor = run["b"]
	await frames(2)
	# [invulnerable as the frame begins, invulnerable from the middle of it]
	for row in [[false, true], [true, false]]:
		b.runner.iframes = row[0]
		var mid := MidFrame.new()
		mid.event = _jab_on(run["a"], b)
		mid.invulnerable = row[1]
		track(mid)
		await frames(1)
		b.runner.iframes = false
		mid.free()
	assert_eq(run["b_got"].map(func(g: Array) -> String: return g[0]), ["HIT", "WHIFF"],
			"invulnerable from mid-frame: it lands; invulnerable until mid-frame: it whiffs")
	assert_eq(b.stats.hp, 92.0, "the one that landed")


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


func test_dead_are_not_hit_and_die_once() -> void:
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 44}, {"frames": 1, "press": [&"palm"]}, {"frames": 40}],
			[], _foe(5.0))
	var b: Actor = run["b"]
	b.stats.hp = 8.0
	await _play_to(run["a"], 12)
	assert_eq(run["a_landed"], [["HIT", 11]])
	assert_true(b.dead, "8 HP and a blow of 8")
	assert_eq(b.stats.hp, 0.0)
	assert_eq(run["b_died"], 1)
	assert_eq(run["b_started"], [[&"death", 11]], "the death plays, and no flinch over it")
	await _play_to(run["a"], 80)
	assert_eq(run["a_started"], [[&"palm_jab", 1], [&"palm_jab", 46]], "the second jab is swung")
	assert_eq(run["a_landed"], [["HIT", 11]], "and never lands on the dead")
	assert_eq(run["b_died"], 1, "who die once")
	assert_eq(_current(b), &"death", "and are left to fall")


func test_a_flinch_and_a_stagger_on_one_frame_are_one_stagger() -> void:
	# The jab from in front flinches the target; the staggering jab from behind staggers it. Both land on frame
	# 10, and whichever attacker runs first, they come to one reaction, the stronger, started once.
	for c_first in [false, true]:
		var run := _pincer(_staggering_jab(), 100.0, c_first)
		var b: Actor = run["b"]
		var sounds := []
		b.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
			if kind == &"sfx":
				sounds.append(b.frame))
		await _play_to(b, 15)
		var order := "c first" if c_first else "a first"
		assert_eq([run["a_landed"], run["c_landed"]], [[["HIT", 10]], [["HIT", 10]]], "both land (%s)" % order)
		assert_eq(b.stats.hp, 84.0, "both blows' damage (%s)" % order)
		assert_eq(run["b_started"], [[&"stagger", 10]], "one reaction, the stagger (%s)" % order)
		assert_eq(sounds, [10], "its sound once (%s)" % order)
		(run["arena"] as Node).free()


func test_two_killing_blows_on_one_frame_die_once() -> void:
	# Two blows of 8 on a body of 8 HP on the same frame, from in front and behind. Each would kill it alone;
	# they land together, and are one death that both dealt, whichever attacker runs first.
	for c_first in [false, true]:
		var run := _pincer(Registry.fetch(&"moves", &"palm_jab") as MoveData, 8.0, c_first)
		var b: Actor = run["b"]
		await _play_to(b, 15)
		var order := "c first" if c_first else "a first"
		assert_eq([run["a_landed"], run["c_landed"]], [[["HIT", 10]], [["HIT", 10]]], "both land (%s)" % order)
		assert_eq(run["b_got"], [["HIT", 10], ["HIT", 10]], order)
		assert_eq([run["b_died"], b.stats.hp], [1, 0.0], "one death (%s)" % order)
		assert_eq(run["b_started"], [[&"death", 10]], "and no reaction before it (%s)" % order)
		(run["arena"] as Node).free()


func test_two_blows_that_kill_together_die_once_without_a_flinch() -> void:
	# Two blows of 8 on a body of 12 HP: neither kills alone, both together do. The body dies, and does not
	# flinch on the way.
	for c_first in [false, true]:
		var run := _pincer(Registry.fetch(&"moves", &"palm_jab") as MoveData, 12.0, c_first)
		var b: Actor = run["b"]
		await _play_to(b, 15)
		var order := "c first" if c_first else "a first"
		assert_eq([run["a_landed"], run["c_landed"]], [[["HIT", 10]], [["HIT", 10]]], "both land (%s)" % order)
		assert_eq([run["b_died"], b.stats.hp], [1, 0.0], "they kill it together (%s)" % order)
		assert_eq(run["b_started"], [[&"death", 10]], "with no flinch first (%s)" % order)
		(run["arena"] as Node).free()


func test_a_blow_on_a_body_that_died_mid_frame_comes_to_nothing() -> void:
	# The target dies in the middle of a frame, after the snapshot, before Melee: the blow posted at it that
	# frame takes nothing, and both sides hear it was a whiff.
	var run := _duel([], [], _foe(5.0))
	var b: Actor = run["b"]
	await frames(2)
	var mid := MidFrame.new()
	mid.event = _jab_on(run["a"], b)
	mid.kill = true
	track(mid)
	await frames(1)
	assert_true(b.dead)
	assert_eq(b.stats.hp, 100.0, "nothing taken")
	assert_eq([run["a_landed"].map(func(l: Array) -> String: return l[0]), run["b_got"].map(func(g: Array) -> String: return g[0])],
			[["WHIFF"], ["WHIFF"]], "and both sides hear so")


func test_the_dead_fall_and_leave_the_actor_layer() -> void:
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 30}], [], _foe(5.0))
	var b: Actor = run["b"]
	b.stats.hp = 8.0
	await _play_to(run["a"], 12)
	assert_eq(b.rig.hurtbox.collision_layer, 0, "the hurtbox is off at once")
	assert_true(b.collision_layer & Layers.ACTOR != 0, "the body is an actor's while it falls")
	# The killing blow's 3 frames of hit-stop come first: the death clip starts on frame 15, not 12.
	await _play_to(run["a"], 11 + 3 + 144 + 2)
	assert_eq(b.collision_layer & Layers.ACTOR, 0, "and leaves the actor layer when the clip ends")
	assert_eq(b.collision_mask & Layers.WORLD, Layers.WORLD, "still lying on the world")
	var head := b.rig.bone_global(&"Head").y
	await _play_to(run["a"], 11 + 144 + 30)
	assert_true(head < 0.6, "down at the clip's end: the head %.2f m up" % head)
	assert_near(b.rig.bone_global(&"Head").y, head, 0.05, "and stays down")


func test_dead_do_not_attack() -> void:
	# Killed on frame 11. Its brain then presses palm and dodge and pushes the stick, while it falls and after.
	var east := Vector2(1, 0)
	var steps := [{"frames": 19}, {"frames": 1, "press": [&"palm"]}, {"frames": 9}, {"frames": 1, "press": [&"dodge"], "move": east},
			{"frames": 150, "move": east}, {"frames": 1, "press": [&"palm"]}, {"frames": 1, "press": [&"dodge"]}, {"frames": 20}]
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 30}], steps, _foe(5.0))
	var b: Actor = run["b"]
	b.stats.hp = 8.0
	var lay := Vector3.ZERO
	await _play_to(run["a"], 12)
	lay = b.global_position
	await _play_to(run["a"], 205)
	assert_eq(run["b_started"], [[&"death", 11]], "nothing starts after the death")
	assert_eq(b.buffer.size(), 0, "no press is even remembered")
	# The body does slide the 0.1 m of the killing blow's knockback along +Z (the jab's 1.0 m/s at a decay of 10),
	# which is not the stick, east.
	assert_near(b.global_position.x, lay.x, 0.05, "nor does the stick move the body")
	assert_near(b.global_position.z, lay.z + 0.1, 0.05, "which only slides on the blow's knockback")
	assert_eq(run["a"].stats.hp, 100.0)
