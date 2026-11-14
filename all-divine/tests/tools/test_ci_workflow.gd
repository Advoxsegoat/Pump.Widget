extends TestCase
## The CI workflow (.github/workflows/all-divine.yml, at the repository root, outside res://).
##
## - The builds wait for the headless tests and the clip checker (the export job needs the test job): the spec
##   says the build fails when the clip checker fails.
## - The three builds are uploaded before the Linux build is run, so a stray log line in a run check cannot
##   withhold the Windows build; the job still fails on it.
## - The workflow's token can only read the repository.
##
## The file is read as lines: a top-level key has no indent, a job two spaces, a job's key four, and a step
## starts with "      - ".

const WORKFLOW := "../.github/workflows/all-divine.yml"
## The steps of the export job that run the Linux build.
const RUN_CHECKS: PackedStringArray = ["Self-test of the Linux build", "The Linux build starts and quits cleanly"]


func test_the_token_only_reads() -> void:
	var lines := _lines()
	var block := _block(lines, "permissions:", 0)
	assert_eq(block, PackedStringArray(["  contents: read"]), "a top-level permissions block with contents: read and nothing else")


func test_the_builds_wait_for_the_tests() -> void:
	var export_job := _block(_lines(), "  export:", 2)
	assert_false(export_job.is_empty(), "there is an export job")
	assert_true(export_job.has("    needs: [test]"), "the export job needs the test job (headless suite and clip checker)")


func test_the_headless_job_plays_the_combat_bot_over_two_seeds() -> void:
	var steps := _steps(_block(_lines(), "  test:", 2))
	var bot: Array = Array(steps).filter(func(text: String) -> bool: return text.contains("name: Combat bot\n"))
	assert_eq(bot.size(), 1, "the headless job has a bot step")
	if bot.size() == 1:
		assert_true(bot[0].contains("run_bot.gd -- --seeds=1-2 --frames=3600 --policy=mixed"), "seeds 1 and 2, 3,600 frames, the mixed policy: %s" % bot[0])


func test_the_headless_job_also_plays_the_counter_policy() -> void:
	var steps := _steps(_block(_lines(), "  test:", 2))
	var bot: Array = Array(steps).filter(func(text: String) -> bool: return text.contains("name: Combat bot, the other policies"))
	assert_eq(bot.size(), 1, "a second bot step, for what the suite is too short to hold")
	if bot.size() == 1:
		assert_true(bot[0].contains("--policy=counter"), bot[0])


func test_the_builds_are_uploaded_before_the_linux_build_runs() -> void:
	var steps := _steps(_block(_lines(), "  export:", 2))
	var uploads: Array[int] = []
	var checks: Array[int] = []
	for i in steps.size():
		var text := steps[i]
		if text.contains("uses: actions/upload-artifact@"):
			uploads.append(i)
		for check in RUN_CHECKS:
			if text.contains("name: " + check):
				checks.append(i)
	assert_eq(uploads.size(), 3, "three uploads: Linux, Windows, Web")
	assert_eq(checks.size(), RUN_CHECKS.size(), "both run checks are there")
	if uploads.is_empty() or checks.is_empty():
		return
	assert_true(uploads.max() < checks.min(), "every upload (steps %s) comes before the run checks (steps %s)" % [uploads, checks])


func test_the_render_job_runs_the_whole_suite_in_shards() -> void:
	# A software renderer draws every frame of every test, so the suite is split over parallel jobs: the matrix
	# must name every shard from 1 to n, and the run line must pass each one of the same n.
	var job := _block(_lines(), "  render:", 2)
	assert_false(job.is_empty(), "there is a render job")
	var shards := PackedStringArray()
	var count := ""
	for line in job:
		var body := line.strip_edges()
		if body.begins_with("shard: ["):
			shards = body.trim_prefix("shard: [").trim_suffix("]").replace(" ", "").split(",")
		if body.begins_with("run: tools/test.sh --render --shard=${{ matrix.shard }}/"):
			count = body.get_slice("/", body.get_slice_count("/") - 1)
	assert_true(shards.size() >= 2, "the matrix lists the shards (%s)" % [shards])
	assert_eq(count, str(shards.size()), "the run line splits the suite into as many shards as the matrix lists")
	for i in shards.size():
		assert_eq(shards[i], str(i + 1), "the shards are 1 to %d, each once" % shards.size())
	assert_true(job.has("      fail-fast: false"), "one shard failing does not stop the others")


func test_the_python_tools_step_installs_the_pinned_libraries_and_runs_the_portrait_tests() -> void:
	# The sketch tool needs Pillow and numpy, which the runner's own Python may not have: the step installs them at the
	# versions the tool was made with, before it runs the tool's tests.
	var steps := _steps(_block(_lines(), "  test:", 2))
	var found := ""
	for step in steps:
		if step.contains("name: Python tools' tests"):
			found = step
	assert_false(found.is_empty(), "the headless job has a Python tools' step")
	var install := found.find("python3 -m pip install --quiet pillow==12.3.0 numpy==2.5.3")
	var portraits := found.find("python3 -I -m unittest discover -s tools/portraits/tests")
	assert_true(install >= 0, "the step installs pillow==12.3.0 and numpy==2.5.3")
	assert_true(portraits >= 0, "the step runs the portrait tests")
	assert_true(install < portraits, "the libraries are installed before the portrait tests run")


func _lines() -> PackedStringArray:
	var path := ProjectSettings.globalize_path("res://").path_join(WORKFLOW).simplify_path()
	assert_true(FileAccess.file_exists(path), "%s is there" % path)
	return FileAccess.get_file_as_string(path).split("\n")


# The lines under `header` (a line at `indent` spaces), up to the next line at that indent or less.
# Blank lines and comments are left out.
func _block(lines: PackedStringArray, header: String, indent: int) -> PackedStringArray:
	var found := PackedStringArray()
	var inside := false
	for line in lines:
		var body := line.strip_edges()
		if body.is_empty() or body.begins_with("#"):
			continue
		var depth := line.length() - line.lstrip(" ").length()
		if inside and depth <= indent:
			break
		if inside:
			found.append(line.rstrip(" "))
		elif depth == indent and line.rstrip(" ") == header:
			inside = true
	return found


# A job's steps, each as its lines joined by newlines.
func _steps(job: PackedStringArray) -> PackedStringArray:
	var steps := PackedStringArray()
	var inside := false
	for line in job:
		if line == "    steps:":
			inside = true
		elif inside and line.begins_with("      - "):
			steps.append(line)
		elif inside and line.begins_with("        ") and not steps.is_empty():
			steps[-1] += "\n" + line
		elif inside and not line.begins_with("      "):
			inside = false
	return steps
