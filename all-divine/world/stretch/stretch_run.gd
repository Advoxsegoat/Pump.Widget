class_name StretchRun
extends Node
## The stretch as it is being played: a node under the stretch's region that owns the world's memory (`SaveData`, what the player's
## deeds have changed), the shrines, resting, the way back three seconds after a death, where he last stood on safe ground, and the
## saved game that keeps all of it. Places and numbers are data (`StretchDef`, `ShrineDef`); this is only what happens.
##
## `start` puts the player where the saved game says (the last safe place he stood at, when it is still standing ground; else the
## shrine he last rested at, or the first one) with the bars he had, and makes the shrines. From then on:
##  - the interact button near a shrine rests (`rest`): bars full, the shrine is where he stands up, the game is saved;
##  - a death stands him up at the last shrine three seconds of play later (`respawn`), the file written at the moment of death;
##  - once a second of play, when it is safe (`is_safe`), his place is noted: the saved game's `at` and `bars`;
##  - every AUTOSAVE_FRAMES of play, if something changed (he has moved half a metre or turned fifteen degrees from where the file
##    has him counts; standing still does not), the game is saved; and it is saved when the run leaves the tree.
## Every timer counts `Game.play_frames`, so a pause and a scene stand them still. The run reads no clock and no random number.
##
## A run with no store (a new game, a test, a recording) writes nothing, ever.

## The shrine was rested at: its id. F2's level-up menu will open from this.
signal rested(shrine_id: StringName)
## A flag was set in the world's memory for the first time.
signal world_changed(flag: StringName)
## The foes should be put back (a rest, a death's stand-up): the encounters listen.
signal world_reset
## The player fell.
signal player_fell
## The player stood up at his shrine after a death.
signal respawned

## Seconds after a fall that he stands up at the last shrine (the yard's own delay).
const DEATH_DELAY := 3.0
## Play frames between two autosaves (thirty seconds).
const AUTOSAVE_FRAMES := 1800
## His place is noted on every NOTE_EVERY'th play frame: once a second.
const NOTE_EVERY := 60
## No living foe of the other team within this many metres, flat, for a place to be safe.
const SAFE_DISTANCE := 12.0
## A place is another place for the autosave's sake after this many metres or this many degrees.
const MOVED_METRES := 0.5
const TURNED_DEGREES := 15.0
## The dice of the stretch's foes start at `n * SEED_SERIALS` for a seed `n`, as the yard's start at `n * Arena.SEED_ROUNDS`.
const SEED_SERIALS := 1000
const SHRINE := preload("res://world/stretch/shrine.tscn")
const BURST_FX := &"petal_burst"
const REST_CUE := &"shrine_rest"

static var _first_serial := 0

## How many foes the stretch has sent: the foes' dice come from it (Task 4). It starts at the seed's.
var serial := 0
var def: StretchDef
var data: SaveData
## Where the game is written; null writes nothing.
var store: SaveStore
var player: Actor
var region: Region
var tokens: AttackTokens
var interactor: Interactor
## Play frames between two autosaves (a test shortens it).
var autosave_frames := AUTOSAVE_FRAMES

# Task 5: gates. One door per gate of the def, made before the player is placed (a board built here is in the world he is placed in).
var gates: Array[GateDoor] = []

var _lived := 0  # physics frames this run has lived (state_hash): the same in a replay, not a clock
var _counted := -1  # the Game.play_frames the timers last counted
var _since_save := 0
var _death_frames := -1  # play frames since a fall, or -1 when he is not waiting to stand up
var _dirty := false  # something other than standing still has changed since the last write
var _written_at := {}  # where the file has him


## Adds a run under `region` for `player`, who is put at the place `data` says (see above), and returns it. `store` null: nothing
## is ever written.
static func start(region_node: Region, who: Actor, stretch_def: StretchDef, save_store: SaveStore, save_data: SaveData) -> StretchRun:
	var run := StretchRun.new()
	run.name = &"StretchRun"
	run.region = region_node
	run.player = who
	run.def = stretch_def
	run.store = save_store
	run.data = save_data
	run.serial = _first_serial
	run._written_at = save_data.at.duplicate()
	run.tokens = AttackTokens.new()
	run.tokens.name = &"AttackTokens"
	run.interactor = Interactor.new()
	run.interactor.name = &"Interactor"
	run.interactor.player = who
	region_node.add_child(run)
	run.add_child(run.tokens)
	run.add_child(run.interactor)
	for shrine_def in stretch_def.shrines:
		var shrine := SHRINE.instantiate() as Shrine
		shrine.name = String(shrine_def.id)
		shrine.def = shrine_def
		run.add_child(shrine)
		shrine.global_position = shrine_def.plinth
	run._make_gates()
	who.died.connect(run._on_player_died)
	run._place_player()
	return run


