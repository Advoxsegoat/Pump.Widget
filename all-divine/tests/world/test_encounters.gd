extends TestCase
## Foes placed as encounters (world/stretch/encounter_host.gd, encounter_def.gd, placement.gd; F3 systems Task 4): six encounters of the
## existing foes stand in as the player comes near and out as he goes far, wake by nearness, a blow or an alarm, walk home past their
## leash and are healed there, come back on a rest and on a death and stay dead otherwise (and across a save: the file's `fallen`), and
## the run's idea of safe ground counts the ones that are awake. The hard cases of a reset (he dies locked on to a foe, he dies in a
## grab) are played in the real game scene with real input.
##
## The world is the real stretch region with Abarax in it (a brain that does nothing) and a StretchRun started on it; the store is null
## unless a test says (then it writes only under user://save_test/encounters, never the player's folder).

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const MAIN := "res://main/main.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const DIR := "user://save_test/encounters"
const SETTINGS_PATH := "user://settings_test.cfg"
## The foes the town may hold at this task.
const EXISTING: Array[StringName] = [&"knuckle_1", &"knuckle_2", &"knuckle_blade", &"knuckle_drummer", &"knuckle_heavy"]
const IDS: Array[StringName] = [&"street_pair", &"street_watch", &"lane_south", &"lane_north", &"rack_keeper", &"loop_straggler"]
## The table (x, z, facing), after the owner's moves of two posts.
const TABLE := {
	&"street_pair": [[&"knuckle_1", -14.0, -1.5, 270.0], [&"knuckle_1", -12.0, 2.0, 270.0]],
	&"street_watch": [[&"knuckle_2", 3.0, 2.0, 270.0], [&"knuckle_1", 5.5, -2.0, 270.0]],
	&"lane_south": [[&"knuckle_blade", 27.5, -14.0, 0.0]],
	&"lane_north": [[&"knuckle_drummer", 27.5, -47.0, 0.0]],
	&"rack_keeper": [[&"knuckle_heavy", 8.0, -22.5, 90.0]],
	&"loop_straggler": [[&"knuckle_1", -32.5, -14.8, 180.0]],
}

var _runs: Array[StretchRun] = []


func before_each() -> void:
	_clean()
	Game.reset()
	Game.change(Game.State.PLAY)
	StretchRun.start_seed(0)
	Settings.path = SETTINGS_PATH


func after_each() -> void:
	InputFeed.release()
	for run in _runs:
		if is_instance_valid(run):
			run.store = null  # leaving the tree saves: not into a folder this test is about to remove
	_runs.clear()
	_clean()
	Game.reset()
	StretchRun.start_seed(0)
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)


