extends TestCase
## The stretch's run (world/stretch/stretch_run.gd): the player's place and bars at the start (a new game's, a saved game's), the
## shrines (rest, respawn point, the press that rests), the way back three seconds after a death, the world's flags and the hash of
## it all; and where he last stood on safe ground, which the saved game keeps ("save exact position too!").
##
## The world is the real stretch region with Abarax as a child of it (a brain that does nothing) and a StretchRun started on it;
## the store is null unless a test says (then it writes only under user://save_test/run, never the player's folder).

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE := "res://data/actors/knuckle_1.tres"
const DIR := "user://save_test/run"

var _runs: Array[StretchRun] = []


func before_each() -> void:
	_clean()
	Game.reset()
	Game.change(Game.State.PLAY)


func after_each() -> void:
	InputFeed.release()
	# A run leaving the tree saves (that is under test elsewhere): not into a folder this test is about to remove.
	for run in _runs:
		if is_instance_valid(run):
			run.store = null
	_runs.clear()
	_clean()
	Game.reset()


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)


func _actor(region: Region, def_path: String, at: Vector3, actor_name: String) -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.name = actor_name
	actor.def = load(def_path) as ActorDef
	actor.position = at
	actor.set_brain(Brain.new())
	region.add_child(actor)
	return actor


# The stretch with Abarax in it, not yet started (the physics has stepped, so the ground answers): {region, player}.
func _bare() -> Dictionary:
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	var player := _actor(region, ABARAX, Vector3.ZERO, "Player")
	await frames(2)
	return {region = region, player = player}


func _start(bare: Dictionary, data: SaveData = null, store: SaveStore = null) -> StretchRun:
	var def := Registry.fetch(&"stretch", &"bilibara") as StretchDef
	var run := StretchRun.start(bare.region, bare.player, def, store, data if data != null else SaveData.new_game())
	_runs.append(run)
	return run


# The stretch, a started run on it and Abarax: {region, player, run}.
func _world(data: SaveData = null, store: SaveStore = null) -> Dictionary:
	var bare := await _bare()
	bare["run"] = _start(bare, data, store)
	return bare


func _at(player: Actor, at: Vector3, yaw_deg := 0.0) -> void:
	player.place(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at))


func _press(action: StringName) -> void:
	InputFeed.apply({"pressed": PackedStringArray([action])})
	await frames(1)
	InputFeed.release()
	await frames(2)


func _shrine(id: StringName) -> ShrineDef:
	return Registry.fetch(&"stretch", id) as ShrineDef


func _forward(yaw_deg: float) -> Vector3:
	return Vector3(sin(deg_to_rad(yaw_deg)), 0.0, cos(deg_to_rad(yaw_deg)))


func _store() -> SaveStore:
	return SaveStore.new(DIR)


# --- the start, shrines, rest, death ---

func test_a_new_game_stands_at_the_first_shrines_respawn_with_full_bars() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	assert_vec_near(player.global_position, Vector3(-32.5, 0, 1.25), 0.01, "at rose_a's respawn")
	assert_vec_near(player.facing(), _forward(90.0), 0.01, "facing 90 degrees")
	assert_eq(player.stats.hp, player.stats.max_hp, "full HP")
	assert_eq(player.stats.stamina, player.stats.max_stamina, "full stamina")
	assert_eq(player.stats.posture, player.stats.max_posture, "full posture")
	assert_eq(run.data.rest_shrine, &"", "no shrine rested at")
	assert_eq(run.rest_shrine().id, &"rose_a", "the start is rose_a")


func test_resting_fills_the_bars_sets_the_respawn_and_flags_the_shrine() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	player.stats.hp = 10.0
	player.stats.stamina = 0.0
	player.stats.exhausted = true
	player.stats.posture = 0.0
	player.stats.posture_broken = true
	var rested: Array[StringName] = []
	var changed: Array[StringName] = []
	var resets := [0]
	run.rested.connect(func(id: StringName) -> void: rested.append(id))
	run.world_changed.connect(func(flag: StringName) -> void: changed.append(flag))
	run.world_reset.connect(func() -> void: resets[0] += 1)
	run.rest(_shrine(&"rose_b"))
	assert_eq(player.stats.hp, player.stats.max_hp, "HP full")
	assert_eq(player.stats.stamina, player.stats.max_stamina, "stamina full")
	assert_eq(player.stats.posture, player.stats.max_posture, "posture full")
	assert_false(player.stats.exhausted, "not exhausted")
	assert_false(player.stats.posture_broken, "posture mended")
	assert_eq(run.data.rest_shrine, &"rose_b", "the respawn is rose_b")
	assert_true(run.flag(&"shrine:rose_b"), "the shrine is flagged")
	assert_eq(rested, [&"rose_b"], "rested once")
	assert_eq(resets[0], 1, "world_reset once")
	assert_eq(changed, [&"shrine:rose_b"], "world_changed once with the flag")
	run.rest(_shrine(&"rose_b"))
	assert_eq(rested, [&"rose_b", &"rose_b"], "resting there again: rested again")
	assert_eq(changed, [&"shrine:rose_b"], "but the flag is not announced again")


