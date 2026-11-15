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
## this holds the ordering so that a change to the foes, the defence or the bot that overturns it is seen. It costs about a minute of processor, in three child Godots.
## FEEL_REPORT=1 prints the numbers.

const FRAMES := 3600
const SEEDS := "1-3"
## The line run_bot.gd prints for a seed: waves cleared, deaths, problems, and the HP dealt and taken.
const LINE := "bot seed (\\d+): waves (\\d+), deaths (\\d+), problems (\\d+) .*dealt (\\d+), taken (\\d+)"


# {waves, deaths, dealt, taken, seeds_with_a_wave, runs} over the seeds for `policy` at `reaction`, from run_bot.gd in a Godot of its own.
# A child, and headless whatever this run is: a rendered run of nine fights of a minute took more than ten minutes of CI's software
# renderer, and the bot's fights are the same drawn or not (it reads no picture).
func _play(policy: String, reaction: int) -> Dictionary:
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "-s", "res://tools/bot/run_bot.gd",
			"--", "--seeds=" + SEEDS, "--frames=%d" % FRAMES, "--policy=" + policy, "--reaction=%d" % reaction])
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
	var counter := _play("counter", 10)
	assert_true(mash["seeds_with_a_wave"] >= 2, "the masher clears a wave in most seeds: %s" % [mash])
	assert_true(mash["taken"] >= 0.9 * mash["dealt"], "the masher takes about as much as it deals or more: %s" % [mash])
	assert_true(mixed["taken"] < mixed["dealt"], "the mixed player takes less than it deals: %s" % [mixed])
	assert_true(mixed["deaths"] * 2 < mash["deaths"], "the mixed player dies less than half as often as the masher: %s against %s" % [mixed, mash])
	assert_true(counter["taken"] < 0.5 * counter["dealt"], "the counter player at 10 frames takes under half of what it deals: %s" % [counter])
	assert_true(counter["waves"] >= mash["waves"] and counter["deaths"] <= mash["deaths"], "and clears as many waves as the masher, with no more deaths: %s against %s" % [counter, mash])
	var ratio := func(row: Dictionary) -> float: return row["taken"] / maxf(row["dealt"], 1.0)
	assert_true(ratio.call(counter) < ratio.call(mixed) and ratio.call(mixed) < ratio.call(mash), "HP taken for each HP dealt: counter %.2f, mixed %.2f, mash %.2f" % [ratio.call(counter), ratio.call(mixed), ratio.call(mash)])
