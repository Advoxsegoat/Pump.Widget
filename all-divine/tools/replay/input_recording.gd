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

## One entry per physics frame, the first the first frame the recorder ran.
@export var frames: Array = []
## The scene file of the region the fight was in.
@export var region := ""
## The seed the fight's dice were rolled from (Arena.reset_spawn_counts) and the bot played by.
@export var seed := 0
## The arena's own frame count (the one its state hash holds) when the first entry was recorded: 0 for a recording that began with
## the fight, which is the only kind a replay reproduces.
@export var start_frame := 0


## An entry for a frame with no control touched.
static func idle() -> Dictionary:
	return {"move": Vector2.ZERO, "pressed": PackedStringArray(), "held": PackedStringArray(), "direction": Vector2.ZERO}
