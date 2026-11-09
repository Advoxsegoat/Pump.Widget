class_name Actor
extends CharacterBody3D
## Anyone who moves and fights: Abarax, and later his foes. This CharacterBody3D is the body (a capsule
## on the `actor` layer that collides with `world`); its Rig, made from the def's rig_scene and drawn in
## the def's palette, is how it looks; its Brain says what it wants (player, script, later an AI), and
## can be swapped at any time; its MoveRunner plays its moves, and Locomotion moves it when no move does.
##
## It fights through its HitScanner, which finds what its hitboxes strike, and Melee, which judges every hit of
## a frame once all actors have moved and hands each target its blow (apply_hit) and each attacker the result
## (hit_landed); all the blows a frame lands on it are taken together (apply_hits). Its HitIntake is what they do
## to it, and how it dies. A blow that lands has weight: Melee freezes both fighters for its hit-stop (freeze)
## and shoves the target (push). The actor joins the group `actors` when ready, which is how Melee finds every
## defender, and marks its rig's hurtbox with the meta `actor`, which is how a scanner knows whose body it
## reached. An enemy also joins the group `lockable` until it dies: the foes the player aims at.
##
## Two actors can play one move together, a paired move (start_paired: a finisher, a grab): each has the other as its
## paired_with while it plays, no one else's blow lands on either, their brains are ignored, and Melee keeps the two
## moves on one clock and aligns the two before each goes by its own root motion (Pairing). A palm pressed with a
## broken foe in reach (in the group `finishable` while it reels, within the tuning's finisher_range and
## finisher_arc_deg of the facing, facing the actor, with a clear line to it and room to align) starts the def's
## finisher on it instead of the jab (start_finisher_on, which the runner asks before starting a pressed move). A grab
## of the actor's that takes hold starts its def's grab_pair the same way, if the foe faces it and the pair can be staged
## (start_grab_on, which Melee asks); otherwise the grab is a HIT that staggers.
##
## Each physics frame, in this order:
##   1. frame += 1
##   2. the brain thinks, giving an Intent (not once the actor is dead: the dead want nothing; nor while it is in a
##      paired move, which plays out whatever the brain would want)
##   3. the intent's presses go into the input buffer, stamped with this frame's buffer_frame
##      Then, if the actor is frozen (hit-stop, see freeze), the frame is over: one frozen frame is counted off and
##      steps 4 to 13 do not happen, so its move, locomotion, velocity, stats, rig and scanner all stand still, while
##      the brain went on thinking and its presses wait in the buffer. They last 9 frames of the buffer's clock,
##      which stands still while frozen, so a freeze never uses up a press: one made just before a cancel window
##      opens still comes out on its first frame, however long the hit-stop in between
##   4. the runner ticks: the current move advances (its marks, a cancel window, its end; an attack that aims
##      first turns the body toward the intent's aim_target while it winds up, and a charge_hold mark held
##      stops the clock), or a buffered press starts one; this is how a press shows on the frame it is made.
##      Then the guard stance is kept (see `guarding`): up if a guard move just played out with guard held, down
##      if guard is let go, or palm or heavy is pressed with no move playing
##   5. on a frame with no move, locomotion turns the stick into a velocity, sprinting while dodge is held
##      (and the actor can act: an exhausted actor jogs instead; a guarding one only walks, slowly, and never
##      sprints), and with the intent's face_target set the body turns toward the target (at the turn rate)
##      rather than toward the way it goes, unless it sprints (a sprint runs where it goes, as in Souls); on a
##      frame a move ran (one that ended this frame too), the velocity is the move's root motion, and locomotion
##      takes it over, so it carries on from the move's speed when the move is done
##   6. a sprint spends sprint_stamina a second, and the stats are ticked: stamina and posture come back (stamina
##      slower while a guard is up)
##   7. move_and_slide, with gravity when off the floor, and with the knockback added (see push), which the
##      move and locomotion know nothing of; first its ground motion is cut where it would take the body into another
##      actor's (BodySpacing.keep_apart), so bodies do not pass through each other
##   8. the body turns to locomotion's facing
##   9. the rig is given the strafe (the way the body goes against the way it faces, when it keeps facing a
##      target), which says whether locomotion plays backward, then the speed (see _rig_speed: while a move
##      plays it is not the speed the move carries, which would show as a run under it), and its exertion
##      while sprinting
##  10. each foot is probed: a ray on `ik_surface` from 0.5 m above where the foot is in the clip's pose to
##      0.5 m below it, whose hit (or miss) the rig stands the foot on
##  11. the actor picks what to look at (the intent's look_target; else the nearest node in the group `poi`
##      within 6 m and 100° of its facing, an actor at its head; else nothing; the dead look at nothing) and the
##      rig turns its head to it
##  12. the rig is ticked: the only place it animates
##  13. the scanner sweeps the hitboxes that are on over this tick's pose, and what they struck is posted to
##      Melee, which applies it after every actor has run
## Holding dodge sprints only after the roll its press started is over, since locomotion does not run
## while a move does (Bloodborne-style: tap to roll, hold to run).

