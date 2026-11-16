extends TestCase
## A foe who has come round a wall stays come round (Task 15c, fix round 1). The first way-round dropped its plan the moment the foe stood
## where he had a line, and the ordinary brain (circle, space, close in) walked him one step back into the wall's shadow, where he planned
## again: two to four turns a second of about a metre, the legs flipping some 170 degrees at each turn (the cause of two red tests of
## Task 14f's file). Now a foe who has come round holds the lit ground while the target stands where he was: he does not step back behind
## the thing he came round, and he does not plan again for HOLD_FRAMES after arriving.
##
## Measured here, in fights of three tier I Knuckles on a still Abarax, TEN seeds each, in their own arenas, 1,200 frames:
##   legs      the strafe angle the rig is given (foe.rig.warp.angle) jumps more than 90 degrees from the frame before, both over 45
##             degrees, more than LEG_JUMPS times in any 60 frames (the measure of Task 14f's shiver test)
##   crossings the foe's line to the player (the world's, chest and hand) turns from there to none or back more than CROSSINGS times in any
##             120 frames while the player stands still
## in the places the review found it: a wall 1 m long (the player 0.7 m behind it), Task 14f's gate (2 m wide, 0.8 m thick, the player in
## the gap, the foes 2.5 m out at -50, 0 and 50 degrees) and a doorway 1.2 m wide (the player 2 m inside).
##
## Before this round (402cf55) the legs jumped more than twice in 25 of 40 fights at the gate and the 1 m wall; the base had 0 of 40.

const FAR := 40.0
const SEEDS := 10
const FRAMES := 1200
const LEG_JUMPS := 2
const CROSSINGS := 2
const HAND := 0.72
## Task 14f's spacing: every two foes over this many degrees apart seen from the player.
const APART_DEG := 40.0
const FOES_AT := [Vector2(-1.2, -2.3), Vector2(0.0, -2.6), Vector2(1.2, -2.3)]


static func _walls(place: String) -> Array:
	match place:
		"wall1":
			return [[Vector3(0, 1.5, 0), Vector3(1, 3, 0.2)]]
		"gate", "behind":
			return [[Vector3(-6.0, 1.5, 0), Vector3(10, 3, 0.8)], [Vector3(6.0, 1.5, 0), Vector3(10, 3, 0.8)]]
		"door":
			return [[Vector3(-5.6, 1.5, 0), Vector3(10, 3, 0.2)], [Vector3(5.6, 1.5, 0), Vector3(10, 3, 0.2)]]
	return []


## [player, [foes (x, z)]] of a place.
static func _spots(place: String) -> Array:
	match place:
		"wall1":
			return [Vector3(0, 0, 0.7), FOES_AT]
		"door":
			return [Vector3(0, 0, 2.0), [Vector2(-1.2, -2.6), Vector2(0.0, -3.0), Vector2(1.2, -2.6)]]
		"behind":  # the player 2.5 m behind the gate's gap
			return [Vector3(0, 0, -2.5), [Vector2(-1.9, 1.6), Vector2(0.0, 2.5), Vector2(1.9, 1.6)]]
	return [Vector3.ZERO, [Vector2(-1.9, 1.6), Vector2(0.0, 2.5), Vector2(1.9, 1.6)]]  # the gate: the player in the gap


func _fight(place: String, seed_value: int, origin: Vector3) -> Dictionary:
	var arena := TestArena.make(self)
	arena.position = origin
	arena.add_child(AttackTokens.new())
	for w: Array in _walls(place):
		TestArena.wall(arena, w[0], w[1])
	var spots := _spots(place)
	var player_at: Vector3 = spots[0]
	var player := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 1000.0), Brain.new(), player_at, "A")
	player.place(Transform3D(Basis(Vector3.UP, PI), origin + player_at))
	var run := {"arena": arena, "player": player, "foes": [] as Array[Actor], "frame": 0, "place": place, "seed": seed_value,
		"warp": [], "jumps": [], "jump_max": 0, "line": [], "cross": [], "cross_max": 0, "apart_run": 0, "apart_best": 0, "apart_first": -1, "through": -1}
	for i in 3:
		var def := load("res://data/actors/knuckle_1.tres") as ActorDef
		var xz: Vector2 = (spots[1] as Array)[i]
		var at := Vector3(xz.x, 0, xz.y)
		var brain := EnemyBrain.new(def.brain, seed_value * 7 + i)
		var foe := TestArena.spawn(arena, def, brain, at, "Foe%d" % (i + 1))
		foe.place(Transform3D(Basis(Vector3.UP, atan2(-(player_at.x - at.x), -(player_at.z - at.z))), origin + at))
		brain.target = player
		brain.mode = EnemyBrain.Mode.ENGAGED
		brain._engage(foe)
		(run["foes"] as Array[Actor]).append(foe)
		run["warp"].append(0.0)
		run["jumps"].append([])
		run["line"].append(true)
		run["cross"].append([])
	return run


