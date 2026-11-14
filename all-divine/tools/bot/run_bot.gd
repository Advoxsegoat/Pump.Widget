extends SceneTree
## The combat bot's command:
##   tools/godot.sh -s res://tools/bot/run_bot.gd -- [--seeds=1-10] [--frames=7200] [--policy=mixed|aggress|counter|mash|all] [--reaction=14] [--detail]
## Plays each seed (see BotRunner) and prints a line for it ("bot seed 3: waves 4, deaths 1, problems 0 (...)"); exits 1 if any seed
## had a problem. The fight is played on the fixed clock, as fast as the machine goes: without --fixed-fps 60 it would run in real time,
## so a run is played by a Godot of its own started with it, one for each seed (and run again if it dies).
##
## This script names no game class: a script run with -s is compiled before the autoloads are there, so the work is in BotRunner,
## loaded once they are.

const RUNNER := "res://tools/bot/bot_runner.gd"
## The argument a run on the fixed clock is given, so that it does not start itself again.
const MARK := "--on-the-fixed-clock"
## How many times a seed is run again when its Godot dies.
const RETRIES := 2


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	await physics_frame  # the autoloads are in the tree from the first frame, not from _initialize
	var runner: Variant = load(RUNNER).new()
	if args.has(MARK):
		args.remove_at(args.find(MARK))
		quit(await runner.run(root, args))
		return
	quit(_supervise(runner, runner.parse(args)))


# Plays each policy and seed asked for in a Godot of its own on the fixed clock (--fixed-fps 60: without it the physics runs in real time),
# passing what it prints through: a Godot that dies on one (the engine crashed, which it has now and then, with no problem of the game's
# in the log) is run again for that seed, up to RETRIES times, and said so. Returns 1 if any seed had a problem or never finished, 2 for
# arguments that cannot be read, else 0.
func _supervise(runner: Variant, asked: Dictionary) -> int:
	if asked.is_empty():
		return 2
	var failed := false
	for policy: int in asked["policies"]:
		for seed_number: int in asked["seeds"]:
			var policy_name: String = runner.policy_name(policy)
			var code := -1
			for attempt in RETRIES + 1:
				code = _child(["--seeds=%d" % seed_number, "--frames=%d" % asked["frames"], "--policy=%s" % policy_name, "--reaction=%d" % asked["reaction"]] + (["--detail"] if asked["detail"] else []) + (["--no-steering"] if not asked["steering"] else []) + (["--until-round"] if asked["until_round"] else []))
				if code == 0 or code == 1:
					break
				printerr("run_bot: Godot died (exit %d) on seed %d, policy %s%s" % [code, seed_number, policy_name, "; running it again" if attempt < RETRIES else ""])
			failed = failed or code != 0
	return 1 if failed else 0


# One Godot on the fixed clock playing `user_args`, its output passed through; returns its exit code.
func _child(user_args: Array) -> int:
	var argv := PackedStringArray()
	if DisplayServer.get_name() == "headless":
		argv.append("--headless")
	argv.append_array(["--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "-s", "res://tools/bot/run_bot.gd", "--", MARK])
	argv.append_array(PackedStringArray(user_args))
	var child := OS.execute_with_pipe(OS.get_executable_path(), argv, false)
	if child.is_empty():
		printerr("run_bot: could not start Godot again with --fixed-fps")
		return 2
	var out: FileAccess = child["stdio"]
	var err: FileAccess = child["stderr"]
	var pid: int = child["pid"]
	while OS.is_process_running(pid):
		_pass_on(out, false)
		_pass_on(err, true)
		OS.delay_msec(50)
	_pass_on(out, false)
	_pass_on(err, true)
	return OS.get_process_exit_code(pid)


# Prints the lines `pipe` has to give.
func _pass_on(pipe: FileAccess, to_stderr: bool) -> void:
	while pipe.get_position() < pipe.get_length():
		var line := pipe.get_line()
		if to_stderr:
			printerr(line)
		else:
			print(line)
