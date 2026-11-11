extends TestCase
## The Arena (world/arena.gd): the training yard's waves of Knuckles, how it hands out their spawns, clears and starts
## the next wave, resets after the player's death or F9, and hashes the whole fight (state_hash, for replays). It also
## carries what the preview demo's director promised: no more than two Knuckles press an attack at once, and a
## respawn or reset rolls new dice.

const YARD := "res://world/training_yard/training_yard.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const WAVES := "res://data/arena/waves.tres"
## The tier of each def, by id.
const TIERS := {&"knuckle_1": 1, &"knuckle_2": 2, &"knuckle_3": 3}


func before_each() -> void:
	Arena.reset_spawn_counts()


func after_each() -> void:
	Game.reset()


# The yard with Abarax standing in it (a child of it, where Main would put him beside it) and the arena begun: its first
# wave sent. `automatic` false is the self-test's arena, which does nothing by itself.
func _arena(automatic := true) -> Arena:
	var arena := track((load(YARD) as PackedScene).instantiate()) as Arena
	arena.automatic = automatic
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.name = "Player"
	player.def = load(ABARAX) as ActorDef
	player.set_brain(Brain.new())
	arena.add_child(player)
	arena.begin(player)
	return arena


func _foes(arena: Arena) -> Array[Actor]:
	var found: Array[Actor] = []
	for node in arena.get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		var actor := node as Actor
		if actor != null and arena.is_ancestor_of(actor):
			found.append(actor)
	return found


func _tier(actor: Actor) -> int:
	return TIERS[actor.def.id]


func _attacking(actor: Actor) -> bool:
	if actor.paired_with != null:
		return true
	return actor.runner.current != null and actor.runner.current.kind == MoveData.Kind.ATTACK


func _press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		get_viewport().push_input(event)


func test_the_wave_data_is_the_eight_waves() -> void:
	var set := load(WAVES) as ArenaWaveSet
	assert_true(set != null, "data/arena/waves.tres is an ArenaWaveSet")
	if set == null:
		return
	var shown: Array = []
	for wave in set.waves:
		assert_eq(wave.defs.size(), wave.count.size(), "a count for each def")
		var who: Array = []
		for i in wave.defs.size():
			who.append([String(wave.defs[i].id), wave.count[i]])
		shown.append(who)
	assert_eq(shown, [
		[["knuckle_1", 1]], [["knuckle_1", 2]], [["knuckle_drummer", 1]], [["knuckle_2", 1]], [["knuckle_2", 1], ["knuckle_1", 1]],
		[["knuckle_drummer", 1], ["knuckle_1", 1]], [["knuckle_3", 1]], [["knuckle_3", 1], ["knuckle_2", 1]],
	], "1x I; 2x I; the Drummer; 1x II; II + I; the Drummer + I; 1x III; III + II")
	var bare := Arena.new()
	assert_eq(bare.waves.size(), 8, "and the arena has them by default")
	bare.free()


func test_waves_spawn_their_defs_at_the_enemy_spawns() -> void:
	var arena := _arena()
	var started: Array[int] = []
	arena.wave_started.connect(func(i: int) -> void: started.append(i))
	assert_true(arena.get_node_or_null("AttackTokens") is AttackTokens, "the arena has an AttackTokens child")
	assert_eq(arena.wave, 0, "it began with wave 0")
	var first := _foes(arena)
	assert_eq(first.size(), 1, "wave 0 is one Knuckle")
	assert_eq(_tier(first[0]), 1, "tier I")
	assert_vec_near(first[0].global_position, (arena.get_node("EnemySpawn_1") as Marker3D).global_position, 1e-3, "at the first enemy spawn")
	assert_true(first[0].brain is EnemyBrain, "thinking with the enemy brain its def names")
	var to_him := arena.player.global_position - first[0].global_position
	to_him.y = 0.0
	assert_true(first[0].facing().dot(to_him.normalized()) > 0.95, "facing the player")
	# Wave 4 is a tier II and a tier I, at the first two spawns in turn.
	arena.start_wave(4)
	assert_eq(started, [4] as Array[int], "wave_started(4)")
	var fresh := _foes(arena).filter(func(a: Actor) -> bool: return not first.has(a))
	assert_eq(fresh.size(), 2, "two more")
	var tiers := fresh.map(func(a: Actor) -> int: return _tier(a))
	assert_eq(tiers, [2, 1], "the tier II first, then the tier I")
	for i in fresh.size():
		var marker := arena.get_node("EnemySpawn_%d" % (i + 1)) as Marker3D
		assert_vec_near(fresh[i].global_position, marker.global_position, 1e-3, "in turn: the %d-th at EnemySpawn_%d" % [i + 1, i + 1])
	# Five Knuckles take the four spawns round again.
	arena.start_wave(1)
	arena.start_wave(1)
	assert_true(_foes(arena).size() >= 7, "more of them")


