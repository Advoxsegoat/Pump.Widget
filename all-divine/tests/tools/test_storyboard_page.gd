extends TestCase
## The storyboard sheet's words and layout (headless, pure): what each shot's row says in words a script would use, which frame of the
## shot is photographed, and where the frames and text go on the pages.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


func test_the_text_for_each_fixture_shot_names_framing_move_action_line_sound_and_timing() -> void:
	var scene := _fixture()
	assert_eq(StoryboardPage.ShotText.describe(scene, 1), PackedStringArray([
		"S2   MEDIUM, the camera pushes in, from medium to close   (DOLLY 2>3)",
		"1.00 s long   ·   1.50 s to 2.50 s   (frames 90 to 150)",
		"picture: 0.50 s into the shot (the middle)",
		"ACTION: He stops and folds his arms",
		"CAMERA: Medium (people from about the waist up), looking at Knuckle. The camera pushes in, from medium to close. It cuts in from the last shot.",
		"DOES: Knuckle plays the clip knuckle_idle, repeating (at the start)",
		"DOES: Abarax plays the clip guard_raise (at the start)",
		"DOES: Abarax plays the clip guard_hold, repeating (at +0.23 s)",
		"SOUND: cloth_move, heard at Knuckle (at the start)",
		"FOCUS: sharp on Knuckle",
	]))
	assert_eq(StoryboardPage.ShotText.describe(scene, 2), PackedStringArray([
		"S3   CLOSE, the camera holds still   (STATIC)",
		"1.00 s long   ·   2.50 s to 3.50 s   (frames 150 to 210)",
		"picture: 0.57 s into the shot (the line just typed)",
		"ACTION: A line",
		"CAMERA: Close (one person or detail filling the picture), looking at Abarax. The camera holds still. It cuts in from the last shot.",
		"SAYS: Fixture Knuckle (Gold Tooth's look): \"Fixture line one.\" (at the start, on screen 0.90 s)  [STAND-IN: the portrait of Fixture Knuckle (Gold Tooth's look) is not drawn yet, so a plain card shows]",
		"MUSIC: fixture_sting starts (at the start)",
		"FOCUS: sharp on Abarax",
	]))


func test_the_first_shot_says_where_the_camera_turns_and_the_walk_in_words() -> void:
	var text := StoryboardPage.ShotText.describe(_fixture(), 0)
	assert_eq(text.size() > 5, true, "S1 has its rows: %s" % [text])
	if text.size() > 5:
		assert_eq(text[0], "S1   WIDE, the camera turns from Abarax to the foe stop mark   (PAN Abarax>foe stop)")
		assert_eq(text[4], "CAMERA: Wide (everyone and the ground round them), looking at Abarax. The camera turns from Abarax to the foe stop mark.")
		assert_eq(text[5], "DOES: Knuckle walks to the foe stop mark (at the start)")


func test_a_placeholder_clip_is_marked_on_the_row_it_belongs_to() -> void:
	var scene := _fixture()
	scene.shots[1].beats[0].placeholder = true
	var text := StoryboardPage.ShotText.describe(scene, 1)
	assert_true("\n".join(text).contains("DOES: Knuckle plays the clip knuckle_idle, repeating (at the start)  [PLACEHOLDER: this clip is not made yet, so Knuckle just stands]"), "\n".join(text))


func test_the_key_frame_defaults_to_the_middle_and_is_clamped_inside_the_shot() -> void:
	var shot := Shot.new()
	shot.length = 60
	assert_eq(StoryboardPage.ShotText.key_frame(shot), 30, "-1 is the middle")
	shot.key_frame = 500
	assert_eq(StoryboardPage.ShotText.key_frame(shot), 59, "500 is the last frame")
	shot.key_frame = 12
	assert_eq(StoryboardPage.ShotText.key_frame(shot), 12, "the data's own frame wins")
	shot.key_frame = -1
	shot.length = 61
	assert_eq(StoryboardPage.ShotText.key_frame(shot), 30)


