extends TestCase
## Attack tokens (combat/attack_tokens.gd, spec §4.5): only PER_TARGET (two) enemies commit to an attack on one target at
## a time. A token comes back by itself when its attacker's move is over, when the attacker dies, or TIMEOUT (3 s) after
## it was last taken; a squad that ignores tokens never takes one; with no AttackTokens in the tree every take succeeds.
##
## Abarax (his own def, HP to spare, standing idle) at the origin; Knuckles around him.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"


# A copy of the def at `path` with HP enough to live through anything here.
static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	return def


# An arena (with an AttackTokens node in it when `with_tokens`), Abarax at the origin, and `knuckles` Knuckles of tier I
# standing 2 m from him in a ring, each driven by the brain `brain_of.call(i)` (a Brain), facing him:
# {arena, tokens, abarax, knuckles}.
func _ring(knuckles: int, brain_of: Callable, with_tokens := true) -> Dictionary:
	var arena := TestArena.make(self)
	var tokens: AttackTokens = null
	if with_tokens:
		tokens = AttackTokens.new()
		arena.add_child(tokens)
	var abarax := TestArena.spawn(arena, _tough(ABARAX), Brain.new(), Vector3.ZERO, "Abarax")
	var ring: Array[Actor] = []
	for i in knuckles:
		var angle := TAU * i / knuckles
		var at := Vector3(sin(angle), 0.0, cos(angle)) * 2.0
		var knuckle := TestArena.spawn(arena, _tough(KNUCKLE_1), brain_of.call(i), at, "Knuckle%d" % i)
		knuckle.place(Transform3D(Basis(Vector3.UP, angle + PI), at))
		ring.append(knuckle)
	return {"arena": arena, "tokens": tokens, "abarax": abarax, "knuckles": ring}


func test_tokens_come_back_on_move_end_death_and_timeout() -> void:
	var run := _ring(3, func(i: int) -> Brain:
		return ScriptBrain.new([{"frames": 2}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}] if i == 0 else []))
	var tokens: AttackTokens = run["tokens"]
	var abarax: Actor = run["abarax"]
	var k: Array[Actor] = run["knuckles"]
	await frames(1)
	assert_true(tokens.take(k[0], abarax), "the first takes a token")
	assert_true(tokens.take(k[1], abarax), "and the second")
	assert_false(tokens.take(k[2], abarax), "but there are only two for one target")
	assert_true(tokens.take(k[0], abarax), "one that holds a token may take it again")
	assert_eq(tokens.count(abarax), 2)
	# The first jabs from frame 3; its jab is over by frame 3 + 48 and some hit-stop.
	await frames(10)
	assert_true(k[0].runner.busy() and tokens.holds(k[0]), "it holds its token while its jab plays")
	await frames(60)
	assert_false(k[0].runner.busy(), "the jab is over")
	assert_false(tokens.holds(k[0]), "and its token came back with it")
	k[1].die()
	assert_false(tokens.holds(k[1]), "a token comes back when its holder dies")
	assert_eq(tokens.count(abarax), 0)
	assert_true(tokens.take(k[2], abarax), "so the third can take one now")
	await frames(roundi(AttackTokens.TIMEOUT * 60.0) - 5)
	assert_true(tokens.holds(k[2]), "held, unused, for a little under %.0f s" % AttackTokens.TIMEOUT)
	await frames(10)
	assert_false(tokens.holds(k[2]), "and taken back after %.0f s" % AttackTokens.TIMEOUT)
	assert_eq(AttackTokens.PER_TARGET, 2)
	assert_eq(AttackTokens.TIMEOUT, 3.0)


func test_a_flinch_gives_the_token_back() -> void:
	var run := _ring(1, func(_i: int) -> Brain: return Brain.new())
	var tokens: AttackTokens = run["tokens"]
	var abarax: Actor = run["abarax"]
	var knuckle: Actor = (run["knuckles"] as Array)[0]
	await frames(1)
	assert_true(tokens.take(knuckle, abarax))
	knuckle.runner.start(Registry.fetch(&"moves", &"flinch") as MoveData)
	assert_false(tokens.holds(knuckle), "an attack cut short by a reaction is over: its token comes back")