## Starts the dice of the stretch's foes at the stream of `seed_number` (see SEED_SERIALS): the bot's seeds and a recording's.
static func start_seed(seed_number: int) -> void:
	_first_serial = seed_number * SEED_SERIALS


## The shrine he stands up at: the one he last rested at, else the stretch's first.
func rest_shrine() -> ShrineDef:
	var wanted := data.rest_shrine if data.rest_shrine != &"" else def.start_shrine
	for shrine_def in def.shrines:
		if shrine_def.id == wanted:
			return shrine_def
	return def.shrines[0] if not def.shrines.is_empty() else null


## Rests at `shrine`: bars full and no exhaustion or break, the shrine the one he stands up at, the shrine flagged, a burst of
## petals on him and the bell, the foes put back (`world_reset`), the place he rests at noted, and the game saved.
func rest(shrine: ShrineDef) -> void:
	player.stats.refill()
	data.rest_shrine = shrine.id
	_remember(StringName("shrine:%s" % shrine.id))
	var fx := player.get_node_or_null(^"ActorFx") as ActorFx
	if fx != null:
		fx.show_fx(BURST_FX, player.global_position)
	Sfx.play(REST_CUE, player.global_position)
	if player.dead:
		data.at = _place_of(spawn_point(shrine))
	else:
		data.at = _place_of(player.global_transform)
	_note_bars()
	world_reset.emit()
	rested.emit(shrine.id)
	save_now()


## Whether the world remembers `name`.
func flag(flag_name: StringName) -> bool:
	return data.memory.has(flag_name)


## Remembers `name`: announced (`world_changed`) the first time only, and the game saved.
func set_flag(flag_name: StringName) -> void:
	if _remember(flag_name):
		save_now()


## Stands him up at the shrine he last rested at, with full bars, and puts the foes back; he is up when his getup is over.
func respawn() -> void:
	_death_frames = -1
	world_reset.emit()
	player.runner.stop()
	player.revive(spawn_point(rest_shrine()))
	data.at = {}
	data.bars = {}
	_snap_camera()
	respawned.emit()
	save_now()


## Where he stands up at `shrine`.
func spawn_point(shrine: ShrineDef) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(shrine.respawn_yaw_deg)), shrine.respawn)


## Writes the game (his bars as they are now, if there is a place saved with them). OK when there is no store, or the store may
## not use its folder; otherwise the error of the write, and the game stays "changed" so that the next autosave tries again.
func save_now() -> Error:
	if not data.at.is_empty():
		_note_bars()
	var written := OK if store == null else store.write(data)
	_since_save = 0
	if written == OK:
		_dirty = false
		_written_at = data.at.duplicate()
	return written


## A hash of the stretch as it stands: the physics frames lived, the player and every actor under the region in tree order (its
## position to the millimetre, HP, posture and stamina to a tenth, the id of its move), the shrine he rests at and the flags
## sorted. Equal sessions hash equal; a replay that goes wrong shows where it first differed. Not where he last stood: that is
## the file's, and a recorded session never reads or writes a file.
func state_hash() -> int:
	var parts: Array = [_lived]
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor == null or not (region.is_ancestor_of(actor) or actor == player) or actor.stats == null:
			continue
		var at := actor.global_position
		parts.append_array([roundi(at.x * 1000.0), roundi(at.y * 1000.0), roundi(at.z * 1000.0),
				roundi(actor.stats.hp * 10.0), roundi(actor.stats.posture * 10.0), roundi(actor.stats.stamina * 10.0),
				String(actor.runner.current.id) if actor.runner.current != null else ""])
	parts.append(String(data.rest_shrine))
	for flag_name in data.memory.names():
		parts.append(String(flag_name))
	return parts.hash()


## Whether this is a place worth coming back to: he is alive, on the floor, in no move, not frozen by a blow, not in a paired
## move, and no living foe of the other team is within SAFE_DISTANCE of him. (Where foes sleep, this will say "awake".)
func is_safe() -> bool:
	if player.dead or not player.is_on_floor() or player.runner.current != null or player.frozen > 0 or player.paired_with != null:
		return false
	return not _foe_near()


func _physics_process(_delta: float) -> void:
	_lived += 1
	if Game.play_frames == _counted:
		return  # a frame of no play (a pause, a scene): nothing counts
	_counted = Game.play_frames
	data.play_frames += 1
	if _death_frames >= 0:
		_death_frames += 1
		if _death_frames >= roundi(DEATH_DELAY * Engine.physics_ticks_per_second):
			respawn()
	if Game.play_frames % NOTE_EVERY == 0 and is_safe():
		_note_place()
	_since_save += 1
	if _since_save >= autosave_frames:
		if _dirty:
			save_now()
		else:
			_since_save = 0


