extends TestCase
## CineCamera and the timeline it is animated by, with a small stand-in for the Director (which is Task 3's): it takes the
## `_cue` calls, shows the lines in the overlay and ramps the rig's weight in and out the way the Director will. What is
## checked is the part this task owns: the camera follows the animated shot and progress, the bars and box follow the
## timeline, a paused tree stops and resumes all of it from the same frame, and a scene cut short gives everything back.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const PLACES := {
	&"abarax": Vector3(0, 0, 5), &"knuckle": Vector3(1.2, 0, 2.4), &"foe_stop": Vector3(1.2, 0, 2.4),
	&"foe_in": Vector3(2.2, 0, 2.6),
}


# What the Director does with the timeline's calls and the weight, as far as this task can see it.
class Cues extends Node:
	var clock := 0
	var scene: SceneShots
	var rig: CameraRig
	var overlay: CineOverlay
	var log: Array = []  # [clock, kind, frame]

	func _init() -> void:
		name = "Director"
		process_physics_priority = -10

	func _physics_process(_delta: float) -> void:
		clock += 1
		var total := scene.total_frames()
		var weight := clampf(float(clock) / scene.lead_in, 0.0, 1.0)
		if clock >= total - scene.lead_out:
			weight = clampf(float(total - clock) / scene.lead_out, 0.0, 1.0)
		rig.cine_weight = weight

	func _cue(kind: StringName, payload: Dictionary) -> void:
		log.append([clock, kind, payload.frame])
		if kind == &"line":
			var speaker := Registry.fetch(&"speakers", payload.speaker) as Speaker
			overlay.show_line(speaker, payload.text, payload.expr, payload.hold)
		elif kind == &"sound":
			Sfx.play(payload.id)


# Records what is on screen after every frame of the scene, by the scene's clock.
class Recorder extends Node:
	var cues: Cues
	var camera: CineCamera
	var rig: CameraRig
	var overlay: CineOverlay
	var states := {}  # clock -> state
	var pause_at := -1
	var frozen := false

	func _init() -> void:
		process_physics_priority = 100

	func _physics_process(_delta: float) -> void:
		var pose := rig.cine
		states[cues.clock] = [
			camera.shot, snappedf(camera.progress, 1e-6), rig.cine_weight, overlay.visible_text(), overlay.bar_height(),
			[pose.aim, pose.yaw_deg, pose.pitch_deg, pose.zoom, pose.focus] if pose != null else null,
		]
		if cues.clock == pause_at and not frozen:
			frozen = true
			get_tree().paused = true


var stage: PixelStage
var rig: CameraRig
var overlay: CineOverlay
var hud: Hud


func after_each() -> void:
	get_tree().paused = false


func _world() -> Callable:
	return func(name: StringName) -> Variant: return PLACES.get(name, null)


# The portrait cards in the stage that are not on their way out (the overlay shows one while a line is up; a card taken away
# is hidden at once and freed at the frame's end).
func _cards() -> Array[Node]:
	var found: Array[Node] = []
	for card in stage.find_children("*", "PortraitCard", true, false):
		if not card.is_queued_for_deletion():
			found.append(card)
	return found


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


# A stage with a rig, an overlay and a Hud, and a scene on it: returns the pieces.
func _play(scene: SceneShots, pause_at := -1) -> Dictionary:
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	var target := Node3D.new()
	stage.world.add_child(target)
	target.position = Vector3(0, 0, 5)
	rig = CameraRig.new()
	rig.target = target
	rig.stage = stage
	stage.world.add_child(rig)
	target.reset_physics_interpolation()
	rig.snap_now()
	hud = Hud.new()
	stage.hud.add_child(hud)
	hud.suppressed = true
	overlay = CineOverlay.new()
	stage.hud.add_child(overlay)
	var player := TimelineBuilder.player_for(scene)
	var root := player.get_parent()
	var camera := root.get_node("CineCamera") as CineCamera
	camera.scene = scene
	camera.world = _world()
	camera.rig = rig
	camera.overlay = overlay
	camera.hud = hud
	var cues := Cues.new()
	cues.scene = scene
	cues.rig = rig
	cues.overlay = overlay
	root.add_child(cues)
	var recorder := Recorder.new()
	recorder.cues = cues
	recorder.camera = camera
	recorder.rig = rig
	recorder.overlay = overlay
	recorder.pause_at = pause_at
	root.add_child(recorder)
	track(root)
	player.play(TimelineBuilder.animation_of(player))
	return {"root": root, "player": player, "camera": camera, "cues": cues, "recorder": recorder}


