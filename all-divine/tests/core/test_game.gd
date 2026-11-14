extends TestCase

# An autoload is not a constant expression, so the enum is taken from its script.
const S := preload("res://core/game.gd").State

# The allowed moves, as written in the spec: [from, to].
func _allowed() -> Array:
	return [
		[S.BOOT, S.TITLE], [S.BOOT, S.PLAY], [S.TITLE, S.PLAY],
		[S.PLAY, S.PAUSE], [S.PAUSE, S.PLAY],
		[S.PLAY, S.MENU], [S.MENU, S.PLAY],
		[S.PLAY, S.CUTSCENE], [S.CUTSCENE, S.PLAY],
		[S.CUTSCENE, S.PAUSE], [S.PAUSE, S.CUTSCENE],
		[S.PAUSE, S.TITLE], [S.MENU, S.TITLE],
	]

func before_each() -> void:
	Game.reset()

func after_each() -> void:
	Game.reset()

func test_boot_to_play_emits_and_changes() -> void:
	var seen := []
	var on_change := func(a, b): seen.append([a, b])
	Game.state_changed.connect(on_change)
	assert_true(Game.change(S.PLAY))
	Game.state_changed.disconnect(on_change)
	assert_eq(seen, [[S.BOOT, S.PLAY]])
	assert_eq(Game.state, S.PLAY)

func test_disallowed_change_is_refused() -> void:
	assert_false(quietly(func(): return Game.change(S.CUTSCENE)))
	assert_eq(Game.state, S.BOOT)

func test_every_move_is_allowed_or_refused_as_specified() -> void:
	var allowed := _allowed()
	for from in S.values():
		for to in S.values():
			Game.reset()
			Game.state = from
			var seen := []
			var on_change := func(a, b): seen.append([a, b])
			Game.state_changed.connect(on_change)
			var ok: bool = quietly(func(): return Game.change(to))
			Game.state_changed.disconnect(on_change)
			var label := "%s -> %s" % [S.find_key(from), S.find_key(to)]
			assert_eq(ok, allowed.has([from, to]), label)
			if ok:
				assert_eq(Game.state, to, label)
				assert_eq(seen, [[from, to]], label)
			else:
				assert_eq(Game.state, from, label)
				assert_eq(seen, [], label + " must not emit")

func test_pause_pauses_tree_and_play_resumes() -> void:
	Game.change(S.PLAY)
	assert_false(get_tree().paused)
	Game.change(S.PAUSE)
	assert_true(get_tree().paused)
	Game.change(S.PLAY)
	assert_false(get_tree().paused)

func test_leaving_pause_for_the_title_also_resumes() -> void:
	Game.change(S.PLAY)
	Game.change(S.PAUSE)
	assert_true(Game.change(S.TITLE))
	assert_false(get_tree().paused)

func test_other_states_do_not_pause_the_tree() -> void:
	Game.change(S.PLAY)
	Game.change(S.MENU)
	assert_false(get_tree().paused)
	Game.change(S.PLAY)
	Game.change(S.CUTSCENE)
	assert_false(get_tree().paused)

func test_reset_returns_to_boot_and_unpauses() -> void:
	Game.change(S.PLAY)
	Game.change(S.PAUSE)
	Game.reset()
	assert_eq(Game.state, S.BOOT)
	assert_false(get_tree().paused)

func test_play_frames_count_only_while_playing() -> void:
	Game.change(S.PLAY)
	var start: int = Game.play_frames
	await frames(5)
	assert_eq(Game.play_frames - start, 5, "five physics frames, five play frames")
	Game.change(S.PAUSE)
	var paused_at: int = Game.play_frames
	await frames(30)
	assert_eq(Game.play_frames, paused_at, "a pause stops the count")
	Game.change(S.PLAY)
	await frames(4)
	assert_eq(Game.play_frames - paused_at, 4, "and it carries on from where it stopped")

func test_reset_zeroes_play_frames() -> void:
	Game.change(S.PLAY)
	await frames(3)
	assert_true(Game.play_frames > 0, "some frames counted")
	Game.reset()
	assert_eq(Game.play_frames, 0)


func test_a_cutscene_can_be_paused_and_the_pause_gives_it_back() -> void:
	Game.change(S.PLAY)
	Game.change(S.CUTSCENE)
	assert_true(Game.change(S.PAUSE), "a cutscene can be paused")
	assert_true(get_tree().paused)
	var seen := []
	var on_change := func(a, b): seen.append([a, b])
	Game.state_changed.connect(on_change)
	assert_true(Game.change(S.PLAY), "the menu's Resume asks for PLAY")
	Game.state_changed.disconnect(on_change)
	assert_eq(Game.state, S.CUTSCENE, "and the pause gives back what it paused: the cutscene")
	assert_eq(seen, [[S.PAUSE, S.CUTSCENE]], "said as the move it was")
	assert_false(get_tree().paused)
	Game.change(S.PLAY)
	Game.change(S.PAUSE)
	Game.change(S.PLAY)
	assert_eq(Game.state, S.PLAY, "a pause from the fight gives back the fight")


func test_play_frames_stand_still_in_a_cutscene() -> void:
	Game.change(S.PLAY)
	await frames(3)
	Game.change(S.CUTSCENE)
	var at: int = Game.play_frames
	await frames(30)
	assert_eq(Game.play_frames, at, "a scene is not fight time: the HUD's blink and bars, the refusal gate, stand where they were")
	Game.change(S.PLAY)
	await frames(4)
	assert_eq(Game.play_frames - at, 4, "and go on from there when the fight is back")


func test_a_cutscene_that_ends_while_paused_is_not_given_back_by_the_pause() -> void:
	Game.change(S.PLAY)
	Game.change(S.CUTSCENE)
	Game.end_cutscene()
	assert_eq(Game.state, S.PLAY, "ending a cutscene that is the state plays")
	Game.change(S.CUTSCENE)
	Game.change(S.PAUSE)
	Game.end_cutscene()
	assert_eq(Game.state, S.PAUSE, "paused, the game stays paused")
	Game.change(S.PLAY)
	assert_eq(Game.state, S.PLAY, "and Resume plays: the cutscene is over")
	Game.end_cutscene()
	assert_eq(Game.state, S.PLAY, "ending one that is not on changes nothing")
