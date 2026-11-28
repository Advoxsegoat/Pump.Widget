class_name EnemyBrain
extends Brain
## An enemy's mind (spec §4.5), played from a BrainDef: perception, spacing, attack choice and reactions, a small state
## machine that wants things of its actor through an Intent each frame, as every brain does. All its dice are one
## RandomNumberGenerator seeded at the start, so a fight goes the same way every time.
##
## Its target is found on its own: the nearest live actor of the player's team (ActorDef.Team.PLAYER).
##   IDLE        it stands. When it perceives the target it is NOTICING: the target is in its sight cone (within
##               sight_range and half sight_fov_deg either side of its facing, nothing on the `world` layer between
##               their heads), or within hearing_range while it sprints or attacks, whichever way it faces
##   NOTICING    it turns to look. Perceived for notice_time in all (losing sight of it counts back down), it engages;
##               counted all the way back down, it is IDLE again
##   ENGAGED     it faces the target and keeps preferred_range ± range_tolerance from it: once out of that range it
##               walks in or backs off until it is SETTLE_WITHIN of preferred_range, and within it it circles at
##               circle_speed, easing toward preferred_range as it goes. When its spacing has got no nearer for reangle_after
##               seconds (Review Focus 5), or it has been blocked outright for BLOCKED_AFTER (a body or a wall in the
##               way: the stick pushed, the body going nowhere), it tries another angle: the circling turns the other
##               way and its heading swings 60 degrees that way, until it is back in its range. Circling that is blocked
##               turns the other way.
##               Off its rest (attack_rest after its last attack), it chooses an attack: it takes one of the target's
##               attack tokens (AttackTokens; none needed by a squad that ignores them, or for an option that needs
##               none; an option that holds more than one, AttackOption.tokens, is on the menu only while the tokens it
##               holds are free, and takes them when it is chosen, so no other enemy begins an attack on the target while
##               it is thrown, and it is thrown only while no other enemy holds one), picks by weight among the options
##               off cooldown that it may throw and that are on the menu at this range (it would back up no more than the option's back_up_margin: on_menu), and then closes or
##               backs off into that option's range (where the move really lands: AttackOption) and throws it once it
##               is there, square enough to the target (max_angle_deg) and slowed to a walk (PRESS_SPEED), checking
##               all three again at the press. It jogs in, braking to a walk over the last of it, and backs up at a
##               walk. One that cannot reach its range in twice reangle_after gives it up
##   ATTACKING   it presses the option's combo, each action as the cancel window that takes it opens; each blow is warped
##               toward the target (Intent.warp, MoveData.strike_distance), and when the target will stand beyond the
##               next blow's warped reach, or inside it (he stepped in and smothers it), the combo ends there rather
##               than swing at air. Its tier rolls,
##               when it chooses: a feint (dodge first, then the attack into the feint's window, if that window takes
##               it), a delayed swing (it holds the attack's action through its move's charge_hold for some of
##               delay_frames), one blow more (the combo's last action again). Its swings aim at the target through
##               their wind-up, and with track_dodges through their active frames too. When its moves are over it gives
##               the token back, and the option waits its cooldown
##   RETREATING  below retreat_below of its max HP (once each time it drops below) it turns and runs from the target for
##               regroup_time, then engages again
## A reaction (a flinch, a stagger, a parried or caught recoil) cuts its attack off: the token goes back. After a
## stagger, a parry or a catch it walks back one preferred_range before it does anything else.
##
## It is not asked while its actor is paired or dead (Actor), and it attacks no target that is dead or paired.

enum Mode { IDLE, NOTICING, ENGAGED, ATTACKING, RETREATING }

## It went from not fighting to fighting: once each time it goes from noticing (or being woken, or alarmed) to engaged.
signal engaged
## It walked home and is there (within HOME_ARRIVED of it).
signal arrived_home

## A foe that stands at a post (F3 systems Task 4). All of this is inert at its defaults, so the yard's foes are as they were:
## `home` is the post (a Vector3), or null for none; `leash` is how far from it, flat, it follows a target (metres); `asleep` is a
## brain that senses and does nothing until `wake` or `engage_now`. A foe with a home that stands down for any reason (past its
## leash, no target in reach, its target dead) and is further than HOME_ARRIVED from home walks home at the jog, ignoring the
## target, for at most HOME_GIVE_UP seconds, then stands at `home_facing` (a yaw in radians about +Y, or null) for a moment.
var home: Variant = null
var leash := INF
var asleep := false
var home_facing: Variant = null

## How far its heading swings when it re-angles.
const REANGLE_DEG := 60.0
## The stick: a jog to cover ground, a walk to settle into a range.
const JOG_PUSH := 1.0
const WALK_PUSH := 0.45
## Within this many metres of where it is going it walks rather than jogs (so it does not run past a narrow range).
const WALK_WITHIN := 1.5
## How strongly circling eases toward preferred_range, against going round (at the edge of its range: 1 is as much in as
## round).
const DRIFT := 0.5
## Out of its range, it goes back until it is this near preferred_range (metres), and only then circles.
const SETTLE_WITHIN := 0.15
## Closing in to an attack it brakes to a walk this much (metres) before its stopping distance says it must, and it
## presses only at this speed (m/s) or slower: a move stops the body dead, so one started from a jog slides its feet.
const BRAKE_MARGIN := 0.1
const PRESS_SPEED := 1.2
## Task 14f: foes spread round their target. A foe with another within SPREAD_DEG (seen from the target) circles away from it, and
## one who waits (no token to be had) stands in the outer half of his band, a body's width clear of the attackers' ring.
const SPREAD_DEG := 60.0
## A foe with a neighbour within SPREAD_DEG on both sides, the two gaps within EVEN_DEG of each other, stands his ground (he does not circle,
## which would be to choose between two equals on every frame); he goes on again when they differ by EVEN_DEG plus EVEN_MARGIN.
const EVEN_DEG := 10.0
const EVEN_MARGIN := 10.0
## Seconds a holder who is in his band but not his range may be held up (blocked, no way round) before he gives his token to a ready foe
## with a clear line to the target, and how long he rests after (he does not take it straight back).
const HAND_OVER_AFTER := 0.75
const HAND_OVER_REST := 0.5
## How near the straight line from a foe to the target a body may be before the line is not clear, metres, and how near the target the
## foe must be to be given a token.
const CLEAR_LINE := 0.5
const HAND_OVER_REACH := 4.0
## How far round, degrees, a foe's way in is swung away from a neighbour that close, and how near the ring (metres to go) that starts.
const SPREAD_SWING := 25.0
## A neighbour this close to a foe's own line to the target is in his way: only then is his way in swung round him.
const LINE_DEG := 30.0
const SPREAD_SWING_CLOSE := 75.0
## Once a neighbour is that close to his line, he stays "close" until the neighbour is this many degrees further off: the swing itself moves the
## bearings by about a degree a frame, and at the edge of LINE_DEG the swing was switching between its two sizes on every frame.
const LINE_MARGIN := 8.0
const SPREAD_REACH := 1.5
## Once swinging round a neighbour, a foe goes on until he is this much (metres) further from his range than SPREAD_REACH: the swing walks him
## away from it (against a wall, a step back each frame), and without the margin that step alone switched the swing off and on again.
const SPREAD_REACH_MARGIN := 0.3
## Task 15c: a foe begins an attack only when the world will not stop it (HitScanner.line_clear), and when it would, goes round to where it
## would not: to the nearest place, by a way a body can walk (a search on a grid of ROUND_CELL cells, _plan_round), that has a line to the target
## for a body ROUND_PAD either side of it. He walks the way (ROUND_GIVE_UP seconds at most, or until the target has moved ROUND_MOVED), then
## goes on as ever. Two ends about as near (ROUND_EVEN_CELLS): the one with room (the open side, as Task 14f's way round a neighbour).
## A swing round a neighbour is refused when a wall stands within ROOM_REACH (a stride) ahead on the way it takes a body ROOM_BODY wide, for NO_ROOM_FRAMES.
## The most the target's height may differ from his for the lines to a wall (see _same_level).
const LEVEL_GAP := 0.6
const ROOM_REACH := 0.8
const ROOM_BODY := 0.35
const NO_ROOM_FRAMES := 30
const ROUND_CELL := 0.6
const ROUND_RADIUS := 10.0
const ROUND_BODY := 0.35
## How far below his feet (metres) ground still counts as ground a body steps down to (a kerb, a stair): further is a drop, not a way.
const ROUND_STEP_DOWN := 0.5
const ROUND_EVEN_CELLS := 2
## A place within this many metres of where another foe stands or is going is crowded.
const ROUND_CROWD := 0.9
const ROUND_PAD := 0.3
const ROUND_REACHED := 0.15
const ROUND_GIVE_UP := 8.0
const ROUND_MOVED := 1.0
## The cells of search all the foes together may open on one physics frame (about 7 us each: a step's cost over the base stays under 1 ms), the
## frames a foe who found no way waits before he searches again (doubled with each failure, ROUND_BACK_OFF_DOUBLINGS times at most), and after
## how many frames of waiting he searches again though the target has not moved.
const ROUND_CELLS_PER_FRAME := 100
const ROUND_BACK_OFF := 60
const ROUND_BACK_OFF_DOUBLINGS := 2
const ROUND_RECHECK := 600
## After he has come round: no new search for ROUND_HOLD frames, and how far ahead (metres) a step is looked at for the line (COME_LOOK).
const ROUND_HOLD := 30
const COME_LOOK := 0.8
## How much further than an attack's back_up_margin (metres) a back-up may go before the attack is given up.
const BACK_UP_SPARE := 0.1
## How far beyond a warped blow's strike_distance and MoveRunner.MAX_WARP the target may stand when it lands and the combo
## go on: every Knuckle blow still lands at least this far past where it was made to meet it.
const WARP_SLACK := 0.1
## How much nearer than a warped blow's strike_distance less MoveRunner.MAX_WARP the target may stand when it lands and the
## combo go on (the hook still meets a target that much inside its warp; nearer, it swings past him).
const SMOTHER_SLACK := 0.25
## How hard it backs off after a stagger, a parry or a catch (a walk backward, 1 m/s: a jog would slingshot it out of
## the reach of the player who has just earned the opening), and how long it may take at most.
const BACK_OFF_PUSH := 0.5
const BACK_OFF_LIMIT := 2.6
## Its spacing counts as getting somewhere while the distance to its range shrinks by this much at least.
const PROGRESS := 0.05
## Going slower than this (m/s) with the stick pushed is being blocked (a body or a wall in the way): blocked for
## BLOCKED_AFTER seconds, circling turns the other way, and walking in or backing off tries another angle (re-angles).
const STALL_SPEED := 0.2
const BLOCKED_AFTER := 0.75
## Past this share of its sight_range it lets an engaged target go.
const LOSE_FACTOR := 2.0
## The reactions after which it backs off.
const BACK_OFF_AFTER: Array[StringName] = [&"stagger", &"parried", &"caught"]
## The action that, pressed with the stick at rest, starts the actor's feint (its moveset's `dodge`).
const FEINT_ACTION := &"dodge"
## A foe walking home is home within this many metres, and gives up the walk after this many seconds.
const HOME_ARRIVED := 0.6
const HOME_GIVE_UP := 8.0
## It turns to its post's facing for this long once it is home (the turn itself is the body's, at its own rate).
const HOME_TURN_SECONDS := 0.75

