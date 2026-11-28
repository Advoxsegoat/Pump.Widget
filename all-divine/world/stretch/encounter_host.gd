class_name EncounterHost
extends Node
## Foes placed as encounters (F3 systems Task 4). A child of the run, named "Encounters": it stands each `EncounterDef`'s foes in as the
## player comes near and out as he goes far, wakes the ones that sleep, passes an alarm from one member to the rest, heals the one that
## walks home, remembers which have fallen (the saved game's `fallen`) and puts all of them back on a rest and on a death.
##
## Every STREAM_EVERY play frames it streams: an encounter that stands nowhere whose centre (the mean of its posts) is within its
## `spawn_radius` of the player stands in the placements that have not fallen and are not `gone_if`-flagged; one whose foes are all
## idle (none noticing, fighting, or walking home) with its centre beyond `despawn_radius` is taken away (the fallen stay fallen). The
## picture is 20 x 11 m on the ground and ends within ten metres of him, so both happen out of sight. A foe is named
## `<encounter id>_<index>`, rolls its dice from that name and the run's `serial`, and is a child of the region like any foe of the yard
## (so the lock, the Hud and the hash find it). Every timer counts `Game.play_frames`: a pause and a scene stand it all still.

## An encounter stood in: its foes, in placement order (the fallen's places are not there).
signal spawned(id: StringName, foes: Array[Actor])
## An encounter was taken away (the player went far, or a reset).
signal despawned(id: StringName)
## The last of an encounter's placements fell.
signal cleared(id: StringName)

const ACTOR := preload("res://actors/actor.tscn")
## Play frames between two streamings (a quarter of a second).
const STREAM_EVERY := 15

var run: StretchRun

var _foes := {}  # encounter id -> Array[Actor] (its stood-in foes, in order, dead or alive)
var _killed := {}  # encounter id -> Array[int] (placement indices fallen since the last reset, sorted)
var _counted := -1  # the Game.play_frames last counted


## Adds the host under `run`, the fallen of the saved game remembered, and streams once (a game begun in the street has its foes at once).
static func begin(for_run: StretchRun) -> EncounterHost:
	var host := EncounterHost.new()
	host.name = &"Encounters"
	host.run = for_run
	for id in for_run.data.fallen:
		host._read_fallen(String(id))
	for_run.add_child(host)
	for_run.player_fell.connect(host._on_player_fell)
	for_run.world_reset.connect(host.reset_all)
	host._stream()
	return host


## The foes of encounter `id` that are stood in (dead ones too, until it is taken away), in placement order.
func foes(id: StringName) -> Array[Actor]:
	var out: Array[Actor] = []
	for foe: Actor in _foes.get(id, []):
		if is_instance_valid(foe):
			out.append(foe)
	return out


## Every foe stood in, in the stretch's order.
func all_foes() -> Array[Actor]:
	var out: Array[Actor] = []
	for enc in run.def.encounters:
		out.append_array(foes(enc.id))
	return out


## The indices of the placements of `id` that have fallen since the last reset.
func killed(id: StringName) -> PackedInt32Array:
	var out := PackedInt32Array()
	for index: int in _killed.get(id, []):
		out.append(index)
	return out


## Whether encounter `id` stands now.
func stands(id: StringName) -> bool:
	return _foes.has(id)


## Every foe is taken away as `Arena.clear_foes` takes one (pairs ended, the player's move stopped if he was in one, his lock and the
## camera's lean let go, out of the tree before it is freed), the fallen forgotten (here and in the saved game); the next streaming stands
## the encounters near him in again. Run on `world_reset`: a rest and the stand-up after a death.
func reset_all() -> void:
	for enc in run.def.encounters:
		_remove(enc.id)
	_foes.clear()
	_killed.clear()
	run.data.fallen.clear()
	_let_go_of_lock()


## A part of the run's hash: for each encounter, whether it stands and which of its placements have fallen.
func hash_part() -> Array:
	var parts: Array = []
	for enc in run.def.encounters:
		parts.append([String(enc.id), 1 if _foes.has(enc.id) else 0, Array(killed(enc.id))])
	return parts


func _physics_process(_delta: float) -> void:
	if Game.play_frames == _counted:
		return  # a frame of no play (a pause, a scene)
	_counted = Game.play_frames
	_wake_near()
	if _counted % STREAM_EVERY == 0:
		_stream()


# --- streaming ---

func _stream() -> void:
	if run.player == null or not is_instance_valid(run.player):
		return
	var here := Vector2(run.player.global_position.x, run.player.global_position.z)
	for enc in run.def.encounters:
		var centre := enc.centre()
		var away := here.distance_to(Vector2(centre.x, centre.z))
		if not _foes.has(enc.id):
			if away <= enc.spawn_radius and not _gone(enc):
				_stand(enc)
		elif away > enc.despawn_radius and _idle(enc):
			_remove(enc.id)
			_foes.erase(enc.id)
			despawned.emit(enc.id)


func _gone(enc: EncounterDef) -> bool:
	return enc.gone_if != &"" and run.flag(enc.gone_if)


# Whether every living foe of `enc` is standing about: none noticing, fighting, or walking home.
func _idle(enc: EncounterDef) -> bool:
	for foe in foes(enc.id):
		var brain := foe.brain as EnemyBrain
		if foe.dead:
			continue
		if brain == null or brain.mode != EnemyBrain.Mode.IDLE or brain.going_home():
			return false
	return true


