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
##     still strike that body on a later tick: a roll's iframes ending inside a long swing do not spare it
## So every hit of a frame is judged against the defenders as they stood when the frame began, and in a trade
## each side gets the result of the other's blow: both land. (The hurtboxes the hits were found on stood there
## too: see HitScanner.)
##
## All the blows a frame lands on one body are taken together (Actor.apply_hits), so that what the body ends up
## doing does not depend on which attacker's script ran first either: every blow's numbers come off and every
## blow kicks the body, and then one thing comes of them all, started once: the death, if together they emptied
## its HP, or else the strongest reaction among them, a STAGGER over a FLINCH. Two blows that would each kill it
## are one death that both dealt, and each attacker hears its blow landed. A body that died since the frame
## began (by something other than this frame's blows) takes nothing: its blows come to a WHIFF, on both sides.

## Melee's place in each physics frame: after every actor (which run at the default, 0).
const PRIORITY := 100
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


func _ready() -> void:
	process_physics_priority = PRIORITY
	_snapshot = Snapshot.new()
	_snapshot.name = &"Snapshot"
	_snapshot.process_physics_priority = SNAPSHOT_PRIORITY
	add_child(_snapshot)


## Records `event` to be judged and applied once every actor has moved this frame.
func post(event: HitEvent) -> void:
	_posted.append(event)


func _physics_process(_delta: float) -> void:
	if _posted.is_empty():
		return
	var events := _posted
	_posted = []
	var results: Array[HitResult] = []
	var blows := {}  # target -> the indices of its blows, the targets in the order they were first struck
	for i in events.size():
		results.append(_judge(events[i]))
		if results[i] != null:
			if not blows.has(events[i].target):
				blows[events[i].target] = []
			(blows[events[i].target] as Array).append(i)
	for target: Actor in blows:
		var taken: Array[HitEvent] = []
		var came_to: Array[HitResult] = []
		for i: int in blows[target]:
			if target.dead:
				results[i] = HitResult.new()
			if results[i].outcome == HitResult.Outcome.WHIFF:
				events[i].attacker.scanner.forget(events[i])
			taken.append(events[i])
			came_to.append(results[i])
		target.apply_hits(taken, came_to)
		for i: int in blows[target]:
			events[i].attacker.hit_landed.emit(results[i], events[i])


# What `e` comes to against its target as it stood when the frame began (as it stands now, for one that was
# not yet an actor then); null if either side is gone.
func _judge(e: HitEvent) -> HitResult:
	if not is_instance_valid(e.attacker) or not is_instance_valid(e.target):
		return null
	var d: Defense = _snapshot.defenses.get(e.target)
	if d == null:
		d = Defense.of(e.target)
	return Combat.resolve(e, d, e.target.stats.tuning)
