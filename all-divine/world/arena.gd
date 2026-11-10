class_name Arena
extends Region
## A Region with a fight in it: the training yard. It sends waves of Knuckles (data/arena/waves.tres) at the player,
## starts the next three seconds after the last of a wave falls (and fills the player's bars as it does), and puts it all
## back when the player dies (three seconds after) or F9 is pressed.
##
## Main begins it with the player (begin): he is its target, and when he dies it resets after RESET_DELAY seconds. Each
## wave sends its foes, one def after another and each as many times as its count says, to the region's markers
## EnemySpawn_1 to EnemySpawn_4 in turn, facing the player. The foes are children of the arena, thinking with the enemy
## brain their def names, and it owns the AttackTokens node (a child) that lets two of them at a time commit to an
## attack on the player. Waves go round: after the last comes the first again.
##
## With `automatic` off (the self-test: it asks for the wave it wants, and nothing else happens) the arena sends no next
## wave and never resets by itself.
##
## F6, F7 and F8 spawn one Knuckle of tier I, II or III (a debug foe: it is not part of any wave and does not count toward
## clearing one) and F9 resets.
##
## Times are counted in physics frames of game time, so they stop while the game is paused.

## One wave went down and the next starts after this many seconds; the player's death resets after as many.
const NEXT_WAVE_DELAY := 3.0
const RESET_DELAY := 3.0
const ACTOR := preload("res://actors/actor.tscn")
const WAVES := preload("res://data/arena/waves.tres")
## The debug keys' foes, by key.
const DEBUG_KEYS := {
	KEY_F6: preload("res://data/actors/knuckle_1.tres"),
	KEY_F7: preload("res://data/actors/knuckle_2.tres"),
	KEY_F8: preload("res://data/actors/knuckle_3.tres"),
}
const RESET_KEY := KEY_F9

## A wave started: its index in `waves`.
signal wave_started(index: int)
## Every foe of the wave has fallen: its index.
signal wave_cleared(index: int)

## Where the waves come from (the default, with none set, is data/arena/waves.tres). Only this is saved with a scene, so the
## waves stay one resource: editing the wave set changes every arena that uses it, a saved scene included.
@export var wave_set: ArenaWaveSet
## The waves, in order: the wave set's, as the arena was made (not saved: a copy of them in a scene would no longer follow
## their data). A test may put its own here.
var waves: Array[ArenaWave] = []
## Whether the arena runs the fight by itself (the next wave, the reset after the player's death).
var automatic := true
## The player: the foes' target, and who is put back at the Spawn.
var player: Actor
## The index in `waves` of the wave that is on (or was last): -1 before begin.
var wave := -1
## Gives out the attack tokens (a child, "AttackTokens").
var tokens: AttackTokens

## How many rounds of foes have been sent since the game started: it outlives a reload of the scene, and each round's foes
## take it as their spawn_count, so every wave, reset and reload rolls new dice.
static var _rounds := 0

var _enemies: Array[Actor] = []  # the foes of the wave that is on
var _extras: Array[Actor] = []  # the debug foes
var _cleared := false  # the wave that is on has been cleared
var _next_in := -1.0  # seconds to the next wave, or -1
var _reset_in := -1.0  # seconds to the reset after the player's death, or -1


func _init() -> void:
	waves.assign(WAVES.waves)


func _ready() -> void:
	if wave_set != null:
		waves.assign(wave_set.waves)
	tokens = get_node_or_null(^"AttackTokens") as AttackTokens
	if tokens == null:
		tokens = AttackTokens.new()
		tokens.name = "AttackTokens"
		add_child(tokens)


## Starts the fight with `who` as the player: the first wave is sent. Calling it again begins anew.
func begin(who: Actor) -> void:
	if player != null and player.died.is_connected(_on_player_died):
		player.died.disconnect(_on_player_died)
	player = who
	player.died.connect(_on_player_died)
	_next_in = -1.0
	_reset_in = -1.0
	start_wave(0)


## Sends wave `index` (past the last, the first again): its foes appear at the enemy spawns in turn, facing the player.
## The dead of the wave before are taken away; foes that still live stay.
func start_wave(index: int) -> void:
	if waves.is_empty():
		return
	wave = posmod(index, waves.size())
	_cleared = false
	_next_in = -1.0
	_forget_dead()
	var spawns := enemy_spawns()
	var n := 0
	for def_index in waves[wave].defs.size():
		for i in waves[wave].count[def_index]:
			var foe := _send(waves[wave].defs[def_index], spawns[n % spawns.size()] if not spawns.is_empty() else null, "Enemy%d" % (n + 1))
			foe.died.connect(_on_enemy_died)
			_enemies.append(foe)
			n += 1
	_rounds += 1
	wave_started.emit(wave)


## Takes every foe away, puts the player at the Spawn with full bars (standing him up through his get up if he was dead),
## and sends the current wave again. F9 and the player's death do it.
func reset() -> void:
	clear_foes()
	if player != null:
		player.runner.stop()  # whatever he was playing (a grab's fall, a finisher's lunge) goes with the foes
		if player.dead:
			player.revive(spawn())
		else:
			player.place(spawn())
			player.stats.refill()
	start_wave(maxi(wave, 0))


