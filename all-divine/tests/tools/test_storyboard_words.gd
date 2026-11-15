extends TestCase
## The sheet's words are a writer's (headless, pure): every camera move in a plain sentence with its shorthand after it in grey (never
## broken inside its bracket), seconds before frames (frames only on a row's own time line), the places the shots name told in words,
## and a cast line that says who the player is and who is shown by a stand-in body.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const MOVE_FIELDS := {
	Shot.CamMove.STATIC: {},
	Shot.CamMove.PAN: {aim = &"abarax", aim_to = &"knuckle"},
	Shot.CamMove.DOLLY: {zoom = 2, zoom_to = 3},
	Shot.CamMove.CRANE: {pitch_deg = -30.0, pitch_to_deg = -50.0},
	Shot.CamMove.ORBIT: {yaw_deg = 0.0, yaw_to_deg = 90.0},
	Shot.CamMove.HANDHELD: {shake = 0.6},
}


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# The fixture's S2 with the camera move `move` set up as `fields` says; its title row.
func _title(move: int, fields: Dictionary) -> String:
	var scene := _fixture()
	var shot := scene.shots[1]
	shot.move = move
	shot.zoom = 0
	shot.zoom_to = 0
	for key in fields:
		shot.set(key, fields[key])
	return StoryboardPage.ShotText.describe(scene, 1)[0]


func test_every_camera_move_has_a_plain_sentence_and_its_shorthand_after_it() -> void:
	for name in Shot.CamMove.keys():
		var move: int = Shot.CamMove[name]
		assert_true(MOVE_FIELDS.has(move), "the test knows how to set up %s" % name)
		var title := _title(move, MOVE_FIELDS.get(move, {}))
		assert_true(title.contains(", the camera "), "%s has a sentence: %s" % [name, title])
		assert_false(title.contains("no words"), "%s has words: %s" % [name, title])
		if move != Shot.CamMove.STATIC:
			assert_false(title.contains("holds still"), "%s is not said to hold still: %s" % [name, title])
		assert_true(title.ends_with("(%s)" % String(name) ) or title.contains("(%s " % String(name)), "the shorthand is after the sentence: %s" % title)


func test_the_moves_are_said_in_the_words_a_script_would_use() -> void:
	assert_eq(_title(Shot.CamMove.STATIC, {}), "S2   MEDIUM, the camera holds still   (STATIC)")
	assert_eq(_title(Shot.CamMove.PAN, {aim = &"abarax", aim_to = &"knuckle"}), "S2   MEDIUM, the camera turns from Abarax to Knuckle   (PAN Abarax>Knuckle)")
	assert_eq(_title(Shot.CamMove.DOLLY, {zoom = 2, zoom_to = 3}), "S2   MEDIUM, the camera pushes in, from medium to close   (DOLLY 2>3)")
	assert_eq(_title(Shot.CamMove.DOLLY, {zoom = 3, zoom_to = 1}), "S2   MEDIUM, the camera pulls out, from close to wide   (DOLLY 3>1)")
	assert_eq(_title(Shot.CamMove.CRANE, {pitch_deg = -30.0, pitch_to_deg = -50.0}), "S2   MEDIUM, the camera rises, tilting down from 30 to 50 degrees   (CRANE -30>-50)")
	assert_eq(_title(Shot.CamMove.CRANE, {pitch_deg = -50.0, pitch_to_deg = -30.0}), "S2   MEDIUM, the camera sinks, tilting down from 50 to 30 degrees   (CRANE -50>-30)")
	assert_eq(_title(Shot.CamMove.ORBIT, {yaw_deg = 0.0, yaw_to_deg = 90.0}), "S2   MEDIUM, the camera circles a quarter turn to the right   (ORBIT 0>90)")
	assert_eq(_title(Shot.CamMove.ORBIT, {yaw_deg = 0.0, yaw_to_deg = -90.0}), "S2   MEDIUM, the camera circles a quarter turn to the left   (ORBIT 0>-90)")
	assert_eq(_title(Shot.CamMove.ORBIT, {yaw_deg = 0.0, yaw_to_deg = 180.0}), "S2   MEDIUM, the camera circles half way round to the right   (ORBIT 0>180)")
	assert_eq(_title(Shot.CamMove.ORBIT, {yaw_deg = 10.0, yaw_to_deg = 55.0}), "S2   MEDIUM, the camera circles 45 degrees to the right   (ORBIT 10>55)")
	assert_eq(_title(Shot.CamMove.HANDHELD, {shake = 0.1}), "S2   MEDIUM, the camera is hand-held, with a slight shake   (HANDHELD 0.1)")
	assert_eq(_title(Shot.CamMove.HANDHELD, {shake = 0.6}), "S2   MEDIUM, the camera is hand-held, with a clear shake   (HANDHELD 0.6)")
	assert_eq(_title(Shot.CamMove.HANDHELD, {shake = 0.9}), "S2   MEDIUM, the camera is hand-held, with a strong shake   (HANDHELD 0.9)")


