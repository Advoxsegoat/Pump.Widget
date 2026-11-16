extends TestCase
## A foe does not swing at a wall (Task 15c). Task 15b made the world stop a blow; the foes did not know it: three Knuckles at a player
## 0.7 m behind a short wall swung 39 to 44 times in a fight and none landed. The rule: a foe begins an attack only when the line the
## scanner will ask about is clear (HitScanner.line_clear), and when it is not he goes round to where it is; in the open he plays as he did.
##
## The places are small: the test arena's floor and walls 0.2 m thick (3 m high unless said, 1 m, 3 m and 6 m long; a 0.6 m low wall; a post
## 0.4 m across; a doorway 1.2 m wide in a long wall). They are plain boxes without the Bilibara stretch's `deflects` mark: the walls
## do not carry a body along them, so what the foes do here is the brain's own way round. The player (Abarax, HP refilled each frame, too
## much poise to flinch) stands still on the far side; the foes are engaged with him from the first frame (a foe who has not noticed him
## does not come: see the report), and each fight is in its own arena, FAR apart.
##
## What is measured of a foe is his own: a swing is begun on the first frame an attack move plays; it has "no line" when a world ray
## from his chest (1.1 m up) to the player's chest, or at his hand's height (0.72 m), is cut (a low move's own ray is at 0.45 m: over a
## kerb, under a low wall); standing is a foe within 3 m of the player, with no line, going slower than STILL_SPEED.

const ABARAX := "res://data/actors/abarax.tres"
const KINDS := ["knuckle_1", "knuckle_1", "knuckle_1"]
## Metres between the arenas of two fights.
const FAR := 40.0
const SEEDS := 10
const STILL_SPEED := 0.3
const STILL_LIMIT := 60
## Where the foes start in the walled places: (x, z) in metres, the wall's middle at the origin, the player behind it at +z.
const FOES_AT := [Vector2(-1.2, -2.3), Vector2(0.0, -2.6), Vector2(1.2, -2.3)]
const PLAYER_AT := Vector3(0.0, 0.0, 0.7)
const HAND := 0.72
const LOW_LINE := 0.45


## The walls of a place: [centre, size] for each.
static func _walls(place: String) -> Array:
	match place:
		"wall1":
			return [[Vector3(0, 1.5, 0), Vector3(1, 3, 0.2)]]
		"wall3":
			return [[Vector3(0, 1.5, 0), Vector3(3, 3, 0.2)]]
		"wall6":
			return [[Vector3(0, 1.5, 0), Vector3(6, 3, 0.2)]]
		"low":
			return [[Vector3(0, 0.3, 0), Vector3(6, 0.6, 0.2)]]
		"kerb":
			return [[Vector3(0, 0.15, 0), Vector3(6, 0.3, 0.2)]]
		"counter":  # the review's own case: a counter 1.0 m high across a 5 m lane (the foes see over it)
			return [[Vector3(0, 0.5, 0), Vector3(5, 1.0, 0.2)]]
		"post":
			return [[Vector3(0, 1.5, 0), Vector3(0.4, 3, 0.4)]]
		"end":  # a wall 6 m long that ends at x = 0
			return [[Vector3(-3, 1.5, 0), Vector3(6, 3, 0.2)]]
		"door":  # a doorway 1.2 m wide in a long wall
			return [[Vector3(-5.6, 1.5, 0), Vector3(10, 3, 0.2)], [Vector3(5.6, 1.5, 0), Vector3(10, 3, 0.2)]]
	return []


