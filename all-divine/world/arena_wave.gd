class_name ArenaWave
extends Resource
## One wave of the training yard's arena, as data: which foes come and how many of each. `defs[i]` comes `count[i]`
## times, in that order, to the enemy spawns in turn (Arena.start_wave).

@export var defs: Array[ActorDef] = []
@export var count := PackedInt32Array()
