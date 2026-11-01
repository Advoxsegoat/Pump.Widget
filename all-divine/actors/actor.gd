class_name Actor
extends CharacterBody3D
## Anyone who moves and fights: Abarax, and later his foes. This CharacterBody3D is the body (a capsule
## on the `actor` layer that collides with `world`); its Rig, made from the def's rig_scene and drawn in
## the def's palette, is how it looks; its Brain says what it wants (player, script, later an AI), and
## can be swapped at any time; its MoveRunner plays its moves, and Locomotion moves it when no move does.
##
## It fights through its HitScanner, which finds what its hitboxes strike, and Melee, which judges every hit of
## a frame once all actors have moved and hands each target its blow (apply_hit) and each attacker the result
## (hit_landed). The actor joins the group `actors` when ready, which is how Melee finds every defender, and
## marks its rig's hurtbox with the meta `actor`, which is how a scanner knows whose body it reached.
##
## Each physics frame, in this order:
##   1. frame += 1
##   2. the brain thinks, giving an Intent (not once the actor is dead: the dead want nothing)
##   3. the intent's presses go into the input buffer, stamped with this frame
##   4. the runner ticks: the current move advances (its marks, a cancel window, its end), or a buffered
##      press starts one; this is how a press shows on the frame it is made
##   5. on a frame with no move, locomotion turns the stick into a velocity, sprinting while dodge is held
##      (and the actor can act: an exhausted actor jogs instead), and with the intent's face_target set the
##      body turns toward the target (at the turn rate) rather than toward the way it goes, unless it sprints
##      (a sprint runs where it goes, as in Souls); on a frame a move ran (one that ended this frame too), the
##      velocity is the move's root motion, and locomotion takes it over, so it carries on from the move's
##      speed when the move is done
##   6. a sprint spends sprint_stamina a second, and the stats are ticked: stamina and posture come back
##   7. move_and_slide, with gravity when off the floor
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
## How hard a blow kicks the upper body (Rig.hit_react): HIT_REACT_BASE plus its poise damage over
## HIT_REACT_POISE, so a jab (6) is 0.8 and a blow of 10 poise damage is 1.
const HIT_REACT_BASE := 0.5
const HIT_REACT_POISE := 20.0

@export var def: ActorDef

var brain: Brain = Brain.new()
var stats: Stats
var buffer := InputBuffer.new()
## Physics frames this actor has lived; the first is frame 1. Presses are buffered by it.
var frame := 0
var locomotion: Locomotion
var rig: Rig
## The world point (Vector3) the actor chose to look at this frame, or null (see _physics_process, step 11).
var look_target: Variant = null
## Set for good by die().
var dead := false
## Finds what the hitboxes strike; the runner says when each comes on and goes off.
var scanner := HitScanner.new()

# The speed the rig's locomotion layer is given. With no move it is locomotion's. A move that starts is laid over
# that layer in its blend_in, so the layer keeps the speed it had until the move is fully in (dropping it to
# idle at once would pop the legs under a third of the move); then it eases down to 0 over the blend_in, so the
# speed a roll carries on from (locomotion.speed, root motion) never shows as a run under the move.
var _rig_speed := 0.0
var _death: MoveData  # the death move once die() has started it

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
	stats = Stats.from_def(def)
	locomotion = Locomotion.new(def.locomotion)
	locomotion.facing_yaw = rotation.y
	runner.actor = self
	runner.move_ended.connect(_on_move_ended)
	rig.hurtbox.set_meta(&"actor", self)
	add_to_group(GROUP)
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


## True while a move's marks make the actor invulnerable (a roll's iframes).
func is_invulnerable() -> bool:
	return runner.iframes


