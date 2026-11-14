extends TestCase
## What the player and the foes owe each other at the hand-back (the controller's rulings for this task): nothing lands on him as the
## scene ends and every foe begins a fresh attack with its whole tell; what he mashed through the scene is dead until he lets it go;
## a scene is not fight time (the bars, the clocks, the effects of a stopped move); and a scene can be paused through the real menu.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const KNUCKLE := "res://data/actors/knuckle_1.tres"
const MAIN := "res://main/main.tscn"
const C := MenuNav.Cmd

var _finished: Array = []


func before_each() -> void:
	Game.reset()
	Game.change(Game.State.PLAY)
	StoryLog.forget_all()
	Director.reset_spawn_counts()
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.GAMEPAD
	_finished = []


func after_each() -> void:
	_key(KEY_W, false)
	_key(KEY_ESCAPE, false)
	for action in [&"palm", &"heavy", &"guard", &"dodge", &"menu"]:
		Input.action_release(action)
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
	director.finished.connect(func(_skipped: bool) -> void: _finished.append(true))
	return director


func _until_hand_back(director: Director, limit := 500) -> void:
	var n := 0
	while is_instance_valid(director) and director.phase != Director.Phase.LEAD_OUT and n < limit:
		await frames(1)
		n += 1


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# The moves `actor` starts from now on, as [id, frames since `from`].
func _watch(actor: Actor, from: Array) -> Array:
	var started := []
	actor.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, m.kind, actor.frame - from[0]]))
	return started


# --- ruling 2: nothing lands on him as the scene ends ---

func test_a_blow_two_frames_from_landing_never_lands_and_the_foe_swings_again_later() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var player: Actor = parts.player
	var def := load(KNUCKLE) as ActorDef
	var behind := player.global_position - player.facing() * 1.3
	var foe := TestArena.spawn(parts.region, def, EnemyBrain.new(def.brain, 11), behind, "Foe")
	foe.place(Transform3D(Basis(Vector3.UP, Locomotion.yaw_of(Vector2(player.global_position.x - behind.x, player.global_position.z - behind.z))), behind))
	await frames(2)
	# play until the foe's swing is two frames from its first hitbox
	var near := false
	var guard := 0
	while not near and guard < 900:
		await frames(1)
		guard += 1
		var move := foe.runner.current
		if move != null and move.kind == MoveData.Kind.ATTACK:
			var on := INF
			for mark in Marks.read(foe.rig.tree.get_animation(move.clip)):
				if mark["kind"] == &"hitbox_on":
					on = mark["time"]
					break
			near = foe.runner.time >= on - 2.0 / 60.0 - 0.0001 and foe.runner.time < on
	assert_true(near, "the foe's swing was caught two frames from landing")
	if not near:
		return
	var hp := player.stats.hp
	var posture := player.stats.posture
	var director := _start(parts)
	assert_true(director != null, "taken: %s" % Director.last_refusal)
	if director == null:
		return
	assert_true(foe.runner.current == null, "his swing is stopped as the cast's moves are")
	assert_false(foe.rig.aura_active(), "and the tell on his body is out")
	assert_eq(foe.rig.active_hitboxes(), [] as Array[StringName], "no hitbox is on")
	var started := _watch(foe, [0])
	await _until_hand_back(director)
	assert_eq(player.stats.hp, hp, "nothing landed on him during the scene")
	assert_eq(started.filter(func(s: Array) -> bool: return s[1] == MoveData.Kind.ATTACK), [], "and the foe began no attack in it")
	var handed := foe.frame
	started.clear()
	var attack_at := -1
	for i in 260:
		await frames(1)
		var swings := started.filter(func(s: Array) -> bool: return s[1] == MoveData.Kind.ATTACK)
		if attack_at < 0 and not swings.is_empty():
			attack_at = foe.frame - handed
		if i == 29:
			assert_eq(player.stats.hp, hp, "he took no damage in the 30 frames after the hand-back")
			assert_eq(player.stats.posture, posture, "nor posture")
			assert_eq(swings, [], "and no foe has begun an attack")
	assert_true(attack_at >= 30, "the first attack began %d frames after the hand-back, not before 30" % attack_at)
	assert_true(attack_at <= 240, "and the foe attacks again within 4 s (%d frames)" % attack_at)
	assert_true(foe.brain is EnemyBrain, "he has his own mind back")


# --- ruling 3: what was mashed through the scene is dead ---

func test_buttons_pressed_during_the_scene_do_nothing_at_hand_back() -> void:
	for action: StringName in [&"palm", &"dodge", &"heavy", &"guard", &"menu"]:
		var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
		await frames(3)
		var player: Actor = parts.player
		var director := _start(parts)
		assert_true(director != null)
		if director == null:
			return
		while director.frame < 100:
			await frames(1)
		Input.action_press(action)
		var started := _watch(player, [player.frame])
		await _until_hand_back(director)
		var pressed_after := 0
		for i in 15:
			if Inputs.pressed_this_frame().has(action):
				pressed_after += 1
			assert_false(Inputs.held(action), "%s: dead while it is held across the hand-back (frame %d)" % [action, i])
			await frames(1)
		assert_eq(pressed_after, 0, "%s: no press" % action)
		assert_eq(started, [], "%s: he starts nothing" % action)
		assert_false(Game.state == Game.State.PAUSE, "%s: and no menu" % action)
		Input.action_release(action)
		await frames(2)
		if action == &"palm":
			Input.action_press(action)
			await frames(4)
			Input.action_release(action)
			assert_eq(started.map(func(s: Array) -> StringName: return s[0]).slice(0, 1), [&"palm_jab"], "palm: let go and pressed again, it jabs")
		parts.stage.free()
		await frames(1)
		Input.action_release(action)


