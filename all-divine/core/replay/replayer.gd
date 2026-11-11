class_name InputReplayer
extends Node
## Plays an InputRecording back into the game, one entry a physics frame, through the real input path (InputFeed): the actions
## through Input.action_press and action_release, the stick and the direction pressed through the Inputs seam, so the
## PlayerBrain reads them as it reads a player. The same recording into the same game (the same seed and region) makes the same
## fight, and the same Arena.state_hash at the end.
##
## It runs at the end of each physics frame (InputFeed.PRIORITY) and gives the controls what the NEXT frame will read, as a
## device's events arrive between frames; the first entry is given on the first frame the replayer runs, so that the recorder (which
## skips the frame it begins on, see InputRecorder) and the replayer, begun alike, count the same frames. When the last entry has
## been lived it lets the controls go and says so, at the end of that frame.

## Every entry has been played and the fight has lived the last one.
signal finished

var _rec: InputRecording
var _at := 0


func _init() -> void:
	process_physics_priority = InputFeed.PRIORITY


## Starts playing `rec` from its first entry on the next physics frame.
func play(rec: InputRecording) -> void:
	_rec = rec
	_at = 0


## Whether a recording is being played.
func playing() -> bool:
	return _rec != null


func _physics_process(_delta: float) -> void:
	if _rec == null:
		return
	if _at >= _rec.frames.size():
		_rec = null
		InputFeed.release()
		finished.emit()
		return
	InputFeed.apply(_rec.frames[_at])
	_at += 1
