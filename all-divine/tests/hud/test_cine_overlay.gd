extends TestCase
## The cine overlay (hud/cine_overlay.gd): the letterbox bars and the dialogue box, in whole picture pixels. Headless.
## What it draws is read back through its queries (bar_rects, box_rect, portrait_rect, visible_text), which the drawing
## uses too; the look is the render run's.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const MAIN := "res://main/main.tscn"
const PICTURE := Rect2i(0, 0, 640, 360)

var overlay: CineOverlay
var abarax: Speaker
var knuckle: Speaker


# A Hud that only counts what it would draw, so that Hud.suppressed can be checked without a display.
class CountingHud extends Hud:
	var bars_drawn := 0
	var pips_drawn := 0

	func _draw_player_bars() -> void:
		bars_drawn += 1

	func _draw_pips() -> void:
		pips_drawn += 1


func before_each() -> void:
	overlay = CineOverlay.new()
	overlay.auto = false
	track(overlay)
	abarax = Registry.fetch(&"speakers", &"abarax") as Speaker
	knuckle = Registry.fetch(&"speakers", &"fixture_knuckle") as Speaker


func test_bars_are_whole_pixels_at_every_weight_and_44_at_one() -> void:
	for i in 11:
		overlay.letterbox = i / 10.0
		var height := overlay.bar_height()
		assert_eq(typeof(height), TYPE_INT, "a whole number of pixels at %d tenths" % i)
		assert_eq(height, roundi(i / 10.0 * 44.0))
		assert_true(2.0 * height / 360.0 <= 0.245, "never more than 0.245 of the rows")
		var rects := overlay.bar_rects()
		if height == 0:
			assert_eq(rects.size(), 0, "no bars at 0")
		else:
			assert_eq(rects.size(), 2)
			assert_eq(rects[0], Rect2i(0, 0, 640, height), "the top bar")
			assert_eq(rects[1], Rect2i(0, 360 - height, 640, height), "the bottom bar")
	overlay.letterbox = 1.0
	assert_eq(overlay.bar_height(), 44, "exactly 44 at one")
	overlay.letterbox = 2.0
	assert_eq(overlay.bar_height(), 44, "and no more for a weight over one")


func test_the_box_stays_in_the_picture_above_the_bars_and_clears_them() -> void:
	for letterbox in [0.0, 0.3, 1.0]:
		overlay.letterbox = letterbox
		var box := overlay.box_rect()
		assert_eq(box.size, Vector2i(620, 64), "620 by 64")
		assert_true(PICTURE.encloses(box), "inside the picture at %s" % letterbox)
		assert_eq(box.position.x, 10, "10 px from the left; 10 px from the right")
		assert_eq(box.end.x, 630)
		assert_eq(box.end.y + 10, 360 - overlay.bar_height(), "its bottom is 10 px above the bars (or the picture's bottom)")
		for bar in overlay.bar_rects():
			assert_false(box.intersects(bar), "clear of the bars")
			assert_false(overlay.tab_rect().intersects(bar), "and so is the name tab")
		assert_true(PICTURE.encloses(overlay.tab_rect()), "the tab is in the picture too")
	overlay.letterbox = 1.0
	assert_eq(overlay.box_rect().end.y, 306, "with the bars the box ends at row 306")


func test_a_line_types_30_characters_a_second_and_blips_every_second_character() -> void:
	var text := "Fixture line one, with enough words to type for a while."
	overlay.show_line(knuckle, text, &"neutral", 400)
	var seen := {}
	var blips := 0
	var pitches := PackedFloat32Array()
	for frame in range(0, 61):
		if frame > 0:
			overlay.advance(1)
		seen[frame] = overlay.visible_text()
	assert_eq(seen[0], "", "nothing is typed on frame 0")
	assert_eq(seen[1], "", "nor on frame 1: a character takes two frames")
	assert_eq(seen[2], text.substr(0, 1), "one character after 2 frames")
	assert_eq(seen[30], text.substr(0, 15), "15 after half a second")
	assert_eq(seen[60], text.substr(0, 30), "30 after a second")
	for id in Sfx.last_played():
		if id == &"voice_blip":
			blips += 1
	for pitch in Sfx.last_pitches():
		pitches.append(pitch)
	assert_eq(blips, 15, "a blip on every second of the 30 characters")
	assert_eq(pitches.size(), 15)
	for pitch in pitches:
		assert_near(pitch, knuckle.blip_pitch, 1e-6, "at the speaker's pitch")
	# A line of the other speaker blips at his pitch.
	overlay.show_line(abarax, "Hi.", &"neutral", 100)
	overlay.advance(2)
	assert_near(Sfx.last_pitches()[Sfx.last_pitches().size() - 1], 1.0, 1e-6)
	# Typing is as quick however the frames are given.
	var other := CineOverlay.new()
	other.auto = false
	track(other)
	other.show_line(knuckle, text, &"neutral", 400)
	other.advance(30)
	assert_eq(other.visible_text(), text.substr(0, 15), "advance(30) is 30 frames")


func test_a_line_ends_after_its_hold_and_closing_clears_the_box() -> void:
	overlay.show_line(abarax, "Short.", &"smile", 40)
	assert_true(overlay.showing(), "shown at once")
	overlay.advance(39)
	assert_true(overlay.showing(), "still up on frame 39")
	assert_eq(overlay.visible_text(), "Short.", "fully typed and held")
	overlay.advance(1)
	assert_false(overlay.showing(), "gone after its hold")
	assert_eq(overlay.visible_text(), "")
	overlay.show_line(abarax, "Another.", &"smile", 100)
	overlay.advance(6)
	assert_true(overlay.showing())
	overlay.close()
	assert_false(overlay.showing(), "closing clears it")
	assert_eq(overlay.visible_text(), "")
	overlay.advance(10)
	assert_false(overlay.showing(), "and time does not bring it back")
	overlay.close()
	assert_false(overlay.showing(), "closing twice is harmless")


