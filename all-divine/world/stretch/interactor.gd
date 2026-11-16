class_name Interactor
extends Node
## The player's hand on the world: each frame it finds the nearest Interactable in reach (the one whose prompt is not empty) and, if
## the interact button went down this frame, uses it. It does nothing while the game is not in play, and while Abarax is dead,
## frozen by a blow, in the middle of a move or in a paired move, or a scene is on: a press made then is no one's.
##
## It runs after every actor (priority 10), so it sees where they stand at the end of the frame, and it reads the press through
## `Inputs.pressed_this_frame()`, the seam a recording stores and a replay feeds, so a replayed session rests where the recorded one did.

## An interactable was used.
signal interacted(what: Interactable)

## The one in reach whose line is shown now, or null.
var current: Interactable
## Whose hand it is.
var player: Actor


func _init() -> void:
	process_physics_priority = 10


## The line that tells the player what the button does now, `"<key>  <prompt>"` (the key of the device he last used), or "" when
## there is nothing in reach.
func prompt_line() -> String:
	if current == null or not is_instance_valid(current):
		return ""
	var key := ControlsList.shown(&"interact", Inputs.last_device() == Inputs.Device.GAMEPAD)
	return "%s  %s" % [key, current.prompt(player)]


## Whether the player may use anything now.
func can_act() -> bool:
	if player == null or not is_instance_valid(player) or player.stats == null:
		return false
	if Game.state != Game.State.PLAY or Director.current() != null or Director.moment_playing() != null:
		return false
	return not player.dead and player.frozen <= 0 and player.runner.current == null and player.paired_with == null


func _physics_process(_delta: float) -> void:
	current = _nearest() if can_act() else null
	if current != null and Inputs.pressed_this_frame().has(&"interact"):
		var used := current
		used.interact(player)
		interacted.emit(used)


# The nearest interactable of this run in reach of the player whose prompt is not empty, or null.
func _nearest() -> Interactable:
	var best: Interactable = null
	var best_distance := INF
	var run := get_parent()
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var thing := node as Interactable
		if thing == null or not run.is_ancestor_of(thing) or not thing.in_reach(player) or thing.prompt(player).is_empty():
			continue
		var distance := Vector2(thing.global_position.x - player.global_position.x, thing.global_position.z - player.global_position.z).length()
		if distance < best_distance:
			best = thing
			best_distance = distance
	return best
