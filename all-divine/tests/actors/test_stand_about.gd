extends TestCase
## Nothing stands about (Task 14f): a foe who holds an attack token and has his blow planned throws it, or gives his turn to
## someone who can. Before, with three foes on one player, the one who held a token queued behind a neighbour who stood in
## range and swung, could not get near enough to throw, and held the token (and one of the target's two) until its timeout:
## the third foe could not attack either, and a foe could go fourteen seconds without a blow.
##
## The fights are FOES foes of one kind on a still Abarax (HP refilled every frame), 2.5 m out at angles round him, FIGHT_FRAMES
## long, SEEDS of them at once each in its own arena (twenty were run for the report: STAND_ABOUT_SEEDS=20).

const ABARAX_POISE := 5.0
const KINDS := ["knuckle_1", "knuckle_2", "knuckle_3", "knuckle_blade", "knuckle_drummer", "knuckle_heavy"]
const FIGHT_FRAMES := 1200
## Six seconds and eight seconds, in frames.
const FIRST_WITHIN := 360
const GAP_WITHIN := 480
## Some attack begins at least this often (frames) on average with three foes.
const MEAN_EVERY := 150
const ANGLES := {1: [0.0], 2: [-40.0, 40.0], 3: [-60.0, 0.0, 60.0]}


## The seeds each kind is played with: ones where, before the fix, a foe began late or waited too long (found in twenty), and a
## quiet one or two.
const SEEDS := {
	"knuckle_1": [1, 2], "knuckle_2": [20, 1], "knuckle_3": [19, 11, 1], "knuckle_blade": [3, 1],
	"knuckle_drummer": [18, 8, 4, 13], "knuckle_heavy": [1, 2],
}


static func _seeds(kind: String) -> Array:
	var named := OS.get_environment("STAND_ABOUT_SEEDS")
	if named.is_valid_int():
		return range(1, int(named) + 1)
	return SEEDS[kind]


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


## One fight in its own arena at `origin`: {arena, a, foes, starts, attacking}. `starts` is [[frame, foe index]] of every attack
## move started, `attacking` the most foes in an attack move at once, kept by `_watch`.
func _fight(def_id: String, n: int, seed_value: int, origin: Vector3, circles := false) -> Dictionary:
	var arena := TestArena.make(self)
	arena.position = origin
	arena.add_child(AttackTokens.new())
	var brain: Brain = Circler.new() if circles else Brain.new()
	var a := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, ABARAX_POISE), brain, Vector3.ZERO, "A")
	a.place(Transform3D(Basis(Vector3.UP, 0.0), origin))
	var run := {"arena": arena, "a": a, "foes": [] as Array[Actor], "starts": [], "attacking": 0, "frame": 0, "seed": seed_value}
	for i in n:
		var def := load("res://data/actors/%s.tres" % def_id) as ActorDef
		var ang := deg_to_rad(ANGLES[n][i])
		var at := Vector3(sin(ang) * 2.5, 0, cos(ang) * 2.5)
		var foe := TestArena.spawn(arena, def, EnemyBrain.new(def.brain, seed_value * 7 + i), at, "Foe%d" % (i + 1))
		foe.place(Transform3D(Basis(Vector3.UP, atan2(-at.x, -at.z)), origin + at))
		(run["foes"] as Array[Actor]).append(foe)
		var index := i
		foe.runner.move_started.connect(func(m: MoveData) -> void:
			if m.kind == MoveData.Kind.ATTACK:
				run["starts"].append([run["frame"], index]))
	if circles:
		(brain as Circler).foe = (run["foes"] as Array[Actor])[0]
	return run


## Plays every fight in `runs` together for `frames_n` frames, refilling each player and noting the most foes attacking at once.
func _play(runs: Array[Dictionary], frames_n: int) -> void:
	for f in frames_n:
		await frames(1)
		for run in runs:
			run["frame"] += 1
			(run["a"] as Actor).stats.refill()
			var now := 0
			for foe: Actor in run["foes"]:
				if foe.runner.current != null and foe.runner.current.kind == MoveData.Kind.ATTACK:
					now += 1
			run["attacking"] = maxi(run["attacking"], now)


