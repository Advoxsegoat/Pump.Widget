class_name DialogueLine
extends Resource
## One line of speech, shown in the dialogue box of the shot it is in.

## A Registry `speakers` id.
@export var speaker: StringName
@export var text := ""
## A portrait of the speaker.
@export var expr: StringName = &"neutral"
## Frames into the shot.
@export var at := 0
## Frames the line stays up; 0 is its typing time plus 45.
@export var hold := 0
