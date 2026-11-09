class_name BrainDef
extends Resource
## An enemy's mind as data (spec §4.5): how it perceives, the range it keeps, the attacks it chooses from, what its tier
## adds to them, and when it backs off. EnemyBrain plays it; an ENEMY ActorDef names one in its `brain`. Tiers of one
## archetype differ here in what they do (feints, delayed swings, combo extensions, tracking), not only in numbers.

## Perception: it sees the target within sight_range metres and sight_fov_deg degrees (the whole cone) of its facing,
## with nothing on the `world` layer between their heads; it hears one that sprints or attacks within hearing_range
## metres, whichever way it faces. Once it has perceived the target for notice_time seconds it engages.
@export var sight_range := 12.0
@export var sight_fov_deg := 120.0
@export var hearing_range := 6.0
@export var notice_time := 0.6

## Spacing: engaged and not attacking, it keeps preferred_range ± range_tolerance metres from the target, walking in or
## backing off, and circles it with the stick pushed circle_speed (0 to 1) while it is there.
@export var preferred_range := 2.2
@export var range_tolerance := 0.6
@export var circle_speed := 0.5

## The attacks it chooses from.
@export var attacks: Array[AttackOption] = []
## Seconds after an attack is over before it chooses the next (a quarter either way, by its dice): the opening its
## blows leave.
@export var attack_rest := 0.8

## Tier behaviour, each a chance per attack. feint_chance: it presses `dodge` (the feint) first and the attack's action
## into the feint's cancel window. delay_chance: it holds the attack's action through its move's charge_hold for a
## number of frames in delay_frames (a delayed swing that baits an early parry). extend_combo_chance: its combo gets one
## blow more (the fourth). track_dodges: its swings keep turning to the target through their active frames (Intent.track).
@export var feint_chance := 0.0
@export var delay_chance := 0.0
@export var delay_frames := Vector2i(6, 12)
@export var track_dodges := false
@export var extend_combo_chance := 0.0

## Retreat: below this share of its max HP it backs away from the target for regroup_time seconds (0: it never does).
@export var retreat_below := 0.0
@export var regroup_time := 2.0

## Gank squads (spec §4.5) commit together: a brain that ignores tokens never takes one.
@export var ignores_tokens := false

## Seconds its spacing (or its approach to an attack's range) may fail before it tries another angle: the circling
## turns the other way and its heading swings 60 degrees (Review Focus 5: a wall in the way).
@export var reangle_after := 3.0
