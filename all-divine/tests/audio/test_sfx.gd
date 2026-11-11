extends TestCase
## The sound cues in data/sounds/ (the Registry kind `sounds`) and the Sfx autoload that plays them.
##
## Headless, the audio server is a dummy one that does not mix in step with the test clock, so a sound that
## starts keeps reporting `playing` however many frames pass: the tests read what started, not what finished.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
## Every cue the marks, the hit profiles and the actor defs name, and how many files it groups.
const CUES := {
	&"impact_palm": 3, &"impact_heavy": 2, &"palm_whoosh": 3, &"whoosh_light": 3, &"whoosh_heavy": 1,
	&"guard_block": 2, &"parry_ring": 1, &"catch_snap": 1, &"perilous_sting": 1, &"tell_glint": 1,
	&"cloth_move": 1, &"foot_land": 1, &"surface_cloth": 2, &"body_fall": 1, &"charge_hum": 1,
}


func before_each() -> void:
	_silence()


func after_each() -> void:
	_silence()


# Stops every voice that is playing, so that a test starts with a free pool.
func _silence() -> void:
	for node in Sfx.playing_nodes():
		node.stop()


func _cue(id: StringName) -> SoundCue:
	return Registry.fetch(&"sounds", id) as SoundCue


func test_every_cue_exists_and_groups_its_files() -> void:
	for id: StringName in CUES:
		var cue := _cue(id)
		assert_ne(cue, null, "the cue %s" % id)
		if cue == null:
			continue
		assert_eq(cue.id, id)
		assert_eq(cue.streams.size(), CUES[id], "%s groups %d files" % [id, CUES[id]])
		for stream in cue.streams:
			assert_true(stream is AudioStream and stream.get_length() > 0.03, "%s: a real sound" % id)


func test_the_two_whoosh_cues_share_the_light_whooshes() -> void:
	var a := _cue(&"palm_whoosh")
	var b := _cue(&"whoosh_light")
	assert_eq(a.streams, b.streams, "palm_whoosh is whoosh_light under the name the palm marks use")
	for i in 3:
		assert_eq(a.streams[i].resource_path.get_file(), "whoosh_light_%d.wav" % (i + 1))


func test_cues_play_on_the_sfx_bus_that_the_project_has() -> void:
	assert_eq(SoundCue.new().bus, &"SFX", "the default bus is the project's SFX bus")
	assert_ne(AudioServer.get_bus_index(&"SFX"), -1, "and the project has it")
	for id: StringName in CUES:
		assert_eq(_cue(id).bus, &"SFX", id)
		assert_true(_cue(id).pitch_jitter >= 0.0 and _cue(id).pitch_jitter <= 0.15, "%s: a small jitter" % id)


func test_a_sound_with_no_position_plays_on_a_flat_voice() -> void:
	Sfx.play(&"impact_palm")
	var playing := Sfx.playing_nodes()
	assert_eq(playing.size(), 1)
	assert_true(playing[0] is AudioStreamPlayer, "a 2D player: %s" % [playing])
	assert_eq(playing[0].bus, &"SFX")
	assert_eq(Sfx.last_played(), [&"impact_palm"] as Array[StringName])


func test_a_sound_at_a_point_plays_on_a_positional_voice_there() -> void:
	Sfx.play(&"impact_heavy", Vector3(1.0, 2.0, 3.0))
	var playing := Sfx.playing_nodes()
	assert_eq(playing.size(), 1)
	assert_true(playing[0] is AudioStreamPlayer3D, "a 3D player: %s" % [playing])
	assert_vec_near((playing[0] as AudioStreamPlayer3D).global_position, Vector3(1.0, 2.0, 3.0), 1e-5)
	assert_eq(playing[0].bus, &"SFX")


func test_an_empty_id_plays_nothing() -> void:
	Sfx.play(&"")
	Sfx.play(&"", Vector3.ONE)
	assert_eq(Sfx.playing_nodes().size(), 0)
	assert_eq(Sfx.last_played().size(), 0)
	assert_eq(Sfx.last_unknown().size(), 0, "an empty id is no cue, not a wrong one")


