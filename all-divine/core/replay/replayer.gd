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

## The fight is not the one recorded: after `at` frames its state hash was `got`, the recording's `recorded`. The replay stops there.
signal diverged(at: int, recorded: int, got: int)
## Every entry has been played and the fight has lived the last one.
signal finished

## The arena whose state hash is compared with the recording's, as the replay goes; null for no comparing.
var arena: Arena

var _rec: InputRecording
var _at := 0
var _lent := {}  # what the settings were before the recording's were lent, for the end


func _init() -> void:
	process_physics_priority = InputFeed.PRIORITY


## Starts playing `rec` from its first entry on the next physics frame.
func play(rec: InputRecording) -> void:
	_give_back()
	_rec = rec
	_at = 0
	_lent = Settings.lend(rec.settings)  # the fight is played under the settings it was recorded with


## Whether a recording is being played.
func playing() -> bool:
	return _rec != null


func _exit_tree() -> void:
	_give_back()


# Puts the player's settings back (nothing is written: they were only lent).
func _give_back() -> void:
	if not _lent.is_empty():
		Settings.take_back(_lent)
		_lent = {}


func _physics_process(_delta: float) -> void:
	if _rec == null:
		return
	# The fight stands as it does after `_at` frames lived: where the recording says what it was.
	if arena != null and is_instance_valid(arena) and _rec.hashes.has(_at):
		var got := arena.state_hash()
		if got != int(_rec.hashes[_at]):
			var recorded := int(_rec.hashes[_at])
			_rec = null
			_give_back()
			InputFeed.release()
			diverged.emit(_at, recorded, got)
			return
	if _at >= _rec.frames.size():
		_rec = null
		_give_back()
		InputFeed.release()
		finished.emit()
		return
	InputFeed.apply(_rec.frames[_at])
	_at += 1
