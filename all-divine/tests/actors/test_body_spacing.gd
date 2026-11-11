extends TestCase
## Bodies do not pass through each other (BodySpacing): on the ground an actor's motion stops at another actor's capsule,
## so the Knuckle's thrust stops at the body it hits and ends in front of it, and Abarax's own lunges (the hook, the dash-step)
## stop at a Knuckle; while a body is airborne (the hop) a low slide passes beneath it, so the hop still counters the
## sweep. Measured on every attack below: no two grounded capsules are ever more than SLACK inside each other.
##
## Abarax (his own def, a ScriptBrain, HP to spare) stands at the origin facing +Z; the Knuckle stands `gap` metres in
## front of him on +Z, facing back, and presses its action on frame 1.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_2 := "res://data/actors/knuckle_2.tres"
## How far two grounded capsules may be pressed into each other at most.
const SLACK := 0.05
const O := HitResult.Outcome


# A copy of the def at `path` with HP enough to live through anything here.
static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	return def


# Abarax at the origin facing +Z driven by `abarax_steps`, and a Knuckle of `knuckle_path` `gap` metres in front facing
# back, driven by `knuckle_steps`: {abarax, knuckle}.
func _pair(gap: float, knuckle_steps: Array, abarax_steps := [], knuckle_path := KNUCKLE_2) -> Dictionary:
	var arena := TestArena.make(self)
	var abarax := TestArena.spawn(arena, _tough(ABARAX), ScriptBrain.new(abarax_steps), Vector3.ZERO, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var at := Vector3(0, 0, gap)
	var knuckle := TestArena.spawn(arena, _tough(knuckle_path), ScriptBrain.new(knuckle_steps), at, "Knuckle")
	knuckle.place(Transform3D(Basis(Vector3.UP, PI), at))
	return {"abarax": abarax, "knuckle": knuckle}


# The two capsules' gap on the ground: how far apart their axes are, less both radii (negative: that far inside).
static func _clearance(a: Actor, b: Actor) -> float:
	var flat := Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z)
	return flat.length() - _radius(a) - _radius(b)


# The radius of `actor`'s body capsule (actor.tscn's Body).
static func _radius(actor: Actor) -> float:
	return ((actor.get_node(^"Body") as CollisionShape3D).shape as CapsuleShape3D).radius


# Plays `frames_to_play` frames and returns the deepest the two capsules were inside each other on a frame where both
# stood on the ground (neither airborne), as a positive depth (0 if they never touched).
func _deepest(a: Actor, b: Actor, frames_to_play: int) -> float:
	var deepest := 0.0
	for i in frames_to_play:
		await frames(1)
		if not a.runner.airborne and not b.runner.airborne:
			deepest = maxf(deepest, -_clearance(a, b))
	return deepest


func test_the_thrust_connects_and_the_knuckle_ends_in_front_of_abarax() -> void:
	var run := _pair(2.6, [{"frames": 1, "press": [&"heavy"]}, {"frames": 120}])
	var abarax: Actor = run["abarax"]
	var knuckle: Actor = run["knuckle"]
	var taken: Array[int] = []
	abarax.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: taken.append(r.outcome))
	var deepest: float = await _deepest(abarax, knuckle, 110)
	assert_true(taken.has(O.HIT), "the thrust lands (%s)" % [taken])
	assert_true(knuckle.global_position.z > abarax.global_position.z + 0.5,
			"the Knuckle ends in front of him, on the side it came from (Knuckle z %.2f, Abarax z %.2f)" % [knuckle.global_position.z, abarax.global_position.z])
	assert_true(deepest <= SLACK, "their bodies were at most %.2f m inside each other (%.3f)" % [SLACK, deepest])


func test_abarax_palm_hook_stops_at_a_knuckle() -> void:
	var run := _pair(0.8, [{"frames": 120}], [], KNUCKLE_1)
	var abarax: Actor = run["abarax"]
	var knuckle: Actor = run["knuckle"]
	abarax.runner.start(Registry.fetch(&"moves", &"palm_hook") as MoveData)
	var deepest: float = await _deepest(abarax, knuckle, 90)
	assert_true(deepest <= SLACK, "his hook's lunge stops at the Knuckle (%.3f m inside)" % deepest)
	assert_true(knuckle.global_position.z > abarax.global_position.z, "and he is still in front of it")


func test_a_dash_step_into_a_knuckle_stops_at_it() -> void:
	# 1.4 m apart a free dash-step (1.3 m) would end 0.1 m from the Knuckle's centre, well inside its body: it must stop at it.
	var run := _pair(1.4, [{"frames": 60}], [{"frames": 1, "press": [&"dodge"], "move": Vector2(0, 1)}, {"frames": 60}], KNUCKLE_1)
	var abarax: Actor = run["abarax"]
	var knuckle: Actor = run["knuckle"]
	var deepest: float = await _deepest(abarax, knuckle, 40)
	assert_true(deepest <= SLACK, "a dash-step at a Knuckle stops at its body (%.3f m inside)" % deepest)
	assert_true(knuckle.global_position.z > abarax.global_position.z, "he did not step through it")
	assert_true(abarax.global_position.z > 0.3, "but he did step toward it (z %.2f)" % abarax.global_position.z)


