class_name Brain
extends RefCounted
## What drives an actor: the player's hands, a script, later an enemy's mind or a cutscene. The actor
## asks its brain once per physics frame what it wants, as an Intent; a brain never moves the actor
## itself, so any brain can take over at any time (Actor.set_brain). This one wants nothing.


## What `actor` should do over the next `delta` seconds.
func think(_actor: Actor, _delta: float) -> Intent:
	return Intent.new()
