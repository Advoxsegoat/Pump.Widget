extends TestCase
## The stretch's gates (world/stretch/gate_def.gd, gate_door.gd, latch.gd): two low slate boards that a flag takes away. The street's west
## gate (the layout's own `Gate` node) is lifted by a latch from the loop lane's side only; the toll board across the lane's mouth is built by
## the run and waits for the mini-boss's flag. The real town has the shortcut alone (the toll board is not placed until the owner says where
## the mini-boss stands: its data is loaded and tested here, and a test that needs the board builds a run whose def has it added). An open gate stays open through a rest, a death and a load, and nothing about opening one
## is sticky: one press, the bar stops blocking on that very frame, and he keeps control while the board sinks.
##
## The world is the real stretch region with Abarax in it and a StretchRun started on it, as in test_stretch_run.

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const DIR := "user://save_test/gates"
const SHOVE := 30.0
const DT := 1.0 / 60

var _runs: Array[StretchRun] = []


func before_each() -> void:
	_clean()
	Game.reset()
	Game.change(Game.State.PLAY)


func after_each() -> void:
	InputFeed.release()
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


func _actor(region: Region, at: Vector3, actor_name: String) -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.name = actor_name
	actor.def = load(ABARAX) as ActorDef
	actor.position = at
	actor.set_brain(Brain.new())
	region.add_child(actor)
	return actor


func _bare() -> Dictionary:
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	var player := _actor(region, Vector3.ZERO, "Player")
	await frames(2)
	return {region = region, player = player}


# The real town's def, or, `with_toll`, a copy of it with the toll board added to its gates (the town does not place it yet).
func _def(with_toll := false) -> StretchDef:
	var def := Registry.fetch(&"stretch", &"bilibara") as StretchDef
	if not with_toll:
		return def
	var copy := def.duplicate() as StretchDef
	var gates: Array[GateDef] = def.gates.duplicate()
	gates.append(_gate(&"gate_toll"))
	copy.gates = gates
	return copy


func _start(bare: Dictionary, data: SaveData = null, store: SaveStore = null, with_toll := false) -> StretchRun:
	var def := _def(with_toll)
	var run := StretchRun.start(bare.region, bare.player, def, store, data if data != null else SaveData.new_game())
	_runs.append(run)
	return run


func _world(data: SaveData = null, store: SaveStore = null, with_toll := false) -> Dictionary:
	var bare := await _bare()
	bare["run"] = _start(bare, data, store, with_toll)
	await frames(2)
	return bare


func _at(player: Actor, at: Vector3, yaw_deg := 0.0) -> void:
	player.place(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at))


func _press(action: StringName) -> void:
	InputFeed.apply({"pressed": PackedStringArray([action])})
	await frames(1)
	InputFeed.release()
	await frames(2)


func _gate(id: StringName) -> GateDef:
	return Registry.fetch(&"stretch", id) as GateDef


func _door(run: StretchRun, id: StringName) -> GateDoor:
	for door in run.gates:
		if door.def.id == id:
			return door
	return null


func _marker(region: Region, marker_name: String) -> Vector3:
	return (region.find_child(marker_name, true, false) as Marker3D).global_position


func _data_with(flags: Array[StringName]) -> SaveData:
	var data := SaveData.new_game()
	for flag in flags:
		data.memory.set_flag(flag)
	return data


# --- the data ---

