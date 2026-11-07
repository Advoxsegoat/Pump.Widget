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
