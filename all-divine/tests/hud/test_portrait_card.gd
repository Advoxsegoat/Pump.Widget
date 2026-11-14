extends TestCase
## The portrait card (hud/portrait_card.gd): a speaker's portrait drawn large, beside the dialogue box, at the window's
## resolution above the pixel picture. Headless: what it says is read back through its queries (card_rect, portrait_rect,
## text_rect, free_rect, the card nodes in the stage); the look is tests/render/test_portrait_card_draw.gd's.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const PICTURE := Rect2i(0, 0, 640, 360)

var stage: PixelStage
var overlay: CineOverlay
var abarax: Speaker
var knuckle: Speaker


func before_each() -> void:
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	overlay = CineOverlay.new()
	overlay.auto = false
	stage.hud.add_child(overlay)
	abarax = Registry.fetch(&"speakers", &"abarax") as Speaker
	knuckle = Registry.fetch(&"speakers", &"fixture_knuckle") as Speaker


# The cards in the stage (a card is a child of the PixelStage, drawn in the window above the pixel picture).
func _cards() -> Array[Node]:
	return stage.find_children("*", "PortraitCard", true, false)


# The first card in the stage (null when none).
func _first_card() -> PortraitCard:
	var found := _cards()
	if found.is_empty():
		fail("no card in the stage")
		return null
	return found[0] as PortraitCard


# Where a world point is on the picture under `pose`: (column, row), as the camera sees it.
func _project(pose: CinePose, point: Vector3) -> Vector2:
	var basis := Basis.from_euler(Vector3(deg_to_rad(pose.pitch_deg), deg_to_rad(pose.yaw_deg), 0.0))
	var along := point - pose.aim
	return Vector2(
		PixelSnap.INTERNAL.x / 2.0 + along.dot(basis.x) * pose.zoom / PixelSnap.TEXEL,
		PixelSnap.INTERNAL.y / 2.0 - along.dot(basis.y) * pose.zoom / PixelSnap.TEXEL)


func test_the_card_stands_at_the_boxs_left_and_rises_above_it() -> void:
	assert_eq(PortraitCard.CARD, Vector2i(116, 160))
	for letterbox in [1.0, 0.0]:
		overlay.letterbox = letterbox
		assert_eq(overlay.portrait_rect(), Rect2i(16, 194, 116, 160), "the card's place, with or without bars (%s)" % letterbox)
		var box := overlay.box_rect()
		assert_eq(overlay.portrait_rect().position.x - box.position.x, 6, "its left is 6 px inside the box's left edge")
		assert_eq(box.end.y - overlay.portrait_rect().end.y, 2, "its bottom is 2 px above the box's bottom edge")
		assert_true(overlay.portrait_rect().position.y < box.position.y, "it rises above the box")
		assert_true(PICTURE.encloses(overlay.portrait_rect()), "and stays in the picture")
	overlay.show_line(abarax, "Hmph.", &"neutral", 60)
	assert_eq(_cards().size(), 1, "a line with a speaker shows one card")
	var card := _first_card()
	if card == null:
		return
	assert_eq(card.card_rect(), overlay.portrait_rect(), "the card says where it is as the overlay does")
	assert_true(card.visible, "and shows")
	assert_true(card.texture == overlay.portrait(), "the speaker's portrait")


func test_text_and_tab_begin_right_of_the_card() -> void:
	overlay.show_line(abarax, "Hmph.", &"neutral", 60)
	var card := overlay.portrait_rect()
	assert_eq(overlay.text_rect().position.x, 140, "the text begins 8 px right of the card")
	assert_eq(overlay.text_rect().position.x - card.end.x, 8)
	assert_eq(overlay.tab_rect().position.x, 140, "and so does the name tab")
	assert_eq(overlay.tab_rect().end.y, overlay.box_rect().position.y, "which stands on the box's top edge")
	assert_true(overlay.box_rect().encloses(overlay.text_rect()), "the text is inside the box")
	assert_false(card.intersects(overlay.text_rect()), "and beside the card")
	# A name of 35 characters: its tab stays on the box.
	var long_name := abarax.duplicate() as Speaker
	long_name.display_name = "Abaraxabaraxabaraxabaraxabaraxabar"
	assert_eq(long_name.display_name.length(), 34)
	long_name.display_name += "x"
	assert_eq(long_name.display_name.length(), 35)
	overlay.show_line(long_name, "Hmph.", &"neutral", 60)
	assert_true(overlay.tab_rect().end.x <= overlay.box_rect().end.x, "a 35-character name's tab ends inside the box (%d)" % overlay.tab_rect().end.x)
	assert_true(PICTURE.encloses(overlay.tab_rect()))
	# Three rows of the widest letters (140 of them) still fit the box's three rows, none wider than the text.
	var wide := "W".repeat(140)
	var rows := overlay.lines_of(wide)
	assert_true(rows.size() <= CineOverlay.MAX_LINES, "140 wide letters take %d rows" % rows.size())
	for row in rows:
		assert_true(overlay.text_width(row) <= overlay.text_rect().size.x, "a row is not wider than the text's area")
	assert_true(overlay.lines_of("W".repeat(160)).size() <= CineOverlay.MAX_LINES, "and 160, the most a line may be")
	var three := ["m".repeat(60), "m".repeat(60), "m".repeat(60)]
	assert_eq(overlay.lines_of("\n".join(three)).size(), 3, "three rows of 60 wide letters, by line breaks, are three rows")
	assert_true(overlay.text_width(three[0]) <= overlay.text_rect().size.x, "and each fits")
	var rows_height := CineOverlay.MAX_LINES * CineOverlay.LINE_HEIGHT
	assert_true(rows_height <= overlay.text_rect().size.y, "three rows are as tall as the text's area (%d of %d)" % [rows_height, overlay.text_rect().size.y])


