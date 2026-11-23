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

# --- timing pays more (Task 17) ---
## Frames (on the punisher's own clock, which stands still while it is frozen) a foe is open after his blow was turned (parried or
## caught) or perfectly dodged by this actor, until he starts a move of his own: the tuning of the one who punishes.
@export var punish_frames := 40
## What a blow of this actor's is worth times (its HP and posture damage and its hit-stop) while the foe it lands on is open to it. The foes'
## tunings say 1: they get no such bonus against Abarax.
@export var punish_scale := 1.5

# --- mashing costs stamina (Task 17) ---
## Stamina a redundant press costs (a press of palm, heavy, sway or duck made while the same action's last press is still waiting in the
## buffer, or while the move it started has not yet reached its first cancel window), after the first redundant press of a move, which
## is free. Times 100 / max_stamina, so a larger stamina bar pays less. 0 turns the rule off: every foe's tuning says 0. It is stamina and
## nothing else: it does not restart the wait before stamina comes back (fix round 1; 1.0, the gentlest of the range the controller gave: see notes/f1-feel.md).
@export var hammer_tax := 1.0
## Each sway or duck that evades nothing makes the next one cost this much of its base cost more (0.25: x1.25, x1.5, x1.75), until one evades
## something or `strain_reset_frames` pass with no sway or duck. The added part is times 100 / max_stamina. 0 turns the rule off (the foes').
@export var strain_step := 0.25
## The most a strained sway or duck costs, times its base cost.
@export var strain_cap := 2.0
## Frames (on the actor's own clock) with no sway or duck before the strain is gone.
@export var strain_reset_frames := 60
