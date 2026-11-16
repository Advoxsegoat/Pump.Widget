class_name SoundCue
extends Resource
## One sound of the game as data: which recorded or made files it plays and how. Marks (`sfx`), hit profiles
## (`impact_sound`) and actor defs (`surface_sound`, `hurt_voice`) name a cue by its `id`; Sfx plays it. The
## cues are in data/sounds/, the Registry kind `sounds`, so a better recording replaces a made sound by changing
## one cue's streams and nothing else.

@export var id: StringName
## The files a cue plays, one of them each time: variants of the same sound, so that a blow repeated does not
## sound the same twice running. Sfx never plays the one it played last twice in a row.
@export var streams: Array[AudioStream] = []
## How loud the cue is, over its files'.
@export var volume_db := 0.0
## How far the pitch is shaken each time it plays, either way, as a fraction (0.08 is up to 8% up or down).
@export_range(0.0, 0.5) var pitch_jitter := 0.08
## The audio bus it plays on (default_bus_layout.tres has Music, SFX, Voice and UI).
@export var bus := &"SFX"