# --- making foes ---

func _stand(enc: EncounterDef) -> void:
	var gone := killed(enc.id)
	var made: Array[Actor] = []
	for i in enc.placements.size():
		if gone.has(i):
			continue
		made.append(_make(enc, i))
	_foes[enc.id] = made
	if not made.is_empty():
		spawned.emit(enc.id, made)


func _make(enc: EncounterDef, index: int) -> Actor:
	var placement := enc.placements[index]
	var foe := ACTOR.instantiate() as Actor
	foe.name = "%s_%d" % [enc.id, index]
	foe.def = placement.def
	foe.spawn_count = run.serial
	run.serial += 1
	if placement.brain != null:
		foe.set_brain(EnemyBrain.new(placement.brain, hash("%s#%d" % [foe.name, foe.spawn_count])))
	run.region.add_child(foe)
	foe.place(Transform3D(Basis(Vector3.UP, placement.yaw()), placement.at))
	var brain := foe.brain as EnemyBrain
	if brain != null:
		brain.home = placement.at
		brain.home_facing = placement.yaw()
		brain.leash = enc.leash
		brain.asleep = enc.sleeping
		brain.engaged.connect(_on_engaged.bind(enc, foe))
		brain.arrived_home.connect(_on_arrived.bind(foe))
	foe.died.connect(_on_died.bind(enc, index))
	foe.got_hit.connect(_on_hit.bind(enc))
	run.watch_foe(foe)
	return foe


# --- what foes do ---

# A sleeper wakes when the player comes within the wake radius of any member.
func _wake_near() -> void:
	var player := run.player
	if player == null or not is_instance_valid(player) or player.dead:
		return
	for enc in run.def.encounters:
		if not enc.sleeping or not _foes.has(enc.id):
			continue
		for foe in foes(enc.id):
			var brain := foe.brain as EnemyBrain
			if foe.dead or brain == null or not brain.asleep:
				continue
			var flat := Vector2(foe.global_position.x - player.global_position.x, foe.global_position.z - player.global_position.z)
			if flat.length() <= enc.wake_radius:
				_wake(enc)
				break


# Wakes every living member of `enc`.
func _wake(enc: EncounterDef) -> void:
	for foe in foes(enc.id):
		var brain := foe.brain as EnemyBrain
		if not foe.dead and brain != null and brain.asleep:
			brain.wake()


func _on_hit(_result: HitResult, _event: HitEvent, enc: EncounterDef) -> void:
	_wake(enc)


# A member engaged: with the alarm, the rest do too.
func _on_engaged(enc: EncounterDef, source: Actor) -> void:
	if not enc.alarm:
		return
	for foe in foes(enc.id):
		var brain := foe.brain as EnemyBrain
		if foe != source and not foe.dead and brain != null:
			brain.engage_now()


# A foe that walked home is healed (it pays no petals for that: it did not die).
func _on_arrived(foe: Actor) -> void:
	if is_instance_valid(foe) and not foe.dead and foe.stats != null:
		foe.stats.refill()


func _on_died(enc: EncounterDef, index: int) -> void:
	var list: Array = _killed.get(enc.id, [])
	if not list.has(index):
		list.append(index)
		list.sort()
	_killed[enc.id] = list
	var id := StringName("%s_%d" % [enc.id, index])
	if not run.data.fallen.has(id):
		run.data.fallen.append(id)
		run.data.fallen.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		run.mark_dirty()
	if list.size() >= enc.placements.size():
		cleared.emit(enc.id)


# He fell: the file written at the moment of death has no fallen (a quit in the three seconds loses nothing twice); the foes
# themselves stand until he stands up.
func _on_player_fell() -> void:
	run.data.fallen.clear()


# --- taking foes away ---

# Takes the foes of `id` out of the game as Arena.clear_foes does.
func _remove(id: StringName) -> void:
	for foe: Actor in _foes.get(id, []):
		if not is_instance_valid(foe):
			continue
		for other in Melee.end_pairs_of(foe):
			if other == run.player:
				run.player.runner.stop()
		AttackTokens.give_back_for(foe)
		if run.player != null and is_instance_valid(run.player) and run.player.brain is PlayerBrain:
			var lock := (run.player.brain as PlayerBrain).lock
			if lock.target == foe:
				lock.target = null
		var rig := get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
		if rig != null and rig.lock_target == foe:
			rig.lock_target = null
		if foe.get_parent() != null:
			foe.get_parent().remove_child(foe)
		foe.queue_free()


# The player's lock and the camera's lean toward it are let go.
func _let_go_of_lock() -> void:
	if run.player != null and is_instance_valid(run.player) and run.player.brain is PlayerBrain:
		(run.player.brain as PlayerBrain).lock.target = null
	var rig := get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	if rig != null:
		rig.lock_target = null


# One id of the saved game's `fallen` (`<encounter id>_<index>`) into the killed lists.
func _read_fallen(text: String) -> void:
	var cut := text.rfind("_")
	if cut <= 0 or not text.substr(cut + 1).is_valid_int():
		return
	var enc_id := StringName(text.substr(0, cut))
	var list: Array = _killed.get(enc_id, [])
	var index := int(text.substr(cut + 1))
	if not list.has(index):
		list.append(index)
		list.sort()
	_killed[enc_id] = list