func test_every_fixture_line_fits_in_three_lines_of_the_box() -> void:
	var scene := load(FIXTURE) as SceneShots
	var count := 0
	for shot in scene.shots:
		for line in shot.lines:
			count += 1
			var wrapped := overlay.lines_of(line.text)
			assert_true(wrapped.size() >= 1 and wrapped.size() <= CineOverlay.MAX_LINES, "'%s' is %d lines" % [line.text, wrapped.size()])
			for row in wrapped:
				assert_true(overlay.text_width(row) <= overlay.text_rect().size.x, "'%s' is not wider than the box's text" % row)
	assert_true(count >= 2, "the fixture has lines")
	# The longest a line can be (160 characters) in the widest letters still fits.
	assert_true(overlay.lines_of("W".repeat(160)).size() <= CineOverlay.MAX_LINES, "160 wide letters with no spaces")
	assert_true(overlay.lines_of(("Mmmmmmmmm ").repeat(16).substr(0, 160)).size() <= CineOverlay.MAX_LINES, "160 characters of wide words")
	assert_eq(overlay.lines_of("").size(), 0, "nothing is no lines")
	var joined := "".join(overlay.lines_of("one two three"))
	assert_eq(joined.replace(" ", ""), "onetwothree", "wrapping loses no letter")


func test_the_portrait_is_the_speakers_expression_at_48_by_48() -> void:
	overlay.show_line(abarax, "Hmph.", &"angry", 60)
	assert_true(overlay.portrait() == abarax.portraits[&"angry"], "the angry portrait")
	assert_eq(overlay.portrait_rect().size, Vector2i(48, 48), "drawn at 48 by 48, not scaled")
	assert_eq(overlay.portrait().get_size(), Vector2(48, 48))
	assert_true(overlay.box_rect().encloses(overlay.portrait_rect()), "inside the box")
	assert_eq(overlay.portrait_rect().position.x - overlay.box_rect().position.x, 8, "8 px in from the box's left")
	assert_eq(overlay.portrait_rect().position.y - overlay.box_rect().position.y, 8, "and 8 px down")
	assert_false(overlay.portrait_rect().intersects(overlay.text_rect()), "the text is beside it")
	overlay.show_line(knuckle, "Hm.", &"no_such_face", 60)
	assert_true(overlay.portrait() == knuckle.portraits[&"neutral"], "an expression the speaker lacks is neutral")
	overlay.close()
	assert_true(overlay.portrait() == null, "no line, no portrait")


func test_the_overlay_never_covers_more_than_the_bars() -> void:
	overlay.show_line(abarax, "A line that is showing while the bars slide.", &"neutral", 400)
	for i in 21:
		overlay.letterbox = i / 20.0
		overlay.advance(3)
		assert_true(overlay.covered_fraction() <= 0.245, "covered %.3f at %d/20" % [overlay.covered_fraction(), i])
	assert_near(overlay.covered_fraction(), 2.0 * 44.0 / 360.0, 1e-6, "the bars, and only they, are what covers the picture at one")
	assert_true(overlay.box_fraction() > 0.1 and overlay.box_fraction() < 0.2, "the box is a panel and is counted apart: %.3f" % overlay.box_fraction())
	overlay.close()
	assert_eq(overlay.box_fraction(), 0.0, "no box without a line")


func test_a_suppressed_hud_draws_nothing_and_an_unsuppressed_one_is_unchanged() -> void:
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(2)
	var counting := CountingHud.new()
	counting.player = main.hud.player
	counting.hints_visible = false
	assert_false(counting.suppressed, "not suppressed by default")
	counting._draw()
	assert_eq([counting.bars_drawn, counting.pips_drawn], [1, 1], "unsuppressed it draws as before")
	counting.suppressed = true
	counting._draw()
	assert_eq([counting.bars_drawn, counting.pips_drawn], [1, 1], "suppressed it draws nothing more")
	counting.suppressed = false
	counting._draw()
	assert_eq([counting.bars_drawn, counting.pips_drawn], [2, 2], "and lifting it brings the drawing back")
	counting.free()


func test_a_line_break_is_a_line_break() -> void:
	var parts := ["First row.", "Second row, a little longer.", "Third."]
	var text := "\n".join(parts)
	assert_eq(overlay.lines_of(text), PackedStringArray(parts), "three rows by newline are three rows")
	assert_eq(overlay.lines_of("a\n\nb"), PackedStringArray(["a", "b"]), "an empty row is dropped")
	overlay.show_line(abarax, text, &"neutral", 600)
	overlay.advance(text.length() * 2)
	assert_eq(overlay.rows_shown(), PackedStringArray(parts), "drawn on three rows, none run into the next")
	var long_part := "Mmmmmmmmm ".repeat(12).strip_edges()
	var mixed := overlay.lines_of(long_part + "\nTail.")
	assert_true(mixed.size() >= 3 and mixed[mixed.size() - 1] == "Tail.", "a part that wraps keeps its break: %s" % [mixed])
	assert_eq("".join(mixed).replace(" ", ""), long_part.replace(" ", "") + "Tail.")
	overlay.advance(2)
	overlay.close()
	assert_eq(overlay.rows_shown().size(), 0)
