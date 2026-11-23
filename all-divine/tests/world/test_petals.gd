extends TestCase
## Petals and the corpse run (world/stretch/petals.gd and the run that owns them): a foe gives petals when it falls; a death leaves what
## he carries where he last stood on the floor, as a pile drawn in the world; walking into the pile takes it back that frame (no press,
## no pause); a second death before he reaches it wilts it for good; and the file is written at the moment of death, at the pickup and on
## the autosave tick.
##
## The world is the real stretch with Abarax in it (a brain that does nothing) and a run started on it. A store, where a test has one, is
## under user://save_test/petals and never the player's folder. A fight here presses as a person would; nothing is hammered.

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_2 := "res://data/actors/knuckle_2.tres"
const DIR := "user://save_test/petals"

var _runs: Array[StretchRun] = []


func before_each() -> void:
	_clean()
	Game.reset()
	Game.change(Game.State.PLAY)


func after_each() -> void:
	InputFeed.release()
	for run in _runs:
		if is_instance_valid(run):
			run.store = null  # leaving the tree saves: not into a folder this test is about to remove
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


# The stretch with Abarax and a started run on it (the physics has stepped, so the ground answers): {region, player, run}.
func _world(data: SaveData = null, store: SaveStore = null) -> Dictionary:
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	var player := _actor(region, ABARAX, Vector3.ZERO, "Player")
	await frames(2)
	var def := Registry.fetch(&"stretch", &"bilibara") as StretchDef
	var run := StretchRun.start(region, player, def, store, data if data != null else SaveData.new_game())
	_runs.append(run)
	return {region = region, player = player, run = run}


func _stand(player: Actor, at: Vector3) -> void:
	player.place(Transform3D(Basis(), at))
	await frames(2)


# He stands at `at` carrying `carried` petals and dies there.
func _fall(w: Dictionary, at: Vector3, carried: int) -> void:
	var run: StretchRun = w.run
	run.data.petals = carried
	await _stand(w.player, at)
	(w.player as Actor).die()


func _piles(w: Dictionary) -> Array[PetalPile]:
	var out: Array[PetalPile] = []
	for node in (w.run as StretchRun).find_children("*", "PetalPile", true, false):
		out.append(node as PetalPile)
	return out


func _respawn_of(id: StringName) -> Vector3:
	return (Registry.fetch(&"stretch", id) as ShrineDef).respawn


func _store() -> SaveStore:
	return SaveStore.new(DIR)


# --- the pile ---

func test_a_death_leaves_all_the_carried_petals_where_he_fell() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var dropped: Array = []
	run.petals.dropped.connect(func(amount: int, at: Vector3) -> void: dropped.append([amount, at]))
	var point := Vector3(10, 0, 0)
	await _fall(w, point, 120)
	assert_eq(run.petals.pile_amount(), 120, "the pile is all he carried")
	assert_true(run.petals.pile_at() != null, "there is a pile")
	if run.petals.pile_at() != null:
		assert_vec_near(run.petals.pile_at(), point, 0.01, "where he fell")
	assert_eq(run.petals.carried(), 0, "he carries none")
	assert_eq(dropped.size(), 1, "dropped once")
	if dropped.size() == 1:
		assert_eq(dropped[0][0], 120, "dropped 120")
		assert_vec_near(dropped[0][1], point, 0.01, "dropped at the point")
	assert_eq(run.data.deaths, 1, "one death counted")
	var piles := _piles(w)
	assert_eq(piles.size(), 1, "one PetalPile node")
	if piles.size() == 1:
		assert_vec_near(piles[0].global_position, point, 0.01, "drawn there")
		assert_eq(piles[0].amount, 120, "and it knows its amount")


func test_no_petals_means_no_pile_and_the_death_is_still_counted() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var dropped := [0]
	run.petals.dropped.connect(func(_amount: int, _at: Vector3) -> void: dropped[0] += 1)
	await _fall(w, Vector3(10, 0, 0), 0)
	assert_true(run.petals.pile_at() == null, "no pile")
	assert_eq(dropped[0], 0, "dropped never")
	assert_eq(run.data.deaths, 1, "the death is counted")
	assert_eq(_piles(w).size(), 0, "no node")


