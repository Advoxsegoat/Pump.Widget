extends TestCase
## The place check agrees with real bodies: what an Abarax can climb, pass through and cross, the check calls reachable,
## and what he cannot, not. Held on a flat arena with steps, doorways and gaps built in the test.

const FOLDER := "res://scenes/story/fixture_yard_entrance"
const SCENE := "fixture_yard_entrance"
const WALK_FRAMES := 400

var _space: PhysicsDirectSpaceState3D


# Pushes toward `to` on the ground and does not stop.
class Pusher extends Brain:
	var to := Vector3.ZERO

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		var remaining := Vector2(to.x - actor.global_position.x, to.z - actor.global_position.z)
		if remaining.length() > 0.05:
			intent.move = remaining.normalized() * 0.45
		return intent


func _fixture() -> SceneShots:
	return (load(FOLDER + "/shots.tres") as SceneShots).duplicate_deep()


# The fixture with its foe_stop mark at `at` in the region's own space (the other marks stay where they are).
func _scene(at: Vector3) -> SceneShots:
	var scene := _fixture()
	for pair in [[&"foe_in", Vector3.ZERO], [&"foe_stop", at]]:
		var mark := scene.mark(pair[0])
		mark.space = SceneMark.Space.REGION
		mark.actor = &""
		mark.position = pair[1]
	return scene


# The lines about foe_stop (the other marks of the fixture may stand anywhere in these small worlds).
func _lines(at: Vector3, spawn := Vector3.ZERO, checker: ShotChecker = null) -> PackedStringArray:
	var used := checker if checker != null else ShotChecker.new()
	var out := PackedStringArray()
	for line in used.check_place(_scene(at), _space, spawn):
		if line.contains("mark 'foe_stop'"):
			out.append(line)
	return out


