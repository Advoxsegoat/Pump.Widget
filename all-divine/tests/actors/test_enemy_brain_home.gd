extends TestCase
## The enemy brain's habits for a foe that stands at a post (actors/enemy_brain.gd, F3 systems Task 4): it can sleep, be woken or
## alarmed, have a home and a leash, and it walks home whenever it stands down (past its leash, no target in reach, its target
## dead). Every one is inert at its default: a brain with no home and no leash is the yard's.
##
## Abarax (his own def, HP to spare) stands in a flat arena driven by a brain that does nothing; the Knuckle stands 2 m off
## facing him unless a test says otherwise.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE := "res://data/actors/knuckle_1.tres"
const BRAIN := "res://data/brains/knuckle_1.tres"
const JOG := 5.5
const ARRIVED := 0.6

var _count := {}


static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	return def


# A bare arena with Abarax at the origin and a Knuckle at `at` facing `yaw`: {arena, abarax, knuckle, brain}.
func _scene(at := Vector3(0, 0, 2), yaw := PI) -> Dictionary:
	var arena := TestArena.make(self)
	var abarax := TestArena.spawn(arena, _tough(ABARAX), Brain.new(), Vector3.ZERO, "Abarax")
	var brain := EnemyBrain.new(load(BRAIN) as BrainDef, 7)
	var knuckle := TestArena.spawn(arena, _tough(KNUCKLE), brain, at, "Knuckle")
	knuckle.place(Transform3D(Basis(Vector3.UP, yaw), at))
	_count = {engaged = 0, arrived = 0}
	brain.engaged.connect(func() -> void: _count.engaged += 1)
	brain.arrived_home.connect(func() -> void: _count.arrived += 1)
	return {arena = arena, abarax = abarax, knuckle = knuckle, brain = brain}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_an_asleep_foe_notices_nothing_and_wakes_into_the_fight() -> void:
	var s := _scene()
	var brain: EnemyBrain = s.brain
	var knuckle: Actor = s.knuckle
	brain.asleep = true
	var at := knuckle.global_position
	var facing := knuckle.facing()
	await frames(120)
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE, "asleep, with him 2 m ahead in plain sight, it stays idle")
	assert_vec_near(knuckle.global_position, at, 1e-3, "it does not move")
	assert_vec_near(knuckle.facing(), facing, 1e-3, "or turn")
	assert_eq(_count.engaged, 0, "and has not engaged")
	brain.wake()
	await frames(2)
	assert_eq(brain.mode, EnemyBrain.Mode.ENGAGED, "woken, it engages within two frames")
	assert_eq(_count.engaged, 1, "once")


func test_a_foe_past_its_leash_gives_up_and_walks_home_and_ignores_the_target_on_the_way() -> void:
	var s := _scene(Vector3(0, 0, 3), PI)
	var brain: EnemyBrain = s.brain
	var knuckle: Actor = s.knuckle
	var abarax: Actor = s.abarax
	brain.home = Vector3(0, 0, 3)
	brain.leash = 6.0
	await frames(90)
	assert_eq(brain.mode, EnemyBrain.Mode.ENGAGED, "(it engaged him)")
	assert_false(brain.going_home(), "(and is not going home while it is inside its leash)")
	abarax.place(Transform3D(Basis(), Vector3(0, 0, 14)))
	var started := -1
	for i in 400:
		await frames(1)
		if brain.going_home():
			started = i
			break
	assert_true(started >= 0, "past its leash it stands down and goes home")
	var away := _flat(knuckle.global_position, brain.home)
	assert_true(away > 6.0 and away < 9.0, "just past the leash (%.2f m from home)" % away)
	var seconds := away / JOG + 2.0
	var attacked := false
	var frames_taken := 0
	while _count.arrived == 0 and frames_taken < int(seconds * 60.0):
		# the target stands 1 m from it, on the side away from home, all the way
		var out := (knuckle.global_position - (brain.home as Vector3)).normalized()
		abarax.place(Transform3D(Basis(), knuckle.global_position + out * 1.0))
		await frames(1)
		frames_taken += 1
		if knuckle.runner.current != null and knuckle.runner.current.kind == MoveData.Kind.ATTACK:
			attacked = true
	assert_false(attacked, "it started no attack on the way, with him 1 m away")
	assert_eq(_count.arrived, 1, "it arrives within distance / jog + 2 s (%.1f s), and says so once" % seconds)
	assert_true(_flat(knuckle.global_position, brain.home) <= ARRIVED + 0.05, "within 0.6 m of home")
	assert_false(brain.going_home(), "and is done going")
	await frames(30)
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE, "idle again")
	assert_eq(_count.arrived, 1, "(once)")
	var ahead := knuckle.facing() * 4.0
	abarax.place(Transform3D(Basis(), knuckle.global_position + ahead))
	await frames(90)
	assert_eq(brain.mode, EnemyBrain.Mode.ENGAGED, "and it engages again when he is in its sight")


