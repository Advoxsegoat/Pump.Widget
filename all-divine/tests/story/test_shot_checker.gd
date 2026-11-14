extends TestCase
## The shot checker. Each test takes the fixture, breaks one thing and expects exactly that line.

const FOLDER := "res://scenes/story/fixture_yard_entrance"
const SCENE := "fixture_yard_entrance"
const TEMP_FOLDER := "user://shot_checker_scene"


func after_each() -> void:
	for file in ["script.md", "notes.md", "shots.tres"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_FOLDER.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_FOLDER))


# --- helpers ---

# The fixture with Knuckle's line said by Abarax: the fixture's own speaker has no drawing yet, and the stand-in that lists is the
# portrait tests' business (tests/hud/test_portrait_card.gd), not this file's.
func _fixture() -> SceneShots:
	var scene := (load(FOLDER + "/shots.tres") as SceneShots).duplicate_deep()
	for shot in scene.shots:
		for line in shot.lines:
			if line.speaker == &"fixture_knuckle":
				line.speaker = &"abarax"
	return scene


# `lines` without the stand-in lines (the fixture's own speaker has no drawing yet; the portrait tests own that rule).
func _without_stand_ins(lines: PackedStringArray) -> PackedStringArray:
	var kept := PackedStringArray()
	for line in lines:
		if not line.contains("is a stand-in"):
			kept.append(line)
	return kept


func _check(scene: SceneShots, folder := "") -> PackedStringArray:
	return ShotChecker.new().check(scene, folder)


# The one line `lines` must be: it starts with the scene and shot, and has `fragment` in it.
func _only(lines: PackedStringArray, shot: String, fragment: String, scene := SCENE) -> void:
	assert_eq(lines.size(), 1, "\n".join(lines))
	if lines.size() == 1:
		assert_true(lines[0].begins_with("%s/%s: " % [scene, shot]), lines[0])
		assert_true(lines[0].contains(fragment), "'%s' is not in: %s" % [fragment, lines[0]])


# Every shot from `index` on starts `by` frames later.
func _shift(scene: SceneShots, index: int, by: int) -> void:
	for i in range(index, scene.shots.size()):
		scene.shots[i].start += by


# The shots laid back to back with these lengths; no beats, lines or cues, so only the lengths are in question.
func _bare(scene: SceneShots, lengths: Array[int]) -> void:
	var at := 0
	for i in scene.shots.size():
		scene.shots[i].beats.clear()
		scene.shots[i].lines.clear()
		scene.shots[i].cues.clear()
		scene.shots[i].start = at
		scene.shots[i].length = lengths[i]
		at += lengths[i]


func _line(speaker: StringName, text: String, at: int, hold: int) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = speaker
	line.text = text
	line.at = at
	line.hold = hold
	return line


# A combat moment of one 60 frame shot with Abarax in it.
func _moment() -> SceneShots:
	var scene := SceneShots.new()
	scene.id = &"moment"
	scene.kind = SceneShots.Kind.MOMENT
	scene.lead_in = 15
	scene.lead_out = 15
	var entry := CastEntry.new()
	entry.actor = &"abarax"
	scene.cast = [entry] as Array[CastEntry]
	var shot := Shot.new()
	shot.id = &"M1"
	shot.length = 60
	shot.aim = &"abarax"
	scene.shots = [shot] as Array[Shot]
	return scene


func _moment_check(scene: SceneShots) -> PackedStringArray:
	return ShotChecker.new().check(scene)


# --- the fixture ---

func test_the_fixture_is_clean() -> void:
	assert_eq(_check(_fixture(), FOLDER), PackedStringArray())
	assert_eq(_check(_fixture()), PackedStringArray())


func test_a_moment_built_in_code_is_clean() -> void:
	assert_eq(_moment_check(_moment()), PackedStringArray())


# --- the shot list ---

func test_a_gap_between_shots_names_the_frames() -> void:
	var scene := _fixture()
	_shift(scene, 1, 10)
	_only(_check(scene), "S2", "gap of 10 frames between S1 and S2")


func test_an_overlap_names_the_frames() -> void:
	var scene := _fixture()
	_shift(scene, 1, -10)
	_only(_check(scene), "S2", "overlap of 10 frames between S1 and S2")


func test_a_first_shot_not_at_zero_and_a_short_shot() -> void:
	var scene := _fixture()
	_shift(scene, 0, 5)
	_only(_check(scene), "S1", "starts at frame 5, not 0")
	scene = _fixture()
	scene.shots[3].length = 11
	scene.shots[3].lines.clear()
	_only(_check(scene), "S4", "11 frames")
	scene = _fixture()
	scene.shots[2].blend_in = 61
	_only(_check(scene), "S3", "blend_in 61")


