extends TestCase
## A scene is not fight time (fix round 1, item 4): every clock the fight keeps either stands still across a scene or is put back,
## so that the fight is handed back as it was left. The audit of the clocks (what each does in a scene) is in the task report; the
## ones that were wrong are tested here by playing the fixture scene over them: the dodge chain (and every clock on the actor's
## buffer_frame: the sway and parry windows, the counter window), the afterimages, and the controls list's timer. The bars and the
## Hud's own play-frame clocks are in test_director_handback.

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"


func before_each() -> void:
	RenderingServer.render_loop_enabled = false  # these tests look at no picture: a render run need not draw their frames (it is most of the time)
	Game.reset()
	Game.change(Game.State.PLAY)
	StoryLog.forget_all()
	Director.reset_spawn_counts()
	Melee.slow(0, 1.0)


func after_each() -> void:
	RenderingServer.render_loop_enabled = true
	Melee.slow(0, 1.0)
	Game.reset()


func _fixture() -> SceneShots:
	return (load(FIXTURE) as SceneShots).duplicate_deep()


func _start(parts: Dictionary) -> Director:
	var director := Director.new()
	if not director.begin(_fixture(), parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return null
	return director


func _until_hand_back(director: Director, limit := 500) -> void:
	var n := 0
	while is_instance_valid(director) and director.phase != Director.Phase.LEAD_OUT and n < limit:
		await frames(1)
		n += 1


func test_a_chain_ten_frames_from_lapsing_is_ten_frames_from_lapsing_after_a_scene() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var player: Actor = parts.player
	await frames(3)
	for i in 4:
		player.chain.link(false, player.buffer_frame - 80)  # four links, the latest 80 of the 90 frames ago
	assert_eq(player.chain.count, 4)
	assert_eq(player.chain.tempo(), DodgeChain.Tempo.QUICK, "Quick tempo")
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	assert_eq(player.chain.count, 4, "the chain is as it was at the hand-back, not lapsed by the scene")
	assert_eq(player.chain.tempo(), DodgeChain.Tempo.QUICK, "and in the same tempo")
	await frames(6)
	assert_eq(player.chain.count, 4, "it still has its few frames")
	await frames(10)
	assert_eq(player.chain.count, 0, "and then it lapses, ten frames after the hand-back and not before")


func test_the_actors_acting_clock_stands_still_through_a_scene() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var player: Actor = parts.player
	await frames(3)
	var before := player.buffer_frame
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	var foe: Actor = director.cast[&"knuckle"]
	var foe_before := foe.buffer_frame
	await _until_hand_back(director)
	assert_true(player.buffer_frame - before <= 2, "his clock (the sway, parry and counter windows, the chain) did not run in the scene: %d frames" % (player.buffer_frame - before))
	assert_true(foe.buffer_frame - foe_before <= 2, "nor the Knuckle's: %d frames" % (foe.buffer_frame - foe_before))


func test_a_ghost_of_a_dodge_fades_out_at_the_start_of_a_scene_and_does_not_hang_through_it() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var player: Actor = parts.player
	await frames(3)
	var ghost := Afterimage.spawn(player.rig, Color(1, 1, 1, 0.5), 12, {}, player)
	await frames(3)
	assert_true(is_instance_valid(ghost) and ghost.left > 0, "the ghost is alive before the scene")
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await frames(20)
	assert_false(is_instance_valid(ghost) and not ghost.is_queued_for_deletion(), "20 frames into the scene it is gone (a scene's frames age it, as the wall's: it does not hang in the shots)")


func test_the_controls_lists_timer_does_not_run_in_a_scene() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	var hud: Hud = parts.hud
	await frames(3)
	hud.advance(0.5)
	var left: float = hud._hint_left
	var director := _start(parts)
	assert_true(director != null)
	if director == null:
		return
	await _until_hand_back(director)
	assert_true(left - hud._hint_left < 0.1, "the list's seconds were not spent in the scene (%.2f s of them)" % (left - hud._hint_left))
