extends TestCase
## TimelineBuilder: a scene's shots as one Animation an AnimationPlayer plays (and the owner can edit). Pure data in,
## an Animation out; nothing here plays it.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# The track of this kind at this path, or -1.
func _track(anim: Animation, type: int, path: String) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == type and String(anim.track_get_path(i)) == path:
			return i
	return -1


# Every key time of a track, in frames (the times are k / 60).
func _frames_of(anim: Animation, track: int) -> Array[int]:
	var frames: Array[int] = []
	for key in anim.track_get_key_count(track):
		frames.append(roundi(anim.track_get_key_time(track, key) * 60.0))
	return frames


# Every _cue call of the animation, as [frame, kind, payload], in the order they are made: by time, and by track
# among calls at one time.
func _calls(anim: Animation) -> Array:
	var calls: Array = []
	for track in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		assert_eq(String(anim.track_get_path(track)), "Director", "every call is on the Director")
		for key in anim.track_get_key_count(track):
			var call := anim.method_track_get_name(track, key)
			assert_eq(call, &"_cue")
			var args := anim.method_track_get_params(track, key)
			calls.append([roundi(anim.track_get_key_time(track, key) * 60.0), args[0], args[1], track])
	calls.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[3] < b[3]))
	return calls


func _equal(a: Animation, b: Animation) -> bool:
	if a.length != b.length or a.get_track_count() != b.get_track_count():
		return false
	for i in a.get_track_count():
		if a.track_get_type(i) != b.track_get_type(i) or a.track_get_path(i) != b.track_get_path(i):
			return false
		if a.track_get_interpolation_type(i) != b.track_get_interpolation_type(i) or a.track_get_key_count(i) != b.track_get_key_count(i):
			return false
		if a.track_get_type(i) == Animation.TYPE_VALUE and a.value_track_get_update_mode(i) != b.value_track_get_update_mode(i):
			return false
		for k in a.track_get_key_count(i):
			if a.track_get_key_time(i, k) != b.track_get_key_time(i, k) or var_to_str(a.track_get_key_value(i, k)) != var_to_str(b.track_get_key_value(i, k)):
				return false
	return true


func test_the_timeline_is_as_long_as_the_scene() -> void:
	var scene := _fixture()
	var anim := TimelineBuilder.build(scene)
	assert_true(anim != null, "the fixture builds: %s" % TimelineBuilder.last_error)
	if anim == null:
		return
	assert_near(anim.length, 330.0 / 60.0, 1e-9, "30 in, 270 of shots, 30 out")
	assert_eq(anim.length, scene.total_frames() / 60.0)
	assert_eq(anim.loop_mode, Animation.LOOP_NONE)
	assert_eq(TimelineBuilder.last_error, "", "a scene that builds leaves no error")


func test_shot_keys_fall_on_each_shots_start_plus_the_lead_in() -> void:
	var anim := TimelineBuilder.build(_fixture())
	var track := _track(anim, Animation.TYPE_VALUE, "CineCamera:shot")
	assert_true(track >= 0, "a value track on CineCamera:shot")
	assert_eq(_frames_of(anim, track), [30, 120, 180, 240] as Array[int])
	assert_eq(anim.value_track_get_update_mode(track), Animation.UPDATE_DISCRETE, "a shot is never between two")
	assert_eq(anim.track_get_interpolation_type(track), Animation.INTERPOLATION_NEAREST)
	for i in 4:
		assert_eq(anim.track_get_key_value(track, i), i, "the index of the shot")
	# The progress: 0 at a shot's start and 1 at its end, a straight line between, a cut from the one to the next.
	var progress := _track(anim, Animation.TYPE_VALUE, "CineCamera:progress")
	assert_true(progress >= 0)
	assert_eq(anim.track_get_interpolation_type(progress), Animation.INTERPOLATION_LINEAR)
	assert_eq(anim.value_track_get_update_mode(progress), Animation.UPDATE_CONTINUOUS)
	for shot in [[30, 90], [120, 60], [180, 60], [240, 60]]:
		var start: int = shot[0]
		var length: int = shot[1]
		assert_near(anim.value_track_interpolate(progress, start / 60.0), 0.0, 1e-6, "0 on the shot's first frame (%d)" % start)
		assert_near(anim.value_track_interpolate(progress, (start + length / 2.0) / 60.0), 0.5, 1e-3, "half-way is 0.5")
		assert_near(anim.value_track_interpolate(progress, (start + length - 1) / 60.0), (length - 1) / float(length), 5e-3, "linear to the last frame")
		assert_near(anim.value_track_interpolate(progress, (start + length) / 60.0 - TimelineBuilder.PROGRESS_EDGE), 1.0, 1e-6, "1 at its end")
	assert_near(anim.value_track_interpolate(progress, 300 / 60.0), 1.0, 1e-6, "held at 1 for the glide out")
	assert_near(anim.value_track_interpolate(progress, 120 / 60.0), 0.0, 1e-6, "and the next shot starts again at 0 on its first frame: a cut")