## One fight in an arena of its own at `origin`: `n` Knuckle_1 on a still Abarax behind the place's walls. `engaged`: the foes start
## engaged (else they have to notice him).
func _fight(place: String, seed_value: int, origin: Vector3, n := 3, engaged := true, player_at := PLAYER_AT, foes_at: Array = FOES_AT) -> Dictionary:
	var arena := TestArena.make(self)
	arena.position = origin
	arena.add_child(AttackTokens.new())
	for w: Array in _walls(place):
		TestArena.wall(arena, w[0], w[1])
	var pdef := Duel.def(ActorDef.Team.PLAYER, 1000.0)
	var player := TestArena.spawn(arena, pdef, Brain.new(), player_at, "A")
	player.place(Transform3D(Basis(Vector3.UP, PI), origin + player_at))
	var run := {"arena": arena, "player": player, "foes": [] as Array[Actor], "seed": seed_value, "frame": 0, "origin": origin,
		"swings": [] as Array, "no_line": [] as Array, "landed": 0, "first": [] as Array, "line_at": [] as Array, "still": [] as Array, "still_max": 0,
		"was": [] as Array, "last_at": [] as Array, "door": 0, "door_max": 0, "swing_moves": [] as Array}
	for i in n:
		var def := load("res://data/actors/%s.tres" % KINDS[i % KINDS.size()]) as ActorDef
		var xz: Vector2 = foes_at[i]
		var at := Vector3(xz.x, 0, xz.y)
		var brain := EnemyBrain.new(def.brain, seed_value * 7 + i)
		var foe := TestArena.spawn(arena, def, brain, at, "Foe%d" % (i + 1))
		foe.place(Transform3D(Basis(Vector3.UP, atan2(-(player_at.x - at.x), -(player_at.z - at.z))), origin + at))
		if engaged:
			brain.target = player
			brain.mode = EnemyBrain.Mode.ENGAGED
			brain._engage(foe)
		(run["foes"] as Array[Actor]).append(foe)
		run["first"].append(-1)
		run["line_at"].append(-1)
		run["still"].append(0)
		run["was"].append(false)
		run["last_at"].append(foe.global_position)
	player.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
		if r.outcome != HitResult.Outcome.WHIFF:
			run["landed"] += 1)
	return run


## Whether the world cuts the line from `foe`'s chest to the player's at `height` (m) of each (the test's own cast: a second copy of the
## rule is what lets the test catch the brain's one).
static func _cut(foe: Actor, player: Actor, height: float) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(foe.global_position + Vector3.UP * height, player.global_position + Vector3.UP * height, Layers.WORLD, [foe.get_rid(), player.get_rid()])
	return not foe.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


static func _no_line(foe: Actor, player: Actor, low := false) -> bool:
	if _cut(foe, player, 1.1):
		return true
	return _cut(foe, player, LOW_LINE) if low else _cut(foe, player, HAND)


func _observe(run: Dictionary) -> void:
	run["frame"] += 1
	var now: int = run["frame"]
	var player: Actor = run["player"]
	player.stats.refill()
	var foes: Array[Actor] = run["foes"]
	var in_door := 0
	for i in foes.size():
		var foe := foes[i]
		var attacking := foe.runner.current != null and foe.runner.current.kind == MoveData.Kind.ATTACK
		var low := false
		if attacking and foe.runner.current != null:
			for p in foe.runner.current.hits.values():
				low = low or (p as HitProfile).height == HitProfile.Height.LOW
		if attacking and not run["was"][i]:
			run["swings"].append([now, i, foe.runner.current.id])
			if run["first"][i] < 0:
				run["first"][i] = now
			if _no_line(foe, player, low):
				run["no_line"].append([now, i, foe.runner.current.id])
		run["was"][i] = attacking
		var no_line := _no_line(foe, player)
		if not no_line and run["line_at"][i] < 0:
			run["line_at"][i] = now
		var speed := Vector2(foe.global_position.x - run["last_at"][i].x, foe.global_position.z - run["last_at"][i].z).length() * 60.0
		run["last_at"][i] = foe.global_position
		var near := Vector2(foe.global_position.x - player.global_position.x, foe.global_position.z - player.global_position.z).length() <= 3.0
		if near and no_line and speed < STILL_SPEED and not foe.runner.busy():
			run["still"][i] += 1
			run["still_max"] = maxi(run["still_max"], run["still"][i])
		else:
			run["still"][i] = 0
		if absf(foe.global_position.z) < 0.2 and absf(foe.global_position.x - run["origin"].x) < 0.6:
			in_door += 1
	run["door"] = in_door
	run["door_max"] = maxi(run["door_max"], in_door)


