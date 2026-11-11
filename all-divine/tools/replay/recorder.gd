class_name InputRecorder
extends Node
## Writes down what the controls report on every physics frame (an InputRecording): the move vector, the actions pressed and
## held, and the direction pressed. It reads what Inputs says and not the devices, so a run played by the replayer or the
## bot, which go through the same seam, is recorded as one played by hand.
##
## It runs at priority -110: before Melee's snapshot (-100) and every actor, so it sees the frame's input as the brains will.
## Whoever works the controls (the bot, a replayer) does so at the end of the frame before (InputFeed), so it has been given
## by then. The recorder skips the frame it is first run on, since what that frame reads was given before it existed: its first
## entry is the next frame, which is the first a replayer begun alongside gives. It stops with the tree when the game is paused,
## as the fight does, so an entry is a frame of the fight.

var _rec := InputRecording.new()
var _skipped := false  # the frame the recorder was first run on has gone by


func _init() -> void:
	process_physics_priority = -110


## Begins a recording of the fight in `region` (a scene file), whose dice were rolled from `seed`, `start_frame` being the arena's
## own frame count now (what Arena.state_hash holds). Whatever was recorded before is dropped.
func begin(region: String, seed: int, start_frame := 0) -> void:
	_rec = InputRecording.new()
	_rec.region = region
	_rec.seed = seed
	_rec.start_frame = start_frame
	_skipped = false


## What has been recorded so far (the recording itself, not a copy: it grows as the recorder runs).
func recording() -> InputRecording:
	return _rec


## Writes the recording to `path` as a text .tres, making the folder if it is not there.
func save(path: String) -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return ResourceSaver.save(_rec, path)


func _physics_process(_delta: float) -> void:
	if not _skipped:
		_skipped = true
		return
	var held := PackedStringArray()
	for action in Inputs.GAMEPLAY:
		if Inputs.held(action):
			held.append(action)
	_rec.frames.append({
		"move": Inputs.move_vector(),
		"pressed": PackedStringArray(Inputs.pressed_this_frame()),
		"held": held,
		"direction": Inputs.direction_pressed_this_frame(),
	})
