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
##      target), which says whether locomotion plays backward, then the speed, its exertion while
##      sprinting, and is ticked: the only place it animates
## Holding dodge sprints only after the roll its press started is over, since locomotion does not run
## while a move does (Bloodborne-style: tap to roll, hold to run).

signal brain_changed(brain: Brain)

## The action that, held, sprints.
const SPRINT_ACTION := &"dodge"
## Below this ground speed, in m/s, the body is not going anywhere, so it has no strafe.
const STRAFE_MIN_SPEED := 0.1

@export var def: ActorDef

var brain: Brain = Brain.new()
var stats: Stats
var buffer := InputBuffer.new()
## Physics frames this actor has lived; the first is frame 1. Presses are buffered by it.
var frame := 0
var locomotion: Locomotion
var rig: Rig

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
	rig.tick(delta)


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
