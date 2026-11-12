class_name StoryWalk
extends RefCounted
## How a scene's walk is played, in one place, so that what the shot checker promises is what the Director plays.
##
## A walk pushes the stick toward the mark at the gait's push and lets go when the body is `release_distance` from
## it; the body then coasts to rest (Locomotion slows by its decel), and rests within ARRIVAL of the mark. The jog
## coasts more than half a metre, so letting go on arrival would rest it well past the mark; the walk coasts a few
## centimetres. `frames` is how long that takes, counted until the body is at rest, which is when the actor's next
## beat can begin. Both numbers are found by running Locomotion itself, tick by tick, along a straight line.

## The Director's rule: a body is at its mark within this many metres.
const ARRIVAL := 0.12
## A walk is pushed at this fraction of the stick: a walk is 0.45 (0.9 m/s for the Knuckle), a jog 1.0.
const WALK_PUSH := 0.45
const JOG_PUSH := 1.0
## Frames the actor takes between the brain's decision and the body's speed changing, measured on real bodies
## (tests/story/test_story_walk.gd).
const LATENCY_FRAMES := 0
const STEP := 0.005
## How far either side of a release the walk must still land well.
const ROBUST := 0.004
const MAX_TICKS := 2000

static var _cache := {}


## The stick's push for a gait.
static func push_of(pace: ActorBeat.Pace) -> float:
	return WALK_PUSH if pace == ActorBeat.Pace.WALK else JOG_PUSH


## The distance from the mark at which the push is let go so that a walk of `metres` comes to rest as near the mark as
## it can (within ARRIVAL, for a walk long enough to reach its speed or short).
static func release_distance(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> float:
	return _solve(tuning, pace, metres).release


## The frames a walk of `metres` takes, from rest, until the body is at rest at its mark.
static func frames(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> int:
	return _solve(tuning, pace, metres).frames + LATENCY_FRAMES


## The seconds the same walk takes.
static func seconds(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> float:
	return float(frames(tuning, pace, metres)) / float(Engine.physics_ticks_per_second)


# {release, frames, error, worst} for the walk, found by trying releases up to the speed's coasting distance.
static func _solve(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> Dictionary:
	var key := "%s|%s|%s|%s|%s|%s" % [tuning.walk_speed, tuning.jog_speed, tuning.accel, tuning.decel, pace, snappedf(metres, 0.0001)]
	if _cache.has(key):
		return _cache[key]
	var v := Locomotion.new(tuning).target_speed(push_of(pace), false)
	var most := minf(metres, v * v / (2.0 * tuning.decel) + 0.1)
	var best := {release = 0.0, frames = 0, error = INF, worst = INF}
	var release := 0.0
	while release <= most + 0.0001:
		# a release that lands the body well only by a hair of position is not trusted: it must land as well a little
		# either side of itself (a body's position is a float32 and the frame it releases on could flip)
		var run := _run(tuning, pace, metres, release)
		var worst := maxf(absf(_run(tuning, pace, metres, release - ROBUST).error), absf(_run(tuning, pace, metres, release + ROBUST).error))
		worst = maxf(worst, absf(run.error))
		if worst < best.worst - 0.0001:
			best = {release = release, frames = run.frames, error = run.error, worst = worst}
		release += STEP
	_cache[key] = best
	return best


# One walk along a line: {frames until at rest, signed distance past the mark when at rest}.
static func _run(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float, release: float) -> Dictionary:
	var loco := Locomotion.new(tuning)
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var at := 0.0
	var released := false
	for tick in MAX_TICKS:
		if metres - at <= release:
			released = true
		var velocity := loco.tick(Vector2.ZERO if released else Vector2(push_of(pace), 0.0), false, delta)
		at += velocity.x * delta
		if released and loco.speed == 0.0:
			return {frames = tick + 1, error = at - metres}
	return {frames = MAX_TICKS, error = INF}
