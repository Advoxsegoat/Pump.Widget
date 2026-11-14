extends TestCase
## Casts the fixture does not have (fix round 1, item 6), through the real Main: a scene with the player alone in the cast, and one
## with no player in it at all. The start, the hand-back and the buttons rule hold for both. With no player in the cast he is a
## bystander like any foe that is not in it: his brain is muted and he is held, so what he can do during the scene is nothing (the
## stick and every button go nowhere), and he has his hands back at the hand-back like everyone.

const MAIN := "res://main/main.tscn"
const KNUCKLE := "res://data/actors/knuckle_1.tres"

var _watched: Array = []


func before_each() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	Director.reset_spawn_counts()
	StoryLog.forget_all()
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.GAMEPAD
	_watched = []


func after_each() -> void:
	_key(KEY_W, false)
	for action in [&"palm", &"heavy", &"guard", &"dodge", &"menu"]:
		Input.action_release(action)
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Game.reset()


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _main() -> Main:
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	for foe in main.arena().enemies():
		foe.set_brain(Brain.new())
	await frames(2)
	return main


func _mark(mark_name: StringName, space: SceneMark.Space, at: Vector3, actor := &"") -> SceneMark:
	var mark := SceneMark.new()
	mark.name = mark_name
	mark.space = space
	mark.position = at
	mark.actor = actor
	return mark


# One medium shot of 130 frames on `aim`, with `beats`.
func _scene(id: StringName, cast: Array[CastEntry], marks: Array[SceneMark], aim: StringName, beats: Array[ActorBeat]) -> SceneShots:
	var scene := SceneShots.new()
	scene.id = id
	scene.kind = SceneShots.Kind.MINI
	scene.lead_in = 30
	scene.lead_out = 30
	scene.cast = cast
	scene.marks = marks
	var shot := Shot.new()
	shot.id = &"S1"
	shot.start = 0
	shot.length = 130
	shot.framing = Shot.Framing.MEDIUM
	shot.aim = aim
	shot.beats = beats
	scene.shots = [shot] as Array[Shot]
	return scene


# Abarax alone: he faces a mark ahead of him.
func _alone() -> SceneShots:
	var entry := CastEntry.new()
	entry.actor = &"abarax"
	entry.source = CastEntry.Source.LIVE_PLAYER
	var face := ActorBeat.new()
	face.actor = &"abarax"
	face.face = &"ahead"
	var marks: Array[SceneMark] = [_mark(&"ahead", SceneMark.Space.ACTOR_START, Vector3(0, 0, 3), &"abarax"), _mark(&"rehearsal.abarax", SceneMark.Space.REGION, Vector3(0, 0, 5))]
	return _scene(&"alone_test", [entry] as Array[CastEntry], marks, &"abarax", [face] as Array[ActorBeat])


# Only a Knuckle, made at a mark: no player in it.
func _no_player(at: Vector3) -> SceneShots:
	var entry := CastEntry.new()
	entry.actor = &"foe"
	entry.source = CastEntry.Source.SPAWN
	entry.def = load(KNUCKLE) as ActorDef
	entry.spawn_mark = &"foe_in"
	entry.after = CastEntry.After.FREE
	var stand := ActorBeat.new()
	stand.actor = &"foe"
	stand.face = &"foe_in"
	var marks: Array[SceneMark] = [_mark(&"foe_in", SceneMark.Space.REGION, at)]
	return _scene(&"no_player_test", [entry] as Array[CastEntry], marks, &"foe_in", [stand] as Array[ActorBeat])


func _play(main: Main, scene: SceneShots) -> Director:
	var director := Director.new()
	if not director.begin(scene, main.region, main.camera_rig, main.hud, main):
		director.free()
		return null
	return director


func _until_hand_back(director: Director, limit := 400) -> void:
	var n := 0
	while is_instance_valid(director) and director.phase != Director.Phase.LEAD_OUT and n < limit:
		await frames(1)
		n += 1