func test_a_shot_with_a_line_is_framed_in_the_free_area() -> void:
	var scene := load(FIXTURE) as SceneShots
	var close: Shot = null
	for shot in scene.shots:
		if shot.framing == Shot.Framing.CLOSE and not shot.lines.is_empty():
			close = shot
	assert_true(close != null, "the fixture has a close shot with a line")
	if close == null:
		return
	var feet := Vector3(0, 0, 5)
	var world := func(name: StringName) -> Variant: return feet if name == &"abarax" else null
	for bars in [true, false]:
		var area := CineOverlay.free_rect(bars)
		assert_eq(area.position.x, overlay.portrait_rect().end.x + CineOverlay.GAP, "the free area begins right of the card")
		assert_eq(area.end.x, 640, "and runs to the picture's right edge")
		assert_eq(area.position.y, CineOverlay.free_band(bars).x, "from the top bar's lower edge (or the picture's top)")
		assert_eq(area.end.y, CineOverlay.free_band(bars).y, "down to the name tab's top")
		for progress in [0.0, 0.5, 1.0]:
			var pose := CinePose.solve(close, progress, world, null, bars)
			var head := _project(pose, feet + Vector3(0, 1.8, 0))
			var middle := _project(pose, feet + Vector3(0, 1.5, 0))
			var foot := _project(pose, feet)
			var reach := 0.35 * pose.zoom / PixelSnap.TEXEL  # a body is 0.35 m either side of its middle
			assert_near(middle.x, area.get_center().x, 0.5, "the aim is in the middle of the free area's columns (%s, bars %s)" % [progress, bars])
			assert_near(middle.y, area.get_center().y, 0.5, "and its rows")
			assert_true(area.has_point(Vector2i(head)), "the head is inside the free area (%s) at %s" % [head, bars])
			assert_true(head.x - reach >= overlay.portrait_rect().end.x, "no column of the head is under the card")
			assert_true(foot.x - reach >= overlay.portrait_rect().end.x, "nor of his feet: no row of him is under the card (%s)" % foot)


func test_a_speaker_with_no_drawing_shows_the_blank_card() -> void:
	assert_true(knuckle.portraits.is_empty(), "the fixture's speaker has no drawing yet")
	overlay.show_line(knuckle, "Hm.", &"smile", 60)
	var blank := overlay.portrait()
	assert_true(blank != null, "a card is shown all the same")
	assert_eq(blank.get_size(), Vector2(464, 640), "at the card's picture size")
	assert_true(blank == knuckle.card(&"neutral"), "the built-in blank card, whatever the expression")
	assert_eq(_cards().size(), 1)
	assert_true(_first_card() != null and _first_card().texture == blank, "which is what the card draws")
	var image := blank.get_image()
	var paper := image.get_pixel(5, 5)
	assert_true(paper.r > 0.85 and paper.g > 0.8 and paper.b > 0.65 and paper.r > paper.b, "cream paper at the corner: %s" % paper)
	var bust := image.get_pixel(232, 600)
	assert_true(absf(bust.r - bust.g) < 0.06 and bust.r < 0.7, "a grey bust shape low in the middle: %s" % bust)
	var speaker := Speaker.new()
	assert_true(speaker.card(&"neutral") == blank, "a speaker with nothing at all has the same blank card")
	overlay.show_line(null, "Nobody speaks.", &"neutral", 60)
	assert_true(overlay.portrait() == null, "no speaker, no portrait")