var def: BrainDef
var rng := RandomNumberGenerator.new()
## Who it fights: the nearest live actor of the player's team, found on its own.
var target: Actor
var mode: Mode = Mode.IDLE

var _noticed := 0.0  # seconds of perception built up while NOTICING
var _circle := 1.0  # which way it circles: 1 or -1
var _swing := 0.0  # radians its heading is swung by, after re-angling
var _failing := 0.0  # seconds its spacing (or approach) has got no nearer
var _best_error := INF  # the nearest it has come to its range since it last got nearer
var _blocked := 0.0  # seconds it has pushed the stick without getting anywhere
var _settling := false  # out of its range, going back to preferred_range
var _backed_up := 0.0  # metres it has backed up toward the chosen attack's range
var _backing_up_for := 0.0  # seconds it has done so
var _last_at := Vector3.INF  # where its actor stood when it last thought
var _speed := 0.0  # how fast its actor really went on the ground since then, m/s
var _plan: AttackOption  # the attack chosen, while it closes in and throws it
var _approach := 0.0  # seconds spent getting into its range
var _feint := false  # this attack starts with a feint
var _delay := 0  # frames to hold the attack's action at its charge_hold (0: no delay)
var _presses: Array[StringName] = []  # the actions still to press, each as a window takes it
var _press_count := 0  # how many presses of the attack it has made
var _holding := &""  # the action it holds for a delayed swing
var _held := 0  # frames the clip has stood at the charge while it held
var _hold_frames := 0  # frames it has held in all (a limit, should the charge never come)
var _cooldowns := {}  # AttackOption -> seconds before it can be chosen again
var _rest := -1.0  # seconds before it chooses an attack; -1 until it engages
var _backing := false  # backing off after a stagger, a parry or a catch
var _back_off_due := false  # one of those is playing: back off when it ends
var _back_from := Vector3.ZERO
var _back_time := 0.0
var _retreat_left := 0.0
var _retreated := false  # it retreated since its HP last went below retreat_below
var _feint_window := {}  # action -> whether the feint's window takes it (read from its clip once)
var _charge_holds := {}  # action -> whether its moveset move has a charge_hold on it (read from its clip once)
var _in_line := false  # a neighbour stands within LINE_DEG of his line, so the swing is the close one (see _spread_swing)
var _spreading := false  # swinging round a neighbour on the way in (see _spread_swing)
var _even := false  # between two neighbours at even gaps: standing his ground (see _away_from_neighbour)
var _held_up := 0.0  # seconds it has gone on toward its range and got no nearer than it has been, for the hand-over
var _nearest_yet := INF  # the nearest it has been to its target since it began to close in
var _round_to := Vector2.INF  # the waypoint he walks to for a line to his target (x, z), INF for none
var _round_path: Array[Vector2] = []  # the points after _round_to
var _no_room_until := -1  # the physics frame until which a swing round a neighbour is refused for want of room
var plans := 0  # how many ways round he has planned (a search begun), for a test and the report
var _search: RoundSearch  # a search for a way round that is not over (it goes on a few cells a frame: see _advance_search)
var _no_way := false  # no way to a line was found: he waits at the nearest place he can reach (see _wait_round)
var _plan_after := 0  # the physics frame before which a waiting foe does not search again
var _fails := 0  # searches in a row that found no way
var _come_round := false  # he has come round a wall and holds the lit ground (see _hold_lit)
var _come_at := Vector2.INF  # where the target stood when he came round
var _snagged := false  # blocked where a body could not walk the way in: _go_round plans a way though the line is clear
var _round_at := Vector2.INF  # where the target stood when it was found
var _round_for := 0.0  # seconds he has been going to it
var _clear_frame := -1  # the physics frame of _clear_cache
var _clear_cache: Array = [null, null]  # whether the line is clear for a blow that is not low, and for a low one, this frame
var _self: Actor  # its own actor, kept for _reangle (which is called from where only the clock is known)
var _wind_ups := {}  # move id -> seconds to its first hitbox_on (read from its clip once)
var _homing := false  # walking home, ignoring the target
var _homing_for := 0.0  # seconds it has walked home
var _turning_home := 0.0  # seconds left that it faces home_facing
var _alarm := false  # woken or alarmed: it engages on its next think, if it has a target


func _init(brain_def: BrainDef, seed_value: int) -> void:
	def = brain_def if brain_def != null else BrainDef.new()
	rng.seed = seed_value


func think(actor: Actor, delta: float) -> Intent:
	var intent := _think(actor, delta)
	if _come_round:
		_hold_lit(actor, intent)
	if _turning_home > 0.0:
		_turning_home -= delta
		if mode == Mode.IDLE and intent.face_target == null:
			_face_home(actor, intent)  # home: it turns to its post's facing over a few frames
	return intent


func _think(actor: Actor, delta: float) -> Intent:
	var intent := Intent.new()
	if _last_at != Vector3.INF and delta > 0.0:
		_speed = _flat(actor, _last_at).length() / delta
	_last_at = actor.global_position
	_self = actor
	if asleep:
		return intent  # no turning, no looking, no perceiving
	for option: AttackOption in _cooldowns.keys():
		_cooldowns[option] = maxf(_cooldowns[option] - delta, 0.0)
	if _homing:
		_walk_home(actor, intent, delta)
		return intent
	_find_target(actor)
	if target == null:
		_go_idle(actor)
		return intent
	if mode == Mode.IDLE or mode == Mode.NOTICING:
		_perceive(actor, delta, intent)
		return intent
	if home != null and _flat(actor, home as Vector3).length() > leash:
		_go_idle(actor)  # past its leash: it gives the fight up and goes home
		return intent
	if _flat(actor, target.global_position).length() > def.sight_range * LOSE_FACTOR:
		_go_idle(actor)
		return intent
	_face(intent)
	if _reacting(actor):
		_on_reaction(actor)
		return intent
	if _holding != &"":
		_keep_holding(actor, intent)
	if mode == Mode.ATTACKING:
		_follow_through(actor, intent)
		return intent
	if _hurt(actor):
		_stand_down(actor)
		mode = Mode.RETREATING
		_retreat_left = def.regroup_time
		_retreated = true
	if mode == Mode.RETREATING:
		_retreat(actor, intent, delta)
		return intent
	if _back_off_due and not actor.runner.busy():
		_back_off_due = false
		_backing = true
		_back_from = actor.global_position
		_back_time = 0.0
	if _backing:
		_back_off(actor, intent, delta)
		return intent
	if actor.runner.busy():
		return intent
	_rest -= delta
	if _go_round(actor, intent, delta):
		return intent
	if _plan == null and _rest <= 0.0:
		_choose(actor)
	if _plan != null:
		_close_in(actor, intent, delta)
	else:
		_space(actor, intent, delta)
	return intent


