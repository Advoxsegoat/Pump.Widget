class_name EndlessMove
extends RefCounted
## A move that never ends, for the tests of what the bot calls a soft-lock: a copy of a move whose clip holds its charge for
## 100,000 frames (put in the actor's rig), which an actor holding the charge's button stands in for good.


## A copy of the move `move_id` (one with a charge_hold mark) with its charge held for 100,000 frames, its clip added to `actor`'s rig.
## Returns {move, action}: the MoveData to start, and the action a brain holds to stay in it.
static func make(actor: Actor, move_id: StringName) -> Dictionary:
	var original := Registry.fetch(&"moves", move_id) as MoveData
	var clip := actor.rig.tree.get_animation(original.clip).duplicate(true) as Animation
	var marks := Marks.read(clip)
	var action := &""
	for mark in marks:
		if mark["kind"] == &"charge_hold":
			mark["args"]["frames"] = 100000
			action = StringName(mark["args"].get("action", &""))
	Marks.write(clip, marks)
	var clip_name := StringName("endless_%s" % move_id)
	actor.rig.tree.get_animation_library(&"").add_animation(clip_name, clip)
	var move := original.duplicate() as MoveData
	move.id = clip_name
	move.clip = clip_name
	return {"move": move, "action": action}
