class_name MoveRunner
extends Node
## Plays an actor's moves. A move is a clip and the marks on it (moves/marks.gd): the runner keeps the
## move's gameplay time, and as that time passes a mark it acts on it, so hitboxes, invulnerability,
## hyper-armour and cancel windows follow the clip to the frame, at any frame rate and any delta.
## Presses come through the actor's InputBuffer, so one made up to 9 frames early (not counting frames of hit-stop)
## comes out on the first frame it can: when a cancel window that takes it opens, or when the actor is free again.
## An attack or a dodge also needs stamina (Stats.can_act): a press it cannot pay for is used up and nothing starts,
## and a move that starts spends its stamina_cost on that frame. A palm press with a broken foe in reach starts the
## actor's finisher instead of the move it asked for (Actor.start_finisher_on), from rest and from a cancel window
## alike, so a riposte can finish.
##
## A shared reaction's cancel window (a flinch's) opens only into the actor's own moves (window_of).
##
## A move with a strike_distance started with the intent's `warp` (an enemy's combo blow) is warped toward the intent's
## aim_target: over its wind-up (up to its first hitbox_on) it travels further or less along its facing than its clip's
## own root travel, so that the target stands where the blow was made to meet it (strike_distance from where it started,
## less its own travel by the blow). The warp is aimed again on every tick of the wind-up at where the target stands then,
## the rest of it spread over the wind-up left, so a target that walks in or out meanwhile is met too; in all it is
## MAX_WARP at most either way, and never so far that the body would pass the target's (BodySpacing still stops it).
##
## A dodge is the stick's too: a move with a `neutral_variant` (the roll's hop) starts that variant instead when the
## intent's stick is at rest, from rest and from a cancel window alike. The variant is checked as the move that was
## asked for (a hop is refused where a roll would be) and spends its own stamina_cost.
##
## A move can be charged. At a charge_hold mark, if the player is holding the mark's action, the clip stops at the
## mark (its time stands still, so the pose holds) until the action is let go, or the mark's `frames` have passed:
## then the move is charged (`charge_profile` is the mark's `profile`, which every hitbox_on after it uses in place of
## its own, and `charged` is emitted). Let go early, the blow goes out as if there had been no hold. A move that ends
## or is cancelled loses its charge, and so does a flinch, which cancels it.
##
## The actor's child MoveRunner; Actor._ready sets `actor`, and the actor calls tick() once per physics
## frame (nothing here runs by itself). Moves are looked up by id in the Registry. The runner tells the
## actor's rig what to show, and the actor's HitScanner when a hitbox comes on (with the profile its mark
## names) and goes off; every activation ends when its move does. It returns the move's root motion as a
## velocity for the actor to move by. A pair_hit mark is only passed on (`mark`): the Pairing the actor is in lands it.

signal move_started(move: MoveData)
## `cancelled` is true when another move took over before the clip's end.
signal move_ended(move: MoveData, cancelled: bool)
## The move's charge has filled: the whole hold of its charge_hold mark was held. Whoever shows a charge (ActorFx)
## listens here.
signal charged(move: MoveData)
## Every mark the move passes, in clip order, after the runner has acted on it (turned the hitbox on,
## opened the window, ...). Effects, sounds, shakes and hit-stops are only this signal: whoever plays
## them listens here.
signal mark(kind: StringName, args: Dictionary)

## The first pass over a move's marks starts here, below 0, so the marks at time 0 are met
## (Marks.between is half-open: it leaves out its start).
const BEFORE_START := -1.0
## How far (metres) a warped move may travel further or less than its clip's own root travel.
const MAX_WARP := 0.3

var actor: Actor

## The move playing, or null.
var current: MoveData
## Seconds into the current move.
var time := 0.0
var iframes := false
var hyperarmour := false
## True between a parry_on and a parry_off mark: a blow judged now is turned back (Combat.resolve, rule 4). A move
## with a parry window that starts less than the tuning's parry_refresh_frames after the last one did (counted on the
## actor's buffer_frame clock, so hit-stop does not count) passes its parry_on without opening it.
var parry_window := false
## True between a guard_on and a guard_off mark: the move holds a guard up (guard_raise from its f4).
var guard_window := false
## True between an airborne_on and an airborne_off mark: the body is off the ground (the hop), so a LOW blow passes
## under it (Defense.airborne) and the feet are not planted (Rig.airborne, which this sets).
var airborne := false
## The open cancel window: action -> the id of the move it cancels into. Empty while closed.
var window := {}
var in_recovery := false
## True while the clip stands at a charge_hold mark for the player holding its action.
var charging := false
## The HitProfile name the move's hitboxes carry, in place of the one their marks name, once it has charged;
## &"" until then.
var charge_profile := &""