func test_a_hop_over_the_sweep_whiffs_and_the_knuckle_slides_beneath() -> void:
	# The sweep's foot is live from its f40 to f60; a hop pressed 36 frames after it is airborne from its f2 to f28,
	# frames 38 to 64 of the sweep.
	var run := _pair(4.2, [{"frames": 1, "press": [&"gift"]}, {"frames": 150}],
			[{"frames": 36}, {"frames": 1, "press": [&"dodge"]}, {"frames": 150}], KNUCKLE_1)
	var abarax: Actor = run["abarax"]
	var knuckle: Actor = run["knuckle"]
	var taken: Array[int] = []
	abarax.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: taken.append(r.outcome))
	var hopped := [false]
	abarax.runner.move_started.connect(func(m: MoveData) -> void:
		if m.id == &"hop":
			hopped[0] = true)
	await frames(140)
	assert_true(hopped[0], "he hopped")
	assert_false(taken.is_empty(), "the sweep reached him")
	assert_true(taken.all(func(o: int) -> bool: return o == O.WHIFF), "and every blow of it came to nothing (%s)" % [taken])
	assert_eq(abarax.stats.hp, abarax.stats.max_hp, "he was not hurt")
	assert_true(knuckle.global_position.z < abarax.global_position.z - 0.7,
			"the Knuckle slid on beneath him and out the other side (Knuckle z %.2f, Abarax z %.2f)" % [knuckle.global_position.z, abarax.global_position.z])


func test_no_two_grounded_capsules_overlap_during_any_attack() -> void:
	# [the Knuckle's presses, Abarax's presses, the gap, the Knuckle's def]
	var cases := [
		[[{"frames": 1, "press": [&"palm"]}, {"frames": 25}, {"frames": 1, "press": [&"palm"]}, {"frames": 30}, {"frames": 1, "press": [&"palm"]}, {"frames": 120}], [], 0.9, KNUCKLE_2],
		[[{"frames": 1, "press": [&"heavy"]}, {"frames": 120}], [], 3.4, KNUCKLE_2],
		[[{"frames": 1, "press": [&"gift"]}, {"frames": 120}], [], 3.0, KNUCKLE_1],
		[[{"frames": 1, "press": [&"gift"]}, {"frames": 120}], [], 1.2, KNUCKLE_1],
		[[{"frames": 120}], [{"frames": 1, "press": [&"palm"]}, {"frames": 15}, {"frames": 1, "press": [&"palm"]}, {"frames": 20}, {"frames": 1, "press": [&"palm"]}, {"frames": 100}], 0.8, KNUCKLE_1],
	]
	for c: Array in cases:
		var run := _pair(c[2], c[0], c[1], c[3])
		var deepest: float = await _deepest(run["abarax"], run["knuckle"], 130)
		assert_true(deepest <= SLACK, "%s vs %s from %.1f m: at most %.2f m inside each other (%.3f)" % [c[0], c[1], c[2], SLACK, deepest])
		(run["abarax"] as Actor).get_parent().queue_free()
		await frames(1)


func test_the_dead_and_the_two_fighters_of_a_pair_are_not_kept_apart() -> void:
	var run := _pair(0.5, [{"frames": 10}], [{"frames": 10}], KNUCKLE_1)
	var abarax: Actor = run["abarax"]
	var knuckle: Actor = run["knuckle"]
	await frames(1)
	var forward := Vector3(0, 0, 1.0)
	var dt := 1.0 / 60.0
	assert_true(abarax.spacing.keep_apart(forward, dt).z < 0.0, "pressed into a live Knuckle, a step toward it becomes a step out")
	abarax.paired_with = knuckle
	knuckle.paired_with = abarax
	assert_vec_near(abarax.spacing.keep_apart(forward, dt), forward, 1e-9, "the lead of a pair goes by its own motion")
	assert_vec_near(knuckle.spacing.keep_apart(-forward, dt), -forward, 1e-9, "and so does its follower")
	abarax.paired_with = null
	knuckle.paired_with = null
	knuckle.dead = true
	assert_vec_near(abarax.spacing.keep_apart(forward, dt), forward, 1e-9, "a corpse is no wall")


