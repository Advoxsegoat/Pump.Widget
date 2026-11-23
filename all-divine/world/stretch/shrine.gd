class_name Shrine
extends Interactable
## A rose shrine: a plinth with a glow on it (shrine.tscn). Pressing the button near it rests there: the run fills his bars, makes this
## the place he stands up at, and saves (`StretchRun.rest`). The shrine knows nothing of files or foes; it asks the run, its parent.

## The data: where it stands and how near he must be.
var def: ShrineDef


func _ready() -> void:
	super._ready()
	if def != null:
		radius = def.radius


func prompt(_actor: Actor) -> String:
	return "Rest"


func interact(_actor: Actor) -> void:
	var run := get_parent() as StretchRun
	if run != null and def != null:
		run.rest(def)
