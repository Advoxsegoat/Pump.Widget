class_name Blows
extends RefCounted
## Blows posted to Melee by hand, so a string of them lands on exact frames: the attacker is a body standing where it
## stands (nothing is swung), and a blow is judged against the defender as it stood when the frame began, as any other.
## Post it while the target's frame is one short of the frame it should land on (the frame count is the target's `frame`:
## the blow is judged at the end of the next frame, against what the target stood as at its start).

## A jab-like profile (8 HP, 6 poise, 4 posture, a straight line, 8 guard stamina) with `fields` set on it.
static func profile(fields := {}) -> HitProfile:
	var p := HitProfile.new()
	p.damage = 8.0
	p.poise_damage = 6.0
	p.posture_damage = 4.0
	p.guard_stamina = 8.0
	for field: String in fields:
		p.set(field, fields[field])
	return p


## `attacker`'s blow `p` on `target`, from where the attacker stands.
static func event(attacker: Actor, target: Actor, p: HitProfile) -> HitEvent:
	var e := HitEvent.new()
	e.attacker = attacker
	e.target = target
	e.move = Registry.fetch(&"moves", &"palm_jab") as MoveData
	e.profile = p
	e.hitbox = &"palm_l"
	e.point = target.chest_point()
	var flat := Vector3(target.global_position.x - attacker.global_position.x, 0.0, target.global_position.z - attacker.global_position.z)
	e.direction = flat.normalized()
	return e


## Posts `attacker`'s blow (a profile made of `fields`) on `target` to Melee.
static func post(attacker: Actor, target: Actor, fields := {}) -> void:
	Melee.post(event(attacker, target, profile(fields)))
