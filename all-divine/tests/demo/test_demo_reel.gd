extends TestCase
## The preview reel (demo/demo_reel.tscn): Abarax's scripted choreography against a Knuckle that throws three scripted
## attacks. The recording is only worth making while every beat really happens, so this plays the reel in game time
## and checks them in order: the jab, cross and hook land; the Knuckle's jab is parried; its sweep and its thrust
## find Abarax hopping and rolling, so he is never hurt; a charged heavy, a jab and a cross break its posture; and the
## Open Hand finisher kills it.

const REEL := "res://demo/demo_reel.tscn"
const O := HitResult.Outcome


func after_each() -> void:
	Game.reset()


func test_every_beat_of_the_reel_happens() -> void:
	Game.reset()
	var reel := track((load(REEL) as PackedScene).instantiate()) as DemoReel
	var abarax := reel.player
	var knuckle := reel.foe
	var mine: Array[StringName] = []
	var theirs: Array[StringName] = []
	abarax.runner.move_started.connect(func(m: MoveData) -> void: mine.append(m.id))
	knuckle.runner.move_started.connect(func(m: MoveData) -> void: theirs.append(m.id))
	var taken: Array[int] = []
	abarax.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: taken.append(r.outcome))
	var landed: Array[int] = []
	abarax.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: landed.append(r.outcome))
	var charged := [0]
	abarax.runner.charged.connect(func(_m: MoveData) -> void: charged[0] += 1)
	await frames(60 * 20)
	assert_eq(mine, [&"palm_jab", &"palm_cross", &"palm_hook", &"guard_raise", &"parry", &"palm_jab", &"hop", &"dodge_roll",
			&"palm_heavy", &"palm_jab", &"palm_cross", &"finisher"], "Abarax's moves, in order")
	assert_eq(theirs, [&"flinch", &"knuckle_jab", &"parried", &"knuckle_sweep", &"knuckle_thrust", &"stagger", &"posture_broken",
			&"finisher_victim"], "the Knuckle's, in order")
	assert_eq(abarax.stats.hp, abarax.stats.max_hp, "not one blow hurt him")
	assert_true(taken.has(O.PARRIED), "he parried the jab")
	assert_true(taken.has(O.WHIFF), "the sweep and the thrust came to nothing")
	assert_false(taken.has(O.HIT) or taken.has(O.GUARDED), "and nothing else came to anything")
	assert_eq(charged[0], 1, "the heavy was charged")
	assert_true(landed.count(O.HIT) >= 8, "his blows landed (%d)" % landed.count(O.HIT))
	assert_true(knuckle.dead, "the finisher killed the Knuckle")
