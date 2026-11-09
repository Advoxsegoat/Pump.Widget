class_name ScriptBrain
extends Brain
## A brain that plays a fixed list of steps, one frame per think: for tests, demos and the self-test.
## Each step is a Dictionary:
##   frames                      how many frames the step lasts (a step of 0 frames is skipped)
##   move                        Vector2, world (x, z), length 0 to 1 (default: none)
##   press                       actions pressed on the step's first frame only (default: none)
##   hold                        actions held on every frame of the step (default: none); a pressed
##                               action is held only if it is listed here too
##   face_target, look_target,   a Vector3, or a Node3D followed as it moves (where it stands; an Actor looked at is
##   aim_target                  looked at in the head), or null (default: null)
## After the last step it wants nothing.

var _steps: Array
var _step := 0  # the step being played
var _frame := 0  # how many of its frames have been played


func _init(steps: Array) -> void:
	_steps = steps


func think(_actor: Actor, _delta: float) -> Intent:
	var intent := Intent.new()
	_skip_played()
	if _step >= _steps.size():
		return intent
	var step: Dictionary = _steps[_step]
	intent.move = step.get("move", Vector2.ZERO)
	if _frame == 0:
		for action in step.get("press", []):
			intent.pressed.append(StringName(action))
	for action in step.get("hold", []):
		intent.held.append(StringName(action))
	intent.face_target = _point(step.get("face_target"), false)
	intent.look_target = _point(step.get("look_target"), true)
	intent.aim_target = _point(step.get("aim_target"), false)
	_frame += 1
	return intent


## True once every frame of every step has been played.
func done() -> bool:
	_skip_played()
	return _step >= _steps.size()


# A step's target as a world point: a Vector3 as it is; a Node3D where it stands now (an Actor's head when `head`); null
# for anything else, or a node that is gone.
static func _point(target: Variant, head: bool) -> Variant:
	if target is Vector3:
		return target
	if is_instance_valid(target) and target is Node3D and (target as Node3D).is_inside_tree():
		if head and target is Actor:
			return (target as Actor).head_point()
		return (target as Node3D).global_position
	return null


# Moves past the steps whose frames have all been played (and those of 0 frames).
func _skip_played() -> void:
	while _step < _steps.size() and _frame >= int(_steps[_step].get("frames", 0)):
		_step += 1
		_frame = 0
