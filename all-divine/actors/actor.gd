class_name Actor
extends CharacterBody3D
## Anyone who moves and fights: Abarax, and later his foes. This CharacterBody3D is the body (a capsule
## on the `actor` layer that collides with `world`); its Rig, made from the def's rig_scene and drawn in
## the def's palette, is how it looks; its Brain says what it wants (player, script, later an AI), and
## can be swapped at any time; its MoveRunner plays its moves, and Locomotion moves it when no move does.
##
## Each physics frame, in this order:
##   1. frame += 1
##   2. the brain thinks, giving an Intent
##   3. the intent's presses go into the input buffer, stamped with this frame
##   4. the runner ticks: the current move advances (its marks, a cancel window, its end), or a buffered
##      press starts one; this is how a press shows on the frame it is made
##   5. on a frame with no move, locomotion turns the stick into a velocity, sprinting while dodge is held,
##      and with the intent's face_target set the body turns toward the target (at the turn rate) rather
##      than toward the way it goes, unless it sprints (a sprint runs where it goes, as in Souls); on a
##      frame a move ran (one that ended this frame too), the velocity is the move's root motion, and
##      locomotion takes it over, so it carries on from the move's speed when the move is done
##   6. move_and_slide, with gravity when off the floor
##   7. the body turns to locomotion's facing
##   8. the rig is given the strafe (the way the body goes against the way it faces, when it keeps facing a
##      target), which says whether locomotion plays backward, then the speed, and its exertion while
##      sprinting
##   9. each foot is probed: a ray on `ik_surface` from 0.5 m above where the foot is in the clip's pose to
##      0.5 m below it, whose hit (or miss) the rig stands the foot on
##  10. the actor picks what to look at (the intent's look_target; else the nearest node in the group `poi`
##      within 6 m and 100° of its facing; else nothing) and the rig turns its head to it
##  11. the rig is ticked: the only place it animates
## Holding dodge sprints only after the roll its press started is over, since locomotion does not run
## while a move does (Bloodborne-style: tap to roll, hold to run).

signal brain_changed(brain: Brain)

## The action that, held, sprints.
const SPRINT_ACTION := &"dodge"
## Below this ground speed, in m/s, the body is not going anywhere, so it has no strafe.
const STRAFE_MIN_SPEED := 0.1
## The feet the rig plants, and the probe under each: from PROBE_UP above the foot, PROBE_LENGTH down.
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const PROBE_UP := 0.5
const PROBE_LENGTH := 1.0
## The physics layer the feet stand on (ik_surface, layer 2): the visible ground, steps and all.
const IK_SURFACE_MASK := 1 << 1
## Members of this group are points of interest: an actor glances at the nearest within LOOK_RANGE metres
## and LOOK_FIELD_DEG degrees of its facing, when its brain gives it nothing to look at.
const POI_GROUP := &"poi"
const LOOK_RANGE := 6.0
const LOOK_FIELD_DEG := 100.0

@export var def: ActorDef

var brain: Brain = Brain.new()
var stats: Stats
var buffer := InputBuffer.new()
## Physics frames this actor has lived; the first is frame 1. Presses are buffered by it.
var frame := 0
var locomotion: Locomotion
var rig: Rig
## The world point (Vector3) the actor chose to look at this frame, or null (see _physics_process, step 10).
var look_target: Variant = null

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


## True while a move's marks make the actor invulnerable (a roll's iframes).
func is_invulnerable() -> bool:
	return runner.iframes


func _physics_process(delta: float) -> void:
	frame += 1
	var intent: Intent = brain.think(self, delta) if brain != null else null
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
		planar = locomotion.tick(intent.move, intent.held.has(SPRINT_ACTION), delta)
		if _keeps_facing(intent):
			var to_target := _flat_to(intent.face_target)
			if not to_target.is_zero_approx():
				locomotion.facing_yaw = Locomotion.turn_toward(facing_before, Locomotion.yaw_of(to_target),
						deg_to_rad(locomotion.tuning.turn_rate_deg) * delta)
	var fall := velocity.y
	if not is_on_floor():
		fall += get_gravity().y * delta
	velocity = Vector3(planar.x, fall, planar.z)
	move_and_slide()
	rotation.y = locomotion.facing_yaw
	var back := rig.set_strafe(_strafe_angle(intent, planar))
	rig.set_locomotion(locomotion.speed, back)
	if locomotion.sprinting:
		rig.set_exertion(1.0)
	_probe_feet()
	look_target = _choose_look_target(intent)
	rig.look_at_point(look_target)
	rig.tick(delta)


# Casts each foot's probe and hands the rig what it hit: {position, normal}, or null.
func _probe_feet() -> void:
	var space := get_world_3d().direct_space_state
	for foot in FEET:
		var from := rig.animated_foot(foot) + Vector3.UP * PROBE_UP
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * PROBE_LENGTH, IK_SURFACE_MASK, [get_rid()])
		var hit := space.intersect_ray(query)
		rig.set_foot_ground(foot, null if hit.is_empty() else {position = hit.position, normal = hit.normal})


# What to look at: the intent's look_target; failing that, the nearest point of interest (a Node3D in
# POI_GROUP, not this actor or part of it) within LOOK_RANGE and LOOK_FIELD_DEG of the facing; or null.
func _choose_look_target(intent: Intent) -> Variant:
	if intent.look_target is Vector3:
		return intent.look_target
	var best: Variant = null
	var best_distance := LOOK_RANGE
	for node in get_tree().get_nodes_in_group(POI_GROUP):
		var poi := node as Node3D
		if poi == null or poi == self or is_ancestor_of(poi):
			continue
		var point := poi.global_position
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
