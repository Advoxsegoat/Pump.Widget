extends TestCase
## Nothing stands about (Task 14f). Three foes on one player used to queue on one side of him: a foe who held an attack token and
## had his blow planned stood a body's width outside the others' ring, on their line, until his token timed out. The rule, as
## measurements of fights of three on a still Abarax (HP refilled each frame), 2.5 m out, SEEDS of them at once, each in its own arena:
##   1. nobody holds a token with a plan for more than HOLD_LIMIT frames without beginning his attack while within 3 m of the target;
##   2. a token is not left free for more than FREE_LIMIT frames while a ready foe within 4 m of the target holds none;
##   3. the fight has a pulse: the first attack begins within 3 s, some attack at least every 2.5 s on average, each foe's first
##      within 6 s or within 3 s of the first token free after he is ready, and no foe is passed over (a fifth of the attacks each).
## The token rule (never more than two attack at once) stands. Twenty seeds were run for the report: STAND_ABOUT_SEEDS=20.

const KINDS := ["knuckle_1", "knuckle_2", "knuckle_3", "knuckle_blade", "knuckle_drummer", "knuckle_heavy"]
const FIGHT_FRAMES := 1200
const HOLD_LIMIT := 90
const FREE_LIMIT := 60
const FIRST_OF_FIGHT := 180
const FIRST_WITHIN := 360
const AFTER_FREE := 180
const MEAN_EVERY := 150
const ANGLES := {1: [0.0], 2: [-40.0, 40.0], 3: [-60.0, 0.0, 60.0]}
## Seeds each fixture is played with by default: ones the stall was seen in (found in twenty), and one quiet one.
const SEEDS := [3, 18, 8]


static func _seeds() -> Array:
	var named := OS.get_environment("STAND_ABOUT_SEEDS")
	if named.is_valid_int():
		return range(1, int(named) + 1)
	return SEEDS


## A circling player's brain (a still one is the default Brain's silence).
class Circler extends Brain:
	var foe: Actor

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		if foe == null:
			return intent
		var to := Vector2(foe.global_position.x - actor.global_position.x, foe.global_position.z - actor.global_position.z)
		intent.face_target = foe.global_position
		if to.length() > 0.01:
			var dir := to.normalized()
			intent.move = (dir.rotated(PI * 0.5) * 0.4 + dir * clampf((to.length() - 2.0) * 0.4, -0.3, 0.6)).limit_length(0.5)
		return intent


## One fight in its own arena at `origin`: foes of `kinds` (one id each) on a still or circling Abarax. The run keeps what the
## rules measure, filled by _play.
func _fight(kinds: Array, seed_value: int, origin: Vector3, circles := false) -> Dictionary:
	var n := kinds.size()
	var arena := TestArena.make(self)
	arena.position = origin
	arena.add_child(AttackTokens.new())
	var brain: Brain = Circler.new() if circles else Brain.new()
	var a := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), brain, Vector3.ZERO, "A")
	a.place(Transform3D(Basis(Vector3.UP, 0.0), origin))
	var run := {"arena": arena, "a": a, "foes": [] as Array[Actor], "frame": 0, "seed": seed_value,
		"begins": [] as Array,  # [frame, foe index] of every attack begun (the first move of a blow after a frame of none)
		"was": [] as Array, "ready_at": [], "free_at": [], "hold": [], "hold_max": 0, "free_run": 0, "free_max": 0,
		"attacking": 0, "min_angle_frames": 0, "frames_seen": 0, "near_run": [], "near_max": 0, "toggles": [], "moving": [],
		"toggle_hist": [], "dither_frames": 0}
	for i in n:
		var def := load("res://data/actors/%s.tres" % kinds[i]) as ActorDef
		var ang := deg_to_rad(ANGLES[n][i])
		var at := Vector3(sin(ang) * 2.5, 0, cos(ang) * 2.5)
		var foe := TestArena.spawn(arena, def, EnemyBrain.new(def.brain, seed_value * 7 + i), at, "Foe%d" % (i + 1))
		foe.place(Transform3D(Basis(Vector3.UP, atan2(-at.x, -at.z)), origin + at))
		(run["foes"] as Array[Actor]).append(foe)
		for key in ["was", "ready_at", "free_at"]:
			(run[key] as Array).append(false if key == "was" else -1)
		for key in ["hold", "near_run", "toggles"]:
			(run[key] as Array).append(0)
		run["moving"].append(false)
		run["toggle_hist"].append([])
	if circles:
		(brain as Circler).foe = (run["foes"] as Array[Actor])[0]
	return run