func test_walking_into_the_pile_takes_it_back_and_clears_it() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var player: Actor = w.player
	var taken: Array[int] = []
	run.petals.taken.connect(func(amount: int) -> void: taken.append(amount))
	var spawn := _respawn_of(&"rose_a")
	var point := spawn + Vector3(1.3, 0, 0)  # 1.3 m from where he stands up
	assert_true(StretchGround.stands(w.region, point), "(the place is standing ground)")
	await _fall(w, point, 120)
	await frames(10)
	assert_eq(run.petals.carried(), 0, "dead on the pile: nothing is taken")
	assert_eq(taken.size(), 0, "no `taken` while dead")
	await frames(185)
	assert_false(player.dead, "he is up")
	assert_vec_near(player.global_position, spawn, 0.01, "at the shrine, 1.3 m off the pile")
	await frames(5)
	assert_eq(run.petals.carried(), 0, "at 1.3 m nothing is taken")
	assert_eq(_piles(w).size(), 1, "the pile still lies")
	# a pause: in reach, and nothing is taken
	Game.change(Game.State.PAUSE)
	player.place(Transform3D(Basis(), point - Vector3(1.1, 0, 0)))  # 1.1 m from the pile, flat
	await frames(5)
	assert_eq(run.petals.carried(), 0, "in a pause nothing is taken")
	Game.change(Game.State.PLAY)
	await frames(1)
	assert_eq(run.petals.carried(), 120, "on the next frame of play it is his")
	assert_eq(taken, [120], "`taken` once with 120")
	await frames(2)
	assert_eq(_piles(w).size(), 0, "the PetalPile node is gone")
	assert_true(run.petals.pile_at() == null, "and the pile")


func test_the_pile_is_taken_on_the_frame_he_comes_within_reach_in_the_middle_of_a_move() -> void:
	# nothing is sticky: no press, no pause, no waiting for the move to end
	var w := await _world()
	var run: StretchRun = w.run
	var player: Actor = w.player
	var point := Vector3(10, 0, 0)
	await _fall(w, point, 50)
	await frames(185)
	await _stand(player, point + Vector3(3, 0, 0))
	assert_eq(run.petals.carried(), 0, "(he is 3 m off)")
	player.runner.start(Registry.fetch(&"moves", &"palm_jab") as MoveData)
	assert_true(player.runner.current != null, "(he is in a move)")
	player.place(Transform3D(Basis(), point + Vector3(1.0, 0, 0)))
	await frames(1)
	assert_eq(run.petals.carried(), 50, "taken in the very frame, in the middle of his blow")
	assert_true(player.runner.current != null, "and the blow goes on: nothing took control of him")


func test_a_second_death_before_the_pile_is_reached_wilts_it_for_good() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var player: Actor = w.player
	var wilted: Array[int] = []
	run.petals.wilted.connect(func(amount: int) -> void: wilted.append(amount))
	var a := Vector3(10, 0, 0)
	var b := Vector3(-10, 0, 0)
	await _fall(w, a, 120)
	await frames(185)
	var one := _actor(w.region, KNUCKLE_1, Vector3(0, 0, 3), "FoeOne")
	var two := _actor(w.region, KNUCKLE_2, Vector3(0, 0, -3), "FoeTwo")
	run.watch_foe(one)
	run.watch_foe(two)
	one.die()
	two.die()
	assert_eq(run.petals.carried(), 30, "the two foes gave 10 and 20")
	await _stand(player, b)
	player.die()
	assert_eq(wilted, [120], "`wilted` once with 120")
	assert_eq(run.petals.pile_amount(), 30, "the new pile is what he carried")
	if run.petals.pile_at() != null:
		assert_vec_near(run.petals.pile_at(), b, 0.01, "at B")
	var piles := _piles(w)
	assert_eq(piles.size(), 1, "exactly one PetalPile")
	if piles.size() == 1:
		assert_vec_near(piles[0].global_position, b, 0.01, "and it is at B, not at A")
	assert_eq(run.data.deaths, 2, "two deaths")