func _actor(region: Region, def_path: String, at: Vector3, actor_name: String) -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.name = actor_name
	var def := (load(def_path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0  # a dummy that is never beaten: these tests are not about him
	actor.def = def
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


func _host(w: Dictionary) -> EncounterHost:
	return (w.run as StretchRun).encounters


func _foes(w: Dictionary, id: StringName) -> Array[Actor]:
	return _host(w).foes(id)


func _def(id: StringName) -> EncounterDef:
	return Registry.fetch(&"stretch", id) as EncounterDef


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _shrine(id: StringName) -> ShrineDef:
	return Registry.fetch(&"stretch", id) as ShrineDef


# Every gate of the run open, at once (the loop lane is reached through the shortcut).
func _open_gates(run: StretchRun) -> void:
	for door in run.gates:
		door.open(false)


# Whether a ball of `radius` standing on the floor at `post` overlaps something on `world` other than the floor.
func _touches_wall(space: PhysicsDirectSpaceState3D, post: Vector3, radius: float) -> bool:
	var ball := SphereShape3D.new()
	ball.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.transform = Transform3D(Basis(), post + Vector3(0, radius + 0.05, 0))
	query.collision_mask = Layers.WORLD
	return not space.intersect_shape(query, 1).is_empty()


# --- the data ---

func test_the_encounter_data_loads_and_uses_only_the_existing_foes() -> void:
	var seen := {}
	for id in IDS:
		var enc := _def(id)
		assert_true(enc != null and enc.id == id, "%s loads" % id)
		if enc == null:
			continue
		assert_false(enc.placements.is_empty(), "%s has foes" % id)
		for placement in enc.placements:
			assert_true(EXISTING.has(placement.def.id), "%s is one of the foes that exist (%s)" % [id, placement.def.id])
			seen[placement.def.id] = true
		assert_eq(enc.spawn_radius, 30.0, "%s stands in at 30 m" % id)
		assert_eq(enc.despawn_radius, 44.0, "and out at 44 m")
	var run_def := Registry.fetch(&"stretch", &"bilibara") as StretchDef
	assert_eq(run_def.encounters.size(), 6, "the stretch lists the six")
	assert_true(seen.has(&"knuckle_1") and seen.has(&"knuckle_blade") and seen.has(&"knuckle_drummer") and seen.has(&"knuckle_heavy"),
			"the four kinds of foe: the Knuckle, the blade, the Drummer, the heavy")
	assert_true(_def(&"lane_north").sleeping, "the Drummer sleeps")
	assert_eq(_def(&"lane_north").wake_radius, 6.0, "and wakes at 6 m")


func test_the_posts_are_where_the_table_says() -> void:
	for id: StringName in TABLE:
		var enc := _def(id)
		var rows: Array = TABLE[id]
		assert_eq(enc.placements.size(), rows.size(), "%s has %d foes" % [id, rows.size()])
		for i in mini(enc.placements.size(), rows.size()):
			var placement := enc.placements[i]
			var row: Array = rows[i]
			assert_eq(placement.def.id, row[0], "%s_%d is a %s" % [id, i, row[0]])
			assert_vec_near(placement.at, Vector3(row[1], 0.0, row[2]), 1e-3, "%s_%d's post" % [id, i])
			assert_eq(placement.facing_deg, row[3], "%s_%d's facing" % [id, i])


func test_every_post_is_standing_ground_and_far_from_every_respawn() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	_open_gates(run)
	await frames(2)
	var reached := StretchGround.reached(w.region)
	var space := (w.region as Region).get_world_3d().direct_space_state
	var posts: Array[Array] = []
	for id in IDS:
		for placement in _def(id).placements:
			var post := placement.at
			assert_true(StretchGround.stands(w.region, post), "%s is standing ground" % post)
			assert_false(_touches_wall(space, post, 0.6), "%s has 0.6 m of clearance" % post)
			assert_true(reached.has(StretchGround.cell_of(Vector2(post.x, post.z))), "%s is reached from the spawn, the gates open" % post)
			for shrine_def in run.def.shrines:
				var gap := _flat(post, shrine_def.respawn)
				assert_true(gap >= 12.0, "%s is %.2f m from %s's respawn (12 m at least)" % [post, gap, shrine_def.id])
			posts.append([id, post])
	for i in posts.size():
		for j in range(i + 1, posts.size()):
			if posts[i][0] != posts[j][0]:
				assert_true(_flat(posts[i][1], posts[j][1]) >= 3.0, "%s and %s are 3 m apart" % [posts[i][1], posts[j][1]])


# --- standing in and out ---

func test_foes_stand_in_when_he_comes_near_and_out_when_he_goes_far() -> void:
	var enc := _def(&"street_pair")
	var centre := enc.centre()
	var saved := SaveData.new_game()
	saved.at = {x = centre.x + 31.0, y = 0.0, z = centre.z, yaw = 0.0}  # the game begins 31 m from them
	var w := await _world(saved)
	await frames(30)
	assert_eq(_foes(w, &"street_pair").size(), 0, "31 m from its centre: no foes after 30 frames")
	await _stand(w.player, Vector3(centre.x + 29.0, 0, centre.z))
	await frames(15)
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "29 m from it: two foes within 15 frames")
	for i in mini(foes.size(), 2):
		var placement := enc.placements[i]
		assert_true(_flat(foes[i].global_position, placement.at) < 0.05 + 0.3, "foe %d is at its post" % i)
		var facing := foes[i].facing()
		var want := Vector3(sin(placement.yaw()), 0, cos(placement.yaw()))
		assert_true(rad_to_deg(facing.angle_to(want)) < 1.0 + 3.0, "and faces as the post says (%.1f degrees off)" % rad_to_deg(facing.angle_to(want)))
	await _stand(w.player, Vector3(27.5, 0, -30))  # 50 m off, up the lane
	await frames(16)
	assert_eq(_foes(w, &"street_pair").size(), 0, "46 m or more off, unengaged: none within 15 frames")
	assert_false(_host(w).stands(&"street_pair"), "and it says it does not stand")


func test_a_foe_is_named_for_its_post_takes_the_serial_and_is_watched() -> void:
	var w := await _world()
	await _stand(w.player, Vector3(-36.1, 0, -3.1))
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "the street pair stands (23 m from the first shrine)")
	if foes.size() != 2:
		return
	assert_eq(String(foes[0].name), "street_pair_0", "named for its post")
	assert_eq(String(foes[1].name), "street_pair_1", "and the second")
	assert_eq(foes[0].spawn_count, 0, "the first takes serial 0")
	assert_eq(foes[1].spawn_count, 1, "the second 1")
	assert_true(foes[0].brain is EnemyBrain, "it thinks with its def's brain")
	var run: StretchRun = w.run
	var carried := run.petals.carried()
	foes[0].die()
	assert_eq(run.petals.carried(), carried + 10, "killing a Knuckle I pays its 10 petals")