signal brain_changed(brain: Brain)
## A blow reached this actor and Melee judged it: `result` is what came of it. Emitted for every outcome, a
## WHIFF too, once the actor has taken the blow (apply_hit).
signal got_hit(result: HitResult, event: HitEvent)
## A blow this actor struck has been judged and `event.target` has taken it: `result` is what it came to.
signal hit_landed(result: HitResult, event: HitEvent)
## The actor died (die). Emitted once.
signal died
## A paired move began (start_paired): `kind` is its moment, &"finisher" or &"grab". Emitted on both of its fighters,
## for F4's camera dip and slow-motion beat to hook into.
signal combat_moment(kind: StringName)

## The action that, held, sprints.
const SPRINT_ACTION := &"dodge"
## Below this ground speed, in m/s, the body is not going anywhere, so it has no strafe.
const STRAFE_MIN_SPEED := 0.1
## The feet the rig plants, and the probe under each (on the ik_surface layer, the visible ground, steps and
## all): from PROBE_UP above the foot, PROBE_LENGTH down.
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const PROBE_UP := 0.5
const PROBE_LENGTH := 1.0
## Members of this group are points of interest: an actor glances at the nearest within LOOK_RANGE metres
## and LOOK_FIELD_DEG degrees of its facing, when its brain gives it nothing to look at.
const POI_GROUP := &"poi"
const LOOK_RANGE := 6.0
const LOOK_FIELD_DEG := 100.0
## Every actor is in this group from when it is ready: Melee takes a Defense of each before any of them moves.
const GROUP := &"actors"
## The foes the player can aim at: actors of team ENEMY, from when they are ready until they die. Aim assist picks
## its target from them, and lock-on will.
const LOCKABLE_GROUP := &"lockable"
## The action that raises the guard (the def's moveset names the raise) and, held as the raise plays out, keeps it
## up: the guard stance.
const GUARD_ACTION := &"guard"
## Pressing one of these drops the guard stance, to attack out of it.
const GUARD_DROPPED_BY: Array[StringName] = [&"palm", &"heavy"]
## The clip the rig lays over the upper body while the guard stance is up.
const GUARD_STANCE := &"guard_hold"
## The reaction a guarded blow plays: the guard stance stays up through it (HitIntake, hold_guard).
const GUARD_HIT := &"guard_hit"
## The action whose press, with a broken foe in reach, starts the def's finisher instead of its own move.
const FINISHER_ACTION := &"palm"
## Actors whose posture is broken, while they reel (HitIntake): the foes a finisher can be started on.
const FINISHABLE_GROUP := &"finishable"
## How far short of where its pair puts it a finisher's lunge may end (a wall in the way) and the finisher still start:
## further, and the palm is the jab (can_stage_finisher_on).
const FINISHER_STANCE_SLACK := 0.05

@export var def: ActorDef