func test_the_walk_home_gives_up_after_eight_seconds() -> void:
	var s := _scene(Vector3(0, 0, -5), 0.0)
	var brain: EnemyBrain = s.brain
	TestArena.wall(s.arena, Vector3(0, 1.5, 0), Vector3(39.0, 3.0, 0.5))
	brain.home = Vector3(0, 0, 5)  # the other side of a wall that spans the arena
	brain.leash = 3.0
	(s.abarax as Actor).place(Transform3D(Basis(), Vector3(0, 0, -9)))
	brain.engage_now()
	var went := -1
	for i in 120:
		await frames(1)
		if brain.going_home():
			went = i + 1
			break
	assert_true(went >= 0, "ten metres from a home with a 3 m leash, it goes home at once")
	await frames(60 * 8 - went - 20)
	assert_true(brain.going_home(), "(still walking at 7.7 s)")
	await frames(40)
	assert_false(brain.going_home(), "walled off from home, it gives up by 8.1 s of walking")
	assert_eq(_count.arrived, 0, "and never arrived")
	assert_true(_flat(s.knuckle.global_position, brain.home) > 3.0, "(it is still short of home)")


func test_a_foe_that_loses_its_target_walks_home() -> void:
	var s := _scene(Vector3(0, 0, 3), PI)
	var brain: EnemyBrain = s.brain
	brain.home = Vector3(0, 0, 3)  # no leash: only losing him sends it home
	await frames(90)
	assert_eq(brain.mode, EnemyBrain.Mode.ENGAGED, "(it engaged him)")
	# He runs off past twice its sight (24 m): the arena is 40 m, so it is drawn out first, then he goes.
	(s.abarax as Actor).place(Transform3D(Basis(), Vector3(0, 0, -18)))
	var knuckle: Actor = s.knuckle
	knuckle.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 0, 8)))
	(s.abarax as Actor).place(Transform3D(Basis(), Vector3(0, 0, -18)))
	await frames(2)
	assert_true(brain.going_home(), "a foe that has lost him is going home, 5 m from it")
	await frames(60 * 3)
	assert_eq(_count.arrived, 1, "and gets there")


func test_a_foe_whose_target_died_walks_home() -> void:
	var s := _scene(Vector3(0, 0, 3), PI)
	var brain: EnemyBrain = s.brain
	brain.home = Vector3(0, 0, 8)
	await frames(90)
	assert_eq(brain.mode, EnemyBrain.Mode.ENGAGED, "(it engaged him)")
	(s.abarax as Actor).die()
	await frames(3)
	assert_true(brain.going_home(), "its target died: it goes home")
	await frames(60 * 4)
	assert_eq(_count.arrived, 1, "and arrives")


func test_engage_now_skips_the_noticing() -> void:
	var s := _scene(Vector3(0, 0, 2), 0.0)  # his back to Abarax
	var brain: EnemyBrain = s.brain
	await frames(30)
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE, "with his back turned it has not noticed him")
	brain.engage_now()
	await frames(2)
	assert_eq(brain.mode, EnemyBrain.Mode.ENGAGED, "an alarm sends it straight to engaged")
	assert_eq(_count.engaged, 1, "and it engaged once")
	brain.engage_now()
	await frames(5)
	assert_eq(_count.engaged, 1, "a second alarm to one that is engaged says nothing more")


func test_the_signal_engaged_comes_once_per_engagement() -> void:
	var s := _scene(Vector3(0, 0, 4), PI)
	var brain: EnemyBrain = s.brain
	await frames(60 * 6)
	assert_eq(brain.mode == EnemyBrain.Mode.ENGAGED or brain.mode == EnemyBrain.Mode.ATTACKING, true, "(fighting)")
	assert_eq(_count.engaged, 1, "one signal for a whole fight, not one for each attack")


func test_with_no_home_and_no_leash_nothing_is_different() -> void:
	var s := _scene(Vector3(0, 0, 3), PI)
	var brain: EnemyBrain = s.brain
	assert_true(brain.home == null, "no home by default")
	assert_eq(brain.leash, INF, "no leash by default")
	assert_false(brain.asleep, "awake by default")
	await frames(90)
	(s.abarax as Actor).place(Transform3D(Basis(), Vector3(0, 0, -19)))
	(s.knuckle as Actor).place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 0, 8)))
	await frames(60 * 4)
	assert_eq(brain.mode, EnemyBrain.Mode.IDLE, "it lost him and is idle")
	assert_false(brain.going_home(), "it never goes home")
	assert_eq(_count.arrived, 0, "and never arrives")
