extends TestCase
## HitScanner on its own (combat/hit_scanner.gd), in an arena: an attacker (Abarax, team PLAYER) whose processing
## is off, so that only the test moves its palm_l hitbox (by hand) and scans, and a target of team ENEMY standing
## 3 m in front of it that does nothing. A scan sweeps each live hitbox from where it was at the last scan to where it is now, so a hand that
## passes through a body between two ticks still finds it; a hitbox turned on and off between two scans is
## looked for once, where it is; the attacker's own hurtbox is never found; and each body is hit once per
## activation of a hitbox, and again only after a new begin.
##
## The target's hurtbox is a capsule of radius 0.35 m about its feet's vertical; the palm is a sphere of
## radius 0.18 m. Hand height here is 1.2 m.

const ABARAX := "res://data/actors/abarax.tres"
const HAND_Y := 1.2


## {attacker, target, scanner, shape (the attacker's palm_l), jab (MoveData)}: the attacker at (0, 0, -3), the
## target at the origin, both settled.
func _setup() -> Dictionary:
	var arena := TestArena.make(self)
	var attacker := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new([]), Vector3(0, 0, -3), "Attacker")
	attacker.set_physics_process(false)
	var foe := (load(ABARAX) as ActorDef).duplicate() as ActorDef
	foe.team = ActorDef.Team.ENEMY
	var target := TestArena.spawn(arena, foe, ScriptBrain.new([]), Vector3.ZERO, "Target")
	await frames(2)
	return {"arena": arena, "attacker": attacker, "target": target, "scanner": attacker.scanner,
			"shape": attacker.rig.hitbox_shape(&"palm_l"), "jab": Registry.fetch(&"moves", &"palm_jab")}


# The attacker's palm_l at `x`, HAND_Y, `z`, and a scan from the attacker: the targets it found.
func _scan_at(s: Dictionary, x: float, z := 0.0) -> Array:
	(s["shape"] as CollisionShape3D).global_position = Vector3(x, HAND_Y, z)
	var events: Array[HitEvent] = (s["scanner"] as HitScanner).scan(s["attacker"])
	return events.map(func(e: HitEvent) -> Actor: return e.target)


func test_fast_swing_between_ticks_hits_once() -> void:
	var s: Dictionary = await _setup()
	var scanner: HitScanner = s["scanner"]
	var shape: CollisionShape3D = s["shape"]
	scanner.begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, -1.0), [], "1 m to the target's side, out of reach")
	# 2 m to the other side in one tick: neither end is in reach, but the way between passes through the body.
	shape.global_position = Vector3(1.0, HAND_Y, 0.0)
	var events: Array[HitEvent] = scanner.scan(s["attacker"])
	assert_eq(events.size(), 1, "one event, though the sweep crossed the body in many steps")
	if events.size() != 1:
		return
	var e := events[0]
	assert_eq([e.attacker, e.target, e.move, e.profile, e.hitbox],
			[s["attacker"], s["target"], s["jab"], (s["jab"] as MoveData).hits[&"palm"], &"palm_l"])
	assert_vec_near(e.direction, Vector3(0, 0, 1), 1e-5, "flat and of length 1, from the attacker through the target")
	assert_true(e.point.x > -0.54 and e.point.x < -0.35, "the hand where it first touched the body: %s" % e.point)
	assert_near(e.point.y, HAND_Y, 1e-4)
	assert_eq(_scan_at(s, -1.0), [], "swung back through it: not hit again by the same activation")


func test_a_new_activation_starts_where_the_hitbox_is() -> void:
	var s: Dictionary = await _setup()
	assert_eq(_scan_at(s, -1.0), [], "nothing is on")
	(s["shape"] as CollisionShape3D).global_position = Vector3(1.0, HAND_Y, 0.0)
	(s["scanner"] as HitScanner).begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 1.0), [], "the first scan looks where the hand is, not along the way it came while off")
	assert_eq(_scan_at(s, 0.3), [s["target"]], "and from then on it sweeps")


