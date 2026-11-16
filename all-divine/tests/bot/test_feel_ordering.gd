extends TestCase
## Does timing beat mashing, without mashing being worthless? The combat bot plays the yard for three seeds (1 to 3), a minute of play
## each (3,600 frames), as a masher (reaction 14, which it does not use: it reads nothing), as a mixed player and a counter player at a
## reaction of 14 frames (a person's, about 230 ms) and as a counter player at 10 frames (a quick person). What is held is the ordering, not
## the numbers, and it is the aims of the fight's tuning of Nov 16 (Task 17): the counter player at 14 clears at least as many waves as the
## masher (1), the mixed player dies at most a third as often and clears more waves (2), the masher still clears a wave in most seeds (3);
## and, as before, the quick counter player takes under half of what it deals and loses nothing to the masher.
## Re-made for Task 17: until then the counter player at 14 cleared fewer waves than the masher (12 against 31 in the ten seeds), which is what
## the tuning changed (tier I's 20-frame jab, the open foe, the cost of mashing).
##
## The full tables (ten seeds, two minutes each, the reaction swept from 10 to 18 and the attack that does the damage) are in notes/f1-feel.md;
## this holds the ordering so that a change to the foes, the defence or the bot that overturns it is seen. It costs about a minute and a half
## of processor, in four child Godots. FEEL_REPORT=1 prints the numbers.

const FRAMES := 3600
const SEEDS := "1-3"
## The line run_bot.gd prints for a seed: waves cleared, deaths, problems, and the HP dealt and taken.
const LINE := "bot seed (\\d+): waves (\\d+), deaths (\\d+), problems (\\d+) .*dealt (\\d+), taken (\\d+)"


# {waves, deaths, dealt, taken, seeds_with_a_wave, runs} over the seeds for `policy` at `reaction`, from run_bot.gd in a Godot of its own.
# A child, and headless whatever this run is: a rendered run of nine fights of a minute took more than ten minutes of CI's software
# renderer, and the bot's fights are the same drawn or not (it reads no picture).
func _play(policy: String, reaction: int) -> Dictionary:
	var out: Array = []
	# --parent: when this runner is killed, run_bot stops its child and ends (it used to play on for 30 to 60 s: a child process left behind).
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "-s", "res://tools/bot/run_bot.gd",
			"--", "--parent=%d" % OS.get_process_id(), "--seeds=" + SEEDS, "--frames=%d" % FRAMES, "--policy=" + policy, "--reaction=%d" % reaction])
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(PackedStringArray(out))
	assert_eq(code, 0, "run_bot exits 0 (no problem found): %s" % text)
	var total := {"waves": 0, "deaths": 0, "dealt": 0.0, "taken": 0.0, "seeds_with_a_wave": 0, "runs": 0}
	var line := RegEx.create_from_string(LINE)
	for found in line.search_all(text):
		total["runs"] += 1
		total["waves"] += found.get_string(2).to_int()
		total["deaths"] += found.get_string(3).to_int()
		assert_eq(found.get_string(4), "0", "seed %s: no problem found" % found.get_string(1))
		total["dealt"] += found.get_string(5).to_float()
		total["taken"] += found.get_string(6).to_float()
		total["seeds_with_a_wave"] += 1 if found.get_string(2).to_int() >= 1 else 0
	assert_eq(total["runs"], 3, "three seeds were played: %s" % text)
	if OS.get_environment("FEEL_REPORT") != "":
		print("FEEL %s at %d: %s" % [policy, reaction, total])
	return total


func test_timing_beats_mashing_and_mashing_is_not_worthless() -> void:
	var mash := _play("mash", 14)
	var mixed := _play("mixed", 14)
	var counter_14 := _play("counter", 14)
	var counter := _play("counter", 10)
	# The rules are the aims of the fight's tuning (Task 17, the owner's choices of Nov 16), each with room: the same seed does not play the
	# same on every machine (CI's is not the one these were measured on), so no bound sits within a fifth of the number measured. Measured
	# here, seeds 1 to 3 at 3,600 frames:  mash at 14: 3 waves, 9 deaths, 264 dealt, 1238 taken, a wave in 3 seeds;  mixed at 14: 8 waves,
	# 1 death, 1028 dealt, 317 taken;  counter at 14: 6 waves, 0 deaths, 804 dealt, 157 taken;  counter at 10: 9 waves, 0 deaths, 1008 dealt, 135 taken.
	# Aim 3: the masher is weaker, not worthless: a wave in at least 2 of the 3 seeds (3 measured; 8 of 10 in the notes' ten).
	assert_true(mash["seeds_with_a_wave"] >= 2, "the masher still clears a wave in most seeds (3 of 3 measured, 2 needed): %s" % [mash])
	# Aim 1: a player who only counters, at a person's reaction, clears at least as many waves as the masher (counter at 14: 6
	# waves measured against 3).
	assert_true(counter_14["waves"] >= mash["waves"], "the counter player at 14 frames clears at least as many waves as the masher: %s against %s" % [counter_14, mash])
	# Aim 2: the mixed player dies at most a third as often as the masher (1 against 9: the bound is 3 of 9) and clears more waves (8 against 3).
	assert_true(mixed["deaths"] * 3 <= mash["deaths"], "the mixed player dies at most a third as often as the masher: %s against %s" % [mixed, mash])
	assert_true(mixed["waves"] > mash["waves"], "and clears more waves: %s against %s" % [mixed, mash])
	# What was held before, with the same room: the masher takes more than it deals (4.7 times measured, once needed), the mixed player takes
	# less than it deals (0.31 measured, under 1), the quick counter player takes under half of what it deals (0.13 measured, under 0.5),
	# clears as many waves as the masher (9 against 3) and dies no more often (0 against 9).
	assert_true(mash["taken"] >= mash["dealt"], "the masher takes as much as it deals or more: %s" % [mash])
	assert_true(mixed["taken"] < mixed["dealt"], "the mixed player takes less than it deals: %s" % [mixed])
	assert_true(counter["taken"] < 0.5 * counter["dealt"], "the counter player at 10 frames takes under half of what it deals: %s" % [counter])
	assert_true(counter["waves"] >= mash["waves"], "the counter player at 10 clears at least as many waves as the masher: %s against %s" % [counter, mash])
	assert_true(counter["deaths"] <= mash["deaths"], "and dies no more often: %s against %s" % [counter, mash])
	var ratio := func(row: Dictionary) -> float: return row["taken"] / maxf(row["dealt"], 1.0)
	assert_true(ratio.call(counter) < ratio.call(mixed) and ratio.call(mixed) < ratio.call(mash), "HP taken for each HP dealt: counter %.2f, mixed %.2f, mash %.2f" % [ratio.call(counter), ratio.call(mixed), ratio.call(mash)])
