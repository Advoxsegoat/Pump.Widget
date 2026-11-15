extends TestCase
## The storyboard and animatic tools run the way the owner runs them (a Godot inside the test's Godot, under the same display):
## `tools/storyboard.sh` on the fixture gives a frame a shot at exactly 640 by 360 and the sheet's pages; `tools/animatic.sh` gives a
## video of the right length. The fixture is shot once and the tests share what it made. Needs a display (render run); the
## animatic needs ffmpeg and says so when it is not there.

const SCENE := "fixture_yard_entrance"
const SHOT_LIMIT := 400
## The animatic's length: the scene is 360 frames from the glide in to the glide home, and the tool lets it run 60 more (a second
## of the world after the hand-back); the 30 frames' wait before the scene is cut. At 60 a second.
const ANIMATIC_SECONDS := 7.0

var _temp := ""
var _board := {}
var _video := {}


func _exit_tree() -> void:
	_remove(_temp)


func _root() -> String:
	return ProjectSettings.globalize_path("res://")


func _remove(path: String) -> void:
	if path == "" or not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove(path.path_join(dir))
	DirAccess.remove_absolute(path)


# Runs tools/<script> with `args` (and STORY_EMPTY=1, which has the storyboard tool also save each frame without Abarax in it, and
# `env`'s KEY=VALUE pairs); {code, text}.
func _run(script: String, args: PackedStringArray, env := PackedStringArray()) -> Dictionary:
	var argv := PackedStringArray(["-k", "10", str(SHOT_LIMIT), "env", "STORY_EMPTY=1"])
	argv.append_array(env)
	argv.append(_root().path_join("tools").path_join(script))
	argv.append_array(args)
	var output := []
	var code := OS.execute("timeout", argv, output, true)
	return {code = code, text = "\n".join(output).strip_edges()}


func _out() -> String:
	if _temp == "":
		_temp = ProjectSettings.globalize_path("user://story_shots_%d" % OS.get_process_id())
		_remove(_temp)
	return _temp


# The storyboard tool's run on the fixture, once for the whole file.
func _storyboard() -> Dictionary:
	if _board.is_empty():
		_board = _run("storyboard.sh", PackedStringArray([SCENE, _out().path_join("board")]))
	return _board


func _frame(i: int) -> Image:
	return Image.load_from_file(_out().path_join("board/frames/shot-%02d.png" % i))


func _ffmpeg() -> bool:
	return OS.execute("sh", ["-c", "command -v ffmpeg ffprobe >/dev/null"]) == 0


func test_the_storyboard_tool_writes_a_frame_per_shot_of_exactly_640_by_360() -> void:
	var run := _storyboard()
	assert_eq(run.code, 0, run.text)
	for i in range(1, 5):
		var image := _frame(i)
		assert_true(image != null, "frame %d is there" % i)
		if image != null:
			assert_eq(image.get_size(), Vector2i(640, 360), "frame %d is the exact window picture" % i)
	assert_false(run.text.contains("ERROR") or run.text.contains("WARNING"), run.text)


func test_the_frames_show_the_framings() -> void:
	_storyboard()
	var body: Array[int] = []   # the pixels of Abarax and his shadow in each frame: those that differ from the same frame without him
	for i in range(1, 5):
		var image := _frame(i)
		var empty := Image.load_from_file(_out().path_join("board/frames/empty-%02d.png" % i)) if FileAccess.file_exists(_out().path_join("board/frames/empty-%02d.png" % i)) else null
		assert_true(image != null and empty != null, "frame %d and its empty twin are there" % i)
		if image == null or empty == null:
			return
		body.append(_differing(image, empty))
	assert_true(body[2] >= int(1.8 * body[0]), "the CLOSE shot's Abarax (%d px) is at least 1.8 times the WIDE shot's (%d px)" % [body[2], body[0]])
	assert_true(body[0] > 100, "he is there in the wide shot (%d px)" % body[0])
	for i in range(1, 5):
		for j in range(i + 1, 5):
			var a := _frame(i)
			var b := _frame(j)
			if a != null and b != null:
				assert_true(_differing(a, b) > 2000, "frame %d is not blank or the same as frame %d" % [i, j])


func test_playing_the_scene_undrawn_between_the_key_frames_takes_the_pictures_of_drawing_every_frame() -> void:
	# The storyboard plays the scene with the render loop off and draws a key frame and its neighbours only (a long scene would take
	# a quarter of an hour otherwise); the pictures must be what a run that draws every tick takes, byte for byte.
	_storyboard()
	var full := _run("storyboard.sh", PackedStringArray([SCENE, _out().path_join("full")]), PackedStringArray(["STORY_DRAW_ALL=1"]))
	assert_eq(full.code, 0, full.text)
	for i in range(1, 5):
		var name := "frames/shot-%02d.png" % i
		var lazy := FileAccess.get_file_as_bytes(_out().path_join("board").path_join(name))
		var every := FileAccess.get_file_as_bytes(_out().path_join("full").path_join(name))
		assert_true(lazy.size() > 1000, "frame %d is there" % i)
		assert_true(lazy == every, "frame %d is the same picture drawn lazily and drawn every tick (%d and %d bytes)" % [i, lazy.size(), every.size()])


func test_no_frame_is_black_and_the_mini_has_no_bars() -> void:
	_storyboard()
	for i in range(1, 5):
		var image := _frame(i)
		if image == null:
			fail("frame %d is missing" % i)
			continue
		for y in [90, 180, 270]:
			assert_true(_row_brightness(image, y) > 0.04, "frame %d is not black on row %d" % [i, y])
		for y in [0, 359]:
			assert_true(_row_distinct_colours(image, y) > 4, "frame %d: row %d is the world's, not a bar" % [i, y])


func test_the_page_is_made_and_the_animatic_has_the_right_length() -> void:
	var board := _storyboard()
	assert_eq(board.code, 0, board.text)
	var page := Image.load_from_file(_out().path_join("board/storyboard-1.png"))
	assert_true(page != null, "storyboard-1.png is there")
	if page != null:
		assert_eq(page.get_width(), 1280)
		assert_true(page.get_height() > 1000, "three rows tall")
	if not _ffmpeg():
		print("SKIPPED the animatic half of test_the_page_is_made_and_the_animatic_has_the_right_length: ffmpeg is not installed here")
		return
	var run := _run("animatic.sh", PackedStringArray([SCENE, _out().path_join("video")]))
	assert_eq(run.code, 0, run.text)
	var video := _out().path_join("video/animatic.mp4")
	assert_true(FileAccess.file_exists(video), "animatic.mp4 is there")
	var out := []
	OS.execute("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video], out, true)
	var seconds := String("".join(out)).strip_edges().to_float()
	assert_true(seconds >= 5.5 and seconds < 8.0, "the video is %.2f s long" % seconds)
	assert_near(seconds, ANIMATIC_SECONDS, 0.4)


# How many pixels of `a` differ from `b` (by more than 0.06 summed over red, green and blue).
func _differing(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06:
				count += 1
	return count


func _row_brightness(image: Image, y: int) -> float:
	var total := 0.0
	for x in image.get_width():
		var c := image.get_pixel(x, y)
		total += (c.r + c.g + c.b) / 3.0
	return total / float(image.get_width())


func _row_distinct_colours(image: Image, y: int) -> int:
	var seen := {}
	for x in image.get_width():
		seen[image.get_pixel(x, y).to_html(false)] = true
	return seen.size()
