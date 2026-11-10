class_name Defense
extends RefCounted
## What a body could do about a blow at one moment: the parts of its state the rules of a blow read
## (Combat.resolve), copied out of the actor. Melee takes one of every actor before any of them moves in a
## frame and judges every hit of that frame against it, so that a hit is judged against the defender as it
## stood when the frame began, whatever order the actors ran in: in a trade, neither side's blow has already
## flinched the other.

## A move's marks make the body untouchable (a roll's iframes).
var invulnerable := false
## Off the ground: a LOW blow passes under it.
var airborne := false
## A guard is up: a move's guard_on mark (guard_raise from its f4), or the guard stance (Actor.is_guarding).
var guarding := false
## A parry window is open: a move's parry_on mark (guard_raise's first ten frames).
var parrying := false
## An evade window is open (a move's evade_on mark): which dodge it is, or NONE.
var evading: MoveData.Evade = MoveData.Evade.NONE
## A move's marks let the body take a blow without a reaction.
var hyperarmour := false
## The way the body faces, on the ground plane, of length 1: a guard or a parry covers the arc about it.
var facing := Vector3(0, 0, 1)
## The threshold a blow's poise damage must reach to flinch the body.
var poise := 0.0
## What a guard has to pay a blow's guard_stamina with.
var stamina := 0.0
var posture_broken := false
var dead := false
## In a paired move (a finisher, a grab; Actor.paired_with), where no one else's blow lands.
var paired := false


## `actor` as it stands now.
static func of(actor: Actor) -> Defense:
	var d := Defense.new()
	d.invulnerable = actor.is_invulnerable()
	d.airborne = actor.runner.airborne
	d.hyperarmour = actor.runner.hyperarmour
	d.guarding = actor.is_guarding()
	d.parrying = actor.runner.parry_window
	d.evading = actor.runner.evading
	var flat := Vector3(actor.facing().x, 0.0, actor.facing().z)
	if not flat.is_zero_approx():
		d.facing = flat.normalized()
	d.poise = actor.stats.poise
	d.stamina = actor.stats.stamina
	d.posture_broken = actor.stats.posture_broken
	d.dead = actor.dead
	d.paired = actor.paired_with != null
	return d
