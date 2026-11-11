extends TestCase
## Clear-outs against the world (spec 3.4: "a body knocked back stops at walls and at other bodies, as every knockback does";
## Review Focus 4): in the training yard, a clear-out with a wall or a corner behind the foe, at Flurry's three metres, puts no
## one through it; three bodies thrown along one line do not end up inside each other; the paired and the dead are not thrown
## and a foe whose posture is broken is thrown but stays open to the finisher; and a foe thrown in the middle of its own swing
## does not hit him from where it lands, holds no attack token and walks back in.

const YARD := "res://world/training_yard/training_yard.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
## The yard runs from -HALF to HALF in x and z (its walls' inner faces), and a body's capsule is BODY wide in radius.
const HALF := 12.5
const BODY := 0.35
## Two bodies' centres are never nearer than this (two capsules touching), less a little for the spacing's own slack.
const APART := 0.65
## The chain that makes a clear-out a Flurry one: it throws three metres.
const FLURRY := 7


func after_each() -> void:
	Game.reset()


func _yard() -> Region:
	return track((load(YARD) as PackedScene).instantiate()) as Region


# An actor of the def at `path` standing at `at` in `parent` (a yard or an arena), facing `yaw`, driven by `brain`.
func _spawn(parent: Node3D, path: String, at: Vector3, brain: Brain = null, yaw := 0.0, actor_name := "") -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.def = _tough(path)
	actor.position = at
	actor.set_brain(brain if brain != null else Brain.new())
	if not actor_name.is_empty():
		actor.name = actor_name
	parent.add_child(actor)
	actor.place(Transform3D(Basis(Vector3.UP, yaw), at))
	return actor


# A copy of the def at `path` with HP enough to live through anything here, Abarax's on the player's side.
static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	return def


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


# Gives `actor` a chain of Flurry (it throws three metres), made on its frame 0.
func _flurry(actor: Actor) -> void:
	for i in FLURRY:
		actor.chain.link(false, 0)
	Melee.slow(0, 1.0)  # the way into Flurry slows the fight (ChainFx); these fights are timed to the frame


# The eight ways at a wall or a corner of the yard: a unit vector in (x, z).
func _ways() -> Dictionary:
	var s := sqrt(0.5)
	return {
		"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0),
		"north-east": Vector2(s, -s), "north-west": Vector2(-s, -s), "south-east": Vector2(s, s), "south-west": Vector2(-s, s),
	}


# How far (metres) the body's centre is past the reach of its capsule from the yard's walls.
func _out(actor: Actor) -> float:
	return maxf(absf(actor.global_position.x) - (HALF - BODY), absf(actor.global_position.z) - (HALF - BODY))


func test_a_clear_out_by_a_wall_and_in_a_corner_puts_no_one_through_it() -> void:
	for id: StringName in [&"clear_wave", &"clear_backpalm"]:
		for way_name: String in _ways():
			var way: Vector2 = _ways()[way_name]
			var region := _yard()
			# He stands three metres in from the wall (or corner). The wave throws the foe straight away from him, so it stands a metre on
			# toward the wall; the back palm throws it to his right, so he faces along the wall and the foe stands in front of him.
			var start := Vector2(0.0 if is_zero_approx(way.x) else signf(way.x) * (HALF - 3.0), 0.0 if is_zero_approx(way.y) else signf(way.y) * (HALF - 3.0))
			var facing := way if id == &"clear_wave" else Vector2(way.y, -way.x)
			var yaw := Locomotion.yaw_of(facing)
			var a := _spawn(region, ABARAX, Vector3(start.x, 0.0, start.y), null, yaw, "A")
			var at := start + (way if id == &"clear_wave" else facing) * 1.1
			var foe := _spawn(region, KNUCKLE_1, Vector3(at.x, 0.0, at.y), null, yaw + PI, "F")
			await frames(3)
			_flurry(a)
			a.runner.start(_move(id))
			var most_out := -INF
			var low := 0.0
			var high := 0.0
			var hit := []
			foe.got_hit.connect(func(_r: HitResult, _e: HitEvent) -> void: hit.append(true))
			for i in 150:
				await frames(1)
				most_out = maxf(most_out, _out(foe))
				low = minf(low, foe.global_position.y)
				high = maxf(high, foe.global_position.y)
			assert_false(hit.is_empty(), "%s %s: the foe was hit" % [id, way_name])
			assert_true(most_out < 0.05, "%s %s: the foe never got more than 5 cm past its capsule's reach of the wall (%.3f m)" % [id, way_name, most_out])
			assert_true(absf(foe.global_position.x) < HALF and absf(foe.global_position.z) < HALF, "%s %s: inside the yard at %s" % [id, way_name, foe.global_position])
			assert_true(low > -0.2 and high < 0.5, "%s %s: on the floor (y %.2f to %.2f)" % [id, way_name, low, high])
			assert_true(foe.global_position.distance_to(a.global_position) > 1.2, "%s %s: and the room was made (%.2f m)" % [id, way_name, foe.global_position.distance_to(a.global_position)])
			region.queue_free()
			await frames(1)


