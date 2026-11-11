class_name Combat
extends RefCounted
## The rules of a blow, in one place: what a blow (a HitEvent: its HitProfile and the way it travels) does
## to a body that stands as a Defense says. resolve is a pure function of its arguments, so the rules are
## tested on their own, and Melee can judge every hit of a frame before applying any of them.


## What `e` comes to against `d`, by the defender's `tuning` (its guard arc, and what its parry and catch take
## from the attacker). The first rule that applies wins:
##   1. the target is dead, paired or invulnerable: WHIFF
##   2. a LOW blow on the airborne: WHIFF (it passes under)
##   3. an evade window open (d.evading) against an ordinary blow or a GRAB: EVADED. The blow is spent: it does nothing
##      to the target, whatever guard or parry is up too. `perfect` says whether the dodge matched (is_perfect). A
##      SWEEP and a THRUST are not avoided and go on down the rules. An evade of a defender with a chain at Quick or Flurry
##      takes posture from the attacker (d.evade_chip, doubled when perfect: attacker_posture_damage)
##   4. a GRAB: GRABBED, which starts the attacker's grab pair (Melee); for an attacker without one it is taken as a
##      HIT that staggers, so it carries the blow's damage and posture and a STAGGER
##   5. a parry with the attacker inside the arc: an ordinary blow is PARRIED (the attacker loses the blow's
##      posture damage times parry_posture_scale), a THRUST is CAUGHT (the attacker loses catch_posture); a
##      SWEEP cannot be parried and goes on down the rules
##   6. a guard with the attacker inside the arc, against a blow a guard can take (an ordinary one): GUARDED,
##      paying the blow's guard_stamina, or GUARD_BREAK when there is less stamina than that (all of it is
##      spent); either way the guard takes the blow's posture damage
##   7. otherwise a HIT: the blow's damage and posture damage, and a reaction: none under hyper-armour; else a STAGGER
##      whatever the blow's weight when the target's dodge chain is at Quick or Flurry (d.chain_tempo; the longer he
##      stood and dodged, the more the blow that finds him costs); else, once the poise damage reaches the target's
##      poise, a STAGGER if the blow staggers or else a FLINCH; below the poise, none
## The arc is guard_arc_deg either side of the defender's facing, toward where the attacker stands (back
## along the blow's direction).
static func resolve(e: HitEvent, d: Defense, tuning: CombatTuning) -> HitResult:
	var r := HitResult.new()
	var p := e.profile
	if d.dead or d.paired or d.invulnerable:
		return r
	if p.height == HitProfile.Height.LOW and d.airborne:
		return r
	if d.evading != MoveData.Evade.NONE and (p.perilous == HitProfile.Perilous.NONE or p.perilous == HitProfile.Perilous.GRAB):
		r.outcome = HitResult.Outcome.EVADED
		r.perfect = is_perfect(d.evading, p)
		r.attacker_posture_damage = d.evade_chip * (2.0 if r.perfect else 1.0)
		return r
	if p.perilous == HitProfile.Perilous.GRAB:
		r.outcome = HitResult.Outcome.GRABBED
		r.hp_damage = p.damage
		r.posture_damage = p.posture_damage
		r.reaction = HitResult.Reaction.STAGGER
		return r
	var faced := _faces_attacker(e, d, tuning)
	if d.parrying and faced and p.parryable():
		if p.perilous == HitProfile.Perilous.THRUST:
			r.outcome = HitResult.Outcome.CAUGHT
			r.attacker_posture_damage = tuning.catch_posture
		else:
			r.outcome = HitResult.Outcome.PARRIED
			r.attacker_posture_damage = p.posture_damage * tuning.parry_posture_scale
		return r
	if d.guarding and faced and p.guardable():
		r.posture_damage = p.posture_damage
		if d.stamina >= p.guard_stamina:
			r.outcome = HitResult.Outcome.GUARDED
			r.stamina_cost = p.guard_stamina
		else:
			r.outcome = HitResult.Outcome.GUARD_BREAK
			r.stamina_cost = d.stamina
		return r
	r.outcome = HitResult.Outcome.HIT
	r.hp_damage = p.damage
	r.posture_damage = p.posture_damage
	if d.hyperarmour:
		r.reaction = HitResult.Reaction.NONE
	elif d.chain_tempo >= 1:
		r.reaction = HitResult.Reaction.STAGGER
	elif p.poise_damage < d.poise:
		r.reaction = HitResult.Reaction.NONE
	elif p.staggers:
		r.reaction = HitResult.Reaction.STAGGER
	else:
		r.reaction = HitResult.Reaction.FLINCH
	return r


## Whether the evade `evade` is the perfect dodge of the blow `p`: any evade of a grab, a SWAY of a STRAIGHT blow, a
## DUCK of a ROUND one. No evade (NONE) is no dodge at all.
static func is_perfect(evade: MoveData.Evade, p: HitProfile) -> bool:
	if evade == MoveData.Evade.NONE:
		return false
	if p.perilous == HitProfile.Perilous.GRAB:
		return true
	return evade == (MoveData.Evade.SWAY if p.line == HitProfile.Line.STRAIGHT else MoveData.Evade.DUCK)


## What a blow of a paired move (`e.paired`: a lead's pair_hit mark) comes to. No rule judges it, since the
## follower is held where the lead's blows land and no one else's blow can reach either of them: it is a HIT with
## the profile's damage and posture damage and no reaction, since the follow move is the follower's reaction.
static func pair_hit(e: HitEvent) -> HitResult:
	var r := HitResult.new()
	r.outcome = HitResult.Outcome.HIT
	r.hp_damage = e.profile.damage
	r.posture_damage = e.profile.posture_damage
	return r


# Whether the attacker stands within the guard arc of the defender's facing: the way back along the blow is
# within guard_arc_deg of it, on the ground plane.
static func _faces_attacker(e: HitEvent, d: Defense, tuning: CombatTuning) -> bool:
	var toward_attacker := Vector3(-e.direction.x, 0.0, -e.direction.z)
	var facing := Vector3(d.facing.x, 0.0, d.facing.z)
	return facing.angle_to(toward_attacker) <= deg_to_rad(tuning.guard_arc_deg)
