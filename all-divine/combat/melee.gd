extends Node
## Autoload "Melee": where every hit of a physics frame is judged, once, after every actor has moved.
##
## Actors scan their hitboxes in their own _physics_process and post what they find here (post). Were a hit
## applied at once, its result would depend on which actor's script ran first: in a trade, whoever ran first
## would flinch the other before the other's hand was looked for. So nothing is applied while the actors run.
## Instead, two things happen around them:
##   - the child node Snapshot runs before any actor (process_physics_priority SNAPSHOT_PRIORITY) and takes
##     Defense.of every actor in the group `actors` (Actor.GROUP; actors join it when ready)
##   - Melee itself runs after every actor (process_physics_priority PRIORITY): it judges every posted hit
##     against those snapshots (Combat.resolve, with the target's CombatTuning), then applies them, target by
##     target (see below), and tells each attacker what its blow came to (hit_landed). A hit that came to
##     nothing (a WHIFF) is handed back to the attacker's scanner (HitScanner.forget), so the same swing may
##     still strike that body on a later tick: a body's iframes ending inside a long swing do not spare it
## So every hit of a frame is judged against the defenders as they stood when the frame began, and in a trade
## each side gets the result of the other's blow: both land. (The hurtboxes the hits were found on stood there
## too: see HitScanner.)
##
## All the blows a frame lands on one body are taken together (Actor.apply_hits), so that what the body ends up
## doing does not depend on which attacker's script ran first either: every blow's numbers come off and every
## blow kicks the body, and then one thing comes of them all, started once: the death, if together they emptied
## its HP, or else the strongest reaction among them (HitIntake.REACTIONS: a stagger over a flinch, a flinch over
## a guard_hit, and so on). Two blows that would each kill it are one death that both dealt, and each attacker
## hears its blow landed. A body that died since the frame began (by something other than this frame's blows)
## takes nothing: its blows come to a WHIFF, on both sides.
##
## A blow that is turned back (TURNED_BACK: PARRIED, or CAUGHT) also does something to its attacker: the attacker
## recoils and loses the result's attacker_posture_damage. That too is taken with everything else that frame did to
## the attacker's body, in the same one call (its apply_hits, as `turned`), so a body that is struck and has its own
## blow turned back on one frame, or has two of its blows turned back, still takes them all at once, in any order.
##
## A blow that was evaded (EVADED) is spent: it is not handed back to the scanner (so the same swing cannot land
## on the body later, when the window has closed), nobody freezes, nobody is pushed and no grab pair starts. Its target
## and its attacker both hear of it (got_hit, hit_landed), and the target's runner notes that it evaded (HitIntake.take).
##
## A blow that landed also has weight (_weigh): both fighters freeze for the profile's `hitstop_frames` and the
## target is pushed along the blow by its `knockback`. A trade freezes both for the longer of the two blows'
## frames, not their sum, since a freeze that is on is only ever lengthened (Actor.freeze).
##
## Melee also keeps paired moves (finishers, grabs) in step, since it runs after every actor has moved. A pair that
## began this frame (Actor.start_paired, begin_pair) has both its moves started here, after the blows; then every
## pair in play aligns its two fighters and, once the follower's move has ended, is finished (see Pairing). A grab that takes
## hold (GRABBED) starts its attacker's grab pair here and comes to nothing more; an attacker without one has it taken
## as a HIT that staggers. A pair's own blows (HitEvent.paired, the lead's pair_hit marks) are posted like any other
## but not judged: each lands on the follower as a HIT with no reaction (Combat.pair_hit). Any other blow on a body
## that is paired, even one that was not when the frame began (a grab took hold this frame), comes to nothing.

## Melee's place in each physics frame: after every actor (which run at the default, 0).
const PRIORITY := 100
## The outcomes that stop both fighters for the blow's hit-stop (Actor.freeze) and shove the target
## (Actor.push): a blow that landed, was guarded, broke the guard, was turned back or was caught. A WHIFF touched
## nothing and an EVADED blow was avoided, so neither has weight; a grab that takes hold is another thing (a paired
## move, not a blow).
const FREEZES: Array[HitResult.Outcome] = [HitResult.Outcome.HIT, HitResult.Outcome.GUARDED,
		HitResult.Outcome.GUARD_BREAK, HitResult.Outcome.PARRIED, HitResult.Outcome.CAUGHT]
## The outcomes that turn a blow back on its attacker, who then takes attacker_posture_damage and recoils.
const TURNED_BACK: Array[HitResult.Outcome] = [HitResult.Outcome.PARRIED, HitResult.Outcome.CAUGHT]
## The snapshot's: before any actor moves.
const SNAPSHOT_PRIORITY := -100


# Takes a Defense of every actor before any of them moves in a frame.
class Snapshot extends Node:
	var defenses := {}  # Actor -> its Defense at the start of this frame

	func _physics_process(_delta: float) -> void:
		defenses.clear()
		for node in get_tree().get_nodes_in_group(Actor.GROUP):
			var actor := node as Actor
			if actor != null:
				defenses[actor] = Defense.of(actor)


var _snapshot: Snapshot
var _posted: Array[HitEvent] = []
var _pairs: Array[Pairing] = []  # the paired moves in play
var _beginning: Array[Pairing] = []  # those begun this frame, whose moves have not started yet


