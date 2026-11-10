extends TestCase
## The training yard (world/training_yard/training_yard.tscn): its markers, lights and posts, and that its walls hold:
## a body shoved toward any wall or corner stays inside, is not stuck there, and does not vibrate against it
## (Review Focus 5: walls and corners).

const YARD := "res://world/training_yard/training_yard.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_3 := "res://data/actors/knuckle_3.tres"
const NIGHT := "res://data/render/grades/training_yard.tres"
## The walls' inner faces (layout.txt): the yard runs from -HALF to HALF in x and z.
const HALF := 12.5
## The body's capsule is this wide in radius (actor.tscn): its centre never gets nearer a wall than this.
const BODY := 0.35
const DT := 1.0 / 60
## A shove: the speed it is given every frame, so it is a shove that goes on, hard enough to run through a wall that
## was not there; and for how many frames.
const SHOVE := 30.0
const SHOVE_FRAMES := 90


func after_each() -> void:
	Game.reset()


func _yard() -> Region:
	return track((load(YARD) as PackedScene).instantiate()) as Region


func _spawn(region: Region, def_path: String, at: Vector3) -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.def = load(def_path) as ActorDef
	actor.position = at
	actor.set_brain(Brain.new())
	region.add_child(actor)
	return actor


# The eight ways at a wall or a corner of the yard: a unit vector in (x, z).
func _ways() -> Dictionary:
	var s := sqrt(0.5)
	return {
		"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0),
		"north-east": Vector2(s, -s), "north-west": Vector2(-s, -s), "south-east": Vector2(s, s), "south-west": Vector2(-s, s),
	}


func test_the_yard_is_a_region_with_the_arena_script_and_the_night_grade() -> void:
	var region := _yard()
	assert_true(region is Arena, "the yard is an Arena")
	assert_eq(region.grade, load(NIGHT), "it is drawn in the night grade")
	assert_true(region.grade.fog_color.b > region.grade.fog_color.r, "the fog is a cool blue")


func test_spawns_and_pois_exist() -> void:
	var region := _yard()
	var spawn := region.get_node_or_null("Spawn") as Marker3D
	assert_true(spawn != null, "a Spawn marker")
	if spawn != null:
		assert_true(spawn.global_position.z > 3.0, "in the south (%s)" % spawn.global_position)
		assert_true(spawn.global_basis.z.dot(Vector3(0, 0, -1)) > 0.99, "facing north, the camera's way")
	for i in range(1, 5):
		var marker := region.get_node_or_null("EnemySpawn_%d" % i) as Marker3D
		assert_true(marker != null, "EnemySpawn_%d" % i)
		if marker != null:
			assert_true(marker.global_position.z < 0.0, "EnemySpawn_%d is in the north (%s)" % [i, marker.global_position])
			assert_true(absf(marker.global_position.x) < HALF and absf(marker.global_position.z) < HALF, "and inside the walls")
	assert_true(region.get_node_or_null("EnemySpawn_5") == null, "four of them")
	var lamps := region.find_children("*", "OmniLight3D", true, false)
	assert_eq(lamps.size(), 6, "six lanterns")
	assert_eq(lamps.filter(func(l: OmniLight3D) -> bool: return l.shadow_enabled).size(), 2, "two of them with shadows")
	for lamp: OmniLight3D in lamps:
		assert_eq(lamp.light_color.to_html(false), "ffc468", "%s is warm" % lamp.name)
	var poi := get_tree().get_nodes_in_group(&"poi").filter(func(n: Node) -> bool: return region.is_ancestor_of(n))
	assert_true(poi.size() >= 2, "points of interest (%d)" % poi.size())
	assert_true(poi.all(func(n: Node) -> bool: return n is Marker3D), "Marker3Ds")


