extends TestCase
## The heavy Knuckle's attacks hold every attack token of their target (AttackOption.tokens, Task 14e): while he winds up,
## blows and recovers no other enemy begins an attack on that target, and he begins none while another enemy holds a token.
## Before, his blow held one of the two, so a tier I beside him could jab into the stagger he made and he could swing again
## into theirs: a player who was hit could be chained for runs of up to eight blows and 122 HP.
##
## The fights are the heavy and a tier I on an Abarax with a great deal of HP, who either stands still and takes it or walks
## round the heavy at 2 m, 1800 frames each, SEEDS (3) of them at once (twenty were run for the report: HEAVY_TOKENS_SEEDS=20),
## each pair in its own arena far from the others.

const ABARAX := "res://data/actors/abarax.tres"
const HEAVY := "res://data/actors/knuckle_heavy.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_2 := "res://data/actors/knuckle_2.tres"
const BRAIN_1 := "res://data/brains/knuckle_1.tres"
const BRAIN_2 := "res://data/brains/knuckle_2.tres"
const FIGHT_FRAMES := 1800
## Blows landing closer than this are one run of blows (a player is still reeling from the first).
const CHAIN_GAP := 45
## Three seconds, in frames.
const WINDOW := 180
## Moves a tier I starts an attack with.
const TIER_I_STARTS: Array[StringName] = [&"knuckle_jab", &"knuckle_sweep"]
## The signature of a tier II and a tier I fighting a still Abarax for 900 frames, recorded before the brain learned to hold
## more than one token: the frame and name of every move started, hashed. A brain whose options hold one token plays on as it did.
const TIER_II_SIGNATURE := 2047247070


static func _seeds() -> int:
	var named := OS.get_environment("HEAVY_TOKENS_SEEDS")
	return int(named) if named.is_valid_int() else 3


static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	def.max_posture = 100000.0
	return def


## Abarax for the fights: stands, or walks round `foe` at about 2 m, facing it.
class Player extends Brain:
	var foe: Actor
	var circles := false

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		if foe == null or not circles:
			return intent
		var to := Vector2(foe.global_position.x - actor.global_position.x, foe.global_position.z - actor.global_position.z)
		intent.face_target = foe.global_position
		if to.length() > 0.01:
			var dir := to.normalized()
			intent.move = (dir.rotated(PI * 0.5) * 0.4 + dir * clampf((to.length() - 2.0) * 0.4, -0.3, 0.6)).limit_length(0.5)
		return intent


## One fight in its own arena at `origin`: {arena, abarax, enemies, hits, starts}. `hits` is [[abarax's frame, attacker's name,
## hp damage]] of every blow that landed (the outcome was a HIT) and `starts` the tier I's attack starts (frames).
func _fight(circles: bool, with_tier_one: bool, seed_value: int, origin: Vector3, with_tokens := true, second := KNUCKLE_1,
		second_brain := BRAIN_1, first := HEAVY) -> Dictionary:
	var arena := TestArena.make(self)
	arena.position = origin
	if with_tokens:
		var tokens := AttackTokens.new()
		arena.add_child(tokens)
	var player := Player.new()
	player.circles = circles
	var abarax := TestArena.spawn(arena, _tough(ABARAX), player, Vector3.ZERO, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, 0.0), origin))
	var enemies: Array[Actor] = []
	var first_def := _tough(first)
	var big := TestArena.spawn(arena, first_def, EnemyBrain.new(first_def.brain, seed_value), Vector3(0, 0, 3.0), "Heavy" if first == HEAVY else "First")
	big.place(Transform3D(Basis(Vector3.UP, PI), origin + Vector3(0, 0, 3.0)))
	enemies.append(big)
	player.foe = big
	if with_tier_one:
		var def := _tough(second)
		var small := TestArena.spawn(arena, def, EnemyBrain.new(load(second_brain) as BrainDef, seed_value + 1000), Vector3(2.5, 0, 2.5), "Tier")
		small.place(Transform3D(Basis(Vector3.UP, PI), origin + Vector3(2.5, 0, 2.5)))
		enemies.append(small)
	var run := {"arena": arena, "abarax": abarax, "enemies": enemies, "hits": [], "starts": []}
	abarax.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if r.outcome == HitResult.Outcome.HIT:
			run["hits"].append([abarax.frame, e.attacker.name, r.hp_damage]))
	if with_tier_one:
		(enemies[1] as Actor).runner.move_started.connect(func(m: MoveData) -> void:
			if TIER_I_STARTS.has(m.id):
				run["starts"].append(abarax.frame))
	return run


## The longest run of blows less than CHAIN_GAP frames apart that holds blows of both enemies, as [blows in it, HP in it], or [0, 0].
static func _mixed_run(hits: Array) -> Array:
	var worst := [0, 0.0]
	var run: Array = []
	for i in hits.size():
		if not run.is_empty() and hits[i][0] - run.back()[0] >= CHAIN_GAP:
			run.clear()
		run.append(hits[i])
		var names := {}
		var hp := 0.0
		for h: Array in run:
			names[h[1]] = true
			hp += h[2]
		if names.size() > 1 and run.size() > worst[0]:
			worst = [run.size(), hp]
	return worst


