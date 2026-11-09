class_name AttackTokens
extends Node
## Attack tokens (spec §4.5): in an ordinary fight only one or two enemies commit to an attack on a target at a time, so
## a group presses without cheap gang-ups. An enemy's brain takes a token for its target before it commits (take) and
## gives it back when the attack is over (give_back); a target has PER_TARGET of them. A token also comes back by itself:
##   - when its attacker's move is over: a move that plays out (the attacker is free again), or one a reaction cuts
##     short (a flinch, a stagger, a parried recoil); a combo's cancels from one blow into the next keep it
##   - when its attacker dies
##   - TIMEOUT seconds after it was last taken, in case an attack never comes (a brain that holds one takes it again at
##     each press, which keeps it)
## Gank squads ignore the rule: their brains never take one (BrainDef.ignores_tokens).
##
## A node of the fight (a child of the arena or the yard), in the group `attack_tokens`; brains find it with take_for and
## give_back_for. With none in the tree, every take succeeds. Time is counted in physics frames of game time, so it
## stands still while the game is paused.

## The group the node is in.
const GROUP := &"attack_tokens"
## How many enemies may commit to one target at a time.
const PER_TARGET := 2
## Seconds a token is kept without being taken again before it comes back by itself.
const TIMEOUT := 3.0

var _held := {}  # attacker (Actor) -> [target (Actor), seconds since last taken]
var _watching := {}  # attacker (Actor) -> the Callables connected to its signals


func _enter_tree() -> void:
	add_to_group(GROUP)


## Takes one of `target`'s tokens for `attacker`: true if it now holds one (or held one already, which starts its
## TIMEOUT again), false while PER_TARGET others hold them. An attacker holds one token at a time: taking one for
## another target gives back the first.
func take(attacker: Actor, target: Actor) -> bool:
	if attacker == null or target == null:
		return false
	if _held.has(attacker):
		if _held[attacker][0] == target:
			_held[attacker][1] = 0.0
			return true
		give_back(attacker)
	if count(target) >= PER_TARGET:
		return false
	_held[attacker] = [target, 0.0]
	_watch(attacker)
	return true


## Gives `attacker`'s token back, if it holds one.
func give_back(attacker: Actor) -> void:
	if not _held.has(attacker):
		return
	_held.erase(attacker)
	_unwatch(attacker)


## Whether `attacker` holds a token.
func holds(attacker: Actor) -> bool:
	return _held.has(attacker)


## How many of `target`'s tokens are held.
func count(target: Actor) -> int:
	var n := 0
	for attacker: Actor in _held:
		if _held[attacker][0] == target:
			n += 1
	return n


## The AttackTokens in `node`'s tree, or null.
static func of(node: Node) -> AttackTokens:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as AttackTokens


## take on the AttackTokens in `attacker`'s tree; true when there is none (nothing limits who attacks).
static func take_for(attacker: Actor, target: Actor) -> bool:
	var tokens := of(attacker)
	return tokens == null or tokens.take(attacker, target)


## give_back on the AttackTokens in `attacker`'s tree, if there is one.
static func give_back_for(attacker: Actor) -> void:
	var tokens := of(attacker)
	if tokens != null:
		tokens.give_back(attacker)


func _physics_process(delta: float) -> void:
	for attacker: Actor in _held.keys():
		if not is_instance_valid(attacker) or attacker.dead or not is_instance_valid(_held[attacker][0]):
			_held.erase(attacker)
			_watching.erase(attacker)
			continue
		_held[attacker][1] += delta
		if _held[attacker][1] >= TIMEOUT - 1e-6:
			give_back(attacker)


func _exit_tree() -> void:
	for attacker: Actor in _held.keys():
		give_back(attacker)


func _watch(attacker: Actor) -> void:
	if _watching.has(attacker):
		return
	var ended := func(_move: MoveData, cancelled: bool) -> void:
		if not cancelled:
			give_back(attacker)
	var started := func(move: MoveData) -> void:
		if move.kind == MoveData.Kind.REACTION:
			give_back(attacker)
	var died := func() -> void: give_back(attacker)
	attacker.runner.move_ended.connect(ended)
	attacker.runner.move_started.connect(started)
	attacker.died.connect(died)
	_watching[attacker] = [ended, started, died]


func _unwatch(attacker: Actor) -> void:
	var callables: Array = _watching.get(attacker, [])
	_watching.erase(attacker)
	if callables.is_empty() or not is_instance_valid(attacker):
		return
	if attacker.runner.move_ended.is_connected(callables[0]):
		attacker.runner.move_ended.disconnect(callables[0])
	if attacker.runner.move_started.is_connected(callables[1]):
		attacker.runner.move_started.disconnect(callables[1])
	if attacker.died.is_connected(callables[2]):
		attacker.died.disconnect(callables[2])