func test_the_gate_data_loads() -> void:
	var shortcut := _gate(&"gate_shortcut")
	var toll := _gate(&"gate_toll")
	assert_true(shortcut != null and toll != null, "both gates are in the Registry")
	if shortcut == null or toll == null:
		return
	assert_eq(shortcut.opens_on, &"shortcut_open", "the shortcut opens on shortcut_open")
	assert_eq(toll.opens_on, &"collector_down", "the toll gate opens on collector_down")
	assert_eq(Array(shortcut.nodes), ["Gate"], "the shortcut lowers the layout's Gate")
	assert_eq(shortcut.board, Rect2(), "and builds no board")
	assert_eq(toll.board, Rect2(25, -5.5, 5, 1.0), "the toll board is across the lane's mouth")
	assert_eq(shortcut.drop, 1.3, "a board sinks 1.3 m")
	assert_eq(shortcut.latch_centre, Vector3(-32.5, 0, -5), "the latch is at the gate")
	assert_eq(shortcut.latch_radius, 3.0, "within 3 m")
	assert_eq(shortcut.open_side, Vector2(0, -1), "it lifts from the loop lane's side (north)")
	assert_eq(shortcut.latch_prompt, "Lift the bar")
	assert_eq(shortcut.barred_prompt, "Barred from the other side")
	assert_eq(toll.latch_radius, 0.0, "nothing lifts the toll gate but its flag")
	assert_eq(toll.drop, 1.3, "the toll board sinks 1.3 m too")
	assert_eq(toll.latch_prompt, "Lift the bar")


# The toll board is not placed in the town yet: the stretch's own list is the shortcut alone, and the lane's mouth is open in a new game.
func test_the_real_towns_gates_are_the_shortcut_alone_and_the_lanes_mouth_is_walkable_in_a_new_game() -> void:
	var stretch := Registry.fetch(&"stretch", &"bilibara") as StretchDef
	assert_eq(stretch.gates.map(func(g: GateDef) -> StringName: return g.id), [&"gate_shortcut"], "the town's gates are the shortcut alone")
	var w := await _world()
	var run: StretchRun = w.run
	var region: Region = w.region
	assert_eq(run.gates.size(), 1, "the run makes one door")
	assert_true(region.get_node_or_null("gate_toll") == null, "and builds no toll board")
	for x: float in [25.6, 27.5, 29.4]:
		assert_true(StretchGround.stands(region, Vector3(x, 0.0, -5.0)), "the lane's mouth at x %.1f is standing ground in a new game" % x)
	var reached: Dictionary = StretchGround.reached(region)
	for place: Vector2 in [Vector2(27.5, -30.0), Vector2(27.5, -65.0), Vector2(-32.5, -22.5), Vector2(-32.5, -6.5)]:
		assert_true(reached.has(StretchGround.cell_of(place)), "%s is walked to from the spawn with only the shortcut's gate shut" % place)
	assert_false(reached.has(StretchGround.cell_of(Vector2(-32.5, -5.0))), "(the shut shortcut's gateway is not)")
	# and a body walks in through the mouth in a new game
	var player: Actor = w.player
	_at(player, Vector3(27.5, 0.0, -2.0))
	await frames(2)
	player.set_brain(ScriptBrain.new([{frames = 90, move = Vector2(0, -1)}]))
	await frames(100)
	assert_true(player.global_position.z < -8.0, "he walks up the lane from the street (z %.2f)" % player.global_position.z)


# --- shut and open at the start ---

func test_a_gate_whose_flag_is_set_loads_open_and_one_without_loads_shut() -> void:
	var w := await _world(_data_with([&"shortcut_open"]))
	var region: Region = w.region
	var run: StretchRun = w.run
	var shortcut_board := region.get_node("Gate") as StaticBody3D
	assert_eq(shortcut_board.collision_layer, 0, "the shortcut's flag is set: its board has no collision at the first frame")
	assert_false(shortcut_board.visible, "and is not shown")
	assert_true(_door(run, &"gate_shortcut").is_open(), "the door says open")
	assert_true(run.gates.size() == 1, "(the town has the shortcut alone)")
	var plain := await _world()
	var fresh_run: StretchRun = plain.run
	var fresh_region: Region = plain.region
	assert_eq((fresh_region.get_node("Gate") as StaticBody3D).collision_layer, Layers.WORLD | Layers.IK_SURFACE, "no flags: the shortcut is shut")
	assert_false(_door(fresh_run, &"gate_shortcut").is_open(), "the shortcut door says shut")


