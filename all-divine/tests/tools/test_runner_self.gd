extends TestCase

const F := "res://tests/fixtures/runner/"

func test_counts_passes_failures_and_errors() -> void:
	var r: TestReport = await TestRunner.new().run_files([F + "fixture_pass.gd", F + "fixture_fail.gd", F + "fixture_error.gd", F + "fixture_await.gd"])
	assert_eq(r.passed, 4)
	assert_eq(r.failed, 3)
	var failure: Dictionary = r.results.filter(func(x): return x.id.ends_with("::test_fails"))[0]
	assert_true(failure.message.contains("expected 2, got 1"), failure.message)

func test_filter_selects_one_test() -> void:
	var r: TestReport = await TestRunner.new().run_files([F + "fixture_pass.gd"], "fixture_pass.gd::test_a")
	assert_eq([r.passed, r.failed], [1, 0])

func test_discover_skips_fixtures_and_render() -> void:
	var files := TestRunner.discover()
	assert_true(files.has("res://tests/tools/test_runner_self.gd"))
	assert_false(Array(files).any(func(p): return p.contains("/fixtures/") or p.contains("/render/")))
