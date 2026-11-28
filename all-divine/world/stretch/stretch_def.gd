class_name StretchDef
extends Resource
## The stretch as data: which region it is played in, which shrines stand in it and which one a new game starts at. Later parts of
## the stretch (petals, foes, gates, the mini-boss) add their own exports here.

@export var id: StringName
## The region's scene file.
@export_file("*.tscn") var region := ""
@export var shrines: Array[ShrineDef] = []
## The shrine a game that has rested nowhere stands up at.
@export var start_shrine: StringName = &"rose_a"
# Task 5: gates
@export var gates: Array[GateDef] = []

## Task 3: the numbers of the petals (what he leaves where he falls, the clock, the reach).
@export var petals: PetalTuning

## Task 4: where foes stand (`EncounterHost` stands them in and out as the player comes and goes).
@export var encounters: Array[EncounterDef] = []