## Takes the blow `e`, which Melee judged to come to `r`: what `r` takes off comes off its HP, posture and
## stamina. A HIT or a GUARDED blow (and a GRABBED one, a HIT for now) kicks the upper body away from it
## (Rig.hit_react, harder the more poise damage it carries): the additive flinch every blow gets, whether or
## not it interrupts what the actor is doing. A blow that empties the HP kills the actor (die); otherwise a
## FLINCH or a STAGGER plays the def's `flinch` or `stagger` reaction move, cutting off the move that was
## playing. A WHIFF changes nothing, nor does a blow on the dead (one that died to an earlier blow of the same
## frame). got_hit is emitted after, whatever the outcome.
func apply_hit(e: HitEvent, r: HitResult) -> void:
	if not dead and r.outcome != HitResult.Outcome.WHIFF:
		_take(e, r)
	got_hit.emit(r, e)


## Kills the actor, once: it plays its def's `death` reaction, its hurtbox goes off (no blow finds it again),
## what it had pressed is forgotten and its brain is ignored from then on, and `died` is emitted. When the death
## clip ends, the body leaves the `actor` layer and lies as the clip left it (at once, with no death clip).
func die() -> void:
	if dead:
		return
	dead = true
	buffer.clear()
	rig.hurtbox.collision_layer = 0
	_death = _reaction_move(&"death")
	if _death != null:
		runner.start(_death)
	else:
		collision_layer &= ~Layers.ACTOR
	died.emit()


func _physics_process(delta: float) -> void:
	frame += 1
	var intent: Intent = brain.think(self, delta) if brain != null and not dead else null
	if intent == null:
		intent = Intent.new()
	for action in intent.pressed:
		buffer.push(action, frame)
	var moved_by_move := runner.busy()
	var facing_before := locomotion.facing_yaw
	var planar := runner.tick(intent, delta)
	if moved_by_move or runner.busy():
		locomotion.carry(planar)
	else:
		planar = locomotion.tick(intent.move, intent.held.has(SPRINT_ACTION) and stats.can_act(), delta)
		if _keeps_facing(intent):
			var to_target := _flat_to(intent.face_target)
			if not to_target.is_zero_approx():
				locomotion.facing_yaw = Locomotion.turn_toward(facing_before, Locomotion.yaw_of(to_target),
						deg_to_rad(locomotion.tuning.turn_rate_deg) * delta)
	if locomotion.sprinting:
		stats.drain_stamina(stats.tuning.sprint_stamina, delta)
	# Guarding comes with the guard (it slows stamina's return); nothing holds one yet.
	stats.tick(delta, false)
	var fall := velocity.y
	if not is_on_floor():
		fall += get_gravity().y * delta
	velocity = Vector3(planar.x, fall, planar.z)
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


# The numbers of apply_hit, the kick, then the death or the reaction.
func _take(e: HitEvent, r: HitResult) -> void:
	if r.outcome in [HitResult.Outcome.HIT, HitResult.Outcome.GUARDED, HitResult.Outcome.GRABBED]:
		rig.hit_react(e.direction, HIT_REACT_BASE + e.profile.poise_damage / HIT_REACT_POISE)
	if r.stamina_cost > 0.0:
		stats.spend_stamina(r.stamina_cost)
	if r.posture_damage > 0.0:
		stats.damage_posture(r.posture_damage)
	if stats.take_damage(r.hp_damage):
		die()
		return
	match r.reaction:
		HitResult.Reaction.FLINCH:
			_react(&"flinch")
		HitResult.Reaction.STAGGER:
			_react(&"stagger")


# Plays the def's reaction move `reaction`, if it has one.
func _react(reaction: StringName) -> void:
	var move := _reaction_move(reaction)
	if move != null:
		runner.start(move)


# The move the def's reactions name for `reaction`, or null if it names none.
func _reaction_move(reaction: StringName) -> MoveData:
	if not def.reactions.has(reaction):
		return null
	return Registry.fetch(&"moves", StringName(def.reactions[reaction])) as MoveData


# A death clip that has played out: the body leaves the `actor` layer, and the rig is held on the clip's last
# pose (the runner fades a move that ends back to locomotion, which would stand the body up again).
func _on_move_ended(move: MoveData, cancelled: bool) -> void:
	if not dead or move != _death or cancelled:
		return
	collision_layer &= ~Layers.ACTOR
	rig.play_move(move.clip, 0.0)
	rig.set_move_time(rig.tree.get_animation(move.clip).length)


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