func test_a_built_toll_board_is_shut_without_its_flag_and_open_with_it() -> void:
	var w := await _world(_data_with([&"collector_down"]), null, true)
	var open_board := (w.region as Region).get_node_or_null("gate_toll") as StaticBody3D
	assert_true(open_board != null and open_board.collision_layer == 0 and not open_board.visible, "with collector_down set the toll board loads open: no collision, hidden")
	assert_true(_door(w.run, &"gate_toll").is_open(), "the door says open")
	(w.region as Node).queue_free()
	await frames(2)
	w = await _world(null, null, true)
	var region: Region = w.region
	var run: StretchRun = w.run
	var toll_board := region.get_node_or_null("gate_toll") as StaticBody3D
	assert_true(toll_board != null, "the toll board is built by the run, named for its gate")
	if toll_board != null:
		assert_eq(toll_board.collision_layer, Layers.WORLD | Layers.IK_SURFACE, "the toll gate has no flag: its board is solid (world and feet)")
		assert_true(toll_board.visible, "and shown")
		var shape := toll_board.get_node("Shape") as CollisionShape3D
		assert_near(shape.global_position.y + (shape.shape as BoxShape3D).size.y / 2.0, 0.6, 0.001, "its top is at 0.6 m")
		assert_vec_near((shape.shape as BoxShape3D).size, Vector3(5, 0.6, 1.0), 0.001, "5 m by 0.6 by 1 m")
		assert_near(shape.global_position.x, 27.5, 0.001, "centred across the lane")
		assert_near(shape.global_position.z, -5.0, 0.001, "on the lane's mouth")
	assert_false(_door(run, &"gate_toll").is_open(), "the toll door says shut")
	assert_eq((region.get_node("Gate") as StaticBody3D).collision_layer, Layers.WORLD | Layers.IK_SURFACE, "and the shortcut too")


func test_setting_the_flag_opens_a_gate_over_forty_five_frames_without_a_pop() -> void:
	var w := await _world()
	var region: Region = w.region
	var run: StretchRun = w.run
	var board := region.get_node("Gate") as StaticBody3D
	var start_y := board.position.y
	var changed := [0]
	run.world_changed.connect(func(_f: StringName) -> void: changed[0] += 1)
	run.set_flag(&"shortcut_open")
	assert_eq(board.collision_layer, 0, "no collision on the very frame the flag is set")
	assert_true(board.visible, "still shown: it sinks")
	var door := _door(run, &"gate_shortcut")
	assert_false(door.is_open(), "not open until it has sunk")
	var last := board.position.y
	var worst := 0.0
	var every_frame := true
	for i in 45:
		await frames(1)
		var fall := last - board.position.y
		worst = maxf(worst, fall)
		if fall <= 0.0 and board.visible:
			every_frame = false
		last = board.position.y
	assert_true(worst <= 0.04, "no frame drops it more than 0.04 m (the worst: %.4f)" % worst)
	assert_true(every_frame, "it falls on every frame until it is down")
	await frames(2)
	assert_near(board.position.y, start_y - 1.3, 0.001, "it ends 1.3 m down")
	assert_false(board.visible, "and is hidden")
	assert_true(door.is_open(), "is_open is true")
	assert_eq(changed[0], 1, "the world changed once")


func test_an_open_gate_is_open_at_once_when_it_is_opened_without_animation() -> void:
	var w := await _world()
	var run: StretchRun = w.run
	var board := (w.region as Region).get_node("Gate") as StaticBody3D
	_door(run, &"gate_shortcut").open(false)
	assert_eq(board.collision_layer, 0, "no collision")
	assert_false(board.visible, "hidden")
	assert_true(_door(run, &"gate_shortcut").is_open(), "open now")


