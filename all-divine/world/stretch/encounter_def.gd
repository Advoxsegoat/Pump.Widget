class_name EncounterDef
extends Resource
## A place where foes stand, as data (kind `stretch`): who stands where, how near the player has to come for them to stand in and how far
## to go for them to stand out, whether they sleep, and how far they follow. `EncounterHost` makes them. Tasks 6 and 7 add `squad` and `boss`.

@export var id: StringName
@export var placements: Array[Placement] = []
## Metres from the mean of the posts: nearer than this and the foes stand in, further than `despawn_radius` (and unengaged) they stand out.
## The picture is 20 x 11 m on the ground at most 10 m from him: both are well outside it.
@export var spawn_radius := 30.0
@export var despawn_radius := 44.0
## Asleep until the player comes within `wake_radius` of a member or a member is hit.
@export var sleeping := false
@export var wake_radius := 7.0
## One member engaging engages the rest.
@export var alarm := true
## How far from its post a member follows before it gives up and walks home.
@export var leash := 24.0
## A world flag that keeps it from ever standing.
@export var gone_if: StringName = &""


## The mean of the posts (flat; y 0).
func centre() -> Vector3:
	var sum := Vector3.ZERO
	for placement in placements:
		sum += placement.at
	return sum / float(maxi(placements.size(), 1))
