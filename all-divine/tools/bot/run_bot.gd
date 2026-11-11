extends SceneTree
## The combat bot's command:
##   tools/godot.sh -s res://tools/bot/run_bot.gd -- [--seeds=1-10] [--frames=7200] [--policy=mixed|aggress|counter|mash|all]
## Plays each seed (see BotRunner) and prints a line for it ("bot seed 3: waves 4, deaths 1, problems 0 (...)"); exits 1 if any seed
## had a problem. The fight is played on the fixed clock, as fast as the machine goes: without --fixed-fps 60 it would run in real time,
## so a run started without it starts itself again with it.
##
## This script names no game class: a script run with -s is compiled before the autoloads are there, so the work is in BotRunner,
## loaded once they are.

const RUNNER := "res://tools/bot/bot_runner.gd"
## The argument a run on the fixed clock is given, so that it does not start itself again.
const MARK := "--on-the-fixed-clock"


func _initialize() -> void:
	# The engine's own arguments are not in get_cmdline_args() once it has read them, so a run that is on the fixed clock says so
	# with an argument of its own (MARK), which the run that starts it adds.
	var args := OS.get_cmdline_user_args()
	if not args.has(MARK):
		quit(_again_fixed(args))
		return
	args.remove_at(args.find(MARK))
	await physics_frame  # the autoloads are in the tree from the first frame, not from _initialize
	var runner: Variant = load(RUNNER).new()
	var code: int = await runner.run(root, args)
	quit(code)


# Runs this same command again with --fixed-fps 60, passing what it prints through; returns its exit code.
func _again_fixed(args: PackedStringArray) -> int:
	var argv := PackedStringArray()
	if DisplayServer.get_name() == "headless":
		argv.append("--headless")
	argv.append_array(["--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "-s", "res://tools/bot/run_bot.gd", "--", MARK])
	argv.append_array(args)
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
