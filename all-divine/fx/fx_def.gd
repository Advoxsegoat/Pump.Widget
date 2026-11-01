class_name FxDef
extends Resource
## One visual effect as data: the scene that is shown and where it is shown. An `fx` mark, a hit and a tell name
## an FxDef by its `id`; ActorFx shows it. They are in data/fx/, the Registry kind `fx`.

@export var id: StringName
## The effect: a small scene (pixel particles or a sprite), shown when asked for and freed after `lifetime`.
@export var scene: PackedScene
## The bone of the actor's skeleton the effect rides, so that it follows (a hand for a trail). Empty means the
## actor's origin, where it stays: dust left on the ground. An `fx` mark may name another bone (`bone`), as the
## cross's trail follows its right hand and not the jab's left.
@export var bone: StringName
## Seconds the scene stays before it is freed: long enough for its particles to finish.
@export var lifetime := 0.5