func test_the_card_goes_with_the_overlay() -> void:
	# Closing the box, and freeing the overlay, at five instants of a line: no card is left the next frame.
	for instant in [0, 1, 15, 60, 130]:
		overlay.show_line(abarax, "A line that is a little long, to type for a while.", &"neutral", 200)
		overlay.advance(instant)
		assert_eq(_cards().size(), 1, "a card is up at %d frames" % instant)
		overlay.close()
		await frames(1)
		assert_eq(_cards().size(), 0, "closing at %d frames takes the card with it" % instant)
	for instant in [0, 1, 15, 60, 130]:
		var other := CineOverlay.new()
		other.auto = false
		stage.hud.add_child(other)
		other.show_line(abarax, "A line that is a little long, to type for a while.", &"neutral", 200)
		other.advance(instant)
		assert_eq(_cards().size(), 1, "a card is up at %d frames" % instant)
		other.free()
		await frames(1)
		assert_eq(_cards().size(), 0, "freeing the overlay at %d frames takes the card with it" % instant)
	# Lines one after the other leave one card, not a pile.
	for i in 3:
		overlay.show_line(abarax, "Line %d." % i, &"neutral", 100)
	assert_eq(_cards().size(), 1, "three lines in a row show one card")
	# Taking the overlay out of the tree without freeing it hides the card too.
	stage.hud.remove_child(overlay)
	await frames(1)
	assert_eq(_cards().size(), 0, "an overlay that leaves the tree takes its card")
	overlay.free()
	# And the scene's own release gives it back with the rest (the cine camera's).
	overlay = CineOverlay.new()
	overlay.auto = false
	stage.hud.add_child(overlay)
	var camera := CineCamera.new()
	camera.overlay = overlay
	track(camera)
	overlay.show_line(abarax, "Hmph.", &"neutral", 100)
	assert_eq(_cards().size(), 1)
	camera.release()
	await frames(1)
	assert_eq(_cards().size(), 0, "release() takes the card with the box")


func test_the_card_never_covers_the_pause_menu() -> void:
	var card := overlay.portrait_rect()
	assert_eq(card.position.y, 194, "the card begins at row 194")
	var menu := track(Menu.new()) as Menu
	menu.open()
	var pages: Array[StringName] = [MenuPages.ROOT, MenuPages.QUIT, MenuPages.SETTINGS, MenuPages.EFFECTS, MenuPages.CAMERA,
			MenuPages.LOOK, MenuPages.SOUND, MenuPages.WINDOW, MenuPages.RESTORE]
	for id in pages:
		menu.show_page(id)
		for step in 40:  # and scrolled through, however long the page
			assert_false(menu.panel().intersects(card), "page %s at step %d: the panel %s and the card %s do not meet" % [id, step, menu.panel(), card])
			assert_true(menu.panel().end.y <= card.position.y, "the panel ends above the card's top (%d)" % menu.panel().end.y)
			menu.press(MenuNav.Cmd.DOWN)
	var long := MenuPage.new()
	long.heading = "A long page"
	long.back = func() -> void: pass
	for i in 30:
		long.rows.append(MenuRow.action("Row %d" % i, func() -> void: pass))
	menu.show_page(&"long", long)
	for step in 70:
		assert_false(menu.panel().intersects(card), "a long page at step %d" % step)
		menu.press(MenuNav.Cmd.DOWN)
	# The card stays where it is while the game is paused.
	overlay.show_line(abarax, "Hmph.", &"neutral", 100)
	var shown := _first_card()
	if shown == null:
		fail("no card is up for the line")
		return
	var before := shown.card_rect()
	get_tree().paused = true
	await get_tree().process_frame
	get_tree().paused = false
	assert_eq(shown.card_rect(), before, "pausing does not move the card")
	assert_true(shown.visible, "or hide it")


# The lines of `lines` that contain `part`.
func _with(lines: PackedStringArray, part: String) -> PackedStringArray:
	var found := PackedStringArray()
	for line in lines:
		if line.contains(part):
			found.append(line)
	return found


func test_final_refuses_a_stand_in_by_name() -> void:
	var scene := (load(FIXTURE) as SceneShots).duplicate_deep()
	var lines := ShotChecker.new().check(scene)
	var stand_ins := _with(lines, "is a stand-in")
	assert_true(stand_ins.size() >= 1, "the fixture's Knuckle has only a blank card: his line is listed (%s)" % [lines])
	for line in stand_ins:
		assert_true(ShotChecker.new().is_placeholder(line), "listed as a placeholder: %s" % line)
		assert_true(line.contains("fixture_knuckle's portrait 'neutral' is a stand-in"), "naming the speaker and the expression: %s" % line)
		assert_true(line.contains("placeholder: line 1 of S3: "), "and the line and the shot: %s" % line)
	assert_eq(_with(lines, "abarax's portrait 'neutral'").size(), 0, "Abarax's neutral is the owner's own drawing, no stand-in")
	assert_eq(_with(lines, "has no '").size(), 0, "no line is an error: %s" % [lines])
	# An approved scene refuses it (what story_check --final does with every placeholder).
	scene.status = SceneShots.Status.APPROVED
	var approved := ShotChecker.new().check(scene)
	assert_eq(_with(approved, "an approved scene has no placeholder").size(), 1, "refused when approved: %s" % [approved])
	# One of Abarax's other expressions is a stand-in until the owner draws it.
	var smile_line: DialogueLine = scene.shots[3].lines[0]
	smile_line.expr = &"smile"
	var again := ShotChecker.new().check(scene)
	assert_eq(_with(again, "abarax's portrait 'smile' is a stand-in").size(), 1, "his smile is a stand-in: %s" % [again])
	# An expression nobody has (not a stand-in either) is still an error.
	smile_line.expr = &"no_such_face"
	var unknown := ShotChecker.new().check(scene)
	assert_eq(_with(unknown, "has no 'no_such_face' portrait").size(), 1, "%s" % [unknown])
