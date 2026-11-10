class_name HitIntake
extends RefCounted
## How an actor takes the blows that land on it, and how it dies. Melee judges every blow of a frame and hands
## each body all of its blows at once (Actor.apply_hits, which comes here), with those of its own blows that were
## turned back; this is what they do to it: their numbers come off its Stats, each kicks its upper body, and one
## thing comes of them all, a reaction move or its death. The actor owns one (Actor.intake), as it owns its
## Locomotion and Stats, and keeps the public face of it: apply_hits, apply_hit, die, `dead` and the signals got_hit
## and died.
##
## A blow that empties the posture breaks it: the body reels (its def's `posture_broken`) and is in the group
## `finishable` (Actor.FINISHABLE_GROUP) while it does, open to a finisher. Blows still land on a reeling body, and
## can kill it, but start no other reaction, so they never cut the reel short. When the reel ends without a finisher,
## the posture is full again and the body leaves the group (restore_posture). In a paired move the body takes the
## blows' numbers but nothing else comes of them: the pair decides, when it is over, whether it dies or gets up
## (Pairing.finish, which calls restore_posture, die and get_up).

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
## What a broken posture plays while the def has no `posture_broken` reaction.
const POSTURE_BROKEN_STANDIN := &"stagger"
## How long a body left lying with no `getup` reaction takes to fade back to locomotion (get_up), in seconds.
const GET_UP_FADE := 0.3

var _actor: Actor
var _death: MoveData  # the death move once die() has started it
var _reel: MoveData  # the move a broken posture plays, while it plays
var _hurtbox_layer := 0  # the layer the hurtbox was on, which die() takes it off and revive() puts it back on


func _init(actor: Actor) -> void:
	_actor = actor
	_hurtbox_layer = actor.rig.hurtbox.collision_layer
	_actor.runner.move_ended.connect(_on_move_ended)


## Takes everything a frame's blows did to the actor together, so that what comes of them does not depend on the
## order they are taken in: the blows that landed on it (`events`, and what Melee judged each to come to,
## `results`), and its own blows that were turned back (`turned`, PARRIED or CAUGHT, and their `turned_results`).
## Each blow that landed takes off its HP, posture and stamina (a broken guard all the stamina there is), and each
## HIT, GUARDED or GRABBED one (GRABBED here is a grab whose attacker has no grab pair, taken as a HIT) kicks the upper
## body away from it (Rig.hit_react, harder the more poise damage it carries): the additive flinch every blow gets,
## whether or not it interrupts what the actor is doing. Each turned blow takes its attacker_posture_damage off the
## actor's posture. Then one thing comes of them all: if together they emptied the HP the actor dies (die); otherwise
## the strongest of REACTIONS plays, once, cutting off the move that was playing:
##   a HIT or GRABBED blow's reaction (flinch or stagger); GUARDED: guard_hit, and the guard stays up through it
##   while guard is held (Actor.hold_guard); GUARD_BREAK: guard_break; PARRIED, CAUGHT: the actor's own parry or
##   catch; its blow PARRIED or CAUGHT: parried or caught; a posture emptied here: posture_broken (or, while the def
##   has none, stagger), and the actor joins the group finishable while it reels
## (each the def's reaction move of that name; one it lacks plays nothing). But a body that is reeling from a broken
## posture plays no new reaction (it reels on), and one in a paired move neither reacts nor dies here (the pair
## decides when it is over). A WHIFF changes nothing, nor does anything on the dead. got_hit is emitted for each blow
## that landed after, whatever its outcome.
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
		if _actor.paired_with != null:
			pass  # the pair decides what comes of it, when it is over
		elif killed:
			die()
		elif strongest >= 0 and _reel == null:
			var started := _react(REACTIONS[strongest])
			if broke:
				_begin_reel(started)
			elif REACTIONS[strongest] == Actor.GUARD_HIT:
				_actor.hold_guard()
	for i in events.size():
		_actor.got_hit.emit(results[i], events[i])