func test_lifting_the_bar_gives_him_his_hands_the_same_frame_and_the_sinking_board_does_not_hold_him() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	_at(player, _marker(w.region, "GateFar"), 0.0)
	await frames(2)
	assert_true(run.interactor.current is Latch, "the latch is in reach")
	InputFeed.apply({"pressed": PackedStringArray([&"interact"])})
	await frames(2)
	InputFeed.release()
	assert_true(run.flag(&"shortcut_open"), "one press lifted the bar within two frames")
	assert_eq(player.frozen, 0, "he is not frozen")
	assert_true(player.runner.current == null, "and in no move (no kneeling, no pause)")
	assert_false(player.dead or player.paired_with != null, "nothing took him")
	# the very next frames he can walk into the gateway while the board is still sinking: the board's north face is at z -5.5, and a shut
	# board would hold his centre at z -5.85
	var board := (w.region as Region).get_node("Gate") as StaticBody3D
	player.set_brain(RouteBrain.new([_marker(w.region, "GateNear")] as Array[Vector3]))
	await frames(30)
	assert_true(board.visible, "the board is still on its way down")
	assert_true(player.global_position.z > -5.5, "he is already past its north face (z %.2f)" % player.global_position.z)


# --- the latch ---

func test_the_latch_lifts_only_from_the_open_side() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	var changes: Array[StringName] = []
	run.world_changed.connect(func(f: StringName) -> void: changes.append(f))
	# the street side first: the bar says why and a press sets nothing
	_at(player, _marker(w.region, "GateNear"), 180.0)
	await frames(2)
	assert_true(run.interactor.current is Latch, "at GateNear the latch is the one in reach")
	assert_eq((run.interactor.current as Latch).prompt(player), "Barred from the other side", "it says it is barred")
	await _press(&"interact")
	assert_false(run.flag(&"shortcut_open"), "a press on the street side sets nothing")
	assert_eq(changes, [] as Array[StringName], "and nothing changed")
	# the loop lane's side
	_at(player, _marker(w.region, "GateFar"), 0.0)
	await frames(2)
	assert_true(run.interactor.current is Latch, "at GateFar the latch is in reach")
	assert_eq((run.interactor.current as Latch).prompt(player), "Lift the bar", "and offers the lift")
	await _press(&"interact")
	assert_true(run.flag(&"shortcut_open"), "one press sets shortcut_open")
	assert_eq(changes, [&"shortcut_open"] as Array[StringName], "world_changed once")
	await _press(&"interact")
	assert_eq(changes.size(), 1, "a second press changes nothing more")
	# an open gate offers nothing
	await frames(50)
	assert_eq((run.interactor.current as Latch).prompt(player) if run.interactor.current is Latch else "", "", "an open gate has no line")


func test_the_latch_cue_plays_when_the_bar_is_lifted() -> void:
	var cue := Registry.fetch(&"sounds", &"gate_unlatch") as SoundCue
	assert_true(cue != null and not cue.streams.is_empty(), "the cue gate_unlatch is data with a stream")


# --- the chooser: the shrine's rest and the latch stand close together ---

func _line_at(w: Dictionary, at: Vector3) -> String:
	_at(w.player, at, 90.0)
	await frames(1)
	return (w.run as StretchRun).interactor.prompt_line()


func test_at_the_first_shrines_respawn_the_prompt_is_the_shrines_and_a_press_rests() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	var respawn := (Registry.fetch(&"stretch", &"rose_a") as ShrineDef).respawn
	_at(player, respawn, 180.0)
	await frames(2)
	assert_true(run.interactor.current is Shrine, "the shrine is what is offered at its respawn")
	assert_eq(run.interactor.prompt_line(), "%s  Rest" % ControlsList.shown(&"interact", false), "the line is Rest")
	var rested: Array[StringName] = []
	run.rested.connect(func(id: StringName) -> void: rested.append(id))
	await _press(&"interact")
	assert_eq(rested, [&"rose_a"] as Array[StringName], "a press rests")
	assert_false(run.flag(&"shortcut_open"), "and lifts nothing")


func test_at_gatenear_the_prompt_is_the_latchs() -> void:
	var w := await _world()
	_at(w.player, _marker(w.region, "GateNear"), 180.0)
	await frames(2)
	assert_true((w.run as StretchRun).interactor.current is Latch, "the latch")
	assert_true((w.run as StretchRun).interactor.prompt_line().ends_with("Barred from the other side"), "its barred line")


