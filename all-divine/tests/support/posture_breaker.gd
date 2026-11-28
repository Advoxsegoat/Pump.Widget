class_name PostureBreaker
extends Node
## Posts, once, a blow of `attacker`'s on `target` that takes all of the target's posture and nothing else (no damage,
## no reaction but the break, no hit-stop), in the middle of the next physics frame: after Melee's snapshot and before
## Melee, as the attacker's scanner would. Add it to the tree (TestCase.track) to break the target's posture on the
## next frame.

var attacker: Actor
var target: Actor


static func make(from: Actor, on: Actor) -> PostureBreaker:
	var breaker := PostureBreaker.new()
	breaker.attacker = from
	breaker.target = on
	return breaker


func _physics_process(_delta: float) -> void:
	if attacker == null:
		return
	var profile := HitProfile.new()
	profile.posture_damage = target.stats.max_posture
	profile.hitstop_frames = 0
	var move := MoveData.new()
	move.id = &"breaker"
	move.hits = {&"break": profile}
	var e := HitEvent.new()
	e.attacker = attacker
	e.target = target
	e.move = move
	e.profile = profile
	e.point = target.global_position + Vector3.UP
	e.direction = (target.global_position - attacker.global_position).normalized()
	Melee.post(e)
	attacker = null