func test_the_killed_stay_dead_while_he_walks_about() -> void:
	var w := await _world()
	await _stand(w.player, Vector3(-30, 0, 0))
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "(they stand)")
	foes[0].die()
	assert_eq(Array(_host(w).killed(&"street_pair")), [0], "street_pair_0 is down")
	await _stand(w.player, Vector3(27.5, 0, -30))
	await frames(16)
	assert_false(_host(w).stands(&"street_pair"), "he went beyond 44 m: the encounter is taken away")
	await _stand(w.player, Vector3(-30, 0, 0))
	await frames(16)
	var back := _foes(w, &"street_pair")
	assert_eq(back.size(), 1, "he comes back: one foe")
	if back.size() == 1:
		assert_eq(String(back[0].name), "street_pair_1", "index 1")
		assert_true(_flat(back[0].global_position, _def(&"street_pair").placements[1].at) < 0.4, "at its post")
	assert_eq(Array(_host(w).killed(&"street_pair")), [0], "and the dead are still dead")


func test_rest_and_death_bring_every_foe_back_healed() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var shrine := _shrine(&"rose_a")
	await _stand(w.player, shrine.respawn)
	for round in 2:
		var foes := _foes(w, &"street_pair")
		assert_eq(foes.size(), 2, "(round %d: they stand)" % round)
		if foes.size() != 2:
			return
		foes[0].die()
		foes[1].stats.hp = 5.0
		if round == 0:
			run.rest(shrine)
		else:
			w.player.die()
			await frames(190)
		await frames(16)
		var back := _foes(w, &"street_pair")
		assert_eq(back.size(), 2, "after %s two foes stand again" % ("a rest" if round == 0 else "a death and the three seconds"))
		for i in mini(back.size(), 2):
			assert_eq(back[i].stats.hp, back[i].stats.max_hp, "foe %d is at full HP" % i)
			assert_true(_flat(back[i].global_position, _def(&"street_pair").placements[i].at) < 0.4, "at its post")
		assert_eq(_host(w).killed(&"street_pair").size(), 0, "and nobody is down")