# A place where the shrine is in reach and the latch is the nearer of the two (a sliver of paving south of the stone's east end): the
# barred latch must not take the rest away.
func test_the_barred_latch_never_takes_the_rest_away() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	var shrine := Registry.fetch(&"stretch", &"rose_a") as ShrineDef
	var latch := _gate(&"gate_shortcut")
	var near_both := 0
	var taken := PackedStringArray()
	var x := -34.4
	while x <= -34.0:
		var at := Vector3(x, 0.0, -4.14)
		var rest_in_reach := Vector2(at.x - shrine.plinth.x, at.z - shrine.plinth.z).length() <= shrine.radius
		var latch_nearer := Vector2(at.x - latch.latch_centre.x, at.z - latch.latch_centre.z).length() < Vector2(at.x - shrine.plinth.x, at.z - shrine.plinth.z).length()
		if rest_in_reach:
			assert_true(StretchGround.stands(w.region, at), "(%s is standing ground)" % at)
			_at(player, at, 90.0)
			await frames(1)
			if latch_nearer:
				near_both += 1
			if not run.interactor.current is Shrine:
				taken.append("x %.2f: %s" % [x, run.interactor.prompt_line()])
		x += 0.005
	assert_true(near_both > 0, "(the sweep does cross places where both are in reach and the latch is nearer: %d)" % near_both)
	assert_eq(taken, PackedStringArray(), "wherever the rest is in reach, it is what is offered")


# Walking from the respawn east to GateNear: the line changes from Rest to the barred line once and never goes back.
func test_walking_from_the_respawn_to_gatenear_the_prompt_changes_once_and_never_flips_back() -> void:
	var w := await _world()
	var player: Actor = w.player
	var run: StretchRun = w.run
	var respawn := (Registry.fetch(&"stretch", &"rose_a") as ShrineDef).respawn
	var waypoints: Array[Vector3] = [_marker(w.region, "GateNear")]
	player.set_brain(RouteBrain.new(waypoints))
	var seen: Array[String] = []
	var blank := 0
	var longest_blank := 0
	var run_blank := 0
	for i in 240:
		await frames(1)
		var line := run.interactor.prompt_line()
		var what := "" if line.is_empty() else ("rest" if run.interactor.current is Shrine else "barred")
		if what.is_empty():
			blank += 1
			run_blank += 1
			longest_blank = maxi(longest_blank, run_blank)
		else:
			run_blank = 0
			if seen.is_empty() or seen[-1] != what:
				seen.append(what)
		if (player.brain as RouteBrain).done and i > 20:
			break
	assert_eq(seen, ["rest", "barred"] as Array[String], "the prompt goes from Rest to the barred line once, never back (%s)" % [seen])
	assert_true(longest_blank <= 6, "and the blank between the two lasts at most six frames (%d)" % longest_blank)
	assert_true(respawn.distance_to(player.global_position) > 3.0, "(he walked on)")


# --- a built board is solid ---

func test_a_built_board_holds_a_shove_and_a_dash_step_until_its_flag() -> void:
	var w := await _world(null, null, true)
	var region: Region = w.region
	var run: StretchRun = w.run
	_at(w.player, Vector3(10, 0, 0))
	# from the street, at three places across the lane's mouth, walked and dash-stepped north into the board and shoved for 3 s
	var cases: Array[Actor] = []
	for x: float in [25.6, 27.5, 29.4]:
		cases.append(_actor(region, Vector3(x, 0.0, -2.0), "Pushed%d" % cases.size()))
	await frames(2)
	for pushed in cases:
		pushed.set_brain(ScriptBrain.new([{frames = 2, move = Vector2(0, -1), press = [&"dodge"]}, {frames = 40, move = Vector2(0, -1)},
				{frames = 2, move = Vector2(0, -1), press = [&"dodge"]}, {frames = 136, move = Vector2(0, -1)}]))
	var north := 100.0
	var up := 0.0
	for i in 180:
		for pushed in cases:
			pushed.push(Vector3(0, 0, -1) * SHOVE * DT * 10.0)
		await frames(1)
		for pushed in cases:
			north = minf(north, pushed.global_position.z)
			up = maxf(up, pushed.global_position.y)
	assert_true(north > -4.5 + StretchGround.BODY - 0.05, "held south of the board's face by a capsule's reach (the furthest north: z %.3f)" % north)
	assert_true(up < 0.05, "and never on top of it (y %.3f)" % up)
	run.set_flag(&"collector_down")
	await frames(60)
	for pushed in cases:
		pushed.place(Transform3D(Basis(), Vector3(pushed.global_position.x, 0.0, -2.0)))
		pushed.set_brain(ScriptBrain.new([{frames = 180, move = Vector2(0, -1)}]))
	await frames(2)
	for i in 180:
		for pushed in cases:
			pushed.push(Vector3(0, 0, -1) * SHOVE * DT * 10.0)
		await frames(1)
	for pushed in cases:
		assert_true(pushed.global_position.z < -8.0, "%s: with collector_down set the same shove goes through (z %.2f)" % [pushed.name, pushed.global_position.z])


