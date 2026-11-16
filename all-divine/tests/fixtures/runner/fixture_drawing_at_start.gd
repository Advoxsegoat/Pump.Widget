extends TestCase
## What a file finds when it begins, whatever ran before it in the same process: the drawing is on.

func test_the_drawing_is_on() -> void:
	assert_true(RenderingServer.render_loop_enabled, "a file begins with the drawing on")
