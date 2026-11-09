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
##               none), picks by weight among the options off cooldown that it may throw and that are on the menu at
##               this range (it would back up no more than the option's back_up_margin: on_menu), and then closes or
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
var _wind_ups := {}  # move id -> seconds to its first hitbox_on (read from its clip once)


func _init(brain_def: BrainDef, seed_value: int) -> void:
	def = brain_def if brain_def != null else BrainDef.new()
	rng.seed = seed_value


func think(actor: Actor, delta: float) -> Intent:
	var intent := Intent.new()
	if _last_at != Vector3.INF and delta > 0.0:
		_speed = _flat(actor, _last_at).length() / delta
	_last_at = actor.global_position
	for option: AttackOption in _cooldowns.keys():
		_cooldowns[option] = maxf(_cooldowns[option] - delta, 0.0)
	_find_target(actor)
	if target == null:
		_go_idle(actor)
		return intent
	if mode == Mode.IDLE or mode == Mode.NOTICING:
		_perceive(actor, delta, intent)
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
	mode = Mode.ENGAGED
	_rest = def.attack_rest * rng.randf_range(0.25, 0.75)
	_reset_spacing()


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
		var ease := clampf((distance - def.preferred_range) / def.range_tolerance, -1.0, 1.0) * DRIFT
		intent.move = (toward.rotated(_circle * PI * 0.5) + toward * ease).normalized() * def.circle_speed
		if _watch_blocked(actor, intent, delta):
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
	_circle = -_circle
	_swing = _circle * deg_to_rad(REANGLE_DEG)
	_failing = 0.0
	_blocked = 0.0


func _reset_spacing() -> void:
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
	var token := def.ignores_tokens
	if not token and def.attacks.any(func(o: AttackOption) -> bool: return o.needs_token):
		token = AttackTokens.take_for(actor, target)
	var open: Array[AttackOption] = []
	var total := 0.0
	var distance := _flat(actor, target.global_position).length()
	for option in def.attacks:
		if _cooldowns.get(option, 0.0) > 0.0 or option.weight <= 0.0 or (option.needs_token and not token):
			continue
		if not on_menu(option, distance):
			continue
		open.append(option)
		total += option.weight
	if open.is_empty():
		_give_back(actor)
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
	_plan = chosen
	_approach = 0.0
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
	if distance > hi:
		# Jogs in, braking to a walk over the last of it: from where slowing down to a walk at the tuning's decel only just
		# takes it to the edge of the range (BRAKE_MARGIN before).
		var tuning := actor.locomotion.tuning
		var speed := actor.locomotion.speed
		var braking := maxf(speed * speed - tuning.walk_speed * tuning.walk_speed, 0.0) / (2.0 * maxf(tuning.decel, 0.01))
		var push := WALK_PUSH if distance - hi <= braking + BRAKE_MARGIN else JOG_PUSH
		intent.move = (to / distance).rotated(_swing) * push
	else:
		intent.move = (-to / distance).rotated(_swing) * WALK_PUSH  # a back-up within the option's margin, at a walk
	if _watch_blocked(actor, intent, delta):
		_reangle()


# Presses the attack: the feint first, if it feints, else the option's action (held for a delayed swing). Its token is
# taken again (an attacker that holds one keeps it, for TIMEOUT more); with none to be had, the attack is off.
func _fire(actor: Actor, intent: Intent) -> void:
	if _plan.needs_token and not def.ignores_tokens and not AttackTokens.take_for(actor, target):
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
		AttackTokens.take_for(actor, target)  # each blow keeps its token


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
	if not _presses.is_empty() and actor.runner.window.has(_presses[0]):
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
# back, and it rests a little before choosing again.
func _drop_plan(actor: Actor) -> void:
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
	_stand_down(actor)
	mode = Mode.IDLE
	_noticed = 0.0
	_backing = false
	_back_off_due = false
	_retreat_left = 0.0
	_blocked = 0.0
	_reset_spacing()


func _give_back(actor: Actor) -> void:
	if not def.ignores_tokens:
		AttackTokens.give_back_for(actor)


# Whether the window of the actor's feint (its moveset's FEINT_ACTION move) takes `action`.
func _feint_takes(actor: Actor, action: StringName) -> bool:
	if not _feint_window.has(action):
		var takes := false
		for m in _marks_of(actor, FEINT_ACTION):
			if m["kind"] == &"cancel_open" and m["args"].get("into") is Dictionary and (m["args"]["into"] as Dictionary).has(action):
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


# --- helpers ---

# How far (degrees) the way `to` (world (x, z)) is off the actor's facing.
static func _off_facing(actor: Actor, to: Vector2) -> float:
	var facing := Vector2(actor.facing().x, actor.facing().z)
	return 0.0 if to.is_zero_approx() else absf(rad_to_deg(facing.angle_to(to)))


# The way from the actor to `point` on the ground plane, world (x, z).
static func _flat(actor: Actor, point: Vector3) -> Vector2:
	return Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z)
