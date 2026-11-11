extends TestCase
## The shot list as data: a scene saves and loads with every field, its lengths add up, and the fixture is what the plan says.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const TEMP := "user://test_shot_data.tres"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


# A scene with a value in every field of every class, none of them the default.
func _full_scene() -> SceneShots:
	var scene := SceneShots.new()
	scene.id = &"full"
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.status = SceneShots.Status.IN_REVIEW
	scene.revision = 3
	scene.region = "res://world/training_yard/training_yard.tscn"
	scene.letterbox = true
	scene.lead_in = 45
	scene.lead_out = 25
	var entry := CastEntry.new()
	entry.actor = &"foe"
	entry.source = CastEntry.Source.SPAWN
	entry.node_name = &"Foe"
	entry.def = load("res://data/actors/knuckle_1.tres")
	entry.spawn_mark = &"in"
	entry.required = false
	entry.after = CastEntry.After.FREE
	entry.speaker = &"abarax"
	scene.cast = [entry] as Array[CastEntry]
	var mark := SceneMark.new()
	mark.name = &"in"
	mark.space = SceneMark.Space.ACTOR_START
	mark.actor = &"foe"
	mark.position = Vector3(1.5, 0.25, -2.0)
	mark.yaw_deg = 135.0
	scene.marks = [mark] as Array[SceneMark]
	var shot := Shot.new()
	shot.id = &"A"
	shot.start = 0
	shot.length = 77
	shot.framing = Shot.Framing.OVER_SHOULDER
	shot.move = Shot.CamMove.ORBIT
	shot.action = "words"
	shot.aim = &"foe"
	shot.aim_to = &"in"
	shot.aim_height = 1.4
	shot.zoom = 3
	shot.zoom_to = 4
	shot.yaw_deg = 30.0
	shot.yaw_to_deg = 90.0
	shot.pitch_deg = -50.0
	shot.pitch_to_deg = -60.0
	shot.shake = 0.5
	shot.over_shoulder = &"foe"
	shot.focus = &"foe"
	shot.focus_to = &"in"
	shot.blend_in = 9
	shot.key_frame = 11
	var beat := ActorBeat.new()
	beat.actor = &"foe"
	beat.at = 5
	beat.clip = &"idle"
	beat.loop = true
	beat.blend = 0.25
	beat.move_to = &"in"
	beat.pace = ActorBeat.Pace.JOG
	beat.face = &"in"
	beat.look = &"foe"
	beat.placeholder = true
	shot.beats = [beat] as Array[ActorBeat]
	var line := DialogueLine.new()
	line.speaker = &"abarax"
	line.text = "A line."
	line.expr = &"smile"
	line.at = 4
	line.hold = 60
	shot.lines = [line] as Array[DialogueLine]
	var cue := CueEvent.new()
	cue.at = 3
	cue.kind = CueEvent.Kind.MUSIC
	cue.id = &"sting"
	cue.at_ref = &"in"
	shot.cues = [cue] as Array[CueEvent]
	scene.shots = [shot] as Array[Shot]
	var timeline := PackedScene.new()
	timeline.pack(Node.new())
	scene.timeline = timeline
	return scene


# Every stored property of `a` equals `b`'s, nested resources and arrays of them included.
func _same_fields(a: Variant, b: Variant, where: String) -> void:
	if a is Resource and b is Resource:
		if (a as Resource).resource_path != "" and not (a as Resource).resource_path.contains("::"):
			assert_eq((b as Resource).resource_path, (a as Resource).resource_path, where)
			return
		assert_eq((b as Resource).get_script(), (a as Resource).get_script(), where + " script")
		for info in (a as Resource).get_property_list():
			if info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and info.usage & PROPERTY_USAGE_STORAGE:
				_same_fields((a as Resource).get(info.name), (b as Resource).get(info.name), where + "." + info.name)
	elif a is Array and b is Array:
		assert_eq((b as Array).size(), (a as Array).size(), where + " size")
		for i in mini((a as Array).size(), (b as Array).size()):
			_same_fields(a[i], b[i], "%s[%d]" % [where, i])
	else:
		assert_eq(b, a, where)


func test_a_scene_saves_and_loads_with_every_field() -> void:
	var scene := _full_scene()
	assert_eq(ResourceSaver.save(scene, TEMP), OK)
	var loaded := ResourceLoader.load(TEMP, "", ResourceLoader.CACHE_MODE_IGNORE) as SceneShots
	assert_true(loaded != null, "the saved scene loads as a SceneShots")
	if loaded == null:
		return
	_same_fields(scene, loaded, "scene")
	assert_eq(loaded.shots[0].beats[0].blend, 0.25)
	assert_eq(loaded.cast[0].def.id, &"knuckle_1")


func test_total_frames_and_shot_at() -> void:
	var scene := SceneShots.new()
	scene.lead_in = 30
	scene.lead_out = 30
	var first := Shot.new()
	first.length = 90
	var second := Shot.new()
	second.start = 90
	second.length = 60
	scene.shots = [first, second] as Array[Shot]
	assert_eq(scene.length(), 150)
	assert_eq(scene.total_frames(), 210)
	assert_eq(scene.shot_at(0), 0)
	assert_eq(scene.shot_at(89), 0)
	assert_eq(scene.shot_at(90), 1)
	assert_eq(scene.shot_at(149), 1)
	assert_eq(scene.shot_at(150), -1)
	assert_eq(scene.shot_at(-1), -1)


func test_cast_entry_and_mark_are_found_by_name() -> void:
	var scene := _full_scene()
	assert_eq(scene.cast_entry(&"foe").node_name, &"Foe")
	assert_eq(scene.cast_entry(&"nobody"), null)
	assert_eq(scene.mark(&"in").yaw_deg, 135.0)
	assert_eq(scene.mark(&"nowhere"), null)


func test_the_fixture_loads_and_is_a_mini_of_330_frames() -> void:
	var scene := load(FIXTURE) as SceneShots
	assert_true(scene != null, "the fixture loads as a SceneShots")
	if scene == null:
		return
	assert_eq(scene.id, &"fixture_yard_entrance")
	assert_eq(scene.kind, SceneShots.Kind.MINI)
	assert_eq(scene.status, SceneShots.Status.DRAFT)
	assert_eq(scene.length(), 270)
	assert_eq(scene.total_frames(), 330)
	assert_eq(scene.shots.size(), 4)
	assert_eq(scene.cast.size(), 2)
	assert_eq(scene.cast_entry(&"abarax").source, CastEntry.Source.LIVE_PLAYER)
	assert_eq(scene.cast_entry(&"knuckle").def.id, &"knuckle_1")
	assert_eq(scene.cast_entry(&"knuckle").after, CastEntry.After.ENEMY_BRAIN)