func test_an_unknown_id_warns_plays_nothing_and_is_recorded() -> void:
	quietly(func() -> void: Sfx.play(&"no_such_cue"))
	assert_eq(Sfx.playing_nodes().size(), 0)
	assert_eq(Sfx.last_played().size(), 0)
	assert_eq(Sfx.last_unknown(), [&"no_such_cue"] as Array[StringName])


func test_what_was_played_is_forgotten_with_the_frame() -> void:
	Sfx.play(&"foot_land")
	Sfx.play(&"surface_cloth")
	quietly(func() -> void: Sfx.play(&"no_such_cue"))
	assert_eq(Sfx.last_played(), [&"foot_land", &"surface_cloth"] as Array[StringName], "in the order played")
	await frames(1)
	assert_eq(Sfx.last_played().size(), 0, "a frame later")
	assert_eq(Sfx.last_unknown().size(), 0)


func test_the_pool_has_sixteen_voices_and_the_oldest_gives_way() -> void:
	assert_eq(Sfx.VOICES, 16)
	for i in 16:
		Sfx.play(&"body_fall", Vector3(float(i), 0, 0))
	assert_eq(Sfx.playing_nodes().size(), 16, "all sixteen busy")
	var oldest := Sfx.playing_nodes()[0] as AudioStreamPlayer3D
	assert_near(oldest.global_position.x, 0.0, 1e-5, "the first one played")
	Sfx.play(&"charge_hum")
	assert_eq(Sfx.playing_nodes().size(), 16, "a seventeenth takes a voice and adds none")
	assert_false(oldest.playing, "the oldest was cut off")
	assert_true(Sfx.playing_nodes().any(func(n: Node) -> bool: return n is AudioStreamPlayer), "and the new one plays")


func test_pitch_and_volume_follow_the_cue() -> void:
	var cue := _cue(&"tell_glint")
	var seen := {}
	for i in 12:
		Sfx.play(&"tell_glint")
		var voice := Sfx.playing_nodes()[0] as AudioStreamPlayer
		assert_near(voice.volume_db, cue.volume_db, 1e-6)
		assert_true(absf(voice.pitch_scale - 1.0) <= cue.pitch_jitter + 1e-6, "pitch %s within %s" % [voice.pitch_scale, cue.pitch_jitter])
		seen[snappedf(voice.pitch_scale, 0.0001)] = true
		_silence()
	if cue.pitch_jitter > 0.0:
		assert_true(seen.size() > 1, "the pitch varies from play to play")


func test_a_cue_with_variants_does_not_repeat_the_one_it_just_played() -> void:
	var last: AudioStream = null
	for i in 12:
		Sfx.play(&"impact_palm")
		var voice := Sfx.playing_nodes()[0] as AudioStreamPlayer
		assert_ne(voice.stream, last, "play %d is a different file from the last" % i)
		last = voice.stream
		_silence()


func test_positional_sounds_play_inside_the_cameras_world() -> void:
	# The listener is the camera of the viewport the player is in: a voice under the root would be heard by no one.
	var stage := track(STAGE_SCENE.instantiate()) as PixelStage
	var camera := CameraRig.new()
	camera.stage = stage
	stage.world.add_child(camera)
	assert_true(stage.world.audio_listener_enable_3d, "the world hears")
	Sfx.play(&"impact_palm", Vector3(2, 0, 2))
	var voice := Sfx.playing_nodes()[0] as AudioStreamPlayer3D
	assert_eq(voice.get_viewport(), stage.world, "the voice is in the camera's world")
	assert_vec_near(voice.global_position, Vector3(2, 0, 2), 1e-5)


func test_a_world_that_is_gone_does_not_take_the_pool_with_it() -> void:
	var stage := STAGE_SCENE.instantiate() as PixelStage
	add_child(stage)
	var camera := CameraRig.new()
	camera.stage = stage
	stage.world.add_child(camera)
	for i in 16:
		Sfx.play(&"foot_land", Vector3(float(i), 0, 0))
	stage.free()
	for i in 20:
		Sfx.play(&"foot_land", Vector3(float(i), 0, 0))
	Sfx.play(&"foot_land")
	assert_eq(Sfx.playing_nodes().size(), 16, "sixteen voices still")
