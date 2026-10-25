extends SceneTree
## Test entry point:
##   godot --headless --fixed-fps 60 -s res://tools/test/run.gd -- [--filter=<s>] [--render|--forward-plus]
##         [--update-golden] [--expect-method=<rendering method>]
## Prints PASS <id> or FAIL <id>: <message> per test, then "N passed, M failed".
## Exits 1 if anything failed or no test ran. tools/test.sh is the usual way to call it.

func _initialize() -> void:
	quit(await _run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var filter := ""
	var include_render := false
	var expect_method := ""
	for arg in args:
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--expect-method="):
			expect_method = arg.trim_prefix("--expect-method=")
		elif arg == "--render" or arg == "--forward-plus":
			include_render = true
		elif arg != "--update-golden":
			printerr("run.gd: unknown argument '%s'" % arg)
			return 2

	if expect_method != "":
		var method := RenderingServer.get_current_rendering_method()
		if method != expect_method:
			print("FAIL rendering method: expected %s, got %s" % [expect_method, method])
			return 1

	var runner := TestRunner.new()
	var total := TestReport.new()
	for path in TestRunner.discover("res://tests", include_render):
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
		return 1
	return 1 if total.failed > 0 else 0
