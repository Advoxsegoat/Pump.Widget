class_name MoveData
extends Resource
## One move: which clip it plays and what it costs and does. The timeline (hitboxes, invulnerability,
## cancel windows, effects) is not here but in the clip's marks (see marks.gd); the clip checker
## (tools/clip_checker.gd) keeps the two consistent.

## A REACTION is what an actor plays when something is done to it (a flinch, a stagger, a death).
enum Kind { ATTACK, DODGE, OTHER, REACTION }
## Which way a move's evade window leans (the window itself is its clip's evade_on and evade_off marks): NONE is no
## evade at all, SWAY a lean aside, DUCK a drop. A sway is the perfect dodge of a straight blow, a duck of a round one.
enum Evade { NONE, SWAY, DUCK }

@export var id: StringName
@export var kind: Kind = Kind.ATTACK
## The clip in the actor's rig that plays the move.
@export var clip: StringName
## Whether the clip's root bone drives the actor's travel while the move plays.
@export var root_motion := true
## What the root motion is multiplied by: the clip's own travel times this is how far the actor goes.
## Keeps a move's distance tunable without re-authoring its clip.
@export var root_motion_scale := 1.0
@export var stamina_cost := 0.0
## The evade the move's evade window is, while it is open (see Evade). A move with an evade window says which here, and
## a move without one leaves it NONE: the clip checker holds the two together.
@export var evade: Evade = Evade.NONE
## After a dodge that avoided nothing, the frame of this move before which another sway or duck cannot start: twice the
## evade window's length, so a press at random is paid for in time as well as stamina. 0 for a move that does not bar one.
@export var redodge_frame := 0
## The ways this move hits: profile name -> HitProfile, written inline in the move's .tres. A hitbox_on
## mark names the profile its hitbox carries, so every hit of the move is one of these.
@export var hits: Dictionary = {}
## Whether the body turns toward the intent's aim target during the wind-up (aim assist and lock-on).
@export var aim := true
## Where the blow lands as it was made: how far (metres, root to root on the ground, for an actor of model_scale 1) the
## target stands when the move starts for its blow to meet it squarely. A move started with the intent's `warp` has its
## wind-up's root travel changed so the target stands there (MoveRunner). 0: the move is never warped.
@export var strike_distance := 0.0
## The move started instead of this one when the stick is at rest (a standing jab, say, in place of a
## stepping one). None means this move is started either way.
@export var neutral_variant: StringName
## The moves started instead of this one when the direction asked for lies on that side of the body: &"left", &"right" or
## &"back" -> a move id (a sway's mirror and its pull back, a dash-step's three other ways). The direction is measured
## against the way the body faces, as a sway leans and a dash-step goes; the move itself is the forward or left one. Empty:
## this move is started whichever way the stick lies.
@export var directional: Dictionary = {}
## Seconds over which the move fades in over what the actor was doing, and out to locomotion.
@export var blend_in := 0.05
@export var blend_out := 0.15
## The move whose blow this one imitates until it stops (a feint): its tell shows the rim of that move's tell on the same
## frames, so that the two cannot be told apart until the blow does not come (ActorFx). Empty for a move that is itself.
@export var imitates: StringName
