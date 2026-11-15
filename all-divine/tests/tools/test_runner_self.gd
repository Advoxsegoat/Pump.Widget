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


func test_shards_split_the_files_between_them_and_miss_none() -> void:
	var files := PackedStringArray()
	for i in 10:
		files.append("suite/x/test_%02d.gd" % i)
	var seen := {}
	for index in [1, 2, 3]:
		var part := TestRunner.shard(files, index, 3)
		assert_true(part.size() >= 3 and part.size() <= 4, "shard %d of 3 holds its share of ten files (%d)" % [index, part.size()])
		for path in part:
			assert_false(seen.has(path), "%s is in one shard only" % path)
			seen[path] = true
	assert_eq(seen.size(), 10, "the three shards hold every file between them")
	assert_eq(TestRunner.shard(files, 1, 3), PackedStringArray([files[0], files[3], files[6], files[9]]), "a shard takes every third file, so neighbours (the slow files of one folder) are spread")
	assert_eq(TestRunner.shard(files, 1, 1), files, "one shard of one is every file")


# CI's render shards each have a cap of seconds. Dealt every n-th, three slow files can land in one shard (they did: 1,770 s in
# one shard of five against 630 in the next, and the cap is 1,800); dealt by weight, the slow files are spread and the shards
# come out even.
func _twelve() -> PackedStringArray:
	var files := PackedStringArray()
	for i in 12:
		files.append("res://tests/x/test_%02d.gd" % i)
	return files


func _load(part: PackedStringArray, weights: Dictionary) -> float:
	var total := 0.0
	for path in part:
		total += float(weights.get(path, TestRunner.DEFAULT_WEIGHT))
	return total


func test_weighted_shards_put_the_slow_files_in_different_shards_and_miss_none() -> void:
	var files := _twelve()
	# every third file is slow: the plain split puts all three in shard 1
	var weights := {files[0]: 500.0, files[3]: 300.0, files[6]: 250.0}
	var shard_of := {}
	var loads: Array[float] = []
	for index in [1, 2, 3]:
		var part := TestRunner.shard(files, index, 3, weights)
		loads.append(_load(part, weights))
		var sorted_part := Array(part)
		sorted_part.sort()
		assert_eq(Array(part), sorted_part, "shard %d runs its files in the suite's own order" % index)
		for path in part:
			assert_false(shard_of.has(path), "%s is in one shard only" % path)
			shard_of[path] = index
	assert_eq(shard_of.size(), 12, "the three shards hold every file between them")
	var slow := [shard_of.get(files[0], 0), shard_of.get(files[3], 0), shard_of.get(files[6], 0)]
	slow.sort()
	assert_eq(slow, [1, 2, 3], "the three slow files are in three shards")
	assert_true(loads.max() <= 500.0 + 3 * TestRunner.DEFAULT_WEIGHT, "no shard holds more than the slowest file and a few quick ones (%s)" % [loads])
	assert_true(loads.max() - loads.min() <= 260.0, "the quick files go where the load is least (%s)" % [loads])


func test_weighted_shards_are_the_same_split_every_time_and_plain_without_weights() -> void:
	var files := _twelve()
	var weights := {files[1]: 90.0, files[2]: 90.0, files[7]: 40.0}  # two of a weight: the path settles which goes first
	for index in [1, 2, 3, 4]:
		assert_eq(TestRunner.shard(files, index, 4, weights), TestRunner.shard(files, index, 4, weights.duplicate()), "shard %d of 4 twice" % index)
	assert_true(TestRunner.shard(files, 1, 4, weights) != TestRunner.shard(files, 1, 4), "weights change the split")
	assert_eq(TestRunner.shard(files, 2, 3, {}), TestRunner.shard(files, 2, 3), "no weights: every third file, as before")
	assert_eq(TestRunner.shard(files, 5, 4, weights), PackedStringArray(), "a shard that does not exist holds nothing, weights or not")


const WEIGHTS_FIXTURE := "user://shard_weights_fixture.txt"

func test_weights_are_read_from_a_file_of_seconds_and_paths() -> void:
	var file := FileAccess.open(WEIGHTS_FIXTURE, FileAccess.WRITE)
	file.store_string("# seconds, then the file under tests/\n\n 575 story/test_cine_camera.gd   # from a CI log\n40 actors/test_drummer.gd\nnot a line\n-3 x/test_minus.gd\n")
	file.close()
	var weights := TestRunner.read_weights(WEIGHTS_FIXTURE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WEIGHTS_FIXTURE))
	assert_eq(weights.size(), 2, "two lines name a weight: %s" % [weights])
	assert_eq(weights.get("res://tests/story/test_cine_camera.gd", 0.0), 575.0)
	assert_eq(weights.get("res://tests/actors/test_drummer.gd", 0.0), 40.0)
	assert_eq(TestRunner.read_weights("user://no_such_weights.txt"), {}, "no file: no weights, and the split is the plain one")


func test_a_run_of_the_suite_is_dealt_by_the_weights_file() -> void:
	var files := TestRunner.discover("res://tests", true)
	var slow := ["res://tests/story/test_cine_camera.gd", "res://tests/bot/test_combat_bot.gd", "res://tests/actors/test_enemy_brain.gd"]
	var where := {}
	var seen := 0
	for index in range(1, 6):
		var part := TestRunner.shard_for_run(files, index, 5)
		seen += part.size()
		for path in slow:
			if part.has(path):
				where[path] = index
	assert_eq(seen, files.size(), "the five shards hold every file between them")
	var shards := where.values()
	shards.sort()
	assert_eq(where.size(), 3, "the three slowest files are in the suite (%s)" % [where])
	assert_true(shards.size() == 3 and shards[0] != shards[1] and shards[1] != shards[2], "and no two of them share a shard (%s)" % [where])
	var source := FileAccess.get_file_as_string("res://tools/test/run.gd")
	assert_true(source.contains("TestRunner.shard_for_run(files, shard.x, shard.y)"), "run.gd deals its files with shard_for_run")


func test_every_weight_names_a_test_file_that_is_there() -> void:
	var weights := TestRunner.read_weights(TestRunner.WEIGHTS)
	assert_true(weights.size() >= 20, "tests/shard_weights.txt names the slow files (%d)" % weights.size())
	var gone := PackedStringArray()
	for path: String in weights:
		if not FileAccess.file_exists(path):
			gone.append(path)
	assert_eq(gone, PackedStringArray(), "a weight for a file that is gone (take its line out of tests/shard_weights.txt)")


func test_a_shard_that_does_not_exist_holds_nothing() -> void:
	var files := PackedStringArray(["suite/x/test_a.gd", "suite/x/test_b.gd"])
	for bad: Array in [[0, 3], [4, 3], [1, 0], [-1, 2]]:
		assert_eq(TestRunner.shard(files, bad[0], bad[1]), PackedStringArray(), "shard %d of %d" % bad)


func test_shard_argument_is_read_as_index_of_count() -> void:
	assert_eq(TestRunner.shard_of("2/3"), Vector2i(2, 3))
	assert_eq(TestRunner.shard_of("1/1"), Vector2i(1, 1))
	for bad in ["", "2", "0/3", "4/3", "a/b", "2/3/4", "2/0", "-1/3"]:
		assert_eq(TestRunner.shard_of(bad), Vector2i.ZERO, "'%s' is not a shard" % bad)