func test_bodies_thrown_into_each_other_do_not_overlap() -> void:
	# a file of three along the wave's line, and two along the back palm's: thrown together, they are never nearer one another, or him,
	# than two capsules touching
	for case: Array in [[&"clear_wave", [Vector3(0, 0, 1.0), Vector3(0, 0, 1.75), Vector3(0, 0, 2.5)]],
			[&"clear_backpalm", [Vector3(-0.4, 0, 0.9), Vector3(-1.15, 0, 0.9)]]]:
		var arena := TestArena.make(self)
		var a := _spawn(arena, ABARAX, Vector3.ZERO, null, 0.0, "A")
		var foes: Array[Actor] = []
		for i in (case[1] as Array).size():
			foes.append(_spawn(arena, KNUCKLE_1, case[1][i], null, PI, "F%d" % i))
		await frames(3)
		_flurry(a)
		a.runner.start(_move(case[0]))
		var nearest := INF
		var moved := 0.0
		for i in 150:
			await frames(1)
			for x in foes.size() + 1:
				var one: Actor = a if x == foes.size() else foes[x]
				for y in range(x + 1, foes.size() + 1):
					var other: Actor = a if y == foes.size() else foes[y]
					var gap := Vector2(one.global_position.x - other.global_position.x, one.global_position.z - other.global_position.z).length()
					if i > 2:
						nearest = minf(nearest, gap)
		for foe in foes:
			moved = maxf(moved, foe.global_position.distance_to(Vector3.ZERO))
		assert_true(nearest > APART, "%s: no two bodies came nearer than %.2f m (nearest %.2f)" % [case[0], APART, nearest])
		assert_true(moved > 2.0, "%s: and they were thrown (the furthest stands %.2f m from him)" % [case[0], moved])
		arena.queue_free()
		await frames(2)


func test_the_paired_and_the_dead_are_not_thrown_and_a_broken_foe_stays_finishable() -> void:
	var arena := TestArena.make(self)
	var a := _spawn(arena, ABARAX, Vector3.ZERO, null, 0.0, "A")
	var spots := [Vector3(0, 0, 1.3), Vector3(1.3, 0, 0), Vector3(0, 0, -1.3), Vector3(-1.3, 0, 0)]
	var dead := _spawn(arena, KNUCKLE_1, spots[0], null, 0.0, "Dead")
	var paired := _spawn(arena, KNUCKLE_1, spots[1], null, 0.0, "Paired")
	var broken := _spawn(arena, KNUCKLE_1, spots[2], null, 0.0, "Broken")
	var plain := _spawn(arena, KNUCKLE_1, spots[3], null, 0.0, "Plain")
	await frames(3)
	dead.die()
	await frames(200)  # lying where it fell, off the actor layer
	var lay := dead.global_position
	paired.paired_with = dead  # in a pair: no one else's blow lands on it (stands for a finisher or a grab in play)
	track(PostureBreaker.make(a, broken))
	await frames(3)
	assert_true(broken.is_in_group(Actor.FINISHABLE_GROUP), "the foe's posture is broken: it is open to the finisher")
	var at := {dead: dead.global_position, paired: paired.global_position, broken: broken.global_position, plain: plain.global_position}
	var hp := {dead: dead.stats.hp, paired: paired.stats.hp}
	_flurry(a)
	a.runner.start(_move(&"clear_wave"))
	await frames(40)
	assert_true(dead.global_position.distance_to(lay) < 0.02, "a corpse stays where it lies (%.3f m)" % dead.global_position.distance_to(lay))
	assert_eq(dead.stats.hp, hp[dead], "and takes nothing")
	assert_true(paired.global_position.distance_to(at[paired]) < 0.02, "a paired body is not thrown (%.3f m)" % paired.global_position.distance_to(at[paired]))
	assert_eq(paired.stats.hp, hp[paired], "and takes nothing")
	assert_true(plain.global_position.distance_to(at[plain]) > 1.5, "the one that is free is (%.2f m)" % plain.global_position.distance_to(at[plain]))
	assert_true(broken.global_position.distance_to(at[broken]) > 1.5, "a foe whose posture is broken is thrown too (%.2f m)" % broken.global_position.distance_to(at[broken]))
	assert_true(broken.is_in_group(Actor.FINISHABLE_GROUP), "and is still open to the finisher")
	assert_true(broken.runner.current != null and broken.runner.current.id == &"posture_broken", "still reeling from its broken posture, not staggered out of it")
	paired.paired_with = null