func test_dying_with_none_carried_still_wilts_the_old_pile() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var wilted: Array[int] = []
	run.petals.wilted.connect(func(amount: int) -> void: wilted.append(amount))
	await _fall(w, Vector3(10, 0, 0), 120)
	await frames(185)
	await _stand(w.player, Vector3(-10, 0, 0))
	w.player.die()
	assert_eq(wilted, [120], "the old pile wilted")
	assert_true(run.petals.pile_at() == null, "and none lies")
	assert_eq(_piles(w).size(), 0, "no node")
	assert_eq(run.data.deaths, 2, "both deaths counted")


func test_reaching_the_pile_then_dying_again_leaves_a_new_pile_of_everything() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var player: Actor = w.player
	var wilted := [0]
	run.petals.wilted.connect(func(_amount: int) -> void: wilted[0] += 1)
	var a := Vector3(10, 0, 0)
	await _fall(w, a, 120)
	await frames(185)
	await _stand(player, a)
	assert_eq(run.petals.carried(), 120, "he has it back")
	run.petals.gain(15)
	var b := Vector3(-10, 0, 0)
	await _stand(player, b)
	player.die()
	assert_eq(wilted[0], 0, "nothing wilted: there was no old pile")
	assert_eq(run.petals.pile_amount(), 135, "all of it is the new pile")
	assert_eq(_piles(w).size(), 1, "one node")


func test_a_foe_gives_its_defs_petals_once_when_it_falls() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var gained: Array[int] = []
	run.petals.gained.connect(func(amount: int) -> void: gained.append(amount))
	var foe := _actor(w.region, KNUCKLE_1, Vector3(0, 0, 3), "Foe")
	run.watch_foe(foe)
	run.watch_foe(foe)  # twice: still once
	foe.die()
	foe.die()
	assert_eq(run.petals.carried(), 10, "10 petals")
	assert_eq(gained, [10], "`gained` once with 10")


func test_a_foe_that_walks_into_the_stretch_is_watched_without_being_asked() -> void:
	# a foe put in the region by anything (the encounters of a later task, a test) gives its petals: nothing to remember to call
	var w := await _world()
	var run: StretchRun = w.run
	var foe := _actor(w.region, KNUCKLE_2, Vector3(0, 0, 3), "Late")
	await frames(1)
	foe.die()
	assert_eq(run.petals.carried(), 20, "20 petals from a foe nobody asked the run to watch")
	run.player.die()
	assert_eq(run.petals.carried(), 0, "(and his own death gives him nothing)")


func test_the_clock_is_off_by_default_and_wilts_the_pile_when_set() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	await _fall(w, Vector3(10, 0, 0), 120)
	run.petals.tick(100000)
	assert_eq(run.petals.pile_amount(), 120, "default tuning: the pile is there 100000 frames later")
	# with a clock of two seconds
	var tuned := PetalTuning.new()
	tuned.wilt_seconds = 2.0
	var data := SaveData.new_game()
	data.petals = 40
	var petals := Petals.new(data, tuned)
	var wilted: Array[int] = []
	petals.wilted.connect(func(amount: int) -> void: wilted.append(amount))
	petals.fall_at(Vector3(1, 0, 2))
	petals.tick(119)
	assert_eq(wilted.size(), 0, "not wilted at 119 frames")
	petals.tick(1)
	assert_eq(wilted, [40], "wilted at 120")
	assert_true(petals.pile_at() == null, "and gone")


