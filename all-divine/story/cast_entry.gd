class_name CastEntry
extends Resource
## Who is in a scene and where the Director gets them from. The `actor` name is the one shots and marks use.

enum Source {
	## The actor the player holds.
	LIVE_PLAYER,
	## An actor already in the region, found by its node name.
	LIVE_NAMED,
	## An actor the Director makes from `def` at `spawn_mark`.
	SPAWN,
}

## What an actor is left doing when the scene ends.
enum After {
	## The brain it had; none if it was spawned.
	KEEP,
	## Removed from the region.
	FREE,
	## Given its def's own brain.
	ENEMY_BRAIN,
}

## The name shots use for this actor.
@export var actor: StringName
@export var source: Source = Source.LIVE_PLAYER
## LIVE_NAMED: the actor node's name in the region.
@export var node_name: StringName
## SPAWN: what to make, and where (a mark of the scene).
@export var def: ActorDef
@export var spawn_mark: StringName
## A required actor that is missing or dead refuses the scene; an optional one drops out with its beats.
@export var required := true
@export var after: After = After.KEEP
## Who speaks for this actor: a Registry `speakers` id.
@export var speaker: StringName