static func _is_ready(b: EnemyBrain, foe: Actor) -> bool:
	if b.mode != EnemyBrain.Mode.ENGAGED or b.plan() != null or b._rest > 0.0 or foe.runner.busy() or b._backing:
		return false
	return b.def.attacks.any(func(o: AttackOption) -> bool: return o.weight > 0.0 and b._cooldowns.get(o, 0.0) <= 0.0)


static func _flat(from: Vector3, to: Vector3) -> Vector2:
	return Vector2(to.x - from.x, to.z - from.z)


## Plays every fight together for `frames_n` frames, keeping each rule's measurement.
func _play(runs: Array[Dictionary], frames_n: int) -> void:
	for f in frames_n:
		await frames(1)
		for run in runs:
			_observe(run)


func _observe(run: Dictionary) -> void:
	run["frame"] += 1
	var now: int = run["frame"]
	var a: Actor = run["a"]
	a.stats.refill()
	var tokens := AttackTokens.of(a)
	var foes: Array[Actor] = run["foes"]
	var attacking := 0
	var free := tokens.count(a) < AttackTokens.PER_TARGET
	var ready_waiter := false
	var angles: Array[float] = []
	for i in foes.size():
		var foe := foes[i]
		var b := foe.brain as EnemyBrain
		var is_attack := foe.runner.current != null and foe.runner.current.kind == MoveData.Kind.ATTACK
		if is_attack:
			attacking += 1
			if not run["was"][i]:
				run["begins"].append([now, i])
		run["was"][i] = is_attack
		var distance := _flat(foe.global_position, a.global_position).length()
		var holds := tokens.holds(foe)
		if run["ready_at"][i] < 0 and _is_ready(b, foe):
			run["ready_at"][i] = now
		if run["ready_at"][i] >= 0 and run["free_at"][i] < 0 and free:
			run["free_at"][i] = now
		# rule 1
		if holds and b.plan() != null and not is_attack and not foe.runner.busy() and distance <= 3.0:
			run["hold"][i] += 1
			run["hold_max"] = maxi(run["hold_max"], run["hold"][i])
		else:
			run["hold"][i] = 0
		if distance <= 4.0 and not holds and _is_ready(b, foe):
			ready_waiter = true
		angles.append(rad_to_deg(_flat(a.global_position, foe.global_position).angle()))
		# spacing: a waiter (ready for his turn, no token, not attacking) inside 1.5 m
		if not holds and not is_attack and not foe.runner.busy() and b.mode == EnemyBrain.Mode.ENGAGED and b._rest <= 0.0 and distance < 1.5:
			run["near_run"][i] += 1
			run["near_max"] = maxi(run["near_max"], run["near_run"][i])
		else:
			run["near_run"][i] = 0
		# stickiness: moving/still toggles in the last second
		var moving := foe.locomotion.speed > 0.3
		var hist: Array = run["toggle_hist"][i]
		hist.append(1 if moving != run["moving"][i] else 0)
		if hist.size() > 60:
			hist.pop_front()
		run["moving"][i] = moving
	run["attacking"] = maxi(run["attacking"], attacking)
	run["free_run"] = run["free_run"] + 1 if free and ready_waiter else 0
	run["free_max"] = maxi(run["free_max"], run["free_run"])
	# the dithering: more than four toggles a second held for a second (60 frames of windows over the limit)
	var worst := 0
	for i in foes.size():
		worst = maxi(worst, (run["toggle_hist"][i] as Array).reduce(func(s: int, x: int) -> int: return s + x, 0))
	run["dither_run"] = run.get("dither_run", 0) + 1 if worst > 4 else 0
	run["dither_max"] = maxi(run.get("dither_max", 0), run["dither_run"])
	if now > 180 and foes.size() == 3:
		run["frames_seen"] += 1
		var smallest := 360.0
		for i in 3:
			for j in range(i + 1, 3):
				var d := absf(fposmod(angles[i] - angles[j] + 180.0, 360.0) - 180.0)
				smallest = minf(smallest, d)
		if smallest > 40.0:
			run["min_angle_frames"] += 1