## The most HP taken in any WINDOW frames.
static func _worst_window(hits: Array) -> float:
	var worst := 0.0
	for i in hits.size():
		var hp := 0.0
		for j in range(i, hits.size()):
			if hits[j][0] - hits[i][0] >= WINDOW:
				break
			hp += hits[j][2]
		worst = maxf(worst, hp)
	return worst


## The damage of one tier I string: its jab, cross and hook.
static func _tier_one_string() -> float:
	var hp := 0.0
	for id in [&"knuckle_jab", &"knuckle_cross", &"knuckle_hook"]:
		for profile: HitProfile in (Registry.fetch(&"moves", id) as MoveData).hits.values():
			hp += profile.damage
	return hp


## Plays `circles` fights of the heavy alone and of the heavy with a tier I, `seeds` of each, together; returns
## {mixed_runs: the longest mixed run over them, window: the worst window with the tier I, alone_window: the worst window of the heavy alone,
## starts: the tier I's attack starts in all, blows: [the heavy's, the tier I's] landed in all}.
func _measure(circles: bool, seeds: int) -> Dictionary:
	var pairs: Array[Dictionary] = []
	var alones: Array[Dictionary] = []
	for s in seeds:
		pairs.append(_fight(circles, true, s + 1, Vector3(s * 50.0, 0, 0)))
		alones.append(_fight(circles, false, s + 1, Vector3(s * 50.0, 0, 200.0)))
	await frames(FIGHT_FRAMES)
	var result := {"mixed": [0, 0.0], "window": 0.0, "alone_window": 0.0, "starts": 0, "blows": [0, 0]}
	for run in pairs:
		var mixed := _mixed_run(run["hits"])
		if mixed[0] > result["mixed"][0]:
			result["mixed"] = mixed
		result["window"] = maxf(result["window"], _worst_window(run["hits"]))
		result["starts"] += (run["starts"] as Array).size()
		for h: Array in run["hits"]:
			result["blows"][0 if h[1] == "Heavy" else 1] += 1
	for run in alones:
		result["alone_window"] = maxf(result["alone_window"], _worst_window(run["hits"]))
	for run in pairs + alones:
		(run["arena"] as Node).free()
	if OS.get_environment("HEAVY_TOKENS_SEEDS") != "":
		print("heavy tokens, %s, %d seeds: %s" % ["circling" if circles else "standing", seeds, result])
	return result


func _check_fights(circles: bool) -> void:
	var seeds := _seeds()
	var shown := "%s Abarax, %d fights" % ["a circling" if circles else "a still", seeds]
	var m: Dictionary = await _measure(circles, seeds)
	assert_eq(m["mixed"][0], 0, "%s: no run of blows under %d frames apart holds blows of both enemies (longest: %s blows, %.0f HP)" % [shown, CHAIN_GAP, m["mixed"][0], m["mixed"][1]])
	var bound: float = m["alone_window"] + _tier_one_string()
	assert_true(m["window"] <= bound, "%s: the most taken in 3 s is %.0f HP, no more than the heavy alone's %.0f plus a tier I string's %.0f" % [shown, m["window"], m["alone_window"], _tier_one_string()])
	var per_ten := float(m["starts"]) / (seeds * float(FIGHT_FRAMES) / 600.0)
	assert_true(per_ten >= 1.0, "%s: the tier I still attacks, %d times in %d fights (%.2f per ten seconds)" % [shown, m["starts"], seeds, per_ten])
	assert_true(m["blows"][0] > 0 and m["blows"][1] > 0, "%s: both land blows (%s)" % [shown, m["blows"]])


func test_a_player_standing_between_the_heavy_and_a_tier_one_is_not_chained() -> void:
	await _check_fights(false)


func test_a_player_circling_the_heavy_at_two_metres_is_not_chained() -> void:
	await _check_fights(true)


func test_a_tier_ii_and_a_tier_i_play_as_they_did() -> void:
	var run := _fight(false, true, 5, Vector3.ZERO, true, KNUCKLE_1, BRAIN_1, KNUCKLE_2)
	var seen: Array = []
	for enemy: Actor in run["enemies"]:
		enemy.runner.move_started.connect(func(m: MoveData) -> void: seen.append([(run["abarax"] as Actor).frame, enemy.name, m.id]))
	await frames(900)
	(run["arena"] as Node).free()
	var signature := str(seen).hash()
	assert_true(seen.size() >= 6, "they attacked (%d moves)" % seen.size())
	assert_eq(signature, TIER_II_SIGNATURE, "the same moves on the same frames as before (%d moves: %s)" % [seen.size(), seen.slice(0, 8)])
