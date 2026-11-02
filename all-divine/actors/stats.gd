class_name Stats
extends RefCounted
## An actor's numbers as it plays: what is left of its bars, and how they wear down and come back.
## Stamina is spent by moves and by sprinting, waits a moment, then regenerates; at zero the actor is
## exhausted until it has climbed back. Posture wears down under blows, waits, then mends, unless it has
## broken, which only restore_posture ends. Poise is the threshold a hit must reach to flinch the actor, and
## is the def's, for good. The numbers of how fast things come back are the def's CombatTuning.

var hp := 0.0
var stamina := 0.0
## A second bar beside HP: guards, parries and heavy hits wear it down, and at zero it breaks.
var posture := 0.0
var poise := 0.0
var max_hp := 0.0
var max_stamina := 0.0
var max_posture := 0.0
## Damage kind (StringName) -> how much of it is taken off, 0 to 1.
var resistances: Dictionary = {}
var tuning: CombatTuning
## Stamina ran out and has not yet climbed back to tuning.exhausted_until: no moves, no sprint.
var exhausted := false
## Posture emptied and has not been restored (by a finisher, or when the break has run its time).
var posture_broken := false

# Seconds since stamina was last spent or drained, and since posture was last damaged: regen starts when
# the matching delay has passed. Both start past any delay, so a fresh actor has nothing to wait for.
var _stamina_idle := INF
var _posture_idle := INF


## Full bars, from the actor's definition. A def with no combat tuning gets CombatTuning's defaults.
static func from_def(def: ActorDef) -> Stats:
	var stats := Stats.new()
	stats.max_hp = def.max_hp
	stats.max_stamina = def.max_stamina
	stats.max_posture = def.max_posture
	stats.hp = stats.max_hp
	stats.stamina = stats.max_stamina
	stats.posture = stats.max_posture
	stats.poise = def.poise
	stats.tuning = def.combat if def.combat != null else CombatTuning.new()
	return stats


## Whether the actor may start a move: it has stamina and is not exhausted.
func can_act() -> bool:
	return stamina > 0.0 and not exhausted


## Takes `amount` of stamina (not below 0) and restarts the wait before it comes back. Running out
## makes the actor exhausted. A spend of nothing (0 or less, as a guard pays for a blow of no guard_stamina)
## changes nothing, and does not hold the regen back.
func spend_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = maxf(stamina - amount, 0.0)
	_stamina_idle = 0.0
	if stamina <= 0.0:
		exhausted = true


## Takes `rate` stamina a second for `delta` seconds: what sprinting costs, a frame at a time. As a spend,
## it restarts the wait, so stamina does not come back while it goes on.
func drain_stamina(rate: float, delta: float) -> void:
	spend_stamina(rate * delta)


## Takes `amount` of HP (not below 0). True on the blow that empties it, and only that one.
func take_damage(amount: float) -> bool:
	var was_alive := hp > 0.0
	hp = maxf(hp - amount, 0.0)
	return was_alive and hp <= 0.0


## Takes `amount` of posture (not below 0) and restarts the wait before it mends. True on the blow that
## empties it, which also breaks it (posture_broken); a blow on a broken posture is not a new break.
func damage_posture(amount: float) -> bool:
	var was_standing := posture > 0.0
	posture = maxf(posture - amount, 0.0)
	_posture_idle = 0.0
	if was_standing and posture <= 0.0:
		posture_broken = true
		return true
	return false


## Fills posture and ends the break.
func restore_posture() -> void:
	posture = max_posture
	posture_broken = false


## One frame of `delta` seconds. After tuning.stamina_regen_delay without a spend, stamina regenerates at
## tuning.stamina_regen_rate (times tuning.guard_regen_scale while `guarding`), and exhaustion ends once
## it is back to tuning.exhausted_until. After tuning.posture_regen_delay without posture damage, and not
## while broken, posture regenerates at tuning.posture_regen_rate. Only the part of the frame after a delay
## counts, so a regen total is the same at any frame rate.
func tick(delta: float, guarding: bool) -> void:
	_stamina_idle += delta
	var rate := tuning.stamina_regen_rate * (tuning.guard_regen_scale if guarding else 1.0)
	stamina = minf(stamina + rate * _regen_time(_stamina_idle, tuning.stamina_regen_delay, delta), max_stamina)
	# A bar smaller than the climb (a minor foe's) would never get out of exhaustion.
	if exhausted and stamina >= minf(tuning.exhausted_until, max_stamina):
		exhausted = false
	_posture_idle += delta
	if not posture_broken:
		var mended := tuning.posture_regen_rate * _regen_time(_posture_idle, tuning.posture_regen_delay, delta)
		posture = minf(posture + mended, max_posture)


# How much of the last `delta` seconds was past `wait`, given `idle` seconds without a spend, this frame included.
static func _regen_time(idle: float, wait: float, delta: float) -> float:
	return clampf(idle - wait, 0.0, delta)
