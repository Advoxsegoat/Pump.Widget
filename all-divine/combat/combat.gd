class_name Combat
extends RefCounted
## The rules of a blow, in one place: what a blow (a HitEvent: its HitProfile and the way it travels) does
## to a body that stands as a Defense says. resolve is a pure function of its arguments, so the rules are
## tested on their own, and Melee can judge every hit of a frame before applying any of them.


## What `e` comes to against `d`, by the defender's `tuning` (its guard arc, and what its parry and catch take
## from the attacker). The first rule that applies wins:
##   1. the target is dead, paired or invulnerable: WHIFF
##   2. a LOW blow on the airborne: WHIFF (it passes under)
##   3. a GRAB: GRABBED. Until paired moves exist it is taken as a HIT that staggers, so it carries the
##      blow's damage and posture and a STAGGER
##   4. a parry with the attacker inside the arc: an ordinary blow is PARRIED (the attacker loses the blow's
##      posture damage times parry_posture_scale), a THRUST is CAUGHT (the attacker loses catch_posture); a
##      SWEEP cannot be parried and goes on down the rules
##   5. a guard with the attacker inside the arc, against a blow a guard can take (an ordinary one): GUARDED,
##      paying the blow's guard_stamina, or GUARD_BREAK when there is less stamina than that (all of it is
##      spent); either way the guard takes the blow's posture damage
##   6. otherwise a HIT: the blow's damage and posture damage, and a reaction: none under hyper-armour; else,
##      once the poise damage reaches the target's poise, a STAGGER if the blow staggers or else a FLINCH;
##      below the poise, none
## The arc is guard_arc_deg either side of the defender's facing, toward where the attacker stands (back
## along the blow's direction).
static func resolve(e: HitEvent, d: Defense, tuning: CombatTuning) -> HitResult:
	var r := HitResult.new()
	var p := e.profile
	if d.dead or d.paired or d.invulnerable:
		return r
	if p.height == HitProfile.Height.LOW and d.airborne:
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
	if d.hyperarmour or p.poise_damage < d.poise:
		r.reaction = HitResult.Reaction.NONE
	elif p.staggers:
		r.reaction = HitResult.Reaction.STAGGER
	else:
		r.reaction = HitResult.Reaction.FLINCH
	return r


# Whether the attacker stands within the guard arc of the defender's facing: the way back along the blow is
# within guard_arc_deg of it, on the ground plane.
static func _faces_attacker(e: HitEvent, d: Defense, tuning: CombatTuning) -> bool:
	var toward_attacker := Vector3(-e.direction.x, 0.0, -e.direction.z)
	var facing := Vector3(d.facing.x, 0.0, d.facing.z)
	return facing.angle_to(toward_attacker) <= deg_to_rad(tuning.guard_arc_deg)
