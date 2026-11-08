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
## Lock-on (see LockOn): lock_on locks the foe the camera looks at (or the stick points at), or lets go. While
## locked, target_left and target_right (a flick of the right stick), and the wheel, move to the neighbouring foe, he
## faces the foe's head whatever the device, his attacks turn to it and track it through the swing, the camera leans
## to it, and a palm that can finish it finishes it. The lock lets go of a foe that dies or goes too far, and nothing
## else changes then: a swing under way carries on, and aim assist is back to the stick.

## The camera's yaw (CameraRig.yaw()). At 0 the camera looks along -Z, so pushing up goes to -Z and
## pushing right to +X; a turned camera turns the stick with it.
var view_yaw := 0.0
## Which foe he has locked on to.
var lock := LockOn.new()


func think(actor: Actor, _delta: float) -> Intent:
	var intent := Intent.new()
	var screen := screen_move()
	var world := Vector3(screen.x, 0.0, screen.y).rotated(Vector3.UP, view_yaw)
	intent.move = Vector2(world.x, world.z)
	intent.pressed = pressed_actions()
	for action in Inputs.GAMEPLAY:
		if Inputs.held(action):
			intent.held.append(action)
	if actor != null:
		_lock(actor, intent)
		_aim(actor, intent)
	return intent


## The gameplay actions that went down this frame.
func pressed_actions() -> Array[StringName]:
	return Inputs.pressed_this_frame()


## The movement the player asks for on screen: right is +x, up is -y, length 0 to 1, deadzone out.
## Every connected gamepad and the keys (Inputs.move_vector()).
func screen_move() -> Vector2:
	return Inputs.move_vector()


## Where the mouse is, in the window: the coordinates of the root viewport, which the PixelStage is drawn in (not
## the actor's own, the World viewport inside it, where the mouse never is).
func mouse_position(actor: Actor) -> Vector2:
	return actor.get_tree().root.get_mouse_position()


# Lock-on: lets go of a lost foe, then follows this frame's presses (toggle, switch), and tells the camera and the
# intent who is locked.
func _lock(actor: Actor, intent: Intent) -> void:
	lock.update(actor)
	var foes := actor.get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP)
	if intent.pressed.has(&"lock_on"):
		if lock.target != null:
			lock.target = null
		else:
			var along := Vector3(intent.move.x, 0.0, intent.move.y)
			if along.is_zero_approx():
				along = Vector3.FORWARD.rotated(Vector3.UP, view_yaw)
			lock.target = LockOn.pick(actor, foes, along)
	elif lock.target != null:
		var right := intent.pressed.has(&"target_right") or intent.pressed.has(&"slot_next")
		var left := intent.pressed.has(&"target_left") or intent.pressed.has(&"slot_prev")
		if right != left:
			lock.target = LockOn.next(actor, lock.target, foes, right)
	intent.locked = lock.target
	var rig := actor.get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	if rig != null:
		rig.lock_target = lock.target


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