func test_resting_with_two_foes_on_him_takes_them_away_at_once_and_they_stand_at_their_posts_again() -> void:
	# What the owner asked to see: he rests in the middle of a fight. The press is not refused; the bars are full, the foes that were on
	# him are gone that frame and stand again, idle and whole, at their posts (22 m off and out of the picture) within a streaming tick.
	var w := await _world()
	var run: StretchRun = w.run
	var shrine := _shrine(&"rose_a")
	await _stand(w.player, shrine.respawn)
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "(they stand)")
	if foes.size() != 2:
		return
	for i in 2:
		foes[i].place(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), shrine.respawn + Vector3(2.0, 0, 0.8 * (i * 2 - 1))))
		(foes[i].brain as EnemyBrain).engage_now()
	await frames(20)
	assert_eq((foes[0].brain as EnemyBrain).mode != EnemyBrain.Mode.IDLE, true, "(the foes are on him)")
	w.player.stats.hp = 10.0
	run.rest(shrine)
	assert_eq(w.player.stats.hp, w.player.stats.max_hp, "the rest is not refused: bars full")
	assert_eq(_foes(w, &"street_pair").size(), 0, "the foes that were on him are gone that frame")
	await frames(16)
	var back := _foes(w, &"street_pair")
	assert_eq(back.size(), 2, "and stand again within a streaming tick")
	for i in mini(back.size(), 2):
		assert_true(_flat(back[i].global_position, _def(&"street_pair").placements[i].at) < 0.4, "at their posts")
		assert_eq((back[i].brain as EnemyBrain).mode, EnemyBrain.Mode.IDLE, "idle")


# --- waking ---

func test_a_sleeper_wakes_by_nearness_by_a_blow_or_by_the_alarm() -> void:
	var w := await _world()
	var post := _def(&"lane_north").placements[0].at
	await _stand(w.player, post + Vector3(0, 0, 6.5))
	await frames(120)
	var drummer := _foes(w, &"lane_north")
	assert_eq(drummer.size(), 1, "(the Drummer stands)")
	if drummer.size() != 1:
		return
	var brain := drummer[0].brain as EnemyBrain
	assert_true(brain.asleep and brain.mode == EnemyBrain.Mode.IDLE, "at 6.5 m for 120 frames nothing: he sleeps")
	await _stand(w.player, post + Vector3(0, 0, 5.9))
	await frames(10)
	assert_false(brain.asleep, "at 5.9 m he wakes")
	assert_true(brain.mode == EnemyBrain.Mode.ENGAGED or brain.mode == EnemyBrain.Mode.ATTACKING, "and engages")
	# A blow from further off.
	var w2 := await _world()
	await _stand(w2.player, post + Vector3(0, 0, 10.0))
	await frames(30)
	var second := _foes(w2, &"lane_north")
	assert_eq(second.size(), 1, "(a second Drummer stands)")
	if second.size() == 1:
		var sleeper := second[0].brain as EnemyBrain
		assert_true(sleeper.asleep, "at 10 m he sleeps")
		Blows.post(w2.player, second[0])
		await frames(5)
		assert_false(sleeper.asleep, "a blow wakes him")
		assert_true(sleeper.mode == EnemyBrain.Mode.ENGAGED or sleeper.mode == EnemyBrain.Mode.ATTACKING, "into the fight")


func test_the_alarm_engages_the_rest_of_the_encounter() -> void:
	var w := await _world()
	var enc := _def(&"street_pair")
	# Behind them (they face west): neither sees him, and a walk makes no noise.
	await _stand(w.player, Vector3(-8, 0, 0))
	await frames(40)
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "(they stand)")
	if foes.size() != 2:
		return
	var first := foes[0].brain as EnemyBrain
	var second := foes[1].brain as EnemyBrain
	assert_eq(first.mode, EnemyBrain.Mode.IDLE, "with his back to them, the first has not noticed him")
	assert_eq(second.mode, EnemyBrain.Mode.IDLE, "nor the second")
	first.engage_now()
	await frames(5)
	assert_true(enc.alarm, "(the street pair has the alarm)")
	assert_true(second.mode != EnemyBrain.Mode.IDLE, "one member engaging engages the other")


