extends TestCase

const F := "res://tests/fixtures/runner/"

func test_counts_passes_failures_and_errors() -> void:
	# pass, fail and await run in this process; none of them makes the engine print an error.
	var r: TestReport = await TestRunner.new().run_files([F + "fixture_pass.gd", F + "fixture_fail.gd", F + "fixture_await.gd"])
	assert_eq(r.passed, 3)
	assert_eq(r.failed, 1)
	var failure: Dictionary = r.results.filter(func(x): return x.id.ends_with("::test_fails"))[0]
	assert_true(failure.message.contains("expected 2, got 1"), failure.message)

	# fixture_error calls push_error on purpose, and the engine prints every push_error to stderr,
	# so it runs in a child Godot whose output is captured here instead of showing up in the run.
	var child := _run_in_child("res://tools/test/run.gd", ["--files=" + F + "fixture_error.gd"])
	assert_eq(child.code, 1)
	assert_true(child.lines.has("PASS " + F + "fixture_error.gd::test_expected_error"), "\n".join(child.lines))
	assert_true(_has_line_starting(child.lines, "FAIL " + F + "fixture_error.gd::test_unexpected_error: unexpected error: boom"), "\n".join(child.lines))
	assert_true(_has_line_starting(child.lines, "FAIL " + F + "fixture_error.gd::test_missing_expected_error: expected an error containing \"never\""), "\n".join(child.lines))
	assert_true(child.lines.has("1 passed, 2 failed"), "\n".join(child.lines))

	# A script error inside the runner itself must exit non-zero, not read as a clean run.
	var crashed := _run_in_child(F + "run_crashes.gd", [])
	assert_eq(crashed.code, 1, "\n".join(crashed.lines))

func test_filter_selects_one_test() -> void:
	var r: TestReport = await TestRunner.new().run_files([F + "fixture_pass.gd"], "fixture_pass.gd::test_a")
	assert_eq([r.passed, r.failed], [1, 0])

func test_discover_skips_fixtures_and_render() -> void:
	var files := TestRunner.discover()
	assert_true(files.has("res://tests/tools/test_runner_self.gd"))
	assert_false(Array(files).any(func(p): return p.contains("/fixtures/") or p.contains("/render/")))

# Runs `script` as the main loop of a headless child Godot on this project. Returns {code, lines}.
func _run_in_child(script: String, args: Array[String]) -> Dictionary:
	var argv := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "-s", script, "--"])
	argv.append_array(PackedStringArray(args))
	var output := []
	var code := OS.execute(OS.get_executable_path(), argv, output, true)
	return {"code": code, "lines": str(output[0]).split("\n")}

func _has_line_starting(lines: PackedStringArray, prefix: String) -> bool:
	return Array(lines).any(func(line: String) -> bool: return line.begins_with(prefix))
