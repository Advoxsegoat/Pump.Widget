extends TestCase
## A wall stops a blow (HitScanner): a body the sweep found is struck only if no `world` collider cuts the line from the
## attacker's chest to the hitbox and the line from the hitbox to the body's chest. The place is the test arena's floor and
## one wall 0.2 m thick, 3 m high and 4 m long (or 0.6 m high, for the low-wall cases) between the two fighters, who stand on
## the z axis: the attacker at the origin facing +Z, the target `gap` metres in front of it facing back.
##
## What is compared is always the same blow against the same fighters without the wall (or with the target out of reach, for
## the attacker's own moves): where the wall changes nothing, the frame of the hit is today's.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_BLADE := "res://data/actors/knuckle_blade.tres"
const KNUCKLE_HEAVY := "res://data/actors/knuckle_heavy.tres"
const FRAMES := 130
const WALL := Vector3(4.0, 3.0, 0.2)
const LOW_WALL := Vector3(4.0, 0.6, 0.2)


func after_each() -> void:
	Game.reset()


func _def(path: String, team: ActorDef.Team) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.team = team
	def.poise = 100.0
	return def


## Plays `move` of `attacker` (a def path, team PLAYER if it is Abarax's, else ENEMY) at `target` (the other team) `gap`
## metres off, with `walls` ([[centre, size], ...]) in the arena, for FRAMES frames. Returns {hits: the frames the target
## was struck on, trace: the attacker's [move id, time, in_recovery] at the end of each frame}.
func _blow(attacker_path: String, move: StringName, target_path: String, gap: float, walls: Array, target_at := Vector3.INF,
		mid := Callable()) -> Dictionary:
	var arena := TestArena.make(self)
	for w: Array in walls:
		TestArena.wall(arena, w[0], w[1])
	var a_team := ActorDef.Team.PLAYER if attacker_path == ABARAX else ActorDef.Team.ENEMY
	var t_team := ActorDef.Team.ENEMY if a_team == ActorDef.Team.PLAYER else ActorDef.Team.PLAYER
	var a := TestArena.spawn(arena, _def(attacker_path, a_team), ScriptBrain.new([]), Vector3.ZERO, "Attacker")
	a.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var at := Vector3(0, 0, gap) if target_at == Vector3.INF else target_at
	var t := TestArena.spawn(arena, _def(target_path, t_team), ScriptBrain.new([]), at, "Target")
	t.place(Transform3D(Basis(Vector3.UP, PI), at))
	var run := {"hits": [], "trace": [], "attacker": a, "target": t}
	t.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
		if r.outcome != HitResult.Outcome.WHIFF:
			run["hits"].append(a.frame))
	a.runner.start(Registry.fetch(&"moves", move) as MoveData)
	for i in FRAMES:
		await frames(1)
		if mid.is_valid():
			mid.call(run)
		run["trace"].append([a.runner.current.id if a.runner.current != null else &"", snappedf(a.runner.time, 0.0001), a.runner.in_recovery])
	arena.free()
	return run


func _wall(z: float, size := WALL, y := -1.0, x := 0.0) -> Array:
	return [[Vector3(x, size.y / 2.0 if y < 0.0 else y, z), size]]


# A blow thrown through the wall lands on nobody, and the attacker's move plays as one that hit nothing (the target out of reach).
func _stopped(attacker: String, move: StringName, target: String, gap: float, wall_z: float, far := 8.0) -> void:
	var open: Dictionary = await _blow(attacker, move, target, gap, [])
	var walled: Dictionary = await _blow(attacker, move, target, gap, _wall(wall_z))
	var whiff: Dictionary = await _blow(attacker, move, target, far, [])
	assert_true((open["hits"] as Array).size() > 0, "%s: the blow lands without the wall" % move)
	assert_eq(walled["hits"], [], "%s: the wall stops it" % move)
	assert_eq(whiff["hits"], [], "%s: the far control is a whiff" % move)
	assert_eq(walled["trace"], whiff["trace"], "%s: the attacker plays it as a miss, frame for frame" % move)


func test_a_palm_through_the_wall_hits_nobody_and_without_it_lands_on_frame_10() -> void:
	var open: Dictionary = await _blow(ABARAX, &"palm_jab", KNUCKLE_1, 0.9, [])
	assert_eq((open["hits"] as Array).slice(0, 1), [10], "without the wall the jab lands on frame 10, as it always did")
	var walled: Dictionary = await _blow(ABARAX, &"palm_jab", KNUCKLE_1, 0.9, _wall(0.45))
	assert_eq(walled["hits"], [], "with the wall between, no hit")


func test_the_knuckles_thrust_and_hook_and_the_blades_lunge_are_stopped() -> void:
	await _stopped(KNUCKLE_1, &"knuckle_thrust", ABARAX, 1.6, 1.3)
	await _stopped(KNUCKLE_1, &"knuckle_hook", ABARAX, 1.5, 0.75)
	await _stopped(KNUCKLE_BLADE, &"blade_lunge", ABARAX, 2.0, 1.7)