# --- the walkable set ---

func test_an_open_gate_changes_the_walkable_set_by_no_more_than_the_gate_board() -> void:
	var plain := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	await frames(2)
	var plain_set: Dictionary = StretchGround.reached(plain)
	plain.queue_free()  # two regions in one world would be solid to each other
	await frames(2)
	var bare := await _bare()
	var run := _start(bare, null, null, true)
	await frames(2)
	var shut_set: Dictionary = StretchGround.reached(bare.region)
	# with the toll board added to the town and both gates shut: the toll board cuts the lane, the yard, the Rack Walk, the loop lane and the alcove off from the street
	var lane := StretchGround.cell_of(Vector2(27.5, -30.0))
	var rack_west := StretchGround.cell_of(Vector2(-32.5, -22.5))
	var yard := StretchGround.cell_of(Vector2(27.5, -65.0))
	var loop_lane := StretchGround.cell_of(Vector2(-32.5, -6.5))
	for cell: Vector2i in [lane, rack_west, yard, loop_lane]:
		assert_false(shut_set.has(cell), "with the toll board in, %s is cut off from the street" % [cell])
	assert_true(plain_set.has(lane) and plain_set.has(yard), "(the plain scene has no toll board: they are reached)")
	_door(run, &"gate_toll").open(false)
	_door(run, &"gate_shortcut").open(false)
	await frames(2)  # the physics takes a layer change at its next step
	var open_set: Dictionary = StretchGround.reached(bare.region)
	var added := PackedStringArray()
	for cell: Vector2i in open_set:
		if not plain_set.has(cell):
			var at := StretchGround.middle(cell)
			# only the cells the shortcut's board kept the body out of: its footprint grown by the body's radius and a cell
			if not Rect2(-35.0, -5.5, 5.0, 1.0).grow(StretchGround.BODY + StretchGround.CELL).has_point(at):
				added.append(str(at))
	assert_eq(added, PackedStringArray(), "with every gate open nothing is reached that the plain scene did not reach except where the shortcut's board stood")
	for cell: Vector2i in plain_set:
		assert_true(open_set.has(cell), "and nothing the plain scene reached is lost")
		if not open_set.has(cell):
			break
	assert_true(open_set.has(StretchGround.cell_of(Vector2(-32.5, -5.0))), "the gateway itself is walkable now")
	assert_false(plain_set.has(StretchGround.cell_of(Vector2(-32.5, -5.0))), "(it was not)")


# --- memory ---

