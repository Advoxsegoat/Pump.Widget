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