var _anim: Animation  # the current move's clip
var _marks: Array[Dictionary] = []  # its marks (Marks.read)
var _root_track := -1  # its root position track, or -1 when the move has no root motion
var _hitboxes_on: Array[StringName] = []  # the hitboxes the current move has turned on
var _charge_args := {}  # the arguments of the charge_hold mark being held at
var _charge_left := 0.0  # seconds of the hold still to go
var _aim_until := -1.0  # the time of the current move's first hitbox_on, where aim assist stops turning the body; -1 if it has none
var _track_until := -1.0  # the time of its last hitbox_off, where a lock-on's tracking stops
var _parry_started := -1  # the actor's buffer_frame when the last move with a parry window started; -1 before any
var _parry_fresh := true  # whether the current move's parry_on opens its window (see parry_window)
var _warp := 0.0  # the extra travel along the facing the current move has made so far in its wind-up (metres; see the top)
var _warping := false  # whether the current move is warped
var _strike_at_hit := 0.0  # where the target should stand from the body when the warped blow lands (metres)


## True while a move plays.
func busy() -> bool:
	return current != null


## Starts `move` now, cancelling the current one if there is one. The marks at time 0 fire at once. An attack or a
## dodge is refused while the actor cannot act (Stats.can_act): nothing changes. With `force` it starts whatever the
## stamina, as both moves of a paired move do.
func start(move: MoveData, force := false) -> void:
	_start(move, null, force)


## One physics frame: turns an attacking body toward the intent's aim_target (see _aim), advances the current
## move by `delta` (not while a charge is held) and acts on the marks it passes, starts the move a buffered press
## asks for (into an open cancel window, or from rest), and ends the move at its clip's end. Returns the
## root-motion velocity: the clip's root travel over this frame (horizontal, times the move's root_motion_scale,
## turned with the body) divided by `delta`.
func tick(intent: Intent, delta: float) -> Vector3:
	var velocity := Vector3.ZERO
	if current != null:
		_aim(intent, delta)
		if charging:
			_keep_charging(intent, delta)
		if not charging:
			var move := current
			var before := time
			time += delta
			var hold := _hold_between(before, time, intent)
			if not hold.is_empty():
				time = hold["time"]
			velocity = _root_velocity(before, time, delta) + _warp_velocity(intent, before, time, delta)
			actor.rig.set_move_time(time)
			_pass_marks(before, time)
			if not hold.is_empty() and current == move:
				_begin_charge(hold["args"])
	if current != null and not window.is_empty():
		var action := actor.buffer.consume(window.keys(), actor.buffer_frame)
		if action != &"" and not actor.start_finisher_on(action):
			_start(_fetch(window[action]), intent)
	if current != null and time >= _anim.length - Marks.EPSILON:
		_end(false)
	if current == null:
		var action := actor.buffer.consume(actor.def.moveset.keys(), actor.buffer_frame)
		if action != &"" and not actor.start_finisher_on(action):
			_start(_fetch(actor.def.moveset[action]), intent)
	return velocity


# Starts `move`, unless it is an attack or a dodge, the actor cannot act (no stamina, or exhausted) and it is not
# `force`d: then nothing changes, a move that plays goes on, and the press that asked is gone, since the callers have
# consumed it. A dodge with the stick pushed (`intent` from this frame, or null) faces the stick at once. With the
# stick at rest, a move's neutral variant starts in its place, once the move asked for has passed the stamina gate.
func _start(move: MoveData, intent: Intent, force := false) -> void:
	if move == null:
		push_error("MoveRunner: no move to start on '%s'" % actor.name)
		return
	if (move.kind == MoveData.Kind.ATTACK or move.kind == MoveData.Kind.DODGE) and not force and not actor.stats.can_act():
		return
	if move.neutral_variant != &"" and intent != null and intent.move.length() == 0.0:
		var variant := _fetch(move.neutral_variant)
		if variant == null:
			push_error("MoveRunner: move '%s' has the unknown neutral variant '%s'" % [move.id, move.neutral_variant])
			return
		move = variant
	var rig := actor.rig
	if not rig.tree.has_animation(move.clip):
		push_error("MoveRunner: '%s' has no clip '%s' for move '%s'" % [actor.name, move.clip, move.id])
		return
	if move.stamina_cost > 0.0:
		actor.stats.spend_stamina(move.stamina_cost)
	if current != null:
		_end(true)
	current = move
	time = 0.0
	_anim = rig.tree.get_animation(move.clip)
	_marks = Marks.read(_anim)
	if _marks.any(func(m: Dictionary) -> bool: return m["kind"] == &"parry_on"):
		_parry_fresh = _parry_started < 0 or actor.buffer_frame - _parry_started >= actor.stats.tuning.parry_refresh_frames
		_parry_started = actor.buffer_frame
	_root_track = _anim.find_track(rig.tree.root_motion_track, Animation.TYPE_POSITION_3D) if move.root_motion else -1
	_aim_until = -1.0
	_track_until = -1.0
	for m in _marks:
		if m["kind"] == &"hitbox_on" and _aim_until < 0.0:
			_aim_until = m["time"]
		elif m["kind"] == &"hitbox_off":
			_track_until = m["time"]
	_begin_warp(move, intent)
	rig.play_move(move.clip, move.blend_in)
	if move.kind == MoveData.Kind.DODGE and intent != null and intent.move.length() > 0.0:
		actor.snap_facing(Locomotion.yaw_of(intent.move))
	move_started.emit(move)
	_pass_marks(BEFORE_START, 0.0)


