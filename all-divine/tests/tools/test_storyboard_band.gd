extends TestCase
## The sheet's "NOT FINAL" band (headless, pure): it is how the owner knows what on the sheet is not theirs yet, so what it lists
## is held here: a stand-in portrait, a clip not made, a model that stands in for someone, a sound with no recording; each once,
## with the shot it first appears in, and named as the row names it (the speaker's own name, not an id). A drawn portrait is never
## listed.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"

var _speakers := {}


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


func _speaker(id: StringName, display: String, drawn: bool, stand_in: Array[StringName]) -> Speaker:
	var speaker := Speaker.new()
	speaker.id = id
	speaker.display_name = display
	if drawn:
		speaker.portraits = {&"neutral": Speaker.blank_card()}
	speaker.placeholder_exprs = stand_in
	_speakers[id] = speaker
	return speaker


func _lookup(id: StringName) -> Speaker:
	return _speakers.get(id) as Speaker


# Both speakers of the fixture drawn: nothing in the speakers is a stand-in.
func _all_drawn() -> void:
	_speaker(&"abarax", "Abarax", true, [])
	_speaker(&"fixture_knuckle", "Fixture Knuckle", true, [])


func _found(list: Array[Dictionary], kind: String) -> Array[Dictionary]:
	return list.filter(func(each: Dictionary) -> bool: return each.kind == kind)


func test_a_scene_with_one_stand_in_portrait_lists_it_in_the_band_and_marks_its_row() -> void:
	var scene := _fixture()
	var list := StoryboardPage.stand_ins(scene)   # the data as it is: the Knuckle has no drawing yet
	assert_eq(list.size(), 1, "one stand-in: %s" % [list])
	if list.size() != 1:
		return
	assert_eq(list[0].kind, "portrait")
	assert_eq(list[0].shot, "S3", "the first shot it speaks in")
	var head := StoryboardPage.header_blocks(scene, list)
	assert_false(head.good, "the band is the warning one")
	var band: PackedStringArray = head.band
	assert_true(band[0].begins_with("NOT FINAL: 1 stand-in"), band[0])
	assert_true("\n".join(band).contains("S3: "), "the band says which shot: %s" % ["\n".join(band)])
	var row := "\n".join(StoryboardPage.ShotText.describe(scene, 2))
	assert_true(row.contains("[STAND-IN: "), "the row is marked: %s" % row)
	var note := row.substr(row.find("[STAND-IN: "))
	assert_true(note.contains("Fixture Knuckle (Gold Tooth's look)"), "the red note names the speaker as the row does: %s" % note)
	assert_false(note.contains("fixture_knuckle") or note.contains("'neutral'"), "no id in the note: %s" % note)
	assert_true("\n".join(band).contains("Fixture Knuckle (Gold Tooth's look)"), "the band names him the same way: %s" % ["\n".join(band)])
	assert_false("\n".join(band).contains("fixture_knuckle") or "\n".join(band).contains("'neutral'"), "no id in the band: %s" % ["\n".join(band)])
	assert_false("\n".join(StoryboardPage.ShotText.describe(scene, 3)).contains("[STAND-IN"), "Abarax's drawn portrait marks no row")


func test_a_scene_with_no_stand_in_has_no_band() -> void:
	_all_drawn()
	var scene := _fixture()
	var list := StoryboardPage.stand_ins(scene, _lookup)
	assert_eq(list, [] as Array[Dictionary])
	var head := StoryboardPage.header_blocks(scene, list)
	assert_true(head.good)
	assert_false("\n".join(head.band as PackedStringArray).contains("NOT FINAL"), "no warning band")


func test_a_drawn_portrait_is_never_listed_and_only_the_expression_a_line_uses_counts() -> void:
	_speaker(&"abarax", "Abarax", true, [])
	_speaker(&"fixture_knuckle", "Fixture Knuckle", true, [&"grin", &"cry"])   # two looks are not drawn, but no line uses them
	var scene := _fixture()
	assert_eq(StoryboardPage.stand_ins(scene, _lookup), [] as Array[Dictionary], "neutral is drawn, so the lines' portraits are")