func test_every_beat_line_and_cue_is_one_call_at_its_frame_in_order() -> void:
	var scene := _fixture()
	var calls := _calls(TimelineBuilder.build(scene))
	# frame (scene frame + the lead in), kind, and a field that says which it is
	var seen: Array = []
	for call in calls:
		var payload: Dictionary = call[2]
		var which: Variant = payload.get("actor", payload.get("id", payload.get("speaker", "")))
		seen.append([call[0], call[1], which])
	var expected := [
		[30, &"beat", &"knuckle"], [30, &"beat", &"abarax"],
		[120, &"beat", &"knuckle"], [120, &"beat", &"abarax"], [120, &"sound", &"cloth_move"], [134, &"beat", &"abarax"],
		[180, &"line", &"fixture_knuckle"], [180, &"music", &"fixture_sting"],
		[240, &"line", &"abarax"],
		[285, &"end", ""],
	]
	assert_eq(seen, expected)
	assert_eq(calls.size(), 10, "nothing else is called")
	# What a call carries is what the data says.
	var first: Dictionary = calls[0][2]
	assert_eq(first.move_to, &"foe_stop")
	assert_eq(first.actor, &"knuckle")
	var loop: Dictionary = calls[2][2]
	assert_eq([loop.clip, loop.loop], [&"knuckle_idle", true])
	var line: Dictionary = calls[6][2]
	assert_eq([line.text, line.expr, line.hold], ["Fixture line one.", &"neutral", 54])
	var sound: Dictionary = calls[4][2]
	assert_eq([sound.id, sound.at_ref], [&"cloth_move", &"knuckle"])
	assert_eq(calls[9][0], scene.total_frames() - scene.lead_out - TimelineBuilder.RETURN_BLEND, "the end is the last shot's end minus the return blend")
	for call in calls:
		assert_eq(call[1] is StringName, true)


func test_building_twice_gives_equal_animations() -> void:
	var one := TimelineBuilder.build(_fixture())
	var two := TimelineBuilder.build(_fixture())
	assert_true(one != two, "two animations")
	assert_true(_equal(one, two), "the same tracks and keys")
	var other := _fixture()
	other.shots[1].beats[0].clip = &"idle"
	assert_false(_equal(one, TimelineBuilder.build(other)), "and a change shows")


func test_a_letterboxed_scene_slides_the_bars_in_and_out_and_a_mini_has_none() -> void:
	var mini := TimelineBuilder.build(_fixture())
	assert_eq(_track(mini, Animation.TYPE_VALUE, "CineCamera:letterbox"), -1, "a mini-cutscene has no bars")
	var scene := _fixture()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.letterbox = true
	scene.lead_in = 45
	var anim := TimelineBuilder.build(scene)
	assert_true(anim != null, TimelineBuilder.last_error)
	var track := _track(anim, Animation.TYPE_VALUE, "CineCamera:letterbox")
	assert_true(track >= 0)
	assert_eq(anim.track_get_interpolation_type(track), Animation.INTERPOLATION_LINEAR)
	var total := scene.total_frames()
	assert_eq(_frames_of(anim, track), [0, 30, total - 30, total] as Array[int], "in over 30 frames, out over the last 30")
	assert_near(anim.value_track_interpolate(track, 0.0), 0.0, 1e-9)
	assert_near(anim.value_track_interpolate(track, 15 / 60.0), 0.5, 1e-6, "half in at 15")
	assert_near(anim.value_track_interpolate(track, 30 / 60.0), 1.0, 1e-9)
	assert_near(anim.value_track_interpolate(track, (total / 2) / 60.0), 1.0, 1e-9, "full between")
	assert_near(anim.value_track_interpolate(track, (total - 15) / 60.0), 0.5, 1e-6, "half out 15 frames from the end")
	assert_near(anim.value_track_interpolate(track, total / 60.0), 0.0, 1e-9, "gone at the end")
	assert_eq(_track(anim, Animation.TYPE_VALUE, "CineCamera:shot") >= 0, true)


