extends TestCase
## The bot's command (tools/bot/run_bot.gd): its arguments, and a run of it as a child Godot, which prints a line for the seed and
## exits 0 for a clean run and 2 for arguments it cannot read. (That a problem makes it exit 1 is BotRunner.run's one line; the
## problem itself is the soft-lock fixture's in test_combat_bot.gd.)

## Seconds a child run may take.
const CHILD_LIMIT := 120


func test_seeds_are_read_as_ranges_and_lists() -> void:
	assert_eq(BotRunner.parse_seeds("1-4"), [1, 2, 3, 4] as Array[int])
	assert_eq(BotRunner.parse_seeds("3"), [3] as Array[int])
	assert_eq(BotRunner.parse_seeds("1,4-5,9"), [1, 4, 5, 9] as Array[int])
	assert_eq(BotRunner.parse_seeds("4-1"), [] as Array[int], "a range that runs backward is not one")
	assert_eq(BotRunner.parse_seeds("x"), [] as Array[int])


func test_policies_are_read_by_name_and_all_is_all_four() -> void:
	assert_eq(BotRunner.parse_policies("mixed"), [CombatBot.Policy.MIXED] as Array[CombatBot.Policy])
	assert_eq(BotRunner.parse_policies("counter"), [CombatBot.Policy.COUNTER] as Array[CombatBot.Policy])
	assert_eq(BotRunner.parse_policies("all").size(), 4)
	assert_eq(BotRunner.parse_policies("rolling").size(), 0, "there is no such policy")


# Runs run_bot.gd as the command line does (in a child of this Godot): {code, text}.
func _run(user_args: Array[String]) -> Dictionary:
	var argv := PackedStringArray(["-k", "5", str(CHILD_LIMIT), OS.get_executable_path(), "--headless", "--path",
			ProjectSettings.globalize_path("res://"), "-s", "res://tools/bot/run_bot.gd", "--"])
	argv.append_array(PackedStringArray(user_args))
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	return {code = code, text = str(output[0]) if not output.is_empty() else ""}


func test_a_clean_run_prints_a_line_for_its_seed_and_exits_zero() -> void:
	var run := _run(["--seeds=1", "--frames=120"])
	assert_eq(run["code"], 0, run["text"])
	assert_true(String(run["text"]).contains("bot seed 1: waves 0, deaths 0, problems 0"), run["text"])


func test_arguments_it_cannot_read_exit_two() -> void:
	var run := _run(["--seeds=nine"])
	assert_eq(run["code"], 2, run["text"])


func test_the_arguments_are_parsed_together() -> void:
	var asked := BotRunner.parse(PackedStringArray(["--seeds=2-3", "--frames=500", "--policy=counter", "--detail"]))
	assert_eq(asked["seeds"], [2, 3] as Array[int])
	assert_eq(asked["frames"], 500)
	assert_eq(asked["policies"], [CombatBot.Policy.COUNTER] as Array[CombatBot.Policy])
	assert_true(asked["detail"])
	assert_eq(BotRunner.parse(PackedStringArray()), {"seeds": [1] as Array[int], "frames": 7200, "policies": [CombatBot.Policy.MIXED] as Array[CombatBot.Policy], "detail": false}, "the defaults")
	assert_true(quietly(func() -> Variant: return BotRunner.parse(PackedStringArray(["--seeds=x"]))).is_empty(), "unreadable gives nothing")
