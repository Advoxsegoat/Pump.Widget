class_name Placement
extends Resource
## One foe of an encounter: who it is, where it stands and which way it faces. Inline in an `EncounterDef`.

@export var def: ActorDef
## Where it stands (x east, z south; y 0).
@export var at := Vector3.ZERO
## Its facing in degrees about +Y: 0 faces south (+Z), 90 east, 180 north, 270 west.
@export var facing_deg := 0.0
## Optional: handed to the foe in place of the brain its def names.
@export var brain: BrainDef
## Task 6: handed instead once the encounter's squad is slowed.
@export var brain_broken: BrainDef


## Its facing as a yaw in radians (the basis of `Transform3D(Basis(Vector3.UP, yaw), at)`).
func yaw() -> float:
	return deg_to_rad(facing_deg)