func test_a_list_with_a_gap_or_an_overlap_is_not_built() -> void:
	var gap := _fixture()
	gap.shots[1].start += 10
	gap.shots[2].start += 10
	gap.shots[3].start += 10
	var built: Variant = quietly(func() -> Variant: return TimelineBuilder.build(gap))
	assert_true(built == null, "a gap: no animation")
	assert_true(TimelineBuilder.last_error.contains("gap of 10 frames"), TimelineBuilder.last_error)
	assert_true(TimelineBuilder.last_error.contains("S1") and TimelineBuilder.last_error.contains("S2"), "naming the shots: " + TimelineBuilder.last_error)
	var overlap := _fixture()
	overlap.shots[2].start -= 12
	overlap.shots[3].start -= 12
	built = quietly(func() -> Variant: return TimelineBuilder.build(overlap))
	assert_true(built == null, "an overlap: no animation")
	assert_true(TimelineBuilder.last_error.contains("overlap of 12 frames"), TimelineBuilder.last_error)
	var short := _fixture()
	short.shots[3].length = 5
	built = quietly(func() -> Variant: return TimelineBuilder.build(short))
	assert_true(built == null, "a shot under 12 frames: no animation")
	assert_true(TimelineBuilder.last_error.contains("12"), TimelineBuilder.last_error)
	assert_true(TimelineBuilder.build(_fixture()) != null, "and the good one builds again, with the error cleared")
	assert_eq(TimelineBuilder.last_error, "")


func test_a_scene_timeline_scene_plays_instead_when_set() -> void:
	var scene := _fixture()
	var generated := TimelineBuilder.player_for(scene)
	track(generated.get_parent())
	assert_true(generated.has_animation(TimelineBuilder.ANIMATION), "the generated animation")
	assert_eq(generated.get_animation(TimelineBuilder.ANIMATION).length, 330.0 / 60.0)
	assert_eq(generated.get_parent().name, &"Cutscene", "in a Cutscene node")
	assert_true(generated.get_parent().get_node_or_null("CineCamera") is CineCamera, "beside a CineCamera")
	# An edited copy: a Cutscene node with its own player and animation.
	var root := Node.new()
	root.name = "Cutscene"
	var mine := AnimationPlayer.new()
	mine.name = "AnimationPlayer"
	root.add_child(mine)
	mine.owner = root
	var library := AnimationLibrary.new()
	var edited := Animation.new()
	edited.length = 2.0
	library.add_animation(&"edited", edited)
	mine.add_animation_library("", library)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK)
	root.free()
	scene.timeline = packed
	var player := TimelineBuilder.player_for(scene)
	track(player.get_parent())
	assert_true(player.has_animation(&"edited"), "the owner's animation plays")
	assert_false(player.has_animation(TimelineBuilder.ANIMATION), "and not the generated one")
	assert_eq(TimelineBuilder.animation_of(player), &"edited")
	assert_eq(TimelineBuilder.animation_of(generated), TimelineBuilder.ANIMATION)


func test_forty_calls_on_one_frame_fire_in_data_order_in_a_scene_of_two_hundred_events() -> void:
	var scene := _fixture()
	var shot := scene.shots[0]
	for i in 40:
		var beat := ActorBeat.new()
		beat.actor = &"abarax"
		beat.at = 0
		beat.face = &"foe_stop"
		beat.blend = 0.001 * (i + 1)  # its number in the data
		shot.beats.append(beat)
	for i in 160:
		var beat := ActorBeat.new()
		beat.actor = &"abarax"
		beat.at = 1 + i % 80
		beat.face = &"foe_stop"
		beat.blend = 5.0 + i
		shot.beats.append(beat)
	var anim := TimelineBuilder.build(scene)
	assert_true(anim != null, TimelineBuilder.last_error)
	var first: Array[float] = []
	for call in _calls(anim):
		if call[0] == 30 and call[1] == &"beat" and call[2].blend < 0.05:
			first.append(call[2].blend)
	assert_eq(first.size(), 40, "all forty are called")
	for i in first.size():
		assert_near(first[i], 0.001 * (i + 1), 1e-9, "call %d is the %dth of the data" % [i, i + 1])


