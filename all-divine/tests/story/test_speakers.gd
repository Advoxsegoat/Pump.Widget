extends TestCase
## The speakers: Abarax has the owner's own drawing (a 464 by 640 picture, the card's), his other five expressions point at it
## until the owner draws them; every other speaker has no drawing yet and shows the built-in blank card. What is a stand-in
## is said by `placeholder_exprs`, which the shot checker lists and `story_check --final` refuses.

const SPEAKERS: PackedStringArray = ["abarax", "noella", "sierra", "kesra", "fixture_knuckle"]
const EXPRESSIONS: PackedStringArray = ["neutral", "smile", "serious", "angry", "sad", "surprise"]


func _speaker(id: String) -> Speaker:
	return Registry.fetch(&"speakers", StringName(id)) as Speaker


func test_every_speaker_has_a_name_and_a_card_for_each_of_the_six_expressions() -> void:
	for id in SPEAKERS:
		var speaker := _speaker(id)
		assert_true(speaker != null, "speaker %s" % id)
		if speaker == null:
			continue
		assert_eq(speaker.id, StringName(id))
		assert_true(speaker.display_name != "", "%s has a name" % id)
		for expression in EXPRESSIONS:
			var card := speaker.card(StringName(expression))
			assert_true(card != null, "%s has a card for %s" % [id, expression])
			if card != null:
				assert_eq(card.get_size(), Vector2(464, 640), "%s %s is the card's 464 by 640" % [id, expression])


func test_abarax_has_the_owners_drawing_and_his_other_expressions_point_at_it() -> void:
	var abarax := _speaker("abarax")
	var neutral := abarax.portraits.get(&"neutral") as Texture2D
	assert_true(neutral != null, "a neutral portrait")
	var image := neutral.get_image()
	assert_eq(image.get_size(), Vector2i(464, 640))
	for point in [Vector2i(0, 0), Vector2i(463, 0), Vector2i(0, 639), Vector2i(463, 639), Vector2i(232, 320)]:
		assert_eq(image.get_pixelv(point).a, 1.0, "no alpha at %s: the card is paper" % [point])
	var paper := image.get_pixel(450, 20)
	assert_true(paper.r > 0.85 and paper.g > 0.8 and paper.b > 0.65, "the paper is warm cream at a corner: %s" % paper)
	for expression in ["smile", "serious", "angry", "sad", "surprise"]:
		assert_true(abarax.portraits.get(StringName(expression)) == neutral, "%s points at the neutral drawing" % expression)
		assert_true(abarax.placeholder_exprs.has(StringName(expression)), "%s is a stand-in until the owner draws it" % expression)
		assert_true(abarax.card(StringName(expression)) == neutral, "and its card is the neutral drawing")
	assert_false(abarax.placeholder_exprs.has(&"neutral"), "the neutral drawing is the owner's own")
	assert_eq(abarax.placeholder_exprs.size(), 5)
	assert_true(abarax.card(&"no_such_face") == neutral, "an expression nobody has shows neutral")


func test_every_other_speaker_shows_the_blank_card_and_all_its_expressions_are_stand_ins() -> void:
	var blank := Speaker.new().card(&"neutral")
	assert_true(blank != null)
	assert_eq(blank.get_size(), Vector2(464, 640))
	for id in ["noella", "sierra", "kesra", "fixture_knuckle"]:
		var speaker := _speaker(id)
		assert_true(speaker.portraits.is_empty(), "%s has no drawing yet" % id)
		for expression in EXPRESSIONS:
			assert_true(speaker.placeholder_exprs.has(StringName(expression)), "%s %s is a stand-in" % [id, expression])
			assert_true(speaker.card(StringName(expression)) == blank, "%s %s shows the one blank card" % [id, expression])
		assert_eq(speaker.placeholder_exprs.size(), 6)


func test_the_blank_card_is_cream_paper_with_a_grey_bust() -> void:
	var image := Speaker.new().card(&"neutral").get_image()
	assert_eq(image.get_size(), Vector2i(464, 640))
	var paper := image.get_pixel(8, 8)
	assert_true(paper.r > 0.85 and paper.g > 0.8 and paper.b > 0.65 and paper.r > paper.b, "cream at the corner: %s" % paper)
	var head := image.get_pixel(232, 250)
	var shoulders := image.get_pixel(232, 560)
	for part in [head, shoulders]:
		assert_true(absf(part.r - part.g) < 0.06 and absf(part.g - part.b) < 0.06 and part.r < 0.75, "a grey shape: %s" % part)
	assert_true(Speaker.new().card(&"neutral") == Speaker.new().card(&"smile"), "one card is made, for every speaker")


func test_the_portrait_files_have_a_ledger_row() -> void:
	var rows := FileAccess.get_file_as_string("res://ASSETS.md")
	assert_true(rows.contains("| assets/portraits/abarax/neutral.png |"), "ASSETS.md has a row for Abarax's picture")
	assert_true(FileAccess.file_exists("res://assets/portraits/abarax/neutral.png"), "abarax/neutral.png")
	for old in ["smile", "serious", "angry", "sad", "surprise"]:
		assert_false(FileAccess.file_exists("res://assets/portraits/abarax/%s.png" % old), "the old 48 by 48 %s is gone" % old)


func test_a_speaker_with_no_neutral_portrait_is_not_complete() -> void:
	var speaker := Speaker.new()
	assert_false(speaker.portraits.has(&"neutral"))
	assert_eq(speaker.blip_pitch, 1.0)
	assert_eq(speaker.placeholder_exprs.size(), 0, "a made speaker has no stand-ins listed")