## Whether `option` may be chosen with the target `distance` metres away: by range, on the near side only. The actor would
## have to back up no more than the option's back_up_margin to throw it; from further out it can always walk in.
func on_menu(option: AttackOption, distance: float) -> bool:
	return option.min_range - distance <= option.back_up_margin


## The attack it has chosen and is closing in to throw or throwing, or null.
func plan() -> AttackOption:
	return _plan


## A scene begins (Director): whatever it was planning or throwing is off and its token is back, so that no swing it had begun
## is carried through the scene and lands the moment control is given back.
func stand_down_for_scene(actor: Actor) -> void:
	_stand_down(actor)
	_holding = &""


## A scene is over (Director): it rests at least `seconds` before it chooses an attack, so that the player has his hands back
## before anyone swings. The attack it then chooses is thrown whole, with its tell.
func rest_for(seconds: float) -> void:
	_rest = maxf(_rest, seconds)


## Wakes it: awake from now on, and it engages on its next think if it has a target (which it turns to face).
func wake() -> void:
	engage_now()


## An alarm: awake, and straight to ENGAGED on its next think if it has a target, with no noticing. One already fighting is not
## told twice.
func engage_now() -> void:
	asleep = false
	if mode == Mode.ENGAGED or mode == Mode.ATTACKING or mode == Mode.RETREATING:
		return
	_homing = false
	_alarm = true


## Whether it is walking home (it ignores its target while it does).
func going_home() -> bool:
	return _homing


# --- target and perception ---

# Keeps the target while it is alive and in the game, else finds the nearest live actor of the player's team.
func _find_target(actor: Actor) -> void:
	if target != null and is_instance_valid(target) and target.is_inside_tree() and not target.dead:
		return
	target = null
	var best := INF
	for node in actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == actor or other.dead or other.def == null or other.def.team != ActorDef.Team.PLAYER:
			continue
		var distance := _flat(actor, other.global_position).length()
		if distance < best:
			best = distance
			target = other


# IDLE and NOTICING: builds up its notice while it perceives the target, turning to look, and lets it fade when it does
# not; engages at notice_time.
func _perceive(actor: Actor, delta: float, intent: Intent) -> void:
	if _alarm:
		_alarm = false
		intent.face_target = target.global_position
		intent.look_target = target.head_point()
		_engage(actor)
		return
	if _sees(actor) or _hears(actor):
		mode = Mode.NOTICING
		_noticed += delta
		intent.face_target = target.global_position
		intent.look_target = target.head_point()
	elif mode == Mode.NOTICING:
		_noticed = maxf(_noticed - delta, 0.0)
		if _noticed <= 0.0:
			mode = Mode.IDLE
	if _noticed >= def.notice_time - 1e-6:
		_engage(actor)


func _engage(_actor: Actor) -> void:
	var was := mode
	mode = Mode.ENGAGED
	_rest = def.attack_rest * rng.randf_range(0.25, 0.75)
	_reset_spacing()
	if was != Mode.RETREATING:
		engaged.emit()  # (a foe that regroups and comes back is the same engagement)