func test_on_and_off_in_one_tick_still_hits() -> void:
	var s: Dictionary = await _setup()
	var scanner: HitScanner = s["scanner"]
	(s["shape"] as CollisionShape3D).global_position = Vector3(0.2, HAND_Y, 0.0)
	scanner.begin(&"palm_l", &"palm", s["jab"])
	scanner.end(&"palm_l")
	assert_eq(_scan_at(s, 0.2), [s["target"]], "looked for once, where it is now")
	assert_eq(_scan_at(s, 0.1), [], "and then it is off")
	scanner.begin(&"palm_l", &"palm", s["jab"])
	scanner.end(&"palm_l")
	assert_eq(_scan_at(s, 3.0), [], "on and off out of reach finds nothing")
	assert_eq(_scan_at(s, 0.0), [], "nor does it hit later, being off")


func test_own_hurtbox_is_never_hit() -> void:
	var s: Dictionary = await _setup()
	(s["scanner"] as HitScanner).begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 0.0, -3.0), [], "in the attacker's own chest")
	assert_eq(_scan_at(s, 0.0, -2.9), [], "still there")
	assert_eq(_scan_at(s, 0.0, 0.0), [s["target"]], "swept out of its own body into the target: only the target")


func test_an_ally_is_never_hit() -> void:
	var s: Dictionary = await _setup()
	var ally := TestArena.spawn(s["arena"], load(ABARAX), ScriptBrain.new([]), Vector3(3, 0, 0), "Ally")
	await frames(1)
	(s["scanner"] as HitScanner).begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 3.0), [], "in the body of one of its own team")
	assert_eq(_scan_at(s, 0.0), [s["target"]], "swept from there into the foe: only the foe")
	assert_eq(ally.def.team, (s["attacker"] as Actor).def.team)


func test_each_target_once_per_activation_and_again_after_a_new_begin() -> void:
	var s: Dictionary = await _setup()
	var scanner: HitScanner = s["scanner"]
	scanner.begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 0.0), [s["target"]])
	assert_eq(_scan_at(s, 0.1), [], "still inside: once per activation")
	assert_eq(_scan_at(s, 2.0), [])
	assert_eq(_scan_at(s, 0.0), [], "out and back in: still the same activation")
	scanner.end(&"palm_l")
	assert_eq(_scan_at(s, 0.0), [], "off")
	scanner.begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 0.0), [s["target"]], "a new begin hits it again")


func test_each_hitbox_is_its_own_activation() -> void:
	var s: Dictionary = await _setup()
	var scanner: HitScanner = s["scanner"]
	var attacker: Actor = s["attacker"]
	(s["shape"] as CollisionShape3D).global_position = Vector3(0.0, HAND_Y, 0.0)
	attacker.rig.hitbox_shape(&"palm_r").global_position = Vector3(0.1, HAND_Y, 0.0)
	scanner.begin(&"palm_l", &"palm", s["jab"])
	scanner.begin(&"palm_r", &"palm", s["jab"])
	var events: Array[HitEvent] = scanner.scan(attacker)
	assert_eq(events.map(func(e: HitEvent) -> StringName: return e.hitbox), [&"palm_l", &"palm_r"], "both hands land")
	scanner.end(&"palm_l")
	assert_eq(scanner.scan(attacker), [] as Array[HitEvent], "palm_r is still on, and has hit already")


func test_a_profile_the_move_lacks_turns_nothing_on() -> void:
	var s: Dictionary = await _setup()
	quietly(func() -> void: (s["scanner"] as HitScanner).begin(&"palm_l", &"no_such_profile", s["jab"]))
	assert_eq(_scan_at(s, 0.0), [], "no blow without a profile to land with")


func test_bodies_are_found_where_they_stood_when_the_frame_began() -> void:
	# The engine hands a moved node's transform to the physics server once every node has run its frame, so
	# within a frame a hurtbox is found where it stood when the frame began, whichever actor moved first. Every
	# scan relies on it (see HitScanner); this pins it, for the next engine upgrade.
	var s: Dictionary = await _setup()
	var scanner: HitScanner = s["scanner"]
	var target: Actor = s["target"]
	target.global_position = Vector3(5, 0, 0)
	scanner.begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 0.0), [target], "moved this frame: still found where it stood")
	scanner.begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 5.0), [], "and not yet where it went")
	await frames(1)
	scanner.begin(&"palm_l", &"palm", s["jab"])
	assert_eq(_scan_at(s, 5.0), [target], "found there once the frame is over")
