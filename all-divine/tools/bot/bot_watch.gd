class_name BotWatch
extends RefCounted
## What the combat bot calls a problem in the game it plays, checked once a physics frame (check). Each is said once.
##   soft-lock         an actor in one move longer than its clip's length plus a second, counted on its own clock (the frames it
##                     spent frozen, by hit-stop or the slow-down, do not count); the player able to do nothing, no move and no
##                     step, for stuck_frames while he is alive and free; no wave started or cleared for progress_frames (only once
##                     the bot says there are waves, note_progress)
##   broken encounter  an actor outside `bounds` (the yard's walls) or below `floor_y`; a foe with an enemy brain that has not
##                     engaged within engage_frames of being first seen
## The numbers are in physics frames at 60 a second: 10 s, 90 s and 15 s. A move's charge holds are short (a few frames) and are
## in the second it is given.

## The ground the fight is in, as a rect of the ground plane (x, z): the yard's 25 m inside its walls, and a half metre.
var bounds := Rect2(-13.0, -13.0, 26.0, 26.0)
## How many deaths in one wave, with none of it cleared between, make a finding (not a failure: a wave a policy cannot beat is
## something to know, and its replay to look at).
var deaths_limit := 5
## An actor below this is through the floor.
var floor_y := -5.0
## A move may last its clip and this many frames more.
var slack_frames := 60
## The player is stuck after this many frames of doing nothing while alive.
var stuck_frames := 600
## The fight is stuck after this many frames with no wave started or cleared.
var progress_frames := 5400
## A foe has this many frames to engage.
var engage_frames := 900

var _moves := {}  # actor id -> [the move, its actor's buffer_frame when it started]
var _said := {}  # a problem's key -> true
var _first_seen := {}  # actor id -> the frame it was first seen on
var _engaged := {}  # actor id -> true
var _last_position := Vector3.INF  # the player's, last frame
var _idle := 0  # frames the player has done nothing
var _started_this_frame := false  # the player started a move since the last check
var _watched := {}  # actor id -> true, the actors whose runner it listens to
var _deaths := {}  # wave index -> deaths in it since it was last cleared
var _progress_at := -1  # the frame a wave last started or was cleared; -1 until the bot says there are waves


## A wave started or was cleared on `frame`.
func note_progress(frame: int) -> void:
	_progress_at = frame


## Looks at the game as it stands on `frame` (the bot's count): the player, and `actors`, every actor of the fight (the player
## among them). Returns the problems that are new, each a line without the frame (the bot puts "bot: seed S frame F: " on it).
func check(frame: int, player: Actor, actors: Array) -> PackedStringArray:
	var found := PackedStringArray()
	for node: Variant in actors:
		var actor := node as Actor
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree() or actor.dead:
			continue
		_watch(actor, player)
		_check_move(actor, found)
		_check_place(actor, found)
		if actor != player:
			_check_engaged(actor, frame, found)
	_check_player(frame, player, found)
	if _progress_at >= 0 and frame - _progress_at > progress_frames:
		_say("progress", "no wave started or cleared for %d frames (%d s)" % [frame - _progress_at, (frame - _progress_at) / 60], found)
	return found


func _say(key: String, text: String, found: PackedStringArray) -> void:
	if _said.has(key):
		return
	_said[key] = true
	found.append(text)


# Listens to the actor's moves starting (a move restarted by itself is a new move, which the move on the runner alone would not say).
func _watch(actor: Actor, player: Actor) -> void:
	var id := actor.get_instance_id()
	if _watched.has(id):
		return
	_watched[id] = true
	_first_seen[id] = -1
	actor.runner.move_started.connect(func(move: MoveData) -> void:
		_moves[id] = [move, actor.buffer_frame]
		if actor == player:
			_started_this_frame = true)
	if actor.runner.current != null:
		_moves[id] = [actor.runner.current, actor.buffer_frame]