func test_a_cleared_wave_starts_the_next_after_three_seconds() -> void:
	var arena := _arena()
	var events: Array = []
	arena.wave_cleared.connect(func(i: int) -> void: events.append(["cleared", i]))
	arena.wave_started.connect(func(i: int) -> void: events.append(["started", i]))
	var player := arena.player
	player.stats.take_damage(40.0)
	player.stats.spend_stamina(70.0)
	player.stats.damage_posture(30.0)
	var foe := _foes(arena)[0]
	foe.die()
	assert_eq(events, [["cleared", 0]], "wave_cleared(0) the moment the last one falls")
	await frames(170)
	assert_eq(events.size(), 1, "the next wave waits (2.8 s)")
	assert_true(player.stats.hp < player.stats.max_hp, "and his bars are not full yet")
	await frames(20)
	assert_eq(events, [["cleared", 0], ["started", 1]], "three seconds after, wave 1 starts")
	assert_eq(_foes(arena).size(), 2, "two tier I Knuckles")
	assert_eq(player.stats.hp, player.stats.max_hp, "his HP is full")
	assert_eq(player.stats.stamina, player.stats.max_stamina, "his stamina is full")
	assert_eq(player.stats.posture, player.stats.max_posture, "his posture is full")
	assert_false(is_instance_valid(foe) and foe.is_inside_tree(), "and the dead one has been taken away")


func test_the_last_wave_is_followed_by_the_first_again() -> void:
	var arena := _arena()
	arena.start_wave(arena.wave_count() - 1)
	for foe in _foes(arena):
		foe.die()
	await frames(185)
	assert_eq(arena.wave, 0, "the waves go round")


func test_reset_clears_and_refills() -> void:
	var arena := _arena()
	arena.start_wave(1)
	var before := _foes(arena)
	assert_true(before.size() >= 2)
	before[0].die()
	var player := arena.player
	player.place(Transform3D(Basis(), Vector3(5, 0, 0)))
	player.stats.take_damage(55.0)
	player.stats.spend_stamina(100.0)
	arena.reset()
	await frames(1)
	for old in before:
		assert_false(is_instance_valid(old) and old.is_inside_tree(), "the old Knuckles are gone")
	var now := _foes(arena)
	assert_eq(now.size(), 2, "wave 1 again: two Knuckles")
	assert_eq(arena.wave, 1, "the current wave restarted, not the first")
	assert_vec_near(player.global_position, arena.spawn().origin, 1e-3, "the player is at Spawn")
	assert_eq(player.stats.hp, player.stats.max_hp, "with full HP")
	assert_eq(player.stats.stamina, player.stats.max_stamina, "full stamina")
	assert_false(player.stats.exhausted, "not exhausted")
	assert_false(player.dead, "alive")


func test_the_debug_keys_spawn_one_of_a_tier_and_f9_resets() -> void:
	var arena := _arena()
	await frames(2)
	var base := _foes(arena).size()
	_press_key(KEY_F6)
	_press_key(KEY_F7)
	_press_key(KEY_F8)
	var foes := _foes(arena)
	assert_eq(foes.size(), base + 3, "three more")
	var tiers: Array = foes.map(func(a: Actor) -> int: return _tier(a))
	assert_eq(tiers.count(1), 2, "the wave's tier I and one more")
	assert_eq(tiers.count(2), 1, "a tier II")
	assert_eq(tiers.count(3), 1, "a tier III")
	_press_key(KEY_F9)
	await frames(1)
	assert_eq(_foes(arena).size(), 1, "F9 resets: wave 0's one Knuckle is all there is")
	assert_eq(arena.wave, 0)


