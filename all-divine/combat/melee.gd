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
##     against those snapshots (Combat.resolve, with the target's CombatTuning), then applies them all, each
##     through target.apply_hit and the attacker's hit_landed, in the order they were posted. A hit that came to
##     nothing (a WHIFF) is handed back to the attacker's scanner (HitScanner.forget), so the same swing may
##     still strike that body on a later tick: a roll's iframes ending inside a long swing do not spare it
## So every hit of a frame is judged against the defenders as they stood when the frame began, and in a trade
## each side gets the result of the other's blow: both land. (The hurtboxes the hits were found on stood there
## too: see HitScanner.)

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
	for e in events:
		results.append(_judge(e))
	for i in events.size():
		var e := events[i]
		if results[i] == null:
			continue
		if results[i].outcome == HitResult.Outcome.WHIFF:
			e.attacker.scanner.forget(e)
		e.target.apply_hit(e, results[i])
		e.attacker.hit_landed.emit(results[i], e)


# What `e` comes to against its target as it stood when the frame began (as it stands now, for one that was
# not yet an actor then); null if either side is gone.
func _judge(e: HitEvent) -> HitResult:
	if not is_instance_valid(e.attacker) or not is_instance_valid(e.target):
		return null
	var d: Defense = _snapshot.defenses.get(e.target)
	if d == null:
		d = Defense.of(e.target)
	return Combat.resolve(e, d, e.target.stats.tuning)