# The game is left (the region goes, the game ends): what was played is kept.
func _exit_tree() -> void:
	if store != null and _lived > 0:
		save_now()


# Puts the player where the saved game says, or at the rest shrine, with the bars he had (or full ones).
func _place_player() -> void:
	var spot := spawn_point(rest_shrine())
	var loaded := false
	if not data.at.is_empty():
		var point := Vector3(data.at.x, data.at.y, data.at.z)
		if StretchGround.stands(region, point):
			spot = Transform3D(Basis(Vector3.UP, deg_to_rad(fposmod(float(data.at.yaw), 360.0))), point)
			loaded = true
	if player.dead:
		player.revive(spot)
	else:
		player.place(spot)
		player.stats.refill()
	var bars := data.bars
	if not bars.is_empty():
		_apply_bars(bars)
	if loaded:
		_note_bars()
	else:
		data.at = {}
		data.bars = {}
		_written_at = {}
	_snap_camera()


# Gives the player `bars` (shares of full, from the file): HP at least 1 (a saved game never loads dead), and able to act.
func _apply_bars(bars: Dictionary) -> void:
	var stats := player.stats
	stats.hp = minf(maxf(1.0, float(bars.hp) * stats.max_hp), stats.max_hp)
	stats.stamina = float(bars.stamina) * stats.max_stamina
	stats.posture = float(bars.posture) * stats.max_posture
	stats.exhausted = false
	stats.posture_broken = false


# Notes where he stands as the place to come back to; it is a change for the autosave only when it is a different place.
func _note_place() -> void:
	var place := _place_of(player.global_transform)
	if _moved(_written_at, place):
		_dirty = true
	data.at = place
	_note_bars()


# His bars as shares of full.
func _note_bars() -> void:
	var stats := player.stats if is_instance_valid(player) else null
	if stats == null or stats.max_hp <= 0.0:
		return
	data.bars = {
		hp = clampf(stats.hp / stats.max_hp, 0.0, 1.0),
		stamina = clampf(stats.stamina / maxf(stats.max_stamina, 0.001), 0.0, 1.0),
		posture = clampf(stats.posture / maxf(stats.max_posture, 0.001), 0.0, 1.0),
	}


# `at` for a body at `transform`: its place to the millimetre and its facing in degrees, 0 to 360, to a tenth.
static func _place_of(transform: Transform3D) -> Dictionary:
	var face := transform.basis.z
	var yaw := snappedf(fposmod(rad_to_deg(atan2(face.x, face.z)), 360.0), 0.1)
	return {
		x = snappedf(transform.origin.x, 0.001),
		y = snappedf(transform.origin.y, 0.001),
		z = snappedf(transform.origin.z, 0.001),
		yaw = 0.0 if yaw >= 360.0 else yaw,
	}


# Whether `b` is a different place from `a` for the autosave: from nowhere to somewhere, half a metre, or fifteen degrees.
static func _moved(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() != b.is_empty()
	var from := Vector3(a.x, a.y, a.z)
	var to := Vector3(b.x, b.y, b.z)
	var turned := absf(wrapf(float(b.yaw) - float(a.yaw), -180.0, 180.0))
	return from.distance_to(to) >= MOVED_METRES or turned >= TURNED_DEGREES


# Whether a living foe of the other team is within SAFE_DISTANCE of the player, flat.
func _foe_near() -> bool:
	var here := Vector2(player.global_position.x, player.global_position.z)
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor == null or actor == player or actor.dead or actor.def == null or actor.def.team == player.def.team:
			continue
		if here.distance_to(Vector2(actor.global_position.x, actor.global_position.z)) <= SAFE_DISTANCE:
			return true
	return false


# Sets `flag_name` in the memory; true (and announced) the first time.
func _remember(flag_name: StringName) -> bool:
	if not data.memory.set_flag(flag_name):
		return false
	world_changed.emit(flag_name)
	return true


func _on_player_died() -> void:
	player_fell.emit()
	_death_frames = 0
	data.at = {}
	data.bars = {}
	save_now()


# The camera takes him where he stands now (a jump, not a drift across the stretch).
func _snap_camera() -> void:
	var rig := get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	if rig != null:
		rig.snap_now()


# --- Task 5: gates ---

# A door for each gate of the def, and a latch for each that has one (at the latch's centre; the doors and latches are children of the run).
func _make_gates() -> void:
	for gate_def in def.gates:
		var door := GateDoor.make(self, gate_def)
		gates.append(door)
		if gate_def.latch_radius > 0.0:
			var latch := Latch.new()
			latch.name = "Latch_%s" % gate_def.id
			latch.def = gate_def
			latch.door = door
			add_child(latch)
			latch.global_position = gate_def.latch_centre