func test_a_foe_that_leaves_its_leash_walks_home_and_is_healed() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	await _stand(w.player, Vector3(-26, 0, -1.5))
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "(they stand)")
	if foes.size() != 2:
		return
	var foe := foes[0]
	var brain := foe.brain as EnemyBrain
	var other := foes[1].brain as EnemyBrain
	brain.leash = 6.0  # (the data's 24 m is a stretch of road; the walk is the same)
	other.leash = 6.0
	foe.stats.hp = 3.0
	var petals_before := run.petals.carried()
	var left := false
	var arrived := [0]
	brain.arrived_home.connect(func() -> void: arrived[0] += 1)
	for i in 600:
		await frames(1)
		if brain.going_home():
			left = true
			break
	assert_true(left, "lured west past its leash, it gives up and goes home")
	for i in 60 * 10:
		if arrived[0] > 0:
			break
		await frames(1)
	assert_eq(arrived[0], 1, "it arrives")
	assert_eq(foe.stats.hp, foe.stats.max_hp, "and is healed")
	assert_true(_flat(foe.global_position, _def(&"street_pair").placements[0].at) <= 0.65, "within 0.6 m of its post")
	assert_eq(run.petals.carried(), petals_before, "and the healing paid nothing")
	assert_false(foe.dead, "(it did not die)")


# --- seeds and the hash ---

func _walk_and_hash(seed_number: int) -> Dictionary:
	StretchRun.start_seed(seed_number)
	var w := await _world()
	await _stand(w.player, Vector3(-24, 0, -1.5))
	await frames(300)
	var spawn_counts: Array[int] = []
	for foe in _foes(w, &"street_pair"):
		spawn_counts.append(foe.spawn_count)
	var result := {hash = (w.run as StretchRun).state_hash(), counts = spawn_counts}
	(_runs.pop_back() as StretchRun).store = null
	(w.region as Region).free()
	await frames(2)
	return result


func test_the_dice_are_seeded_and_a_respawn_rolls_new_ones() -> void:
	var a := await _walk_and_hash(1)
	var b := await _walk_and_hash(1)
	var c := await _walk_and_hash(2)
	assert_eq(a.hash, b.hash, "two runs with seed 1 and the same walk hash alike after 300 frames")
	assert_ne(a.hash, c.hash, "a run with seed 2 differs")
	assert_eq(a.counts, [1000, 1001], "the street pair of seed 1 has serials 1000 and 1001")
	assert_eq(c.counts, [2000, 2001], "and seed 2's 2000 and 2001")
	# A second spawn of the same post has another serial.
	var w := await _world()
	await _stand(w.player, Vector3(-30, 0, 0))
	var first := _foes(w, &"street_pair")[0].spawn_count
	await _stand(w.player, Vector3(27.5, 0, -30))
	await frames(16)
	await _stand(w.player, Vector3(-30, 0, 0))
	await frames(16)
	var again := _foes(w, &"street_pair")
	assert_eq(again.size(), 2, "(they stand again)")
	if again.size() == 2:
		assert_ne(again[0].spawn_count, first, "the same post rolls other dice the second time")


func test_the_hash_includes_the_encounters() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	await _stand(w.player, Vector3(-30, 0, 0))
	var standing := _host(w).hash_part()
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "(they stand)")
	if foes.size() != 2:
		return
	foes[0].die()
	var fallen := _host(w).hash_part()
	assert_ne(fallen, standing, "a killed foe is in the encounters' hash")
	await _stand(w.player, Vector3(27.5, 0, -30))
	await frames(16)
	assert_ne(_host(w).hash_part(), fallen, "a despawned encounter is too")
	var a := run.state_hash()
	run.encounters._foes.erase(&"lane_north")  # (the host's own memory: what the hash reads)
	assert_ne(run.state_hash(), a, "and the run's hash reads them")


# --- the saved game's fallen ---