func test_a_press_of_interact_within_a_shrines_radius_rests_and_one_outside_does_not() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	var plinth := _shrine(&"rose_b").plinth
	var rested: Array[StringName] = []
	run.rested.connect(func(id: StringName) -> void: rested.append(id))
	_at(player, plinth + Vector3(-1.9, 0, 0))
	await frames(2)
	assert_true(run.interactor.current is Shrine, "the shrine is in reach at 1.9 m")
	assert_eq(run.interactor.prompt_line(), "%s  Rest" % ControlsList.shown(&"interact", false), "the line names the key and the deed")
	await _press(&"interact")
	assert_eq(rested, [&"rose_b"], "one press, one rest")
	_at(player, plinth + Vector3(-2.1, 0, 0))
	await frames(2)
	assert_true(run.interactor.current == null, "nothing in reach at 2.1 m")
	assert_eq(run.interactor.prompt_line(), "", "and no line")
	await _press(&"interact")
	assert_eq(rested, [&"rose_b"], "a press outside does nothing")


func test_nothing_is_interacted_with_while_dead_frozen_in_a_move_or_paired() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	var foe := _actor(w.region, KNUCKLE, Vector3(0, 0, 0), "Foe")
	var touched := [0]
	run.interactor.interacted.connect(func(_what: Interactable) -> void: touched[0] += 1)
	var plinth := _shrine(&"rose_a").plinth
	_at(player, plinth + Vector3(1.0, 0, 0))
	await frames(2)
	# frozen
	player.frozen = 30
	await _press(&"interact")
	player.frozen = 0
	assert_eq(touched[0], 0, "not while frozen")
	# in a move
	player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	await _press(&"interact")
	assert_true(player.runner.current != null, "(the jab is still on)")
	assert_eq(touched[0], 0, "not in a move")
	player.runner.stop()
	await frames(2)
	# paired
	player.paired_with = foe
	await _press(&"interact")
	player.paired_with = null
	assert_eq(touched[0], 0, "not paired")
	# dead
	player.die()
	await _press(&"interact")
	assert_eq(touched[0], 0, "not dead")
	# and, as the control, standing free he can
	run.respawn()
	_at(player, plinth + Vector3(1.0, 0, 0))
	await frames(200)
	await _press(&"interact")
	assert_eq(touched[0], 1, "standing free, the same press interacts")


func test_death_stands_him_up_at_the_last_shrine_after_three_seconds() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	var fell := [0]
	var back := [0]
	run.player_fell.connect(func() -> void: fell[0] += 1)
	run.respawned.connect(func() -> void: back[0] += 1)
	_at(player, Vector3(-10, 0, 0))
	await frames(2)
	player.die()
	assert_eq(fell[0], 1, "player_fell once")
	await frames(179)
	assert_true(player.dead, "still down at 179 frames")
	await frames(2)
	assert_false(player.dead, "up at 181")
	assert_vec_near(player.global_position, Vector3(-32.5, 0, 1.25), 0.01, "at rose_a's respawn")
	assert_eq(player.stats.hp, player.stats.max_hp, "with full bars")
	assert_eq(back[0], 1, "respawned once")
	# after resting at rose_b, at rose_b
	run.rest(_shrine(&"rose_b"))
	_at(player, Vector3(-10, 0, 0))
	await frames(2)
	player.die()
	await frames(182)
	assert_false(player.dead, "up again")
	assert_vec_near(player.global_position, Vector3(31.8, 0, -35.6), 0.01, "at rose_b's respawn")
	assert_eq(back[0], 2, "respawned twice in all")


