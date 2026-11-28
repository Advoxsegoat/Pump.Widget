class_name Interactable
extends Node3D
## Something in the world the player can use with the interact button when he stands near it: a shrine to rest at (and, in the
## parts of the stretch to come, a latch, a pickup, a notice). The Interactor finds the nearest one in reach whose prompt is not
## empty, shows its line and calls `interact` when the button is pressed.
##
## This is the whole contract; each kind overrides `prompt` and `interact`.

## The group every interactable is in (from the frame it is ready).
const GROUP := &"interactables"

## How near, flat, the actor must be to this node's place for the press to reach it.
@export var radius := 1.8


func _ready() -> void:
	add_to_group(GROUP)


## What pressing the button would do, in a word or two ("Rest"); "" for nothing to offer this actor now (the line is then not
## shown and the press does nothing here).
func prompt(_actor: Actor) -> String:
	return ""


## Whether the press would do something for `actor` (a line that only says why not, like a barred latch's, is not usable). When two are in
## reach the Interactor offers a usable one before one that is not, whichever is nearer, so that a line that does nothing never takes away
## a press that does.
func usable(_actor: Actor) -> bool:
	return true


## The press: `actor` used this.
func interact(_actor: Actor) -> void:
	pass


## Whether `actor` is within `radius` of this node, flat (height does not count: a plinth is a plinth).
func in_reach(actor: Actor) -> bool:
	var here := global_position
	var there := actor.global_position
	return Vector2(there.x - here.x, there.z - here.z).length() <= radius