func test_a_shot_with_a_line_is_photographed_when_the_line_is_typed_and_the_data_still_wins() -> void:
	var scene := _fixture()
	var s3 := scene.shots[2]
	assert_eq(StoryboardPage.ShotText.key_frame(s3, scene), 34, "17 characters at 2 frames each")
	s3.key_frame = 5
	assert_eq(StoryboardPage.ShotText.key_frame(s3, scene), 5)
	var s4 := scene.shots[3]
	assert_eq(StoryboardPage.ShotText.key_frame(s4, scene), 34)
	s4.lines[0].at = 40
	assert_eq(StoryboardPage.ShotText.key_frame(s4, scene), 59, "typed after the shot ends: its last frame")


func test_a_shot_whose_walk_arrives_is_photographed_when_the_body_is_at_rest() -> void:
	var scene := _fixture()
	var arrives := StoryboardPage.ShotText.key_frame(scene.shots[0], scene)
	assert_true(arrives > 45 and arrives < 90, "S1's 1 m walk arrives well after the middle and before the shot's end: %d" % arrives)
	assert_eq(arrives, StoryWalk.frames(scene.cast_entry(&"knuckle").def.locomotion, ActorBeat.Pace.WALK, 1.0))
	assert_eq(StoryboardPage.ShotText.key_frame(scene.shots[1], scene), 30, "S2 has no line and no walk: the middle")


func test_the_key_frames_are_distinct_frames_of_the_scene() -> void:
	var scene := _fixture()
	var frames := StoryboardPage.ShotText.key_frames(scene)
	assert_eq(frames.size(), 4)
	for i in frames.size():
		assert_true(frames[i] >= scene.shots[i].start and frames[i] < scene.shots[i].start + scene.shots[i].length, "frame %d is inside shot %d" % [frames[i], i])
		assert_true(frames[i] < scene.length())
		if i > 0:
			assert_true(frames[i] > frames[i - 1], "increasing")


func test_the_layout_is_three_rows_a_page_with_frames_at_one_to_one() -> void:
	var boxes := StoryboardPage.layout(4)
	assert_eq(boxes.size(), 4)
	var pages := {}
	for box in boxes:
		pages[box.page] = true
	assert_eq(pages.size(), 2, "four shots at three a page: two pages")
	for i in boxes.size():
		var rect: Rect2i = boxes[i].rect
		assert_eq(rect.size, Vector2i(640, 360), "1:1, no scaling")
		assert_true(rect.position.x >= 0 and rect.end.x <= StoryboardPage.TEXT_X - 16, "clear of the text column and the edge")
		assert_true(rect.position.y >= StoryboardPage.SLIM_HEAD and rect.end.y <= boxes[i].page_size.y, "inside its page")
		for j in i:
			if boxes[j].page == boxes[i].page:
				assert_false(rect.intersects(boxes[j].rect), "frames %d and %d do not overlap" % [j, i])
	assert_eq(boxes[0].page, 1)
	assert_eq(boxes[2].page, 1)
	assert_eq(boxes[3].page, 2)


func test_a_row_with_much_text_takes_a_second_rows_height_and_the_layout_says_so() -> void:
	var scene := _fixture()
	assert_eq(StoryboardPage.row_spans(scene), [1, 1, 1, 1] as Array[int], "the fixture's rows each fit one row")
	var busy := scene.shots[1]
	for i in 6:
		var beat := ActorBeat.new()
		beat.actor = &"knuckle"
		beat.at = 4 + i * 6
		beat.clip = StringName("a_long_clip_name_number_%d" % i)
		beat.move_to = &"foe_stop"
		beat.face = &"abarax"
		beat.look = &"abarax"
		busy.beats.append(beat)
	var line := DialogueLine.new()
	line.speaker = &"abarax"
	line.text = "This is a very long line, said in three rows of the dialogue box, so that the sheet has to show every word of it and still has room. ".repeat(1).substr(0, 150)
	line.at = 2
	busy.lines.append(line)
	var spans := StoryboardPage.row_spans(scene)
	assert_eq(spans[1], 2, "six beats and a three-row line need a second row's height")
	assert_eq(spans[0], 1)
	var boxes := StoryboardPage.layout(4, spans)
	assert_eq(boxes[1].span, 2)
	assert_eq(boxes[1].page, 1)
	assert_eq(boxes[2].page, 2, "the next shot does not fit under it on page 1 (shot 2 holds rows 2 and 3, so the page is full)")
	assert_eq(boxes[3].page, 2)


