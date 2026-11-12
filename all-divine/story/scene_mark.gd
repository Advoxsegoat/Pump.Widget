class_name SceneMark
extends Resource
## A named place a scene's shots and beats can point at. It is data: the region scene is not edited to hold it.
##
## A name that starts `rehearsal.` (`rehearsal.abarax`) is where the tools stand that LIVE actor before the scene
## begins, so a storyboard frame shows him where a player would have been. It is not a place a shot may name.

## Where `position` is measured from.
enum Space {
	## The region's own space.
	REGION,
	## `actor`'s own space, +Z the way it faced, as it stood when the scene began. A scene that starts wherever the
	## player happens to be uses these.
	ACTOR_START,
}

@export var name: StringName
@export var space: Space = Space.REGION
## ACTOR_START: whose space the position is in (a cast name).
@export var actor: StringName
## Metres.
@export var position := Vector3.ZERO
@export var yaw_deg := 0.0
