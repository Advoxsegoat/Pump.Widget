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