func test_state_hash_changes_with_play_and_repeats_with_the_same_state() -> void:
	var arena := _arena()
	await frames(5)
	var a := arena.state_hash()
	assert_eq(arena.state_hash(), a, "the same state hashes the same")
	await frames(30)
	var b := arena.state_hash()
	assert_ne(b, a, "play changes it")
	arena.player.stats.take_damage(10.0)
	var c := arena.state_hash()
	assert_ne(c, b, "his HP is in it")
	arena.player.stats.spend_stamina(20.0)
	assert_ne(arena.state_hash(), c, "his stamina is in it")
	var d := arena.state_hash()
	_foes(arena)[0].stats.damage_posture(5.0)
	assert_ne(arena.state_hash(), d, "and a foe's posture")
	var e := arena.state_hash()
	arena.player.global_position += Vector3(0.002, 0, 0)
	assert_ne(arena.state_hash(), e, "a position to the millimetre")
	var f := arena.state_hash()
	arena.player.global_position += Vector3(0.0002, 0, 0)
	assert_eq(arena.state_hash(), f, "but not a fifth of one")


func test_reset_spawn_counts_can_start_at_a_round_and_so_a_seed_is_a_fight() -> void:
	Arena.reset_spawn_counts(7)
	var arena := _arena()
	var foe := _foes(arena)[0]
	assert_eq(foe.spawn_count, 7, "the first foes roll the dice of round 7")
	Arena.reset_spawn_counts()
	assert_eq(_foes(_arena())[0].spawn_count, 0, "and no argument is the first round")


func test_state_hash_counts_frames_from_the_waves_start_not_the_engines() -> void:
	# A replay needs the same hash whenever it is played: two fights alike in everything but the engine's frame count (the
	# second begins a hundred frames later) hash alike frame for frame, and a frame later is another hash.
	Arena.reset_spawn_counts()
	var first := _arena()
	await frames(20)
	var early := first.state_hash()
	first.queue_free()
	await frames(100)
	Arena.reset_spawn_counts()
	var second := _arena()
	await frames(20)
	assert_eq(second.state_hash(), early, "the same fight 100 frames of the engine's count later")
	await frames(1)
	assert_ne(second.state_hash(), early, "and a frame on is another hash")


func test_state_hash_includes_the_current_move_and_the_wave() -> void:
	var arena := _arena()
	await frames(3)
	var idle := arena.state_hash()
	arena.player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	var jabbing := arena.state_hash()
	assert_ne(jabbing, idle, "the move playing is in it")
	arena.player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData, true)
	var wave := arena.wave
	arena.wave = wave + 1
	assert_ne(arena.state_hash(), jabbing, "and the wave")
	arena.wave = wave


func test_never_more_than_two_knuckles_attack_at_once_and_they_never_overlap() -> void:
	var arena := _arena()
	var player := arena.player
	player.stats.hp = 100000.0
	player.stats.max_hp = 100000.0
	_press_key(KEY_F6)
	_press_key(KEY_F6)
	var knuckles := _foes(arena)
	assert_eq(knuckles.size(), 3, "three Knuckles")
	# All three stand in his face so that each wants to attack.
	for i in knuckles.size():
		var at := player.global_position + Vector3(2.0 * (i - 1), 0, -1.6)
		knuckles[i].place(Transform3D(Basis(Vector3.UP, 0.0), at))
	var started := [0]
	for knuckle in knuckles:
		knuckle.runner.move_started.connect(func(m: MoveData) -> void:
			if m.kind == MoveData.Kind.ATTACK:
				started[0] += 1)
	var most := 0
	var closest := INF
	var everyone: Array[Actor] = [player]
	everyone.append_array(knuckles)
	for i in 900:
		await frames(1)
		var now := 0
		for knuckle in knuckles:
			if _attacking(knuckle):
				now += 1
		most = maxi(most, now)
		for x in everyone.size():
			for y in range(x + 1, everyone.size()):
				var d := everyone[x].global_position - everyone[y].global_position
				d.y = 0.0
				closest = minf(closest, d.length())
	assert_true(started[0] >= 4, "they did attack (%d attack moves in 15 s)" % started[0])
	assert_eq(most, AttackTokens.PER_TARGET, "two at a time, never more")
	assert_true(closest > 0.6, "and no two bodies overlap (the closest centres: %.2f m)" % closest)