# Whether the target is in its sight cone with a clear line between their heads.
func _sees(actor: Actor) -> bool:
	var flat := _flat(actor, target.global_position)
	if flat.length() > def.sight_range:
		return false
	var facing := Vector2(actor.facing().x, actor.facing().z)
	if not flat.is_zero_approx() and absf(rad_to_deg(facing.angle_to(flat))) > def.sight_fov_deg * 0.5:
		return false
	var ray := PhysicsRayQueryParameters3D.create(actor.head_point(), target.head_point(), Layers.WORLD, [actor.get_rid(), target.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


# Whether it hears the target: within hearing_range while it sprints or attacks.
func _hears(actor: Actor) -> bool:
	if _flat(actor, target.global_position).length() > def.hearing_range:
		return false
	var attacking := target.runner.current != null and target.runner.current.kind == MoveData.Kind.ATTACK
	return target.locomotion.sprinting or attacking


# --- engaged ---

# Faces the target, looks at its head and aims every swing at it (through the active frames with track_dodges), its combo
# blows warped toward it (Intent.warp).
func _face(intent: Intent) -> void:
	intent.face_target = target.global_position
	intent.look_target = target.head_point()
	intent.aim_target = target.global_position
	intent.track = def.track_dodges
	intent.warp = true


# Keeps preferred_range ± range_tolerance: in, out, or round (see the top).
func _space(actor: Actor, intent: Intent, delta: float) -> void:
	var to := _flat(actor, target.global_position)
	var distance := to.length()
	if distance < 1e-4:
		return
	var toward := to / distance
	var error := absf(distance - def.preferred_range)
	if error <= (SETTLE_WITHIN if _settling else def.range_tolerance):
		_settling = false
		_reset_spacing()
		# Round it, easing toward the middle of its range as it goes (it settles at preferred_range, not at an edge).
		var middle := def.preferred_range + (def.range_tolerance * 0.5 if _waiting(actor) else 0.0)
		var ease := clampf((distance - middle) / def.range_tolerance, -1.0, 1.0) * DRIFT
		var away := _away_from_neighbour(actor)
		if away != 0.0:
			_circle = away
		elif _even:
			# between two equals: no way round, only his distance (straight out if he is nearer than the waiters' band)
			intent.move = toward * ease * def.circle_speed
			_blocked = 0.0
			return
		intent.move = (toward.rotated(_circle * PI * 0.5) + toward * ease).normalized() * def.circle_speed
		# Blocked circling turns the other way, unless a neighbour decides the way (he would put it back on the next frame, and the foe
		# would flip twice for nothing).
		if _watch_blocked(actor, intent, delta) and away == 0.0:
			_circle = -_circle
		return
	_settling = true  # out of its range: it goes back to preferred_range itself, not to the edge of its range
	_track_progress(error - SETTLE_WITHIN, delta)
	_head(intent, toward if distance > def.preferred_range else -toward, error - SETTLE_WITHIN)
	if _watch_blocked(actor, intent, delta):
		_reangle()


# Sets the stick toward `heading` (swung by any re-angling), jogging while more than WALK_WITHIN from where it is going.
func _head(intent: Intent, heading: Vector2, still_to_go: float) -> void:
	intent.move = heading.rotated(_swing) * (JOG_PUSH if still_to_go > WALK_WITHIN else WALK_PUSH)


# Counts the time its spacing has got no nearer (`error`: how far it still is from its range); at reangle_after it
# re-angles.
func _track_progress(error: float, delta: float) -> void:
	if error < _best_error - PROGRESS:
		_best_error = error
		_failing = 0.0
		return
	_failing += delta
	if _failing >= def.reangle_after:
		_reangle()
		_best_error = error


# Tries another angle: the circling turns the other way and the heading swings REANGLE_DEG that way.
func _reangle() -> void:
	# Task 15c: stuck where the line is clear but a body cannot walk it (a wall's corner in the way): that is a wall, and he goes round it.
	if _self != null and target != null and is_instance_valid(target) and _same_level(_self) and not _goal_at(_self.get_world_3d().direct_space_state,
			Vector2(_self.global_position.x, _self.global_position.z), _self.global_position.y, [_self.get_rid(), target.get_rid()]):
		_snagged = true
	# Task 14f turned the circling toward the wider gap here. Since a foe plans a way round what blocks him (Task 15c) that rule decided nothing a
	# test or a measured fight could see (the whole suite and every place of the stand-about fixtures play the same with and without it), and
	# it was retired: the circling turns the other way, and the room check below keeps it out of a wall.
	_circle = -_circle
	_swing = _circle * deg_to_rad(REANGLE_DEG)
	# Task 15c: the way that has a wall against it is no way (a foe at a door's jamb swung into the jamb, was blocked, and chose it again, for fifteen
	# seconds): where there is no room a stride that way and there is the other, he goes the other. In the open there is room: nothing changes.
	if _self != null and target != null and is_instance_valid(target):
		var to := _flat(_self, target.global_position)
		if to.length() > 0.1 and not _has_room(_self, to.rotated(_swing)) and _has_room(_self, to.rotated(-_swing)):
			_circle = -_circle
			_swing = -_swing
	_failing = 0.0
	_blocked = 0.0


# The other foes of this target, with the signed angle (degrees, seen from the target) each stands at from `actor`.
func _neighbour_angles(actor: Actor) -> Array[float]:
	var angles := _all_neighbour_angles(actor)
	if angles.size() < 2:
		angles.clear()  # two foes fight as they always did: it takes a third to crowd the ring
	return angles


func _all_neighbour_angles(actor: Actor) -> Array[float]:
	var angles: Array[float] = []
	var from := -_flat(actor, target.global_position)
	if from.length() < 1e-3:
		return angles
	for node in actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == actor or other.dead or not (other.brain is EnemyBrain) or (other.brain as EnemyBrain).target != target:
			continue
		var mode_of_other := (other.brain as EnemyBrain).mode
		if mode_of_other == Mode.IDLE or mode_of_other == Mode.NOTICING:
			continue
		var there := -_flat(other, target.global_position)
		if there.length() < 1e-3:
			continue
		angles.append(rad_to_deg(from.angle_to(there)))
	return angles


# Which way round the target (the `_circle` that takes it there) is open: toward the side whose nearest neighbour is further, 0 with
# no neighbour. Moving along `_circle` = 1 turns its bearing from the target by the sign of the cross product below.
func _open_side(actor: Actor) -> float:
	var angles := _neighbour_angles(actor)
	if angles.is_empty():
		return 0.0
	var positive := 360.0  # the nearest neighbour on the side of increasing bearing
	var negative := 360.0
	for angle in angles:
		if angle >= 0.0:
			positive = minf(positive, angle)
		else:
			negative = minf(negative, -angle)
	var toward_positive := positive >= negative  # more room that way
	return _circle_for(actor, 1.0 if toward_positive else -1.0)


# The `_circle` whose circling turns its bearing from the target the way `bearing_sign` says (the sign of from.angle_to).
func _circle_for(actor: Actor, bearing_sign: float) -> float:
	var to := _flat(actor, target.global_position)
	if to.length() < 1e-3:
		return _circle
	var from := -to
	var tangent := (to / to.length()).rotated(PI * 0.5)
	var turns := signf(from.cross(tangent))
	return bearing_sign * turns if turns != 0.0 else _circle


# 0, or the `_circle` that takes it away from its nearest neighbour when that one is within SPREAD_DEG. Between two neighbours, both within
# SPREAD_DEG and at gaps within EVEN_DEG of each other, it is 0 and `_even` is set: pushed away from whichever is nearer, a foe between equals
# would change his mind on every step (a shiver), so he stands his ground until the gaps differ by EVEN_DEG + EVEN_MARGIN.
func _away_from_neighbour(actor: Actor, within := SPREAD_DEG) -> float:
	var nearest := 360.0
	var sign_of := 0.0
	var positive := 360.0
	var negative := 360.0
	for angle in _neighbour_angles(actor):
		if absf(angle) < nearest:
			nearest = absf(angle)
			sign_of = signf(angle)
		if angle >= 0.0:
			positive = minf(positive, angle)
		else:
			negative = minf(negative, -angle)
	# Both neighbours near (a margin past SPREAD_DEG too: a neighbour at the very edge of it would be in and out on alternate frames).
	if positive < within + EVEN_MARGIN and negative < within + EVEN_MARGIN:
		var gap := absf(positive - negative)
		_even = gap < EVEN_DEG or (_even and gap < EVEN_DEG + EVEN_MARGIN)
		if _even:
			return 0.0
	else:
		_even = false
	if nearest >= within or sign_of == 0.0:
		return 0.0
	return _circle_for(actor, -sign_of)


# How far (radians) its way in is swung to keep off a neighbour who stands within SPREAD_DEG of its bearing: nothing far out, SPREAD_SWING
# near the ring. It goes in beside him, not in a queue behind him. Between two neighbours the swing grows with how much nearer one is than the
# other (nothing at even gaps, all of it at EVEN_DEG + EVEN_MARGIN), so that it is not a switch that a step in either direction throws.
func _spread_swing(actor: Actor, still_to_go: float) -> float:
	if still_to_go > SPREAD_REACH + (SPREAD_REACH_MARGIN if _spreading else 0.0):
		_spreading = false
		_in_line = false
		return 0.0
	var positive := 360.0
	var negative := 360.0
	for angle in _neighbour_angles(actor):
		if angle >= 0.0:
			positive = minf(positive, angle)
		else:
			negative = minf(negative, -angle)
	var nearest := minf(positive, negative)
	if nearest >= SPREAD_DEG:
		_spreading = false
		_in_line = false
		return 0.0
	_spreading = true
	var scale := 1.0
	if positive < SPREAD_DEG + EVEN_MARGIN and negative < SPREAD_DEG + EVEN_MARGIN:
		scale = clampf(absf(positive - negative) / (EVEN_DEG + EVEN_MARGIN), 0.0, 1.0)
	var away := _circle_for(actor, -1.0 if positive < negative else 1.0)
	_in_line = nearest < LINE_DEG or (_in_line and nearest < LINE_DEG + LINE_MARGIN)
	return away * deg_to_rad(SPREAD_SWING_CLOSE if _in_line else SPREAD_SWING) * scale


# Whether it waits for its turn: no token for it to take (both are held by others).
func _waiting(actor: Actor) -> bool:
	if def.ignores_tokens or _neighbour_angles(actor).is_empty():
		return false
	var tokens := AttackTokens.of(actor)
	return tokens != null and not tokens.holds(actor) and not tokens.can_take(actor, target)


func _reset_spacing() -> void:
	_nearest_yet = INF
	_held_up = 0.0
	_swing = 0.0
	_failing = 0.0
	_best_error = INF


# Counts the time the stick (`intent`'s) has been pushed while the actor got nowhere (a body or a wall in the way; not a
# hit-stop or a move); true, and the count starts again, once it reaches BLOCKED_AFTER.
func _watch_blocked(actor: Actor, intent: Intent, delta: float) -> bool:
	if intent.move.length() < 0.01 or actor.frozen > 0 or actor.runner.busy() or _speed >= STALL_SPEED:
		_blocked = 0.0
		return false
	_blocked += delta
	if _blocked < BLOCKED_AFTER:
		return false
	_blocked = 0.0
	return true


# --- choosing and throwing an attack ---

# Takes a token, picks an option by weight among those it may throw now (off cooldown, on the menu at this range: on_menu),
# and rolls its tier's dice for it.
func _choose(actor: Actor) -> void:
	if target.paired_with != null or def.attacks.is_empty():
		return
	if not _clear(actor, false) and not (_has_low(actor) and _clear(actor, true)):
		return  # the world would stop it: no plan, and no token taken (see _go_round)
	var token := def.ignores_tokens
	if not token and def.attacks.any(func(o: AttackOption) -> bool: return o.needs_token):
		token = AttackTokens.take_for(actor, target)
	var open: Array[AttackOption] = []
	var total := 0.0
	var needs_more := false
	var distance := _flat(actor, target.global_position).length()
	for option in def.attacks:
		if _cooldowns.get(option, 0.0) > 0.0 or option.weight <= 0.0 or (option.needs_token and not token):
			continue
		if option.needs_token and not def.ignores_tokens and option.tokens != 1 and not _may_hold(actor, option):
			needs_more = true
			continue  # a big attack waits until the tokens it needs are free
		if not on_menu(option, distance):
			continue
		if not _clear(actor, _is_low(actor, option)):
			continue  # a low sweep across a low wall, or a hook over a counter, would be stopped
		open.append(option)
		total += option.weight
	if open.is_empty():
		_give_back(actor)
		if needs_more:
			AttackTokens.reserve_for(actor, target)  # the others let the tokens run out for it (Task 14f)
		return
	var roll := rng.randf() * total
	var chosen := open.back() as AttackOption
	for option in open:
		roll -= option.weight
		if roll < 0.0:
			chosen = option
			break
	if not chosen.needs_token:
		_give_back(actor)
	elif chosen.tokens != 1 and not def.ignores_tokens:
		AttackTokens.take_for(actor, target, chosen.tokens)  # it holds what it needs from now on: no other enemy begins an attack
	_plan = chosen
	_approach = 0.0
	_backed_up = 0.0
	_backing_up_for = 0.0
	_reset_spacing()
	_feint = rng.randf() < def.feint_chance and _feint_takes(actor, chosen.action)
	var delay_roll := rng.randf()
	var frames := rng.randi_range(def.delay_frames.x, def.delay_frames.y)
	_delay = frames if delay_roll < def.delay_chance and _charges(actor, chosen.action) else 0
	_presses.clear()
	if _feint:
		_presses.append(chosen.action)
	for action in chosen.combo:
		_presses.append(StringName(action))
	if rng.randf() < def.extend_combo_chance and not chosen.combo.is_empty():
		_presses.append(StringName(chosen.combo[chosen.combo.size() - 1]))


# Closes or backs off into the chosen option's range and throws it there, square enough to the target.
func _close_in(actor: Actor, intent: Intent, delta: float) -> void:
	if target.paired_with != null:
		_drop_plan(actor)
		return
	var to := _flat(actor, target.global_position)
	var distance := to.length()
	var lo := _plan.min_range
	var hi := _plan.max_range
	if distance >= lo and distance <= hi and not _within_warp(actor, actor.def.moveset.get(_plan.action, &"")):
		hi = distance - 0.01  # in range, but the target is walking out of the first blow's reach: keep closing
	if distance >= lo and distance <= hi:
		if actor.locomotion.speed > PRESS_SPEED:
			intent.move = (to / distance) * WALK_PUSH  # still slowing to a walk: no attack starts from a jog
		elif _off_facing(actor, to) <= _plan.max_angle_deg and actor.frozen == 0:
			_fire(actor, intent)
		return  # in range: it stands and turns to face the target (or waits out a hit-stop)
	_approach += delta
	if _approach > def.reangle_after * 2.0:
		_drop_plan(actor)
		return
	_track_progress(maxf(distance - hi, lo - distance), delta)
	if distance > hi and actor.frozen == 0:
		if distance < _nearest_yet - PROGRESS:
			_nearest_yet = distance
			_held_up = 0.0
		else:
			_held_up += delta
		if _held_up >= HAND_OVER_AFTER and distance <= def.preferred_range + def.range_tolerance and _hand_over(actor):
			return
	else:
		_held_up = 0.0
		_nearest_yet = INF
	if distance > hi:
		# Jogs in, braking to a walk over the last of it: from where slowing down to a walk at the tuning's decel only just
		# takes it to the edge of the range (BRAKE_MARGIN before).
		var tuning := actor.locomotion.tuning
		var speed := actor.locomotion.speed
		var braking := maxf(speed * speed - tuning.walk_speed * tuning.walk_speed, 0.0) / (2.0 * maxf(tuning.decel, 0.01))
		var push := WALK_PUSH if distance - hi <= braking + BRAKE_MARGIN else JOG_PUSH
		var spread := _spread_swing(actor, distance - hi)
		if spread != 0.0:
			# A swing that would walk him into a wall he is against is no swing (Task 15c): it goes where there is room, and a refusal holds for
			# NO_ROOM_FRAMES (at the edge of the room, the swing would otherwise be on and off with each step).
			var frame := Engine.get_physics_frames()
			if frame >= _no_room_until and not _has_room(actor, (to / distance).rotated(_swing + spread)):
				_no_room_until = frame + NO_ROOM_FRAMES
			if frame < _no_room_until:
				spread = 0.0
		intent.move = (to / distance).rotated(_swing + spread) * push
	else:
		# A back-up within the option's margin, at a walk. One chosen while still going faster than a walk (a jog in) brakes first,
		# the stick at rest: a stick pushed the other way turns the body round at once at the speed it has (Locomotion), and it
		# would glide backward at a jog, slowing as it went. One the target keeps following it through is given up once it has
		# gone the margin, or taken that long at a walk and a second more.
		if actor.locomotion.speed > PRESS_SPEED:
			return
		_backed_up += _speed * delta
		_backing_up_for += delta
		var walk := actor.locomotion.target_speed(WALK_PUSH, false)
		if _backed_up > _plan.back_up_margin + BACK_UP_SPARE or _backing_up_for > _plan.back_up_margin / maxf(walk, 0.1) + 1.0:
			_drop_plan(actor)
			return
		intent.move = (-to / distance).rotated(_swing) * WALK_PUSH
	if _watch_blocked(actor, intent, delta):
		_reangle()


# Gives its token to a foe who can use it, if there is one: engaged, ready, within HAND_OVER_REACH of the target, with a clear line to it.
# True if it did (it drops its plan and rests a while); false, and it keeps both, if nobody can.
func _hand_over(actor: Actor) -> bool:
	if not _plan.needs_token or def.ignores_tokens or _neighbour_angles(actor).is_empty():
		return false
	var taker := false
	for node in actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == actor or other.dead or not (other.brain is EnemyBrain):
			continue
		var brain := other.brain as EnemyBrain
		if brain.target != target or brain.mode != Mode.ENGAGED or brain._plan != null or brain._rest > 0.0 or brain._backing or other.runner.busy() or other.frozen > 0:
			continue
		if _flat(other, target.global_position).length() > HAND_OVER_REACH or not brain._line_is_clear(other):
			continue
		var tokens := AttackTokens.of(other)
		if tokens != null and tokens.holds(other):
			continue
		if brain.def.attacks.any(func(o: AttackOption) -> bool: return o.weight > 0.0 and brain._cooldowns.get(o, 0.0) <= 0.0):
			taker = true
			break
	if not taker:
		return false
	_drop_plan(actor)
	_rest = maxf(_rest, HAND_OVER_REST)
	_held_up = 0.0
	return true


# Whether no body stands within CLEAR_LINE of the straight line from `actor` to its target (the target's own and its own excepted).
func _line_is_clear(actor: Actor) -> bool:
	var from := Vector2(actor.global_position.x, actor.global_position.z)
	var to := Vector2(target.global_position.x, target.global_position.z)
	var line := to - from
	var length := line.length()
	if length < 1e-3:
		return true
	if _same_level(actor) and not HitScanner.line_clear(actor, target):
		return false  # a wall between: he could not use the token
	for node in actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == actor or other == target or other.dead:
			continue
		var at := Vector2(other.global_position.x, other.global_position.z) - from
		var along := at.dot(line) / length
		if along > 0.0 and along < length and absf(at.cross(line / length)) < CLEAR_LINE:
			return false
	return true


# --- Task 15c: no swing at a wall ---

# Whether the world lets a blow through to the target from here this frame (HitScanner.line_clear), asked once a frame per kind.
func _clear(actor: Actor, low: bool) -> bool:
	if not _same_level(actor):
		return true  # a target well above or below him (falling off the world's edge, say) is not behind a wall: the old brain's way
	var frame := Engine.get_physics_frames()
	if frame != _clear_frame:
		_clear_frame = frame
		_clear_cache = [null, null]
	var i := 1 if low else 0
	if _clear_cache[i] == null:
		_clear_cache[i] = HitScanner.line_clear(actor, target, low)
	return _clear_cache[i]


# Whether the target stands within LEVEL_GAP metres of his height: the lines a wall may cut are asked on one level only.
func _same_level(actor: Actor) -> bool:
	return absf(target.global_position.y - actor.global_position.y) <= LEVEL_GAP


# Whether `option`'s first move has a low blow (a sweep: HitProfile.Height.LOW).
func _is_low(actor: Actor, option: AttackOption) -> bool:
	var id: StringName = actor.def.moveset.get(option.action, &"")
	if id == &"" or not Registry.ids(&"moves").has(String(id)):
		return false
	var move := Registry.fetch(&"moves", id) as MoveData
	return move != null and move.hits.values().any(func(p: HitProfile) -> bool: return p.height == HitProfile.Height.LOW)


func _has_low(actor: Actor) -> bool:
	return def.attacks.any(func(o: AttackOption) -> bool: return _is_low(actor, o))


# The plan is off, its token is back, and nothing else changes (no cooldown, no rest: nothing was thrown).
func _forget_plan(actor: Actor) -> void:
	_plan = null
	_presses.clear()
	_give_back(actor)
	_reset_spacing()


# With no line to the target within sight he goes to where he has one, instead of circling, closing in or standing at the wall. True while
# he does (his plan is off and his token back: he cannot attack from here). While his way is being searched for (a few frames: see
# _advance_search) he plays as before, and _choose and _fire still refuse a swing at the wall. With no way to be found (a shut gate, a closed
# room, a wall longer than the grid) he goes to the nearest place to the target he can reach and waits there facing him (see _wait_round).
func _go_round(actor: Actor, intent: Intent, delta: float) -> bool:
	var here := Vector2(actor.global_position.x, actor.global_position.z)
	var there := Vector2(target.global_position.x, target.global_position.z)
	if here.distance_to(there) > def.sight_range:
		_stop_round()
		return false
	if _no_way:
		return _wait_round(actor, intent, delta, here, there)
	if _round_to != Vector2.INF:
		_round_for += delta
		if here.distance_to(_round_to) < ROUND_REACHED:
			_round_to = _round_path.pop_front() if not _round_path.is_empty() else Vector2.INF
			if _round_to == Vector2.INF:
				_arrive(there)
		if _round_for > ROUND_GIVE_UP or there.distance_to(_round_at) > ROUND_MOVED:
			_round_to = Vector2.INF
			_round_path.clear()
			_come_round = false
		elif _round_to != Vector2.INF and _goal_at(actor.get_world_3d().direct_space_state, here, actor.global_position.y, [actor.get_rid(), target.get_rid()]):
			_round_to = Vector2.INF  # where he stands is already well inside the lit ground, with room to walk in: no need to go on
			_round_path.clear()
			_arrive(there)
	if _round_to == Vector2.INF:
		if _clear(actor, false) and not _snagged:
			_search = null
			return false
		if not _begin_or_advance(actor, there):
			return false
		if _no_way:
			return _wait_round(actor, intent, delta, here, there)
		if _round_to == Vector2.INF:
			return false
	if _plan != null:
		_forget_plan(actor)
	else:
		_reset_spacing()  # a heading swung by a re-angle (the snag that sent him round) is not taken along the way or on arrival
	_walk_to_round(intent, delta, here)
	return true


# He has come round: from here on, while the target stands where he stood, the ordinary brain may not take him back into the shadow (_hold_lit),
# and no new search begins for ROUND_HOLD frames.
func _arrive(there: Vector2) -> void:
	_come_round = true
	_come_at = there
	_plan_after = maxi(_plan_after, Engine.get_physics_frames() + ROUND_HOLD)


# A foe who has come round does not step back behind what he came round: a stick that would take him where, COME_LOOK metres on, he has no line
# is let go, and he stands (the line itself, not the room for a body either side of it: the way in through a gap is narrow). Released when the target has moved ROUND_MOVED from where it was.
func _hold_lit(actor: Actor, intent: Intent) -> void:
	if target == null or not is_instance_valid(target) or mode == Mode.IDLE or mode == Mode.NOTICING:
		_come_round = false
		return
	var there := Vector2(target.global_position.x, target.global_position.z)
	if there.distance_to(_come_at) > ROUND_MOVED or not _same_level(actor):
		_come_round = false
		return
	if intent.move.length() < 0.01 or actor.runner.busy():
		return
	var here := Vector2(actor.global_position.x, actor.global_position.z)
	var space := actor.get_world_3d().direct_space_state
	var exclude: Array[RID] = [actor.get_rid(), target.get_rid()]
	var way := intent.move.normalized()
	if _lit_step(space, actor, here + way * COME_LOOK, exclude):
		return
	# A swing round a neighbour or a circling that would leave the lit ground becomes a step straight in, if that keeps the line; else he stands.
	var straight := (there - here).normalized()
	if _lit_at(space, here + straight * COME_LOOK, actor.global_position.y, exclude):
		intent.move = straight * intent.move.length()  # (with the room for a body either side: not grazing the edge)
		return
	intent.move = Vector2.ZERO


# Whether a body that stood at `ahead` (x, z) would have the line (not the room either side of it) to the target.
func _lit_step(space: PhysicsDirectSpaceState3D, actor: Actor, ahead: Vector2, exclude: Array[RID]) -> bool:
	return HitScanner.clear_between(space, Vector3(ahead.x, actor.global_position.y, ahead.y), target, exclude)


# Walks the way: the stick at the next point of it, a jog until the last 0.6 m.
func _walk_to_round(intent: Intent, delta: float, here: Vector2) -> void:
	var way := _round_to - here
	intent.move = way.normalized() * (JOG_PUSH if way.length() > 0.6 else WALK_PUSH)
	if _watch_blocked(_self, intent, delta):
		_round_to = Vector2.INF
		_round_path.clear()


# He has no way to a line (a search found none): he goes to the nearest place he can reach and stands there facing the target, which _face
# does; a search again only when the target has moved (ROUND_MOVED) after a back-off that doubles with each failure (ROUND_BACK_OFF), or
# after ROUND_RECHECK frames of waiting.
func _wait_round(actor: Actor, intent: Intent, delta: float, here: Vector2, there: Vector2) -> bool:
	if _clear(actor, false) and _goal_at(actor.get_world_3d().direct_space_state, here, actor.global_position.y, [actor.get_rid(), target.get_rid()]):
		_stop_round()  # the target came out from behind it (or the world changed): the old brain's way
		return false  # (a line through a slit he cannot walk to is not a way: he goes on waiting)
	var frame := Engine.get_physics_frames()
	if _search != null:
		_begin_or_advance(actor, there)
	elif frame >= _plan_after and (there.distance_to(_round_at) > ROUND_MOVED or frame >= _plan_after + ROUND_RECHECK):
		_begin_or_advance(actor, there)
	if not _no_way:
		return _go_round(actor, intent, delta)  # the search found a way after all
	if _plan != null:
		_forget_plan(actor)
	else:
		_reset_spacing()
	if _round_to != Vector2.INF:
		_round_for += delta
		if here.distance_to(_round_to) < ROUND_REACHED:
			_round_to = _round_path.pop_front() if not _round_path.is_empty() else Vector2.INF
		if _round_to != Vector2.INF:
			_walk_to_round(intent, delta, here)
	return true


# Forgets the way, the search and the wait.
func _stop_round() -> void:
	_come_round = false
	_round_to = Vector2.INF
	_round_path.clear()
	_search = null
	_no_way = false


# Starts a search for a way (if none is under way) and spends this frame's share of the cells on it (the foes together may open
# ROUND_CELLS_PER_FRAME a frame: _spend). When it ends: a way found is the path he walks; none found, he waits (_no_way) at the nearest place
# he can reach. False while it goes on.
func _begin_or_advance(actor: Actor, there: Vector2) -> bool:
	if _search != null and (_search as RoundSearch).at.distance_to(there) > ROUND_MOVED:
		_search = null  # the target has moved on: what was found is for another place
	if _search == null:
		if Engine.get_physics_frames() < _plan_after and there.distance_to(_round_at) <= ROUND_MOVED:
			return false  # a search found no way a moment ago and the target has not moved: no new one yet
		var s := _start_search(actor)
		if s == null:
			return false
		_search = s
	var s := _search as RoundSearch
	if not _advance_search(actor, s):
		return false
	_search = null
	_round_at = s.at
	_round_for = 0.0
	_snagged = false
	var frame := Engine.get_physics_frames()
	_come_round = false
	if s.found:
		_fails = 0
		_no_way = false
		_round_path = s.legs
		_round_to = _round_path.pop_front() if not _round_path.is_empty() else Vector2.INF
		return true
	_fails += 1
	_plan_after = frame + ROUND_BACK_OFF * (1 << mini(_fails - 1, ROUND_BACK_OFF_DOUBLINGS))
	_no_way = true
	_round_path = s.legs
	_round_to = _round_path.pop_front() if not _round_path.is_empty() else Vector2.INF
	return true


## What a search for a way round keeps from frame to frame: the breadth-first search over the grid (phase 0), then the smoothing of the way
## found to the fewest straight legs a body can walk (phase 1).
class RoundSearch extends RefCounted:
	var start := Vector2.ZERO
	var y := 0.0
	var at := Vector2.ZERO  # where the target stood when it began
	var perp := Vector2.ZERO
	var exclude: Array[RID] = []
	var query: PhysicsShapeQueryParameters3D
	var open := 0.0
	var crowd: Array[Vector2] = []
	var free := {Vector2i.ZERO: true}
	var depth := {Vector2i.ZERO: 0}
	var parent := {}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head := 0
	var first := -1
	var best_cost := INF
	var best := Vector2i.ZERO
	var nearest := Vector2i.ZERO  # the cell reached that is nearest the target
	var nearest_distance := INF
	var phase := 0
	var found := false
	var cells: Array[Vector2] = []
	var i := 0
	var j := 0
	var legs: Array[Vector2] = []


# The cells the foes together may open on one physics frame (a cell: a shape query for each new neighbour, a goal test, and the rays of
# the ground under it), and what is left of them this frame.
static var _spent_frame := -1
static var _spent := 0


# How many cells of search this frame still allows, of `want`.
static func _spend(want: int) -> int:
	var frame := Engine.get_physics_frames()
	if frame != _spent_frame:
		_spent_frame = frame
		_spent = 0
	var got := mini(want, ROUND_CELLS_PER_FRAME - _spent)
	_spent += maxi(got, 0)
	return maxi(got, 0)


# Begins a search from where the actor stands for a way to a line to the target; null if the target is too near to have a way.
func _start_search(actor: Actor) -> RoundSearch:
	var s := RoundSearch.new()
	s.start = Vector2(actor.global_position.x, actor.global_position.z)
	s.y = actor.global_position.y
	s.at = Vector2(target.global_position.x, target.global_position.z)
	var along := s.at - s.start
	if along.length() < 0.1:
		return null
	plans += 1
	s.perp = along.normalized().rotated(PI * 0.5)  # circling with _circle = 1 goes this way
	s.exclude = [actor.get_rid(), target.get_rid()]
	var ball := SphereShape3D.new()
	ball.radius = ROUND_BODY
	s.query = PhysicsShapeQueryParameters3D.new()
	s.query.shape = ball
	s.query.collision_mask = Layers.WORLD
	s.open = _open_side(actor)
	s.crowd = _neighbour_spots(actor)
	return s


# Spends what this frame allows on the search `s`. True when it is over (found a way, or found none: s.found).
#
# Phase 0: a breadth-first search over a grid of ROUND_CELL cells round him, a cell free where a ball of ROUND_BODY (a body) touches no
# `world` collider, a goal a cell from which a body ROUND_PAD either side of its middle has a line (HitScanner.clear_between). The nearest goals
# are taken (those within ROUND_EVEN_CELLS of the first), the one on the open side (_open_side) if the two sides are about as near.
# Phase 1: the way is smoothed to the fewest straight legs a body can walk. With no goal, the way is to the cell nearest the target.
func _advance_search(actor: Actor, s: RoundSearch) -> bool:
	var space := actor.get_world_3d().direct_space_state
	var reach := int(ROUND_RADIUS / ROUND_CELL)
	var budget := _spend(ROUND_CELLS_PER_FRAME)
	while budget > 0:
		if s.phase == 0:
			if s.head >= s.queue.size():
				_end_search_phase(s)
				continue
			var c: Vector2i = s.queue[s.head]
			s.head += 1
			budget -= 1
			var d: int = s.depth[c]
			if s.first >= 0 and d > s.first + ROUND_EVEN_CELLS:
				_end_search_phase(s)
				continue
			var at := s.start + Vector2(c) * ROUND_CELL
			var to_target := at.distance_to(s.at)
			if to_target < s.nearest_distance - 0.01:
				s.nearest_distance = to_target
				s.nearest = c
			if c != Vector2i.ZERO and to_target >= 0.8 and _goal_at(space, at, s.y, s.exclude):
				s.first = d if s.first < 0 else s.first
				var side := signf(s.perp.dot(at - s.start))
				var cost := float(d) + (0.0 if s.open == 0.0 or side == s.open else float(ROUND_EVEN_CELLS))
				for other in s.crowd:
					if other.distance_to(at) < ROUND_CROWD:
						cost += float(ROUND_EVEN_CELLS)  # a place a neighbour stands in or goes to: another, if one is about as near
				if cost < s.best_cost:
					s.best_cost = cost
					s.best = c
				continue
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var n: Vector2i = c + step
				if s.depth.has(n) or maxi(absi(n.x), absi(n.y)) > reach:
					continue
				if not s.free.has(n):
					var pos := s.start + Vector2(n) * ROUND_CELL
					s.query.transform = Transform3D(Basis(), Vector3(pos.x, s.y + 0.5, pos.y))
					s.free[n] = space.intersect_shape(s.query, 1).is_empty() and _ground_at(space, pos, s.y)
				if not s.free[n]:
					continue
				if step.x != 0 and step.y != 0 and not (_free_cell(s.free, c + Vector2i(step.x, 0)) and _free_cell(s.free, c + Vector2i(0, step.y))):
					continue  # no cutting a corner
				s.depth[n] = d + 1
				s.parent[n] = c
				s.queue.append(n)
		else:
			budget -= 1
			if s.i >= s.cells.size() - 1:
				s.phase = 2
				return true
			if s.j > s.i + 1 and not _walkable(space, s.cells[s.i], s.cells[s.j], s.y, s.exclude, ROUND_BODY, true):
				s.j -= 1
				continue
			s.legs.append(s.cells[s.j])
			s.i = s.j
			s.j = s.cells.size() - 1
	return s.phase == 2


# The grid is searched: the way to the goal chosen (or, with none, to the cell nearest the target) as cells, to be smoothed.
func _end_search_phase(s: RoundSearch) -> void:
	s.found = s.best_cost != INF
	var end := s.best if s.found else s.nearest
	var c := end
	while c != Vector2i.ZERO:
		s.cells.push_front(s.start + Vector2(c) * ROUND_CELL)
		c = s.parent[c]
	s.cells.push_front(s.start)
	s.phase = 1
	s.i = 0
	s.j = s.cells.size() - 1
	if s.cells.size() < 2:
		s.phase = 2


# Where the other foes of this target stand, or are going (their waypoint's end).
func _neighbour_spots(actor: Actor) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for node in actor.get_tree().get_nodes_in_group(Actor.GROUP):
		var other := node as Actor
		if other == null or other == actor or other.dead or not (other.brain is EnemyBrain) or (other.brain as EnemyBrain).target != target:
			continue
		spots.append(Vector2(other.global_position.x, other.global_position.z))
		var going := other.brain as EnemyBrain
		if going._round_to != Vector2.INF:
			spots.append(going._round_path.back() if not going._round_path.is_empty() else going._round_to)
	return spots


# Whether a body can go a stride (ROOM_REACH) along `heading` (x, z) without meeting a `world` collider at knee height, ROOM_BODY wide.
func _has_room(actor: Actor, heading: Vector2) -> bool:
	var space := actor.get_world_3d().direct_space_state
	var here := Vector2(actor.global_position.x, actor.global_position.z)
	return _walkable(space, here, here + heading.normalized() * ROOM_REACH, actor.global_position.y, [actor.get_rid()], ROOM_BODY)


# A cell already looked at (the diagonal check's neighbours may not have been): free only if known free.
static func _free_cell(free: Dictionary, cell: Vector2i) -> bool:
	return free.get(cell, false)


# Whether a body standing at `at` (x, z) would have a line to the target with ROUND_PAD of room either side of it (the lit ground).
func _lit_at(space: PhysicsDirectSpaceState3D, at: Vector2, y: float, exclude: Array[RID], pad_room := ROUND_PAD) -> bool:
	var feet := Vector3(at.x, y, at.y)
	var to := Vector2(target.global_position.x, target.global_position.z) - at
	var side := to.normalized().rotated(PI * 0.5) * pad_room
	for pad: float in [0.0, -1.0, 1.0]:
		if not HitScanner.clear_between(space, feet + Vector3(side.x, 0.0, side.y) * pad, target, exclude):
			return false
	return true


# Whether a body standing at `at` (x, z) would have a line to the target, with ROUND_PAD of room either side of it, and a way in it can walk.
func _goal_at(space: PhysicsDirectSpaceState3D, at: Vector2, y: float, exclude: Array[RID], pad_room := ROUND_PAD) -> bool:
	if not _lit_at(space, at, y, exclude, pad_room):
		return false
	var to := Vector2(target.global_position.x, target.global_position.z) - at
	# and the way in from there is one a body can walk (the line is clear for a ray; a corner's end face is not for a body)
	var in_line := to.normalized()
	return to.length() < 0.8 or _walkable(space, at, at + in_line * (to.length() - 0.8), y, exclude, ROUND_BODY + 0.1)


# Whether the world has ground under `at` (x, z) within ROUND_STEP_DOWN below the height `y` of the feet: a ray down from knee height on the `world`
# layer. Where it has none a body would fall, not step: a floor's edge, a pit.
func _ground_at(space: PhysicsDirectSpaceState3D, at: Vector2, y: float) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x, y + 0.5, at.y), Vector3(at.x, y - ROUND_STEP_DOWN, at.y), Layers.WORLD)
	return not space.intersect_ray(ray).is_empty()


