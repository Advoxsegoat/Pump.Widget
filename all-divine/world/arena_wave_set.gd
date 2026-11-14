class_name ArenaWaveSet
extends Resource
## The waves of an arena, in the order they come (data/arena/waves.tres). A resource of its own so that they can be one
## .tres; the Arena takes its `waves` from it.

@export var waves: Array[ArenaWave] = []
