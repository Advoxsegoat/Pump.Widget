extends TestCase
## A foe's way round stays on the ground (Task 15c, fix round 1). The first planner looked at walls and not at the floor: a way round that
## went past the floor's edge went into the void, and three foes walked off it and fell without end (y reached -1,006 in the review's probe;
## never on the base). A cell is free now only where a ray down from knee height meets the world within STEP_DOWN (0.5 m: a kerb or a
## stair a body steps down, where more is a drop, not a way); a straight leg of the way is looked at along its length.
##
## The floor is the test arena's 40 m square (x and z from -20 to 20, its top at y = 0); the fights are FAR apart so that no floor touches another.
##   edge   a wall 40 m long from edge to edge of the floor, the player 0.7 m behind it at x = 16 and three foes 2.3 m in front: the nearest end
##          of the wall is out in the void and the other is 37 m away. No way round exists on the floor: they wait.
##   long   a wall 10 m long from x = 10 to the edge of the floor (x = 20), the same fight at x = 16: the way round the void end is 4 m, the way
##          round the other end 6 m. They go the long way and fight. What is held is the way round: a foe's height until he first has a line
##          (once he fights, the circling and spacing of the ordinary brain know no edge, here 3 m away: that is not the planner's).

const FAR := 60.0
const SEEDS := 10
const FRAMES := 1800
## A body steps down this far (m): lower than the floor by more than that is falling.
const STEP := 0.5


func _fight(place: String, seed_value: int, origin: Vector3) -> Dictionary:
	var arena := TestArena.make(self)
	arena.position = origin
	arena.add_child(AttackTokens.new())
	match place:
		"edge":
			TestArena.wall(arena, Vector3(0, 1.5, 0), Vector3(40, 3, 0.2))
		"long":
			TestArena.wall(arena, Vector3(15, 1.5, 0), Vector3(10, 3, 0.2))
	var player_at := Vector3(16, 0, 0.7)
	var player := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 1000.0), Brain.new(), player_at, "A")
	player.place(Transform3D(Basis(Vector3.UP, PI), origin + player_at))
	var run := {"arena": arena, "player": player, "foes": [] as Array[Actor], "lowest": 0.0, "line_at": [], "swings": 0, "was": [], "lowest_going": 0.0}
	for i in 3:
		var def := load("res://data/actors/knuckle_1.tres") as ActorDef
		var at := Vector3(15.0 + i, 0, -2.3 - (i % 2) * 0.3)
		var brain := EnemyBrain.new(def.brain, seed_value * 7 + i)
		var foe := TestArena.spawn(arena, def, brain, at, "Foe%d" % (i + 1))
		foe.place(Transform3D(Basis(Vector3.UP, atan2(-(player_at.x - at.x), -(player_at.z - at.z))), origin + at))
		brain.target = player
		brain.mode = EnemyBrain.Mode.ENGAGED
		brain._engage(foe)
		(run["foes"] as Array[Actor]).append(foe)
		run["line_at"].append(-1)
		run["was"].append(false)
	return run


func _observe(run: Dictionary, frame: int) -> void:
	var player: Actor = run["player"]
	player.stats.refill()
	for i in (run["foes"] as Array).size():
		var foe: Actor = run["foes"][i]
		run["lowest"] = minf(run["lowest"], foe.global_position.y)
		if run["line_at"][i] < 0:
			run["lowest_going"] = minf(run["lowest_going"], foe.global_position.y)
		var ray := PhysicsRayQueryParameters3D.create(foe.global_position + Vector3.UP * 1.1, player.global_position + Vector3.UP * 1.1, Layers.WORLD, [foe.get_rid(), player.get_rid()])
		if run["line_at"][i] < 0 and foe.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			run["line_at"][i] = frame
		var attacking := foe.runner.current != null and foe.runner.current.kind == MoveData.Kind.ATTACK
		if attacking and not run["was"][i]:
			run["swings"] += 1
		run["was"][i] = attacking


func _play(place: String) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for s in SEEDS:
		runs.append(_fight(place, s + 1, Vector3(s * FAR, 0, 0)))
	for f in FRAMES:
		await frames(1)
		for run in runs:
			_observe(run, f)
	for node in Sfx.playing_nodes():
		node.stop()
	OS.delay_msec(150)
	var kept: Array[Dictionary] = []
	for run in runs:
		kept.append({"lowest": run["lowest"], "lowest_going": run["lowest_going"], "line_at": run["line_at"], "swings": run["swings"],
				"ends": (run["foes"] as Array).map(func(a: Actor) -> Vector3: return a.global_position - (run["arena"] as Node3D).position)})
		(run["arena"] as Node).free()
	return kept


func _lowest(runs: Array[Dictionary], key := "lowest") -> float:
	var lowest := 0.0
	for run in runs:
		lowest = minf(lowest, run[key])
	return lowest


func test_no_foe_walks_off_the_floors_edge_round_a_wall_that_ends_in_the_void() -> void:
	var runs := await _play("edge")
	var report := OS.get_environment("FOE_GROUND_REPORT")
	if report != "":
		var f := FileAccess.open(report, FileAccess.WRITE)
		f.store_string("edge: lowest y %.2f; ends of seed 1: %s\n" % [_lowest(runs), runs[0]["ends"]])
		f.close()
	assert_true(_lowest(runs) > -STEP, "no foe's y goes below the floor by more than a step (%.1f m) in %d frames, %d seeds (lowest %.2f)" % [STEP, FRAMES, SEEDS, _lowest(runs)])


func test_where_the_short_way_round_is_over_the_edge_they_take_the_long_way() -> void:
	var runs := await _play("long")
	var late := 0
	var swings := 0
	var report := OS.get_environment("FOE_GROUND_REPORT")
	if report != "":
		var f := FileAccess.open(report, FileAccess.READ_WRITE) if FileAccess.file_exists(report) else FileAccess.open(report, FileAccess.WRITE)
		f.seek_end()
		f.store_string("long: lowest y %.2f (going round %.2f); line at (seed 1) %s; swings %d; ends of seed 1: %s\n" % [_lowest(runs), _lowest(runs, "lowest_going"), runs[0]["line_at"], runs[0]["swings"], runs[0]["ends"]])
		f.close()
	var which := []
	for run in runs:
		swings += run["swings"]
		for at: int in run["line_at"]:
			late += 1 if at < 0 or at > 900 else 0
		which.append(run["line_at"])
	assert_true(_lowest(runs, "lowest_going") > -STEP, "no foe falls on his way round (lowest y %.2f)" % _lowest(runs, "lowest_going"))
	assert_eq(late, 0, "every foe has a line to the player within 15 s: they went round the far end (%s)" % [which])
	assert_true(swings > 0, "they fight (%d swings)" % swings)
