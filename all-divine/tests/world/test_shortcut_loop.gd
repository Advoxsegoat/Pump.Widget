extends TestCase
## The shortcut loop: the street's west gate joins the first shrine to the Rack Walk. Lifted from the loop lane's side, it turns the walk from
## the first shrine's respawn to the Rack Walk's west end from the whole way round (the street, the lane, the Rack Walk) into a few strides.
## The numbers are measured from shrine A's respawn as it stands in data (a flood fill, 0.5 m cells, four neighbours).

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const ABARAX := "res://data/actors/abarax.tres"
## Measured from rose_a's respawn (-36.1, -3.1) to RackWest in the town as it is (the toll board is not placed): the way round with the shortcut shut is 142.0 m, with it
## open 23.0 m, and RouteBrain over GateNear, GateFar, RackWest takes 4.08 s. Each bound has a fifth of room: the shut way at least 113 m (a
## fifth under 142), the open way at most 27.6 m (a fifth over 23), the walk at most 4.9 s (a fifth over 4.08).
const SHUT_AT_LEAST := 113.0
const OPEN_AT_MOST := 27.6
const WALK_SECONDS := 4.9

var _runs: Array[StretchRun] = []


func before_each() -> void:
	Game.reset()
	Game.change(Game.State.PLAY)


func after_each() -> void:
	InputFeed.release()
	_runs.clear()
	Game.reset()


func _world(flags: Array[StringName]) -> Dictionary:
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.name = "Player"
	player.def = load(ABARAX) as ActorDef
	player.set_brain(Brain.new())
	region.add_child(player)
	await frames(2)
	var data := SaveData.new_game()
	for flag in flags:
		data.memory.set_flag(flag)
	var run := StretchRun.start(region, player, Registry.fetch(&"stretch", &"bilibara") as StretchDef, null, data)
	_runs.append(run)
	await frames(2)
	return {region = region, player = player, run = run}


func _marker(region: Region, marker_name: String) -> Vector3:
	return (region.find_child(marker_name, true, false) as Marker3D).global_position


func _respawn() -> Vector3:
	return (Registry.fetch(&"stretch", &"rose_a") as ShrineDef).respawn


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# Walks the player over `points` with a RouteBrain; every leg within (length / 4 + 3) s. Returns the frames each leg took, or an empty
# array with the leg that failed in `failed`.
func _walk(w: Dictionary, points: Array[Vector3], budget_frames := -1) -> Dictionary:
	var player: Actor = w.player
	var brain := RouteBrain.new(points)
	player.set_brain(brain)
	var taken := 0
	var limit := budget_frames if budget_frames >= 0 else 100000
	var leg_start := player.global_position
	var legs: Array[int] = []
	var leg_frames := 0
	var index := 0
	while not brain.done and taken < limit:
		var length := _flat(leg_start).distance_to(_flat(points[index]))
		var leg_limit := roundi((length / 4.0 + 3.0) * 60.0)
		await frames(1)
		taken += 1
		leg_frames += 1
		if brain.index > index:
			legs.append(leg_frames)
			leg_frames = 0
			leg_start = points[index]
			index = brain.index
		elif leg_frames > leg_limit:
			break
	return {done = brain.done, frames = taken, legs = legs, at = player.global_position}


func test_the_shortcut_cuts_the_first_shrines_way_to_the_rack_walk() -> void:
	var w := await _world([] as Array[StringName])
	var region: Region = w.region
	var run: StretchRun = w.run
	var rack_west := _flat(_marker(region, "RackWest"))
	var from := _flat(_respawn())
	var shut := StretchPaths.metres(region, from, rack_west)
	for door in run.gates:
		door.open(false)
	var open := StretchPaths.metres(region, from, rack_west)
	print("path from rose_a's respawn to RackWest: shut %.1f m, open %.1f m" % [shut, open])
	assert_true(shut >= SHUT_AT_LEAST, "the shut shortcut: the way round is at least %.0f m (%.1f)" % [SHUT_AT_LEAST, shut])
	assert_true(open > 0.0 and open <= OPEN_AT_MOST, "the open shortcut: at most %.0f m (%.1f)" % [OPEN_AT_MOST, open])
	assert_true(open < shut / 3.0, "it is a third of the way or less")


func test_abarax_walks_the_loop_from_its_far_side_and_opens_the_gate() -> void:
	var w := await _world([] as Array[StringName])
	var region: Region = w.region
	var player: Actor = w.player
	var run: StretchRun = w.run
	player.place(Transform3D(Basis.IDENTITY, _marker(region, "LaneMid")))
	await frames(2)
	var route: Array[Vector3] = []
	for marker_name in ["RackEast", "RackWest", "GateFar"]:
		route.append(_marker(region, marker_name))
	var result := await _walk(w, route)
	assert_true(result.done, "he walked LaneMid, RackEast, RackWest, GateFar, each leg within its time (%s)" % [result])
	assert_false(run.flag(&"shortcut_open"), "the gate is shut when he arrives")
	# one press
	InputFeed.apply({"pressed": PackedStringArray([&"interact"])})
	await frames(1)
	InputFeed.release()
	await frames(1)
	assert_true(run.flag(&"shortcut_open"), "one press lifted it within two frames")
	# and he walks through it
	var through: Array[Vector3] = [_marker(region, "GateNear")]
	var crossing := await _walk(w, through, 180)
	assert_true(crossing.done, "GateFar to GateNear, 3 m, through the gate in under 3 s (%s)" % [crossing])


func test_the_same_walk_with_the_gate_shut_stops_at_the_board() -> void:
	var w := await _world([] as Array[StringName])
	var region: Region = w.region
	var player: Actor = w.player
	player.place(Transform3D(Basis.IDENTITY, _marker(region, "GateFar")))
	await frames(2)
	var through: Array[Vector3] = [_marker(region, "GateNear")]
	var crossing := await _walk(w, through, 180)
	assert_false(crossing.done, "shut, the leg is not walked")
	assert_true(player.global_position.z < -5.5, "he stands north of the board (z %.2f)" % player.global_position.z)


func test_after_it_is_open_the_first_shrine_to_the_rack_walk_is_a_short_walk() -> void:
	var w := await _world([&"shortcut_open"])
	var region: Region = w.region
	var player: Actor = w.player
	player.place(Transform3D(Basis.IDENTITY, _respawn()))
	await frames(2)
	var route: Array[Vector3] = []
	for marker_name in ["GateNear", "GateFar", "RackWest"]:
		route.append(_marker(region, marker_name))
	var result := await _walk(w, route, roundi(WALK_SECONDS * 60.0))
	assert_true(result.done, "from rose_a's respawn over GateNear and GateFar to RackWest within %.1f s (took %.1f s)" % [WALK_SECONDS, float(result.frames) / 60.0])
	print("walk from rose_a's respawn to RackWest by the open gate: %d frames (%.2f s)" % [result.frames, float(result.frames) / 60.0])