func test_the_burn_in_names_the_shot_its_framing_move_frame_and_time() -> void:
	var scene := _fixture()
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 90), "S2/4 MEDIUM DOLLY 2>3 f090 0:01.50\nSFX cloth_move")
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 95), "S2/4 MEDIUM DOLLY 2>3 f095 0:01.58\nSFX cloth_move")
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 0), "S1/4 WIDE PAN Abarax>foe stop f000 0:00.00")
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 190), "S3/4 CLOSE STATIC f190 0:03.16\nMUSIC fixture_sting\nSTAND-IN portrait: fixture_knuckle")
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 150 + 59), "S3/4 CLOSE STATIC f209 0:03.48\nMUSIC fixture_sting", "the line is down (54 frames): no stand-in on show")


func test_the_burn_in_says_the_glides_and_when_a_cue_or_a_line_is_over() -> void:
	var scene := _fixture()
	assert_eq(StoryboardPage.ShotText.burn_in(scene, -5), "GLIDE IN")
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 270), "GLIDE OUT")
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 90 + 60), "S3/4 CLOSE STATIC f150 0:02.50\nMUSIC fixture_sting\nSTAND-IN portrait: fixture_knuckle", "S2's sound caption has gone by the next shot")
	assert_eq(StoryboardPage.ShotText.burn_in(scene, 210 + 10), "S4/4 OVER SHOULDER STATIC f220 0:03.66", "the answer has no stand-in on it: Abarax has his drawing")


func test_the_burn_in_lists_a_placeholder_clip_once_it_has_begun() -> void:
	var scene := _fixture()
	scene.shots[1].beats[2].placeholder = true   # guard_hold, at frame 14 of S2
	assert_false(StoryboardPage.ShotText.burn_in(scene, 90 + 13).contains("PLACEHOLDER"), "not before its beat")
	assert_true(StoryboardPage.ShotText.burn_in(scene, 90 + 14).contains("\nPLACEHOLDER guard_hold"), StoryboardPage.ShotText.burn_in(scene, 90 + 14))


# ---- when the picture was taken (fix round 1, item 2) ----

# The row's "picture:" line (empty when the row has none).
func _picture_line(text: PackedStringArray) -> String:
	for line in text:
		if line.begins_with("picture: "):
			return line
	return ""


func test_each_row_says_when_its_picture_was_taken_and_why_that_instant() -> void:
	var scene := _fixture()
	assert_eq(_picture_line(StoryboardPage.ShotText.describe(scene, 0)), "picture: 1.17 s into the shot (the walk's end)", "S1: the Knuckle's walk arrives at frame 70")
	assert_eq(_picture_line(StoryboardPage.ShotText.describe(scene, 1)), "picture: 0.50 s into the shot (the middle)", "S2: no line, no walk")
	assert_eq(_picture_line(StoryboardPage.ShotText.describe(scene, 2)), "picture: 0.57 s into the shot (the line just typed)", "S3: 17 characters at two frames each")
	scene.shots[2].key_frame = 12
	assert_eq(_picture_line(StoryboardPage.ShotText.describe(scene, 2)), "picture: 0.20 s into the shot (chosen in the shot's data)", "the data's own frame says so")


func test_the_picture_line_sits_under_the_times_in_grey() -> void:
	var scene := _fixture()
	var text := StoryboardPage.ShotText.describe(scene, 2)
	assert_eq(text[1].begins_with("1.00 s long"), true)
	assert_eq(text[2].begins_with("picture: "), true, "the third row of text, straight under the times: %s" % [text])
	var blocks := StoryboardPage.blocks_of(text)
	assert_eq(blocks[2].color, StoryboardPage.GREY, "grey, like the times")
	assert_eq(blocks[3].color, StoryboardPage.INK, "the ACTION after it is in ink")
