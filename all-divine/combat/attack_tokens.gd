class_name AttackTokens
extends Node
## Attack tokens (spec §4.5): in an ordinary fight only one or two enemies commit to an attack on a target at a time, so
## a group presses without cheap gang-ups. An enemy's brain takes a token for its target before it commits (take) and
## gives it back when the attack is over (give_back); a target has PER_TARGET of them. A token also comes back by itself:
##   - when its attacker's move is over: a move that plays out (the attacker is free again), or one a reaction cuts
##     short (a flinch, a stagger, a parried recoil); a combo's cancels from one blow into the next keep it
##   - when its attacker dies, or leaves the tree (freed, or taken out of it)
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
## Asked for as a count: all of a target's tokens, whatever their number.
const ALL := 0

var _held := {}  # attacker (Actor) -> [target (Actor), seconds since last taken, how many tokens]
var _watching := {}  # attacker (Actor) -> the Callables connected to its signals


func _init() -> void:
	# Its clock is the fight's: it stands still while the game is paused, even under a root that runs while paused.
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _enter_tree() -> void:
	add_to_group(GROUP)


## Takes `n` of `target`'s tokens for `attacker` (ALL, or any number past PER_TARGET, is every one the target gives; below 1
## is taken as ALL): true if it now holds them (or held them already, which starts its TIMEOUT again), false while others hold
## so many that fewer than `n` are left, and then it keeps what it held. An attacker holds tokens for one target at a time:
## taking some for another target gives back the first. What an attacker holds is `n` as last taken, not added up: taken as
## one after all, it holds one.
func take(attacker: Actor, target: Actor, n := 1) -> bool:
	if attacker == null or target == null or not attacker.is_inside_tree():
		return false
	var want := _wanted(n)
	if _held.has(attacker):
		if _held[attacker][0] == target:
			if _others(attacker, target) + want > PER_TARGET:
				return false
			_held[attacker][1] = 0.0
			_held[attacker][2] = want
			return true
		give_back(attacker)
	if _others(attacker, target) + want > PER_TARGET:
		return false
	_held[attacker] = [target, 0.0, want]
	_watch(attacker)
	return true


## Whether `attacker` could hold `n` of `target`'s tokens now, holding what it holds.
func can_take(attacker: Actor, target: Actor, n := 1) -> bool:
	return attacker != null and target != null and _others(attacker, target) + _wanted(n) <= PER_TARGET


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
	return _others(null, target)


## The AttackTokens in `node`'s tree, or null.
static func of(node: Node) -> AttackTokens:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as AttackTokens


## take on the AttackTokens in `attacker`'s tree; true when there is none (nothing limits who attacks).
static func take_for(attacker: Actor, target: Actor, n := 1) -> bool:
	var tokens := of(attacker)
	return tokens == null or tokens.take(attacker, target, n)


## give_back on the AttackTokens in `attacker`'s tree, if there is one.
static func give_back_for(attacker: Actor) -> void:
	var tokens := of(attacker)
	if tokens != null:
		tokens.give_back(attacker)


func _physics_process(delta: float) -> void:
	for key: Variant in _held.keys():
		if not is_instance_valid(key) or (key as Actor).dead or not is_instance_valid(_held[key][0]):
			_held.erase(key)
			_watching.erase(key)
			continue
		_held[key][1] += delta
		if _held[key][1] >= TIMEOUT - 1e-6:
			give_back(key as Actor)


func _exit_tree() -> void:
	for key: Variant in _held.keys():
		if is_instance_valid(key):
			give_back(key as Actor)
	_held.clear()
	_watching.clear()


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
	attacker.tree_exiting.connect(died)  # freed or taken out of the tree: it attacks no more
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
	if attacker.tree_exiting.is_connected(callables[2]):
		attacker.tree_exiting.disconnect(callables[2])


# How many tokens of `target` are held by anyone but `attacker`.
func _others(attacker: Actor, target: Actor) -> int:
	var n := 0
	for key: Variant in _held:  # untyped: a holder freed under us must not be assigned to a typed variable
		if key != attacker and is_instance_valid(key) and _held[key][0] == target:
			n += _held[key][2]
	return n


static func _wanted(n: int) -> int:
	return PER_TARGET if n < 1 or n > PER_TARGET else n