func test_a_pause_does_not_count_against_the_clock() -> void:
	var tuned := PetalTuning.new()
	tuned.wilt_seconds = 2.0
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	var player := _actor(region, ABARAX, Vector3.ZERO, "Player")
	await frames(2)
	var def := (Registry.fetch(&"stretch", &"bilibara") as StretchDef).duplicate() as StretchDef
	def.petals = tuned
	var run := StretchRun.start(region, player, def, null, SaveData.new_game())
	_runs.append(run)
	var w := {region = region, player = player, run = run}
	await _fall(w, Vector3(10, 0, 0), 120)
	await frames(60)
	Game.change(Game.State.PAUSE)
	await frames(600)
	Game.change(Game.State.PLAY)
	assert_eq(run.petals.pile_amount(), 120, "a pause of 600 frames does not count: 60 play frames in, still there")
	await frames(70)
	assert_eq(run.petals.pile_amount(), 0, "wilted once 120 play frames have gone")
	assert_eq(_piles(w).size(), 0, "and the node with it")


func test_the_file_written_at_the_moment_of_death_has_the_pile_and_the_shrine() -> void:
	var store := _store()
	var w := await _world(null, store)
	var run: StretchRun = w.run
	run.rest(Registry.fetch(&"stretch", &"rose_b") as ShrineDef)
	var point := Vector3(10, 0, 0)
	await _fall(w, point, 120)
	var saved := store.read()  # the same frame
	assert_true(saved != null, "a file was written")
	if saved == null:
		return
	assert_eq(int(saved.pile.get("amount", -1)), 120, "the pile is in it")
	assert_vec_near(Vector3(saved.pile.get("x", 99.0), saved.pile.get("y", 99.0), saved.pile.get("z", 99.0)), point, 0.01, "at the point")
	assert_eq(saved.rest_shrine, &"rose_b", "and the shrine")
	assert_eq(saved.petals, 0, "carrying none")
	assert_true(saved.at.is_empty(), "no place saved (a game loaded from it stands at the shrine, not at the pile)")
	assert_true(saved.bars.is_empty(), "no bars")
	# a quit in the three seconds loses nothing twice: a new run from that file
	(w.region as Node).queue_free()
	await frames(2)
	var second := await _world(saved)
	var again: StretchRun = second.run
	assert_vec_near(second.player.global_position, _respawn_of(&"rose_b"), 0.01, "he stands at rose_b's respawn, not at the pile")
	assert_eq(again.petals.carried(), 0, "carrying none")
	var piles := _piles(second)
	assert_eq(piles.size(), 1, "the pile is drawn again")
	if piles.size() == 1:
		assert_vec_near(piles[0].global_position, point, 0.01, "at the point")
	await _stand(second.player, point)
	assert_eq(again.petals.carried(), 120, "reaching it gives the 120 back")


func test_the_pile_is_taken_back_and_the_file_says_so_that_frame() -> void:
	var store := _store()
	var w := await _world(null, store)
	var point := Vector3(10, 0, 0)
	await _fall(w, point, 120)
	await frames(185)
	assert_eq(store.read().pile.get("amount", 0), 120, "(the file has the pile)")
	await _stand(w.player, point)
	var saved := store.read()
	assert_eq(saved.petals, 120, "the file has the petals back")
	assert_true(saved.pile.is_empty(), "and no pile")


func test_dying_in_the_air_leaves_the_pile_on_the_ground() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var player: Actor = w.player
	var point := Vector3(10, 0, 0)
	await _stand(player, point)
	run.data.petals = 80
	player.place(Transform3D(Basis(), point + Vector3(1.5, 0.8, 0)))  # in the air, the physics not yet stepped
	assert_true(player.global_position.y > 0.3, "(he is in the air)")
	player.die()
	assert_true(run.petals.pile_at() != null, "a pile")
	if run.petals.pile_at() == null:
		return
	var at: Vector3 = run.petals.pile_at()
	assert_near(at.y, 0.0, 0.001, "on the ground")
	assert_true(StretchGround.stands(w.region, at), "on standing ground")
	assert_vec_near(at, point, 0.01, "at the last point he stood on the floor")