# Whether a body can walk the straight way from `a` to `b` (x, z): no `world` collider in the way at knee height for its width, and, with
# `on_ground`, ground under every ROUND_CELL of it.
func _walkable(space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2, y: float, exclude: Array[RID], room := ROUND_BODY, on_ground := false) -> bool:
	if on_ground:
		var steps := ceili(a.distance_to(b) / ROUND_CELL)
		for k in range(1, steps):
			if not _ground_at(space, a.lerp(b, float(k) / steps), y):
				return false  # the leg crosses a drop (a corner cut over a pit or a floor's edge)
	var side := (b - a).normalized().rotated(PI * 0.5) * room
	for pad: float in [0.0, -1.0, 1.0]:
		var from := Vector3(a.x + side.x * pad, y + 0.5, a.y + side.y * pad)
		var to := Vector3(b.x + side.x * pad, y + 0.5, b.y + side.y * pad)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD, exclude)).is_empty():
			return false
	return true


# Presses the attack: the feint first, if it feints, else the option's action (held for a delayed swing). Its token is
# taken again (an attacker that holds one keeps it, for TIMEOUT more); with none to be had, the attack is off.
func _fire(actor: Actor, intent: Intent) -> void:
	if not _clear(actor, _is_low(actor, _plan)):
		_forget_plan(actor)  # the line was cut between the choice and the press: no swing at a wall
		return
	if _plan.needs_token and not def.ignores_tokens and not AttackTokens.take_for(actor, target, _plan.tokens):
		_drop_plan(actor)
		return
	mode = Mode.ATTACKING
	_press_count = 0
	_press(actor, intent, FEINT_ACTION if _feint else _plan.action)