func test_yard_walls_hold_and_nobody_leaves() -> void:
	for way_name: String in _ways():
		var way: Vector2 = _ways()[way_name]
		var region := _yard()
		# Starts a metre in from the wall (or the corner), toward the middle.
		var start := Vector2(0.0 if is_zero_approx(way.x) else signf(way.x) * (HALF - 1.0), 0.0 if is_zero_approx(way.y) else signf(way.y) * (HALF - 1.0))
		var actor := _spawn(region, ABARAX, Vector3(start.x, 0.0, start.y))
		await frames(2)
		var last := actor.global_position
		var worst_step := 0.0
		var most_out := 0.0
		for i in SHOVE_FRAMES:
			actor.push(Vector3(way.x, 0.0, way.y) * SHOVE * DT * 10.0)
			await frames(1)
			if i > SHOVE_FRAMES / 2:
				worst_step = maxf(worst_step, actor.global_position.distance_to(last))
			last = actor.global_position
			most_out = maxf(most_out, maxf(absf(actor.global_position.x) - (HALF - BODY), absf(actor.global_position.z) - (HALF - BODY)))
		assert_true(most_out < 0.05, "%s: shoved at the wall, the body's centre never went more than 5 cm past its capsule's reach (%.3f m)" % [way_name, most_out])
		assert_true(absf(actor.global_position.x) < HALF and absf(actor.global_position.z) < HALF, "%s: inside the yard at %s" % [way_name, actor.global_position])
		assert_true(actor.global_position.y > -0.2 and actor.global_position.y < 0.5, "%s: still on the floor (y %.2f)" % [way_name, actor.global_position.y])
		assert_true(worst_step < 0.03, "%s: held against the wall it does not vibrate (moves %.3f m a frame at most)" % [way_name, worst_step])
		# Not stuck: given the stick away from the wall, it walks off it.
		var stuck_at := actor.global_position
		actor.set_brain(ScriptBrain.new([{frames = 60, move = -way}]))
		await frames(60)
		assert_true(actor.global_position.distance_to(stuck_at) > 1.5, "%s: it walks away from the wall (%.2f m in a second)" % [way_name, actor.global_position.distance_to(stuck_at)])
		region.queue_free()
		await frames(1)


func test_a_big_body_is_held_in_too() -> void:
	# A tier III Knuckle is a little larger than Abarax: the same walls hold it.
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]:
		var region := _yard()
		var actor := _spawn(region, KNUCKLE_3, Vector3(corner.x * (HALF - 1.0), 0.0, corner.y * (HALF - 1.0)))
		await frames(2)
		for i in 60:
			actor.push(Vector3(corner.x, 0.0, corner.y) * 5.0)
			await frames(1)
		assert_true(absf(actor.global_position.x) < HALF and absf(actor.global_position.z) < HALF, "the tier III at the corner %s stays inside (%s)" % [corner, actor.global_position])
		region.queue_free()
		await frames(1)


func test_sliding_along_a_wall_into_a_corner_stops_at_the_corner() -> void:
	# Shoved almost along the north wall toward the north-east corner: the body slides along the wall and is held where
	# the two walls meet, not caught on the way or squeezed through.
	var region := _yard()
	var actor := _spawn(region, ABARAX, Vector3(0.0, 0.0, -HALF + BODY + 0.02))
	await frames(2)
	var along := Vector3(cos(deg_to_rad(8)), 0.0, -sin(deg_to_rad(8)))
	var last := actor.global_position
	var worst_step := 0.0
	for i in 150:
		actor.push(along * 2.0)
		await frames(1)
		if i > 100:
			worst_step = maxf(worst_step, actor.global_position.distance_to(last))
		last = actor.global_position
	assert_true(actor.global_position.x > HALF - BODY - 0.1, "it slid to the east wall (x %.2f)" % actor.global_position.x)
	assert_true(absf(actor.global_position.x) < HALF and absf(actor.global_position.z) < HALF, "and is inside (%s)" % actor.global_position)
	assert_true(worst_step < 0.03, "held in the corner it does not vibrate (%.3f m a frame)" % worst_step)
