extends SceneTree
## Test entry point:
##   godot --headless --fixed-fps 60 -s res://tools/test/run.gd -- [--filter=<s>] [--files=<a.gd,b.gd>]
##         [--render|--forward-plus] [--update-golden] [--expect-method=<rendering method>]
## Prints PASS <id> or FAIL <id>: <message> per test, then "N passed, M failed".
## Exits 1 if anything failed or no test ran. tools/test.sh is the usual way to call it.
## --files runs exactly the listed test files (comma-separated res:// paths) instead of discovering them.

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
	for arg in args:
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--files="):
			files = arg.trim_prefix("--files=").split(",", false)
		elif arg.begins_with("--expect-method="):
			expect_method = arg.trim_prefix("--expect-method=")
		elif arg == "--render" or arg == "--forward-plus":
			include_render = true
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
	var runner := TestRunner.new()
	var total := TestReport.new()
	for path in files:
		var report: TestReport = await runner.run_files([path], filter)
		for result in report.results:
			if result.ok:
				print("PASS %s" % result.id)
			else:
				print("FAIL %s: %s" % [result.id, result.message])
		total.merge(report)

	print("%d passed, %d failed" % [total.passed, total.failed])
	if total.passed + total.failed == 0:
		print("no tests ran")
		return false
	return total.failed == 0