func _letterboxed() -> SceneShots:
	var scene := _fixture()
	scene.kind = SceneShots.Kind.CUTSCENE
	scene.letterbox = true
	scene.lead_in = 45
	return scene


func test_the_camera_hands_the_rig_the_pose_the_animated_shot_solves_to() -> void:
	var scene := _fixture()
	var stage_parts := _play(scene)
	var camera: CineCamera = stage_parts.camera
	stage_parts.player.stop()
	stage_parts.cues.process_mode = Node.PROCESS_MODE_DISABLED
	camera.shot = 1
	camera.progress = 0.5
	camera.letterbox = 0.5
	await frames(2)
	assert_true(rig.cine != null, "the rig has a cine pose")
	assert_near(rig.cine.zoom, 2.5, 1e-6, "the dolly of shot 2 half way: zoom 2 to 3")
	assert_vec_near(rig.cine.aim, PLACES[&"knuckle"] + Vector3.UP, 1e-5, "the knuckle, a metre up")
	assert_eq(rig.cine_weight, 0.0, "it never sets the weight: the Director does")
	assert_near(overlay.letterbox, 0.5, 1e-6, "the bars follow the track")
	camera.shot = 99
	await frames(2)
	assert_near(rig.cine.zoom, 2.0, 1e-6, "a shot past the end is held at the last (over the shoulder: zoom 2)")


func test_a_blend_in_glides_from_the_pose_the_last_shot_ended_on() -> void:
	var scene := _fixture()
	scene.shots[1].blend_in = 20
	var parts := _play(scene)
	var camera: CineCamera = parts.camera
	parts.player.stop()
	camera.shot = 0
	camera.progress = 1.0
	await frames(2)
	var before := rig.cine.zoom
	var first_aim := rig.cine.aim
	camera.shot = 1
	camera.progress = 0.0
	var zooms: Array[float] = []
	for i in 24:
		await frames(1)
		zooms.append(rig.cine.zoom)
	assert_near(zooms[0], before, 1e-6, "the first frame of the shot is where the last one ended")
	for i in range(1, 20):
		assert_true(zooms[i] >= zooms[i - 1] - 1e-9, "never backwards at frame %d" % i)
	assert_true(zooms[10] > before + 0.1 and zooms[10] < 2.0, "partway at frame 10: %s" % zooms[10])
	assert_near(zooms[20], 2.0, 1e-6, "the shot's own pose after 20 frames")
	assert_near(zooms[23], 2.0, 1e-6)
	# With no blend_in the next shot is a cut.
	camera.shot = 2
	camera.progress = 0.0
	await frames(2)
	assert_near(rig.cine.zoom, 3.0, 1e-6, "shot 3 is a close-up at once")
	assert_true(first_aim != Vector3.ZERO)


func test_a_handheld_shot_lifts_the_trauma_and_leaves_a_harder_one_alone() -> void:
	var scene := _fixture()
	scene.shots[0].move = Shot.CamMove.HANDHELD
	scene.shots[0].shake = 0.4
	scene.shots[0].aim_to = &""
	var parts := _play(scene)
	parts.player.stop()
	parts.camera.shot = 0
	await frames(2)
	assert_true(rig.trauma >= 0.4 - 0.05, "the shake is held at 0.4 (the rig loses 0.04 a frame between two lifts): %s" % rig.trauma)
	rig.trauma = 0.9
	await frames(1)
	assert_true(rig.trauma > 0.8, "a blow's harder trauma is not pulled down: %s" % rig.trauma)
	parts.camera.shot = 1
	rig.trauma = 0.0
	await frames(2)
	assert_true(rig.trauma < 0.01, "a steady shot lifts nothing")


func test_the_timeline_drives_the_camera_the_bars_and_the_lines() -> void:
	var scene := _letterboxed()
	var parts := _play(scene)
	var recorder: Recorder = parts.recorder
	var cues: Cues = parts.cues
	var total := scene.total_frames()
	await frames(total + 4)
	assert_true(recorder.states.has(60) and recorder.states.has(total - 2), "recorded")
	var at_60: Array = recorder.states[60]
	assert_eq(at_60[0], 0, "shot 1 at frame 15 of it")
	assert_eq(at_60[4], 44, "the bars are all the way in once the slide is over")
	assert_true(absi(recorder.states[10][4] - roundi(10.0 / 30.0 * 44.0)) <= 3, "and part way in on the way: %d" % recorder.states[10][4])
	var shots_seen := {}
	for clock in recorder.states:
		shots_seen[recorder.states[clock][0]] = true
	assert_eq(shots_seen.keys().size(), 4, "all four shots were shown")
	# A line is up while it is on and typed as it goes.
	var typed := ""
	for clock in recorder.states:
		if recorder.states[clock][3] != "":
			typed = recorder.states[clock][3]
	assert_true(typed.begins_with("Fixture line"), "a line was shown: '%s'" % typed)
	var kinds := {}
	for entry in cues.log:
		kinds[entry[1]] = kinds.get(entry[1], 0) + 1
	assert_eq(kinds, {&"beat": 5, &"sound": 1, &"line": 2, &"music": 1, &"end": 1}, "every call, once")
	assert_eq(recorder.states[total + 3][4], 0, "the bars have gone when the timeline is over")
	assert_eq(rig.cine_weight, 0.0, "and the Director's weight is back at 0")


