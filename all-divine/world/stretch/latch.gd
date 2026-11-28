class_name Latch
extends Interactable
## The latch of a gate (made by the run for a `GateDef` with a `latch_radius`): on the side the gate can be lifted from it offers to lift
## the bar and a press sets the gate's flag; on the other side it says the bar is barred from there and a press does nothing. An open
## gate offers nothing.

const CUE := &"gate_unlatch"

var def: GateDef
var door: GateDoor


func _ready() -> void:
	super._ready()
	if def != null:
		radius = def.latch_radius


## Whether `actor` stands on the side the gate lifts from: his side of the latch's centre, along `open_side`.
func on_open_side(actor: Actor) -> bool:
	var there := Vector2(actor.global_position.x - def.latch_centre.x, actor.global_position.z - def.latch_centre.z)
	return there.dot(def.open_side) > 0.0


func prompt(actor: Actor) -> String:
	if def == null or door == null or door.is_released():
		return ""
	return def.latch_prompt if on_open_side(actor) else def.barred_prompt


## A barred latch gives the press nothing; the chooser lets something that can use the press come first.
func usable(actor: Actor) -> bool:
	return def != null and door != null and not door.is_released() and on_open_side(actor)


func interact(actor: Actor) -> void:
	if not usable(actor):
		return
	var run := get_parent() as StretchRun
	if run == null:
		return
	Sfx.play(CUE, global_position)
	run.set_flag(def.opens_on)
