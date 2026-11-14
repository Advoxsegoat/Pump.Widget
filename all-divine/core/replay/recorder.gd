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

## The arena whose state hash is written into the recording (every hash_every frames, and at close); null for none.
var arena: Arena
## How many frames between hashes.
var hash_every := 60

var _rec := InputRecording.new()
var _skipped := false  # the frame the recorder was first run on has gone by
var _pending := -1  # the entry whose frame the brain has yet to think, for the cursor it will read (taken at the next frame)


func _init() -> void:
	process_physics_priority = -110
	# A pause stops the fight and so the recording: the frames it holds still are not frames of the fight (the recorder would otherwise
	# go on, as a child of Main, which runs through a pause to hear the menu button).
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Begins a recording of the fight in `region` (a scene file), whose dice were rolled from `seed`, `start_frame` being the arena's
## own frame count now (what Arena.state_hash holds). Whatever was recorded before is dropped.
func begin(region: String, seed: int, start_frame := 0, policy := "") -> void:
	_rec = InputRecording.new()
	_rec.policy = policy
	for key in InputRecording.FIGHT_SETTINGS:
		_rec.settings[key] = Settings.get_value(key)  # the fight as it is played: under the player's own settings, or the defaults
	_rec.region = region
	_rec.seed = seed
	_rec.start_frame = start_frame
	_skipped = false
	_pending = -1


## What has been recorded so far (the recording itself, not a copy: it grows as the recorder runs).
func recording() -> InputRecording:
	return _rec


## Closes the recording: the header's frame count, and the state hash after its last frame. Call it where the fight stands after the
## last recorded frame (the end of a frame, or between frames); save does.
func close() -> void:
	_take_cursor()
	_rec.frame_count = _rec.frames.size()
	if arena != null and is_instance_valid(arena) and arena.is_inside_tree():
		_rec.hashes[_rec.frames.size()] = arena.state_hash()


## Writes the recording to `path` as a text .tres, making the folder if it is not there.
func save(path: String) -> Error:
	close()
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return ResourceSaver.save(_rec, path)


func _physics_process(_delta: float) -> void:
	_take_cursor()
	if not _skipped:
		_skipped = true
		return
	var held := PackedStringArray()
	for action in Inputs.GAMEPLAY:
		if Inputs.held(action):
			held.append(action)
	if arena != null and is_instance_valid(arena) and not _rec.frames.is_empty() and _rec.frames.size() % hash_every == 0:
		_rec.hashes[_rec.frames.size()] = arena.state_hash()  # the fight after the frames recorded so far
	# The pause button is not a control of the fight: a pause changes nothing in it, and a replay never pauses.
	var pressed := PackedStringArray()
	for action in Inputs.pressed_this_frame():
		if action != &"menu":
			pressed.append(action)
	var kept := PackedStringArray()
	for action in held:
		if action != &"menu":
			kept.append(action)
	_rec.frames.append({
		"move": Inputs.move_vector(),
		"pressed": pressed,
		"held": kept,
		"direction": Inputs.direction_pressed_this_frame(),
		"device": Inputs.last_device(),
	})
	_pending = _rec.frames.size() - 1


# The cursor's point the brain read on the frame of the entry before this one, if it read one, goes into that entry (the brain thinks after the
# recorder has written the frame's input, so the point is known a frame later); and the note is cleared for the frame to come.
func _take_cursor() -> void:
	if _pending >= 0 and Inputs.cursor_read is Vector3 and Inputs.last_device() == Inputs.Device.KEYBOARD_MOUSE:
		_rec.frames[_pending]["cursor"] = Inputs.cursor_read
	_pending = -1
	Inputs.cursor_read = null