## {late: how many foes began their first attack after FIRST_WITHIN (or never), first: the latest first attack (9999: never),
## gap: the longest wait between one foe's attacks, to the fight's end too, starts: attack moves started in all, attacking: the most
## at once in any fight, fights}.
func _measure(def_id: String, n: int, seeds: Array) -> Dictionary:
	var runs: Array[Dictionary] = []
	for i in seeds.size():
		runs.append(_fight(def_id, n, seeds[i], Vector3(i * 50.0, 0, 0)))
	await _play(runs, FIGHT_FRAMES)
	var result := {"late": 0, "first": 0, "gap": 0, "starts": 0, "attacking": 0, "fights": seeds.size(), "foes": 0, "bad": []}
	for run in runs:
		result["attacking"] = maxi(result["attacking"], run["attacking"])
		result["starts"] += (run["starts"] as Array).size()
		for i in n:
			var mine: Array = (run["starts"] as Array).filter(func(s: Array) -> bool: return s[1] == i).map(func(s: Array) -> int: return s[0])
			var first: int = mine[0] if not mine.is_empty() else 9999
			result["foes"] += 1
			result["first"] = maxi(result["first"], first)
			if first > FIRST_WITHIN:
				result["late"] += 1
			var last := 0
			var longest := 0
			for frame: int in mine:
				longest = maxi(longest, frame - last)
				last = frame
			longest = maxi(longest, FIGHT_FRAMES - last)
			result["gap"] = maxi(result["gap"], longest)
			if first > FIRST_WITHIN or longest > GAP_WITHIN:
				result["bad"].append([run["seed"], i, first, longest])
	for run in runs:
		(run["arena"] as Node).free()
	if OS.get_environment("STAND_ABOUT_SEEDS") != "":
		print("stand about, %s x%d, seeds %s: %s" % [def_id, n, seeds, result])
	return result


func _check_kind(def_id: String) -> void:
	var seeds := _seeds(def_id)
	var m: Dictionary = await _measure(def_id, 3, seeds)
	var shown := "%s x3, %d fights (seeds %s)" % [def_id, seeds.size(), seeds]
	assert_eq(m["late"], 0, "%s: every foe begins an attack within 6 s (%d of %d did not; the latest first attack at frame %d)" % [shown, m["late"], m["foes"], m["first"]])
	assert_true(m["gap"] <= GAP_WITHIN, "%s: no foe goes longer than 8 s between his attacks (longest %d frames)" % [shown, m["gap"]])
	var per_fight := float(m["starts"]) / seeds.size()
	assert_true(per_fight >= float(FIGHT_FRAMES) / MEAN_EVERY, "%s: some attack begins at least every 2.5 s on average (%.1f attacks a fight, %.1f wanted)" % [shown, per_fight, float(FIGHT_FRAMES) / MEAN_EVERY])
	assert_true(m["attacking"] <= 2, "%s: never more than two attack at once (%d did)" % [shown, m["attacking"]])


func test_three_tier_ones_all_attack() -> void:
	await _check_kind("knuckle_1")


func test_three_tier_twos_all_attack() -> void:
	await _check_kind("knuckle_2")


func test_three_tier_threes_all_attack() -> void:
	await _check_kind("knuckle_3")


func test_three_blades_all_attack() -> void:
	await _check_kind("knuckle_blade")


func test_three_drummers_all_attack() -> void:
	await _check_kind("knuckle_drummer")


func test_three_heavies_all_attack() -> void:
	await _check_kind("knuckle_heavy")


## The signature of fights of one foe and of two (every kind but the heavy and with him, a still and a circling Abarax, SIGNATURE_SEEDS
## seeds each, SIGNATURE_FRAMES frames): the frame and name of every move started, hashed. Recorded before the fix: a foe alone and
## two foes play on as they did, frame for frame.
const SIGNATURE_SEEDS := 5
const SIGNATURE_FRAMES := 900
const SIGNATURE_KINDS := ["knuckle_1", "knuckle_3", "knuckle_blade", "knuckle_drummer", "knuckle_heavy"]
const ONE_FOE_SIGNATURE := 2644839554
const TWO_FOES_SIGNATURE := 1375423006


func _signature(n: int) -> Array:
	var runs: Array[Dictionary] = []
	var seen: Array = []
	var k := 0
	for kind in SIGNATURE_KINDS:
		for circles in [false, true]:
			for s in SIGNATURE_SEEDS:
				var run := _fight(kind, n, s + 1, Vector3(k * 50.0, 0, 0), circles)
				var log := []
				seen.append(log)
				for foe: Actor in run["foes"]:
					foe.runner.move_started.connect(func(m: MoveData) -> void: log.append([run["frame"], foe.name, m.id]))
				runs.append(run)
				k += 1
	await _play(runs, SIGNATURE_FRAMES)
	for run in runs:
		(run["arena"] as Node).free()
	return seen


func _check_signature(n: int, expected: int) -> void:
	var seen: Array = await _signature(n)
	var moves := 0
	for log: Array in seen:
		moves += log.size()
	assert_true(moves > 200, "they fought (%d moves)" % moves)
	assert_eq(str(seen).hash(), expected, "%d foe(s) play the same moves on the same frames as before (%d moves)" % [n, moves])


func test_one_foe_alone_plays_as_before() -> void:
	await _check_signature(1, ONE_FOE_SIGNATURE)


func test_two_foes_play_as_before() -> void:
	await _check_signature(2, TWO_FOES_SIGNATURE)
