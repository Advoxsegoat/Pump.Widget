extends TestCase
## The walking rule the checker promises and the Director's brain will keep: release the push at a distance from the
## mark, and the body comes to rest within 0.12 m of it in the frames the rule says. Held against real bodies.

const METRES: Array[float] = [1.0, 3.3, 5.0, 8.0]
const MAX_FRAMES := 4000


# Pushes toward `to` and lets go at `release` metres from it, as the Director's brain does.
class WalkBrain extends Brain:
	var to := Vector3.ZERO
	var release := 0.0
	var push := 1.0
	var released := false

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		var remaining := Vector2(to.x - actor.global_position.x, to.z - actor.global_position.z)
		if remaining.length() <= release:
			released = true
		if not released:
			intent.move = remaining.normalized() * push
		return intent


# Walks `def`'s actor `metres` along `direction` at `pace`; returns {frames, error} where frames is the first physics
# frame the body is at rest after letting go and error is how far from the mark it rests.
func _walk(def: ActorDef, pace: ActorBeat.Pace, metres: float, direction: Vector2) -> Dictionary:
	var arena := TestArena.make(self)
	if metres > 12.0:
		_wide_floor(arena)
	var brain := WalkBrain.new()
	var dir := Vector3(direction.x, 0.0, direction.y).normalized()
	brain.to = dir * metres
	brain.push = StoryWalk.push_of(pace)
	brain.release = StoryWalk.release_distance(def.locomotion, pace, metres)
	var actor := TestArena.spawn(arena, def, brain, Vector3.ZERO)
	await frames(1)
	var frame := 0
	var rested := -1
	while frame < MAX_FRAMES:
		await frames(1)
		frame += 1
		if brain.released and actor.locomotion.speed == 0.0:
			rested = frame
			break
	var error := Vector2(actor.global_position.x - brain.to.x, actor.global_position.z - brain.to.z).length()
	arena.free()
	return {frames = rested, error = error}


func test_a_body_comes_to_rest_at_the_mark_in_the_frames_the_rule_says() -> void:
	for id in [&"abarax", &"knuckle_1"]:
		var def := Registry.fetch(&"actors", id) as ActorDef
		for pace in [ActorBeat.Pace.WALK, ActorBeat.Pace.JOG]:
			for metres in METRES:
				for direction in [Vector2(1, 0), Vector2(3, 4)]:
					var got: Dictionary = await _walk(def, pace, metres, direction)
					var said := StoryWalk.frames(def.locomotion, pace, metres)
					var where := "%s %s %.1f m %s: rested after %d, rule says %d, %.3f m off" % [id, ActorBeat.Pace.keys()[pace], metres, direction, got.frames, said, got.error]
					assert_true(got.frames > 0, where)
					assert_true(got.error <= StoryWalk.ARRIVAL, where)
					assert_true(got.frames <= said, "no more frames than the rule says: " + where)
					assert_true(got.frames >= said - 5, "no fewer than 5 fewer: " + where)


func test_the_release_is_before_the_mark_and_the_frames_grow_with_the_length() -> void:
	var def := Registry.fetch(&"actors", &"knuckle_1") as ActorDef
	for pace in [ActorBeat.Pace.WALK, ActorBeat.Pace.JOG]:
		var last := 0
		for metres in METRES:
			var release := StoryWalk.release_distance(def.locomotion, pace, metres)
			assert_true(release >= 0.0 and release < metres, "%s %.1f m: release %.3f" % [ActorBeat.Pace.keys()[pace], metres, release])
			var n := StoryWalk.frames(def.locomotion, pace, metres)
			assert_true(n > last, "longer walks take longer")
			last = n
	# a jog coasts about 0.6 m; a walk about 2 cm
	assert_true(StoryWalk.release_distance(def.locomotion, ActorBeat.Pace.JOG, 8.0) > 0.5)
	assert_true(StoryWalk.release_distance(def.locomotion, ActorBeat.Pace.WALK, 8.0) < 0.05)


# A floor 400 m across under the arena's own, for walks longer than it is.
func _wide_floor(arena: Node3D) -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD | Layers.IK_SURFACE
	ground.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	arena.add_child(ground)


func test_a_long_walk_has_a_number_that_grows_with_the_distance() -> void:
	var def := Registry.fetch(&"actors", &"knuckle_1") as ActorDef
	var tuning := def.locomotion
	for pace in [ActorBeat.Pace.WALK, ActorBeat.Pace.JOG]:
		var steady := Locomotion.new(tuning).target_speed(StoryWalk.push_of(pace), false)
		var base := StoryWalk.frames(tuning, pace, 8.0)
		var last := 0
		for metres: float in [32.0, 45.0, 100.0, 200.0, 300.0, 500.0]:
			var said := StoryWalk.frames(tuning, pace, metres)
			var expected: float = base + (metres - 8.0) / steady * 60.0
			var where := "%s %.0f m: %d frames, expected about %.1f" % [ActorBeat.Pace.keys()[pace], metres, said, expected]
			assert_true(said > 0, where)
			assert_true(absf(float(said) - expected) <= 2.0, where)
			assert_true(said >= last, "never falls with distance: " + where)
			last = said
			var release := StoryWalk.release_distance(tuning, pace, metres)
			assert_near(release, StoryWalk.release_distance(tuning, pace, 8.0), 0.0001, "a long walk releases as the steady one does: " + where)


func test_a_real_body_walks_32_m_and_jogs_60_m_to_rest_on_the_promised_frame() -> void:
	var def := Registry.fetch(&"actors", &"knuckle_1") as ActorDef
	for run in [[ActorBeat.Pace.WALK, 32.0], [ActorBeat.Pace.JOG, 60.0]]:
		var got: Dictionary = await _walk(def, run[0], run[1], Vector2(1, 0))
		var said := StoryWalk.frames(def.locomotion, run[0], run[1])
		var where := "%s %.0f m: rested after %d, rule says %d, %.3f m off" % [ActorBeat.Pace.keys()[run[0]], run[1], got.frames, said, got.error]
		assert_true(got.frames > 0, where)
		assert_true(got.error <= StoryWalk.ARRIVAL, where)
		assert_true(absf(float(got.frames - said)) <= 2.0, where)


# A tuning whose body never gets up to speed: no walk of it has a time.
func _stalled() -> LocomotionTuning:
	var tuning := (Registry.fetch(&"actors", &"knuckle_1") as ActorDef).locomotion.duplicate() as LocomotionTuning
	tuning.accel = 0.001
	return tuning


func test_a_walk_that_cannot_be_solved_has_no_number_and_is_not_zero() -> void:
	var tuning := _stalled()
	assert_eq(StoryWalk.frames(tuning, ActorBeat.Pace.WALK, 1.0), -1)
	assert_eq(StoryWalk.frames(tuning, ActorBeat.Pace.JOG, 300.0), -1, "a long walk of it as well")
