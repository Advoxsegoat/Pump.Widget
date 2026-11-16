extends TestCase
## A file that asks for the drawing (the renderer's smoke tests do): it has it, whatever the file before it was played with.

const DRAWS := true


func test_the_drawing_is_on() -> void:
	assert_true(RenderingServer.render_loop_enabled, "a file that says DRAWS true is played with the drawing on")
