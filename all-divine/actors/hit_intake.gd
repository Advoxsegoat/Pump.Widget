class_name HitIntake
extends RefCounted
## How an actor takes the blows that land on it, and how it dies. Melee judges every blow of a frame and hands
## each body all of its blows at once (Actor.apply_hits, which comes here); this is what they do to it: their
## numbers come off its Stats, each kicks its upper body, and one thing comes of them all, a reaction move or its
## death. The actor owns one (Actor.intake), as it owns its Locomotion and Stats, and keeps the public face of it:
## apply_hits, apply_hit, die, `dead` and the signals got_hit and died.

## How hard a blow kicks the upper body (Rig.hit_react): HIT_REACT_BASE plus its poise damage over
## HIT_REACT_POISE, so a jab (6) is 0.8 and a blow of 10 poise damage is 1.
const HIT_REACT_BASE := 0.5
const HIT_REACT_POISE := 20.0

var _actor: Actor
var _death: MoveData  # the death move once die() has started it


func _init(actor: Actor) -> void:
	_actor = actor
	_actor.runner.move_ended.connect(_on_move_ended)


## Takes every blow that landed on the actor in one frame (`events`, and what Melee judged each to come to,
## `results`) together, so that what comes of them does not depend on the order they are taken in. Each blow's
## HP, posture and stamina come off, and each HIT or GUARDED blow (and a GRABBED one, a HIT for now) kicks the
## upper body away from it (Rig.hit_react, harder the more poise damage it carries): the additive flinch every
## blow gets, whether or not it interrupts what the actor is doing. Then one thing comes of them all: if
## together they emptied the HP the actor dies (die), and otherwise the strongest reaction among them plays,
## once: a STAGGER over a FLINCH (the def's `stagger` or `flinch` reaction move, cutting off the move that was
## playing). A WHIFF changes nothing, nor does any blow on the dead. got_hit is emitted for each blow after,
## whatever its outcome.
func take(events: Array[HitEvent], results: Array[HitResult]) -> void:
	if not _actor.dead:
		var killed := false
		var reaction := HitResult.Reaction.NONE
		for i in events.size():
			if results[i].outcome == HitResult.Outcome.WHIFF:
				continue
			killed = _take(events[i], results[i]) or killed
			reaction = maxi(reaction, results[i].reaction) as HitResult.Reaction
		if killed:
			die()
		elif reaction == HitResult.Reaction.STAGGER:
			_react(&"stagger")
		elif reaction == HitResult.Reaction.FLINCH:
			_react(&"flinch")
	for i in events.size():
		_actor.got_hit.emit(results[i], events[i])


## Kills the actor, once: it plays its def's `death` reaction, its hurtbox goes off (no blow finds it again),
## what it had pressed is forgotten and its brain is ignored from then on, and `died` is emitted. When the death
## clip ends, the body leaves the `actor` layer and lies as the clip left it (at once, with no death clip).
func die() -> void:
	if _actor.dead:
		return
	_actor.dead = true
	_actor.remove_from_group(Actor.LOCKABLE_GROUP)
	_actor.buffer.clear()
	_actor.rig.hurtbox.collision_layer = 0
	_death = _reaction_move(&"death")
	if _death != null:
		_actor.runner.start(_death)
	else:
		_actor.collision_layer &= ~Layers.ACTOR
	_actor.died.emit()


# One blow of take: its kick and its numbers. True if it emptied the HP.
func _take(e: HitEvent, r: HitResult) -> bool:
	var stats := _actor.stats
	if r.outcome in [HitResult.Outcome.HIT, HitResult.Outcome.GUARDED, HitResult.Outcome.GRABBED]:
		_actor.rig.hit_react(e.direction, HIT_REACT_BASE + e.profile.poise_damage / HIT_REACT_POISE)
	if r.stamina_cost > 0.0:
		stats.spend_stamina(r.stamina_cost)
	if r.posture_damage > 0.0:
		stats.damage_posture(r.posture_damage)
	return stats.take_damage(r.hp_damage)


# Plays the def's reaction move `reaction`, if it has one.
func _react(reaction: StringName) -> void:
	var move := _reaction_move(reaction)
	if move != null:
		_actor.runner.start(move)


# The move the def's reactions name for `reaction`, or null if it names none.
func _reaction_move(reaction: StringName) -> MoveData:
	if not _actor.def.reactions.has(reaction):
		return null
	return Registry.fetch(&"moves", StringName(_actor.def.reactions[reaction])) as MoveData


# A death clip that has played out: the body leaves the `actor` layer, and the rig is held on the clip's last
# pose (the runner fades a move that ends back to locomotion, which would stand the body up again).
func _on_move_ended(move: MoveData, cancelled: bool) -> void:
	if not _actor.dead or move != _death or cancelled:
		return
	_actor.collision_layer &= ~Layers.ACTOR
	_actor.rig.play_move(move.clip, 0.0)
	_actor.rig.set_move_time(_actor.rig.tree.get_animation(move.clip).length)
