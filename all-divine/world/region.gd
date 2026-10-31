class_name Region
extends Node3D
## A place to be in: its ground, walls, props and lights, how it looks on screen, and where the player
## starts. The courtyard (world/courtyard/courtyard.tscn) is one.
##
## A region is built on the game's physics layers: what bodies walk on and bump into is on `world`, and the
## exact visible ground, steps and all, is on `ik_surface`, where the feet stand (stairs are a ramp on
## `world` and their steps on `ik_surface`). Things to glance at are Marker3Ds in the group `poi`.

## The region's colours on screen: its colour grade and fog (PixelStage.apply_settings).
@export var grade: GradeProfile


## Where the player starts: the global transform of the child Marker3D named Spawn, whose +Z is the way he
## faces (an actor faces its +Z). The region's own transform, with an error, if it has no Spawn.
func spawn() -> Transform3D:
	var marker := get_node_or_null(^"Spawn") as Marker3D
	if marker == null:
		push_error("Region: '%s' has no Spawn marker" % name)
		return global_transform
	return marker.global_transform
