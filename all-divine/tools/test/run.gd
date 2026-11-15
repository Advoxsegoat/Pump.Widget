extends SceneTree
## Test entry point:
##   godot --headless --fixed-fps 60 -s res://tools/test/run.gd -- [--filter=<s>] [--files=<a.gd,b.gd>]
##         [--render|--forward-plus] [--update-golden] [--expect-method=<rendering method>] [--shard=<i>/<n>]
## Prints PASS <id> or FAIL <id>: <message> per test, `FILE-SECONDS <seconds> <path under tests/>` after each file's tests (what
## tools/test/shard_weights.py turns CI's render logs into tests/shard_weights.txt), then "N passed, M failed".
## Exits 1 if anything failed or no test ran. tools/test.sh is the usual way to call it.
## --files runs exactly the listed test files (comma-separated res:// paths) instead of discovering them.
## --shard=<i>/<n> runs the i-th of n shares of the files (i from 1): n runs with i from 1 to n cover the suite between them
## (CI's render job is split this way; the software renderer makes the whole suite too long for one job). The files are dealt
## by their weights in tests/shard_weights.txt, slowest first, so that the shares take about the same time.

func _initialize() -> void:
	# A script error inside _run makes it return the default for its type, which is false.
	# That has to read as a failed run, so _run reports success as true and nothing else.
	var passed := await _run(OS.get_cmdline_user_args())
	quit(0 if passed else 1)


func _run(args: PackedStringArray) -> bool:
	var filter := ""
	var files := PackedStringArray()
	var include_render := false
	var expect_method := ""
	var shard := Vector2i(1, 1)
	for arg in args:
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--files="):
			files = arg.trim_prefix("--files=").split(",", false)
		elif arg.begins_with("--expect-method="):
			expect_method = arg.trim_prefix("--expect-method=")
		elif arg == "--render" or arg == "--forward-plus":
			include_render = true
		elif arg.begins_with("--shard="):
			shard = TestRunner.shard_of(arg.trim_prefix("--shard="))
			if shard == Vector2i.ZERO:
				printerr("run.gd: '%s' is not a shard (--shard=<i>/<n>, i from 1 to n)" % arg)
				return false
		elif arg != "--update-golden":
			printerr("run.gd: unknown argument '%s'" % arg)
			return false

	if expect_method != "":
		var method := RenderingServer.get_current_rendering_method()
		if method != expect_method:
			print("FAIL rendering method: expected %s, got %s" % [expect_method, method])
			return false

	if files.is_empty():
		files = TestRunner.discover("res://tests", include_render)
	files = TestRunner.shard_for_run(files, shard.x, shard.y)
	var runner := TestRunner.new()
	var total := TestReport.new()
	for path in files:
		var began := Time.get_ticks_msec()
		var report: TestReport = await runner.run_files([path], filter)
		var took := (Time.get_ticks_msec() - began) / 1000.0
		for result in report.results:
			if result.ok:
				print("PASS %s" % result.id)
			else:
				print("FAIL %s: %s" % [result.id, result.message])
		if not report.results.is_empty():
			print(TestRunner.time_line(path, took))
		total.merge(report)

	print("%d passed, %d failed" % [total.passed, total.failed])
	if total.passed + total.failed == 0:
		print("no tests ran")
		return false
	return total.failed == 0
