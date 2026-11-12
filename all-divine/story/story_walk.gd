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
## Walks longer than this are this walk with a longer steady stretch.
const REFERENCE := 8.0

static var _cache := {}


## The stick's push for a gait.
static func push_of(pace: ActorBeat.Pace) -> float:
	return WALK_PUSH if pace == ActorBeat.Pace.WALK else JOG_PUSH


## The distance from the mark at which the push is let go so that a walk of `metres` comes to rest as near the mark as
## it can (within ARRIVAL, for a walk long enough to reach its speed or short).
static func release_distance(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> float:
	return _solve(tuning, pace, metres).release


## The frames a walk of `metres` takes, from rest, until the body is at rest at its mark; -1 if it cannot be worked out.
static func frames(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> int:
	var solved := _solve(tuning, pace, metres)
	return solved.frames + LATENCY_FRAMES if solved.frames >= 0 else -1


## The seconds the same walk takes.
static func seconds(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> float:
	return float(frames(tuning, pace, metres)) / float(Engine.physics_ticks_per_second)


# {release, frames, error, worst} for the walk. A walk longer than REFERENCE metres is the reference walk with the steady
# stretch lengthened: once the body is at its steady speed, the same start and the same stop are joined by metres at
# that speed, so the answer is arithmetic and nothing is capped. frames is -1 for a walk that cannot be solved.
static func _solve(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float) -> Dictionary:
	var v := Locomotion.new(tuning).target_speed(push_of(pace), false)
	var reference := maxf(REFERENCE, 6.0 * (v * v / (2.0 * tuning.accel) + v * v / (2.0 * tuning.decel)))
	if metres > reference:
		var base := _solve(tuning, pace, reference)
		if base.frames < 0:
			return base
		var extra := (metres - reference) / v * float(Engine.physics_ticks_per_second)
		return {release = base.release, frames = base.frames + roundi(extra), error = base.error, worst = base.worst}
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [tuning.walk_speed, tuning.jog_speed, tuning.sprint_speed, tuning.accel, tuning.decel,
			tuning.walk_threshold, pace, snappedf(metres, 0.0001), Engine.physics_ticks_per_second]
	if _cache.has(key):
		return _cache[key]
	var most := minf(metres, v * v / (2.0 * tuning.decel) + 0.1)
	var best := {release = 0.0, frames = -1, error = INF, worst = INF}
	var release := 0.0
	while release <= most + 0.0001:
		# a release that lands the body well only by a hair of position is not trusted: it must land as well a little
		# either side of itself (a body's position is a float32 and the frame it releases on could flip)
		var run := _run(tuning, pace, metres, release)
		var worst := maxf(absf(_run(tuning, pace, metres, release - ROBUST).error), absf(_run(tuning, pace, metres, release + ROBUST).error))
		worst = maxf(worst, absf(run.error))
		if run.frames >= 0 and worst < best.worst - 0.0001:
			best = {release = release, frames = run.frames, error = run.error, worst = worst}
		release += STEP
	_cache[key] = best
	return best


# One walk along a line: {frames until at rest, signed distance past the mark when at rest}; frames is -1 if the body is
# not at rest by the time it should be (several times the walk at its speed, and a second more).
static func _run(tuning: LocomotionTuning, pace: ActorBeat.Pace, metres: float, release: float) -> Dictionary:
	var loco := Locomotion.new(tuning)
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var speed := maxf(loco.target_speed(push_of(pace), false), 0.001)
	var limit := ceili((metres / speed + 4.0) * 3.0 * float(Engine.physics_ticks_per_second))
	var at := 0.0
	var released := false
	for tick in limit:
		if metres - at <= release:
			released = true
		var velocity := loco.tick(Vector2.ZERO if released else Vector2(push_of(pace), 0.0), false, delta)
		at += velocity.x * delta
		if released and loco.speed == 0.0:
			return {frames = tick + 1, error = at - metres}
	return {frames = -1, error = INF}
