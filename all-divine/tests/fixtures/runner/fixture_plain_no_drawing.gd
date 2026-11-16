extends TestCase
## A file outside tests/render/ that says nothing: it is played as the headless job plays it, with nothing drawn.

func test_the_drawing_is_off_for_a_file_that_looks_at_no_picture() -> void:
	assert_false(RenderingServer.render_loop_enabled, "a file outside tests/render/ is played with the drawing off unless it asks")
