class_name Stats
extends RefCounted
## An actor's numbers as it plays: what is left of its bars. Data only in F0; combat (F1) spends them.

var hp := 0.0
var stamina := 0.0
## A second bar beside HP: guards, parries and heavy hits wear it down, and at zero it breaks.
var posture := 0.0
var poise := 0.0
## Damage kind (StringName) -> how much of it is taken off, 0 to 1.
var resistances: Dictionary = {}


## Full bars, from the actor's definition.
static func from_def(def: ActorDef) -> Stats:
	var stats := Stats.new()
	stats.hp = def.max_hp
	stats.stamina = def.max_stamina
	stats.posture = def.max_posture
	stats.poise = def.poise
	return stats