func test_a_scene_paused_for_200_frames_is_the_same_as_one_never_paused() -> void:
	var scene := _letterboxed()
	var total := scene.total_frames()
	var control := _play(scene)
	await frames(total + 6)
	var wanted: Dictionary = control.recorder.states.duplicate(true)
	var wanted_log: Array = control.cues.log.duplicate(true)
	control.root.queue_free()
	await frames(2)
	for pause_at in [7, 40, 100, 185, 250, 300, 318]:
		var parts := _play(_letterboxed(), pause_at)
		var cues: Cues = parts.cues
		var recorder: Recorder = parts.recorder
		var guard := 0
		while cues.clock < pause_at and guard < 400:
			await frames(1)
			guard += 1
		assert_true(get_tree().paused, "paused at %d" % pause_at)
		var held: Array = recorder.states[pause_at]
		var plays_before: int = Engine.get_physics_frames()
		await frames(200)
		assert_eq(cues.clock, pause_at, "the clock stood still for 200 frames")
		assert_eq(recorder.states[pause_at], held, "and so did the picture")
		assert_eq(Sfx.last_played().filter(func(id: StringName) -> bool: return id != &"voice_blip").size(), 0, "no sound started while paused")
		assert_true(Engine.get_physics_frames() - plays_before >= 200)
		get_tree().paused = false
		await frames(total + 6 - pause_at)
		assert_eq(recorder.states.size(), wanted.size(), "as many frames at pause %d" % pause_at)
		for clock in wanted:
			if recorder.states.get(clock) != wanted[clock]:
				fail("pause at %d: scene frame %d differs: %s against %s" % [pause_at, clock, recorder.states.get(clock), wanted[clock]])
				break
		assert_eq(cues.log, wanted_log, "every call made once, on the same frame, at pause %d" % pause_at)
		parts.root.queue_free()
		await frames(2)


func test_a_scene_cut_short_gives_everything_back_at_three_instants() -> void:
	for instant in [20, 205, 330]:
		var scene := _letterboxed()
		var parts := _play(scene)
		var cues: Cues = parts.cues
		var guard := 0
		while cues.clock < instant and guard < 400:
			await frames(1)
			guard += 1
		assert_true(rig.cine_weight > 0.0 and hud.suppressed, "mid-scene at %d" % instant)
		if instant == 205:
			assert_true(overlay.showing(), "a line is showing")
			assert_eq(_cards().size(), 1, "and its portrait card is up")
		if instant == 20:
			assert_true(overlay.bar_height() > 0, "the bars are sliding in")
		parts.root.queue_free()
		await frames(1)
		assert_eq(rig.cine_weight, 0.0, "the weight is 0 the next frame (%d)" % instant)
		assert_true(rig.cine == null, "the rig has no pose of the scene's")
		assert_false(hud.suppressed, "the Hud draws again")
		assert_eq(overlay.letterbox, 0.0, "the bars are out")
		assert_eq(overlay.bar_height(), 0)
		assert_false(overlay.showing(), "the box is closed")
		assert_eq(_cards().size(), 0, "and the portrait card is gone with it (%d)" % instant)
		await frames(3)
		assert_eq(rig.cine_weight, 0.0, "and it stays so")
		assert_near(rig.camera.size, CameraRig.ORTHO_SIZE, 1e-6, "the game camera's own size")
		stage.queue_free()
		await frames(1)
	# A scene stopped without freeing the node does the same by release().
	var scene := _letterboxed()
	var parts := _play(scene)
	await frames(100)
	parts.camera.release()
	assert_eq(rig.cine_weight, 0.0)
	assert_false(hud.suppressed)
	assert_eq(overlay.bar_height(), 0)
	assert_eq(_cards().size(), 0, "release() gives the portrait card back too")
	parts.camera.release()
	assert_false(hud.suppressed, "twice is harmless")
