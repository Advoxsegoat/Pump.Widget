extends TestCase
## The bot's numbers by attack (CombatBot.by_attack, attack_lines): which blow of which foe took how much HP off the player, and how
## it ended each time it was met (hit, evaded, guarded, ...). Task 16's feel tables use it to name a blow that does most of the damage.

const KNUCKLE := "res://data/actors/knuckle_1.tres"


func after_each() -> void:
	InputFeed.release()
	Game.reset()
	await frames(1)


func test_each_blow_met_is_counted_under_its_foe_and_move_with_the_hp_it_took() -> void:
	# The masher does nothing about a blow: the jab lands (or is slipped by a sway the masher happened to press), and is counted.
	var run := Duel.make(self, [], [], 1.0, load(KNUCKLE) as ActorDef)
	var a: Actor = run["a"]
	a.set_brain(PlayerBrain.new())
	var bot := track(CombatBot.new()) as CombatBot
	bot.reaction_frames = 0
	bot.begin(a, null, 1, CombatBot.Policy.MASH)
	await frames(30)
	(run["b"] as Actor).runner.start(Registry.fetch(&"moves", &"knuckle_jab") as MoveData)
	await frames(120)
	assert_eq(bot.by_attack.keys(), [&"knuckle_1/knuckle_jab"], "one blow was met: %s" % [bot.by_attack])
	var row: Dictionary = bot.by_attack.get(&"knuckle_1/knuckle_jab", {})
	var met := 0
	for outcome: String in row.get("outcomes", {}):
		met += int(row["outcomes"][outcome])
	assert_true(met >= 1, "it was met at least once: %s" % [row])
	assert_eq(float(row.get("taken", -1.0)), bot.damage_taken, "the HP it took is the HP the bot took")
	var lines := bot.attack_lines()
	assert_eq(lines.size(), 1)
	assert_true(lines[0].contains("knuckle_1/knuckle_jab") and lines[0].contains("taken %d" % roundi(bot.damage_taken)), "%s" % [lines])
