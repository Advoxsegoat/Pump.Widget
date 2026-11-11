class_name PlayerBrain
extends Brain
## The player: the move stick turned from the screen into the world by the camera's yaw, the gameplay
## buttons pressed this frame and held, and where he aims.
##
## The aim is two things (see _aim). On the keyboard and mouse, with no foe locked on to, he faces the cursor
## (face_target is the point of the ground under it), since there is no stick to say where he looks. And his
## attacks turn him toward a foe (aim_target): the lock-on target when there is one; otherwise the nearest live
## foe (the group `lockable`) within the tuning's aim_assist_range and aim_assist_deg of the direction he means (the
## stick, or the way he faces when it rests, or the cursor on the keyboard and mouse); otherwise, on the keyboard
## and mouse, the cursor's ground point itself, so a swing turns him to where the player points rather than along a
## facing that trails the cursor; otherwise (a stick) nothing.
##
## Sway and duck (spec 2): guard held (or pressed on this very frame) and a direction pressed on this frame is a sway,
## or a duck when the screen direction is within DUCK_CONE_DEG of straight down; the intent presses `sway` or `duck`
## with the evade_dir (the camera's yaw turns the screen into the world), and a `guard` press of the same frame is
## dropped, so a direction and guard together are a sway and not a parry. A direction that was down before guard was
## presses nothing (Inputs.direction_pressed_this_frame is a press, not a hold).
##
## Lock-on (see LockOn): lock_on locks the foe in the picture that the cursor, the stick or his facing (in that order) points
## at, or lets go. While locked, target_left and target_right (a flick of the right stick), and the wheel, move to the
## foe to the right or left of it on the screen, he
## faces the foe's head whatever the device, his attacks turn to it and track it through the swing, the camera leans
## to it, and a palm that can finish it finishes it. The lock lets go of a foe that dies or goes too far, and nothing
## else changes then: a swing under way carries on, and aim assist is back to the stick.

## How far from straight down the screen a direction may point and still be a duck, in degrees.
const DUCK_CONE_DEG := 45.0

## The camera's yaw (CameraRig.yaw()). At 0 the camera looks along -Z, so pushing up goes to -Z and
## pushing right to +X; a turned camera turns the stick with it.
var view_yaw := 0.0
## Which foe he has locked on to.
var lock := LockOn.new()

var _watched: Actor


func think(actor: Actor, _delta: float) -> Intent:
	var intent := Intent.new()
	var screen := screen_move()
	var world := Vector3(screen.x, 0.0, screen.y).rotated(Vector3.UP, view_yaw)
	intent.move = Vector2(world.x, world.z)
	intent.pressed = pressed_actions()
	intent.held = held_actions()
	_evade(intent)
	if actor != null:
		_lock(actor, intent)
		_aim(actor, intent)
	return intent


## The gameplay actions that went down this frame.
func pressed_actions() -> Array[StringName]:
	return Inputs.pressed_this_frame()


## The gameplay actions that are down this frame.
func held_actions() -> Array[StringName]:
	var held: Array[StringName] = []
	for action in Inputs.GAMEPLAY:
		if Inputs.held(action):
			held.append(action)
	return held


## The screen direction of a move key or stick flick that went down this frame, or zero (Inputs).
func direction_pressed() -> Vector2:
	return Inputs.direction_pressed_this_frame()


## The movement the player asks for on screen: right is +x, up is -y, length 0 to 1, deadzone out.
## Every connected gamepad and the keys (Inputs.move_vector()).
func screen_move() -> Vector2:
	return Inputs.move_vector()


## Where the mouse is, in the window: the coordinates of the root viewport, which the PixelStage is drawn in (not
## the actor's own, the World viewport inside it, where the mouse never is).
func mouse_position(actor: Actor) -> Vector2:
	return actor.get_tree().root.get_mouse_position()


# A direction pressed with guard held, or going down with it this frame, is a sway or a duck (see the top).
func _evade(intent: Intent) -> void:
	var direction := direction_pressed()
	if direction == Vector2.ZERO or not (intent.held.has(Actor.GUARD_ACTION) or intent.pressed.has(Actor.GUARD_ACTION)):
		return
	while intent.pressed.has(Actor.GUARD_ACTION):
		intent.pressed.erase(Actor.GUARD_ACTION)
	var ducks := absf(direction.angle_to(Vector2.DOWN)) <= deg_to_rad(DUCK_CONE_DEG) + 1e-4
	intent.pressed.append(Actor.DUCK_ACTION if ducks else Actor.SWAY_ACTION)
	var world := Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, view_yaw)
	intent.evade_dir = Vector2(world.x, world.z)


