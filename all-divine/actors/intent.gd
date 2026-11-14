class_name Intent
extends RefCounted
## What a brain wants its actor to do this frame. Brains make one per physics frame; the actor acts on it.

## Where to go: world (x, z), length 0 to 1 (how far the stick is pushed, deadzone already out).
var move := Vector2.ZERO
## Actions that went down this frame. They go into the actor's input buffer.
var pressed: Array[StringName] = []
## Actions that are down this frame (holding dodge sprints).
var held: Array[StringName] = []
## The world (x, z) direction of a sway or duck pressed this frame (the stick's or key's, turned by the camera), which
## picks the side the sway leans to; zero when none was pressed.
var evade_dir := Vector2.ZERO
## A world point (Vector3) to keep facing while moving, or null to face the way the actor goes.
var face_target: Variant = null
## A world point (Vector3) for the head and eyes to look at, or null.
var look_target: Variant = null
## A world point (Vector3) the body turns toward while an attack winds up, or null: the foe aim assist picked, or
## the one locked on to, or, on the keyboard and mouse with no foe near, the cursor's ground point. Only an attack
## whose MoveData has `aim` turns to it, and only until its first hitbox comes on, or, with `track`, until its last
## goes off.
var aim_target: Variant = null
## Whether the turn toward aim_target goes on through the attack's active frames too (lock-on tracks its foe
## through a swing; aim assist turns him only in the wind-up).
var track := false
## Whether an attack that starts now is warped toward aim_target: its root travel over the wind-up is stretched or
## shrunk (by MoveRunner.MAX_WARP at most) so the target stands at the move's strike_distance when it lands. An enemy's
## combo blows home in on their target this way; the player's never do.
var warp := false
## The foe the player has locked on to, or null. A palm pressed while it is one to finish (Actor.finishable_target)
## finishes it, rather than the nearest broken foe.
var locked: Actor = null