func _ready() -> void:
	process_physics_priority = PRIORITY
	_snapshot = Snapshot.new()
	_snapshot.name = &"Snapshot"
	_snapshot.process_physics_priority = SNAPSHOT_PRIORITY
	add_child(_snapshot)


## Records `event` to be judged and applied once every actor has moved this frame.
func post(event: HitEvent) -> void:
	_posted.append(event)


## Takes on `pairing`, a paired move begun this frame (Actor.start_paired): its moves start once every actor has
## moved, and it is played from then on until it is over.
func begin_pair(pairing: Pairing) -> void:
	_beginning.append(pairing)


## Ends every paired move `actor` is in, at once (Pairing.abort), before it is taken out of the game; returns the fighters
## on the other side of them that are still here.
func end_pairs_of(actor: Actor) -> Array[Actor]:
	var others: Array[Actor] = []
	for list: Array in [_pairs, _beginning]:
		for pairing: Pairing in list.duplicate():
			if pairing.lead != actor and pairing.follower != actor:
				continue
			var other: Variant = pairing.follower if pairing.lead == actor else pairing.lead
			if is_instance_valid(other):
				others.append(other as Actor)
			pairing.abort()
			list.erase(pairing)
	return others


func _physics_process(_delta: float) -> void:
	if not _posted.is_empty():
		_apply_posted()
	for pairing in _beginning:
		pairing.start()
		_pairs.append(pairing)
	_beginning.clear()
	for pairing in _pairs.duplicate():
		if pairing.tick():
			pairing.finish()
			_pairs.erase(pairing)


# Judges and applies every blow posted this frame (see the top of this file).
func _apply_posted() -> void:
	var events := _posted
	_posted = []
	var results: Array[HitResult] = []
	for i in events.size():
		var r := _judge(events[i])
		if r != null and events[i].target.dead:
			r = HitResult.new()  # it died since the frame began: the blow comes to nothing
		results.append(r)
	# Every grab that took hold starts its pair first, so that whatever order the blows came in, no other blow lands
	# on a body paired this frame.
	for i in events.size():
		if results[i] != null and results[i].outcome == HitResult.Outcome.GRABBED and _grab(events[i]):
			results[i] = null  # the pair takes it from here
	# body -> [the indices of the blows it took, those of its own blows turned back], the bodies in the order met
	var bodies := {}
	for i in events.size():
		var r := results[i]
		if r == null:
			continue
		if not events[i].paired and events[i].target.paired_with != null:
			r = HitResult.new()  # no one else's blow lands on a paired body
			results[i] = r
		_note(bodies, events[i].target, 0, i)
		if TURNED_BACK.has(r.outcome):
			_note(bodies, events[i].attacker, 1, i)
	for body: Actor in bodies:
		var taken: Array[HitEvent] = []
		var came_to: Array[HitResult] = []
		var turned: Array[HitEvent] = []
		var turned_to: Array[HitResult] = []
		for i: int in bodies[body][0]:
			if results[i].outcome == HitResult.Outcome.WHIFF:
				events[i].attacker.scanner.forget(events[i])
			taken.append(events[i])
			came_to.append(results[i])
		for i: int in bodies[body][1]:
			turned.append(events[i])
			turned_to.append(results[i])
		body.apply_hits(taken, came_to, turned, turned_to)
		for i: int in bodies[body][0]:
			_weigh(events[i], results[i])
			events[i].attacker.hit_landed.emit(results[i], events[i])


# Adds blow `i` to `body`'s list `which` in `bodies` (0: the blows it took, 1: its own turned back).
static func _note(bodies: Dictionary, body: Actor, which: int, i: int) -> void:
	if not bodies.has(body):
		bodies[body] = [[], []]
	(bodies[body][which] as Array).append(i)


# Gives the blow `e`, which came to `r`, its weight: both fighters freeze for the profile's hit-stop frames
# (each keeps the longer of this and any other freeze it has: in a trade the longer of the two, not the sum),
# and the target is pushed along the blow by the profile's knockback.
func _weigh(e: HitEvent, r: HitResult) -> void:
	if not FREEZES.has(r.outcome):
		return
	e.attacker.freeze(e.profile.hitstop_frames)
	e.target.freeze(e.profile.hitstop_frames)
	e.target.push(e.direction * e.profile.knockback)


# Starts the grab pair of the attacker of `e`, a GRABBED blow, on its target. False if the attacker has none, or it
# cannot be staged where the two stand (the target turned away, a wall between them, no room to align) or could not
# start (Actor.start_grab_on): the blow is then taken as a HIT that staggers.
static func _grab(e: HitEvent) -> bool:
	return e.attacker.start_grab_on(e.target)


# What `e` comes to against its target as it stood when the frame began (as it stands now, for one that was
# not yet an actor then), or, for a blow of a paired move, what the pair's blow does (Combat.pair_hit); null if
# either side is gone.
func _judge(e: HitEvent) -> HitResult:
	if not is_instance_valid(e.attacker) or not is_instance_valid(e.target):
		return null
	if e.paired:
		return Combat.pair_hit(e)
	var d: Defense = _snapshot.defenses.get(e.target)
	if d == null:
		d = Defense.of(e.target)
	return Combat.resolve(e, d, e.target.stats.tuning)
