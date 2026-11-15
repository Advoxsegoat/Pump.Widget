extends TestCase
## The fixture played end to end: every beat on its frame, the marks on the yard's floor, a clip driven by the Director (no
## mark of it fires), a walk that has arrived by its shot's end.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const YARD := "res://world/training_yard/training_yard.tscn"

var _finished: Array = []


func before_each() -> void:
	RenderingServer.render_loop_enabled = false  # these tests look at no picture: a render run need not draw their frames (it is most of the time)
	Game.reset()
	Game.change(Game.State.PLAY)
	StoryLog.forget_all()
	Director.reset_spawn_counts()
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.GAMEPAD
	_finished = []


func after_each() -> void:
	RenderingServer.render_loop_enabled = true
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Game.reset()


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


func _start(parts: Dictionary, scene: SceneShots = null) -> Director:
	var director := Director.new()
	if not director.begin(scene if scene != null else _fixture(), parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return null
	director.finished.connect(func(skipped: bool) -> void: _finished.append(skipped))
	return director


# Plays frames until the scene is over; how many.
func _play_out(limit := 700) -> int:
	var n := 0
	while _finished.is_empty() and n < limit:
		await frames(1)
		n += 1
	return n


func test_the_fixture_plays_to_the_end_in_360_frames_after_the_wait_with_no_errors() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var director := _start(parts)
	assert_true(director != null, "taken: %s" % Director.last_refusal)
	if director == null:
		return
	# The brief says 330 (30 in, 270 of shots, 30 out). The fixture's last shot is over the shoulder, turned well away from the
	# game's yaw, so by Task 2's ruling (the picture turns at most 3 degrees a frame) its glide home is 60 frames, not 30.
	assert_eq(director.total_frames(), 30 + 270 + 60, "30 in, 270 of shots, 60 out")
	var started: Array[StringName] = []
	director.started.connect(func(id: StringName) -> void: started.append(id))
	var n := await _play_out()
	assert_eq(_finished, [false], "it finishes once, played and not skipped")
	assert_true(n >= 360 and n <= 362, "in %d frames" % n)
	assert_eq(Game.state, Game.State.PLAY, "the game is playing again")
	assert_eq(parts.rig.cine_weight, 0.0, "the camera is the game's")
	assert_false(parts.hud.suppressed, "the Hud is back")
	assert_true(StoryLog.seen(&"fixture_yard_entrance"), "and it is seen")
	await frames(2)
	assert_true(parts.world.get_node_or_null("Cutscene") == null, "the scene's nodes are gone")
	assert_eq(parts.stage.hud.get_children().filter(func(c: Node) -> bool: return c is CineOverlay), [], "and its overlay")
	assert_true(Director.current() == null)


func test_every_beat_happens_at_its_frame() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var foe: Actor = director.cast.get(&"knuckle")
	var lines := {}
	director.line_shown.connect(func(speaker: StringName, text: String) -> void: lines[text] = [director.frame, speaker])
	var music := {}
	director.music_cue.connect(func(id: StringName) -> void: music[id] = director.frame)
	var start_at := foe.global_position
	var first_step := -1
	var clips := {}  # scene frame -> the Abarax's clip
	var cloth := -1
	var played_sting := false
	for i in 340:
		await frames(1)
		if not is_instance_valid(director):
			break
		var f := director.frame
		if first_step < 0 and foe.global_position.distance_to(start_at) > 0.005:
			first_step = f
		clips[f] = _clip_of(player)
		if cloth < 0 and Sfx.last_played().has(&"cloth_move"):
			cloth = f
		played_sting = played_sting or Sfx.last_played().has(&"fixture_sting")
	var lead_in := 30
	assert_true(first_step >= lead_in and first_step <= lead_in + 3, "the Knuckle's first step is at the start of shot 1 (scene frame %d, shot 1 is at %d)" % [first_step, lead_in])
	assert_eq(clips.get(lead_in + 90 + 13), &"guard_raise", "Abarax is in guard_raise the frame before frame 14 of shot 2")
	assert_eq(clips.get(lead_in + 90 + 15), &"guard_hold", "and in guard_hold from it")
	assert_eq(lines.get("Fixture line one."), [lead_in + 150, &"fixture_knuckle"], "line one on its frame, by the Knuckle")
	assert_eq(lines.get("Fixture line two."), [lead_in + 210, &"abarax"], "line two on its frame, by Abarax")
	assert_eq(cloth, lead_in + 90 + 1, "the cloth_move cue sounds on the first frame of shot 2")
	assert_eq(music.get(&"fixture_sting"), lead_in + 150, "the music cue is signalled on its frame")
	assert_false(played_sting, "and nothing is played for it")


# The clip the move layer of `actor`'s rig is set to (the one slot it last played into), or empty.
func _clip_of(actor: Actor) -> StringName:
	var slot: int = actor.rig._slot
	if slot < 0:
		return &""
	return (actor.rig.tree.tree_root.get_node(Rig.SLOT_NODES[slot]) as AnimationNodeAnimation).animation


func test_the_fixture_marks_stand_on_the_yard_floor() -> void:
	var yard := track((load(YARD) as PackedScene).instantiate()) as Node3D
	await frames(2)
	var space := yard.get_world_3d().direct_space_state
	var spawn := (yard.get_node("Spawn") as Node3D).global_position
	var lines := ShotChecker.new().check_place(_fixture(), space, spawn)
	assert_eq(lines, PackedStringArray(), "every mark has the yard's floor under it, room for a body, and a way to it")
	# and the ones a live start makes: Abarax at the rehearsal mark, the two foe marks in his space
	var scene := _fixture()
	var rehearsal := scene.mark(&"rehearsal.abarax")
	var origin := Transform3D(Basis(Vector3.UP, deg_to_rad(rehearsal.yaw_deg)), rehearsal.position)
	for mark_name in [&"foe_in", &"foe_stop"]:
		var at := origin * scene.mark(mark_name).position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 0.5, Layers.WORLD))
		assert_false(hit.is_empty(), "%s has the floor within 0.5 m under it" % mark_name)


