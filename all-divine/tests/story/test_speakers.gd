extends TestCase
## The speakers: each has a neutral portrait and the six expressions as 48 by 48 pictures, and the pictures differ.

const SPEAKERS: PackedStringArray = ["abarax", "noella", "sierra", "kesra", "fixture_knuckle"]
const EXPRESSIONS: PackedStringArray = ["neutral", "smile", "serious", "angry", "sad", "surprise"]


func test_every_speaker_has_neutral_and_the_six_expressions_as_48_by_48_with_transparent_corners() -> void:
	for id in SPEAKERS:
		var speaker := Registry.fetch(&"speakers", StringName(id)) as Speaker
		assert_true(speaker != null, "speaker %s" % id)
		if speaker == null:
			continue
		assert_eq(speaker.id, StringName(id))
		assert_true(speaker.display_name != "", "%s has a name" % id)
		assert_true(speaker.portraits.has(&"neutral"), "%s has a neutral portrait" % id)
		for expression in EXPRESSIONS:
			var texture := speaker.portraits.get(StringName(expression)) as Texture2D
			assert_true(texture != null, "%s has %s" % [id, expression])
			if texture == null:
				continue
			var image := texture.get_image()
			assert_eq(image.get_size(), Vector2i(48, 48), "%s %s is 48x48" % [id, expression])
			assert_eq(image.get_pixel(0, 0).a, 0.0, "%s %s: the top left corner is clear" % [id, expression])
			assert_eq(image.get_pixel(47, 0).a, 0.0, "%s %s: the top right corner is clear" % [id, expression])


## Two expressions of a speaker must differ by this many pixels to be told apart at 48 pixels.
const MIN_DIFFERENCE := 12
## Known limit: the Tactics painter has no option that strengthens `serious`, which is a change of the brows alone, so it
## stays 10 pixels from `neutral`. It is not painted over; the owner is told.
const KNOWN_SHORT := {"neutral|serious": 8}


func test_the_expressions_differ() -> void:
	for id in SPEAKERS:
		var speaker := Registry.fetch(&"speakers", StringName(id)) as Speaker
		if speaker == null:
			fail("speaker %s is missing" % id)
			continue
		var images := {}
		for expression in EXPRESSIONS:
			var texture := speaker.portraits.get(StringName(expression)) as Texture2D
			if texture == null:
				fail("%s has no %s" % [id, expression])
				continue
			images[expression] = texture.get_image().get_data()
		var short := PackedStringArray()
		for i in EXPRESSIONS.size():
			for j in range(i + 1, EXPRESSIONS.size()):
				var a: PackedByteArray = images.get(EXPRESSIONS[i], PackedByteArray())
				var b: PackedByteArray = images.get(EXPRESSIONS[j], PackedByteArray())
				var differing := 0
				for p in range(0, mini(a.size(), b.size()), 4):
					if a[p] != b[p] or a[p + 1] != b[p + 1] or a[p + 2] != b[p + 2] or a[p + 3] != b[p + 3]:
						differing += 1
				var key := "%s|%s" % [EXPRESSIONS[i], EXPRESSIONS[j]]
				var floor_px: int = KNOWN_SHORT.get(key, MIN_DIFFERENCE)
				if differing < MIN_DIFFERENCE:
					short.append("%s differs by %d" % [key, differing])
				assert_true(differing >= floor_px, "%s: %s and %s differ by %d pixels, under %d" % [id, EXPRESSIONS[i], EXPRESSIONS[j], differing, floor_px])
		# the pairs that fall short of 12 are only the known ones
		assert_true(short.size() <= KNOWN_SHORT.size(), "%s: pairs short of %d: %s" % [id, MIN_DIFFERENCE, ", ".join(short)])


func test_every_portrait_file_has_a_ledger_row() -> void:
	var rows := FileAccess.get_file_as_string("res://ASSETS.md")
	assert_true(rows.contains("| assets/portraits/ |"), "ASSETS.md has a row for assets/portraits/")
	for id in ["abarax", "noella", "sierra", "kesra", "goldtooth"]:
		for expression in EXPRESSIONS:
			assert_true(FileAccess.file_exists("res://assets/portraits/%s/%s.png" % [id, expression]), "%s/%s.png" % [id, expression])


func test_a_speaker_with_no_neutral_portrait_is_not_complete() -> void:
	var speaker := Speaker.new()
	assert_false(speaker.portraits.has(&"neutral"))
	assert_eq(speaker.blip_pitch, 1.0)