func test_with_no_tokens_node_every_take_succeeds() -> void:
	var run := _ring(4, func(_i: int) -> Brain: return Brain.new(), false)
	var abarax: Actor = run["abarax"]
	await frames(1)
	for knuckle: Actor in run["knuckles"]:
		assert_true(AttackTokens.take_for(knuckle, abarax), "%s may attack: nothing hands out tokens" % knuckle.name)
	AttackTokens.give_back_for(run["knuckles"][0])  # and giving one back is harmless


# The tier I brain, seeded by the Knuckle's place in the ring, ignoring tokens if `squad`.
static func _brain(i: int, squad := false) -> Brain:
	var def := (load("res://data/brains/knuckle_1.tres") as BrainDef).duplicate(true) as BrainDef
	def.ignores_tokens = squad
	return EnemyBrain.new(def, 100 + i)


# Plays `frames_to_play` frames of `run` and returns [the most Knuckles that were attacking at once, the most tokens held
# on Abarax at once, how many attack moves were started].
func _watch(run: Dictionary, frames_to_play: int) -> Array:
	var tokens: AttackTokens = run["tokens"]
	var abarax: Actor = run["abarax"]
	var started := [0]
	for knuckle: Actor in run["knuckles"]:
		knuckle.runner.move_started.connect(func(m: MoveData) -> void:
			if m.kind == MoveData.Kind.ATTACK:
				started[0] += 1)
	var most := 0
	var most_tokens := 0
	for i in frames_to_play:
		await frames(1)
		var now := 0
		for knuckle: Actor in run["knuckles"]:
			if knuckle.paired_with != null or (knuckle.runner.current != null and knuckle.runner.current.kind == MoveData.Kind.ATTACK):
				now += 1
		most = maxi(most, now)
		most_tokens = maxi(most_tokens, tokens.count(abarax))
	return [most, most_tokens, started[0]]


func test_only_two_of_four_commit_at_once() -> void:
	var run := _ring(4, func(i: int) -> Brain: return _brain(i))
	var seen: Array = await _watch(run, 60 * 15)
	assert_true(seen[2] >= 8, "they attacked (%d attack moves in 15 s)" % seen[2])
	assert_eq(seen[0], 2, "two of the four at once, never more")
	assert_true(seen[1] <= AttackTokens.PER_TARGET, "and never more than two tokens out on him (%d)" % seen[1])


func test_squads_that_ignore_tokens_take_none() -> void:
	var run := _ring(4, func(i: int) -> Brain: return _brain(i, true))
	var seen: Array = await _watch(run, 60 * 10)
	assert_eq(seen[1], 0, "a squad takes no tokens")
	assert_true(seen[2] >= 6, "and attacks all the same (%d attack moves in 10 s)" % seen[2])
	assert_true(seen[0] >= 3, "more than two of it at once (%d)" % seen[0])


func test_a_holder_freed_or_taken_out_of_the_tree_gives_its_token_back() -> void:
	var run := _ring(4, func(_i: int) -> Brain: return Brain.new())
	var tokens: AttackTokens = run["tokens"]
	var abarax: Actor = run["abarax"]
	var k: Array[Actor] = run["knuckles"]
	await frames(1)
	assert_true(tokens.take(k[0], abarax))
	assert_true(tokens.take(k[1], abarax))
	k[0].queue_free()  # gone without dying
	await frames(3)
	assert_eq(tokens.count(abarax), 1, "a holder freed without dying gives its token back")
	assert_true(tokens.take(k[2], abarax), "so another may take it")
	assert_false(tokens.take(k[3], abarax), "and the limit still holds")
	k[1].get_parent().remove_child(k[1])  # out of the tree, not freed
	assert_false(tokens.holds(k[1]), "a holder taken out of the tree gives its token back at once")
	assert_true(tokens.take(k[3], abarax))
	await frames(2)
	k[1].free()
	await frames(2)
	assert_eq(tokens.count(abarax), 2, "nothing is lost or doubled when it is freed after")


# --- an attack that holds more than one token (AttackOption.tokens, the heavy Knuckle's) ---

