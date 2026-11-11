extends TestCase
## The start of the Drummer's string (data/moves/drum_1.tres): it must be told at once from any other attack's start. For the whole of
## its 24 frames of warning the Drummer wears a rim in its own red (the colour on drum_1's tell mark: the palette's wrap red, which no other tell
## uses) and, on its first frame, a deep whoosh no other move makes (the cue whoosh_heavy at half its pitch); at the first blow the rim goes.

const DRUMMER := "res://data/actors/knuckle_drummer.tres"
const RED := Color("d12924")
const WARNING := 24


func _drummer() -> Dictionary:
	var run := Duel.make(self, [{"frames": 200}], [], 6.0, load(DRUMMER) as ActorDef)
	return run


func test_the_warning_is_the_drummers_own_red_rim_from_the_first_frames_to_the_first_blow() -> void:
	var run := _drummer()
	var b: Actor = run["b"]
	b.runner.start(Registry.fetch(&"moves", &"drum_1") as MoveData)
	var colors := {}
	var on_frames := []
	for f in range(1, WARNING + 6):
		await frames(1)
		if b.rig.aura_active():
			on_frames.append(f)
			colors[b.rig.aura_color()] = true
	assert_eq(colors.keys(), [RED], "red, and only red")
	assert_true(on_frames.size() >= WARNING - 3, "the rim is up for the warning (frames %s)" % [on_frames])
	assert_true(on_frames.min() <= 2, "from its first frames (%d)" % on_frames.min())
	assert_true(on_frames.max() <= WARNING + 1, "and gone with the first blow (last frame %d)" % on_frames.max())
	assert_false(b.rig.aura_active(), "off")


func test_no_other_tell_is_that_red_and_the_cue_is_the_drummers_own() -> void:
	# Every other attack mark in the game gets the tuning's blue-white or rose; no clip but drum_1's tell carries a colour.
	var run := _drummer()
	var b: Actor = run["b"]
	for clip in b.rig.tree.get_animation_list():
		for m in Marks.read(b.rig.tree.get_animation(clip)):
			if m["kind"] == &"tell" and m["args"].has("color"):
				assert_eq(clip, &"drum_1", "only drum_1's tell has a colour")
				assert_eq(Color(String(m["args"]["color"])), RED)
			if m["kind"] == &"sfx" and m["args"].has("pitch"):
				assert_eq(clip, &"drum_1", "only drum_1 sounds at a pitch of its own")
				assert_eq([m["args"]["name"], m["args"]["pitch"]], [&"whoosh_heavy", 0.5], "a deep whoosh")
	b.runner.start(Registry.fetch(&"moves", &"drum_1") as MoveData)
	var played := Sfx.last_played()
	var pitches := Sfx.last_pitches()
	var at := played.find(&"whoosh_heavy")
	assert_true(at >= 0, "it sounds on the first frame: %s" % [played])
	assert_near(pitches[at], 0.5, 1e-6, "at half the pitch")
	assert_true(played.has(&"tell_glint"), "with the glint's cue as every tell")