# Ends the current move: what its marks turned on is turned off (its hitboxes' activations end with it), the
# window closes, and the rig fades back to locomotion unless another move is taking over (`cancelled`), which
# crossfades by itself.
func _end(cancelled: bool) -> void:
	var ended := current
	for id in _hitboxes_on:
		actor.rig.set_hitbox_active(id, false)
		actor.scanner.end(id)
	_hitboxes_on.clear()
	iframes = false
	hyperarmour = false
	parry_window = false
	guard_window = false
	_set_airborne(false)
	window = {}
	in_recovery = false
	current = null
	time = 0.0
	_anim = null
	_marks = []
	_root_track = -1
	_aim_until = -1.0
	_track_until = -1.0
	_warp = 0.0
	_warping = false
	charging = false
	charge_profile = &""
	_charge_args = {}
	if not cancelled:
		actor.rig.stop_move(ended.blend_out)
	move_ended.emit(ended, cancelled)


# Aim assist and lock-on: while an attack that aims winds up (its time is before its first hitbox_on, or, when the
# intent tracks, before its last hitbox_off), the body turns toward the intent's aim_target at the tuning's
# aim_turn_rate_deg. Only the ground plane counts. Run before the clip's root motion is read, so a lunge goes where
# the body now faces. It does not run on the frame a move starts (the move has no time yet) but on the next, and
# it runs on every tick of a charge's hold, since the clip's time stands before the hitbox.
func _aim(intent: Intent, delta: float) -> void:
	if current.kind != MoveData.Kind.ATTACK or not current.aim or not intent.aim_target is Vector3:
		return
	var until := _track_until if intent.track else _aim_until
	if time >= until - Marks.EPSILON:
		return
	var point: Vector3 = intent.aim_target
	var to := Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z)
	if to.is_zero_approx():
		return
	var step := deg_to_rad(actor.stats.tuning.aim_turn_rate_deg) * delta
	actor.snap_facing(Locomotion.turn_toward(actor.locomotion.facing_yaw, Locomotion.yaw_of(to), step))


# The charge_hold mark in t0 < time <= t1 that stops the clip this tick: the first one whose action is held. Empty
# if there is none (an action let go passes its mark as if it were not there).
func _hold_between(t0: float, t1: float, intent: Intent) -> Dictionary:
	for m: Dictionary in Marks.between(_marks, t0, t1):
		if m["kind"] == &"charge_hold" and intent.held.has(StringName(m["args"].get("action", &""))):
			return m
	return {}


# The clip has reached the charge_hold mark with `args`, and the player holds its action: stand at it. The frame it
# arrived on is the first of `frames` the clip stands there.
func _begin_charge(args: Dictionary) -> void:
	charging = true
	_charge_args = args
	_charge_left = float(args.get("frames", 0)) / Marks.RATE


# A tick of the hold: counts it off, and ends it when the action is let go (the clip goes on from this tick) or when
# the whole of it has been held (the move is charged, and goes on from this tick too).
func _keep_charging(intent: Intent, delta: float) -> void:
	_charge_left -= delta
	if _charge_left <= Marks.EPSILON:
		charging = false
		charge_profile = StringName(_charge_args.get("profile", &""))
		charged.emit(current)
	elif not intent.held.has(StringName(_charge_args.get("action", &""))):
		charging = false


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
			actor.scanner.begin(id, charge_profile if charge_profile != &"" else StringName(args.get("profile", &"")), current)
			if not _hitboxes_on.has(id):
				_hitboxes_on.append(id)
		&"hitbox_off":
			var id := StringName(args.get("id", &""))
			actor.rig.set_hitbox_active(id, false)
			actor.scanner.end(id)
			_hitboxes_on.erase(id)
		&"iframes_on":
			iframes = true
		&"iframes_off":
			iframes = false
		&"hyperarmour_on":
			hyperarmour = true
		&"hyperarmour_off":
			hyperarmour = false
		&"parry_on":
			parry_window = _parry_fresh
		&"parry_off":
			parry_window = false
		&"guard_on":
			guard_window = true
		&"guard_off":
			guard_window = false
		&"airborne_on":
			_set_airborne(true)
		&"airborne_off":
			_set_airborne(false)
		&"cancel_open":
			var into: Variant = args.get("into", {})
			window = window_of(current, into, actor.def) if into is Dictionary else {}
		&"cancel_close":
			window = {}
		&"recovery":
			in_recovery = true
	mark.emit(kind, args)


