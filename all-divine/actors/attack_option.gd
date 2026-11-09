class_name AttackOption
extends Resource
## One attack an enemy's brain can choose (BrainDef.attacks): which action it presses, from how far and how square on,
## how often, and what it presses after. The move it starts is the actor's own, `def.moveset[action]`, and the combo's
## moves are the ones its cancel windows open into, so the clip checker and the coverage test reach every move a brain
## can use by following the same chain.
##
## The range is where the move really lands on a standing Abarax, measured with bodies that stop at each other (BodySpacing),
## not where it looks like it should: a min_range of 0 means it lands from body contact on. tests/actors/test_enemy_brain.gd
## fires every option of every brain at both ends of its range and checks each blow connects.

## The moveset action pressed to start the attack.
@export var action: StringName
## From how near and how far (metres, centre to centre on the ground) the whole attack lands, its combo included.
@export var min_range := 0.0
@export var max_range := 2.0
## How far off the body's facing (degrees) the target may be when it is pressed (the move's aim turns the body the rest
## of the way during its wind-up).
@export var max_angle_deg := 45.0
## Seconds after the attack is over before this option can be chosen again.
@export var cooldown := 1.5
## How likely it is to be chosen against the other options that can be: its share of their weights.
@export var weight := 1.0
## How far (metres) the brain may back up to throw it: it is on the menu only when the actor stands no more than this short
## of min_range. Walking in to it from further out is always allowed. A travelling attack thrown from close would need a
## long back-up first; with a margin it is chosen only from out where it belongs (the sweep closes a gap).
@export var back_up_margin := 1.0
## Whether it needs one of the target's attack tokens (AttackTokens) to be thrown.
@export var needs_token := true
## Actions pressed in turn after `action`, each as the cancel window that takes it opens: ["palm", "palm"] after the
## jab is the cross and then the hook.
@export var combo := PackedStringArray()
