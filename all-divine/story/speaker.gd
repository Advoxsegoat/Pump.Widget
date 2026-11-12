class_name Speaker
extends Resource
## Who a line is spoken by: a name, a set of portraits and the pitch of its voice blip. Data in
## data/speakers/, found by the Registry as the kind `speakers`.

@export var id: StringName
@export var display_name := ""
## Expression name to a 48 by 48 picture. It must include `neutral`.
@export var portraits: Dictionary = {}
## How high the voice blip plays; 1 is as made.
@export var blip_pitch := 1.0