func test_a_foe_killed_and_the_game_left_and_loaded_is_still_down() -> void:
	var store := SaveStore.new(DIR)
	var w := await _world(null, store)
	var run: StretchRun = w.run
	await _stand(w.player, Vector3(-30, 0, 0))
	var foes := _foes(w, &"street_pair")
	assert_eq(foes.size(), 2, "(they stand)")
	if foes.size() != 2:
		return
	foes[1].die()
	foes[0].die()
	assert_eq(run.data.fallen.size(), 2, "the save's data holds both")
	assert_eq(run.save_now(), OK, "saved")
	var read := store.read()
	assert_eq(read.fallen, [&"street_pair_0", &"street_pair_1"] as Array[StringName], "the file has them, sorted")
	# One more, then the game is left (the run leaving the tree saves).
	(w.region as Region).free()
	await frames(2)
	var loaded := SaveStore.new(DIR).read()
	assert_eq(loaded.fallen.size(), 2, "the file read back after leaving still has both")
	var again := await _world(loaded, null)
	await _stand(again.player, Vector3(-30, 0, 0))
	await frames(16)
	assert_eq(_foes(again, &"street_pair").size(), 0, "loaded, both are still down: neither stands")
	assert_eq(Array(_host(again).killed(&"street_pair")), [0, 1], "and the host knows it")
	# A rest brings them back, and the file says so.
	again.run.store = store
	again.run.rest(_shrine(&"rose_a"))
	await frames(16)
	assert_eq(store.read().fallen.size(), 0, "after a rest the file has nobody down")
	assert_eq(_foes(again, &"street_pair").size(), 2, "and they stand")


func test_a_death_and_a_new_game_empty_the_fallen() -> void:
	var store := SaveStore.new(DIR)
	var w := await _world(null, store)
	var run: StretchRun = w.run
	await _stand(w.player, Vector3(-30, 0, 0))
	_foes(w, &"street_pair")[0].die()
	assert_eq(run.data.fallen.size(), 1, "one is down")
	w.player.die()
	assert_eq(store.read().fallen.size(), 0, "the file written at the moment of death has nobody down")
	await frames(190)
	assert_eq(run.data.fallen.size(), 0, "and after the stand-up too")
	assert_eq(SaveData.new_game().fallen.size(), 0, "a new game has none")
	# A foe killed after the stand-up is down again.
	await _stand(w.player, Vector3(-30, 0, 0))
	await frames(16)
	_foes(w, &"street_pair")[1].die()
	assert_eq(run.data.fallen, [&"street_pair_1"] as Array[StringName], "down again")


func test_a_foe_that_stands_again_and_falls_again_pays_again() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var shrine := _shrine(&"rose_a")
	await _stand(w.player, shrine.respawn)
	for foe in _foes(w, &"street_pair"):
		foe.die()
	assert_eq(run.petals.carried(), 20, "one clearing of the street pair pays 20")
	run.rest(shrine)
	await frames(16)
	var again := _foes(w, &"street_pair")
	assert_eq(again.size(), 2, "they stand again")
	for foe in again:
		foe.die()
	assert_eq(run.petals.carried(), 40, "and pay again: twice one clearing")
	# The same Actor stood up and felled again pays again too.
	var same := _foes(w, &"loop_straggler")[0]
	same.die()
	var once := run.petals.carried()
	same.revive(Transform3D(Basis(), same.global_position))
	same.die()
	assert_eq(run.petals.carried(), once + 10, "a revived foe killed again pays again")


# --- safe ground ---

func test_safe_ground_counts_only_foes_that_are_awake() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var post := _def(&"lane_north").placements[0].at
	await _stand(w.player, post + Vector3(0, 0, 8.0))
	await frames(130)
	assert_true(_foes(w, &"lane_north").size() == 1 and (_foes(w, &"lane_north")[0].brain as EnemyBrain).asleep, "(the Drummer sleeps)")
	assert_true(run.is_safe(), "8 m from the sleeping Drummer is safe ground")
	assert_true(not run.data.at.is_empty() and absf(float(run.data.at.z) - (post.z + 8.0)) < 0.3, "and the saved position moves there")
	# 8 m behind an awake foe that has not noticed him.
	var lane := _def(&"lane_south").placements[0].at
	await _stand(w.player, lane + Vector3(0, 0, -8.0))
	await frames(20)
	var blade := _foes(w, &"lane_south")
	assert_eq(blade.size(), 1, "(the blade Knuckle stands)")
	if blade.size() == 1:
		assert_eq((blade[0].brain as EnemyBrain).asleep, false, "(awake)")
	assert_false(run.is_safe(), "8 m from an awake idle foe is not")


# --- the reset, played in the real game ---

func _main() -> Main:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.save_dir = DIR
	main.stretch_start = "new"
	return track(main) as Main


