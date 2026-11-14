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
## EVADED      an evade window (a sway or a duck) avoided an ordinary blow or a grab: the blow is spent, with no weight and
##             nothing taken off the target, and both fighters hear of it (`perfect` says whether the dodge matched). A
##             target whose chain is at Quick or Flurry takes posture from the attacker for it (attacker_posture_damage)
## GRABBED     a grab took hold: Melee starts the attacker's grab pair, and the blow itself does nothing more; an
##             attacker without a grab pair has it taken as a HIT that staggers
enum Outcome { WHIFF, HIT, GUARDED, GUARD_BREAK, PARRIED, CAUGHT, GRABBED, EVADED }
## The reaction move the target plays: none, its `flinch`, or its longer `stagger`.
enum Reaction { NONE, FLINCH, STAGGER }

var outcome: Outcome = Outcome.WHIFF
## For an EVADED blow: the dodge matched the blow's line (Combat.is_perfect), or it was a grab.
var perfect := false
var reaction: Reaction = Reaction.NONE
## Taken off the target's HP.
var hp_damage := 0.0
## Taken off the target's posture.
var posture_damage := 0.0
## Taken off the target's stamina (a guard paying for the blow).
var stamina_cost := 0.0
## Taken off the attacker's posture (a parry or a catch, or an evade by a body whose chain is at Quick or Flurry).
var attacker_posture_damage := 0.0
