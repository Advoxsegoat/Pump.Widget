class_name InputBuffer
extends RefCounted
## Remembers button presses for WINDOW frames, so a press made a moment too early still counts when the
## move it belongs to becomes possible (a cancel window opening, a recovery ending).
##
## Presses are pushed with the frame they happened on; consume hands out the newest one an action list
## allows and forgets it. Frames are physics frames (60 per second), so 9 of them are 150 ms.

## A press is good for this many frames after the one it happened on (ages 0 to WINDOW).
const WINDOW := 9

var _actions: Array[StringName] = []
var _frames: Array[int] = []


## Remembers that `action` was pressed on `frame`. Presses too old to matter at `frame` are forgotten.
func push(action: StringName, frame: int) -> void:
	_actions.append(action)
	_frames.append(frame)
	_forget_older_than(frame)


## The newest press of an action in `allowed` that is 0 to WINDOW frames old at `frame` (its age is
## `frame` minus the frame it was pressed on). The press is removed; two presses are two consumes. Where
## two presses are from the same frame, the one pushed later wins. Returns &"" when there is none.
## Presses of other actions stay.
func consume(allowed: Array, frame: int) -> StringName:
	_forget_older_than(frame)
	var best := -1
	for i in _actions.size():
		if _frames[i] > frame or not allowed.has(_actions[i]):
			continue
		if best < 0 or _frames[i] >= _frames[best]:
			best = i
	if best < 0:
		return &""
	var action := _actions[best]
	_actions.remove_at(best)
	_frames.remove_at(best)
	return action


## Forgets every press.
func clear() -> void:
	_actions.clear()
	_frames.clear()


## How many presses are remembered (including any that have expired since the last push or consume).
func size() -> int:
	return _actions.size()


func _forget_older_than(frame: int) -> void:
	for i in range(_actions.size() - 1, -1, -1):
		if frame - _frames[i] > WINDOW:
			_actions.remove_at(i)
			_frames.remove_at(i)
