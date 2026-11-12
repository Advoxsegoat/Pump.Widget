extends TestCase
## The marks and walks of a scene checked in the place itself: the training yard, loaded into the tree with its walls
## and props, answers where a body can stand and walk.

const YARD := "res://world/training_yard/training_yard.tscn"
const FOLDER := "res://scenes/story/fixture_yard_entrance"
const SCENE := "fixture_yard_entrance"

var _space: PhysicsDirectSpaceState3D
var _yard: Node3D


func before_each() -> void:
	var region := (load(YARD) as PackedScene).instantiate() as Node3D
	track(region)
	_yard = region
	await frames(2)
	_space = region.get_world_3d().direct_space_state


func _fixture() -> SceneShots:
	return (load(FOLDER + "/shots.tres") as SceneShots).duplicate_deep()


# The fixture with its two foe marks in the region's own space at `from` and `to`.
func _scene(from: Vector3, to: Vector3) -> SceneShots:
	var scene := _fixture()
	for pair in [[&"foe_in", from], [&"foe_stop", to]]:
		var mark := scene.mark(pair[0])
		mark.space = SceneMark.Space.REGION
		mark.actor = &""
		mark.position = pair[1]
	return scene


func _place(scene: SceneShots) -> PackedStringArray:
	return ShotChecker.new().check_place(scene, _space)


func _only(lines: PackedStringArray, fragments: Array[String]) -> void:
	assert_eq(lines.size(), 1, "\n".join(lines))
	if lines.size() == 1:
		assert_true(lines[0].begins_with(SCENE + "/"), lines[0])
		for fragment in fragments:
			assert_true(lines[0].contains(fragment), "'%s' is not in: %s" % [fragment, lines[0]])


func test_the_fixtures_marks_and_walks_are_in_the_place() -> void:
	assert_eq(_place(_fixture()), PackedStringArray())


func test_a_mark_inside_a_practice_post_is_reported() -> void:
	_only(_place(_scene(Vector3(0, 0, 0), Vector3(-9, 0, -1))), ["mark 'foe_stop'", "(-9.00, 0.00, -1.00)", "PillarStone"])


func test_a_mark_inside_a_gate_pillar_is_reported_as_what_it_stands_on() -> void:
	_only(_place(_scene(Vector3(0, 0, 0), Vector3(-1.25, 0, 12.625))), ["mark 'foe_stop'", "(-1.25, 0.00, 12.", "Curb"])


func test_a_mark_on_the_kerb_is_reported() -> void:
	_only(_place(_scene(Vector3(0, 0, 0), Vector3(5, 0, 12.7))), ["mark 'foe_stop'", "Curb"])


func test_a_mark_outside_the_wall_is_reported() -> void:
	_only(_place(_scene(Vector3(0, 0, 0), Vector3(14, 0, 0))), ["mark 'foe_stop'", "outside the region's walls"])


func test_a_mark_just_off_a_lantern_post_is_reported() -> void:
	var yard := _yard
	var shape := yard.get_node("Lanterns/Lantern5/Body/Shape") as CollisionShape3D
	var lantern := (yard.get_node("Lanterns/Lantern5") as Node3D).global_position
	var radius: float = (shape.shape as CylinderShape3D).radius
	var near := lantern + Vector3(radius + 0.05, 0, 0)   # 5 cm from the post: a body is wider than that
	_only(_place(_scene(Vector3(0, 0, 0), near)), ["mark 'foe_stop'", "Lantern5"])
	var clear := lantern + Vector3(radius + 0.5, 0, 0)   # a body's width and a little over
	assert_eq(_place(_scene(Vector3(0, 0, 0), clear)).size(), 0, "a body fits there")


func test_a_mark_with_no_floor_under_it_is_reported() -> void:
	var scene := _scene(Vector3(0, 0, 0), Vector3(0, 3.0, 0))
	_only(_place(scene), ["mark 'foe_stop'", "no walkable floor within 0.1 m"])


func test_a_walk_whose_line_crosses_a_pillar_is_reported() -> void:
	_only(_place(_scene(Vector3(-11, 0, -1), Vector3(-7, 0, -1))), ["walk of knuckle from 'foe_in' to 'foe_stop'", "PillarStone", "its 4.0 m"])


func test_a_mark_that_is_an_actor_start_is_found_through_the_rehearsal_mark() -> void:
	var scene := _fixture()
	scene.mark(&"rehearsal.abarax").position = Vector3(0, 0, 11)   # facing +Z at the kerb: foe_in is 2.6 m ahead, beyond it
	scene.mark(&"rehearsal.abarax").yaw_deg = 0.0
	var lines := _place(scene)
	assert_true(lines.size() >= 1 and lines[0].contains("foe_in"), "\n".join(lines))