# A man at the street pair's first foe, with a lot of HP and the foes' attention: the game scene with real input.
func _fight_ready(main: Main) -> Array[Actor]:
	await frames(2)
	main.player.stats.max_hp = 100000.0
	main.player.stats.hp = 100000.0
	main.player.place(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(-19.0, 0, -1.5)))  # facing east, toward them
	main.camera_rig.snap_now()
	await frames(150)
	return main.stretch.encounters.foes(&"street_pair")


func _wait_until(condition: Callable, limit: int) -> bool:
	for i in limit:
		if condition.call():
			return true
		await frames(1)
	return condition.call()


func test_dying_locked_on_leaves_no_lock_no_lean_and_no_freed_foe() -> void:
	var main := _main()
	var foes := await _fight_ready(main)
	assert_eq(foes.size(), 2, "(the street pair stands and has come)")
	if foes.size() != 2:
		return
	InputFeed.apply({"pressed": PackedStringArray([&"lock_on"])})
	await frames(2)
	InputFeed.release()
	await frames(2)
	var lock := (main.player.brain as PlayerBrain).lock
	assert_true(lock.target != null, "he locked on")
	assert_true(main.camera_rig.lock_target != null, "and the camera leans toward it")
	assert_true(main.hud.foe_bars().any(func(bar: Dictionary) -> bool: return bar.actor == lock.target), "the Hud shows the locked foe's bars with no arena")
	main.player.die()
	await frames(190)
	assert_false(main.player.dead, "he stood up")
	assert_true(lock.target == null, "with no lock")
	assert_true(main.camera_rig.lock_target == null, "no lean")
	assert_true(main.player.paired_with == null, "no pair")
	var spawn := main.stretch.spawn_point(main.stretch.rest_shrine()).origin
	assert_true(_flat(main.player.global_position, spawn) < 0.5, "at the shrine")
	var before := main.player.global_position
	var got_up := await _wait_until(func() -> bool: return main.player.runner.current == null and not main.player.runner.busy(), 120)
	assert_true(got_up, "his getup ends")
	InputFeed.apply({"move": Vector2(1, 0)})
	await frames(3)
	assert_true(_flat(main.player.global_position, before) > 0.01, "and he moves on the frame his getup is over")
	InputFeed.release()
	await frames(300)  # no freed foe is referenced anywhere: an error line here fails the test
	assert_true(true, "300 frames on, nothing was said")


func test_dying_in_a_grab_leaves_no_pair_and_a_free_man() -> void:
	var main := _main()
	var foes := await _fight_ready(main)
	assert_eq(foes.size(), 2, "(the street pair stands and has come)")
	if foes.size() != 2:
		return
	var grabber := foes[0]
	# The grab begins as the arena's pair tests begin one: the foe leads, he follows (a foe's own grab is a wind-up he can slip).
	grabber.set_brain(Brain.new())
	foes[1].set_brain(Brain.new())
	await _wait_until(func() -> bool: return not grabber.runner.busy() and not foes[1].runner.busy(), 200)
	main.player.place(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), grabber.global_position + Vector3(-1.2, 0, 0)))
	await frames(2)
	assert_true(grabber.start_paired(main.player, grabber.def.grab_pair), "the grab starts")
	await frames(20)
	assert_true(main.player.paired_with == grabber, "he is held")
	main.player.die()
	await frames(190)
	assert_false(main.player.dead, "he stood up")
	assert_true(main.player.paired_with == null, "no pair")
	assert_true((main.player.brain as PlayerBrain).lock.target == null and main.camera_rig.lock_target == null, "no lock, no lean")
	assert_true(is_instance_valid(grabber) == false or not grabber.is_inside_tree(), "the grabber is out of the game")
	await _wait_until(func() -> bool: return not main.player.runner.busy(), 120)
	var before := main.player.global_position
	InputFeed.apply({"move": Vector2(1, 0)})
	await frames(3)
	assert_true(_flat(main.player.global_position, before) > 0.01, "free to move on the frame his getup ends")
	InputFeed.release()
	await frames(300)
	assert_true(true, "300 frames on, nothing was said")
