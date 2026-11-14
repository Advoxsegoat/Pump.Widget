extends TestCase
## The HUD goes and comes with the bars, not in one frame (fix round 1, item 6): its opacity follows the bars over the same frames,
## in and out; gone by the time the bars are in (30 frames, before the first line), whole again at the end of the glide home; a
## pause holds it; a skip or an abort never makes it jump. Hud.suppressed keeps its meaning (the scene holds the HUD, first frame to
## hand-back).

const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const BAR := 44.0


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


func _scene(kind := SceneShots.Kind.MINI) -> SceneShots:
	var scene := (load(FIXTURE) as SceneShots).duplicate_deep()
	scene.kind = kind
	scene.letterbox = kind == SceneShots.Kind.CUTSCENE
	return scene


func _start(parts: Dictionary, scene: SceneShots) -> Director:
	var director := Director.new()
	if not director.begin(scene, parts.region, parts.rig, parts.hud, parts.stage):
		director.free()
		return null
	return director


func _overlay(parts: Dictionary) -> CineOverlay:
	for child in parts.stage.hud.get_children():
		if child is CineOverlay:
			return child
	return null


# The HUD's opacity on each frame from the scene's first (frame 0 is the call's own) to the end of the glide home, with the phase.
func _alphas(parts: Dictionary, director: Director, limit := 500) -> Array:
	var rows := [{alpha = parts.hud.shown_alpha(), phase = director.phase, held = parts.hud.suppressed}]
	var n := 0
	while is_instance_valid(director) and director.phase != Director.Phase.DONE and n < limit:
		await frames(1)
		n += 1
		if is_instance_valid(director) and director.phase != Director.Phase.DONE:
			rows.append({alpha = parts.hud.shown_alpha(), phase = director.phase, held = parts.hud.suppressed})
	return rows


func test_the_hud_goes_over_the_bars_frames_and_comes_back_over_the_glide() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	assert_eq(parts.hud.shown_alpha(), 1.0, "whole before the scene")
	var director := _start(parts, _scene())
	assert_true(director != null)
	if director == null:
		return
	var rows := await _alphas(parts, director)
	assert_eq(rows[0].alpha, 1.0, "the scene's first frame is the game's picture, HUD and all")
	var gone := -1
	for i in rows.size():
		if rows[i].alpha <= 0.0:
			gone = i
			break
	assert_true(gone >= 28 and gone <= 32, "it is gone as the bars would be in, about frame 30, not %d" % gone)
	for i in range(1, gone + 1):
		assert_true(rows[i].alpha <= rows[i - 1].alpha and rows[i - 1].alpha - rows[i].alpha <= 0.05, "frame %d: it fades out steadily (%.3f then %.3f)" % [i, rows[i - 1].alpha, rows[i].alpha])
	var back := -1
	for i in rows.size():
		if rows[i].phase == Director.Phase.LEAD_OUT:
			back = i
			break
	assert_true(back > gone, "the hand-back is later")
	for i in range(gone, back):
		assert_eq(rows[i].alpha, 0.0, "frame %d: nothing of it shows through the shots" % i)
		assert_true(rows[i].held, "frame %d: the scene holds the Hud" % i)
	assert_false(rows[back].held, "from the hand-back the Hud is no longer held (suppressed keeps its meaning)")
	for i in range(back + 1, rows.size()):
		assert_true(rows[i].alpha >= rows[i - 1].alpha and rows[i].alpha - rows[i - 1].alpha <= 0.05, "frame %d: it comes back steadily over the glide (%.3f then %.3f)" % [i, rows[i - 1].alpha, rows[i].alpha])
	assert_true(rows[rows.size() - 1].alpha >= 0.95, "and is nearly whole on the glide's last frame (%.2f)" % rows[rows.size() - 1].alpha)
	await frames(2)
	assert_eq(parts.hud.shown_alpha(), 1.0, "whole when it is over")
	assert_eq(parts.hud.scene_fade, -1.0, "and no scene is fading it")


func test_with_bars_the_hud_is_as_opaque_as_the_bars_are_clear() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var director := _start(parts, _scene(SceneShots.Kind.CUTSCENE))
	assert_true(director != null)
	if director == null:
		return
	var overlay := _overlay(parts)
	var worst := 0.0
	var n := 0
	while is_instance_valid(director) and director.phase != Director.Phase.DONE and n < 500 and is_instance_valid(overlay):
		if not overlay.is_queued_for_deletion():
			worst = maxf(worst, absf(parts.hud.shown_alpha() - (1.0 - float(overlay.bar_height()) / BAR)))
		await frames(1)
		n += 1
	assert_true(worst <= 0.03, "the HUD's opacity follows the bars within a pixel of them: %.3f" % worst)


func test_a_pause_holds_it() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var director := _start(parts, _scene())
	assert_true(director != null)
	if director == null:
		return
	while director.frame < 15:
		await frames(1)
	var held: float = parts.hud.shown_alpha()
	assert_true(held > 0.0 and held < 1.0, "half gone at frame 15 (%.2f)" % held)
	Game.change(Game.State.PAUSE)
	await frames(20)
	assert_eq(parts.hud.shown_alpha(), held, "paused, it holds")
	Game.change(Game.State.PLAY)
	await frames(3)
	assert_true(parts.hud.shown_alpha() < held, "and goes on from there")


func test_a_skip_in_the_middle_of_the_fade_never_makes_it_jump() -> void:
	StoryLog.mark_seen(&"fixture_yard_entrance")
	for at in [6, 14, 29, 100]:
		var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
		await frames(3)
		var director := _start(parts, _scene())
		assert_true(director != null)
		if director == null:
			return
		while director.frame < at:
			await frames(1)
		var before: float = parts.hud.shown_alpha()
		assert_true(director.skip(), "skipped at %d" % at)
		var last := before
		var worst := 0.0
		var n := 0
		while is_instance_valid(director) and director.phase != Director.Phase.DONE and n < 100:
			await frames(1)
			n += 1
			var now: float = parts.hud.shown_alpha()
			worst = maxf(worst, absf(now - last))
			last = now
		assert_true(worst <= 0.06, "skipped at %d: the HUD moves at most 6%% a frame (%.3f)" % [at, worst])
		assert_true(last >= 0.95, "skipped at %d: and is back" % at)
		parts.stage.free()
		await frames(1)


func test_an_abort_gives_the_hud_back_whole() -> void:
	var parts := StoryStage.make(self, Vector3(3, 0, 4), deg_to_rad(200.0))
	await frames(3)
	var director := _start(parts, _scene())
	assert_true(director != null)
	if director == null:
		return
	while director.frame < 15:
		await frames(1)
	director.abort()
	assert_eq(parts.hud.shown_alpha(), 1.0, "whole")
	assert_false(parts.hud.suppressed)
	assert_eq(parts.hud.scene_fade, -1.0)
	assert_eq(parts.hud.self_modulate.a, 1.0, "and drawn whole")
