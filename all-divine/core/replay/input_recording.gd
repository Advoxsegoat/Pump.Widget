class_name InputRecording
extends Resource
## What the controls did, one entry for every physics frame of a fight, saved as a text .tres: enough to play the same fight
## again (InputReplayer), since the game's only other input is the seed its enemies' dice are rolled from.
##
## An entry is a Dictionary:
##   move        Vector2, the stick as Inputs.move_vector() gave it (screen space, deadzone out)
##   pressed     PackedStringArray, the gameplay actions that went down on the frame (Inputs.pressed_this_frame)
##   held        PackedStringArray, the gameplay actions that were down on it (a press is held too, unless it was let go of again
##               within the frame, which a physics-frame recording cannot see)
##   direction   Vector2, the screen direction a key or a flick of the stick pressed on the frame, or zero
##               (Inputs.direction_pressed_this_frame). A sway or a duck is guard with this, so a recording needs it as it
##               needs the stick: the stick alone says where he walks, not that a flick began.

##
## And a header, so that a recording says what it is and checks itself: the format's `version`, the `seed` and `policy` of the bot that
## made it (a person's has none), `frame_count`, whether a `debug_keys` key (F5 to F9, which change the fight and are not controls) was
## pressed, and `hashes`: the fight's state hash (Arena.state_hash) after every `hash_every` frames and after the last, which a replay
## compares as it goes.

## The format this game reads.
const VERSION := 1

## The settings that change a fight (Settings keys): the header stores their values, and a replay runs with them. Found by playing a
## seeded fight with each setting at its default and at its other end; only the slow-down on a perfect dodge changed it.
const FIGHT_SETTINGS: Array[String] = ["effects/slowdown_on"]

## The header: the format's version, who made it, how many frames it has, and whether a debug key was pressed while it was made.
@export var version := VERSION
@export var policy := ""
@export var frame_count := 0
@export var debug_keys := false
## The values the settings in FIGHT_SETTINGS had when the fight was recorded: key -> value.
@export var settings: Dictionary = {}
## Entries lived (a count of frames from the first) -> the arena's state hash after them.
@export var hashes: Dictionary = {}

## One entry per physics frame, the first the first frame the recorder ran.
@export var frames: Array = []
## The scene file of the region the fight was in.
@export var region := ""
## The seed the fight's dice were rolled from (Arena.start_seed) and the bot played by.
@export var seed := 0
## The arena's own frame count (the one its state hash holds) when the first entry was recorded: 0 for a recording that began with
## the fight, which is the only kind a replay reproduces.
@export var start_frame := 0


## An entry for a frame with no control touched.
static func idle() -> Dictionary:
	return {"move": Vector2.ZERO, "pressed": PackedStringArray(), "held": PackedStringArray(), "direction": Vector2.ZERO}


## Why this recording cannot be played, in one line, or "" if it can: from a format the game does not know, cut short (fewer frames
## than its header says), or made with a debug key pressed.
func problem() -> String:
	if version != VERSION:
		return "the recording is of format %d and this game reads format %d" % [version, VERSION]
	if frames.size() != frame_count:
		return "the recording is cut short: it has %d frames of the %d it says" % [frames.size(), frame_count]
	if debug_keys:
		return "a debug key (F5 to F9) was pressed while it was recorded, and that is not in the recording"
	return ""