func test_the_shorthand_is_set_apart_in_grey_and_never_wraps_inside_its_bracket() -> void:
	var scene := _fixture()
	scene.shots[1].move = Shot.CamMove.CRANE
	scene.shots[1].pitch_deg = -30.0
	scene.shots[1].pitch_to_deg = -50.0
	var blocks := StoryboardPage.blocks_of(StoryboardPage.ShotText.describe(scene, 1))
	var title: Dictionary = blocks[0]
	var rows: PackedStringArray = title.rows
	var tails: PackedStringArray = title.tails
	assert_eq(rows.size(), tails.size(), "a tail for each row")
	assert_eq(tails[tails.size() - 1], "(CRANE -30>-50)", "the shorthand is the last row's grey tail: %s" % [tails])
	assert_false("\n".join(rows).contains("CRANE"), "and is not in the ink: %s" % [rows])
	# a sentence so long that the bracket cannot stay on its row: the bracket moves whole to a row of its own
	var long_title: Array[Dictionary] = StoryboardPage.blocks_of(PackedStringArray(["S2   MEDIUM, the camera turns from one thing to another very distant thing in a way that will certainly be wrapped   (PAN Abarax>foe stop)", "x"]))
	var long_rows: PackedStringArray = long_title[0].rows
	var long_tails: PackedStringArray = long_title[0].tails
	assert_true(long_rows.size() >= 2, "it wraps: %s" % [long_rows])
	for i in long_rows.size():
		var shown := long_rows[i] + long_tails[i]
		assert_eq(shown.count("("), shown.count(")"), "no row cuts the bracket in two: '%s'" % shown)
	assert_true(long_tails.has("(PAN Abarax>foe stop)"), "the shorthand is whole: %s" % [long_tails])


func test_times_say_seconds_and_frames_stay_on_the_rows_own_time_line() -> void:
	var scene := _fixture()
	for i in scene.shots.size():
		var text := StoryboardPage.ShotText.describe(scene, i)
		assert_true(text[1].contains("frames "), "the time line keeps its frames: %s" % text[1])
		for line in text:
			if line.begins_with("DOES: ") or line.begins_with("SOUND: ") or line.begins_with("MUSIC: ") or line.begins_with("SAYS: ") or line.begins_with("picture: "):
				assert_false(line.contains("frame"), "seconds only: %s" % line)
	var s2 := "\n".join(StoryboardPage.ShotText.describe(scene, 1))
	assert_true(s2.contains("DOES: Abarax plays the clip guard_hold, repeating (at +0.23 s)"), s2)
	assert_true(s2.contains("SOUND: cloth_move, heard at Knuckle (at the start)"), s2)


func test_the_header_lists_each_place_a_shot_names_in_words() -> void:
	var scene := _fixture()
	var places := StoryboardPage.mark_sentences(scene)
	assert_eq(places, PackedStringArray([
		"foe in (where Knuckle starts): 2.6 m in front of Abarax, 2.2 m to the left as he faces",
		"foe stop: 2.6 m in front of Abarax, 1.2 m to the left as he faces",
	]))
	var head := StoryboardPage.header_blocks(scene, StoryboardPage.stand_ins(scene))
	assert_eq(head.marks, places, "the header carries them")
	var bare := head.duplicate()
	bare.marks_rows = PackedStringArray()
	assert_true(StoryboardPage.header_height(head) > StoryboardPage.header_height(bare), "and has room for them")


func test_a_place_in_the_regions_own_space_and_one_behind_the_actor_are_said_too() -> void:
	var scene := _fixture()
	scene.mark(&"foe_stop").position = Vector3(-0.5, 0, -1.0)
	scene.mark(&"foe_in").space = SceneMark.Space.REGION
	scene.mark(&"foe_in").position = Vector3(4, 0, 7)
	var places := StoryboardPage.mark_sentences(scene)
	assert_eq(places.size(), 2, "both places: %s" % [places])
	if places.size() != 2:
		return
	assert_eq(places[0], "foe in (where Knuckle starts): at x 4.0, z 7.0 on the place's own map")
	assert_eq(places[1], "foe stop: 1.0 m behind Abarax, 0.5 m to the right as he faces")


func test_the_cast_line_says_who_the_player_is_and_who_wears_a_stand_in_body() -> void:
	var scene := _fixture()
	var head := StoryboardPage.header_blocks(scene, [])
	var facts := ""
	for fact: PackedStringArray in head.facts:
		facts += " ".join(fact) + "\n"
	assert_true(facts.contains("Cast: Abarax (the player), Knuckle\n"), facts)
	var noella := CastEntry.new()
	noella.actor = &"noella"
	noella.source = CastEntry.Source.SPAWN
	noella.def = scene.cast_entry(&"knuckle").def
	noella.spawn_mark = &"foe_in"
	scene.cast.append(noella)
	facts = ""
	for fact: PackedStringArray in StoryboardPage.header_blocks(scene, []).facts:
		facts += " ".join(fact) + "\n"
	assert_true(facts.contains("Cast: Abarax (the player), Knuckle, Noella (shown by a stand-in model)\n"), facts)