func test_a_clip_is_driven_by_the_director_and_fires_no_mark() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var scene := _fixture()
	var beat := scene.shots[1].beats[0]
	assert_eq(beat.clip, &"knuckle_idle")
	beat.clip = &"knuckle_feint"
	beat.loop = false
	var director := _start(parts, scene)
	assert_true(director != null, "taken: %s" % Director.last_refusal)
	if director == null:
		return
	var foe: Actor = director.cast.get(&"knuckle")
	var marks: Array[StringName] = []
	foe.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void: marks.append(kind))
	var shown := false
	var hitboxes := 0
	var sounds := 0
	for i in 220:
		await frames(1)
		if not is_instance_valid(director):
			break
		if director.frame > 125 and director.frame < 175:
			shown = shown or _clip_of(foe) == &"knuckle_feint"
		hitboxes += foe.rig.active_hitboxes().size()
		sounds += Sfx.last_played().filter(func(id: StringName) -> bool: return id != &"cloth_move" and id != &"voice_blip").size()
		assert_true(foe.runner.current == null, "no move of the Knuckle's runs")
	assert_true(shown, "the clip is shown on the Knuckle's rig")
	assert_eq(marks, [] as Array[StringName], "no mark of it fires")
	assert_eq(hitboxes, 0, "no hitbox is on")
	assert_eq(sounds, 0, "and no mark makes a sound")


func test_the_walk_arrives_within_arrive_of_its_mark_by_the_shots_end() -> void:
	for pace: ActorBeat.Pace in [ActorBeat.Pace.WALK, ActorBeat.Pace.JOG]:
		var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
		await frames(3)
		var scene := _fixture()
		scene.shots[0].beats[0].pace = pace
		var director := _start(parts, scene)
		assert_true(director != null, "taken: %s" % Director.last_refusal)
		if director == null:
			return
		var foe: Actor = director.cast.get(&"knuckle")
		var stop := Transform3D(Basis(Vector3.UP, deg_to_rad(200.0)), Vector3(3, 0, 4)) * scene.mark(&"foe_stop").position
		var shot_end := scene.lead_in + scene.shots[0].length
		while director.frame < shot_end:
			await frames(1)
		var off := Vector2(foe.global_position.x - stop.x, foe.global_position.z - stop.z).length()
		assert_true(off <= Director.ARRIVE, "%s: within ARRIVE of the mark, %.3f m off" % [pace, off])
		assert_eq(foe.locomotion.speed, 0.0, "%s: and at rest" % pace)
		parts.stage.free()
		await frames(1)