func test_the_slam_does_not_reach_through_a_wall_but_does_around_its_end() -> void:
	var behind: Dictionary = await _blow(KNUCKLE_HEAVY, &"heavy_slam", ABARAX, 1.5, [])
	assert_true((behind["hits"] as Array).size() > 0, "1.5 m away in the open, the slam lands")
	var walled: Dictionary = await _blow(KNUCKLE_HEAVY, &"heavy_slam", ABARAX, 1.5, _wall(0.75))
	assert_eq(walled["hits"], [], "behind the wall, nothing")
	# The wall spans x -4 to 0 here; Abarax stands beside its end, in the ring, with a clear line.
	var beside: Dictionary = await _blow(KNUCKLE_HEAVY, &"heavy_slam", ABARAX, 0.0, _wall(0.75, WALL, -1.0, -2.0), Vector3(1.2, 0, 1.2))
	assert_true((beside["hits"] as Array).size() > 0, "beside the wall's end the slam lands")


func test_a_body_that_steps_out_from_behind_the_wall_is_struck_while_the_blow_is_live() -> void:
	var out_at := Vector3(1.2, 0, 1.2)
	var step_out := func(run: Dictionary) -> void:
		var attacker: Actor = run["attacker"]
		var target: Actor = run["target"]
		if attacker.frame == 39:
			target.place(Transform3D(Basis(Vector3.UP, PI), out_at))
	var run: Dictionary = await _blow(KNUCKLE_HEAVY, &"heavy_slam", ABARAX, 1.5, _wall(0.75, WALL, -1.0, -2.0), Vector3(-0.5, 0, 1.4), step_out)
	var hits: Array = run["hits"]
	assert_eq(hits.size(), 1, "struck once, after stepping out")
	if hits.size() == 1:
		assert_true(hits[0] >= 40 and hits[0] <= 42, "on a later step of the same blow (frame %d)" % hits[0])


func test_a_low_wall_stops_the_sweep_but_not_the_palm_or_the_hook() -> void:
	var low := _wall(0.75, LOW_WALL)
	var palm: Dictionary = await _blow(ABARAX, &"palm_jab", KNUCKLE_1, 1.0, _wall(0.5, LOW_WALL))
	assert_eq((palm["hits"] as Array).slice(0, 1), [10], "the palm goes over a 0.6 m wall")
	var hook: Dictionary = await _blow(KNUCKLE_1, &"knuckle_hook", ABARAX, 1.5, low)
	var hook_open: Dictionary = await _blow(KNUCKLE_1, &"knuckle_hook", ABARAX, 1.5, [])
	assert_true((hook["hits"] as Array).size() > 0, "and so does the hook")
	assert_eq(hook["hits"], hook_open["hits"], "on the frame it lands without the wall")
	var sweep_open: Dictionary = await _blow(KNUCKLE_1, &"knuckle_sweep", ABARAX, 1.5, [])
	var sweep: Dictionary = await _blow(KNUCKLE_1, &"knuckle_sweep", ABARAX, 1.5, low)
	assert_true((sweep_open["hits"] as Array).size() > 0, "the sweep lands without the wall")
	assert_eq(sweep["hits"], [], "and not over the low wall: its hitbox is at the ankles")


func test_an_attacker_with_his_back_to_a_wall_still_hits_the_foe_before_him() -> void:
	var open: Dictionary = await _blow(ABARAX, &"palm_jab", KNUCKLE_1, 1.0, [])
	var walled: Dictionary = await _blow(ABARAX, &"palm_jab", KNUCKLE_1, 1.0, _wall(-0.4))
	assert_true((open["hits"] as Array).size() > 0, "the jab lands in the open")
	assert_eq(walled["hits"], open["hits"], "and on the same frame with a wall at his back")
	var shallow: Dictionary = await _blow(ABARAX, &"palm_jab", KNUCKLE_1, 1.0, _wall(-0.2, Vector3(4.0, 3.0, 0.8)))
	assert_eq(shallow["hits"], open["hits"], "and with a deep wall his body is half in")


# A grab begins with a blow (its hitbox's GRABBED profile), so the rule covers it: through a wall no pair starts.
func test_a_grab_does_not_take_hold_through_a_wall() -> void:
	var seen := func(run: Dictionary) -> void:
		if (run["attacker"] as Actor).paired_with != null:
			run["paired"] = true
	var open: Dictionary = await _blow(KNUCKLE_1, &"knuckle_grab", ABARAX, 1.0, [], Vector3.INF, seen)
	assert_true(open.get("paired", false), "in the open the grab takes hold")
	var walled: Dictionary = await _blow(KNUCKLE_1, &"knuckle_grab", ABARAX, 1.0, _wall(0.5), Vector3.INF, seen)
	assert_false(walled.get("paired", false), "through a wall no pair starts")
	assert_eq(walled["hits"], [], "and the foe is not even struck")
