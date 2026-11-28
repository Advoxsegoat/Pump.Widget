class_name PetalTuning
extends Resource
## The numbers of the petals (data/stretch/petals.tres, the Registry kind `stretch`, id `petals`): how much of what he carries he
## leaves where he falls, whether the pile wilts on a clock, and how near he comes to take it back.

@export var id: StringName
## The share of the carried petals left where he falls.
@export var drop_share := 1.0
## Play seconds after which a pile wilts on its own; 0 is no clock (the pile waits for a second death).
@export var wilt_seconds := 0.0
## Metres, flat: how near he comes to take the pile back (no press, no pause).
@export var reach := 1.2
