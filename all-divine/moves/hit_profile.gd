class_name HitProfile
extends Resource
## What one blow does to whoever it lands on, and which answers it allows. A move names its profiles in
## `MoveData.hits`; a hitbox_on mark says which one its hitbox carries (`profile`), so one move can hit
## in more than one way (a jab, then a charged swing). The numbers are tuned here, in data, and the
## combat rules (combat/) only read them.

## How high the blow lands. A LOW blow misses a target that is off the ground (mid-hop); a MID blow hits
## it.
enum Height { MID, LOW }
## What kind of danger the blow is. NONE is an ordinary hit. The other three are the "perilous" attacks,
## each with its own answer: a SWEEP cannot be guarded or parried (hop it), a THRUST cannot be
## guarded but can be parried (a parried thrust is a catch), and a GRAB can be neither (sway or duck it).
enum Perilous { NONE, SWEEP, THRUST, GRAB }
## The line the blow travels, which says which dodge matches it (Combat.is_perfect): a STRAIGHT blow (a jab, a cross,
## a thrust) is matched by a sway, a ROUND one (a hook, a swing) by a duck. Any evade avoids an ordinary blow, but
## only the matching one is a perfect dodge.
enum Line { STRAIGHT, ROUND }

## Which way a thrown target (`throw`) goes: ALONG_BLOW is the way the blow travels, RADIAL straight away from the attacker, SIDEWAYS
## to the attacker's right.
enum ThrowWay { ALONG_BLOW, RADIAL, SIDEWAYS }

## Hit points taken from the target.
@export var damage := 0.0
## How hard the blow shoves the target's footing: a hit flinches only if this reaches the target's
## `ActorDef.poise`.
@export var poise_damage := 0.0
## What the blow takes off the target's posture meter; an empty meter breaks the target's stance.
@export var posture_damage := 0.0
## The stamina a guard spends to block this blow.
@export var guard_stamina := 0.0
## Metres per second the target is pushed along the direction of the hit; the push dies away at
## `CombatTuning.knockback_decay`.
@export var knockback := 0.0
## Frames both sides freeze on contact. 3 is a tap, 6 is a heavy blow; the clip checker holds the data
## to this range.
@export_range(3, 6) var hitstop_frames := 3
## Camera shake on contact, 0 to 1.
@export var shake := 0.0
## Whether a hit that reaches the target's poise staggers it (the longer reaction) instead of
## flinching it.
@export var staggers := false
@export var height: Height = Height.MID
@export var perilous: Perilous = Perilous.NONE
@export var line: Line = Line.STRAIGHT
## How wide the blow reaches round the attacker's facing, in degrees: a target further than half of it from the way the attacker
## faces is not hit. 360 is all round.
@export_range(0.0, 360.0) var arc_deg := 360.0
## Metres the target is thrown in the open (the push travels its speed over the tuning's knockback_decay); 0 leaves the profile's
## `knockback`. A clear-out's value is scaled by the tempo it was cashed at (HitEvent.throw).
@export var throw := 0.0
@export var throw_way: ThrowWay = ThrowWay.ALONG_BLOW
## The sound cue played on contact (a name in data/sounds/).
@export var impact_sound := &"impact_palm"


## True if a guard can block the blow: only an ordinary one.
func guardable() -> bool:
	return perilous == Perilous.NONE


## True if a parry answers the blow: an ordinary one, and a thrust (a parried thrust is a catch).
func parryable() -> bool:
	return perilous == Perilous.NONE or perilous == Perilous.THRUST
