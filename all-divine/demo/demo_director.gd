class_name DemoDirector
extends Node
## The preview demo's yard master: a stand-in that Task 14's training yard replaces. A child of the demo yard (the
## main scene's courtyard with Abarax in it).
##
## It spawns the three Knuckles (knuckle_1 to knuckle_3), each with a DemoBrain, spread 6 to 9 m from Abarax's spawn
## and facing him; hands out the single attack token (request_attack, release_attack: one Knuckle attacks at a time);
## spawns the three again RESPAWN_DELAY seconds after the last one dies; and reloads the scene RELOAD_DELAY seconds
## after Abarax dies. With --selftest (the game's self-test, which runs the courtyard's own circuit) it spawns nothing,
## so the self-test behaves as it does on the plain main scene.
##
## Times are counted in physics frames of game time, so they stop while the game is paused.

const RESPAWN_DELAY := 4.0
const RELOAD_DELAY := 3.0
## A token held this long is taken back (an attack never lasts this long; this is for one that went wrong).
const TOKEN_LIMIT := 6.0
## Each Knuckle: its def, and where it starts, in metres from Abarax's spawn on the ground plane (x, z).
const ROSTER := [
	[preload("res://data/actors/knuckle_1.tres"), Vector2(-7.0, -2.0)],
	[preload("res://data/actors/knuckle_2.tres"), Vector2(6.5, -1.5)],
	[preload("res://data/actors/knuckle_3.tres"), Vector2(-4.0, -7.0)],
]
## What the Knuckles' dice are seeded with, plus the Knuckle's index: the same fights every time.
const SEED := 1313
const ACTOR := preload("res://actors/actor.tscn")

## True when the game runs its self-test: nothing is spawned.
var selftest := SelfTest.active
## Seconds to wait; the constants above, as tests and tuning change them.
var respawn_delay := RESPAWN_DELAY
var reload_delay := RELOAD_DELAY
## What reloads the scene when Abarax is dead (a Callable with no arguments); the current scene's reload when not set.
var reloader := Callable()

signal reloading

var _player: Actor
var _world: Node
var _region: Region
var _knuckles: Array[Actor] = []
var _respawn_in := -1.0
var _reload_in := -1.0
var _holder: Actor
var _held_for := 0.0
var _round := 0  # how many times the three have been sent, for the dice


func _init() -> void:
	# The yard's root runs while paused (it hears the menu button); the fight does not.
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	var main := get_parent() as Main
	if main == null:
		push_error("DemoDirector: it belongs in the yard (a Main), not under '%s'" % get_parent().name)
		return
	if not main.is_node_ready():
		await main.ready
	_player = main.player
	_world = _player.get_parent()
	_region = main.region
	_player.died.connect(_on_player_died)
	if not selftest:
		_spawn_all()


## Asks for the attack token: true if `who` now holds it (or already did), false while another Knuckle does.
func request_attack(who: Actor) -> bool:
	if _holder == who:
		return true
	if _holder != null and is_instance_valid(_holder) and not _holder.dead and _held_for < TOKEN_LIMIT:
		return false
	_holder = who
	_held_for = 0.0
	return true


## Gives the token back (a Knuckle that does not hold it changes nothing).
func release_attack(who: Actor) -> void:
	if _holder == who:
		_holder = null


## The Knuckles of the yard, living or not, in tier order.
func knuckles() -> Array[Actor]:
	return _knuckles


func _physics_process(delta: float) -> void:
	_held_for += delta
	if _respawn_in >= 0.0:
		_respawn_in -= delta
		if _respawn_in < 0.0:
			_spawn_all()
	if _reload_in >= 0.0:
		_reload_in -= delta
		if _reload_in < 0.0:
			_reload_in = -1.0
			reloading.emit()
			if reloader.is_valid():
				reloader.call()
			else:
				get_tree().reload_current_scene()


# Sends the three, after taking away whatever is left of the last three.
func _spawn_all() -> void:
	_respawn_in = -1.0
	for old in _knuckles:
		if is_instance_valid(old):
			old.queue_free()
	_knuckles.clear()
	_holder = null
	var origin := _region.spawn().origin
	for i in ROSTER.size():
		var def: ActorDef = ROSTER[i][0]
		var offset: Vector2 = ROSTER[i][1]
		var at := Vector3(origin.x + offset.x, origin.y, origin.z + offset.y)
		var knuckle := ACTOR.instantiate() as Actor
		knuckle.name = "Knuckle%d" % (i + 1)
		knuckle.def = def
		knuckle.set_brain(DemoBrain.new(_player, self, SEED + 10 * _round + i))
		_world.add_child(knuckle)
		var toward := Vector2(origin.x - at.x, origin.z - at.z)
		knuckle.place(Transform3D(Basis(Vector3.UP, Locomotion.yaw_of(toward)), at))
		knuckle.died.connect(_on_knuckle_died)
		_knuckles.append(knuckle)
	_round += 1


func _on_knuckle_died() -> void:
	for knuckle in _knuckles:
		if is_instance_valid(knuckle) and not knuckle.dead:
			return
	_respawn_in = respawn_delay


func _on_player_died() -> void:
	_reload_in = reload_delay