# Lifts the body off the ground or sets it down: the runner's flag, and the rig's, which keeps the feet from planting.
func _set_airborne(value: bool) -> void:
	airborne = value
	actor.rig.airborne = value


# The root's travel from t0 to t1 of the current clip as a world velocity on the ground plane.
func _root_velocity(t0: float, t1: float, delta: float) -> Vector3:
	if _root_track < 0 or delta <= 0.0:
		return Vector3.ZERO
	return _root_travel(t0, t1) / delta


# The current clip's root travel from t0 to t1, in the world on the ground plane (times the move's root_motion_scale).
func _root_travel(t0: float, t1: float) -> Vector3:
	var length := _anim.length
	var from := _anim.position_track_interpolate(_root_track, clampf(t0, 0.0, length))
	var to := _anim.position_track_interpolate(_root_track, clampf(t1, 0.0, length))
	# The track is in the skeleton's space; its global basis is the body's facing (and the model's own
	# placement under it, which is none for Abarax).
	var travel := actor.rig.skeleton.global_basis * ((to - from) * current.root_motion_scale)
	travel.y = 0.0
	return travel


# The clip's own root travel from t0 to t1 toward where the body faces (metres; 0 for a move without root motion).
func _own_travel(t0: float, t1: float) -> float:
	if _root_track < 0:
		return 0.0
	var facing := actor.facing()
	return _root_travel(t0, t1).dot(Vector3(facing.x, 0.0, facing.z).normalized())


# Whether `move` started with `intent` is warped (see the top), and where the target should stand when its blow lands.
func _begin_warp(move: MoveData, intent: Intent) -> void:
	_warp = 0.0
	_warping = intent != null and intent.warp and move.strike_distance > 0.0 and _aim_until > 0.0
	if _warping:
		_strike_at_hit = move.strike_distance * actor.def.model_scale - _own_travel(0.0, _aim_until)


# The warp's travel over t0 to t1 of the wind-up as a world velocity (see the top): the rest of the warp the target needs
# now, kept within MAX_WARP in all and short of body contact, spread over what is left of the wind-up.
func _warp_velocity(intent: Intent, t0: float, t1: float, delta: float) -> Vector3:
	if not _warping or delta <= 0.0 or t0 >= _aim_until - Marks.EPSILON or not intent.aim_target is Vector3:
		return Vector3.ZERO
	var point: Vector3 = intent.aim_target
	var distance := Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z).length()
	var own_left := _own_travel(t0, _aim_until)
	var contact := actor.spacing.radius() * 2.0 if actor.spacing != null else 0.0
	var wanted := clampf(_warp + distance - own_left - _strike_at_hit, -MAX_WARP, MAX_WARP)
	wanted = minf(wanted, _warp + distance - own_left - contact)
	var step := (wanted - _warp) * (minf(t1, _aim_until) - t0) / (_aim_until - t0)
	_warp += step
	var facing := actor.facing()
	return Vector3(facing.x, 0.0, facing.z).normalized() * step / delta


## The cancel window a cancel_open mark of `move` opens for an actor of `def`, from the mark's `into` (action -> move id).
## A move the actor plays as one of its reactions (one its def's `reactions` names: a flinch, a stagger, a guard_hit) is
## shared by every actor, and its clip's windows name the moves of the actor it was made on (Abarax's roll and jab). So
## such a window opens only for the actions whose move in it is the actor's own for that action (its moveset's): a
## Knuckle plays out a flinch whose window would roll it with Abarax's roll. Any other move's window is `into` as it is.
## The clip checker follows cancels by the same rule.
static func window_of(move: MoveData, into: Dictionary, def: ActorDef) -> Dictionary:
	if not def.reactions.values().has(move.id):
		return into.duplicate()
	var open := {}
	for action: Variant in into:
		if def.moveset.get(action, &"") == StringName(str(into[action])):
			open[action] = into[action]
	return open


func _fetch(id: Variant) -> MoveData:
	return Registry.fetch(&"moves", StringName(id)) as MoveData