func _free(runs: Array[Dictionary]) -> void:
	for run in runs:
		(run["arena"] as Node).free()


## Plays `kinds` (three) for the seeds, returns the rules' numbers worst over the seeds:
## {hold: longest frames a token and a plan went unused, free: longest a token lay free with a ready foe, first: first attack of a
## fight (latest), slow: foes whose first attack was late by rule 3, mean: fewest attacks begun in a fight, pass: least share of a
## foe (of the attacks begun), attacking: most at once, bad: [[seed, ...]]}.
func _measure(kinds: Array, seeds: Array) -> Dictionary:
	var runs: Array[Dictionary] = []
	for i in seeds.size():
		runs.append(_fight(kinds, seeds[i], Vector3(i * 50.0, 0, 0)))
	await _play(runs, FIGHT_FRAMES)
	var r := {"hold": 0, "free": 0, "first": 0, "slow": 0, "fewest": 9999, "share": 1.0, "attacking": 0, "bad": [], "fights": seeds.size()}
	for run in runs:
		r["hold"] = maxi(r["hold"], run["hold_max"])
		r["free"] = maxi(r["free"], run["free_max"])
		r["attacking"] = maxi(r["attacking"], run["attacking"])
		var begins: Array = run["begins"]
		r["first"] = maxi(r["first"], begins[0][0] if not begins.is_empty() else 9999)
		r["fewest"] = mini(r["fewest"], begins.size())
		for i in kinds.size():
			var mine: Array = begins.filter(func(x: Array) -> bool: return x[1] == i)
			var first: int = mine[0][0] if not mine.is_empty() else 9999
			var allowed: int = FIRST_WITHIN
			if run["free_at"][i] >= 0:
				allowed = maxi(allowed, run["free_at"][i] + AFTER_FREE)
			if first > allowed:
				r["slow"] += 1
				r["bad"].append([run["seed"], i, first, allowed])
			if not begins.is_empty():
				r["share"] = minf(r["share"], float(mine.size()) / begins.size())
	_free(runs)
	if OS.get_environment("STAND_ABOUT_SEEDS") != "":
		print("stand about %s, %d seeds: %s" % [kinds, seeds.size(), r])
	return r


func _check(kinds: Array) -> void:
	var seeds := _seeds()
	var m: Dictionary = await _measure(kinds, seeds)
	var shown := "%s (seeds %s)" % [kinds, seeds]
	assert_true(m["hold"] <= HOLD_LIMIT, "%s: nobody holds a token and a plan for more than %d frames without attacking (longest %d)" % [shown, HOLD_LIMIT, m["hold"]])
	assert_true(m["free"] <= FREE_LIMIT, "%s: no token lies free for more than %d frames while a ready foe holds none (longest %d)" % [shown, FREE_LIMIT, m["free"]])
	assert_true(m["first"] <= FIRST_OF_FIGHT, "%s: the first attack begins within 3 s (latest at frame %d)" % [shown, m["first"]])
	assert_eq(m["slow"], 0, "%s: every foe's first attack comes within 6 s or 3 s of the first free token (late: %s)" % [shown, m["bad"]])
	assert_true(m["fewest"] >= FIGHT_FRAMES / MEAN_EVERY, "%s: some attack begins at least every 2.5 s (fewest in a fight: %d, wanted %d)" % [shown, m["fewest"], FIGHT_FRAMES / MEAN_EVERY])
	assert_true(m["share"] >= 0.2, "%s: no foe is passed over (least share of the attacks begun: %.2f)" % [shown, m["share"]])
	assert_true(m["attacking"] <= 2, "%s: never more than two attack at once (%d did)" % [shown, m["attacking"]])