## Plays the fights together for `frames_n` frames.
func _play(runs: Array[Dictionary], frames_n: int) -> void:
	for f in frames_n:
		await frames(1)
		for run in runs:
			_observe(run)


func _free(runs: Array[Dictionary]) -> void:
	for node in Sfx.playing_nodes():
		node.stop()  # a blow's sound still playing when the run ends is reported as a leak
	OS.delay_msec(150)
	for run in runs:
		if is_instance_valid(run["arena"]):
			(run["arena"] as Node).free()


## `seeds` fights of `place`, played `frames_n` frames: the runs (freed).
func _fights(place: String, seeds: int, frames_n: int, n := 3, engaged := true, player_at := PLAYER_AT, foes_at: Array = FOES_AT) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for s in seeds:
		runs.append(_fight(place, s + 1, Vector3(s * FAR, 0, 0), n, engaged, player_at, foes_at))
	await _play(runs, frames_n)
	_free(runs)
	return runs


static func _sum(runs: Array[Dictionary], key: String) -> int:
	var total := 0
	for run in runs:
		total += (run[key] as Array).size() if run[key] is Array else int(run[key])
	return total


static func _worst(runs: Array[Dictionary], key: String) -> int:
	var worst := 0
	for run in runs:
		worst = maxi(worst, run[key])
	return worst


## The frame by which every foe of every run had a line (9999 if one never did) and the latest first attack (9999 if a foe never attacked).
static func _slowest(runs: Array[Dictionary], key: String) -> int:
	var slowest := 0
	for run in runs:
		for at: int in run[key]:
			slowest = maxi(slowest, 9999 if at < 0 else at)
	return slowest


func _names(swings: Array) -> Array:
	return swings.map(func(x: Array) -> StringName: return x[2])


func test_three_foes_do_not_swing_at_a_one_metre_wall_and_come_round_it() -> void:
	# The reviewer's case, ten seeds, 1,800 frames: today 20 swings begun with no line and 413 blows landed.
	var runs: Array[Dictionary] = await _fights("wall1", SEEDS, 1800)
	assert_eq(_sum(runs, "no_line"), 0, "no swing is begun with no line (today 20 of %d)" % _sum(runs, "swings"))
	assert_true(_sum(runs, "landed") > 413, "more blows land than today's 413 (%d): he comes round" % _sum(runs, "landed"))


func test_foes_come_round_a_three_and_a_six_metre_wall() -> void:
	for place in ["wall3", "wall6"]:
		var runs: Array[Dictionary] = await _fights(place, 4, 700)
		assert_true(_slowest(runs, "line_at") <= 360, "%s: every foe has a line to the player within 6 s (latest frame %d)" % [place, _slowest(runs, "line_at")])
		assert_true(_slowest(runs, "first") <= 600, "%s: every foe has attacked within 10 s (latest frame %d)" % [place, _slowest(runs, "first")])
		assert_eq(_sum(runs, "no_line"), 0, "%s: no swing with no line" % place)
		assert_true(_worst(runs, "still_max") <= STILL_LIMIT, "%s: no foe with no line stands still more than %d frames (%d)" % [place, STILL_LIMIT, _worst(runs, "still_max")])


func test_one_foe_at_a_time_comes_through_a_doorway_and_nobody_swings_at_the_frame() -> void:
	var runs: Array[Dictionary] = await _fights("door", 4, 900, 3, true, Vector3(0, 0, 2.0), [Vector2(-1.2, -2.6), Vector2(0.0, -3.0), Vector2(1.2, -2.6)])
	assert_eq(_sum(runs, "no_line"), 0, "nobody swings with no line (at the door's frame)")
	assert_true(_sum(runs, "swings") > 0, "they attack (%d swings)" % _sum(runs, "swings"))
	assert_true(_worst(runs, "door_max") <= 1, "never two in the doorway at once (%d)" % _worst(runs, "door_max"))
	assert_true(_slowest(runs, "first") <= 600, "every foe attacks within 10 s (%d)" % _slowest(runs, "first"))