func test_a_beat_line_or_cue_outside_its_shot() -> void:
	var scene := _fixture()
	scene.shots[1].beats[0].at = 60
	_only(_check(scene), "S2", "beat at frame 60 is outside")
	scene = _fixture()
	scene.shots[2].lines[0].at = 60
	_only(_check(scene), "S3", "line at frame 60 is outside")
	scene = _fixture()
	scene.shots[1].cues[0].at = 61
	_only(_check(scene), "S2", "cue at frame 61 is outside")
	scene = _fixture()
	scene.shots[1].cues[0].at = -1
	_only(_check(scene), "S2", "cue at frame -1 is outside")


func test_a_line_that_cannot_finish_or_overlaps_another_or_is_too_long() -> void:
	var scene := _fixture()
	scene.shots[2].lines[0].hold = 10
	_only(_check(scene), "S3", "hold of 10 frames is under")
	scene = _fixture()
	scene.shots[2].lines[0].at = 10
	_only(_check(scene), "S3", "cannot finish")
	scene = _fixture()
	scene.shots[2].lines.append(_line(&"abarax", "Fixture line one.", 5, 54))
	_only(_check(scene), "S3", "overlaps the line at frame 0")
	# 161 characters in a shot long enough to type them
	scene = _fixture()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.shots[2].length = 400
	_shift(scene, 3, 340)
	scene.shots[2].lines[0] = _line(&"abarax", "x".repeat(161), 0, 360)
	_only(_check(scene), "S3", "161 characters, at most 160")


func test_a_line_with_an_expression_its_speaker_lacks_or_no_text() -> void:
	var scene := _fixture()
	scene.shots[2].lines[0].expr = &"smirk"
	_only(_check(scene), "S3", "no 'smirk' portrait")
	scene = _fixture()
	scene.shots[2].lines[0].text = ""
	_only(_check(scene), "S3", "no text")


func test_an_unknown_clip_is_reported_like_a_move_and_a_placeholder_is_listed() -> void:
	var scene := _fixture()
	scene.shots[1].beats[0].clip = &"no_such_clip"
	_only(_check(scene), "S2", "knuckle has no clip 'no_such_clip'")
	scene.shots[1].beats[0].placeholder = true
	var lines := _check(scene)
	_only(lines, "S2", ShotChecker.PLACEHOLDER + "knuckle has no clip 'no_such_clip'")
	assert_true(ShotChecker.new().is_placeholder(lines[0]))
	assert_false(ShotChecker.new().is_placeholder("%s/S2: knuckle has no clip 'x'" % SCENE))


func test_an_unknown_actor_mark_speaker_sound_def_or_spawn_mark_is_reported() -> void:
	var scene := _fixture()
	scene.shots[0].beats[0].actor = &"ghost"
	_only(_check(scene), "S1", "'ghost' is not in the cast")
	scene = _fixture()
	scene.shots[0].beats[0].move_to = &"nowhere"
	_only(_check(scene), "S1", "move_to 'nowhere' is no actor or mark")
	scene = _fixture()
	scene.shots[2].lines[0].speaker = &"nobody"
	_only(_check(scene), "S3", "speaker 'nobody' is not in the Registry")
	scene = _fixture()
	scene.shots[1].cues[0].id = &"no_such_sound"
	_only(_check(scene), "S2", "sound 'no_such_sound' is not in the Registry")
	scene = _fixture()
	scene.cast_entry(&"knuckle").def = null
	_only(_check(scene), "-", "knuckle has no def")
	scene = _fixture()
	scene.cast_entry(&"knuckle").spawn_mark = &"nope"
	_only(_check(scene), "-", "spawn mark 'nope' is not a mark")
	scene = _fixture()
	scene.mark(&"foe_in").actor = &"ghost"
	_only(_check(scene), "-", "mark 'foe_in' is placed in the space of 'ghost'")
	scene = _fixture()
	scene.shots[1].aim = &"ghost@start"
	_only(_check(scene), "S2", "aim 'ghost@start'")


func test_an_at_start_target_is_read_as_the_actor_or_mark_it_names() -> void:
	var scene := _fixture()
	scene.shots[1].aim = &"knuckle@start"
	scene.shots[1].focus = &"foe_stop@start"
	assert_eq(_check(scene), PackedStringArray())


