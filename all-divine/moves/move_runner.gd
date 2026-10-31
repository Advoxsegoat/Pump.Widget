class_name MoveRunner
extends Node
## Plays an actor's moves. A move is a clip and the marks on it (moves/marks.gd): the runner keeps the
## move's gameplay time, and as that time passes a mark it acts on it, so hitboxes, invulnerability,
## hyper-armour and cancel windows follow the clip to the frame, at any frame rate and any delta.
## Presses come through the actor's InputBuffer, so one made up to 9 frames early comes out on the first
## frame it can: when a cancel window that takes it opens, or when the actor is free again.
##
## The actor's child MoveRunner; Actor._ready sets `actor`, and the actor calls tick() once per physics
## frame (nothing here runs by itself). Moves are looked up by id in the Registry. The runner tells the
## actor's rig what to show and returns the move's root motion as a velocity for the actor to move by.

signal move_started(move: MoveData)
## `cancelled` is true when another move took over before the clip's end.
signal move_ended(move: MoveData, cancelled: bool)
## Every mark the move passes, in clip order, after the runner has acted on it (turned the hitbox on,
## opened the window, ...). Effects, sounds, shakes and hit-stops are only this signal: whoever plays
## them listens here.
signal mark(kind: StringName, args: Dictionary)

## The first pass over a move's marks starts here, below 0, so the marks at time 0 are met
## (Marks.between is half-open: it leaves out its start).
const BEFORE_START := -1.0

var actor: Actor

## The move playing, or null.
var current: MoveData
## Seconds into the current move.
var time := 0.0
var iframes := false
var hyperarmour := false
## The open cancel window: action -> the id of the move it cancels into. Empty while closed.
var window := {}
var in_recovery := false

var _anim: Animation  # the current move's clip
var _marks: Array[Dictionary] = []  # its marks (Marks.read)
var _root_track := -1  # its root position track, or -1 when the move has no root motion
var _hitboxes_on: Array[StringName] = []  # the hitboxes the current move has turned on


## True while a move plays.
func busy() -> bool:
	return current != null


## Starts `move` now, cancelling the current one if there is one. The marks at time 0 fire at once.
func start(move: MoveData) -> void:
	_start(move, null)


## One physics frame: advances the current move by `delta` and acts on the marks it passes, starts the
## move a buffered press asks for (into an open cancel window, or from rest), and ends the move at its
## clip's end. Returns the root-motion velocity: the clip's root travel over this frame (horizontal,
## times the move's root_motion_scale, turned with the body) divided by `delta`.
func tick(intent: Intent, delta: float) -> Vector3:
	var velocity := Vector3.ZERO
	if current != null:
		var before := time
		time += delta
		velocity = _root_velocity(before, time, delta)
		actor.rig.set_move_time(time)
		_pass_marks(before, time)
	if current != null and not window.is_empty():
		var action := actor.buffer.consume(window.keys(), actor.frame)
		if action != &"":
			_start(_fetch(window[action]), intent)
	if current != null and time >= _anim.length - Marks.EPSILON:
		_end(false)
	if current == null:
		var action := actor.buffer.consume(actor.def.moveset.keys(), actor.frame)
		if action != &"":
			_start(_fetch(actor.def.moveset[action]), intent)
	return velocity


# Starts `move`. A dodge with the stick pushed (`intent` from this frame, or null) faces the stick at once.
func _start(move: MoveData, intent: Intent) -> void:
	if move == null:
		push_error("MoveRunner: no move to start on '%s'" % actor.name)
		return
	var rig := actor.rig
	if not rig.tree.has_animation(move.clip):
		push_error("MoveRunner: '%s' has no clip '%s' for move '%s'" % [actor.name, move.clip, move.id])
		return
	if current != null:
		_end(true)
	current = move
	time = 0.0
	_anim = rig.tree.get_animation(move.clip)
	_marks = Marks.read(_anim)
	_root_track = _anim.find_track(rig.tree.root_motion_track, Animation.TYPE_POSITION_3D) if move.root_motion else -1
	rig.play_move(move.clip, move.blend_in)
	if move.kind == MoveData.Kind.DODGE and intent != null and intent.move.length() > 0.0:
		var yaw := Locomotion.yaw_of(intent.move)
		actor.locomotion.facing_yaw = yaw
		actor.rotation.y = yaw
	move_started.emit(move)
	_pass_marks(BEFORE_START, 0.0)


# Ends the current move: what its marks turned on is turned off, the window closes, and the rig fades
# back to locomotion unless another move is taking over (`cancelled`), which crossfades by itself.
func _end(cancelled: bool) -> void:
	var ended := current
	for id in _hitboxes_on:
		actor.rig.set_hitbox_active(id, false)
	_hitboxes_on.clear()
	iframes = false
	hyperarmour = false
	window = {}
	in_recovery = false
	current = null
	time = 0.0
	_anim = null
	_marks = []
	_root_track = -1
	if not cancelled:
		actor.rig.stop_move(ended.blend_out)
	move_ended.emit(ended, cancelled)


# Acts on the current move's marks with t0 < time <= t1, in order. Stops if a listener of `mark` started
# another move.
func _pass_marks(t0: float, t1: float) -> void:
	var move := current
	for m: Dictionary in Marks.between(_marks, t0, t1):
		_act(m["kind"], m["args"])
		if current != move:
			return


func _act(kind: StringName, args: Dictionary) -> void:
	match kind:
		&"hitbox_on":
			var id := StringName(args.get("id", &""))
			actor.rig.set_hitbox_active(id, true)
			if not _hitboxes_on.has(id):
				_hitboxes_on.append(id)
		&"hitbox_off":
			var id := StringName(args.get("id", &""))
			actor.rig.set_hitbox_active(id, false)
			_hitboxes_on.erase(id)
		&"iframes_on":
			iframes = true
		&"iframes_off":
			iframes = false
		&"hyperarmour_on":
			hyperarmour = true
		&"hyperarmour_off":
			hyperarmour = false
		&"cancel_open":
			var into: Variant = args.get("into", {})
			window = (into as Dictionary).duplicate() if into is Dictionary else {}
		&"cancel_close":
			window = {}
		&"recovery":
			in_recovery = true
	mark.emit(kind, args)


# The root's travel from t0 to t1 of the current clip as a world velocity on the ground plane.
func _root_velocity(t0: float, t1: float, delta: float) -> Vector3:
	if _root_track < 0 or delta <= 0.0:
		return Vector3.ZERO
	var length := _anim.length
	var from := _anim.position_track_interpolate(_root_track, clampf(t0, 0.0, length))
	var to := _anim.position_track_interpolate(_root_track, clampf(t1, 0.0, length))
	# The track is in the skeleton's space; its global basis is the body's facing (and the model's own
	# placement under it, which is none for Abarax).
	var travel := actor.rig.skeleton.global_basis * ((to - from) * current.root_motion_scale)
	travel.y = 0.0
	return travel / delta


func _fetch(id: Variant) -> MoveData:
	return Registry.fetch(&"moves", StringName(id)) as MoveData
