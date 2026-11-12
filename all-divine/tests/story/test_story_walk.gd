extends TestCase
## The walking rule the checker promises and the Director's brain will keep: release the push at a distance from the
## mark, and the body comes to rest within 0.12 m of it in the frames the rule says. Held against real bodies.

const METRES: Array[float] = [1.0, 3.3, 5.0, 8.0]
const MAX_FRAMES := 900


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