func test_a_foe_steps_round_a_post_and_attacks_within_two_seconds() -> void:
	var runs: Array[Dictionary] = await _fights("post", 6, 300, 1, true, Vector3(0, 0, 1.0), [Vector2(0.0, -1.5)])
	assert_eq(_sum(runs, "no_line"), 0, "no swing at the post")
	assert_true(_slowest(runs, "first") <= 120, "he attacks within 2 s (latest frame %d)" % _slowest(runs, "first"))


func test_palms_and_hooks_go_over_a_low_wall_and_no_sweep_is_chosen_across_it() -> void:
	var runs: Array[Dictionary] = await _fights("low", 4, 900)
	var swings: Array = []
	for run in runs:
		swings.append_array(run["swings"])
	var sweeps := _names(swings).filter(func(n: StringName) -> bool: return n == &"knuckle_sweep")
	assert_true(_sum(runs, "landed") > 0, "blows land over the low wall (%d)" % _sum(runs, "landed"))
	assert_true(_names(swings).any(func(n: StringName) -> bool: return n == &"knuckle_jab"), "the palm is thrown over it")
	assert_eq(sweeps.size(), 0, "no sweep is thrown across it (12 of them today)")
	assert_eq(_sum(runs, "no_line"), 0, "no swing with no line")


func test_a_wind_up_already_begun_finishes_when_the_player_steps_behind_a_wall_and_the_next_waits_for_a_line() -> void:
	# A committed blow is not cancelled (the foe has begun; the world will stop it, as it always could): only the NEXT attack waits.
	var run := _fight("end", 1, Vector3.ZERO, 1, true, Vector3(1.0, 0, -1.3), [Vector2(1.0, -2.8)])
	var player: Actor = run["player"]
	var foe: Actor = (run["foes"] as Array)[0]
	var stepped := -1
	var still_busy := true
	var after_swings := 0
	for i in 900:
		await frames(1)
		_observe(run)
		if stepped < 0 and (run["swings"] as Array).size() > 0:
			stepped = i
			player.place(Transform3D(Basis(Vector3.UP, PI), Vector3(-1.0, 0, 0.7)))
			run["swings"].clear()
			run["no_line"].clear()
		if stepped >= 0 and i > stepped and i < stepped + 8 and not foe.runner.busy():
			still_busy = false
	var arena: Node = run["arena"]
	arena.free()
	assert_true(stepped >= 0, "he began a swing")
	assert_true(still_busy, "the wind-up he had begun plays on for 8 frames after the player stepped behind the wall")
	assert_eq((run["no_line"] as Array).size(), 0, "no later swing is begun with no line")
	assert_true((run["swings"] as Array).size() > 0, "he comes round and attacks again (%d swings)" % (run["swings"] as Array).size())


func test_survey_for_the_report() -> void:
	# Not a rule: prints the table of swings (begun with no line, landed, first attack, line) for the report, BEFORE and AFTER.
	if OS.get_environment("FOE_WALLS_SURVEY") == "":
		return
	var out := ""
	var places := OS.get_environment("FOE_WALLS_PLACES").split(",") if OS.get_environment("FOE_WALLS_PLACES") != "" else PackedStringArray(["wall1", "wall3", "wall6", "low", "kerb", "counter", "post", "door"])
	for place in places:
		var runs: Array[Dictionary] = await _fights(place, SEEDS, 1800, 3, place != "counter", PLAYER_AT if place != "post" else Vector3(0, 0, 1.0))
		var names := {}
		for run in runs:
			for x: Array in run["no_line"]:
				names[x[2]] = names.get(x[2], 0) + 1
		out += "  no-line moves %s\n" % [names]
		out += "%s: swings %d, no line %d, landed %d, last first-attack %d, last first-line %d, still %d, door_max %d\n" % [place, _sum(runs, "swings"), _sum(runs, "no_line"),
				_sum(runs, "landed"), _slowest(runs, "first"), _slowest(runs, "line_at"), _worst(runs, "still_max"), _worst(runs, "door_max")]
	var f := FileAccess.open(OS.get_environment("FOE_WALLS_SURVEY"), FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print(out)
	assert_true(true)
