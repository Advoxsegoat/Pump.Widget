class_name HitIntake
extends RefCounted
## How an actor takes the blows that land on it, and how it dies. Melee judges every blow of a frame and hands
## each body all of its blows at once (Actor.apply_hits, which comes here), with those of its own blows that were
## turned back; this is what they do to it: their numbers come off its Stats, each kicks its upper body, and one
## thing comes of them all, a reaction move or its death. The actor owns one (Actor.intake), as it owns its
## Locomotion and Stats, and keeps the public face of it: apply_hits, apply_hit, die, `dead` and the signals got_hit
## and died.

## How hard a blow kicks the upper body (Rig.hit_react): HIT_REACT_BASE plus its poise damage over
## HIT_REACT_POISE, so a jab (6) is 0.8 and a blow of 10 poise damage is 1.
const HIT_REACT_BASE := 0.5
const HIT_REACT_POISE := 20.0
## The outcomes whose blow kicks the upper body: those that reached it, or the guard in front of it.
const KICKS: Array[HitResult.Outcome] = [HitResult.Outcome.HIT, HitResult.Outcome.GUARDED, HitResult.Outcome.GRABBED]
## The reactions a frame's blows can leave the body with, weakest first: of all of them, the strongest plays, once.
## Its own answers (parry, catch) give way to anything done to it; a guarded blow to one that got through; a flinch
## to its own blow turned back (parried) and that to a stagger; then being caught, a broken guard, and last a broken
## posture.
const REACTIONS: Array[StringName] = [&"parry", &"catch", &"guard_hit", &"flinch", &"parried", &"stagger", &"caught",
		&"guard_break", &"posture_broken"]
## What a broken posture plays while the def has no `posture_broken` reaction (F1 Task 10 brings it).
const POSTURE_BROKEN_STANDIN := &"stagger"

var _actor: Actor
var _death: MoveData  # the death move once die() has started it


func _init(actor: Actor) -> void:
	_actor = actor
	_actor.runner.move_ended.connect(_on_move_ended)


## Takes everything a frame's blows did to the actor together, so that what comes of them does not depend on the
## order they are taken in: the blows that landed on it (`events`, and what Melee judged each to come to,
## `results`), and its own blows that were turned back (`turned`, PARRIED or CAUGHT, and their `turned_results`).
## Each blow that landed takes off its HP, posture and stamina (a broken guard all the stamina there is), and each
## HIT, GUARDED or GRABBED one (a GRABBED one is a HIT for now) kicks the upper body away from it (Rig.hit_react,
## harder the more poise damage it carries): the additive flinch every blow gets, whether or not it interrupts what
## the actor is doing. Each turned blow takes its attacker_posture_damage off the actor's posture. Then one thing
## comes of them all: if together they emptied the HP the actor dies (die); otherwise the strongest of REACTIONS
## plays, once, cutting off the move that was playing:
##   a HIT or GRABBED blow's reaction (flinch or stagger); GUARDED: guard_hit, and the guard stays up through it
##   while guard is held (Actor.hold_guard); GUARD_BREAK: guard_break; PARRIED, CAUGHT: the actor's own parry or
##   catch; its blow PARRIED or CAUGHT: parried or caught; a posture emptied here: posture_broken (or, while the def
##   has none, stagger)
## (each the def's reaction move of that name; one it lacks plays nothing). A WHIFF changes nothing, nor does
## anything on the dead. got_hit is emitted for each blow that landed after, whatever its outcome.
func take(events: Array[HitEvent], results: Array[HitResult], turned: Array[HitEvent] = [],
		turned_results: Array[HitResult] = []) -> void:
	if not _actor.dead:
		var stats := _actor.stats
		var killed := false
		var broke := false
		var strongest := -1  # in REACTIONS
		for i in events.size():
			var r := results[i]
			if r.outcome == HitResult.Outcome.WHIFF:
				continue
			if KICKS.has(r.outcome):
				_actor.rig.hit_react(events[i].direction, HIT_REACT_BASE + events[i].profile.poise_damage / HIT_REACT_POISE)
			stats.spend_stamina(stats.stamina if r.outcome == HitResult.Outcome.GUARD_BREAK else r.stamina_cost)
			if r.posture_damage > 0.0:
				broke = stats.damage_posture(r.posture_damage) or broke
			killed = stats.take_damage(r.hp_damage) or killed
			strongest = maxi(strongest, REACTIONS.find(_answer(r)))
		for i in turned.size():
			var r := turned_results[i]
			if r.attacker_posture_damage > 0.0:
				broke = stats.damage_posture(r.attacker_posture_damage) or broke
			strongest = maxi(strongest, REACTIONS.find(&"caught" if r.outcome == HitResult.Outcome.CAUGHT else &"parried"))
		if broke:
			strongest = REACTIONS.find(&"posture_broken")
		if killed:
			die()
		elif strongest >= 0:
			_react(REACTIONS[strongest])
			if REACTIONS[strongest] == Actor.GUARD_HIT:
				_actor.hold_guard()
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


# The reaction a blow that landed on the actor asks for (a name in REACTIONS), or &"" for none.
static func _answer(r: HitResult) -> StringName:
	match r.outcome:
		HitResult.Outcome.GUARDED:
			return &"guard_hit"
		HitResult.Outcome.GUARD_BREAK:
			return &"guard_break"
		HitResult.Outcome.PARRIED:
			return &"parry"
		HitResult.Outcome.CAUGHT:
			return &"catch"
	match r.reaction:
		HitResult.Reaction.STAGGER:
			return &"stagger"
		HitResult.Reaction.FLINCH:
			return &"flinch"
	return &""


# Plays the def's reaction move `reaction`, if it has one (a posture_broken it lacks is POSTURE_BROKEN_STANDIN).
func _react(reaction: StringName) -> void:
	if reaction == &"posture_broken" and not _actor.def.reactions.has(reaction):
		reaction = POSTURE_BROKEN_STANDIN
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