var brain: Brain = Brain.new()
var stats: Stats
var buffer := InputBuffer.new()
## Physics frames this actor has lived; the first is frame 1.
var frame := 0
## `frame` less the frames spent frozen: the clock the input buffer keeps its time by (presses are stamped with it
## and age by it), so that hit-stop does not count toward the 9 frames a press is good for.
var buffer_frame := 0
var locomotion: Locomotion
## How it takes the blows Melee hands it, and dies (apply_hits and die are its front).
var intake: HitIntake
var rig: Rig
## The world point (Vector3) the actor chose to look at this frame, or null (see _physics_process, step 11).
var look_target: Variant = null
## Set for good by die().
var dead := false
## Finds what the hitboxes strike; the runner says when each comes on and goes off.
var scanner := HitScanner.new()
## Physics frames of hit-stop still to go (freeze).
var frozen := 0
## The guard stance is up: the guard held with no move playing, or through a guard_hit. It comes up when the def's
## guard raise (moveset `guard`) or its guard_hit plays out with guard held, or a guarded blow lands while guard is
## held (hold_guard); it goes down when guard is let go, palm or heavy is pressed with no move playing, or any other
## move starts. While it is up the rig shows GUARD_STANCE on the upper body, the body walks at the tuning's
## guard_speed_scale and never sprints, and stamina comes back slower. See is_guarding for whether a guard is up at
## all.
var guarding := false
## The other fighter of the paired move the actor is in (start_paired), or null. While it is set, no one else's blow
## lands on the actor (Defense.paired) and its brain is ignored.
var paired_with: Actor
## The paired move the actor is in, or null.
var pair: PairedMove
## Keeps its body out of other actors' (step 7): its motion on the ground stops at their capsules.
var spacing: BodySpacing

# The speed the rig's locomotion layer is given. With no move it is locomotion's. A move that starts is laid over
# that layer in its blend_in, so the layer keeps the speed it had until the move is fully in (dropping it to
# idle at once would pop the legs under a third of the move); then it eases down to 0 over the blend_in, so the
# speed a roll carries on from (locomotion.speed, root motion) never shows as a run under the move.
var _rig_speed := 0.0
var _push := Vector3.ZERO  # the knockback still to travel, in m/s on the ground plane (see push)
var _locked: Actor = null  # the foe the brain had locked on to on the latest frame (Intent.locked)
var _guard_held := false  # whether the brain held GUARD_ACTION on the latest frame
var _guard_move_ended := false  # a guard move (the raise, or guard_hit) played out on this frame

@onready var runner: MoveRunner = $MoveRunner


func _ready() -> void:
	if def == null or def.rig_scene == null:
		push_error("Actor: '%s' has no def with a rig_scene" % name)
		set_physics_process(false)
		return
	rig = def.rig_scene.instantiate() as Rig
	rig.name = &"Rig"
	add_child(rig)
	if def.palette != null:
		rig.apply_palette(def.palette)
	rig.hide_parts(def.hidden_parts)
	rig.set_model_scale(def.model_scale)
	stats = Stats.from_def(def)
	locomotion = Locomotion.new(def.locomotion)
	locomotion.facing_yaw = rotation.y
	runner.actor = self
	runner.move_started.connect(_on_move_started)
	runner.move_ended.connect(_on_move_ended)
	intake = HitIntake.new(self)
	spacing = BodySpacing.new(self, get_node_or_null(^"Body") as CollisionShape3D)
	rig.hurtbox.set_meta(&"actor", self)
	add_to_group(GROUP)
	if def.team == ActorDef.Team.ENEMY:
		add_to_group(LOCKABLE_GROUP)
	# Where in its breath each actor starts comes from its name, so that actors standing together do not
	# breathe in step. The hash is stirred (rand_from_seed) first: names that end in different characters,
	# like Knuckle2 and Knuckle3, hash to neighbours, which alone would put them a thousandth of a radian apart.
	rig.set_breath_phase(float(rand_from_seed(hash(name))[0] % 6283) / 1000.0)


## Hands the actor to `b` from the next frame on.
func set_brain(b: Brain) -> void:
	brain = b
	brain_changed.emit(b)


## Puts the actor at `at` (a spawn, a teleport): there, facing its +Z, at rest, with nothing for physics
## interpolation to smooth over from where it was. Call it once the actor is ready.
func place(at: Transform3D) -> void:
	global_transform = at.orthonormalized()
	velocity = Vector3.ZERO
	_push = Vector3.ZERO
	frozen = 0
	locomotion.speed = 0.0
	locomotion.facing_yaw = rotation.y
	reset_physics_interpolation()


## The way the body faces, in the world: its +Z.
func facing() -> Vector3:
	return global_basis.z


## Turns the body to face `yaw` (radians about up; 0 faces +Z) at once, with no turn rate, and locomotion
## with it so that it carries on from there. What a roll does to face the stick, and an aim assist to face a foe.
func snap_facing(yaw: float) -> void:
	locomotion.facing_yaw = yaw
	rotation.y = yaw


## Where others look at this actor: its head, def.look_height above its feet.
func head_point() -> Vector3:
	return global_position + Vector3.UP * def.look_height