func test_a_pile_is_standing_ground_wherever_he_falls() -> void:
	# beside a kerb, the gate's board, the lane's mouth, a corner of the yard, the court's wall, the plinths, a vat: and also where he
	# was put by a test, in a wall or off the ground altogether
	var points: Array[Vector3] = [
		Vector3(-35.3, 0, -4.4), Vector3(-32.5, 0, -5.4), Vector3(-32.5, 0, -3.6), Vector3(26.0, 0, -5.2), Vector3(29.8, 0, -4.9),
		Vector3(15.2, 0, -55.2), Vector3(39.8, 0, -74.8), Vector3(-39.8, 0, 4.9), Vector3(31.8, 0, -36.9), Vector3(-36.1, 0, -4.6),
		Vector3(24.5, 0, -66.25), Vector3(-20, 0, -7), Vector3(500, 0, 500),
	]
	for point in points:
		var w := await _world()
		await _fall(w, point, 10)
		var run: StretchRun = w.run
		assert_true(run.petals.pile_at() != null, "%s: a pile" % [point])
		if run.petals.pile_at() != null:
			var at: Vector3 = run.petals.pile_at()
			assert_true(StretchGround.stands(w.region, at), "%s: the pile at %s is standing ground" % [point, at])
			if StretchGround.stands(w.region, point):
				assert_true(Vector2(at.x, at.z).distance_to(Vector2(point.x, point.z)) < 0.6, "%s: and where he fell (%s)" % [point, at])
		(w.region as Node).queue_free()
		await frames(2)


# --- the file ---

func test_petals_gained_are_saved_by_the_next_event_or_the_autosave() -> void:
	var store := _store()
	var w := await _world(null, store)
	var run: StretchRun = w.run
	run.autosave_frames = 120
	var player: Actor = w.player
	await _stand(player, Vector3(-15, 0, 0))
	await frames(70)
	assert_eq(run.save_now(), OK)
	var main_file := DIR.path_join(SaveStore.MAIN)
	var bytes := FileAccess.get_file_as_bytes(main_file)
	var stamp := FileAccess.get_modified_time(main_file)
	run.petals.gain(20)
	assert_eq(FileAccess.get_file_as_bytes(main_file), bytes, "no file change at once")
	await frames(130)
	assert_eq(store.read().petals, 20, "the file says 20 after the autosave tick")
	# nothing marked: no write
	bytes = FileAccess.get_file_as_bytes(main_file)
	stamp = FileAccess.get_modified_time(main_file)
	await frames(400)
	assert_eq(FileAccess.get_file_as_bytes(main_file), bytes, "with nothing marked the bytes are as they were")
	assert_eq(FileAccess.get_modified_time(main_file), stamp, "and so is the modification time")


func test_a_foe_that_falls_marks_the_game_for_the_autosave() -> void:
	var store := _store()
	var w := await _world(null, store)
	var run: StretchRun = w.run
	run.autosave_frames = 120
	await _stand(w.player, Vector3(-15, 0, 0))
	await frames(70)
	assert_eq(run.save_now(), OK)
	var foe := _actor(w.region, KNUCKLE_1, Vector3(0, 0, 30), "Foe")
	run.watch_foe(foe)
	foe.die()
	await frames(130)
	assert_eq(store.read().petals, 10, "the petals of the fallen foe are in the file")


func test_the_state_hash_has_the_petals_the_pile_and_the_deaths() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var start := run.state_hash()
	assert_eq(run.state_hash(), start, "(the same frame hashes the same)")
	run.petals.gain(5)
	var carried := run.state_hash()
	assert_ne(carried, start, "carried petals are in the hash")
	run.petals.fall_at(Vector3(10, 0, 0))
	var fallen := run.state_hash()
	assert_ne(fallen, carried, "a pile and a death are in the hash")
	run.petals.take_back()
	assert_ne(run.state_hash(), fallen, "the pile taken back is a different state")