func test_the_builder_refuses_what_the_checker_refuses() -> void:
	var cases := {}
	var lead := _fixture()
	lead.lead_in = 5
	cases["lead_in 5"] = lead
	var blend := _fixture()
	blend.shots[1].blend_in = 70
	cases["blend_in longer than the shot"] = blend
	var late := _fixture()
	late.shots[0].beats[0].at = 95
	cases["a beat past its shot"] = late
	var late_line := _fixture()
	late_line.shots[2].lines[0].at = 70
	cases["a line past its shot"] = late_line
	var aimless := _fixture()
	aimless.shots[3].aim = &""
	cases["no aim"] = aimless
	for name in cases:
		var built: Variant = quietly(func() -> Variant: return TimelineBuilder.build(cases[name]))
		assert_true(built == null, "%s: not built" % name)
		var checker := ShotChecker.new()
		var first := ""
		for line in checker.check(cases[name]):
			if not checker.is_placeholder(line):  # a stand-in portrait is listed, not refused
				first = line
				break
		assert_true(first != "" and TimelineBuilder.last_error == first, "%s: the checker's first problem is the error: '%s'" % [name, TimelineBuilder.last_error])


# The most the picture turns in one frame while the camera glides from a pose at `yaw` back to the game's, over `frames`
# frames of a linear weight (as the Director will ramp it), through CinePose.blend.
func _worst_turn(yaw: float, frames: int) -> float:
	var shown := CinePose.new()
	shown.yaw_deg = yaw
	var home := CinePose.new()
	var worst := 0.0
	var last := yaw
	for i in range(1, frames + 1):
		var now := CinePose.blend(shown, home, float(i) / frames).yaw_deg
		worst = maxf(worst, absf(now - last))
		last = now
	return worst


func test_the_glide_back_from_a_turned_shot_turns_at_most_three_degrees_a_frame_within_sixty_frames() -> void:
	var scene := _fixture()
	assert_eq(TimelineBuilder.return_frames(scene), scene.lead_out, "a shot at yaw 0 returns in the scene's own glide (%d)" % scene.lead_out)
	assert_eq(TimelineBuilder.build(scene).length, scene.total_frames() / 60.0, "and the timeline is as long as before")
	scene.shots[3].yaw_deg = 120.0
	var frames := TimelineBuilder.return_frames(scene)
	assert_true(frames >= 50 and frames <= 60, "120 degrees takes %d frames" % frames)
	assert_true(_worst_turn(120.0, frames) <= 3.0 + 1e-6, "no frame turns more than 3 degrees: %.2f" % _worst_turn(120.0, frames))
	assert_near(TimelineBuilder.build(scene).length, (scene.lead_in + scene.length() + frames) / 60.0, 1e-9, "the timeline's end holds the longer glide")
	scene.shots[3].yaw_deg = 150.0
	assert_eq(TimelineBuilder.return_frames(scene), 60, "and never more than 60")
	scene.shots[3].yaw_deg = -150.0
	assert_eq(TimelineBuilder.return_frames(scene), 60, "either way round")
	scene.shots[3].yaw_deg = 150.0
	scene.lead_out = 80
	assert_eq(TimelineBuilder.return_frames(scene), 80, "a scene's own longer glide is kept")
	var letterboxed := _fixture()
	letterboxed.kind = SceneShots.Kind.CUTSCENE
	letterboxed.letterbox = true
	letterboxed.shots[3].yaw_deg = 120.0
	var anim := TimelineBuilder.build(letterboxed)
	var track := _track(anim, Animation.TYPE_VALUE, "CineCamera:letterbox")
	var end := roundi(anim.length * 60.0)
	assert_eq(_frames_of(anim, track), [0, 30, end - 30, end] as Array[int], "the bars still slide out over the last 30 frames")
