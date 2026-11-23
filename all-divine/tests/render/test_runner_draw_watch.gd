extends TestCase
## A test outside tests/render that awaits a drawn frame (RenderingServer.frame_post_draw) is played with the drawing off, so the frame
## never comes and the run stood still until its timeout. The runner must fail it at once, with a line that says what to do. The file is
## made here, outside tests/render and without DRAWS, and played by a runner of its own (--render), under `timeout` so that a hang is
## a number and not a stopped run.

const FILE := "user://runner_draw_watch_fixture.gd"
const LIMIT := 40
const SOURCE := """extends TestCase

func test_awaits_a_drawn_frame() -> void:
	await RenderingServer.frame_post_draw
	assert_true(true)


func test_after_it_still_runs() -> void:
	assert_eq(1, 1)
"""


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


func test_a_test_that_awaits_a_drawn_frame_outside_tests_render_fails_at_once_instead_of_hanging() -> void:
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	file.store_string(SOURCE)
	file.close()
	var argv := PackedStringArray(["-k", "5", str(LIMIT), OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60",
			"-s", "res://tools/test/run.gd", "--", "--render", "--files=" + FILE])
	var output: Array = []
	var code := OS.execute("timeout", argv, output, true)
	var text := "\n".join(PackedStringArray(output))
	assert_true(code != 124 and code != 137, "the run ended by itself, it did not hang to the timeout (exit %d): %s" % [code, text])
	assert_eq(code, 1, "and it failed: %s" % text)
	assert_true(text.contains("test_awaits_a_drawn_frame: this test awaits a drawn frame but its file is not under tests/render and does not say DRAWS"),
			"with a line that names the test and says what to do: %s" % text)
	assert_true(text.contains("PASS " + FILE + "::test_after_it_still_runs"), "and the next test still runs: %s" % text)