func test_the_three_seconds_stand_still_in_a_pause_and_in_a_scene() -> void:
	for state: Game.State in [Game.State.PAUSE, Game.State.CUTSCENE]:
		Game.reset()
		Game.change(Game.State.PLAY)
		var w := await _world()
		var player: Actor = w.player
		_at(player, Vector3(-10, 0, 0))
		await frames(2)
		player.die()
		await frames(30)
		Game.change(state)
		await frames(120)
		Game.change(Game.State.PLAY)
		await frames(120)
		assert_true(player.dead, "%s: still dead, 150 play frames in" % Game.State.find_key(state))
		await frames(35)
		assert_false(player.dead, "%s: up once 180 play frames have gone" % Game.State.find_key(state))
		(w.region as Node).queue_free()
		await frames(2)


func test_every_shrine_is_standing_ground_and_clear_of_the_foes() -> void:
	var w := await _world()
	var region: Region = w.region
	var reached := StretchGround.reached(region)
	for id: StringName in [&"rose_a", &"rose_b"]:
		var shrine := _shrine(id)
		assert_true(StretchGround.stands(region, shrine.respawn), "%s: the respawn is standing ground" % id)
		var toward := (shrine.respawn - shrine.plinth).normalized()
		assert_true(StretchGround.stands(region, shrine.plinth + toward), "%s: and so is the ground 1 m from the plinth toward it" % id)
		assert_true(shrine.respawn.distance_to(shrine.plinth) <= 3.0, "%s: the respawn is within 3 m of the plinth" % id)
		for point: Vector3 in [shrine.respawn, shrine.plinth + toward]:
			assert_true(reached.has(StretchGround.cell_of(Vector2(point.x, point.z))), "%s: %s is walked to from the spawn" % [id, point])


func test_set_flag_saves_through_the_store_and_announces_once() -> void:
	var store := _store()
	var w := await _world(null, store)
	var run: StretchRun = w.run
	var changed := [0]
	run.world_changed.connect(func(_flag: StringName) -> void: changed[0] += 1)
	run.set_flag(&"x")
	run.set_flag(&"x")
	assert_eq(changed[0], 1, "announced once")
	var saved := store.read()
	assert_true(saved != null and saved.memory.has(&"x"), "the file has the flag")
	# a run with no store writes nothing and does not complain
	var other := await _world()
	other.run.set_flag(&"y")
	assert_true(other.run.flag(&"y"), "it is still remembered")
	assert_eq(other.run.save_now(), OK, "and saving it is not an error")


func test_the_state_hash_changes_with_the_world_and_not_with_the_clock() -> void:
	var one := await _world()
	await frames(3)
	var begun: int = one.run.state_hash()
	(one.region as Node).queue_free()
	await frames(2)
	var two := await _world()
	await frames(3)
	assert_eq(two.run.state_hash(), begun, "two runs begun alike hash alike")
	var run: StretchRun = two.run
	var before := run.state_hash()
	Game.change(Game.State.PAUSE)
	await frames(120)
	Game.change(Game.State.PLAY)
	assert_eq(run.state_hash(), before, "120 paused frames do not change it")
	run.rest(_shrine(&"rose_b"))
	assert_ne(run.state_hash(), before, "a rest does")
	var rested := run.state_hash()
	run.set_flag(&"x")
	assert_ne(run.state_hash(), rested, "a flag does")
	var flagged := run.state_hash()
	_at(two.player, Vector3(-20, 0, 0))
	assert_ne(run.state_hash(), flagged, "a moved player does")


# --- where he stood: the saved position and bars ---

func test_a_game_saved_twenty_metres_from_a_shrine_loads_there_with_the_bars_it_had() -> void:
	var store := _store()
	var first := await _world(null, store)
	var player: Actor = first.player
	_at(player, Vector3(-15, 0, 0), 217.0)
	await frames(70)
	player.stats.hp = player.stats.max_hp * 0.5
	player.stats.stamina = player.stats.max_stamina * 0.75
	assert_eq(first.run.save_now(), OK)
	var saved := store.read()
	assert_true(saved != null and not saved.at.is_empty(), "the file says where he stood")
	(first.region as Node).queue_free()
	await frames(2)
	var second := await _world(saved)
	var again: Actor = second.player
	assert_vec_near(again.global_position, Vector3(-15, 0, 0), 0.01, "he is where he stood (20 m from the shrine)")
	assert_vec_near(again.facing(), _forward(217.0), 0.01, "facing as he faced")
	assert_near(again.stats.hp, again.stats.max_hp * 0.5, 0.01, "with half his HP")
	assert_near(again.stats.stamina, again.stats.max_stamina * 0.75, 0.01, "and three quarters of his stamina")
	assert_eq(again.stats.posture, again.stats.max_posture, "his posture was full")


