class_name ActorDef
extends Resource
## An actor as data: its body, its moves and its numbers. Abarax is data/actors/abarax.tres; the
## Registry finds it by `id`.

@export var id: StringName
## The scene with the actor's Rig (see actors/rig.gd).
@export var rig_scene: PackedScene
## Input action -> move id, for the moves the actor starts from rest. Moves reached by cancelling into
## them are named by their clips' cancel_open marks instead.
@export var moveset: Dictionary = {}
@export var locomotion: LocomotionTuning
@export var max_hp := 100.0
@export var max_stamina := 100.0
@export var max_posture := 100.0
@export var poise := 10.0
## Clips the rig must have, and that must not leave the bind pose showing (see ClipChecker).
@export var required_clips := PackedStringArray(["idle", "walk", "jog", "sprint"])
