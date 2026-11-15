extends TestCase
## Does timing beat mashing, without mashing being worthless? The combat bot plays the yard for three seeds (1 to 3), a minute of play
## each (3,600 frames), as a masher (reaction 14, which it does not use: it reads nothing), as a mixed player at a reaction of 14 frames
## (a person's, about 230 ms) and as a counter player at 10 frames (a quick person). What is held is the ordering, not the numbers:
##
##   the masher still clears a wave in most seeds (it is not worthless), and takes as much as it deals;
##   the mixed player takes less than it deals and dies less than half as often as the masher;
##   the counter player at 10 frames takes under half of what it deals, and clears as many waves as the masher with no more deaths.
##
## The full tables (ten seeds, two minutes each, the reaction swept from 10 to 18 and the attack that does the damage) are in notes/f1-feel.md;
## this holds the ordering so that a change to the foes, the defence or the bot that overturns it is seen. It costs about a minute.
## FEEL_REPORT=1 prints the numbers.

const FRAMES := 3600
const SEEDS: Array[int] = [1, 2, 3]


func after_each() -> void:
	InputFeed.release()
	Game.reset()
	await frames(1)


# {waves, deaths, dealt, taken, seeds_with_a_wave} over SEEDS for `policy` at `reaction`.
func _play(policy: CombatBot.Policy, reaction: int) -> Dictionary:
	var total := {"waves": 0, "deaths": 0, "dealt": 0.0, "taken": 0.0, "seeds_with_a_wave": 0}
	var runner := BotRunner.new()
	for seed_number in SEEDS:
		var run := await runner.play(self, seed_number, policy, FRAMES, reaction)
		assert_eq((run["problems"] as PackedStringArray).size(), 0, "seed %d: no problem found: %s" % [seed_number, run["problems"]])
		total["waves"] += run["waves"]
		total["deaths"] += run["deaths"]
		total["dealt"] += run["dealt"]
		total["taken"] += run["taken"]
		total["seeds_with_a_wave"] += 1 if run["waves"] >= 1 else 0
	if OS.get_environment("FEEL_REPORT") != "":
		print("FEEL %s at %d: %s" % [CombatBot.POLICIES.find_key(policy), reaction, total])
	return total


func test_timing_beats_mashing_and_mashing_is_not_worthless() -> void:
	var mash := await _play(CombatBot.Policy.MASH, 14)
	var mixed := await _play(CombatBot.Policy.MIXED, 14)
	var counter := await _play(CombatBot.Policy.COUNTER, 10)
	assert_true(mash["seeds_with_a_wave"] >= 2, "the masher clears a wave in most seeds: %s" % [mash])
	assert_true(mash["taken"] >= 0.9 * mash["dealt"], "the masher takes about as much as it deals or more: %s" % [mash])
	assert_true(mixed["taken"] < mixed["dealt"], "the mixed player takes less than it deals: %s" % [mixed])
	assert_true(mixed["deaths"] * 2 < mash["deaths"], "the mixed player dies less than half as often as the masher: %s against %s" % [mixed, mash])
	assert_true(counter["taken"] < 0.5 * counter["dealt"], "the counter player at 10 frames takes under half of what it deals: %s" % [counter])
	assert_true(counter["waves"] >= mash["waves"] and counter["deaths"] <= mash["deaths"], "and clears as many waves as the masher, with no more deaths: %s against %s" % [counter, mash])
	var ratio := func(row: Dictionary) -> float: return row["taken"] / maxf(row["dealt"], 1.0)
	assert_true(ratio.call(counter) < ratio.call(mixed) and ratio.call(mixed) < ratio.call(mash), "HP taken for each HP dealt: counter %.2f, mixed %.2f, mash %.2f" % [ratio.call(counter), ratio.call(mixed), ratio.call(mash)])