func test_a_stand_in_clip_a_stand_in_model_and_a_missing_sound_are_each_listed_once_with_their_first_shot() -> void:
	_all_drawn()
	var scene := _fixture()
	# a clip not made: used in S2, and again in S3 (still one entry, S2)
	scene.shots[1].beats[0].placeholder = true
	var again := ActorBeat.new()
	again.actor = scene.shots[1].beats[0].actor
	again.clip = scene.shots[1].beats[0].clip
	again.placeholder = true
	scene.shots[2].beats.append(again)
	# a model that stands in for someone: Noella is made from the Knuckle's body, and first acts in S3
	var noella := CastEntry.new()
	noella.actor = &"noella"
	noella.source = CastEntry.Source.SPAWN
	noella.def = scene.cast_entry(&"knuckle").def
	noella.spawn_mark = &"foe_in"
	noella.speaker = &"noella"
	scene.cast.append(noella)
	var walk := ActorBeat.new()
	walk.actor = &"noella"
	walk.face = &"abarax"
	scene.shots[2].beats.append(walk)
	var walk_again := ActorBeat.new()
	walk_again.actor = &"noella"
	walk_again.look = &"abarax"
	scene.shots[3].beats.append(walk_again)
	# a sound with no recording, cued in S4 and again later in S4
	for at in [5, 9]:
		var cue := CueEvent.new()
		cue.at = at
		cue.id = &"ghost_step"
		scene.shots[3].cues.append(cue)
	var list := StoryboardPage.stand_ins(scene, _lookup, func(id: StringName) -> bool: return id != &"ghost_step")
	assert_eq(list.size(), 3, "three entries: %s" % [list])
	var clips := _found(list, "clip")
	var models := _found(list, "model")
	var sounds := _found(list, "sound")
	assert_eq(clips.size(), 1, "the clip, once: %s" % [list])
	assert_eq(models.size(), 1, "the model, once: %s" % [list])
	assert_eq(sounds.size(), 1, "the sound, once: %s" % [list])
	if clips.size() == 1:
		assert_eq(clips[0].shot, "S2")
		assert_true(String(clips[0].text).contains(String(scene.shots[1].beats[0].clip)), clips[0].text)
	if models.size() == 1:
		assert_eq(models[0].shot, "S3")
		assert_true(String(models[0].text).begins_with("Noella"), models[0].text)
	if sounds.size() == 1:
		assert_eq(sounds[0].shot, "S4")
		assert_true(String(sounds[0].text).contains("ghost_step"), sounds[0].text)
	var band := "\n".join(StoryboardPage.header_blocks(scene, list).band as PackedStringArray)
	assert_true(band.begins_with("NOT FINAL: 3 stand-ins"), band)
	assert_true(band.contains("S2: ") and band.contains("S3: ") and band.contains("S4: "), band)


func test_the_player_and_a_character_with_a_body_of_its_own_are_not_stand_in_models() -> void:
	_all_drawn()
	var scene := _fixture()
	assert_eq(_found(StoryboardPage.stand_ins(scene, _lookup), "model"), [] as Array[Dictionary], "Abarax and the Knuckle have their own bodies")


func test_the_band_and_the_row_name_the_speaker_as_the_row_does_and_say_portrait_without_the_look_unless_there_are_several() -> void:
	_speaker(&"abarax", "Abarax", true, [])
	_speaker(&"fixture_knuckle", "The Keeper of the Old Ash Gate", false, [&"neutral", &"grin"])
	var scene := _fixture()
	var list := StoryboardPage.stand_ins(scene, _lookup)
	assert_eq(list.size(), 1, "%s" % [list])
	if list.size() != 1:
		return
	var text: String = list[0].text
	assert_true(text.contains("The Keeper of the Old Ash Gate"), text)
	assert_false(text.contains("fixture_knuckle"), "an id is not a name: %s" % text)
	assert_true(text.contains("portrait"), text)
	assert_false(text.contains("neutral"), "one stand-in look is used: the look's id is left out: %s" % text)
	# the same speaker, two of its stand-in looks used in the scene: now the looks are named
	scene.shots[3].lines[0].speaker = &"fixture_knuckle"
	scene.shots[3].lines[0].expr = &"grin"
	var both := StoryboardPage.stand_ins(scene, _lookup)
	var texts := PackedStringArray()
	for each in both:
		texts.append(each.text)
	assert_eq(both.size(), 2, "%s" % [texts])
	assert_true("\n".join(texts).contains("'grin'") and "\n".join(texts).contains("'neutral'"), "several looks: each is named: %s" % ["\n".join(texts)])