# Presses `action`, and starts holding it when it is the attack's own press and the swing is to be delayed.
func _press(actor: Actor, intent: Intent, action: StringName) -> void:
	intent.pressed.append(action)
	if _delay > 0 and _press_count == (1 if _feint else 0):
		_holding = action
		_held = 0
		_hold_frames = 0
		intent.held.append(action)
	_press_count += 1
	if _press_count > 1 and _plan.needs_token and not def.ignores_tokens:
		AttackTokens.take_for(actor, target, _plan.tokens)  # each blow keeps its tokens


# ATTACKING: the next press as its window opens; the attack is over when its moves are.
func _follow_through(actor: Actor, intent: Intent) -> void:
	if target.dead:
		_stand_down(actor)
		return
	if actor.frozen > 0:
		return  # hit-stop: nothing has moved on since the last frame
	if not actor.runner.busy():
		_finish(actor)
		return
	# A blow already begun is not cancelled (it plays out, and the world stops it if it must): only the next one of the combo waits for a line.
	if not _presses.is_empty() and actor.runner.window.has(_presses[0]):
		if not _clear(actor, false):
			_presses.clear()
			return
		if not _within_warp(actor, StringName(actor.runner.window[_presses[0]])):
			_presses.clear()  # the target is out of the next blow's reach: the combo ends rather than swing at air
			return
		_press(actor, intent, _presses.pop_front())