func test_with_a_living_foe_near_the_place_is_not_noted_and_the_last_safe_place_is_the_one_saved() -> void:
	var store := _store()
	var w := await _world(null, store)
	var player: Actor = w.player
	var foe := _actor(w.region, KNUCKLE, Vector3(10, 0, 0), "Foe")
	_at(player, Vector3(-20, 0, 0), 90.0)
	await frames(70)
	assert_true(w.run.is_safe(), "he is safe where he stands (the foe is 30 m off)")
	_at(foe, Vector3(-15, 0, 0))
	await frames(70)
	assert_false(w.run.is_safe(), "a living foe 5 m off: not safe")
	# he walks 10 m on with the foe following at 5 m
	for step in 10:
		_at(player, Vector3(-20 + step + 1, 0, 0), 90.0)
		_at(foe, Vector3(-15 + step + 1, 0, 0))
		await frames(7)
	await frames(70)
	assert_eq(w.run.save_now(), OK)
	var saved := store.read()
	assert_true(saved != null and not saved.at.is_empty(), "a place is saved")
	(w.region as Node).queue_free()
	await frames(2)
	var second := await _world(saved)
	assert_vec_near(second.player.global_position, Vector3(-20, 0, 0), 0.01, "he loads where he last stood with no foe near")


func test_an_at_inside_a_wall_loads_at_the_shrine_with_the_saved_bars() -> void:
	var bare := await _bare()
	var inside := Vector3(-20, 0, -7)
	assert_false(StretchGround.stands(bare.region, inside), "(the point is not standing ground)")
	var data := SaveData.new_game()
	data.rest_shrine = &"rose_b"
	data.at = {x = inside.x, y = inside.y, z = inside.z, yaw = 10.0}
	data.bars = {hp = 0.5, stamina = 0.25, posture = 1.0}
	_start(bare, data)
	var player: Actor = bare.player
	assert_vec_near(player.global_position, Vector3(31.8, 0, -35.6), 0.01, "he stands at rose_b's respawn")
	assert_vec_near(player.facing(), _forward(180.0), 0.01, "facing as the shrine says")
	assert_near(player.stats.hp, player.stats.max_hp * 0.5, 0.01, "with the saved HP")
	assert_near(player.stats.stamina, player.stats.max_stamina * 0.25, 0.01, "and the saved stamina")


func test_a_place_with_no_ground_under_it_or_an_odd_height_loads_at_the_shrine() -> void:
	for at: Dictionary in [{x = 0.0, y = 3.0, z = 0.0, yaw = 0.0}, {x = 500.0, y = 0.0, z = 500.0, yaw = 0.0}]:
		var bare := await _bare()
		var data := SaveData.new_game()
		data.at = at
		_start(bare, data)
		assert_vec_near(bare.player.global_position, Vector3(-32.5, 0, 1.25), 0.01, "%s: at the first shrine" % [at])
		(bare.region as Node).queue_free()
		await frames(2)


func test_a_yaw_outside_zero_to_360_is_brought_in_before_he_is_turned() -> void:
	var data := SaveData.new_game()
	data.at = {x = -15.0, y = 0.0, z = 0.0, yaw = -143.0}
	var bare := await _bare()
	_start(bare, data)
	assert_vec_near(bare.player.facing(), _forward(217.0), 0.01, "-143 degrees is 217")
	assert_true(rad_to_deg(atan2(bare.player.facing().x, bare.player.facing().z)) > -180.0, "(a turn, not a spin)")


func test_saved_bars_with_no_hp_load_with_one_and_able_to_act() -> void:
	var data := SaveData.new_game()
	data.at = {x = -15.0, y = 0.0, z = 0.0, yaw = 0.0}
	data.bars = {hp = 0.0, stamina = 0.0, posture = 0.0}
	var w := await _world(data)
	var player: Actor = w.player
	assert_eq(player.stats.hp, 1.0, "HP 1, never dead")
	assert_false(player.dead, "alive")
	assert_false(player.stats.exhausted, "not exhausted")
	assert_false(player.stats.posture_broken, "posture not broken")


func test_a_death_empties_the_place_and_the_bars_in_the_file_written_at_the_death() -> void:
	var store := _store()
	var w := await _world(null, store)
	var player: Actor = w.player
	_at(player, Vector3(-15, 0, 0))
	await frames(70)
	assert_eq(w.run.save_now(), OK)
	var before := store.read()
	assert_true(before != null and not before.at.is_empty() and not before.bars.is_empty(), "(a place and bars were saved)")
	player.die()
	var at_death := store.read()
	assert_true(at_death != null, "a file was written")
	assert_true(at_death.at.is_empty(), "the place is empty in it")
	assert_true(at_death.bars.is_empty(), "and the bars")
	await frames(185)
	var after := store.read()
	assert_true(after.at.is_empty() and after.bars.is_empty(), "and still empty once he is back at the shrine")
	await frames(400)  # he is on his feet again (the getup is no safe time) and a second has gone
	assert_eq(w.run.save_now(), OK)
	assert_false(store.read().at.is_empty(), "the next safe second notes a place again")