## The actor's chest, in the world: Pairing.HIT_HEIGHT of its look_height above its feet. A finisher's line is drawn
## from the chest of the one finishing to the foe's (can_stage_finisher_on).
func chest_point() -> Vector3:
	return global_position + Vector3.UP * def.look_height * Pairing.HIT_HEIGHT


## Hit-stop: the actor stands still for `frames` physics frames (a blow that lands freezes both fighters; Melee
## does it). Frozen, its move runner, locomotion, velocity and rig do not tick, so everything holds the pose of
## the frame the blow landed on; its brain still thinks and its presses are buffered, so one made while frozen
## comes out as soon as the move can take it. A freeze that is on already is kept if it is the longer, never
## added to: two blows on one frame, or a trade, freeze for the longest of them. A knockback waits out the freeze.
func freeze(frames: int) -> void:
	frozen = maxi(frozen, frames)


## Knockback: shoves the actor along the ground by `velocity` (m/s; only its horizontal part counts), added to
## whatever else moves it, and dying away by the tuning's knockback_decay a second, so it travels about
## `velocity` over the decay in all (1.5 m/s at a decay of 10 is 0.15 m). It goes through move_and_slide, so a
## wall stops it, and pushes add up. It does not run while the actor is frozen.
func push(velocity: Vector3) -> void:
	_push += Vector3(velocity.x, 0.0, velocity.z)


## True while a move's marks make the actor invulnerable (a roll's iframes).
func is_invulnerable() -> bool:
	return runner.iframes


## Starts the paired move `with_pair` with the actor as its lead and `other` as its follower, and returns true; or
## refuses and returns false, when either of them is dead, already paired or invulnerable (or `other` is the actor
## itself). Both are paired at once (paired_with, pair): from now on no one else's blow lands on either, their brains
## are ignored, and what they had pressed is forgotten. Both moves start on this frame, after every actor has moved,
## whatever the stamina, and Melee plays the pair from there (Pairing): the lead is free again when its move ends, the
## follower when its own has. combat_moment is emitted on both.
func start_paired(other: Actor, with_pair: PairedMove) -> bool:
	if with_pair == null or other == null or other == self:
		return false
	for actor: Actor in [self, other]:
		if actor.dead or actor.paired_with != null or actor.is_invulnerable():
			return false
	Melee.begin_pair(Pairing.new(self, other, with_pair))
	combat_moment.emit(with_pair.moment)
	other.combat_moment.emit(with_pair.moment)
	return true


## The foe the actor would finish now, for the HUD's prompt and for a palm press: the one it has locked on to
## (the intent's `locked`) if it is one it could finish by the rules below, else the nearest live, unpaired actor of
## the other team in the group `finishable` (its posture broken, reeling) within the tuning's finisher_range on the
## ground and finisher_arc_deg either side of the facing, that faces the actor (within finisher_facing_deg) and can be
## staged where the two stand (can_stage_finisher_on: a clear line, and room to align). Null if there is none, or the
## actor has no finisher, or is dead or paired itself.
func finishable_target() -> Actor:
	if def.finisher == null or dead or paired_with != null:
		return null
	var reach := stats.tuning.finisher_range
	if is_instance_valid(_locked) and _locked.is_in_group(FINISHABLE_GROUP) and _can_finish(_locked, reach):
		return _locked
	var best: Actor = null
	var best_distance := reach
	for node in get_tree().get_nodes_in_group(FINISHABLE_GROUP):
		var foe := node as Actor
		if foe == null or not _can_finish(foe, best_distance):
			continue
		best = foe
		best_distance = _flat_to(foe.global_position).length()
	return best


# Whether `foe` (in the group finishable) is one to finish now: live, unpaired, of the other team, within `reach` on the
# ground and in the arc of the facing, facing the actor, and able to be staged (can_stage_finisher_on).
func _can_finish(foe: Actor, reach: float) -> bool:
	if foe == self or foe.dead or foe.paired_with != null or foe.def.team == def.team:
		return false
	var flat := _flat_to(foe.global_position)
	if flat.length() > reach:
		return false
	if not flat.is_zero_approx() and absf(angle_difference(locomotion.facing_yaw, Locomotion.yaw_of(flat))) > deg_to_rad(stats.tuning.finisher_arc_deg):
		return false
	return faces_me(foe) and can_stage_finisher_on(foe)