func test_a_mark_with_an_actors_name_and_a_rehearsal_mark_named_in_a_shot() -> void:
	var scene := _fixture()
	var mark := SceneMark.new()
	mark.name = &"knuckle"
	scene.marks.append(mark)
	_only(_check(scene), "-", "mark 'knuckle' has the name of an actor")
	scene = _fixture()
	scene.shots[0].aim_to = &"rehearsal.abarax"
	_only(_check(scene), "S1", "'rehearsal.abarax' is a rehearsal mark")


# --- the camera ---

func test_camera_fields_must_fit_the_move_and_the_framing() -> void:
	var scene := _fixture()
	scene.shots[1].zoom_to = 2
	_only(_check(scene), "S2", "DOLLY zoom_to 2 is the same as its zoom")
	scene = _fixture()
	scene.shots[3].over_shoulder = &""
	_only(_check(scene), "S4", "OVER_SHOULDER has no over_shoulder actor")
	scene = _fixture()
	scene.shots[2].zoom = 5
	_only(_check(scene), "S3", "zoom 5 is not 0 to 4")
	scene = _fixture()
	scene.shots[2].pitch_deg = -10.0
	scene.shots[2].pitch_to_deg = -10.0
	_only(_check(scene), "S3", "pitch -10")
	scene = _fixture()
	scene.shots[2].pitch_deg = 0.0
	scene.shots[2].pitch_to_deg = 0.0
	assert_eq(_check(scene).size(), 0, "pitch 0 is the framing's own: no problem")
	scene = _fixture()
	scene.shots[2].pitch_deg = -50.0
	scene.shots[2].pitch_to_deg = -20.0
	_only(_check(scene), "S3", "pitch_to_deg is set but the move is STATIC")
	scene = _fixture()
	scene.shots[2].aim_to = &"knuckle"
	_only(_check(scene), "S3", "aim_to is set but the move is STATIC")
	scene = _fixture()
	scene.shots[2].over_shoulder = &"knuckle"
	_only(_check(scene), "S3", "over_shoulder is set but the framing is CLOSE")
	scene = _fixture()
	scene.shots[0].aim_to = &""
	_only(_check(scene), "S1", "PAN has no aim_to")
	scene = _fixture()
	scene.shots[2].move = Shot.CamMove.HANDHELD
	_only(_check(scene), "S3", "HANDHELD has no shake")
	scene = _fixture()
	scene.shots[2].move = Shot.CamMove.ORBIT
	_only(_check(scene), "S3", "ORBIT yaw_to_deg")
	scene = _fixture()
	scene.shots[2].move = Shot.CamMove.CRANE
	_only(_check(scene), "S3", "CRANE pitch_to_deg")
	scene = _fixture()
	scene.shots[2].move = Shot.CamMove.CRANE
	scene.shots[2].pitch_to_deg = -25.0  # the close framing's own pitch: no crane
	_only(_check(scene), "S3", "CRANE pitch_to_deg")
	scene = _fixture()
	scene.shots[2].move = Shot.CamMove.CRANE
	scene.shots[2].pitch_to_deg = -45.0
	assert_eq(_check(scene).size(), 0, "a crane from the framing's own pitch to -45")


# --- the kinds ---

func test_the_kinds_have_their_lengths_and_their_rules() -> void:
	var scene := _fixture()
	_bare(scene, [15, 15, 15, 15])
	_only(_check(scene), "-", "a MINI is 180 to 360 frames in all, this one is 120")
	scene = _fixture()
	_bare(scene, [90, 60, 100, 90])
	_only(_check(scene), "-", "a MINI is 180 to 360 frames in all, this one is 400")
	scene = _fixture()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.lead_in = 20
	scene.lead_out = 20
	_bare(scene, [12, 12, 12, 12])
	_only(_check(scene), "-", "a CUTSCENE is 120 frames or more, this one is 88")
	var moment := _moment()
	var second := Shot.new()
	second.id = &"M2"
	second.start = 60
	second.length = 15
	moment.shots[0].length = 30
	second.start = 30
	second.aim = &"abarax"
	moment.shots.append(second)
	_only(_moment_check(moment), "-", "a MOMENT has one shot, this one has 2", "moment")
	moment = _moment()
	moment.shots[0].length = 70
	_only(_moment_check(moment), "-", "a MOMENT is 90 frames at most, this one is 100", "moment")
	moment = _moment()
	moment.letterbox = true
	_only(_moment_check(moment), "-", "a MOMENT has no letterbox", "moment")
	moment = _moment()
	var beat := ActorBeat.new()
	beat.actor = &"abarax"
	beat.clip = &"idle"
	moment.shots[0].beats.append(beat)
	_only(_moment_check(moment), "M1", "a MOMENT has no beats", "moment")