func test_a_rest_notes_the_place_he_rests_at_and_a_new_games_file_has_neither() -> void:
	var store := _store()
	var w := await _world(null, store)
	var player: Actor = w.player
	assert_eq(w.run.save_now(), OK)
	var fresh := store.read()
	assert_true(fresh.at.is_empty() and fresh.bars.is_empty(), "a new game's file has no place and no bars")
	var spot := _shrine(&"rose_b").plinth + Vector3(0, 0, 1.5)
	_at(player, spot, 180.0)
	player.stats.hp = 20.0
	await frames(2)
	w.run.rest(_shrine(&"rose_b"))
	var rested := store.read()
	assert_true(rested != null and not rested.at.is_empty(), "the rest wrote a place")
	assert_near(rested.at.x, spot.x, 0.01, "where he rested (x)")
	assert_near(rested.at.z, spot.z, 0.01, "(z)")
	assert_eq(rested.bars, {hp = 1.0, stamina = 1.0, posture = 1.0}, "with full bars")


func test_sixty_seconds_of_standing_still_after_a_save_write_nothing_more() -> void:
	var store := _store()
	var w := await _world(null, store)
	_at(w.player, Vector3(-15, 0, 0), 90.0)
	await frames(70)
	assert_eq(w.run.save_now(), OK)
	var main_file := DIR.path_join(SaveStore.MAIN)
	var bytes := FileAccess.get_file_as_bytes(main_file)
	var stamp := FileAccess.get_modified_time(main_file)
	await frames(3700)
	assert_eq(FileAccess.get_file_as_bytes(main_file), bytes, "the file's bytes are as they were")
	assert_eq(FileAccess.get_modified_time(main_file), stamp, "and so is its modification")
	assert_false(FileAccess.file_exists(DIR.path_join(SaveStore.BACKUP)), "no backup was made: nothing was written")


func test_moving_half_a_metre_or_turning_fifteen_degrees_is_a_change_and_less_is_not() -> void:
	var store := _store()
	var w := await _world(null, store)
	var run: StretchRun = w.run
	run.autosave_frames = 120
	var player: Actor = w.player
	_at(player, Vector3(-15, 0, 0), 90.0)
	await frames(70)
	assert_eq(run.save_now(), OK)
	var main_file := DIR.path_join(SaveStore.MAIN)
	var written := FileAccess.get_file_as_bytes(main_file)
	for small: Array in [[0.4, 0.0], [0.0, 14.0], [0.3, 10.0]]:
		_at(player, Vector3(-15 + small[0], 0, 0), 90.0 + small[1])
		await frames(300)
		assert_eq(FileAccess.get_file_as_bytes(main_file), written, "%s: not worth a write" % [small])
	for large: Array in [[0.6, 0.0], [0.0, 16.0]]:
		_at(player, Vector3(-15 + large[0], 0, 0), 90.0 + large[1])
		await frames(300)
		var now := FileAccess.get_file_as_bytes(main_file)
		assert_ne(now, written, "%s: a change, written at the next autosave" % [large])
		written = now
		_at(player, Vector3(-15, 0, 0), 90.0)
		await frames(300)
		written = FileAccess.get_file_as_bytes(main_file)


# A store that may not use its folder (the player's, in a test) answers OK and writes nothing: nothing the run does may count that OK as a
# saved game (no line in this task says "saved"; this holds the folder untouched and the answer honest about being OK).
func test_a_store_that_may_not_use_its_folder_writes_nothing_even_when_a_rest_asks() -> void:
	var store := SaveStore.new()
	assert_false(store.may_use(), "(the player's folder is not for a test)")
	var main_file := store.dir.path_join(SaveStore.MAIN)
	var before := FileAccess.file_exists(main_file)
	var w := await _world(null, store)
	var run: StretchRun = w.run
	run.rest(_shrine(&"rose_b"))
	assert_eq(run.save_now(), OK, "the answer is OK")
	assert_eq(FileAccess.file_exists(main_file), before, "and no file appeared in the player's folder")
