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
## Whether a blow of this move that is parried (or caught) turns the move back: its attacker recoils into its parried reaction.
## False for a blow of a string that goes on: the parry still links the defender's chain and still costs its attacker the
## posture a parried blow costs, but the attacker plays no reaction, its move runs on and its cancel windows open as they would
## for a blow that was evaded. Every other move leaves it true.
@export var parry_ends := true
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
## How far (degrees) from the facing a direction is still straight ahead for `directional`, and how far it is already behind
## (side_of). A sway's side is a lean (30 and 150); a dash-step's four sides are equal quarters (45 and 135).
@export var side_ahead_deg := 30.0
@export var side_back_deg := 150.0
## What a palm or heavy pressed within MoveRunner.COUNTER_FRAMES of an evade during this move starts instead of the move's own
## cancel into it: action -> move id (a sway's palm is the hook, its heavy the back-palm clear-out; a duck's the rising palm and
## the wave). Empty for a move that has no counters.
@export var counters: Dictionary = {}
## Whether the move keeps his planted feet where they are through its blend in (Rig.hold_feet): a move whose clip begins in the guard
## stance's own feet, started from a stance where they are planted, so that the blend does not slide them. The counters set it.
@export var plant_feet := false
## Whether the move is a counter or a clear-out: its blows carry what the chain was worth when it was cashed in (HitEvent.power,
## always_staggers, throw), which the scanner fills in from the actor's cashed_tempo.
@export var cashes := false
## Seconds over which the move fades in over what the actor was doing, and out to locomotion.
@export var blend_in := 0.05
@export var blend_out := 0.15
## The move whose blow this one imitates until it stops (a feint): its tell shows the rim of that move's tell on the same
## frames, so that the two cannot be told apart until the blow does not come (ActorFx). Empty for a move that is itself.
@export var imitates: StringName


## Which side of a body facing `facing` the ground direction `dir` (world x, z) lies on: &"" within `ahead_deg` of the
## facing (straight ahead, or no direction at all), &"back" at `back_deg` or more from it, otherwise &"left" or
## &"right" (his own: facing +Z, +X is his left). The key of `directional` the move for that direction is under. `ahead_deg`
## and `back_deg` are the two cuts (a move holds its own: side_ahead_deg, side_back_deg).
static func side_of(dir: Vector2, facing: Vector3, ahead_deg := 30.0, back_deg := 150.0) -> StringName:
	var ahead := Vector2(facing.x, facing.z)
	if dir.is_zero_approx() or ahead.is_zero_approx():
		return &""
	var angle := rad_to_deg(absf(ahead.angle_to(dir)))
	if angle <= ahead_deg + 1e-4:
		return &""
	if angle >= back_deg - 1e-4:
		return &"back"
	# His right hand is the facing turned a quarter toward -X when he faces +Z: (-z, x).
	return &"right" if dir.dot(Vector2(-ahead.y, ahead.x)) > 0.0 else &"left"
