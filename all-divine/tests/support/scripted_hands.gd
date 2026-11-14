class_name ScriptedHands
extends Node
## Hands that work the real controls from a list of steps, one frame each, for the replay tests: what ScriptBrain is for an
## actor's brain, this is for the input seam (InputFeed), so that the PlayerBrain reads it as it would a player and an
## InputRecorder records it. A step is a Dictionary like a ScriptBrain's, with the stick on the screen:
##   frames      how many frames the step lasts
##   move        Vector2, the screen's stick (default: none)
##   press       actions pressed on the step's first frame only
##   hold        actions held on every frame of the step (a pressed action is held only if it is listed here too)
##   direction   Vector2, the direction pressed on the step's first frame (a sway or duck needs guard held with it)
##   device      Inputs.Device the aim is given as (default: none given, the devices are read), and with the keyboard and mouse
##   cursor      the Vector3 ground point the cursor is given at (default: none)
## It works at the end of each frame (InputFeed.PRIORITY), giving the next frame its input as a replayer does, and its first step
## on the first frame it runs. After the last step it lets everything go.

var _steps: Array
var _step := 0
var _frame := 0


func _init(steps: Array) -> void:
	_steps = steps
	process_physics_priority = InputFeed.PRIORITY


func _physics_process(_delta: float) -> void:
	while _step < _steps.size() and _frame >= int(_steps[_step].get("frames", 0)):
		_step += 1
		_frame = 0
	if _step >= _steps.size():
		InputFeed.release()
		return
	var step: Dictionary = _steps[_step]
	var first := _frame == 0
	InputFeed.apply({
		"move": step.get("move", Vector2.ZERO),
		"pressed": PackedStringArray(step.get("press", []) if first else []),
		"held": PackedStringArray(step.get("hold", [])),
		"direction": step.get("direction", Vector2.ZERO) if first else Vector2.ZERO,
		"device": step.get("device"),
		"cursor": step.get("cursor"),
	})
	_frame += 1