func test_a_foe_thrown_mid_swing_does_not_hit_from_where_it_lands_and_walks_back_in() -> void:
	# the control: the same jab, pressed on its frame 8, with no clear-out, reaches him
	var control := TestArena.make(self)
	var target := _spawn(control, ABARAX, Vector3.ZERO, null, 0.0, "A")
	_spawn(control, KNUCKLE_1, Vector3(0, 0, 0.95), ScriptBrain.new([{"frames": 7}, {"frames": 1, "press": [&"palm"]}, {"frames": 300}]), PI, "F")
	await frames(60)
	assert_true(target.stats.hp < target.stats.max_hp, "left alone he is hit by that jab")
	control.queue_free()
	await frames(2)
	var arena := TestArena.make(self)
	var tokens := AttackTokens.new()
	arena.add_child(tokens)
	var a := _spawn(arena, ABARAX, Vector3.ZERO, null, 0.0, "A")
	var foe_def := _tough(KNUCKLE_1)
	# a jab pressed on frame 8: its blow would be on frame 18, and he has a clear-out landing on frame 15
	var foe := _spawn(arena, KNUCKLE_1, Vector3(0, 0, 0.95), ScriptBrain.new([{"frames": 7}, {"frames": 1, "press": [&"palm"]}, {"frames": 300}]), PI, "F")
	await frames(1)
	var taken := []
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: taken.append(r.outcome))
	a.runner.start(_move(&"clear_wave"))
	var held_at_press := false
	var reeled := false
	var landed := Vector3.ZERO
	for i in 40:
		await frames(1)
		if foe.frame == 8:
			held_at_press = tokens.take(foe, a)
		if foe.runner.current != null and foe.runner.current.id == &"stagger":
			reeled = true
	landed = foe.global_position
	assert_true(held_at_press, "the foe held a token for the jab")
	assert_true(reeled, "the clear-out staggered the foe in the middle of its swing")
	assert_false(tokens.holds(foe), "it holds no token: the stagger gave it back")
	assert_true(landed.distance_to(a.global_position) > 2.0, "it was thrown out of reach (%.2f m from him)" % landed.distance_to(a.global_position))
	await frames(60)
	assert_eq(taken.filter(func(o: int) -> bool: return o != HitResult.Outcome.WHIFF), [], "its jab never reached him from where it landed")
	assert_eq(a.stats.hp, a.stats.max_hp, "and he is untouched")
	# Landed, it thinks as any foe does: with its brain it comes back for him within a few seconds.
	foe.set_brain(EnemyBrain.new(foe_def.brain, 7))
	var after_throw := foe.global_position.distance_to(a.global_position)
	var closest := after_throw
	for i in 300:
		await frames(1)
		closest = minf(closest, foe.global_position.distance_to(a.global_position))
	assert_true(closest < after_throw - 0.8, "it walks back in (from %.2f m to %.2f m)" % [after_throw, closest])
	assert_true(tokens.count(a) <= AttackTokens.PER_TARGET, "and the tokens are in order")
