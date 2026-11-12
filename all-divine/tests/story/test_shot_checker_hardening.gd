extends TestCase
## The shot checker's "OK" means the scene can be played: damaged files are reported and never crash it, every walk is
## checked by the one walking rule, and the small rules the plan's tables imply. Each test breaks one thing in the
## fixture and expects exactly that line.

const FOLDER := "res://scenes/story/fixture_yard_entrance"
const SCENE := "fixture_yard_entrance"
var TEMP := ""   # a folder of this run's own: two runs at once never share one


func before_each() -> void:
	TEMP = "user://shot_hardening_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func after_each() -> void:
	_wipe(TEMP)


func _wipe(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for sub in access.get_directories():
		_wipe(dir.path_join(sub))
	for file in access.get_files():
		access.remove(file)
	DirAccess.remove_absolute(dir)


func _fixture() -> SceneShots:
	return (load(FOLDER + "/shots.tres") as SceneShots).duplicate_deep()


func _check(scene: SceneShots, folder := "") -> PackedStringArray:
	return ShotChecker.new().check(scene, folder)


func _only(lines: PackedStringArray, shot: String, fragment: String, scene := SCENE) -> void:
	assert_eq(lines.size(), 1, "\n".join(lines))
	if lines.size() == 1:
		assert_true(lines[0].begins_with("%s/%s: " % [scene, shot]), lines[0])
		assert_true(lines[0].contains(fragment), "'%s' is not in: %s" % [fragment, lines[0]])


func _beat(actor: StringName, at: int, props := {}) -> ActorBeat:
	var beat := ActorBeat.new()
	beat.actor = actor
	beat.at = at
	for key in props:
		beat.set(key, props[key])
	return beat


func _mark(name: StringName, position: Vector3, space := SceneMark.Space.REGION, actor := &"") -> SceneMark:
	var mark := SceneMark.new()
	mark.name = name
	mark.position = position
	mark.space = space
	mark.actor = actor
	return mark


# A scene folder under user:// holding the fixture's files, `edit` applied to the text of its shots.tres.
func _folder_with(edit: Callable) -> String:
	var dir := TEMP.path_join(SCENE)
	DirAccess.make_dir_recursive_absolute(dir)
	for file in ["script.md", "notes.md"]:
		_write(dir.path_join(file), FileAccess.get_file_as_string(FOLDER.path_join(file)))
	_write(dir.path_join("shots.tres"), edit.call(FileAccess.get_file_as_string(FOLDER + "/shots.tres")))
	return dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- a checker that did not finish has not said OK ---

func test_a_checker_that_ran_to_its_end_says_so() -> void:
	var checker := ShotChecker.new()
	assert_false(checker.finished)
	assert_eq(checker.check(_fixture()), PackedStringArray())
	assert_true(checker.finished)


class StopsInMarks extends ShotChecker:
	func _check_marks() -> bool:
		return false


func test_a_checker_that_stops_early_is_reported_and_not_ok() -> void:
	var checker := StopsInMarks.new()
	var lines := checker.check(_fixture())
	assert_false(checker.finished)
	_only(lines, "-", "the checker stopped before it finished: in the marks rules")


func test_every_enum_is_range_checked_and_nothing_crashes() -> void:
	var scene := _fixture()
	scene.status = 9 as SceneShots.Status
	_only(_check(scene, FOLDER), "-", "status 9 is not one of 0 (DRAFT), 1 (IN_REVIEW), 2 (APPROVED)")
	scene = _fixture()
	scene.kind = 7 as SceneShots.Kind
	_only(_check(scene), "-", "kind 7 is not one of 0 (CUTSCENE), 1 (MINI), 2 (MOMENT)")
	scene = _fixture()
	scene.shots[2].framing = 9 as Shot.Framing
	_only(_check(scene), "S3", "framing 9 is not one of")
	scene = _fixture()
	scene.shots[2].move = 9 as Shot.CamMove
	_only(_check(scene), "S3", "move 9 is not one of")
	scene = _fixture()
	scene.cast[1].source = 9 as CastEntry.Source
	_only(_check(scene), "-", "knuckle: source 9 is not one of")
	scene = _fixture()
	scene.cast[1].after = 9 as CastEntry.After
	_only(_check(scene), "-", "knuckle: after 9 is not one of")
	scene = _fixture()
	scene.marks[0].space = 9 as SceneMark.Space
	_only(_check(scene), "-", "mark 'foe_in': space 9 is not one of")
	scene = _fixture()
	scene.shots[0].beats[0].pace = 9 as ActorBeat.Pace
	_only(_check(scene), "S1", "pace 9 is not one of 0 (WALK), 1 (JOG)")
	scene = _fixture()
	scene.shots[1].cues[0].kind = 9 as CueEvent.Kind
	_only(_check(scene), "S2", "cue kind 9 is not one of")


func test_a_key_the_class_does_not_have_is_a_problem_with_the_name_it_probably_meant() -> void:
	var dir := _folder_with(func(text: String) -> String:
		return text.replace("kind = 1\nstatus = 0", "kindd = 1\nstatus = 0").replace("lead_in = 30", "lead_inn = 30").replace("aim_height = 1.5", "aim_heigth = 1.5"))
	var lines := ShotChecker.new().check_folder(dir)
	var text := "\n".join(lines)
	assert_eq(lines.size(), 3, text)
	assert_true(text.contains("'kindd' is not a field of SceneShots (did you mean 'kind'?)"), text)
	assert_true(text.contains("'lead_inn' is not a field of SceneShots (did you mean 'lead_in'?)"), text)
	assert_true(text.contains("'aim_heigth' is not a field of Shot (did you mean 'aim_height'?)"), text)


func test_a_file_that_does_not_parse_is_said_to_not_parse() -> void:
	var dir := _folder_with(func(text: String) -> String: return text.substr(0, text.length() / 2) + "\n= = [[")
	var lines: PackedStringArray = quietly(func() -> PackedStringArray: return ShotChecker.new().check_folder(dir))
	_only(lines, "-", "shots.tres does not parse; see the engine's lines above")


func test_a_file_that_is_a_resource_but_not_a_scene_and_a_missing_file() -> void:
	var dir := _folder_with(func(_text: String) -> String: return "[gd_resource type=\"Resource\" format=3]\n\n[resource]\n")
	_only(ShotChecker.new().check_folder(dir), "-", "shots.tres is not a SceneShots")
	_only(ShotChecker.new().check_folder(TEMP.path_join("nothing_here")), "-", "shots.tres is missing", "nothing_here")


# What the loader dropped from a typed array, or left empty, is a problem.

# `text` with `element` appended to the first array line that starts `field = `.
func _append(text: String, field: String, element: String) -> String:
	var start := text.find("\n" + field + " = ") + 1
	var end := text.find("\n", start)
	var line := text.substr(start, end - start)
	return text.substr(0, start) + line.left(line.length() - 2) + ", " + element + "])" + text.substr(end)


func test_an_element_of_the_wrong_class_or_a_string_in_a_typed_array_is_one_line() -> void:
	for case in [["cast", "SubResource(\"shot_%s\")", "SceneShots: 'cast' has 1 element that is not a CastEntry (the loader drops the whole array)"],
			["shots", "\"oops\"", "SceneShots: 'shots' has 1 element that is not a Shot (the loader drops the whole array)"],
			["beats", "SubResource(\"cue_%s\")", "Shot 'S1': 'beats' has 1 element that is not an ActorBeat (the loader drops the whole array)"]]:
		var dir := _folder_with(func(text: String) -> String:
			var other := RegEx.create_from_string("id=\"(%s)_(\\d+)\"" % ("shot" if case[0] == "cast" else "cue")).search(text)
			var element: String = case[1] % other.get_string(2) if case[1].contains("%s") else case[1]
			return _append(text, case[0], element))
		var lines: PackedStringArray = quietly(func() -> PackedStringArray: return ShotChecker.new().check_folder(dir))
		_only(lines, "-", case[2])
		_wipe(TEMP)


const ARRAYS := {
	"cast": ["SceneShots", "a CastEntry"], "marks": ["SceneShots", "a SceneMark"], "shots": ["SceneShots", "a Shot"],
	"beats": ["Shot 'S1'", "an ActorBeat"], "cues": ["Shot 'S2'", "a CueEvent"], "lines": ["Shot 'S3'", "a DialogueLine"],
}


# `text` with the first `field = ` array written across several lines, `extra` (if any) as one more element.
func _spread(text: String, field: String, extra: String) -> String:
	var start := text.find("\n" + field + " = ") + 1
	var end := text.find("\n", start)
	var line := text.substr(start, end - start)
	var typed := line.substr(0, line.find("([") + 2)
	var inner := line.substr(typed.length(), line.length() - typed.length() - 2)
	var rows := PackedStringArray()
	for element in inner.split(", "):
		rows.append("\t" + element)
	if extra != "":
		rows.append("\t" + extra)
	return text.substr(0, start) + typed + "\n" + ",\n".join(rows) + "\n])" + text.substr(end)


# `text` with the first `field = ` array written untyped, `extra` (if any) as one more element.
func _untyped(text: String, field: String, extra: String) -> String:
	var start := text.find("\n" + field + " = ") + 1
	var end := text.find("\n", start)
	var line := text.substr(start, end - start)
	var inner := line.substr(line.find("([") + 2, line.length() - line.find("([") - 4)
	return text.substr(0, start) + field + " = [" + inner + (", " + extra if extra != "" else "") + "]" + text.substr(end)


func test_an_array_written_across_lines_or_untyped_with_a_wrong_element_is_a_line_in_every_array() -> void:
	for field: String in ARRAYS:
		for layout in ["spread", "untyped"]:
			var dir := _folder_with(func(text: String) -> String:
				return _spread(text, field, "\"oops\"") if layout == "spread" else _untyped(text, field, "\"oops\""))
			var lines: PackedStringArray = quietly(func() -> PackedStringArray: return ShotChecker.new().check_folder(dir))
			_only(lines, "-", "%s: '%s' has 1 element that is not %s" % [ARRAYS[field][0], field, ARRAYS[field][1]])
			_wipe(TEMP)


func test_the_legal_layouts_of_an_array_pass() -> void:
	for field: String in ARRAYS:
		for layout in ["spread", "untyped"]:
			var dir := _folder_with(func(text: String) -> String:
				return _spread(text, field, "") if layout == "spread" else _untyped(text, field, ""))
			var lines := ShotChecker.new().check_folder(dir)
			assert_eq(lines, PackedStringArray(), "%s written %s" % [field, layout])
			_wipe(TEMP)


func test_a_sub_resource_id_that_is_not_in_the_file_is_said_as_that() -> void:
	var dir := _folder_with(func(text: String) -> String: return _append(text, "beats", "SubResource(\"beat_nowhere\")"))
	var lines: PackedStringArray = quietly(func() -> PackedStringArray: return ShotChecker.new().check_folder(dir))
	_only(lines, "-", "Shot 'S1': 'beats' names a sub-resource that is not in the file: beat_nowhere")


func test_an_array_the_loader_cut_short_that_the_text_does_not_explain_is_still_a_line() -> void:
	# an outside resource of the wrong class: the text scan does not open it, the loaded scene is where the loss shows
	var dir := _folder_with(func(text: String) -> String: return _append(text, "shots", "ExtResource(\"8_def\")"))
	var lines: PackedStringArray = quietly(func() -> PackedStringArray: return ShotChecker.new().check_folder(dir))
	_only(lines, "-", "5 of 5 'shots' entries of SceneShots were not read")


func test_an_empty_element_in_an_array_is_one_line_and_the_rest_is_not_read() -> void:
	var dir := _folder_with(func(text: String) -> String: return _append(text, "marks", "null"))
	var lines: PackedStringArray = quietly(func() -> PackedStringArray: return ShotChecker.new().check_folder(dir))
	_only(lines, "-", "SceneShots: 'marks' has 1 empty (null) element")


# --- walks ---

func test_a_live_actors_walk_is_checked_from_his_rehearsal_mark() -> void:
	var scene := _fixture()
	scene.marks.append(_mark(&"far", Vector3(0, 0, 50)))
	scene.shots[0].beats.append(_beat(&"abarax", 20, {move_to = &"far", pace = ActorBeat.Pace.JOG}))
	_only(_check(scene), "S1", "abarax needs")
	assert_true(_check(scene)[0].contains("to walk 45.0 m at JOG to 'far' and come to rest"), _check(scene)[0])


func test_a_forty_five_metre_walk_in_seventy_frames_is_a_line_at_a_walk_too() -> void:
	var scene := _fixture()
	scene.marks.append(_mark(&"far", Vector3(0, 0, 50)))
	scene.shots[0].beats.append(_beat(&"abarax", 20, {move_to = &"far"}))
	var lines := _check(scene)
	_only(lines, "S1", "abarax needs")
	assert_true(lines[0].contains("to walk 45.0 m at WALK"), lines[0])


func test_a_live_actor_that_walks_with_no_rehearsal_mark_is_a_problem() -> void:
	var scene := _fixture()
	scene.marks.append(_mark(&"near", Vector3(0, 0, 6)))
	scene.shots[0].beats.append(_beat(&"abarax", 0, {move_to = &"near"}))
	assert_eq(_check(scene), PackedStringArray(), "with his rehearsal mark the walk is fine")
	scene.marks.remove_at(2)   # rehearsal.abarax
	_only(_check(scene), "S1", "abarax walks but the scene has no 'rehearsal.abarax' mark to start it from")


func test_a_walk_that_just_fits_passes_and_one_frame_less_fails() -> void:
	var def := Registry.fetch(&"actors", &"knuckle_1") as ActorDef
	var scene := _fixture()
	var n := StoryWalk.frames(def.locomotion, ActorBeat.Pace.WALK, 1.0)
	scene.shots[0].beats[0].at = 90 - n
	scene.shots[1].beats.append(_beat(&"knuckle", 0, {move_to = &"foe_in"}))   # the next walk begins as S2 does
	assert_eq(_check(scene), PackedStringArray())
	scene.shots[0].beats[0].at = 91 - n
	_only(_check(scene), "S1", "needs %.2f s (%d frames)" % [float(n) / 60.0, n])


func test_a_clip_or_a_face_mid_walk_does_not_end_the_walk() -> void:
	var scene := _fixture()
	scene.shots[0].beats.append(_beat(&"knuckle", 30, {clip = &"knuckle_idle", loop = true}))
	scene.shots[0].beats.append(_beat(&"knuckle", 40, {face = &"abarax"}))
	assert_eq(_check(scene), PackedStringArray())


func test_a_second_walk_starts_from_the_mark_the_first_reached() -> void:
	var scene := _fixture()
	scene.shots[3].beats.append(_beat(&"knuckle", 50, {move_to = &"foe_in"}))
	var lines := _check(scene)
	_only(lines, "S4", "knuckle needs")
	assert_true(lines[0].contains("to walk 1.0 m at WALK to 'foe_in' and come to rest"), lines[0])
	assert_true(lines[0].contains("before the end of the scene"), lines[0])


func test_a_walk_given_before_the_last_could_arrive_is_a_line() -> void:
	var scene := _fixture()
	scene.shots[0].beats.append(_beat(&"knuckle", 30, {move_to = &"foe_in"}))   # the first walk needs 70 frames from 0
	var lines := _check(scene)
	assert_true(lines.size() >= 1, "\n".join(lines))
	assert_true(lines[0].contains("knuckle needs") and lines[0].contains("before its next move_to"), lines[0])


func test_a_named_live_actor_that_plays_a_clip_has_a_def() -> void:
	var scene := _fixture()
	var guard := CastEntry.new()
	guard.actor = &"guard"
	guard.source = CastEntry.Source.LIVE_NAMED
	guard.node_name = &"Guard"
	scene.cast.append(guard)
	scene.shots[1].beats.append(_beat(&"guard", 0, {clip = &"idle"}))
	_only(_check(scene), "S2", "guard plays the clip 'idle' but has no def to look it up in")
	guard.def = Registry.fetch(&"actors", &"knuckle_1") as ActorDef
	assert_eq(_check(scene), PackedStringArray())


func test_a_walk_that_has_no_number_is_a_line() -> void:
	var scene := _fixture()
	var def := (scene.cast_entry(&"knuckle").def as ActorDef).duplicate() as ActorDef
	def.locomotion = def.locomotion.duplicate() as LocomotionTuning
	def.locomotion.accel = 0.001   # a body that never gets up to speed
	scene.cast_entry(&"knuckle").def = def
	_only(_check(scene), "S1", "knuckle: could not work out how long a walk of 1.0 m takes")


func test_a_named_live_actor_that_walks_has_a_def() -> void:
	var scene := _fixture()
	var guard := CastEntry.new()
	guard.actor = &"guard"
	guard.source = CastEntry.Source.LIVE_NAMED
	guard.node_name = &"Guard"
	scene.cast.append(guard)
	scene.marks.append(_mark(&"guard_at", Vector3(5, 0, 5)))
	scene.marks.append(_mark(&"rehearsal.guard", Vector3(6, 0, 5)))
	scene.shots[1].beats.append(_beat(&"guard", 0, {move_to = &"guard_at"}))
	_only(_check(scene), "S2", "guard walks but has no def to take its speed from")


func test_two_actors_at_rest_closer_than_two_bodies_is_a_problem() -> void:
	var scene := _fixture()
	scene.mark(&"foe_in").position = Vector3(1.2, 0, 0.2)
	scene.mark(&"foe_stop").position = Vector3(0.2, 0, 0.2)
	var lines := _check(scene)
	_only(lines, "-", "knuckle and abarax stand 0.3 m apart")
	assert_true(lines[0].contains("under 0.7 m"), lines[0])


func test_a_region_that_does_not_exist_is_a_problem() -> void:
	var scene := _fixture()
	scene.region = "res://world/" + "nowhere/nowhere.tscn"
	_only(_check(scene), "-", "region 'res://world/" + "nowhere/nowhere.tscn' does not exist")
	scene.region = "res://world/training_yard/training_yard.tscn"
	assert_eq(_check(scene), PackedStringArray())


# --- the small rules ---

func test_a_shot_of_no_length_is_one_line() -> void:
	var scene := _fixture()
	scene.shots[2].length = 0
	scene.shots[3].start = 150
	_only(_check(scene), "S3", "is 0 frames")


func test_the_glides_are_20_to_90_frames_and_15_to_90_for_a_moment() -> void:
	var scene := _fixture()
	scene.lead_in = 5
	_only(_check(scene), "-", "lead_in 5 is not 20 to 90")
	scene = _fixture()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.lead_out = 91
	_only(_check(scene), "-", "lead_out 91 is not 20 to 90")
	scene = _fixture()
	scene.kind = SceneShots.Kind.MOMENT
	scene.lead_in = 15
	scene.lead_out = 15
	scene.shots = [scene.shots[2]] as Array[Shot]
	scene.shots[0].start = 0
	scene.shots[0].length = 60
	scene.shots[0].lines.clear()
	scene.shots[0].cues.clear()
	assert_eq(_check(scene), PackedStringArray(), "15 is right for a moment")
	scene.lead_in = 14
	_only(_check(scene), "-", "lead_in 14 is not 15 to 90")


func test_a_beat_that_sets_nothing_two_clips_on_a_frame_and_a_shot_with_no_aim() -> void:
	var scene := _fixture()
	scene.shots[1].beats.append(_beat(&"knuckle", 5))
	_only(_check(scene), "S2", "beat at frame 5 does nothing")
	scene = _fixture()
	scene.shots[1].beats.append(_beat(&"knuckle", 0, {clip = &"knuckle_idle"}))
	_only(_check(scene), "S2", "knuckle has two clips at frame 0")
	scene = _fixture()
	scene.shots[2].aim = &""
	_only(_check(scene), "S3", "has no aim")


func test_the_player_is_not_left_with_an_enemy_brain_and_a_line_has_at_most_three_lines() -> void:
	var scene := _fixture()
	scene.cast[0].after = CastEntry.After.ENEMY_BRAIN
	_only(_check(scene), "-", "abarax is the player's and cannot be left with ENEMY_BRAIN")
	scene = _fixture()
	scene.shots[2].lines[0].text = "a\nb\nc\nd"
	_only(_check(scene), "S3", "has 4 lines, the box holds 3")


func test_pair_is_an_aim_in_a_moment_and_a_problem_elsewhere() -> void:
	var scene := _fixture()
	scene.shots[2].aim = &"@pair"
	_only(_check(scene), "S3", "'@pair' is the middle of a paired move, which only a MOMENT has")
	scene.kind = SceneShots.Kind.MOMENT
	scene.lead_in = 15
	scene.lead_out = 15
	scene.shots = [scene.shots[2]] as Array[Shot]
	scene.shots[0].start = 0
	scene.shots[0].length = 60
	scene.shots[0].lines.clear()
	scene.shots[0].cues.clear()
	assert_eq(_check(scene), PackedStringArray())