# The deepest any two of `actors` are inside each other over `frames_to_play` frames, on frames neither is airborne.
func _deepest_of(actors: Array[Actor], frames_to_play: int) -> Array:
	var deepest := [0.0, ""]
	for f in frames_to_play:
		await frames(1)
		for i in actors.size():
			for j in range(i + 1, actors.size()):
				var a := actors[i]
				var b := actors[j]
				if a.runner.airborne or b.runner.airborne:
					continue
				var depth := -_clearance(a, b)
				if depth > deepest[0]:
					deepest = [depth, "frame %d, %s and %s" % [a.frame, a.name, b.name]]
	return deepest


# A Knuckle (tier I, HP to spare) at `at` facing `yaw`, pressing `steps`.
func _knuckle(arena: Node3D, at: Vector3, yaw: float, steps: Array, actor_name: String) -> Actor:
	var k := TestArena.spawn(arena, _tough(KNUCKLE_1), ScriptBrain.new(steps), at, actor_name)
	k.place(Transform3D(Basis(Vector3.UP, yaw), at))
	return k


func test_two_closing_bodies_and_a_third_never_overlap() -> void:
	var thrust := [{"frames": 1, "press": [&"heavy"]}, {"frames": 120}]
	# Head on: two thrusts at each other.
	var arena := TestArena.make(self)
	var a := _knuckle(arena, Vector3(-2.2, 0, 0), PI * 0.5, thrust, "A")
	var b := _knuckle(arena, Vector3(2.2, 0, 0), -PI * 0.5, thrust, "B")
	var head_on: Array = await _deepest_of([a, b] as Array[Actor], 110)
	assert_true(head_on[0] <= SLACK, "two thrusts head on: %.3f m inside each other (%s)" % head_on)
	arena.queue_free()
	await frames(1)
	# Three: two thrusts converging on Abarax from either side.
	arena = TestArena.make(self)
	var abarax := TestArena.spawn(arena, _tough(ABARAX), Brain.new(), Vector3.ZERO, "Abarax")
	a = _knuckle(arena, Vector3(-3.0, 0, 0.3), PI * 0.5, thrust, "A")
	b = _knuckle(arena, Vector3(3.0, 0, -0.3), -PI * 0.5, thrust, "B")
	var three: Array = await _deepest_of([abarax, a, b] as Array[Actor], 110)
	assert_true(three[0] <= SLACK, "two thrusts on Abarax from either side: %.3f m (%s)" % three)
	arena.queue_free()
	await frames(1)
	# Along a wall: a thrust down a wall into a Knuckle standing half in its path (the wall's slide must not carry it in).
	arena = TestArena.make(self)
	TestArena.wall(arena, Vector3(0, 1.0, -0.45), Vector3(12.0, 2.0, 0.3))
	abarax = TestArena.spawn(arena, _tough(ABARAX), Brain.new(), Vector3(-2.5, 0, 0.05), "Abarax")
	var stand := _knuckle(arena, Vector3(-0.3, 0, 0.62), PI * 0.5, [{"frames": 120}], "Standing")
	var thruster := _knuckle(arena, Vector3(3.0, 0, 0.05), -PI * 0.5, thrust, "Thruster")
	var wall: Array = await _deepest_of([abarax, stand, thruster] as Array[Actor], 110)
	assert_true(wall[0] <= SLACK, "a thrust along a wall into a body: %.3f m (%s)" % wall)


# How many of `frames_to_play` frames `actor`'s legs walk (its rig's locomotion speed over 0.5 m/s) while its body goes
# less than half that fast.
func _walking_in_place(actor: Actor, frames_to_play: int) -> int:
	var count := 0
	var last := actor.global_position
	for i in frames_to_play:
		await frames(1)
		var speed := Vector2(actor.global_position.x - last.x, actor.global_position.z - last.z).length() * 60.0
		last = actor.global_position
		if not actor.runner.busy() and actor._rig_speed > 0.5 and speed < actor._rig_speed * 0.5:
			count += 1
	return count


func test_legs_stop_with_a_body_that_is_blocked() -> void:
	var jog := [{"frames": 90, "move": Vector2(0, 1)}]
	var run := _pair(1.6, [{"frames": 90}], jog, KNUCKLE_1)  # Abarax jogs into a Knuckle standing in his way
	var into_body: int = await _walking_in_place(run["abarax"], 90)
	assert_eq(into_body, 0, "jogging into a body, his legs stop when he does")
	(run["abarax"] as Actor).get_parent().queue_free()
	await frames(1)
	var arena := TestArena.make(self)
	TestArena.wall(arena, Vector3(0, 1.0, 1.5), Vector3(4.0, 2.0, 0.3))
	var abarax := TestArena.spawn(arena, _tough(ABARAX), ScriptBrain.new(jog), Vector3.ZERO, "Abarax")
	var into_wall: int = await _walking_in_place(abarax, 90)
	assert_eq(into_wall, 0, "and jogging into a wall")
	assert_true(abarax.global_position.z > 0.9, "he did get there (z %.2f)" % abarax.global_position.z)
