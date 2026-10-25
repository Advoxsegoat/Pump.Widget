extends TestCase
## tools/anim/set_marks.gd, run as a child Godot on a clip and a JSON file kept under user://.

const CLIP := "user://set_marks_test_clip.tres"
const JSON_FILE := "user://set_marks_test_marks.json"


func after_each() -> void:
	for file in [CLIP, JSON_FILE]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


func _make_clip() -> void:
	var a := Animation.new()
	a.length = 0.5
	var bone := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(bone, NodePath("Model/Skel:hand_l"))
	a.rotation_track_insert_key(bone, 0.0, Quaternion.IDENTITY)
	Marks.write(a, [{"time": 0.4, "kind": &"recovery", "args": {}}])
	assert_eq(ResourceSaver.save(a, CLIP), OK)


func _write_json(text: String) -> void:
	var file := FileAccess.open(JSON_FILE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _marks() -> Array[Dictionary]:
	return Marks.read(ResourceLoader.load(CLIP, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation)


# Runs the tool in a headless child Godot. Returns {code, lines}.
func _run(args: Array[String]) -> Dictionary:
	var argv := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/anim/set_marks.gd", "--"])
	argv.append_array(PackedStringArray(args))
	var output := []
	var code := OS.execute(OS.get_executable_path(), argv, output, true)
	return {"code": code, "lines": str(output[0]).split("\n")}


func test_it_replaces_the_marks_from_the_json() -> void:
	_make_clip()
	_write_json('[{"frame": 15, "kind": "hitbox_off", "args": {"id": "palm_l"}}, {"frame": 10, "kind": "hitbox_on", "args": {"id": "palm_l"}},'
			+ ' {"frame": 10, "kind": "hitstop", "args": {"frames": 3}}, {"frame": 20, "kind": "recovery"},'
			+ ' {"frame": 15, "kind": "cancel_open", "args": {"into": {"palm": "palm_cross"}}}]')
	var run := _run([CLIP, JSON_FILE])
	assert_eq(run["code"], 0, "\n".join(run["lines"]))
	var marks := _marks()
	assert_eq(marks.map(func(m: Dictionary) -> StringName: return m["kind"]), [&"hitbox_on", &"hitstop", &"hitbox_off", &"cancel_open", &"recovery"])
	assert_eq(marks.map(func(m: Dictionary) -> int: return Marks.frame_of(m["time"])), [10, 10, 15, 15, 20])
	assert_eq(marks[0]["args"], {&"id": &"palm_l"}, "strings become StringNames")
	assert_eq(marks[1]["args"], {&"frames": 3})
	assert_eq(typeof(marks[1]["args"][&"frames"]), TYPE_INT, "a whole number is an int")
	assert_eq(marks[3]["args"], {&"into": {&"palm": &"palm_cross"}})
	assert_eq(marks[4]["args"], {})
	var anim := ResourceLoader.load(CLIP, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
	assert_eq(anim.find_track(NodePath("Model/Skel:hand_l"), Animation.TYPE_ROTATION_3D), 0, "the bone track is still there")


func test_an_unknown_kind_writes_nothing() -> void:
	_make_clip()
	_write_json('[{"frame": 10, "kind": "hitbox_on", "args": {"id": "palm_l"}}, {"frame": 12, "kind": "hitbox_onn"}]')
	var run := _run([CLIP, JSON_FILE])
	assert_eq(run["code"], 1)
	assert_true("\n".join(run["lines"]).contains("entry 1"), "the message names the entry: " + "\n".join(run["lines"]))
	assert_eq(_marks().map(func(m: Dictionary) -> StringName: return m["kind"]), [&"recovery"], "the clip is as it was")


func test_a_frame_that_is_not_a_whole_number_writes_nothing() -> void:
	_make_clip()
	_write_json('[{"frame": 10.5, "kind": "fx"}]')
	assert_eq(_run([CLIP, JSON_FILE])["code"], 1)
	_write_json('[{"frame": -1, "kind": "fx"}]')
	assert_eq(_run([CLIP, JSON_FILE])["code"], 1)
	assert_eq(_marks().size(), 1)


func test_a_wrong_command_line_exits_two() -> void:
	assert_eq(_run([CLIP])["code"], 2, "one argument")
	assert_eq(_run([CLIP, "user://no_such_file.json"])["code"], 2, "no json")


func test_a_missing_clip_exits_one() -> void:
	_write_json("[]")
	assert_eq(_run(["user://no_such_clip.tres", JSON_FILE])["code"], 1)