func test_three_tier_ones() -> void:
	await _check(["knuckle_1", "knuckle_1", "knuckle_1"])


func test_three_tier_twos() -> void:
	await _check(["knuckle_2", "knuckle_2", "knuckle_2"])


func test_three_tier_threes() -> void:
	await _check(["knuckle_3", "knuckle_3", "knuckle_3"])


func test_three_blades() -> void:
	await _check(["knuckle_blade", "knuckle_blade", "knuckle_blade"])


func test_three_drummers() -> void:
	await _check(["knuckle_drummer", "knuckle_drummer", "knuckle_drummer"])


func test_three_heavies() -> void:
	await _check(["knuckle_heavy", "knuckle_heavy", "knuckle_heavy"])


func test_two_tier_ones_and_a_drummer() -> void:
	await _check(["knuckle_1", "knuckle_1", "knuckle_drummer"])


func test_a_heavy_and_two_tier_ones() -> void:
	await _check(["knuckle_heavy", "knuckle_1", "knuckle_1"])


## Spacing and stickiness, three tier I on a still Abarax for 20 s: spread round him (the smallest angle between two foes, from him,
## over 40 degrees on 80% of the frames after the first 3 s), no waiter inside 1.5 m for more than 30 frames at a stretch, and no
## foe dithering between moving and still (more than four toggles a second for more than a second).
func test_three_foes_spread_round_the_player_and_do_not_dither() -> void:
	var runs: Array[Dictionary] = []
	var seeds := _seeds()
	for i in seeds.size():
		runs.append(_fight(["knuckle_1", "knuckle_1", "knuckle_1"], seeds[i], Vector3(i * 50.0, 0, 0)))
	await _play(runs, FIGHT_FRAMES)
	var least := 1.0
	var near := 0
	var dither := 0
	for run in runs:
		least = minf(least, float(run["min_angle_frames"]) / maxf(run["frames_seen"], 1))
		near = maxi(near, run["near_max"])
		dither = maxi(dither, run.get("dither_max", 0))
	_free(runs)
	assert_true(least >= 0.8, "the smallest angle between two foes is over 40 degrees on at least 80%% of the frames (worst fight %.2f)" % least)
	assert_true(near <= 30, "no waiter stands inside 1.5 m for more than 30 frames at a stretch (longest %d)" % near)
	assert_true(dither <= 60, "no foe toggles between moving and still more than four times a second for more than a second (longest %d frames)" % dither)


## One foe alone: the same moves on the same frames as before the fix (every kind, a still and a circling Abarax, SIGNATURE_SEEDS seeds).
const SIGNATURE_SEEDS := 5
const SIGNATURE_FRAMES := 900
const SIGNATURE_KINDS := ["knuckle_1", "knuckle_3", "knuckle_blade", "knuckle_drummer", "knuckle_heavy"]
const ONE_FOE_SIGNATURE := 2644839554


func test_one_foe_alone_plays_as_before() -> void:
	var runs: Array[Dictionary] = []
	var seen: Array = []
	var k := 0
	for kind in SIGNATURE_KINDS:
		for circles in [false, true]:
			for s in SIGNATURE_SEEDS:
				var run := _fight([kind], s + 1, Vector3(k * 50.0, 0, 0), circles)
				var log := []
				seen.append(log)
				for foe: Actor in run["foes"]:
					foe.runner.move_started.connect(func(m: MoveData) -> void: log.append([run["frame"], foe.name, m.id]))
				runs.append(run)
				k += 1
	await _play(runs, SIGNATURE_FRAMES)
	_free(runs)
	var moves := 0
	for log: Array in seen:
		moves += log.size()
	assert_true(moves > 100, "they fought (%d moves)" % moves)
	assert_eq(str(seen).hash(), ONE_FOE_SIGNATURE, "one foe alone plays the same moves on the same frames as before (%d moves)" % moves)