func test_an_attack_can_hold_all_of_a_targets_tokens() -> void:
	var run := _ring(3, func(i: int) -> Brain:
		return ScriptBrain.new([{"frames": 2}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}] if i == 0 else []))
	var tokens: AttackTokens = run["tokens"]
	var abarax: Actor = run["abarax"]
	var k: Array[Actor] = run["knuckles"]
	await frames(1)
	assert_eq(AttackTokens.ALL, 0, "0 asks for all of them")
	assert_true(tokens.take(k[0], abarax, AttackTokens.ALL), "alone, one may take them all")
	assert_eq(tokens.count(abarax), AttackTokens.PER_TARGET, "that is every token the target gives")
	assert_false(tokens.take(k[1], abarax), "and no other enemy takes one")
	assert_false(tokens.take(k[2], abarax, AttackTokens.ALL), "nor all")
	assert_true(tokens.take(k[0], abarax, AttackTokens.ALL), "taken again by its holder, they stay its own")
	assert_eq(tokens.count(abarax), AttackTokens.PER_TARGET, "not doubled")
	await frames(10)
	assert_true(k[0].runner.busy() and tokens.holds(k[0]), "held while its blow plays")
	assert_eq(tokens.count(abarax), AttackTokens.PER_TARGET, "all of them")
	assert_false(tokens.take(k[1], abarax), "so still no one else")
	await frames(60)
	assert_false(k[0].runner.busy(), "its blow is over")
	assert_eq(tokens.count(abarax), 0, "and every token came back with it")
	assert_true(tokens.take(k[1], abarax) and tokens.take(k[2], abarax), "two others may take one each now")


func test_taking_more_is_refused_while_another_holds_one_and_keeps_what_was_held() -> void:
	var run := _ring(2, func(_i: int) -> Brain: return Brain.new())
	var tokens: AttackTokens = run["tokens"]
	var abarax: Actor = run["abarax"]
	var k: Array[Actor] = run["knuckles"]
	await frames(1)
	assert_true(tokens.take(k[0], abarax))
	assert_true(tokens.take(k[1], abarax))
	assert_false(tokens.can_take(k[0], abarax, AttackTokens.ALL), "it could not hold all: another holds one")
	assert_false(tokens.take(k[0], abarax, AttackTokens.ALL), "so it does not")
	assert_true(tokens.holds(k[0]) and tokens.count(abarax) == 2, "and keeps the one it had")
	tokens.give_back(k[1])
	assert_true(tokens.can_take(k[0], abarax, AttackTokens.ALL), "alone it could")
	assert_true(tokens.take(k[0], abarax, AttackTokens.ALL), "and takes them: the one it had grows to all")
	assert_eq(tokens.count(abarax), AttackTokens.PER_TARGET)
	assert_true(tokens.take(k[0], abarax), "taken as one token, it holds one again")
	assert_eq(tokens.count(abarax), 1, "the rest are free")
	assert_true(tokens.take(k[1], abarax), "for another")


func test_all_tokens_come_back_when_the_attack_is_cut_or_its_holder_goes() -> void:
	var run := _ring(4, func(_i: int) -> Brain: return Brain.new())
	var tokens: AttackTokens = run["tokens"]
	var abarax: Actor = run["abarax"]
	var k: Array[Actor] = run["knuckles"]
	await frames(1)
	assert_true(tokens.take(k[0], abarax, AttackTokens.ALL))
	k[0].runner.start(Registry.fetch(&"moves", &"flinch") as MoveData)
	assert_eq(tokens.count(abarax), 0, "a flinch gives them all back")
	assert_true(tokens.take(k[0], abarax, AttackTokens.ALL))
	k[0].runner.start(Registry.fetch(&"moves", &"posture_broken") as MoveData)
	assert_eq(tokens.count(abarax), 0, "a broken posture does")
	assert_true(tokens.take(k[1], abarax, AttackTokens.ALL))
	k[1].die()
	assert_eq(tokens.count(abarax), 0, "a death does")
	assert_true(tokens.take(k[2], abarax, AttackTokens.ALL))
	k[2].queue_free()  # an arena reset frees its actors
	await frames(3)
	assert_eq(tokens.count(abarax), 0, "a reset (the holder freed) does")
	assert_true(tokens.take(k[3], abarax, AttackTokens.ALL), "and the next may take them")
	await frames(roundi(AttackTokens.TIMEOUT * 60.0) + 5)
	assert_eq(tokens.count(abarax), 0, "held unused, they come back after the timeout, all of them")
