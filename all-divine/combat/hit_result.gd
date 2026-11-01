class_name HitResult
extends RefCounted
## What came of a blow (Combat.resolve): its outcome, the reaction it forces on the target, and the numbers
## to take off each side. The target applies it (Actor.apply_hit); the attacker hears of it (Actor.hit_landed).

## WHIFF       nothing: the target could not be touched (dead, paired, invulnerable, or airborne under a LOW blow)
## HIT         the blow landed
## GUARDED     a guard took it, for stamina and posture
## GUARD_BREAK a guard took it but had too little stamina to pay for it: the guard breaks
## PARRIED     a parry turned it back: the attacker loses posture
## CAUGHT      a parry caught a thrust: the attacker loses a set amount of posture
## GRABBED     a grab took hold. Until paired moves exist, it is taken as a HIT that staggers
enum Outcome { WHIFF, HIT, GUARDED, GUARD_BREAK, PARRIED, CAUGHT, GRABBED }
## The reaction move the target plays: none, its `flinch`, or its longer `stagger`.
enum Reaction { NONE, FLINCH, STAGGER }

var outcome: Outcome = Outcome.WHIFF
var reaction: Reaction = Reaction.NONE
## Taken off the target's HP.
var hp_damage := 0.0
## Taken off the target's posture.
var posture_damage := 0.0
## Taken off the target's stamina (a guard paying for the blow).
var stamina_cost := 0.0
## Taken off the attacker's posture (a parry or a catch).
var attacker_posture_damage := 0.0