func test_a_reset_rolls_new_dice() -> void:
	var arena := _arena()
	var first := _foes(arena).map(func(k: Actor) -> int: return (k.brain as EnemyBrain).rng.seed)
	arena.reset()
	await frames(1)
	var again := _foes(arena).map(func(k: Actor) -> int: return (k.brain as EnemyBrain).rng.seed)
	assert_eq(first.size(), again.size())
	assert_ne(again, first, "the Knuckles of a reset roll new dice")
	arena.free()
	Arena.reset_spawn_counts()
	var fresh := _arena()
	var same := _foes(fresh).map(func(k: Actor) -> int: return (k.brain as EnemyBrain).rng.seed)
	assert_eq(same, first, "from the same start, the same dice: a run can be reproduced")


func test_an_arena_that_is_not_automatic_does_nothing_by_itself() -> void:
	var arena := _arena(false)
	var started: Array[int] = []
	arena.wave_started.connect(func(i: int) -> void: started.append(i))
	for foe in _foes(arena):
		foe.die()
	await frames(240)
	assert_eq(started, [] as Array[int], "no next wave")
	arena.player.die()
	await frames(240)
	assert_true(arena.player.dead, "and a dead player stays dead: no reset")


func test_an_edit_to_the_wave_set_changes_what_spawns_after_the_yard_is_saved_and_loaded() -> void:
	# A scene saved from the yard must not bake the waves in: the wave set is what they come from, so editing it still counts.
	var source := (load(YARD) as PackedScene).instantiate() as Arena
	var packed := PackedScene.new()
	assert_eq(packed.pack(source), OK, "the yard packs")
	source.free()
	var set := load(WAVES) as ArenaWaveSet
	var original := set.waves[0].count[0]
	set.waves[0].count[0] = 3
	var arena := track(packed.instantiate()) as Arena
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.def = load(ABARAX) as ActorDef
	player.set_brain(Brain.new())
	arena.add_child(player)
	arena.begin(player)
	var sent := _foes(arena).size()
	set.waves[0].count[0] = original
	assert_eq(sent, 3, "wave 0 sent three: the saved scene follows the wave set, not a copy of it")


func test_the_yard_scene_holds_no_copy_of_the_waves() -> void:
	var text := FileAccess.get_file_as_string(YARD)
	assert_false(text.contains("Wave_") or text.contains("waves ="), "training_yard.tscn keeps no baked waves")


func test_dying_on_the_frame_the_last_knuckle_dies_starts_the_next_wave_once() -> void:
	var arena := _arena()
	var started: Array[int] = []
	arena.wave_started.connect(func(i: int) -> void: started.append(i))
	_foes(arena)[0].die()
	arena.player.die()
	await frames(200)
	assert_eq(started, [1] as Array[int], "wave 1 started, once (not by the timer and again by the reset)")
	assert_eq(_foes(arena).size(), 2, "with its two Knuckles")
	assert_false(arena.player.dead, "and he is up")


func test_a_foe_falling_after_the_player_does_not_start_a_wave_under_his_corpse() -> void:
	var arena := _arena()
	arena.start_wave(1)
	var started: Array[int] = []
	arena.wave_started.connect(func(i: int) -> void: started.append(i))
	arena.player.die()
	await frames(60)
	for foe in _foes(arena):
		foe.die()
	await frames(100)
	assert_eq(started, [] as Array[int], "no wave while he lies dead (3 s after the foes fell would be here, were it not cancelled)")
	await frames(30)
	assert_eq(started, [2] as Array[int], "the reset after his death starts the next one, once")
