class_name PlayerBrain
extends Brain
## The player: the move stick turned from the screen into the world by the camera's yaw, and the
## gameplay buttons pressed this frame and held.

## The camera's yaw (CameraRig.yaw()). At 0 the camera looks along -Z, so pushing up goes to -Z and
## pushing right to +X; a turned camera turns the stick with it.
var view_yaw := 0.0


func think(_actor: Actor, _delta: float) -> Intent:
	var intent := Intent.new()
	var screen := screen_move()
	var world := Vector3(screen.x, 0.0, screen.y).rotated(Vector3.UP, view_yaw)
	intent.move = Vector2(world.x, world.z)
	intent.pressed = Inputs.pressed_this_frame()
	for action in Inputs.GAMEPLAY:
		if Inputs.held(action):
			intent.held.append(action)
	return intent


## The movement the player asks for on screen: right is +x, up is -y, length 0 to 1, deadzone out.
## Every connected gamepad and the keys (Inputs.move_vector()).
func screen_move() -> Vector2:
	return Inputs.move_vector()