func _check_move(actor: Actor, found: PackedStringArray) -> void:
	var move := actor.runner.current
	var id := actor.get_instance_id()
	if move == null or not _moves.has(id):
		return
	var started: Array = _moves[id]
	if not actor.rig.tree.has_animation(move.clip):
		return
	var clip_frames := ceili(actor.rig.tree.get_animation(move.clip).length * 60.0)
	var lived: int = actor.buffer_frame - int(started[1])
	if lived > clip_frames + slack_frames:
		_say("move %d %s" % [id, move.id], "%s has been in %s for %d frames of its own clock (its clip is %d)" % [actor.name, move.id, lived, clip_frames], found)


func _check_place(actor: Actor, found: PackedStringArray) -> void:
	var at := actor.global_position
	if not bounds.has_point(Vector2(at.x, at.z)):
		_say("outside %d" % actor.get_instance_id(), "%s is outside the yard at (%.1f, %.1f)" % [actor.name, at.x, at.z], found)
	if at.y < floor_y:
		_say("below %d" % actor.get_instance_id(), "%s is below the floor at y = %.1f" % [actor.name, at.y], found)


func _check_engaged(foe: Actor, frame: int, found: PackedStringArray) -> void:
	var brain := foe.brain as EnemyBrain
	if brain == null:
		return
	var id := foe.get_instance_id()
	if _first_seen[id] < 0:
		_first_seen[id] = frame
	if brain.mode == EnemyBrain.Mode.ENGAGED or brain.mode == EnemyBrain.Mode.ATTACKING or brain.mode == EnemyBrain.Mode.RETREATING:
		_engaged[id] = true
	if not _engaged.has(id) and frame - int(_first_seen[id]) > engage_frames:
		_say("engage %d" % id, "%s never engages: %d frames since it was first seen" % [foe.name, frame - int(_first_seen[id])], found)


func _check_player(_frame: int, player: Actor, found: PackedStringArray) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var free := not player.dead and player.paired_with == null
	var moved := _last_position == Vector3.INF or player.global_position.distance_to(_last_position) > 0.005
	_last_position = player.global_position
	if not free or moved or _started_this_frame:
		_idle = 0
	else:
		_idle += 1
	_started_this_frame = false
	if _idle > stuck_frames:
		_say("player", "the player has done nothing for %d frames (%d s) while alive" % [_idle, _idle / 60], found)


## The player died in wave `wave`. Returns a line when this is the death that makes a finding (the deaths_limit-th in the wave since
## it was last cleared), once; "" otherwise.
func note_death(wave: int) -> String:
	_deaths[wave] = int(_deaths.get(wave, 0)) + 1
	if int(_deaths[wave]) != deaths_limit:
		return ""
	var words := ["no", "one", "two", "three", "four", "five"]
	return "wave %d was not cleared in %s deaths" % [wave, words[deaths_limit] if deaths_limit < words.size() else str(deaths_limit)]


## Wave `wave` was cleared: its deaths are counted afresh.
func note_cleared(wave: int) -> void:
	_deaths.erase(wave)


## The walkable ground of `arena` as a rect of the ground plane (x, z), found where the walls are: rays along the four directions from
## its spawn, at the height of a kerb's foot, against the world layer, and a half metre beyond what they meet. Where one meets nothing
## the rect runs 100 m that way. The arena must be in the tree, with a physics frame lived.
static func bounds_of(arena: Node3D) -> Rect2:
	var space := arena.get_world_3d().direct_space_state
	var from := arena.global_position
	if arena is Region:
		from = (arena as Region).spawn().origin
	from.y += 0.15
	var reach := {}
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var to := from + Vector3(dir.x, 0.0, dir.y) * 100.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD))
		var far: Vector3 = hit["position"] if not hit.is_empty() else to
		reach[dir] = Vector2(far.x, far.z)
	var margin := 0.5
	return Rect2(Vector2(reach[Vector2.LEFT].x - margin, reach[Vector2.UP].y - margin),
			Vector2(reach[Vector2.RIGHT].x - reach[Vector2.LEFT].x + 2.0 * margin, reach[Vector2.DOWN].y - reach[Vector2.UP].y + 2.0 * margin))