## Whether `foe` faces the actor, within the tuning's finisher_facing_deg: a paired move's follower turns to face its
## lead about the middle of its feet as the pair begins (Pairing), and turned further its planted feet would slide.
func faces_me(foe: Actor) -> bool:
	var flat := _flat_to(foe.global_position)
	return flat.is_zero_approx() or absf(angle_difference(foe.rotation.y, Locomotion.yaw_of(-flat))) <= deg_to_rad(stats.tuning.finisher_facing_deg)


## Whether the def's finisher can be staged on `foe` from where the two stand (can_stage_pair_on). A wall between them,
## or one that would stop the lunge short, makes a palm the jab.
func can_stage_finisher_on(foe: Actor) -> bool:
	return def.finisher != null and can_stage_pair_on(foe, def.finisher)


## Whether the paired move `with_pair` can be staged with the actor as its lead and `foe` as its follower from where the
## two stand: nothing on the `world` layer between the actor's chest and the foe's, and the lunge that aligns them
## (Pairing: the actor closing, or backing off, to where the pair's offset puts it, Pairing.offset_of, gliding with
## collision in align_frames steps as it will) ending within FINISHER_STANCE_SLACK of that spot.
func can_stage_pair_on(foe: Actor, with_pair: PairedMove) -> bool:
	var space := get_world_3d().direct_space_state
	var line := PhysicsRayQueryParameters3D.create(chest_point(), foe.chest_point(), Layers.WORLD, [get_rid(), foe.get_rid()])
	if not space.intersect_ray(line).is_empty():
		return false
	var goal := Pairing.follower_faced(global_position, foe, Pairing.feet_middle(foe)) * Pairing.offset_of(with_pair, self).affine_inverse()
	var lunge := goal.origin - global_position
	var steps := maxi(with_pair.align_frames, 1)
	var at := global_transform
	for i in steps:
		at = _glided(at, lunge / steps)
	return Vector2(at.origin.x - goal.origin.x, at.origin.z - goal.origin.z).length() <= FINISHER_STANCE_SLACK


## A grab of the actor's has taken hold of `foe` (a GRABBED blow; Melee asks): when the def has a grab_pair and it can be
## staged as the finisher can (the foe faces the actor, faces_me; a clear line and room, can_stage_pair_on), it starts
## (start_paired) and this returns true; otherwise false, and the grab is taken as a HIT that staggers.
func start_grab_on(foe: Actor) -> bool:
	var pair := def.grab_pair
	return pair != null and faces_me(foe) and can_stage_pair_on(foe, pair) and start_paired(foe, pair)


## A press of `action` is about to start a move (the runner asks, from rest and in a cancel window): when it is the
## FINISHER_ACTION and there is a foe to finish (finishable_target), the def's finisher starts on it instead, and this
## returns true; otherwise false, and the press starts its move.
func start_finisher_on(action: StringName) -> bool:
	if action != FINISHER_ACTION:
		return false
	var target := finishable_target()
	return target != null and start_paired(target, def.finisher)


## Moves the actor by `offset` along the ground (its height is left out), stopping at the world as move_and_slide
## would, and sliding once along what it meets: a paired move's lead closing on its follower, and the follower turning
## about its feet (Pairing).
func glide(offset: Vector3) -> void:
	global_transform = _glided(global_transform, offset)


## True while a guard is up: a move's guard_on mark (guard_raise from its f4), the guard stance (`guarding`), or the
## def's guard raise played while guard is held, from its first frame. So a held guard has no gap where a raise
## starts: not where one chains onto the last as it ends, nor where guard is pressed again, even when the raise came
## too soon after the last to open a parry window (CombatTuning.parry_refresh_frames).
func is_guarding() -> bool:
	return runner.guard_window or guarding or (_guard_held and _raising())


## Keeps the guard up if guard is held: a guarded blow calls it as its guard_hit starts (HitIntake), so the guard
## stays up through the reaction (even one that cut short the raise whose mark held it up) and after it.
func hold_guard() -> void:
	if _guard_held:
		_set_guarding(true)


## Takes the blow `e`, which Melee judged to come to `r`, on its own: apply_hits with that one blow.
func apply_hit(e: HitEvent, r: HitResult) -> void:
	var events: Array[HitEvent] = [e]
	var results: Array[HitResult] = [r]
	apply_hits(events, results)


