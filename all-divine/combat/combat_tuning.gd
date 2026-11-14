class_name CombatTuning
extends Resource
## The numbers of an actor's fighting that are not part of any one blow: how stamina and posture come
## back, how a guard behaves, how far a finisher reaches and how the body is steered toward a target.
## What one blow does is its HitProfile. The defaults are the Abarax numbers
## (data/tuning/combat_abarax.tres); an enemy gets its own file.

# --- stamina ---
## Stamina regained per second once it is allowed to come back.
@export var stamina_regen_rate := 45.0
## Seconds after the last stamina spend before it starts to come back.
@export var stamina_regen_delay := 0.6
## What regen is multiplied by while guarding: holding a guard recovers slowly.
@export var guard_regen_scale := 0.4
## After stamina runs out the actor is exhausted (it cannot sprint or start a move) until stamina has
## climbed back to this much.
@export var exhausted_until := 20.0
## Stamina spent per second of sprinting.
@export var sprint_stamina := 12.0

# --- posture ---
## Seconds after the last posture damage before the posture meter starts to come back.
@export var posture_regen_delay := 1.5
## Posture regained per second once it starts back.
@export var posture_regen_rate := 20.0
## Seconds an actor stays broken (open to a finisher) once its posture meter is empty.
@export var broken_time := 2.0

# --- guard, parry and catch ---
## Degrees either side of the facing that a guard or parry covers: a blow from outside the arc is not
## answered.
@export var guard_arc_deg := 75.0
## What the actor's walking speed is multiplied by while it holds a guard.
@export var guard_speed_scale := 0.45
## Whether the legs get no stick while the guard stance is up: he stands his ground and only turns to his face_target. A
## held guard that walks is a guard that cannot answer a press in two frames from where it stands.
@export var guard_planted := false
## A parried blow adds its posture damage times this to the attacker.
@export var parry_posture_scale := 2.0
## Posture damage a caught thrust deals to the attacker (a catch ignores the thrust's own numbers).
@export var catch_posture := 50.0
## A guard raise opens its parry window only if the raise before it started at least this many frames earlier
## (frames the actor was not frozen for, as its input buffer counts them). One that comes sooner still guards. So
## tapping guard over and over cannot chain fresh windows: a parry is a timed tap, not spam.
@export var parry_refresh_frames := 20

# --- finisher ---
## Metres within which a broken target can be finished.
@export var finisher_range := 1.6
## Degrees either side of the facing within which a broken target can be finished.
@export var finisher_arc_deg := 60.0
## Degrees within which a broken target must face the one finishing it: it turns to face him as the finisher begins,
## about the middle of its feet (Pairing), and further than this its planted feet would slide more than 0.15 m.
@export var finisher_facing_deg := 30.0

# --- aim assist ---
## Degrees either side of the aim within which an attack that starts is turned onto a target.
@export var aim_assist_deg := 30.0
## Metres within which aim assist looks for a target.
@export var aim_assist_range := 3.5
## Degrees per second the body turns toward the aim during a wind-up.
@export var aim_turn_rate_deg := 540.0

# --- knockback ---
## How fast the push of a hit (`HitProfile.knockback`) dies away, per second.
@export var knockback_decay := 10.0
