class_name ShrineDef
extends Resource
## One rose shrine as data: where its plinth stands, where the player stands up when he rests there or dies after having rested
## there, and how near he must be to rest. They are in data/stretch/, the Registry kind `stretch`, and the stretch's def names them.

@export var id: StringName
## What the shrine is called to the player (the notice, later the map).
@export var title := ""
## The foot of the plinth, on the ground: the shrine's glow is drawn there and the press that rests is measured from it.
@export var plinth := Vector3.ZERO
## Where he stands up (a point on standing ground, within two metres of the plinth and clear of every foe's post).
@export var respawn := Vector3.ZERO
## The way he faces there, in degrees about +Y: 0 faces south, 90 east, 180 north, 270 west.
@export var respawn_yaw_deg := 0.0
## How near, flat, he must be to the plinth for the press to rest.
@export var radius := 2.0
