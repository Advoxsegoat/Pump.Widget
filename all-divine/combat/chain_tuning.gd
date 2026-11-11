class_name ChainTuning
extends Resource
## The numbers of an actor's dodge chain (DodgeChain): how many links make each tempo, how long a chain lives without a
## success, what a perfect dodge links and gives back, and what each tempo does to the attacker and to the one blows land
## on. The tables are indexed by tempo (DodgeChain.Tempo: Slip, Quick, Flurry). Abarax's is data/tuning/chain_open_hand.tres.

## The count at which the tempo is Quick, and at which it is Flurry.
@export var quick_at := 3
@export var flurry_at := 7
## Frames (on the actor's own clock, which stands still while it is frozen) without a defence that succeeds before the
## chain is gone.
@export var timeout_frames := 90
## What a perfect dodge adds to the chain (any other evade, a parry and a catch add 1).
@export var perfect_links := 2
## Stamina a perfect dodge gives back beyond its own cost.
@export var perfect_refund := 4.0
## Posture an evade takes from its attacker, by tempo; a perfect dodge takes double.
@export var posture_chip := PackedFloat32Array([0.0, 4.0, 8.0])
## What a counter cashed in at each tempo is worth times, and how far a clear-out throws (metres). Read by the counters.
@export var cash_scale := PackedFloat32Array([1.0, 1.5, 2.0])
@export var clearout_throw := PackedFloat32Array([2.0, 2.5, 3.0])
## The move a sway and a duck start at each tempo, before the side the press asked for picks its variant
## (MoveData.directional): the Slip, Quick and Flurry base moves.
@export var sway_moves: Array[StringName] = []
@export var duck_moves: Array[StringName] = []