func test_the_gates_survive_a_rest_a_death_and_a_load() -> void:
	var store := SaveStore.new(DIR)
	var first := await _world(null, store, true)
	var run: StretchRun = first.run
	run.set_flag(&"shortcut_open")
	run.set_flag(&"collector_down")
	await frames(60)
	run.rest(Registry.fetch(&"stretch", &"rose_a") as ShrineDef)
	await frames(60)
	assert_true(_door(run, &"gate_shortcut").is_open() and _door(run, &"gate_toll").is_open(), "open after a rest")
	(first.player as Actor).die()
	await frames(190)
	assert_false((first.player as Actor).dead, "he stood up")
	assert_true(_door(run, &"gate_shortcut").is_open() and _door(run, &"gate_toll").is_open(), "open after a death")
	assert_eq((first.region as Region).get_node("Gate").collision_layer, 0, "the shortcut board does not block")
	var saved := store.read()
	assert_true(saved != null and saved.memory.has(&"shortcut_open") and saved.memory.has(&"collector_down"), "the file has both flags")
	(first.region as Node).queue_free()
	await frames(2)
	var second := await _world(saved, null, true)
	var again: StretchRun = second.run
	assert_true(_door(again, &"gate_shortcut").is_open() and _door(again, &"gate_toll").is_open(), "open after a load")
	assert_eq((second.region as Region).get_node("Gate").collision_layer, 0, "the shortcut board does not block after the load")
	var toll := (second.region as Region).get_node_or_null("gate_toll") as StaticBody3D
	assert_true(toll == null or toll.collision_layer == 0, "nor the toll board")


# --- a body is never trapped in a board by a load ---

func test_a_saved_place_on_a_shut_boards_line_loads_him_on_standing_ground() -> void:
	var rose_a := Registry.fetch(&"stretch", &"rose_a") as ShrineDef
	# the toll board is built at run time; the shortcut's is the layout's. Both lines, each with the gate shut.
	for place: Vector3 in [Vector3(27.5, 0, -5.0), Vector3(26.0, 0, -4.9), Vector3(-32.5, 0, -5.0)]:
		var bare := await _bare()
		var data := SaveData.new_game()
		data.at = {x = place.x, y = place.y, z = place.z, yaw = 0.0}
		data.bars = {hp = 1.0, stamina = 1.0, posture = 1.0}
		var run := _start(bare, data, null, true)
		await frames(2)
		var player: Actor = bare.player
		assert_true(StretchGround.stands(bare.region, player.global_position), "saved at %s with the gates shut: he stands on standing ground" % place)
		assert_vec_near(player.global_position, rose_a.respawn, 0.01, "at the shrine, not inside the board")
		await frames(30)
		assert_vec_near(player.global_position, rose_a.respawn, 0.3, "and stays there (nothing shoves him out of a board)")
		(bare.region as Node).queue_free()
		await frames(2)


func test_a_saved_place_in_the_gateway_of_an_open_gate_is_kept() -> void:
	var bare := await _bare()
	var data := _data_with([&"collector_down"])
	data.at = {x = 27.5, y = 0.0, z = -5.0, yaw = 0.0}
	data.bars = {hp = 1.0, stamina = 1.0, posture = 1.0}
	_start(bare, data, null, true)
	await frames(2)
	assert_vec_near((bare.player as Actor).global_position, Vector3(27.5, 0, -5.0), 0.01, "with the toll gate open the mouth of the lane is a place to stand")


func test_a_saved_place_in_the_shortcuts_gateway_is_kept_once_its_flag_is_set() -> void:
	var bare := await _bare()
	var data := _data_with([&"shortcut_open"])
	data.at = {x = -32.5, y = 0.0, z = -5.0, yaw = 0.0}
	data.bars = {hp = 1.0, stamina = 1.0, posture = 1.0}
	_start(bare, data)
	await frames(2)
	assert_vec_near((bare.player as Actor).global_position, Vector3(-32.5, 0, -5.0), 0.01, "with the shortcut open its gateway is a place to stand, at the first frame of the load")


# In the real town (no toll board) a place saved at the lane's mouth is kept: nothing there is a wall.
func test_a_saved_place_at_the_lanes_mouth_is_kept_in_the_real_town() -> void:
	var bare := await _bare()
	var data := SaveData.new_game()
	data.at = {x = 27.5, y = 0.0, z = -5.0, yaw = 0.0}
	data.bars = {hp = 1.0, stamina = 1.0, posture = 1.0}
	_start(bare, data)
	await frames(2)
	assert_vec_near((bare.player as Actor).global_position, Vector3(27.5, 0, -5.0), 0.01, "the mouth of the lane is a place to stand in the town as it is")
