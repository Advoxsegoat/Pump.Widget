extends TestCase
## The seamless rule, measured: control comes back at the start of the glide home with his old brain, in his old facing and in
## a pose that matches idle; the camera goes home with no jump; nothing but the bars covers the picture; the sticks do not turn with
## the glide; the world holds for the scene and goes on after it; the three kinds differ only as specified.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const ABARAX := "res://data/actors/abarax.tres"

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
	_key(KEY_W, false)
	Melee.slow(0, 1.0)
	Inputs._device = Inputs.Device.KEYBOARD_MOUSE
	Game.reset()


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# The fixture with its last shot a medium one at camera yaw `yaw` (no over-the-shoulder, whose turn is the foes' place).
func _ending_at_yaw(yaw: float) -> SceneShots:
	var scene := _fixture()
	var last := scene.shots[scene.shots.size() - 1]
	last.framing = Shot.Framing.MEDIUM
	last.over_shoulder = &""
	last.yaw_deg = yaw
	return scene


func _start(parts: Dictionary, scene: SceneShots = null) -> Director:
	var director := Director.new()
	if not director.begin(scene if scene != null else _fixture(), parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return null
	director.finished.connect(func(_skipped: bool) -> void: _finished.append(parts.rig.cine_weight))
	return director


func _until_hand_back(director: Director, limit := 500) -> void:
	var n := 0
	while director.phase != Director.Phase.LEAD_OUT and n < limit:
		await frames(1)
		n += 1


func _overlay_of(parts: Dictionary) -> CineOverlay:
	for child in parts.stage.hud.get_children():
		if child is CineOverlay:
			return child
	return null


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_control_returns_at_the_start_of_the_glide_out_with_his_old_brain() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	assert_true(player.brain is DirectorBrain, "during the scene his brain is the scene's")
	assert_eq(Game.state, Game.State.CUTSCENE)
	await _until_hand_back(director)
	assert_eq(director.phase, Director.Phase.LEAD_OUT)
	assert_true(player.brain == parts.brain, "at the frame the glide home begins he has the very PlayerBrain he had")
	assert_eq(Game.state, Game.State.PLAY, "and the game is playing")
	assert_eq(director.frame, 30 + 270 + 1, "on the first frame after the last shot's end")
	assert_true(parts.rig.cine_weight > 0.9, "while the camera is still the scene's")


func test_the_pose_at_hand_back_matches_idle_within_four_degrees() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var player: Actor = parts.player
	# The same body in locomotion idle, in a world of its own that the scene does not touch, named alike (the breath phase).
	var yard := TestArena.make(self)
	var holder := Node3D.new()
	yard.add_child(holder)
	var control := TestArena.spawn(holder, load(ABARAX) as ActorDef, Brain.new(), Vector3.ZERO, "Player")
	await frames(3)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	assert_eq(player.runner.current, null)
	assert_true(player.rig.move_weight() < 0.001, "the move layer has faded out (%s)" % player.rig.move_weight())
	var worst := StoryStage.angle_between(StoryStage.pose_of(player.rig), StoryStage.pose_of(control.rig))
	assert_true(worst <= Director.POSE_MATCH_DEG, "his pose is idle within %.1f degrees (the largest bone, %.2f)" % [Director.POSE_MATCH_DEG, worst])


func test_he_keeps_his_facing_at_hand_back() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	var stop: Vector3 = Transform3D(Basis(Vector3.UP, deg_to_rad(200.0)), Vector3(3, 0, 4)) * director.scene.mark(&"foe_stop").position
	var want := Locomotion.yaw_of(Vector2(stop.x - player.global_position.x, stop.z - player.global_position.z))
	assert_near(rad_to_deg(angle_difference(player.rotation.y, want)), 0.0, 2.0, "he faces what the scene had him face")
	var at := player.rotation.y
	for i in 30:
		await frames(1)
	assert_near(rad_to_deg(angle_difference(player.rotation.y, at)), 0.0, 0.5, "and keeps it with the stick at rest")


func test_the_camera_returns_to_the_live_gameplay_pose_with_no_jump() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	var head := StoryStage.screen_of(parts, player.head_point())
	var worst := 0.0
	var n := 0
	while _finished.is_empty() and n < 100:
		await frames(1)
		n += 1
		var now := StoryStage.screen_of(parts, player.head_point())
		worst = maxf(worst, now.distance_to(head))
		head = now
	assert_true(worst <= 12.0, "over the glide his head moves at most 12 px a frame, not %.1f" % worst)
	assert_eq(_finished, [0.0], "the weight is exactly 0 at the end")
	await frames(60)
	var home := StoryStage.screen_of(parts, player.head_point())
	assert_true(home.distance_to(head) <= 1.0, "and the picture is the game camera's for where he stands (%s, then %s)" % [head, home])


func test_no_frame_covers_more_than_the_bars() -> void:
	for kind: SceneShots.Kind in [SceneShots.Kind.CUTSCENE, SceneShots.Kind.MINI]:
		var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
		await frames(3)
		var scene := _fixture()
		scene.kind = kind
		scene.letterbox = kind == SceneShots.Kind.CUTSCENE
		var director := _start(parts, scene)
		assert_true(director != null)
		if director == null:
			return
		var overlay := _overlay_of(parts)
		var worst := 0.0
		var bars := 0
		var wrong_hud := 0
		_finished = []
		var n := 0
		while _finished.is_empty() and n < 500:
			var running := director.phase == Director.Phase.LEAD_IN or director.phase == Director.Phase.PLAY
			if running != parts.hud.suppressed:
				wrong_hud += 1
			worst = maxf(worst, overlay.covered_fraction())
			bars = maxi(bars, overlay.bar_height())
			await frames(1)
			n += 1
		assert_true(worst <= 0.245, "%s: the bars alone cover %.3f of the picture" % [kind, worst])
		assert_eq(bars, 44 if kind == SceneShots.Kind.CUTSCENE else 0, "%s: the bars at full" % kind)
		assert_eq(wrong_hud, 0, "%s: the Hud is hidden exactly while the scene runs" % kind)
		parts.stage.free()
		await frames(1)


func test_the_sticks_do_not_turn_with_the_glide() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var player: Actor = parts.player
	var director := _start(parts, _ending_at_yaw(90.0))
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	assert_true(absf(parts.rig.cine.yaw_deg - 90.0) < 1.0, "the last shot is at yaw 90 (%s)" % parts.rig.cine.yaw_deg)
	_key(KEY_W)
	var turned := 0
	var n := 0
	while is_instance_valid(director) and director.phase == Director.Phase.LEAD_OUT and n < 80:
		if parts.rig.yaw() != 0.0:
			turned += 1
		await frames(1)
		n += 1
		if n == 10:
			var heading := Vector2(player.velocity.x, player.velocity.z).normalized()
			assert_true(heading.angle_to(Vector2(0, -1)) < deg_to_rad(3.0), "up on the stick is north while the picture is still turned: %s" % heading)
	_key(KEY_W, false)
	assert_eq(turned, 0, "rig.yaw() is 0 on every frame of the glide")
	assert_eq(parts.brain.view_yaw, 0.0)


func test_the_world_holds_and_resumes() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var other := StoryStage.knuckle(parts.region, Vector3(-8, 0, -8), 0.0, "Other")
	await frames(10)
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var at := other.global_position
	var pose := StoryStage.pose_of(other.rig)
	var moved := 0.0
	var turned := 0.0
	var ticks := other.buffer_frame
	while director.phase != Director.Phase.LEAD_OUT:
		await frames(1)
		moved = maxf(moved, other.global_position.distance_to(at))
		turned = maxf(turned, StoryStage.angle_between(pose, StoryStage.pose_of(other.rig)))
	assert_eq(moved, 0.0, "the foe does not move during the scene")
	assert_true(turned < 0.5, "or animate (%.3f degrees)" % turned)
	assert_true(other.buffer_frame - ticks <= 1, "his clock stood still (%d)" % (other.buffer_frame - ticks))
	assert_eq(other.frozen, 0, "he is let go at the hand-back")
	var before := other.buffer_frame
	await frames(1)
	assert_eq(other.buffer_frame - before, 1, "and acts on the first frame after it")


func test_the_three_kinds_differ_only_as_specified() -> void:
	var counts := {}
	for kind: SceneShots.Kind in [SceneShots.Kind.CUTSCENE, SceneShots.Kind.MINI]:
		var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
		await frames(3)
		var scene := _fixture()
		scene.kind = kind
		scene.letterbox = kind == SceneShots.Kind.CUTSCENE
		# a MINI of 300 frames in all: 30 in, 240 of shots (the last held longer), 30 out, ending on a shot at the game's yaw
		scene.shots.remove_at(3)
		scene.shots[2].length = 90
		var director := _start(parts, scene)
		assert_true(director != null, "%s: taken (%s)" % [kind, Director.last_refusal])
		if director == null:
			return
		var overlay := _overlay_of(parts)
		var states := {}
		var bars := 0
		var frames_played := 0
		_finished = []
		while _finished.is_empty() and frames_played < 500:
			if director.phase == Director.Phase.LEAD_IN or director.phase == Director.Phase.PLAY:
				states[Game.state] = true
			bars = maxi(bars, overlay.bar_height())
			await frames(1)
			frames_played += 1
		counts[kind] = frames_played
		assert_eq(states.keys(), [Game.State.CUTSCENE], "%s: the game is in CUTSCENE while the scene runs" % kind)
		assert_eq(bars, 44 if kind == SceneShots.Kind.CUTSCENE else 0, "%s: bars of 44 px, or none" % kind)
		assert_eq(Game.state, Game.State.PLAY, "%s: and both end in PLAY" % kind)
		parts.stage.free()
		await frames(1)
	assert_true(counts[SceneShots.Kind.MINI] >= 300 and counts[SceneShots.Kind.MINI] <= 302,
			"a MINI of 300 frames takes %d physics frames, 5.0 s" % counts[SceneShots.Kind.MINI])
	assert_eq(counts[SceneShots.Kind.CUTSCENE], counts[SceneShots.Kind.MINI], "and a CUTSCENE of the same shots takes as long")


func test_the_bars_slide_out_over_the_whole_glide_home() -> void:
	# The timeline's own slide-out takes its last 30 frames, and the fixture's glide home (its last shot is turned) is 60: the bars
	# must not be gone while the camera still turns.
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var scene := _fixture()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.letterbox = true
	var director := _start(parts, scene)
	assert_true(director != null)
	if director == null:
		return
	var overlay := _overlay_of(parts)
	await _until_hand_back(director)
	assert_eq(overlay.bar_height(), 44, "the bars are all the way in as control comes back")
	var worst := 0.0
	var n := 0
	while _finished.is_empty() and is_instance_valid(overlay) and n < 100:
		worst = maxf(worst, absf(float(overlay.bar_height()) - 44.0 * parts.rig.cine_weight))
		await frames(1)
		n += 1
	assert_true(worst <= 2.0, "the bars go out in step with the camera's glide (off by %.1f px at most)" % worst)