# Lock-on: lets go of a lost foe, then follows this frame's presses (toggle, switch), and tells the camera and the
# intent who is locked. Only foes in the camera's picture can be picked or switched to. A pick goes along the cursor on
# the keyboard and mouse, else along the stick, else along the way he faces (the camera is fixed, so its forward is
# always up the screen, which says nothing about where he looks).
func _lock(actor: Actor, intent: Intent) -> void:
	if _watched != actor:
		_watched = actor
		actor.died.connect(_on_died, CONNECT_REFERENCE_COUNTED)
	lock.update(actor)
	var rig := actor.get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	var foes := actor.get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP)
	if intent.pressed.has(&"lock_on"):
		if lock.target != null:
			lock.target = null
		else:
			lock.target = LockOn.pick(actor, foes, _pick_direction(actor, intent), rig)
	elif lock.target != null:
		var right := intent.pressed.has(&"target_right") or intent.pressed.has(&"slot_next")
		var left := intent.pressed.has(&"target_left") or intent.pressed.has(&"slot_prev")
		if right != left:
			lock.target = LockOn.next(actor, lock.target, foes, right, rig)
	intent.locked = lock.target
	if rig != null:
		rig.lock_target = lock.target


# The direction a lock-on press looks along, world.
func _pick_direction(actor: Actor, intent: Intent) -> Vector3:
	if Inputs.last_device() == Inputs.Device.KEYBOARD_MOUSE:
		var cursor: Variant = _cursor(actor)
		if cursor is Vector3:
			var to := _flat_from(actor, cursor)
			if not to.is_zero_approx():
				return Vector3(to.x, 0.0, to.y)
	var along := Vector3(intent.move.x, 0.0, intent.move.y)
	return along if not along.is_zero_approx() else actor.facing()


# The player died: he holds no lock, and the camera stops leaning to the foe (the dead think no more).
func _on_died() -> void:
	lock.target = null
	if _watched != null and is_instance_valid(_watched) and _watched.is_inside_tree():
		var rig := _watched.get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
		if rig != null:
			rig.lock_target = null


# Fills in the intent's aim_target, and, on the keyboard and mouse, its face_target.
func _aim(actor: Actor, intent: Intent) -> void:
	if lock.target != null:
		intent.face_target = lock.target.head_point()
		intent.aim_target = lock.target.global_position
		intent.track = true
		return
	var toward := intent.move
	var cursor: Variant = null
	if Inputs.last_device() == Inputs.Device.KEYBOARD_MOUSE:
		cursor = _cursor(actor)
		if cursor is Vector3:
			intent.face_target = cursor
			toward = _flat_from(actor, cursor)
	if toward.is_zero_approx():
		toward = Vector2(actor.facing().x, actor.facing().z)
	# With no foe near the line, a stick swings along the way he faces, but a cursor is a place to swing at.
	var foe: Variant = _assist_target(actor, toward)
	intent.aim_target = foe if foe != null else cursor


# The point of the ground (at the height of the actor's feet) under the cursor, or null: no camera, or it cannot say.
func _cursor(actor: Actor) -> Variant:
	var rig := actor.get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	if rig == null:
		return null
	return rig.cursor_ground(mouse_position(actor), actor.global_position.y)


# The nearest live foe within aim_assist_range of the actor and aim_assist_deg of `toward` (a world (x, z)
# direction), as a world point; null if there is none. A foe right on top of the actor counts as in the cone.
func _assist_target(actor: Actor, toward: Vector2) -> Variant:
	var tuning := actor.stats.tuning
	var cone := deg_to_rad(tuning.aim_assist_deg)
	var best: Variant = null
	var best_distance := tuning.aim_assist_range
	for node in actor.get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		var foe := node as Actor
		if foe == null or foe == actor or foe.dead:
			continue
		var flat := _flat_from(actor, foe.global_position)
		var distance := flat.length()
		if distance > best_distance:
			continue
		if not flat.is_zero_approx() and absf(toward.angle_to(flat)) > cone:
			continue
		best = foe.global_position
		best_distance = distance
	return best


# The way from the actor to `point` on the ground plane, world (x, z).
static func _flat_from(actor: Actor, point: Vector3) -> Vector2:
	return Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z)