static func _cut(foe: Actor, player: Actor, height: float) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(foe.global_position + Vector3.UP * height, player.global_position + Vector3.UP * height, Layers.WORLD, [foe.get_rid(), player.get_rid()])
	return not foe.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## Adds `flag` (1 or 0) to the last `size` entries of `hist`; returns their sum.
static func _window(hist: Array, flag: int, size: int) -> int:
	hist.append(flag)
	if hist.size() > size:
		hist.pop_front()
	return hist.reduce(func(t: int, x: int) -> int: return t + x, 0)


func _observe(run: Dictionary) -> void:
	run["frame"] += 1
	var now: int = run["frame"]
	var player: Actor = run["player"]
	player.stats.refill()
	var foes: Array[Actor] = run["foes"]
	var angles: Array[float] = []
	var through := 0
	for i in foes.size():
		var foe := foes[i]
		var warp_now := rad_to_deg(foe.rig.warp.angle) if foe.rig.warp != null else 0.0
		var before: float = run["warp"][i]
		var jump := 1 if now > 30 and absf(warp_now) > 45.0 and absf(before) > 45.0 and absf(rad_to_deg(angle_difference(deg_to_rad(warp_now), deg_to_rad(before)))) > 90.0 else 0
		run["warp"][i] = warp_now
		run["jump_max"] = maxi(run["jump_max"], _window(run["jumps"][i], jump, 60))
		var line := not (_cut(foe, player, 1.1) or _cut(foe, player, HAND))
		var cross := 1 if now > 1 and line != run["line"][i] else 0
		run["line"][i] = line
		run["cross_max"] = maxi(run["cross_max"], _window(run["cross"][i], cross, 120))
		angles.append(rad_to_deg(Vector2(foe.global_position.x - player.global_position.x, foe.global_position.z - player.global_position.z).angle()))
		if run["place"] == "behind" and foe.global_position.z < 0.4 + player.global_position.z * 0.0:
			through += 1
	if run["through"] < 0 and through == foes.size():
		run["through"] = now
	var smallest := 360.0
	for i in 3:
		for j in range(i + 1, 3):
			smallest = minf(smallest, absf(fposmod(angles[i] - angles[j] + 180.0, 360.0) - 180.0))
	run["apart_run"] = run["apart_run"] + 1 if smallest > APART_DEG else 0
	run["apart_best"] = maxi(run["apart_best"], run["apart_run"])
	if run["apart_run"] >= 60 and run["apart_first"] < 0:
		run["apart_first"] = now


func _free(runs: Array[Dictionary]) -> void:
	for node in Sfx.playing_nodes():
		node.stop()
	OS.delay_msec(150)
	for run in runs:
		if is_instance_valid(run["arena"]):
			(run["arena"] as Node).free()


func _fights(place: String, frames_n := FRAMES) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for s in SEEDS:
		runs.append(_fight(place, s + 1, Vector3(s * FAR, 0, 0)))
	for f in frames_n:
		await frames(1)
		for run in runs:
			_observe(run)
	_free(runs)
	return runs


static func _worst(runs: Array[Dictionary], key: String) -> int:
	var worst := 0
	for run in runs:
		worst = maxi(worst, run[key])
	return worst


static func _over(runs: Array[Dictionary], key: String, limit: int) -> int:
	var n := 0
	for run in runs:
		n += 1 if run[key] > limit else 0
	return n


func _hold_still(place: String) -> void:
	var runs: Array[Dictionary] = await _fights(place)
	var report := OS.get_environment("FOE_COME_ROUND_REPORT")
	if report != "":
		var f := FileAccess.open(report, FileAccess.READ_WRITE) if FileAccess.file_exists(report) else FileAccess.open(report, FileAccess.WRITE)
		f.seek_end()
		f.store_string("%s: legs worst %d (%d of %d fights over %d), crossings worst %d (%d over %d)\n" % [place, _worst(runs, "jump_max"), _over(runs, "jump_max", LEG_JUMPS), runs.size(),
				LEG_JUMPS, _worst(runs, "cross_max"), _over(runs, "cross_max", CROSSINGS), CROSSINGS])
		f.close()
	assert_true(_over(runs, "jump_max", LEG_JUMPS) == 0, "%s: no foe's legs (the strafe angle the rig is given) jump more than 90 degrees more than %d times in 60 frames (worst %d; %d of %d fights)" % [place, LEG_JUMPS, _worst(runs, "jump_max"), _over(runs, "jump_max", LEG_JUMPS), runs.size()])
	assert_true(_over(runs, "cross_max", CROSSINGS) == 0, "%s: no foe crosses between having a line and having none more than %d times in 120 frames while the player stands still (worst %d; %d of %d fights)" % [place, CROSSINGS, _worst(runs, "cross_max"), _over(runs, "cross_max", CROSSINGS), runs.size()])


func test_at_a_one_metre_wall_a_foe_who_has_come_round_stays_come_round() -> void:
	await _hold_still("wall1")


func test_in_a_gate_a_foe_who_has_come_round_stays_come_round() -> void:
	await _hold_still("gate")


func test_in_a_doorway_a_foe_who_has_come_round_stays_come_round() -> void:
	await _hold_still("door")
