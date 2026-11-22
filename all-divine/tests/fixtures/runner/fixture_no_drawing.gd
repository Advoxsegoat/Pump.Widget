extends TestCase
## A file that looks at no picture: the runner plays it with the drawing off.

const DRAWS := false


func test_the_drawing_is_off_while_this_file_plays() -> void:
	assert_false(RenderingServer.render_loop_enabled, "a file with DRAWS false is played with the drawing off")
