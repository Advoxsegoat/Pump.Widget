class_name CueEvent
extends Resource
## A sound or a piece of music at a frame of a shot.

enum Kind { SOUND, MUSIC }

## Frames into the shot.
@export var at := 0
@export var kind: Kind = Kind.SOUND
## SOUND: a Registry `sounds` id. MUSIC: a name the music system will know; it is signalled, not played, for now.
@export var id: StringName
## A sound plays at this actor or mark; empty is not placed in the world.
@export var at_ref: StringName