# Whether the target will stand within reach of the move `move_id` once warped, when its blow lands, counting how far it
# goes toward or away from the actor over the move's wind-up at the speed it goes now: no further than its strike_distance
# (for the actor's size), MoveRunner.MAX_WARP and WARP_SLACK, and no nearer than its strike_distance less MAX_WARP and
# SMOTHER_SLACK (a player who steps inside a blow smothers it: the hook would swing past his body). The jab and the cross
# are made to land at body contact, so only the far side ever ends them. A move that is never warped is always within reach.
func _within_warp(actor: Actor, move_id: StringName) -> bool:
	var move := Registry.fetch(&"moves", move_id) as MoveData if Registry.ids(&"moves").has(String(move_id)) else null
	if move == null or move.strike_distance <= 0.0:
		return true
	var to := _flat(actor, target.global_position)
	var going := 0.0  # the target's speed away from the actor (toward it: below 0)
	if not to.is_zero_approx():
		# Where it means to go (a knockback slowing its walk in is over in a moment); while a move plays, where it goes.
		var velocity := target.get_real_velocity() if target.runner.busy() else target.locomotion.velocity()
		going = Vector2(velocity.x, velocity.z).dot(to.normalized())
	var at_blow := to.length() + going * _wind_up(actor, move)
	var strike := move.strike_distance * actor.def.model_scale
	return at_blow <= strike + MoveRunner.MAX_WARP + WARP_SLACK and at_blow >= strike - MoveRunner.MAX_WARP - SMOTHER_SLACK