func test_a_direction_held_through_the_scene_carries_on() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	_key(KEY_W)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	var from := player.global_position
	for i in 20:
		await frames(1)
	assert_true(player.global_position.distance_to(from) > 0.3, "W held through the scene: he walks on")
	assert_true(player.global_position.z < from.z, "north, as W is")


func test_a_guard_held_since_before_the_scene_carries_on() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	Input.action_press(&"guard")
	await frames(40)
	assert_true(player.guarding, "his guard is up")
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	assert_true(Inputs.held(&"guard"), "guard is still held, and not a press that went down in the scene")
	await frames(4)
	assert_true(player.guarding, "and the stance is back")
	assert_true(player.is_guarding())


# --- ruling 5: a scene is not fight time ---

func test_a_scene_is_not_fight_time_for_the_bars_and_the_clocks() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	player.stats.spend_stamina(40.0)
	player.stats.damage_posture(30.0)
	await frames(6)
	var bars := player.stats.save()
	var clock := Game.play_frames
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	var now := player.stats.save()
	for key: String in ["hp", "stamina", "posture", "exhausted", "posture_broken"]:
		assert_eq(now[key], bars[key], "%s is as it was: the scene did not heal him" % key)
	assert_near(now.stamina_idle, bars.stamina_idle, 1.0 / 60.0 + 0.0001, "and the wait for stamina to come back is where it was (a frame on, the hand-back's own)")
	assert_near(now.posture_idle, bars.posture_idle, 1.0 / 60.0 + 0.0001, "and so is the posture's")
	assert_eq(Game.play_frames, clock + 1, "the play clock stood still for the scene (the Hud's blink, the foes' bars, the refusal gate): only the hand-back frame, a fight frame, is in it")
	await frames(1)
	assert_eq(Game.play_frames, clock + 2, "and it goes on after it")


func test_the_effects_of_a_move_the_scene_stopped_are_gone() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var slam := Registry.fetch(&"moves", &"heavy_slam") as MoveData
	var def := load("res://data/actors/knuckle_heavy.tres") as ActorDef
	var big := TestArena.spawn(parts.region, def, Brain.new(), Vector3(-3, 0, 6), "Big")
	await frames(3)
	big.runner.start(slam, true)
	var guard := 0
	while get_tree().get_nodes_in_group(SlamRing.GROUP).is_empty() and guard < 60:
		await frames(1)
		guard += 1
	assert_true(guard < 60, "the slam shows its warning ring")
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await frames(2)
	assert_eq(get_tree().get_nodes_in_group(SlamRing.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()), [], "the ring that belonged to the stopped slam is gone")
	assert_false(big.rig.aura_active(), "and so is its rim")
	await _until_hand_back(director)
	assert_eq(get_tree().get_nodes_in_group(ActorFx.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()), [], "no effect of the fight before the scene is left on at the hand-back")


# --- ruling 1: a scene can be paused, and the menu is how ---

# Main in the yard, its foes without a mind, two frames in.
func _main() -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	for foe in main.arena().enemies():
		foe.set_brain(Brain.new())
	await frames(2)
	return main


func test_a_scene_can_be_paused_from_the_menu_and_goes_on_from_the_same_frame() -> void:
	var seen := []
	for paused in [false, true]:
		var main := await _main()
		var director := Director.play(&"fixture_yard_entrance", main)
		assert_true(director != null, "the scene plays in the real game: %s" % Director.last_refusal)
		if director == null:
			return
		assert_eq(Game.state, Game.State.CUTSCENE)
		while director.frame < 100:
			await frames(1)
		if paused:
			_key(KEY_ESCAPE)
			_key(KEY_ESCAPE, false)
			assert_eq(Game.state, Game.State.PAUSE, "Esc pauses a scene as it pauses the fight")
			assert_true(main.menu.is_open, "with the menu")
			var overlay: CineOverlay = main.stage.hud.get_children().filter(func(c: Node) -> bool: return c is CineOverlay)[0]
			assert_true(overlay.get_index() < main.menu.get_index(), "the scene's overlay is under the menu, not over it")
			var at := [director.frame, main.player.global_position, main.camera_rig.cine_weight]
			await frames(90)
			assert_eq([director.frame, main.player.global_position, main.camera_rig.cine_weight], at, "nothing of the scene moves while it is paused")
			main.menu.press(C.CHOOSE)  # Resume
			assert_eq(Game.state, Game.State.CUTSCENE, "Resume gives back the scene")
		while director.frame < 200:
			await frames(1)
		var foe: Actor = director.cast[&"knuckle"]
		seen.append([director.frame, main.player.global_position, foe.global_position, main.camera_rig.cine.aim, main.camera_rig.cine_weight, foe.rotation.y])
		main.free()
		await frames(1)
	assert_eq(seen[1], seen[0], "paused for 90 frames, the scene is where an unpaused one is at the same frame")