# --- walking ---

func test_travel_seconds_is_the_formula_of_the_reel_solved_the_other_way() -> void:
	var def := Registry.fetch(&"actors", &"knuckle_1") as ActorDef
	assert_near(ShotChecker.new().travel_seconds(def, ActorBeat.Pace.WALK, 3.3), 3.6729, 0.001)
	assert_near(ShotChecker.new().travel_seconds(def, ActorBeat.Pace.JOG, 5.0), 0.9473, 0.001)
	for metres in [1.2, 3.3, 5.0]:
		var leg := Main._leg(Vector2.RIGHT, 1.0, metres, def.locomotion)
		assert_eq(leg.frames, roundi(ShotChecker.new().travel_seconds(def, ActorBeat.Pace.JOG, metres) * 60.0), "%s m" % metres)


func test_a_walk_that_does_not_fit_before_the_next_beat_is_reported() -> void:
	var scene := _fixture()
	scene.mark(&"foe_in").position = Vector3(4.5, 0.0, 2.6)   # 3.3 m from foe_stop
	scene.shots[0].beats[0].at = 60
	var lines := _check(scene)
	_only(lines, "S1", "knuckle needs 3.72 s (223 frames) to walk 3.3 m at WALK to 'foe_stop' and come to rest, but has 3.50 s (210 frames) before the end of the scene")


func test_a_walk_carries_across_a_cut() -> void:
	var scene := _fixture()
	scene.mark(&"foe_in").position = Vector3(4.5, 0.0, 2.6)   # 3.3 m: 223 frames, and S1 is 90
	scene.shots[1].beats.clear()
	scene.shots[1].cues.clear()
	assert_eq(_check(scene), PackedStringArray(), "the walk goes on through S2 and S3 (270 frames in all)")
	scene.shots[0].beats[0].at = 60   # 210 frames to the scene's last frame
	_only(_check(scene), "S1", "but has 3.50 s (210 frames) before the end of the scene")


# --- notes, status, placeholders ---

func test_an_approved_scene_with_a_placeholder_and_a_notes_status_that_disagrees_are_errors() -> void:
	var scene := _fixture()
	scene.status = SceneShots.Status.APPROVED
	_only(_check(scene, FOLDER), "-", "notes.md ends with 'Status: draft' but the scene is approved")
	scene.shots[1].beats[0].clip = &"no_such_clip"
	scene.shots[1].beats[0].placeholder = true
	var lines := _check(scene)
	assert_eq(lines.size(), 2, "\n".join(lines))
	var listed := 0
	var errors := 0
	for line in lines:
		if ShotChecker.new().is_placeholder(line):
			listed += 1
		else:
			errors += 1
			assert_true(line.contains("an approved scene has no placeholder"), line)
	assert_eq([listed, errors], [1, 1])


func test_the_folder_must_hold_a_script_notes_with_a_status_and_a_shot_list_of_its_name() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_FOLDER)
	var scene := _fixture()
	scene.id = &"shot_checker_scene"
	_write(TEMP_FOLDER + "/script.md", "")
	_write(TEMP_FOLDER + "/notes.md", "## Rev 1\n\nNo status here.\n")
	var lines := _check(scene, TEMP_FOLDER)
	var text := "\n".join(lines)
	assert_eq(lines.size(), 2, text)
	assert_true(text.contains("script.md is empty"), text)
	assert_true(text.contains("notes.md has no 'Status:' line"), text)
	_write(TEMP_FOLDER + "/script.md", "Words.")
	_write(TEMP_FOLDER + "/notes.md", "## Rev 1\n\nStatus: draft\n\nlater\n\nStatus: in review\n")
	lines = _check(scene, TEMP_FOLDER)
	assert_eq(lines.size(), 1, "\n".join(lines))
	assert_true(lines[0].contains("notes.md ends with 'Status: in review' but the scene is draft"), lines[0])
	scene.id = &"other"
	lines = _check(scene, TEMP_FOLDER)
	assert_true("\n".join(lines).contains("id 'other' is not the folder name 'shot_checker_scene'"), "\n".join(lines))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_FOLDER + "/missing"))
	assert_true("\n".join(_check(scene, TEMP_FOLDER + "_nowhere")).contains("script.md is missing"))


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_check_all_walks_the_scene_folders() -> void:
	assert_eq(_without_stand_ins(ShotChecker.new().check_all()), PackedStringArray())
	var lines := ShotChecker.new().check_all("user://no_such_scenes")
	assert_eq(lines.size(), 0, "a root with no scenes has nothing to report")