## Kills the actor, once: it plays its def's `death` reaction, its hurtbox goes off (no blow finds it again),
## what it had pressed is forgotten and its brain is ignored from then on, it is no longer a foe to aim at or to
## finish, and `died` is emitted. When the death clip ends, the body leaves the `actor` layer and lies as the clip
## left it (at once, with no death clip). A body already `lying` where a paired move left it plays no death clip
## either: it stays as it lies, so a corpse never stands up to fall again.
func die(lying := false) -> void:
	if _actor.dead:
		return
	_actor.dead = true
	_actor.remove_from_group(Actor.LOCKABLE_GROUP)
	_actor.remove_from_group(Actor.FINISHABLE_GROUP)
	_actor.buffer.clear()
	_actor.rig.hurtbox.collision_layer = 0
	_death = null if lying else _reaction_move(&"death")
	if _death != null:
		_actor.runner.start(_death)
	else:
		_actor.collision_layer &= ~Layers.ACTOR
	_actor.died.emit()


## Brings a dead actor back: alive, on the `actor` layer and open to blows again (and a foe to aim at, if it is an
## enemy), with the death clip cancelled by whatever plays next. Actor.revive is its front, and puts the body somewhere
## and starts the get up. Nothing happens to one that is not dead.
func revive() -> void:
	if not _actor.dead:
		return
	_actor.dead = false
	_death = null
	_reel = null
	_actor.collision_layer |= Layers.ACTOR
	_actor.rig.hurtbox.collision_layer = _hurtbox_layer
	if _actor.def.team == ActorDef.Team.ENEMY:
		_actor.add_to_group(Actor.LOCKABLE_GROUP)


## Ends a broken posture: the posture is full again (whether or not it was broken) and the actor leaves the group
## finishable. The reel ending without a finisher does it, and the end of a paired move the actor followed in.
func restore_posture() -> void:
	_actor.stats.restore_posture()
	_actor.remove_from_group(Actor.FINISHABLE_GROUP)


## Stands the actor up from where a paired move left it lying: its def's `getup` reaction, or, with none, a fade
## from the pose it lies in back to locomotion.
func get_up() -> void:
	if _react(&"getup") == null:
		_actor.rig.stop_move(GET_UP_FADE)


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


# Plays the def's reaction move `reaction`, if it has one (a posture_broken it lacks is POSTURE_BROKEN_STANDIN), and
# returns it; null if none started.
func _react(reaction: StringName) -> MoveData:
	if reaction == &"posture_broken" and not _actor.def.reactions.has(reaction):
		reaction = POSTURE_BROKEN_STANDIN
	var move := _reaction_move(reaction)
	if move != null:
		_actor.runner.start(move)
	return move if move != null and _actor.runner.current == move else null


# The posture broke and `reel` (or nothing) started: the actor is open to a finisher while it reels. With nothing to
# reel in, the break is over at once.
func _begin_reel(reel: MoveData) -> void:
	if reel == null:
		restore_posture()
		return
	_reel = reel
	_actor.add_to_group(Actor.FINISHABLE_GROUP)


# The move the def's reactions name for `reaction`, or null if it names none.
func _reaction_move(reaction: StringName) -> MoveData:
	if not _actor.def.reactions.has(reaction):
		return null
	return Registry.fetch(&"moves", StringName(_actor.def.reactions[reaction])) as MoveData


# The reel is over: unless a finisher took over (the actor is paired now; the pair's end restores it) or the actor
# died, the posture is full again. A death clip that has played out: the body leaves the `actor` layer, and the rig
# is held on the clip's last pose (the runner fades a move that ends back to locomotion, which would stand the body
# up again).
func _on_move_ended(move: MoveData, cancelled: bool) -> void:
	if move == _reel:
		_reel = null
		if _actor.paired_with == null and not _actor.dead:
			restore_posture()
	if not _actor.dead or move != _death or cancelled:
		return
	_actor.collision_layer &= ~Layers.ACTOR
	_actor.rig.hold_end_pose(move.clip)
