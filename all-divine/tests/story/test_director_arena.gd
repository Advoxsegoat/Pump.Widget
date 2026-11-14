extends TestCase
## The arena does nothing during a scene (fix round 1, item 5): its timers count frames of play (Game.play_frames), so the next wave
## comes three seconds of PLAY after the last foe fell, and the reset after the player's death three seconds of play after it, never
## in the middle of a shot; and the arena's debug keys (F6 to F9) do nothing in a scene, as in the pause. Through the real Main.

const MAIN := "res://main/main.tscn"


func before_each() -> void:
	Game.reset()
	Arena.reset_spawn_counts()
	Director.reset_spawn_counts()
	StoryLog.forget_all()
	Melee.slow(0, 1.0)


func after_each() -> void:
	Melee.slow(0, 1.0)
	Game.reset()


func _main() -> Main:
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(2)
	return main


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _foes(arena: Arena) -> int:
	return arena.enemies().filter(func(a: Actor) -> bool: return is_instance_valid(a) and not a.dead).size()


func test_the_next_wave_comes_three_seconds_of_play_after_the_last_foe_not_in_a_shot() -> void:
	var main := await _main()
	var arena := main.arena()
	var log := []
	arena.wave_started.connect(func(i: int) -> void: log.append({wave = i, state = Game.state, play = Game.play_frames}))
	for foe in arena.enemies():
		foe.set_brain(Brain.new())
	var director := Director.play(&"fixture_yard_entrance", main)
	assert_true(director != null, "the scene plays: %s" % Director.last_refusal)
	if director == null:
		return
	# the last foe falls a second into the scene's lead... one second (60 frames) before the scene starts is the case the review
	# named; here the scene starts at once and the foe falls 60 frames into it: either way the wave clock must not run in the shots.
	while director.frame < 60:
		await frames(1)
	var cleared_at := Game.play_frames
	for foe in arena.enemies():
		foe.die()
	assert_true(arena.wave_is_cleared(), "the wave is cleared")
	var guard := 0
	while director.phase != Director.Phase.LEAD_OUT and guard < 600:
		await frames(1)
		guard += 1
	assert_true(log.is_empty(), "no wave came during the scene (%s)" % [log])
	var played_before := Game.play_frames - cleared_at
	assert_true(played_before <= 1, "and no frame of play passed in it but the hand-back's own (%d)" % played_before)
	guard = 0
	while log.is_empty() and guard < 400:
		await frames(1)
		guard += 1
	assert_false(log.is_empty(), "the next wave comes after the scene")
	if log.is_empty():
		return
	assert_eq(log[0].state, Game.State.PLAY, "in play")
	var waited: int = log[0].play - cleared_at
	assert_true(waited >= 178 and waited <= 182, "three seconds of PLAY after the last foe fell (%d frames)" % waited)


func test_a_wave_that_clears_a_second_before_a_scene_comes_two_seconds_after_it() -> void:
	var main := await _main()
	var arena := main.arena()
	var log := []
	arena.wave_started.connect(func(i: int) -> void: log.append({wave = i, state = Game.state, play = Game.play_frames}))
	for foe in arena.enemies():
		foe.set_brain(Brain.new())
	var cleared_at := Game.play_frames
	for foe in arena.enemies():
		foe.die()
	await frames(60)
	var director := Director.play(&"fixture_yard_entrance", main)
	assert_true(director != null, "the scene plays: %s" % Director.last_refusal)
	if director == null:
		return
	var guard := 0
	while director.phase != Director.Phase.LEAD_OUT and guard < 600:
		await frames(1)
		guard += 1
	assert_true(log.is_empty(), "no wave came during the scene (%s)" % [log])
	guard = 0
	while log.is_empty() and guard < 400:
		await frames(1)
		guard += 1
	assert_false(log.is_empty(), "the next wave comes after the scene")
	if log.is_empty():
		return
	var waited: int = log[0].play - cleared_at
	assert_true(waited >= 178 and waited <= 184, "three seconds of play in all after the last foe fell, a second before the scene and two after it (%d frames)" % waited)


func test_the_death_reset_does_not_fire_in_a_scene() -> void:
	var main := await _main()
	var arena := main.arena()
	for foe in arena.enemies():
		foe.set_brain(Brain.new())
	var director := Director.play(&"fixture_yard_entrance", main)
	assert_true(director != null, "the scene plays: %s" % Director.last_refusal)
	if director == null:
		return
	while director.frame < 60:
		await frames(1)
	var player := main.player
	player.die()
	assert_true(player.dead)
	var guard := 0
	while director.phase != Director.Phase.LEAD_OUT and guard < 600:
		await frames(1)
		guard += 1
	assert_true(player.dead, "he is still dead when the scene hands back: the reset did not run in it")
	await frames(150)
	assert_true(player.dead, "and three seconds of play have not yet passed (150 frames after)")
	await frames(60)
	assert_false(player.dead, "now the reset has stood him up")


func test_the_debug_keys_do_nothing_in_a_scene() -> void:
	var main := await _main()
	var arena := main.arena()
	for foe in arena.enemies():
		foe.set_brain(Brain.new())
	_key(KEY_F6)
	await frames(1)
	assert_eq(arena._extras.size(), 1, "control: out of a scene F6 sends a foe")
	arena._extras[0].set_brain(Brain.new())
	var director := Director.play(&"fixture_yard_entrance", main)
	assert_true(director != null, "the scene plays: %s" % Director.last_refusal)
	if director == null:
		return
	await frames(30)
	var foes := _foes(arena)
	var extras := arena._extras.size()
	var player_at := main.player.global_position
	for key in [KEY_F6, KEY_F7, KEY_F8, KEY_F9]:
		_key(key)
		await frames(1)
	assert_eq(arena._extras.size(), extras, "F6 to F9 sent no foe and cleared none in the scene")
	assert_eq(_foes(arena), foes, "and F9 reset nothing")
	assert_true(main.player.global_position.distance_to(player_at) < 0.5, "nor moved him to the spawn")
	assert_true(Director.current() == director, "the scene plays on")