## Takes every blow that landed on the actor in one frame (`events`, and what Melee judged each to come to,
## `results`) together, with those of its own blows that were turned back that frame (`turned`, PARRIED or CAUGHT,
## and `turned_results`), so that what comes of them does not depend on the order they are taken in: their
## numbers, their kicks, then one reaction or the death (HitIntake.take). got_hit is emitted for each blow after.
func apply_hits(events: Array[HitEvent], results: Array[HitResult], turned: Array[HitEvent] = [],
		turned_results: Array[HitResult] = []) -> void:
	intake.take(events, results, turned, turned_results)


## Kills the actor, once (HitIntake.die): it plays its def's `death` reaction, its hurtbox goes off, what it had
## pressed is forgotten and its brain is ignored from then on, and `died` is emitted. When the death clip ends,
## the body leaves the `actor` layer and lies as the clip left it. One `lying` already (a paired move left it on the
## ground) plays no death clip: it leaves the layer at once and stays as it lies.
func die(lying := false) -> void:
	intake.die(lying)


func _physics_process(delta: float) -> void:
	frame += 1
	if frozen == 0:
		buffer_frame += 1
	var intent: Intent = brain.think(self, delta) if brain != null and not dead and paired_with == null else null
	if intent == null:
		intent = Intent.new()
	for action in intent.pressed:
		buffer.push(action, buffer_frame)
	_guard_held = intent.held.has(GUARD_ACTION)
	_locked = intent.locked
	if frozen > 0:
		frozen -= 1
		return
	var moved_by_move := runner.busy()
	var facing_before := locomotion.facing_yaw
	var planar := runner.tick(intent, delta)
	_keep_guard(intent)
	if moved_by_move or runner.busy():
		locomotion.carry(planar)
	else:
		var sprint := intent.held.has(SPRINT_ACTION) and stats.can_act()
		planar = locomotion.tick(intent.move, sprint, delta, stats.tuning.guard_speed_scale if guarding else 0.0)
		if _keeps_facing(intent):
			var to_target := _flat_to(intent.face_target)
			if not to_target.is_zero_approx():
				locomotion.facing_yaw = Locomotion.turn_toward(facing_before, Locomotion.yaw_of(to_target),
						deg_to_rad(locomotion.tuning.turn_rate_deg) * delta)
	if locomotion.sprinting:
		stats.drain_stamina(stats.tuning.sprint_stamina, delta)
	stats.tick(delta, is_guarding())
	var fall := velocity.y
	if not is_on_floor():
		fall += get_gravity().y * delta
	var shove := _next_push(delta)
	velocity = spacing.keep_apart(Vector3(planar.x + shove.x, fall, planar.z + shove.z), delta)
	move_and_slide()
	rotation.y = locomotion.facing_yaw
	var back := rig.set_strafe(_strafe_angle(intent, planar))
	rig.set_locomotion(_next_rig_speed(delta), back)
	if locomotion.sprinting:
		rig.set_exertion(1.0)
	_probe_feet()
	look_target = null if dead else _choose_look_target(intent)
	rig.look_at_point(look_target)
	rig.tick(delta)
	for e in scanner.scan(self):
		Melee.post(e)


# Where glide(offset) would leave the actor if it stood at `from`, found without moving it: the motion is tried
# (test_move), and what is left of it where it meets the world is slid along what it met and tried once more.
func _glided(from: Transform3D, offset: Vector3) -> Transform3D:
	var motion := Vector3(offset.x, 0.0, offset.z)
	var hit := KinematicCollision3D.new()
	if not test_move(from, motion, hit):
		return from.translated(motion)
	var at := from.translated(hit.get_travel())
	var rest := hit.get_remainder().slide(hit.get_normal())
	rest.y = 0.0
	if not test_move(at, rest, hit):
		return at.translated(rest)
	return at.translated(hit.get_travel())


# The guard stance for this frame, once the runner has ticked: up when a guard move played out on this frame with
# guard held and nothing else has started; down when guard is let go, or when palm or heavy is pressed in the stance
# proper, with no move playing (whether or not the attack can start). A press while a move plays (a guard_hit, which
# takes no attack before its cancel window) waits in the buffer and leaves the guard up: the attack takes it down
# when it starts (_on_move_started).
func _keep_guard(intent: Intent) -> void:
	var attacking := not runner.busy() and intent.pressed.any(func(action: StringName) -> bool: return GUARD_DROPPED_BY.has(action))
	if not _guard_held or attacking:
		_set_guarding(false)
	elif _guard_move_ended and not runner.busy():
		_set_guarding(true)
	_guard_move_ended = false


