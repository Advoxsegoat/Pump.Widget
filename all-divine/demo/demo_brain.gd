class_name DemoBrain
extends Brain
## The preview demo's enemy mind for the Knuckles: a stand-in that Task 13's real enemy brain replaces.
##
## It idles until the player is alive and within AGGRO_RANGE, then faces him and walks to him, and attacks by how far
## he is, by pressing the actions the Knuckle's moveset maps to its moves (palm: the jab, and in its cancel window the
## cross and the hook; heavy: the thrust; gift: the sweep; interact: the grab; dodge: the feint):
##   within CLOSE_RANGE   a jab, sometimes chained into the cross and the hook, or the grab, or the sweep;
##   FAR_NEAR to FAR_FAR  the thrust or the sweep, which both travel;
##   between              it walks closer.
## Each tier waits INTERVALS seconds between attacks (with jitter), and the second and third sometimes feint first and
## follow it with the thrust or a jab. Only one Knuckle attacks at a time: before it starts it asks the director for
## the single attack token, and gives it back when its attack is over.
##
## It does nothing while the player is dead or paired, or while it is itself reacting to a blow or paired. All of its
## choices come from one seeded RandomNumberGenerator, so a run is the same every time.

## The player counts as in sight within this many metres (and is let go of past AGGRO_LOSE).
const AGGRO_RANGE := 12.0
const AGGRO_LOSE := 16.0
## An attack that does not travel is thrown within this many metres; the Knuckle walks in until it is this close.
const CLOSE_RANGE := 1.8
const WALK_TO := 1.5
## A thrust or a sweep is thrown from between these distances.
const FAR_NEAR := 3.0
const FAR_FAR := 5.0
## Seconds between attacks, by tier (I, II, III), and how far each wait strays (a fraction either way).
const INTERVALS: Array[float] = [2.2, 1.8, 1.4]
const JITTER := 0.25
## The chance a tier (I, II, III) feints before an attack.
const FEINT_CHANCE: Array[float] = [0.0, 0.25, 0.35]
## How hard the stick is pushed while it walks in: a walk.
const WALK_PUSH := 0.6
## The first attack comes this fraction of the tier's interval after the Knuckle wakes (so the yard opens quickly).
const FIRST_WAIT := Vector2(0.2, 0.5)

## Who he fights, and who hands out the attack token (null: no token is needed).
var target: Actor
var director: DemoDirector

var _rng := RandomNumberGenerator.new()
var _tier := 1
var _awake := false
var _wait := -1.0  # seconds until the next attack; -1 until the first think
var _swinging := false  # an attack was started and is not over
var _followups: Array[StringName] = []  # presses still to make, each when the open cancel window takes it


func _init(foe: Actor = null, boss: DemoDirector = null, seed_value := 1) -> void:
	target = foe
	director = boss
	_rng.seed = seed_value


func think(actor: Actor, delta: float) -> Intent:
	var intent := Intent.new()
	if _wait < 0.0:
		_tier = _tier_of(actor)
		_wait = INTERVALS[_tier - 1] * _rng.randf_range(FIRST_WAIT.x, FIRST_WAIT.y)
	if target == null or not is_instance_valid(target) or target.dead or target.paired_with != null:
		_stand_down(actor)
		return intent
	if actor.dead or actor.paired_with != null or _reacting(actor):
		_stand_down(actor)
		return intent
	var flat := Vector2(target.global_position.x - actor.global_position.x, target.global_position.z - actor.global_position.z)
	var distance := flat.length()
	if not _awake:
		_awake = distance <= AGGRO_RANGE
	elif distance > AGGRO_LOSE:
		_awake = false
	if not _awake:
		return intent
	intent.face_target = target.global_position
	intent.look_target = target.head_point()
	intent.aim_target = target.global_position
	if _swinging:
		_follow_through(actor, intent)
		return intent
	_wait -= delta
	if _wait > 0.0 or not _start_attack(actor, intent, distance):
		if distance > WALK_TO and flat.length() > 0.0:
			intent.move = flat.normalized() * WALK_PUSH
	return intent


# Which tier the Knuckle is, from its def's id (knuckle_1 to knuckle_3).
func _tier_of(actor: Actor) -> int:
	return clampi(String(actor.def.id).trim_prefix("knuckle_").to_int(), 1, 3)


# Whether the Knuckle is playing a reaction (a flinch, a stagger, a broken posture, a parried blow).
func _reacting(actor: Actor) -> bool:
	return actor.runner.current != null and actor.runner.current.kind == MoveData.Kind.REACTION


# The attack is off: it gives the token back, forgets what it meant to press next and waits a full interval.
func _stand_down(actor: Actor) -> void:
	if _swinging:
		_finish(actor)


func _finish(actor: Actor) -> void:
	_swinging = false
	_followups.clear()
	_wait = INTERVALS[_tier - 1] * _rng.randf_range(1.0 - JITTER, 1.0 + JITTER)
	if director != null:
		director.release_attack(actor)


# Picks an attack for `distance` and presses its first action; false when there is none to pick (too far to hit, too
# near to throw a sweep, or the token is out).
func _start_attack(actor: Actor, intent: Intent, distance: float) -> bool:
	var close := distance <= CLOSE_RANGE
	var far := distance >= FAR_NEAR and distance <= FAR_FAR
	if not close and not far:
		return false
	if director != null and not director.request_attack(actor):
		return false
	var chain: Array[StringName] = []
	var first: StringName
	if close:
		var roll := _rng.randf()
		if roll < 0.6:
			first = &"palm"
			var more := _rng.randf()
			if more < 0.6:
				chain.append(&"palm")
			if more < 0.25:
				chain.append(&"palm")
		elif roll < 0.8:
			first = &"interact"
		else:
			first = &"gift"
	else:
		first = &"heavy" if _rng.randf() < 0.55 else &"gift"
	if _rng.randf() < FEINT_CHANCE[_tier - 1]:
		# Feint, then the real thing out of the feint's cancel window: the thrust, or a jab up close.
		chain.clear()
		if first != &"interact":
			chain.append(&"heavy" if far else &"palm")
		first = &"dodge"
	_followups = chain
	_swinging = true
	intent.pressed.append(first)
	return true


# Between the first press and the end of the attack: presses the next action of the chain when the cancel window takes
# it, and gives the token back once the Knuckle is free again.
func _follow_through(actor: Actor, intent: Intent) -> void:
	if actor.frozen > 0:
		return  # hit-stop: a press made now is only buffered, so the move has not started or ended
	if not actor.runner.busy():
		# Either the attack is over, or a press the Knuckle could not pay for never started it.
		_finish(actor)
		return
	if not _followups.is_empty() and actor.runner.window.has(_followups[0]):
		intent.pressed.append(_followups.pop_front())
