class_name InputFeed
extends RefCounted
## Gives one recorded frame of input to the game the way a player's hands do: the buttons through the real actions
## (Input.action_press, action_release) and the stick, and the direction a key or flick pressed, through the Inputs seam
## (Inputs.inject_move, inject_direction). The replayer and the combat bot both play this way, so the PlayerBrain reads
## them as it reads a player, and nothing starts a move or writes an Intent behind its back.
##
## An action pressed during a physics frame counts as pressed on the NEXT one (Input.is_action_just_pressed: a press arrives
## between frames, as a real event does), while the stick and the direction injected are read at once. So whoever feeds works
## at the END of a physics frame (PRIORITY, after Melee and every actor), and what it gives is what the next frame will read,
## all of it together: a sway's guard press and its direction land on one frame.

## Where in the physics frame a feeder runs: after every actor and Melee (100), giving the frame to come its input.
const PRIORITY := 200


## Makes the controls what the entry `frame` (see InputRecording) says they will be on the next frame: an action in `pressed` goes down now
## (let go of first if it was still down, so that it is a fresh press), one in `held` stays down, any other is let go of.
static func apply(frame: Dictionary) -> void:
	var pressed: PackedStringArray = frame.get("pressed", PackedStringArray())
	var held: PackedStringArray = frame.get("held", PackedStringArray())
	for action in Inputs.GAMEPLAY:
		var wanted := pressed.has(action) or held.has(action)
		var down := Input.is_action_pressed(action)
		if pressed.has(action):
			if down:
				Input.action_release(action)
			Input.action_press(action)
		elif wanted and not down:
			Input.action_press(action)
		elif not wanted and down:
			Input.action_release(action)
	Inputs.inject_move(frame.get("move", Vector2.ZERO))
	Inputs.inject_direction(frame.get("direction", Vector2.ZERO))
	Inputs.inject_aim(frame.get("device"), frame.get("cursor"))


## Lets everything go: no action is down, and the devices are read again.
static func release() -> void:
	for action in Inputs.GAMEPLAY:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	Inputs.inject_move(null)
	Inputs.inject_direction(null)
	Inputs.inject_aim(null)