# ---- nothing is dropped in silence (fix round 1, item 4) ----

# The fixture with a 3,700-character action in S2 (the review's: it left the DOES, SOUND and FOCUS rows off the sheet).
func _long_scene() -> SceneShots:
	var scene := _fixture()
	scene.shots[1].action = "The yard is quiet and the dust does not move at all. ".repeat(70).substr(0, 3700)
	return scene


# Every drawn row of shot `index`, first part and continuations, as the text and the grey tail it ends with.
func _drawn_rows(plan: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for atom: Dictionary in plan.first:
		rows.append(atom.label + atom.text + "|" + atom.tail)
	for part: Array in plan.more:
		for atom: Dictionary in part:
			rows.append(atom.label + atom.text + "|" + atom.tail)
	return rows


func test_no_text_of_a_shot_is_left_off_the_sheet_however_long() -> void:
	var scene := _long_scene()
	var expected: Array[String] = []
	for block in StoryboardPage.blocks_of(StoryboardPage.ShotText.describe(scene, 1)):
		for r in (block.rows as PackedStringArray).size():
			expected.append((block.label if r == 0 else "") + block.rows[r] + "|" + block.tails[r])
	var drawn := _drawn_rows(StoryboardPage.plan(scene)[1])
	assert_eq(drawn.size(), expected.size(), "every row of text is drawn: %d of %d" % [drawn.size(), expected.size()])
	assert_eq(drawn, expected, "in order, none dropped")
	var text := "\n".join(drawn)
	for label in ["DOES:", "SOUND:", "FOCUS:", "CAMERA:"]:
		assert_true(text.contains(label), "%s is on the sheet" % label)


func test_a_row_longer_than_a_page_fills_the_page_and_continues_on_the_next_headed_continued() -> void:
	var scene := _long_scene()
	var spans := StoryboardPage.row_spans(scene)
	var more := StoryboardPage.continuation_spans(scene)
	assert_eq(spans[1], 3, "a row may fill a page")
	assert_true(more[1].size() >= 1, "and the rest continues: %s" % [more[1]])
	for each in more[1]:
		assert_true(each >= 1 and each <= 3, "a continuation is at most a page: %d" % each)
	assert_eq(StoryboardPage.continued_heading(scene, 1), "S2, continued")
	assert_eq(more[0].size() + more[2].size() + more[3].size(), 0, "the short rows do not continue")
	var boxes := StoryboardPage.layout(4, spans, StoryboardPage.HEAD, more)
	assert_eq(boxes[1].span, 3)
	assert_eq(boxes[1].page, 2, "S2 needs a page of its own: it starts the second")
	var follow: Array = boxes[1].more
	assert_eq(follow.size(), more[1].size(), "a box for each continuation")
	if follow.size() >= 1:
		assert_eq(follow[0].page, 3, "the continuation is on the next page")
		assert_eq(follow[0].slot, 0)
		assert_eq(follow[0].span, more[1][0])
	var last_page: int = follow[follow.size() - 1].page if follow.size() > 0 else 0
	assert_true(boxes[2].page >= last_page, "the next shot comes after the continuation (page %d after %d)" % [boxes[2].page, last_page])
	# nothing is drawn outside its page
	for box in boxes:
		assert_true(box.rect.end.y <= box.page_size.y, "the frame is inside its page")
		for each: Dictionary in box.get("more", []):
			assert_true(each.row.end.y <= each.page_size.y, "the continuation is inside its page")


func test_each_part_of_a_long_row_fits_the_rows_it_is_given() -> void:
	var scene := _long_scene()
	var plan := StoryboardPage.plan(scene)[1]
	assert_eq(plan.span, 3, "a page")
	assert_true(plan.first.size() > 10, "and rows of text beside the frame")
	var first_room: int = int(plan.span) * StoryboardPage.ROW_HEIGHT - 2 * StoryboardPage.ROW_PAD
	var height := 0
	for atom: Dictionary in plan.first:
		height += int(atom.height) + int(atom.gap)
	assert_true(height <= first_room, "the first part (%d px) fits its %d" % [height, first_room])
	for i in plan.more.size():
		var room: int = int(plan.spans_more[i]) * StoryboardPage.ROW_HEIGHT - 2 * StoryboardPage.ROW_PAD - StoryboardPage.CONTINUED_HEAD
		var used := 0
		for atom: Dictionary in plan.more[i]:
			used += int(atom.height) + int(atom.gap)
		assert_true(used <= room, "continuation %d (%d px) fits its %d" % [i, used, room])
