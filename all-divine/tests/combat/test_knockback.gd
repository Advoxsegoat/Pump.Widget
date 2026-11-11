extends TestCase
## Knockback: a blow that lands shoves its target along the blow by the profile's `knockback` (m/s), which dies
## away at the tuning's `knockback_decay` a second (10 for Abarax), so a push of v travels v / 10 metres in all.
## The cross has a knockback of 1.5 (0.15 m) and lands on frame 15 when started before the first frame, with 4 frames
## of hit-stop (16 to 19). The shove goes through move_and_slide: a wall stops it.


# The cross, started before the first frame, against b one metre in front (so it lands on frame 15).
func _cross_duel(gap := 1.0) -> Dictionary:
	var run := Duel.make(self, [{"frames": 80}], [{"frames": 400}], gap)
	(run["a"] as Actor).runner.start(Registry.fetch(&"moves", &"palm_cross") as MoveData)
	return run


# A thin wall across the arena, its near face at z = `face`, on the `world` layer.
func _wall(run: Dictionary, face: float) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	wall.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 3.0, 0.2)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, 1.5, face + 0.1)
	wall.add_child(shape)
	(run["arena"] as Node).add_child(wall)


func test_knockback_moves_the_target_away_and_fades() -> void:
	var run := _cross_duel()
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var hit_at := []
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: hit_at.append([a.frame, r.outcome]))
	await Duel.play_to(self, a, 15)
	assert_eq(hit_at, [[15, HitResult.Outcome.HIT]], "the cross lands on frame 15")
	assert_vec_near(b.global_position, Vector3(0, 0, 1), 1e-4, "and the target has not moved yet")
	await Duel.play_to(self, a, 75)  # a second on
	var moved := b.global_position - Vector3(0, 0, 1)
	assert_near(moved.z, 0.15, 0.01, "1.5 m/s at a decay of 10 carries it 0.15 m, away from the attacker (+Z)")
	assert_near(moved.x, 0.0, 1e-4, "straight along the blow")
	var settled := b.global_position
	await Duel.play_to(self, a, 135)
	assert_vec_near(b.global_position, settled, 1e-4, "and then it is still")
	assert_vec_near(b.velocity, Vector3.ZERO, 1e-3)


func test_the_push_waits_out_the_hit_stop() -> void:
	var run := _cross_duel()
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var seen := {}
	while a.frame < 26:
		await frames(1)
		seen[a.frame] = b.global_position.z
	assert_near(seen[15], 1.0, 1e-4, "landed")
	for f in [16, 17, 18, 19]:
		assert_near(seen[f], 1.0, 1e-4, "frozen: not moved on frame %d" % f)
	assert_true(seen[20] > 1.0 + 1e-3, "moving on the first frame after the freeze")
	assert_true(seen[26] > seen[20], "and going")


func test_the_push_is_the_same_whatever_the_frame_rate() -> void:
	# The frame moves by the average of the decaying velocity over the frame, so the total is v / k at any rate.
	var run := Duel.make(self)
	var b: Actor = run["b"]
	b.push(Vector3(0, 0, 3.0))
	for i in 120:
		await frames(1)
	assert_near(b.global_position.z - 1.0, 0.3, 0.002, "3 m/s at a decay of 10")
	var more := Duel.make(self, [], [], 8.0)
	var c: Actor = more["b"]
	c.push(Vector3(0, 7.0, 3.0))
	c.push(Vector3(0, 0, 1.0))
	for i in 120:
		await frames(1)
	assert_near(c.global_position.z - 8.0, 0.4, 0.002, "pushes add up, and only the ground part counts")
	assert_near(c.global_position.y, 0.0, 1e-3, "and it stays on the floor")


func test_a_whiff_pushes_nothing() -> void:
	# b steps in toward a on frame 5 (the fixture dodge), invulnerable while the jab's hand passes through it. It ends
	# where it would have with no jab at all.
	var calm := Duel.make(self, [{"frames": 80}], [{"frames": 80}], 1.6)
	await Duel.play_to(self, calm["b"], 5)
	(calm["b"] as Actor).runner.start(Duel.untouchable_dash(calm["b"]))
	await Duel.play_to(self, calm["a"], 60)
	var expected: Vector3 = (calm["b"] as Actor).global_position
	(calm["arena"] as Node).free()
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 80}], [{"frames": 80}], 1.6)
	await Duel.play_to(self, run["b"], 5)
	(run["b"] as Actor).runner.start(Duel.untouchable_dash(run["b"]))
	var outcomes := []
	(run["a"] as Actor).hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(r.outcome))
	await Duel.play_to(self, run["a"], 60)
	assert_true(outcomes.has(HitResult.Outcome.WHIFF), "the hand reached the dodging body")
	assert_eq(outcomes.filter(func(o: int) -> bool: return o != HitResult.Outcome.WHIFF), [], "and nothing landed")
	assert_vec_near((run["b"] as Actor).global_position, expected, 1e-4, "so the jab did not move it")


func test_knockback_into_a_wall_does_not_pass_it() -> void:
	# A wall 0.5 m behind b (its near face at z = 1.5); b's capsule is 0.35 m in radius, so its centre stops at 1.15.
	# The blow's push is made a violent 25 m/s, far more than the thin wall's 0.2 m a frame, which a body moved
	# without a shape cast would pass through.
	var run := _cross_duel()
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	_wall(run, 1.5)
	var cross := (Registry.fetch(&"moves", &"palm_cross") as MoveData).duplicate() as MoveData
	var palm := (cross.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	palm.knockback = 25.0
	cross.hits = {&"palm": palm}
	a.runner.start(cross)
	var deepest := 0.0
	while a.frame < 100:
		await frames(1)
		deepest = maxf(deepest, b.global_position.z)
	assert_true(deepest > 1.1, "the blow pushed it up to the wall: %s" % deepest)
	assert_true(deepest <= 1.5 - 0.35 + 0.005, "and not into it: the centre got to %s, the wall's face less the radius is 1.15" % deepest)
	assert_vec_near(b.velocity, Vector3.ZERO, 1e-3)
	assert_true(b.is_on_floor(), "it is still on the floor")


func test_a_push_along_a_wall_slides_on() -> void:
	# Pushed into the wall at an angle, b keeps the part of the push along it.
	var run := Duel.make(self, [], [{"frames": 400}], 1.0)
	var b: Actor = run["b"]
	_wall(run, 1.5)
	b.push(Vector3(3.0, 0.0, 3.0))
	for i in 90:
		await frames(1)
	assert_true(b.global_position.z <= 1.15 + 0.005, "not through the wall: %s" % b.global_position)
	assert_true(b.global_position.x > 0.1, "but along it: %s" % b.global_position)