# Seconds from the start of `move` to its first hitbox_on (its wind-up), read from its clip once; 0 if it has none.
func _wind_up(actor: Actor, move: MoveData) -> float:
	if not _wind_ups.has(move.id):
		var at := 0.0
		if actor.rig.tree.has_animation(move.clip):
			for m in Marks.read(actor.rig.tree.get_animation(move.clip)):
				if m["kind"] == &"hitbox_on":
					at = m["time"]
					break
		_wind_ups[move.id] = at
	return _wind_ups[move.id]


# Holds the delayed swing's action until the clip has stood at its charge for the rolled frames.
func _keep_holding(actor: Actor, intent: Intent) -> void:
	_hold_frames += 1
	if actor.runner.charging:
		_held += 1
	if _held >= _delay or _hold_frames > _delay + 60:
		_holding = &""
		return
	intent.held.append(_holding)


# The attack is over: the token goes back, the option cools down, and it rests before the next.
func _finish(actor: Actor) -> void:
	if _plan != null:
		_cooldowns[_plan] = _plan.cooldown
	_plan = null
	_presses.clear()
	_holding = &""
	_give_back(actor)
	mode = Mode.ENGAGED
	_rest = def.attack_rest * rng.randf_range(0.75, 1.25)
	_reset_spacing()


# The chosen attack is given up before it was thrown (no way into range, the target paired, no token): the token goes
# back, the option waits its cooldown as if it had been thrown, and it rests a little before choosing again.
func _drop_plan(actor: Actor) -> void:
	if _plan != null:
		_cooldowns[_plan] = _plan.cooldown  # as one thrown: or the same attack is chosen again, and given up again, a rest later
	_plan = null
	_presses.clear()
	_give_back(actor)
	_rest = def.attack_rest * 0.5
	_reset_spacing()


# Whatever it was doing to the target is off: the token goes back, no plan, no presses.
func _stand_down(actor: Actor) -> void:
	if _plan != null or mode == Mode.ATTACKING:
		_plan = null
		_presses.clear()
		_holding = &""
		_give_back(actor)
		if mode == Mode.ATTACKING:
			mode = Mode.ENGAGED


# No one to fight (the target is gone, dead or too far): it stands down and forgets what it owed the fight it was in, a
# back-off, a retreat, its spacing, so a new foe meets it fresh.
func _go_idle(actor: Actor) -> void:
	var was := mode
	_stand_down(actor)
	mode = Mode.IDLE
	_noticed = 0.0
	_backing = false
	_back_off_due = false
	_retreat_left = 0.0
	_blocked = 0.0
	_reset_spacing()
	# Standing down from a fight, for whatever reason, a foe with a post goes back to it.
	if was != Mode.IDLE and home != null and _flat(actor, home as Vector3).length() > HOME_ARRIVED:
		_homing = true
		_homing_for = 0.0
		_turning_home = 0.0


# Whether the actor could hold the tokens `option` holds now (AttackOption.tokens), holding what it holds.
func _may_hold(actor: Actor, option: AttackOption) -> bool:
	var tokens := AttackTokens.of(actor)
	return tokens == null or tokens.can_take(actor, target, option.tokens)


func _give_back(actor: Actor) -> void:
	if not def.ignores_tokens:
		AttackTokens.give_back_for(actor)


# Whether the window of the actor's feint (its moveset's FEINT_ACTION move) takes `action` into the move its moveset gives that
# action: the feint stands for that attack, and an actor whose palm is a string of its own is not feinted into the Knuckle's jab.
func _feint_takes(actor: Actor, action: StringName) -> bool:
	if not _feint_window.has(action):
		var takes := false
		for m in _marks_of(actor, FEINT_ACTION):
			if m["kind"] == &"cancel_open" and m["args"].get("into") is Dictionary and (m["args"]["into"] as Dictionary).has(action) \
					and StringName(str(m["args"]["into"][action])) == StringName(actor.def.moveset.get(action, &"")):
				takes = true
		_feint_window[action] = takes
	return _feint_window[action]


# Whether the move `action` starts has a charge_hold for `action` (the jab's), which a delayed swing holds it through.
func _charges(actor: Actor, action: StringName) -> bool:
	if not _charge_holds.has(action):
		var holds := false
		for m in _marks_of(actor, action):
			if m["kind"] == &"charge_hold" and StringName(m["args"].get("action", &"")) == action:
				holds = true
		_charge_holds[action] = holds
	return _charge_holds[action]


# The marks of the move the actor's moveset maps `action` to, or none.
static func _marks_of(actor: Actor, action: StringName) -> Array[Dictionary]:
	var id: StringName = actor.def.moveset.get(action, &"")
	if id == &"" or not Registry.ids(&"moves").has(String(id)):
		return []
	var move := Registry.fetch(&"moves", id) as MoveData
	if move == null or not actor.rig.tree.has_animation(move.clip):
		return []
	return Marks.read(actor.rig.tree.get_animation(move.clip))


# --- reactions ---

# A reaction plays: an attack under way is off, and after a stagger, a parry or a catch it will back off.
func _on_reaction(actor: Actor) -> void:
	_stand_down(actor)
	_holding = &""
	var current := actor.runner.current.id
	for reaction in BACK_OFF_AFTER:
		if actor.def.reactions.get(reaction, &"") == current:
			_back_off_due = true


func _reacting(actor: Actor) -> bool:
	return actor.runner.current != null and actor.runner.current.kind == MoveData.Kind.REACTION


# Backs away from the target until it has gone one preferred_range, or for BACK_OFF_LIMIT at most.
func _back_off(actor: Actor, intent: Intent, delta: float) -> void:
	_back_time += delta
	var away := -_flat(actor, target.global_position)
	if _flat(actor, _back_from).length() >= def.preferred_range or _back_time >= BACK_OFF_LIMIT or away.is_zero_approx():
		_backing = false
		_rest = maxf(_rest, def.attack_rest * 0.5)
		return
	intent.move = away.normalized().rotated(_swing) * BACK_OFF_PUSH
	if _watch_blocked(actor, intent, delta):
		_reangle()


# Whether it is hurt enough to retreat, and has not already retreated since its HP dropped below retreat_below.
func _hurt(actor: Actor) -> bool:
	var below := def.retreat_below > 0.0 and actor.stats.hp < actor.stats.max_hp * def.retreat_below
	if not below:
		_retreated = false
	return below and not _retreated


# RETREATING: turns and runs from the target for regroup_time, then engages again.
func _retreat(actor: Actor, intent: Intent, delta: float) -> void:
	_retreat_left -= delta
	if _retreat_left <= 0.0:
		_engage(actor)
		return
	intent.face_target = null
	var away := -_flat(actor, target.global_position)
	if not away.is_zero_approx():
		intent.move = away.normalized() * JOG_PUSH


# --- home ---

# One frame of the walk home: the jog (a walk over the last of it, as everywhere), the target ignored; home within HOME_ARRIVED ends it
# (`arrived_home`), and so does HOME_GIVE_UP seconds of walking (a wall in the way) with no signal.
func _walk_home(actor: Actor, intent: Intent, delta: float) -> void:
	_homing_for += delta
	var to := _flat(actor, home as Vector3)
	var distance := to.length()
	if distance <= HOME_ARRIVED:
		_homing = false
		_turning_home = HOME_TURN_SECONDS
		_face_home(actor, intent)
		arrived_home.emit()
		return
	if _homing_for >= HOME_GIVE_UP:
		_homing = false
		return
	intent.move = to / distance * (JOG_PUSH if distance > WALK_WITHIN + HOME_ARRIVED else WALK_PUSH)


# Turns it to its post's facing (the body turns at its own rate: this only says which way).
func _face_home(actor: Actor, intent: Intent) -> void:
	if home_facing == null:
		return
	var yaw := float(home_facing)
	intent.face_target = actor.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 4.0


# --- helpers ---

# How far (degrees) the way `to` (world (x, z)) is off the actor's facing.
static func _off_facing(actor: Actor, to: Vector2) -> float:
	var facing := Vector2(actor.facing().x, actor.facing().z)
	return 0.0 if to.is_zero_approx() else absf(rad_to_deg(facing.angle_to(to)))


# The way from the actor to `point` on the ground plane, world (x, z).
static func _flat(actor: Actor, point: Vector3) -> Vector2:
	return Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z)