## Takes every foe away, the wave's and the debug ones, and the pending next wave and reset with them.
func clear_foes() -> void:
	_next_in = -1.0
	_reset_in = -1.0
	for foe in _enemies + _extras:
		if not is_instance_valid(foe):
			continue
		# What holds a foe is ended before it goes: a pair it is in (the player's move, if he was in it, stops with it), and
		# the player's lock on it (and the camera's).
		for other in Melee.end_pairs_of(foe):
			if other == player:
				player.runner.stop()
		_remove(foe)
	_let_go_of_lock()
	_enemies.clear()
	_extras.clear()


## Where the foes come from, in turn: the markers EnemySpawn_1, EnemySpawn_2, ... as far as they go.
func enemy_spawns() -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	var i := 1
	var marker := get_node_or_null("EnemySpawn_%d" % i) as Marker3D
	while marker != null:
		found.append(marker)
		i += 1
		marker = get_node_or_null("EnemySpawn_%d" % i) as Marker3D
	return found


## The foes of the wave that is on, living or dead, in the order they were sent.
func enemies() -> Array[Actor]:
	return _enemies


## How many waves there are.
func wave_count() -> int:
	return waves.size()


## Whether the wave that is on has been cleared (and the next is on its way).
func wave_is_cleared() -> bool:
	return _cleared


## A hash of the whole fight as it stands: every actor in tree order (its position to the millimetre, HP, posture and
## stamina to a tenth, and the id of the move it is playing), the wave and the physics frame. Equal fights hash equal; a
## replay that goes wrong shows where it first differed (Task 15).
func state_hash() -> int:
	var parts: Array = [wave, Engine.get_physics_frames()]
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor == null or not (is_ancestor_of(actor) or actor == player) or actor.stats == null:
			continue
		var at := actor.global_position
		parts.append_array([roundi(at.x * 1000.0), roundi(at.y * 1000.0), roundi(at.z * 1000.0),
				roundi(actor.stats.hp * 10.0), roundi(actor.stats.posture * 10.0), roundi(actor.stats.stamina * 10.0),
				String(actor.runner.current.id) if actor.runner.current != null else ""])
	return parts.hash()


## Forgets the counted rounds, so that the next foes roll the dice of the first round (for tests, and a replay).
static func reset_spawn_counts() -> void:
	_rounds = 0


func _physics_process(delta: float) -> void:
	if not automatic:
		return
	if _next_in >= 0.0:
		_next_in -= delta
		if _next_in < 0.0:
			_next_in = -1.0
			if player != null and is_instance_valid(player):
				player.stats.refill()
			start_wave(wave + 1)
	if _reset_in >= 0.0:
		_reset_in -= delta
		if _reset_in < 0.0:
			reset()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and debug_key(key.keycode):
		get_viewport().set_input_as_handled()


## The debug keys: F6, F7 and F8 spawn one Knuckle of tier I, II or III, F9 resets. True if `keycode` is one of them (and its
## work is done). The arena hears keys itself when it is in the window's viewport; Main, which keeps it in the stage's own
## viewport where keys never arrive, hands them on.
func debug_key(keycode: Key) -> bool:
	if DEBUG_KEYS.has(keycode):
		_extras.append(_send(DEBUG_KEYS[keycode], _next_spawn(), "Debug%d" % (_extras.size() + 1)))
		_rounds += 1
		return true
	if keycode == RESET_KEY:
		reset()
		return true
	return false


# A foe of `def` at `marker` (the region's spawn when null), facing the player, named `foe_name`.
func _send(def: ActorDef, marker: Marker3D, foe_name: String) -> Actor:
	var foe := ACTOR.instantiate() as Actor
	foe.name = foe_name
	foe.def = def
	foe.spawn_count = _rounds
	add_child(foe)
	var at := marker.global_position if marker != null else spawn().origin
	var toward := Vector2.ZERO
	if player != null and is_instance_valid(player):
		toward = Vector2(player.global_position.x - at.x, player.global_position.z - at.z)
	foe.place(Transform3D(Basis(Vector3.UP, Locomotion.yaw_of(toward) if not toward.is_zero_approx() else 0.0), at))
	return foe


# The marker the next debug foe goes to: the spawns in turn.
func _next_spawn() -> Marker3D:
	var spawns := enemy_spawns()
	return spawns[_extras.size() % spawns.size()] if not spawns.is_empty() else null


# The player's lock-on and the camera's lean toward it are let go.
func _let_go_of_lock() -> void:
	if player != null and is_instance_valid(player) and player.brain is PlayerBrain:
		(player.brain as PlayerBrain).lock.target = null
	var rig := get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig if is_inside_tree() else null
	if rig != null:
		rig.lock_target = null


# Takes `foe` out of the tree at once (so that the next foes can have its name, which seeds their dice) and frees it.
func _remove(foe: Actor) -> void:
	if is_instance_valid(foe):
		if foe.get_parent() != null:
			foe.get_parent().remove_child(foe)
		foe.queue_free()


# Takes away the dead of the wave before.
func _forget_dead() -> void:
	var living: Array[Actor] = []
	for foe in _enemies:
		if is_instance_valid(foe) and not foe.dead:
			living.append(foe)
		else:
			_remove(foe)
	_enemies = living


func _on_enemy_died() -> void:
	if _cleared:
		return
	for foe in _enemies:
		if is_instance_valid(foe) and not foe.dead:
			return
	_cleared = true
	wave_cleared.emit(wave)
	if automatic:
		_next_in = NEXT_WAVE_DELAY


func _on_player_died() -> void:
	if automatic:
		_reset_in = RESET_DELAY