func _box(parent: Node3D, centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD | Layers.IK_SURFACE
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.add_child(shape)
	body.position = centre
	parent.add_child(body)


# A world with no floor of its own: the caller lays it out from boxes.
func _world() -> Node3D:
	var world := Node3D.new()
	track(world)
	return world


# Floor from x to x (a strip 20 m wide, its top at `top`).
func _floor(world: Node3D, from_x: float, to_x: float, top := 0.0) -> void:
	_box(world, Vector3((from_x + to_x) / 2.0, top - 0.5, 0.0), Vector3(to_x - from_x, 1.0, 20.0))


# Walks a real Abarax from `from` toward `to`; the distance he is from `to` after WALK_FRAMES.
func _body_walks(world: Node3D, from: Vector3, to: Vector3) -> float:
	var brain := Pusher.new()
	brain.to = to
	var actor := TestArena.spawn(world, Registry.fetch(&"actors", &"abarax") as ActorDef, brain, from)
	await frames(WALK_FRAMES)
	var apart := actor.global_position.distance_to(to)   # in height too: a body that fell into a gap is not across it
	actor.queue_free()
	return apart


func _settle(world: Node3D) -> void:
	await frames(2)
	_space = world.get_world_3d().direct_space_state


# --- the step ---

func test_a_real_body_climbs_a_step_of_0_10_m_and_not_one_of_0_15_m_and_the_check_says_the_same() -> void:
	for height in [0.10, 0.15]:
		var world := _world()
		_floor(world, -10.0, 10.0)
		_box(world, Vector3(6.0, height / 2.0, 0.0), Vector3(8.0, height, 6.0))   # a platform from x 2 to 10
		await _settle(world)
		var apart: float = await _body_walks(world, Vector3(0, 0, 0), Vector3(5, height, 0))
		var climbed := apart < 0.5
		var lines := _lines(Vector3(5, height, 0))
		assert_eq(climbed, height < 0.12, "a real body at a %.2f m step: %.2f m from the platform's middle" % [height, apart])
		assert_eq(lines.is_empty(), climbed, "the check at a %.2f m step: %s" % [height, "\n".join(lines)])
		world.free()


# --- doorways ---

func test_doorways_of_0_8_1_0_and_1_2_m_are_passed_on_and_off_the_grid_as_a_real_body_passes_them() -> void:
	for width in [0.8, 1.0, 1.2]:
		for centre in [0.0, 0.07, 0.125, -0.19]:
			var world := _world()
			_floor(world, -10.0, 10.0)
			_box(world, Vector3((-10.0 + centre - width / 2.0) / 2.0, 1.5, 3.0), Vector3(10.0 + centre - width / 2.0, 3.0, 0.2))
			_box(world, Vector3((10.0 + centre + width / 2.0) / 2.0, 1.5, 3.0), Vector3(10.0 - centre - width / 2.0, 3.0, 0.2))
			await _settle(world)
			var where := "doorway %.1f m wide centred at x = %.3f" % [width, centre]
			var lines := _lines(Vector3(centre, 0, 5), Vector3(centre, 0, 0))
			assert_eq(lines, PackedStringArray(), where)
			var apart: float = await _body_walks(world, Vector3(centre, 0, 0), Vector3(centre, 0, 5))
			assert_true(apart < 0.5, "%s: a real body ends %.2f m from the far side" % [where, apart])
			world.free()


# --- gaps in the floor ---

func test_floor_gaps_of_0_2_0_3_and_0_5_m_are_crossed_on_and_off_the_grid_and_a_1_m_gap_is_not() -> void:
	for width in [0.2, 0.3, 0.5, 1.0]:
		for edge in [0.0, 0.11, 0.19]:
			var world := _world()
			_floor(world, -10.0, edge)
			_floor(world, edge + width, 10.0)
			await _settle(world)
			var far := Vector3(edge + width + 2.0, 0, 0)
			var where := "gap %.1f m wide from x = %.2f" % [width, edge]
			var lines := _lines(far, Vector3(-5, 0, 0))
			var apart: float = await _body_walks(world, Vector3(-3, 0, 0), far)
			var crossed := apart < 0.5
			assert_eq(crossed, width < 1.0, "%s: a real body ends %.2f m from the far mark" % [where, apart])
			assert_eq(lines.is_empty(), crossed, "%s: %s" % [where, "\n".join(lines)])
			world.free()


# --- the pieces the mutants asked for ---

func test_reaching_reads_the_floors_height() -> void:
	var world := _world()
	_floor(world, -10.0, 10.0)
	await _settle(world)
	var checker := ShotChecker.new()
	assert_true(checker._reached(_space, Vector3(0, 0.05, 0), {Vector2i(0, 0): 0.0}), "within a step of the reached floor")
	assert_false(checker._reached(_space, Vector3(0, 0.3, 0), {Vector2i(0, 0): 0.0}), "a mark 0.3 m above the reached floor is not reached from it")


func test_reaching_needs_a_clear_line() -> void:
	var world := _world()
	_floor(world, -10.0, 10.0)
	await _settle(world)
	var checker := ShotChecker.new()
	assert_true(checker._reached(_space, Vector3(0.2, 0, 0), {Vector2i(0, 0): 0.0}), "open ground")
	_box(world, Vector3(0.1, 1.5, 0.0), Vector3(0.04, 3.0, 4.0))
	await frames(2)
	assert_false(checker._reached(_space, Vector3(0.2, 0, 0), {Vector2i(0, 0): 0.0}), "a wall between the cell and the mark")


func test_a_spawn_that_is_not_on_the_floor_is_a_line() -> void:
	var world := _world()
	_floor(world, -10.0, 10.0)
	await _settle(world)
	var lines := ShotChecker.new().check_place(_scene(Vector3(3, 0, 0)), _space, Vector3(0, 5.0, 0))
	var text := "\n".join(lines)
	assert_true(text.contains("the region's Spawn at (0.00, 5.00, 0.00) has no walkable floor under it or no room for a body"), text)


func test_the_reach_is_kept_per_region_and_spawn() -> void:
	var world := _world()
	_floor(world, -10.0, 10.0)
	# a closed room, 4 m across, around x = 6
	for wall in [[Vector3(6, 1.5, -2), Vector3(4.2, 3.0, 0.2)], [Vector3(6, 1.5, 2), Vector3(4.2, 3.0, 0.2)],
			[Vector3(4, 1.5, 0), Vector3(0.2, 3.0, 4.2)], [Vector3(8, 1.5, 0), Vector3(0.2, 3.0, 4.2)]]:
		_box(world, wall[0], wall[1])
	await _settle(world)
	var checker := ShotChecker.new()
	var inside: Dictionary = checker._reach(_space, Vector3(6, 0, 0))
	var outside: Dictionary = checker._reach(_space, Vector3(-5, 0, 0))
	assert_true(inside.size() > 20 and outside.size() > inside.size() * 3, "the room's few cells, the open ground's many: %d and %d" % [inside.size(), outside.size()])
	assert_eq(checker._reach_cache.size(), 2, "one answer for each spawn")
	assert_eq(checker._reach(_space, Vector3(6, 0, 0)).size(), inside.size(), "the room again is the room")
	assert_false(checker._reach(_space, Vector3(6, 0, 0)).has(Vector2i(-20, 0)), "a mark outside the room is not reached from inside it")


func test_a_fill_cut_off_by_its_cell_limit_says_so_and_does_not_call_far_marks_unreachable() -> void:
	var world := _world()
	_floor(world, -10.0, 10.0)
	await _settle(world)
	var checker := ShotChecker.new()
	checker.max_cells = 100
	var lines := checker.check_place(_scene(Vector3(8, 0, 0)), _space, Vector3(0, 0, 0))
	var text := "\n".join(lines)
	assert_true(text.contains("the flood of the region's floor stopped at 100 cells"), text)
	assert_false(text.contains("cannot be reached"), text)


func test_a_street_of_60_by_30_m_is_filled_whole() -> void:
	var world := _world()
	_box(world, Vector3(0, -0.5, 0), Vector3(60, 1.0, 30))
	await _settle(world)
	var checker := ShotChecker.new()
	var started := Time.get_ticks_usec()
	var cells: Dictionary = checker._reach(_space, Vector3(0, 0, 0))
	var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	print("street fill: %d cells in %.2f s" % [cells.size(), seconds])   # reported, never asserted: wall-clock time
	assert_true(cells.size() > int(0.9 * 60.0 * 30.0 / 0.0625), "nearly all of the floor is reached: %d cells" % cells.size())