func _watch(actor: Actor) -> Array:
	var log := []
	actor.runner.move_started.connect(func(m: MoveData) -> void: log.append(m.id))
	return log


func test_a_scene_with_the_player_alone_in_the_cast() -> void:
	var main := await _main()
	var player := main.player
	var brain := player.brain
	await frames(3)
	var at := player.global_position
	var head := main.hud.picture_point(player.head_point())
	var director := _play(main, _alone())
	assert_true(director != null, "the scene is taken: %s %s" % [Director.last_refusal, TimelineBuilder.last_error])
	if director == null:
		return
	assert_eq(director.frame, 0)
	assert_vec_near(player.global_position, at, 0.001, "the start: he has not moved a millimetre")
	assert_true(player.brain is DirectorBrain, "and the scene has his hands")
	assert_eq(main.hud.shown_alpha(), 1.0, "and the picture is the game's, Hud and all")
	var worst := 0.0
	var started := _watch(player)
	while director.frame < 40:
		await frames(1)
		var now := main.hud.picture_point(player.head_point())
		worst = maxf(worst, now.distance_to(head))
		head = now
	assert_true(worst <= 12.0, "his head moves at most 12 px a frame across the start (%.1f)" % worst)
	Input.action_press(&"palm")
	_key(KEY_W)
	await _until_hand_back(director)
	assert_eq(started, [], "he started nothing in the scene, whatever was pressed")
	assert_true(player.brain == brain, "the hand-back: his own hands, the same object")
	assert_eq(Game.state, Game.State.PLAY, "in play")
	assert_false(main.hud.suppressed, "the Hud is no longer held")
	var from := player.global_position
	for i in 15:
		assert_false(Inputs.held(&"palm"), "the buttons: palm is dead while it is held across the hand-back (frame %d)" % i)
		await frames(1)
	assert_eq(started, [], "and he jabs nothing")
	assert_true(player.global_position.distance_to(from) > 0.2, "the stick he held carries on")
	Input.action_release(&"palm")
	await frames(2)
	Input.action_press(&"palm")
	await frames(4)
	assert_eq(started.slice(0, 1), [&"palm_jab"], "let go and pressed again, it jabs")


func test_a_scene_with_no_player_in_the_cast_holds_him_like_any_bystander() -> void:
	var main := await _main()
	var player := main.player
	var brain := player.brain
	await frames(3)
	var at := player.global_position
	var scene := _no_player(at + player.facing() * 4.0 + Vector3(0, 0, 0))
	var director := _play(main, scene)
	assert_true(director != null, "the scene is taken: %s %s" % [Director.last_refusal, TimelineBuilder.last_error])
	if director == null:
		return
	assert_eq(director.frame, 0)
	assert_vec_near(player.global_position, at, 0.001, "the start: he has not moved a millimetre")
	assert_false(player.brain is PlayerBrain, "his hands are the scene's: the stick and the buttons go nowhere")
	var started := _watch(player)
	while director.frame < 20:
		await frames(1)
	Input.action_press(&"palm")
	_key(KEY_W)
	await frames(30)
	Input.action_press(&"dodge")
	await _until_hand_back(director)
	assert_eq(started, [], "he did nothing in the scene: no move, whatever he pressed")
	assert_true(player.global_position.distance_to(at) < 0.05, "and went nowhere (%.2f m)" % player.global_position.distance_to(at))
	assert_true(player.brain == brain, "the hand-back: his own hands, the same object")
	assert_eq(Game.state, Game.State.PLAY)
	for i in 15:
		assert_false(Inputs.held(&"palm"), "palm is dead while held across the hand-back (frame %d)" % i)
		assert_false(Inputs.held(&"dodge"), "so is dodge (frame %d)" % i)
		await frames(1)
	assert_eq(started, [], "he jabs and dodges nothing")
	Input.action_release(&"palm")
	await frames(2)
	Input.action_press(&"palm")
	await frames(4)
	assert_eq(started.slice(0, 1), [&"palm_jab"], "let go and pressed again, it jabs")