# Whether the move playing is the def's guard raise (moveset `guard`).
func _raising() -> bool:
	return runner.current != null and runner.current.id == def.moveset.get(GUARD_ACTION, &"")


func _set_guarding(on: bool) -> void:
	if on == guarding:
		return
	guarding = on
	rig.set_stance(GUARD_STANCE, on)


# Any move but guard_hit takes the guard stance down: an attack or a roll out of it, a reaction, the death.
func _on_move_started(move: MoveData) -> void:
	if guarding and move.id != def.reactions.get(GUARD_HIT, &""):
		_set_guarding(false)


# The raise or guard_hit played out: the guard stance comes up this frame if guard is still held (_keep_guard).
func _on_move_ended(move: MoveData, cancelled: bool) -> void:
	if not cancelled and (move.id == def.moveset.get(GUARD_ACTION, &"") or move.id == def.reactions.get(GUARD_HIT, &"")):
		_guard_move_ended = true


# The knockback's velocity for this frame, and the push left after it: _push is the velocity at the start of the
# frame and decays exponentially, so the frame moves by its average over the frame, (1 - e^(-k delta)) / (k delta)
# of it. That way the whole push travels _push / k however long the frames are.
func _next_push(delta: float) -> Vector3:
	if _push.is_zero_approx():
		_push = Vector3.ZERO
		return Vector3.ZERO
	var k := maxf(stats.tuning.knockback_decay, 0.001)
	var keep := exp(-k * delta)
	var shove := _push * ((1.0 - keep) / (k * delta))
	_push *= keep
	return shove


# _rig_speed for this frame (see there).
func _next_rig_speed(delta: float) -> float:
	if not runner.busy():
		_rig_speed = locomotion.speed
	elif rig.move_weight() >= 1.0:
		var blend_in := maxf(runner.current.blend_in, delta)
		_rig_speed = move_toward(_rig_speed, 0.0, locomotion.tuning.sprint_speed / blend_in * delta)
	return _rig_speed


# Casts each foot's probe and hands the rig what it hit: {position, normal}, or null.
func _probe_feet() -> void:
	var space := get_world_3d().direct_space_state
	for foot in FEET:
		var from := rig.animated_foot(foot) + Vector3.UP * PROBE_UP
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * PROBE_LENGTH, Layers.IK_SURFACE, [get_rid()])
		var hit := space.intersect_ray(query)
		rig.set_foot_ground(foot, null if hit.is_empty() else {position = hit.position, normal = hit.normal})


# What to look at: the intent's look_target; failing that, the nearest point of interest (a Node3D in
# POI_GROUP, not this actor or part of it) within LOOK_RANGE and LOOK_FIELD_DEG of the facing, where an
# actor's point is its head; or null.
func _choose_look_target(intent: Intent) -> Variant:
	if intent.look_target is Vector3:
		return intent.look_target
	var best: Variant = null
	var best_distance := LOOK_RANGE
	for node in get_tree().get_nodes_in_group(POI_GROUP):
		var poi := node as Node3D
		if poi == null or poi == self or is_ancestor_of(poi):
			continue
		var point := (poi as Actor).head_point() if poi is Actor else poi.global_position
		var distance := global_position.distance_to(point)
		if distance > best_distance:
			continue
		var flat := _flat_to(point)
		if not flat.is_zero_approx() and absf(angle_difference(locomotion.facing_yaw, Locomotion.yaw_of(flat))) > deg_to_rad(LOOK_FIELD_DEG):
			continue
		best = point
		best_distance = distance
	return best


# Whether the body keeps facing the intent's face_target: it has one, and is not sprinting.
func _keeps_facing(intent: Intent) -> bool:
	return intent.face_target is Vector3 and not locomotion.sprinting


# The way the body goes (`planar`, its ground velocity) against the way it faces, in radians about up, while
# it keeps facing a target; 0 when it does not, or is not going anywhere.
func _strafe_angle(intent: Intent, planar: Vector3) -> float:
	var flat := Vector2(planar.x, planar.z)
	if not _keeps_facing(intent) or flat.length() < STRAFE_MIN_SPEED:
		return 0.0
	return angle_difference(locomotion.facing_yaw, Locomotion.yaw_of(flat))


# The way from the body to `point` on the ground plane, world (x, z).
func _flat_to(point: Vector3) -> Vector2:
	return Vector2(point.x - global_position.x, point.z - global_position.z)
