extends TestCase
## Marks: the keys on a clip's method track at path "Marks", read and written as {time, kind, args}.

const TMP := "user://test_marks_clip.tres"


func after_each() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func _mark(frame: int, kind: StringName, args := {}) -> Dictionary:
	return {"time": Marks.time_of(frame), "kind": kind, "args": args}


func _clip(length := 1.0) -> Animation:
	var a := Animation.new()
	a.length = length
	return a


func _saved_and_loaded(anim: Animation) -> Animation:
	assert_eq(ResourceSaver.save(anim, TMP), OK)
	return ResourceLoader.load(TMP, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation


func test_the_track_is_called_marks() -> void:
	assert_eq(Marks.TRACK, NodePath("Marks"))


func test_kinds() -> void:
	assert_eq(Marks.KINDS.size(), 13)
	for kind in [&"hitbox_on", &"hitbox_off", &"iframes_on", &"iframes_off", &"hyperarmour_on", &"hyperarmour_off",
			&"cancel_open", &"cancel_close", &"recovery", &"fx", &"sfx", &"shake", &"hitstop"]:
		assert_true(Marks.KINDS.has(kind), kind)


func test_the_rigs_mark_sink_has_a_method_for_every_kind() -> void:
	var sink := MarkSink.new()
	for kind in Marks.KINDS:
		assert_true(sink.has_method(kind), "MarkSink.%s" % kind)
	sink.free()


func test_frames_and_times_are_sixtieths_of_a_second() -> void:
	assert_eq(Marks.frame_of(0.0), 0)
	assert_eq(Marks.frame_of(10 / 60.0), 10)
	assert_eq(Marks.frame_of(0.1667), 10)
	assert_eq(Marks.frame_of(0.0083), 0, "rounds to the nearest frame")
	assert_eq(Marks.frame_of(0.0084), 1)
	assert_near(Marks.time_of(10), 10 / 60.0, 1e-12)
	assert_near(Marks.time_of(0), 0.0, 1e-12)
	for f in 121:
		assert_eq(Marks.frame_of(Marks.time_of(f)), f)
		assert_eq(Marks.frame_of(float(Marks.time_of(f)) + 4e-8), f, "also after the float32 rounding of a saved clip")


func test_write_then_read_round_trips_sorted() -> void:
	var a := _clip()
	Marks.write(a, [
		_mark(15, &"hitbox_off", {"id": &"palm_l"}),
		_mark(5, &"sfx", {"name": &"palm_whoosh"}),
		_mark(10, &"hitbox_on", {"id": &"palm_l"}),
	])
	var read := Marks.read(a)
	assert_eq(read.size(), 3)
	assert_eq(read.map(func(m: Dictionary) -> StringName: return m["kind"]), [&"sfx", &"hitbox_on", &"hitbox_off"])
	assert_eq(read.map(func(m: Dictionary) -> int: return Marks.frame_of(m["time"])), [5, 10, 15])
	assert_eq(read[0]["args"], {"name": &"palm_whoosh"})
	assert_eq(read[1]["args"], {"id": &"palm_l"})
	assert_near(read[1]["time"], 10 / 60.0, 1e-9)


func test_read_gives_the_kind_as_a_string_name() -> void:
	var a := _clip()
	Marks.write(a, [{"time": 0.1, "kind": "fx", "args": {}}])
	assert_eq(typeof(Marks.read(a)[0]["kind"]), TYPE_STRING_NAME)


func test_marks_on_the_same_frame_all_survive_in_the_order_given() -> void:
	# A method track keeps one key per time, so marks that share a frame go on parallel tracks.
	var a := _clip()
	Marks.write(a, [
		_mark(10, &"hitbox_on", {"id": &"palm_l"}),
		_mark(10, &"fx", {"name": &"palm_trail"}),
		_mark(10, &"hitstop", {"frames": 3}),
		_mark(15, &"hitbox_off", {"id": &"palm_l"}),
		_mark(15, &"cancel_open", {"into": {&"palm": &"palm_cross"}}),
	])
	var read := Marks.read(a)
	assert_eq(read.map(func(m: Dictionary) -> StringName: return m["kind"]),
			[&"hitbox_on", &"fx", &"hitstop", &"hitbox_off", &"cancel_open"])
	assert_eq(read.map(func(m: Dictionary) -> int: return Marks.frame_of(m["time"])), [10, 10, 10, 15, 15])
	assert_near(read[0]["time"], read[2]["time"], 0.0, "same frame, same time to the bit: no nudging")


func test_marks_a_hair_apart_both_survive() -> void:
	# Godot merges method keys whose times are nearly equal (about 1e-5 of the time); a mark must not vanish that way.
	var a := _clip()
	Marks.write(a, [{"time": 0.5, "kind": &"fx", "args": {}}, {"time": 0.5 + 1e-6, "kind": &"sfx", "args": {}}, {"time": 0.5 + 5e-5, "kind": &"shake", "args": {}}])
	assert_eq(Marks.read(a).map(func(m: Dictionary) -> StringName: return m["kind"]), [&"fx", &"sfx", &"shake"])


func test_marks_written_survive_a_save_and_load() -> void:
	var a := _clip(0.5833)
	var written := [
		_mark(10, &"hitbox_on", {"id": &"palm_l"}),
		_mark(10, &"hitstop", {"frames": 3}),
		_mark(20, &"cancel_open", {"into": {&"palm": &"palm_cross", &"dodge": &"dodge_roll"}}),
	]
	Marks.write(a, written)
	var read := Marks.read(_saved_and_loaded(a))
	assert_eq(read.size(), 3)
	for i in 3:
		assert_eq(read[i]["kind"], written[i]["kind"], "mark %d" % i)
		assert_eq(read[i]["args"], written[i]["args"], "mark %d" % i)
		assert_near(read[i]["time"], written[i]["time"], 1e-6, "mark %d" % i)


func test_write_replaces_the_marks_it_finds() -> void:
	var a := _clip()
	Marks.write(a, [_mark(10, &"fx"), _mark(10, &"sfx"), _mark(20, &"recovery")])
	Marks.write(a, [_mark(30, &"shake", {"strength": 0.2})])
	var read := Marks.read(a)
	assert_eq(read.size(), 1)
	assert_eq(read[0]["kind"], &"shake")
	assert_eq(a.get_track_count(), 1, "the extra parallel tracks of the first write are gone")


func test_write_leaves_other_tracks_alone() -> void:
	var a := _clip()
	var bone := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(bone, NodePath("Model/Skel:hand_l"))
	a.rotation_track_insert_key(bone, 0.0, Quaternion.IDENTITY)
	var other := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(other, NodePath("Elsewhere"))
	a.track_insert_key(other, 0.2, {"method": &"poke", "args": []})
	Marks.write(a, [_mark(5, &"sfx")])
	Marks.write(a, [_mark(6, &"fx")])
	assert_eq(a.find_track(NodePath("Model/Skel:hand_l"), Animation.TYPE_ROTATION_3D), 0)
	assert_ne(a.find_track(NodePath("Elsewhere"), Animation.TYPE_METHOD), -1)
	assert_eq(a.get_track_count(), 3)
	assert_eq(Marks.read(a).size(), 1, "the other method track is not a mark")


func test_writing_no_marks_removes_the_track() -> void:
	var a := _clip()
	Marks.write(a, [_mark(5, &"sfx")])
	Marks.write(a, [])
	assert_eq(a.get_track_count(), 0)
	assert_eq(Marks.read(a), [])


func test_a_clip_without_marks_reads_empty() -> void:
	assert_eq(Marks.read(_clip()), [])


func test_read_hands_out_copies() -> void:
	var a := _clip()
	Marks.write(a, [_mark(5, &"fx", {"name": &"dust"})])
	(Marks.read(a)[0]["args"] as Dictionary)["name"] = &"changed"
	assert_eq(Marks.read(a)[0]["args"], {"name": &"dust"})


func test_write_copies_what_it_is_given() -> void:
	var a := _clip()
	var args := {"name": &"dust"}
	Marks.write(a, [_mark(5, &"fx", args)])
	args["name"] = &"changed"
	assert_eq(Marks.read(a)[0]["args"], {"name": &"dust"})


func test_a_key_that_is_not_a_mark_is_skipped() -> void:
	var a := _clip()
	var t := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(t, Marks.TRACK)
	a.track_insert_key(t, 0.1, {"method": &"fx", "args": []})
	a.track_insert_key(t, 0.2, {"method": &"sfx", "args": [{"name": &"x"}]})
	var read := Marks.read(a)
	assert_eq(read.size(), 2, "a key with no argument is a mark with no args")
	assert_eq(read[0]["args"], {})
	assert_eq(read[1]["args"], {"name": &"x"})


func test_between_is_half_open_and_includes_time_zero_from_negative() -> void:
	var m := [{"time": 0.0, "kind": &"sfx", "args": {}}, {"time": 10 / 60.0, "kind": &"hitbox_on", "args": {}}]
	assert_eq(Marks.between(m, -1.0, 0.0).size(), 1); assert_eq(Marks.between(m, 0.0, 10 / 60.0).size(), 1)


func test_between_excludes_its_start_and_includes_its_end() -> void:
	var m := [_mark(10, &"fx")]
	assert_eq(Marks.between(m, 9 / 60.0, 10 / 60.0).size(), 1, "the end is in")
	assert_eq(Marks.between(m, 10 / 60.0, 11 / 60.0).size(), 0, "the start is out")
	assert_eq(Marks.between(m, 0.0, 9 / 60.0).size(), 0)
	assert_eq(Marks.between(m, 11 / 60.0, 12 / 60.0).size(), 0)


func test_between_keeps_the_order_of_the_marks() -> void:
	var m := [_mark(5, &"sfx"), _mark(10, &"fx"), _mark(10, &"hitstop", {"frames": 3}), _mark(15, &"recovery")]
	var found := Marks.between(m, 4 / 60.0, 12 / 60.0)
	assert_eq(found.map(func(x: Dictionary) -> StringName: return x["kind"]), [&"sfx", &"fx", &"hitstop"])


func test_every_mark_of_a_saved_clip_is_met_exactly_once_frame_by_frame() -> void:
	# A saved clip keeps times as 32-bit floats, a hair off the exact 10 / 60; a frame-by-frame walk must
	# still meet each mark on its own frame, and only once.
	var a := _clip(1.0)
	var frames := [0, 1, 5, 7, 10, 11, 13, 20, 29, 33, 35, 41, 59]
	Marks.write(a, frames.map(func(f: int) -> Dictionary: return _mark(f, &"fx")))
	var marks := Marks.read(_saved_and_loaded(a))
	var met := {}
	var previous := -1.0
	for f in 60:
		var t := Marks.time_of(f)
		for m in Marks.between(marks, previous, t):
			assert_false(met.has(f), "frame %d meets a mark twice" % f)
			met[f] = Marks.frame_of(m["time"])
		previous = t
	for f in frames:
		assert_eq(met.get(f, -1), f, "the mark of frame %d is met on frame %d" % [f, f])
	assert_eq(met.size(), frames.size())


func test_marks_written_here_survive_a_library_rebuild() -> void:
	# ClipBuilder.merge_kept_tracks is what keeps hand-added tracks when the library is rebuilt.
	var old := _clip()
	Marks.write(old, [_mark(10, &"fx"), _mark(10, &"sfx"), _mark(20, &"recovery")])
	var rebuilt := _clip()
	var bone := rebuilt.add_track(Animation.TYPE_ROTATION_3D)
	rebuilt.track_set_path(bone, NodePath("Model/Skel:hand_l"))
	ClipBuilder.merge_kept_tracks(rebuilt, old)
	var read := Marks.read(rebuilt)
	assert_eq(read.map(func(m: Dictionary) -> StringName: return m["kind"]), [&"fx", &"sfx", &"recovery"])
