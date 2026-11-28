class_name FightBot
extends Brain
## A reactive player brain for seeded fights in tests: it walks at the nearest foe, palms when close (a finishable foe at 2.5 m),
## and when a foe's move has run a while it guards and sways or ducks across the foe's line, sometimes dash-stepping away. Its
## dice are its own seed's, so the same seed plays the same fight. `play` runs one such fight in the training yard and calls
## `each_frame(player)` after every physics frame.

var _rng := RandomNumberGenerator.new()
var _last_evade := -100
var _threshold := 0.2


func _init(seed_number: int) -> void:
	_rng.seed = seed_number


func think(actor: Actor, _delta: float) -> Intent:
	var intent := Intent.new()
	var best: Actor = null
	var best_distance := INF
	for node in actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == actor or other.stats == null or other.stats.hp <= 0.0:
			continue
		var d := other.global_position.distance_to(actor.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	if best == null:
		return intent
	var to := best.global_position - actor.global_position
	intent.face_target = best.global_position
	intent.look_target = best.head_point()
	if best_distance > 1.7:
		intent.move = Vector2(to.x, to.z).normalized()
	var f := actor.frame
	var foe_strikes := best.runner.current != null and best_distance < 3.2
	if foe_strikes and f - _last_evade > 30 and best.runner.time > _threshold:
		_threshold = _rng.randf_range(0.08, 0.5)
		_last_evade = f
		intent.held.append(&"guard")
		var across := Vector2(-to.z, to.x).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
		intent.pressed.append(&"sway" if _rng.randf() < 0.7 else &"duck")
		intent.evade_dir = across
		return intent
	if f - _last_evade < 12:
		intent.held.append(&"guard")
		return intent
	if best.is_in_group(Actor.FINISHABLE_GROUP) and best_distance < 2.5:
		intent.pressed.append(&"palm")
	elif best_distance < 2.0 and _rng.randf() < 0.1:
		intent.pressed.append(&"palm")
	elif _rng.randf() < 0.004:
		intent.pressed.append(&"dodge")
		intent.move = Vector2(-to.x, -to.z).normalized()
	return intent


## Plays `frames` physics frames of the seeded fight `seed_number` against the foes of `waves` (indices into the yard's waves: one
## wave, or the foes of the second take the first's names),
## the player unkillable, and calls `each_frame(player: Actor, frame: int)` after each. `placed` has the player placed where he
## stands first, as Main does at start-up. The test `tc` owns the arena.
static func play(tc: TestCase, seed_number: int, waves: Array, frames: int, placed: bool, each_frame: Callable) -> void:
	Game.reset()
	Arena.reset_spawn_counts(seed_number)
	var arena := tc.track((load("res://world/training_yard/training_yard.tscn") as PackedScene).instantiate()) as Arena
	arena.automatic = false
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.name = "Player"
	player.def = load("res://data/actors/abarax.tres") as ActorDef
	player.set_brain(FightBot.new(seed_number * 7 + 1))
	arena.add_child(player)
	arena.begin(player)
	if placed:
		player.place(player.global_transform)
	player.stats.max_hp = 100000.0
	player.stats.hp = 100000.0
	arena.clear_foes()  # begin sent wave 0; its foes' names would clash with the wave's (a clash names a foe by a counter, and a foe's dice are its name's)
	for wave in waves:
		arena.start_wave(wave)
	for f in frames:
		await tc.frames(1)
		each_frame.call(player, f)
	arena.queue_free()  # so that a second fight in the same test sees none of this one's foes
	await tc.frames(2)
	Game.reset()
