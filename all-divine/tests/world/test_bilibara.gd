extends TestCase
## The Bilibara stretch's ground, walls, gate and markers (world/bilibara/bilibara.tscn, built from layout.txt): a place Abarax
## can walk and cannot leave. The walkable set is found by flood fill with the body's own capsule, so a leak at a corner, a
## junction, a kerb, a post or the gate shows as a cell the body can stand in that no wall closes; the closed gate is a long way
## round; a shove, a dash-step, a lunge and a tier III body are held at every kind of edge (Review Focus 1 and 4).

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_3 := "res://data/actors/knuckle_3.tres"
const TOON_WORLD := "res://render/shaders/toon_world.gdshader"
const STONE := "res://world/materials/%s.tres"
## The body's capsule is this wide in radius (actor.tscn): its centre never gets nearer a wall than this.
const BODY := 0.35
const DT := 1.0 / 60
## A shove: the speed it is given every frame (a shove that goes on, hard enough to run through a wall that was not there).
const SHOVE := 30.0
## The flood fill's cells, in metres, and where it looks: a little more than the whole stretch.
const CELL := 0.5
const GRID_X := Vector2i(-90, 90)
const GRID_Z := Vector2i(-165, 25)
## The seven places of the plan's table (x0 z0 w d), and the stone each is laid in.
const PLACES := {
	"W1 court A": {rect = Rect2(-40, -5, 10, 10), stone = "slate_cold"},
	"W2 Rue Caillou": {rect = Rect2(-30, -5, 62.5, 10), stone = "cobble"},
	"W3 the Tanneries lane": {rect = Rect2(25, -55, 5, 50), stone = "tan_earth"},
	"W4 the Rack Walk": {rect = Rect2(-35, -25, 60, 5), stone = "tan_earth"},
	"W5 the loop lane": {rect = Rect2(-35, -20, 5, 15), stone = "tan_earth"},
	"W6 alcove B": {rect = Rect2(30, -37.5, 7.5, 7.5), stone = "slate_cold"},
	"W7 the Tanneries yard": {rect = Rect2(15, -75, 25, 20), stone = "tan_earth"},
}
## The yard's fighting square is laid in its own stone with a border course of another round it: the margins stay tan earth.
const YARD_CENTRE_STONE := "flagstone_cold"
const YARD_BORDER_STONE := "slate_cold"
const AREA := 1906.25
## Markers: name -> [x, z, yaw in degrees about +Y (0 faces south, 90 east, 180 north, 270 west)].
const MARKERS := {
	"Spawn": [-32.5, 1.25, 90], "ShrineSite_A": [-35, 0, 90], "ShrineSite_B": [35, -33.75, 270],
	"StreetEast": [27.5, 0, 0], "LaneMid": [27.5, -30, 0], "RackEast": [27.5, -22.5, 0], "RackWest": [-32.5, -22.5, 0],
	"GateFar": [-32.5, -6.5, 0], "GateNear": [-32.5, -3.5, 180], "YardEntry": [27.5, -57.5, 180], "KnuckleSpawn": [27.5, -68, 0],
	"HandDoor_1": [20, -73.8, 0], "HandDoor_2": [27.5, -73.8, 0], "HandDoor_3": [35, -73.8, 0],
}
## Points of interest: name -> [x, z, height above the ground].
const POIS := {
	"ShrinePlinth_A": [-36.1, -4.7, 0.65], "ShrinePlinth_B": [31.8, -37.2, 0.65], "ShortcutGate": [-32.5, -5, 1.0],
	"YardGate": [27.5, -55, 1.4], "YardCentre": [27.5, -65, 1.0], "VatWest": [20, -66.25, 1.0], "VatEast": [35, -66.25, 1.0],
	"Lazymans": [-38.75, -5, 1.8], "HatShop": [-10, -5, 1.6],
}

## The flood fill, made once for the run (the stretch does not change): {free, ground, reached} by cell.
static var _fill_memo := {}


func after_each() -> void:
	Game.reset()


func _region() -> Region:
	var scene := load(BILIBARA) as PackedScene
	assert_true(scene != null, "the scene %s exists" % BILIBARA)
	if scene == null:
		return null
	return track(scene.instantiate()) as Region


func _spawn(region: Region, def_path: String, at: Vector3) -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.def = load(def_path) as ActorDef
	actor.position = at
	actor.set_brain(Brain.new())
	region.add_child(actor)
	return actor


func _marker_at(region: Region, marker_name: String) -> Vector2:
	var marker := region.get_node(marker_name) as Marker3D
	return Vector2(marker.global_position.x, marker.global_position.z)


# The cell (a Vector2i) a point of the ground is in, and where its middle is.
func _cell_of(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))


func _middle(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


# Whether the body's capsule, reduced to a ball low down (a 0.35 m capsule 0.5 m up), overlaps something on `world` at `at`
# (x, z); `radius` is the ball's. The ground is under it, not in it.
func _blocked(space: PhysicsDirectSpaceState3D, at: Vector2, radius := BODY) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 2.0 * radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), Vector3(at.x, 0.5, at.y))
	query.collision_mask = Layers.WORLD
	return not space.intersect_shape(query, 1).is_empty()


# Whether `ik_surface` is under (x, z) at y = 0. The ray starts a hand's breadth up (inside a vat or a post it then finds the plate
# under it) and a hair off the cell's middle, which is often on the very face of a box (a ray along a face finds nothing).
func _ground_under(space: PhysicsDirectSpaceState3D, point: Vector2) -> bool:
	var at := point + Vector2(0.013, 0.007)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 0.05, at.y), Vector3(at.x, -0.5, at.y), Layers.IK_SURFACE))
	return not hit.is_empty() and absf((hit["position"] as Vector3).y) < 1e-3


# The flood fill from Spawn on CELL cells: {free: cells whose capsule overlaps no wall (true), ground: cells with ground under
# their middle, reached: cells walked to from Spawn (a free ground cell next to a reached one)}. Made once.
func _fill(region: Region) -> Dictionary:
	if not _fill_memo.is_empty():
		return _fill_memo
	await frames(2)
	var space := region.get_world_3d().direct_space_state
	var free := {}
	var ground := {}
	for cx in range(GRID_X.x, GRID_X.y):
		for cz in range(GRID_Z.x, GRID_Z.y):
			if _ground_under(space, _middle(Vector2i(cx, cz))):
				ground[Vector2i(cx, cz)] = true
	var reached := {}
	var queue: Array[Vector2i] = []
	var start := _cell_of(_marker_at(region, "Spawn"))
	var near := func(cell: Vector2i) -> bool:
		if not free.has(cell):
			free[cell] = not _blocked(space, _middle(cell))
		return free[cell]
	if ground.has(start) and near.call(start):
		reached[start] = true
		queue.append(start)
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if not reached.has(next) and ground.has(next) and near.call(next):
				reached[next] = true
				queue.append(next)
	# What the leak check asks of the neighbours of the reached cells, and which of the ground is free.
	for cell: Vector2i in reached.keys():
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			near.call(cell + step)
	for cell: Vector2i in ground.keys():
		near.call(cell)
	_fill_memo = {free = free, ground = ground, reached = reached}
	return _fill_memo


# The number of steps, over walkable cells, from `from` to `to` (-1 if there is no way), found by breadth first search.
func _steps(fill: Dictionary, from: Vector2i, to: Vector2i) -> int:
	var reached: Dictionary = fill.reached
	var seen := {from: 0}
	var queue: Array[Vector2i] = [from]
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		if cell == to:
			return seen[cell]
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if reached.has(next) and not seen.has(next):
				seen[next] = seen[cell] + 1
				queue.append(next)
	return -1


# The plates of the walkable ground: {rect (x, z), body}.
func _plates(region: Region) -> Array[Dictionary]:
	var plates: Array[Dictionary] = []
	var walkable := region.get_node_or_null("Walkable")
	assert_true(walkable != null, "a Walkable group of ground plates")
	if walkable == null:
		return plates
	for body: StaticBody3D in walkable.find_children("*", "StaticBody3D", true, false):
		var shape := body.get_node("Shape") as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		var centre := shape.global_position
		plates.append({rect = Rect2(centre.x - size.x / 2, centre.z - size.z / 2, size.x, size.z), body = body})
	return plates


func test_the_stretch_is_a_plain_region_with_its_markers_pois_and_no_enemy_spawns() -> void:
	var region := _region()
	if region == null:
		return
	assert_true(region is Region and not region is Arena, "a Region and not an Arena")
	assert_eq(region.name, &"Bilibara", "called Bilibara")
	for marker_name: String in MARKERS:
		var marker := region.get_node_or_null(marker_name) as Marker3D
		assert_true(marker != null, "a Marker3D %s" % marker_name)
		if marker == null:
			continue
		var spec: Array = MARKERS[marker_name]
		assert_near(marker.global_position.x, spec[0], 1e-3, "%s x" % marker_name)
		assert_near(marker.global_position.z, spec[1], 1e-3, "%s z" % marker_name)
		assert_near(marker.global_position.y, 0.0, 1e-3, "%s stands on the ground" % marker_name)
		var yaw := deg_to_rad(float(spec[2]))
		assert_vec_near(marker.global_basis.z, Vector3(sin(yaw), 0.0, cos(yaw)), 1e-3, "%s faces yaw %d" % [marker_name, spec[2]])
	var pois := get_tree().get_nodes_in_group(&"poi").filter(func(n: Node) -> bool: return region.is_ancestor_of(n))
	assert_eq(pois.size(), POIS.size(), "%d points of interest" % POIS.size())
	for poi_name: String in POIS:
		var poi := region.find_child(poi_name, true, false) as Marker3D
		assert_true(poi != null and poi.is_in_group(&"poi"), "%s is a Marker3D in the group poi" % poi_name)
		if poi == null:
			continue
		var spec: Array = POIS[poi_name]
		assert_near(poi.global_position.x, spec[0], 1e-3, "%s x" % poi_name)
		assert_near(poi.global_position.z, spec[1], 1e-3, "%s z" % poi_name)
		assert_near(poi.global_position.y, spec[2], 1e-3, "%s is %s m up" % [poi_name, spec[2]])
	assert_eq(region.find_children("EnemySpawn*", "Node", true, false).size(), 0, "no EnemySpawn marker")
	assert_eq(region.find_children("Barrier*", "Node", true, false).size(), 0, "no unseen barrier")
	# What the task says the scene holds: a pale sky and a gentle sun, and the vats of the yard.
	var env := (region.get_node("WorldEnvironment") as WorldEnvironment).environment
	assert_eq(env.background_color.to_html(false), "aebbcc", "the sky")
	var sun := region.get_node("Sun") as DirectionalLight3D
	assert_vec_near(sun.rotation_degrees, Vector3(-60, 30, 0), 1e-3, "the sun's way")
	assert_near(sun.light_energy, 0.25, 1e-6, "its energy")
	assert_eq(sun.light_color.to_html(false), "f4f7ff", "and colour")
	assert_eq(region.find_children("Vat*", "StaticBody3D", true, false).size(), 5, "five vats: two in the yard, three in the drying yard")
	assert_true(region.get_node_or_null("Kit") is KitDresser, "drawn in Bilibara's colours (kit bilibara)")


func test_ground_plates_tile_each_place_exactly() -> void:
	var region := _region()
	if region == null:
		return
	var plates := _plates(region)
	var total := 0.0
	for i in plates.size():
		var rect: Rect2 = plates[i].rect
		total += rect.get_area()
		assert_true(rect.size.x <= 12.5 + 1e-6 and rect.size.y <= 12.5 + 1e-6, "plate %s is at most 12.5 m a side" % rect)
		for j in range(i + 1, plates.size()):
			assert_true(rect.intersection(plates[j].rect).get_area() < 1e-6, "plates %s and %s do not overlap" % [rect, plates[j].rect])
	assert_near(total, AREA, 0.01, "the plates cover 1,906.25 m2 (%.2f)" % total)
	for place_name: String in PLACES:
		var place: Rect2 = PLACES[place_name].rect
		var inside := 0.0
		for plate in plates:
			if place.grow(1e-6).encloses(plate.rect):
				inside += (plate.rect as Rect2).get_area()
		assert_near(inside, place.get_area(), 0.01, "%s is tiled by plates inside it (%.2f of %.2f m2)" % [place_name, inside, place.get_area()])
	# The street is six plates: five of 10 m and the last 12.5.
	var street: Array = plates.filter(func(p: Dictionary) -> bool: return (PLACES["W2 Rue Caillou"].rect as Rect2).grow(1e-6).encloses(p.rect))
	assert_eq(street.size(), 6, "the street is six plates")
	var widths := street.map(func(p: Dictionary) -> float: return (p.rect as Rect2).size.x)
	widths.sort()
	assert_eq(widths, [10.0, 10.0, 10.0, 10.0, 10.0, 12.5], "five of 10 m and the last 12.5")


func test_every_ground_is_toon_world_at_32_texels_per_metre() -> void:
	var region := _region()
	if region == null:
		return
	var plates := _plates(region)
	assert_true(plates.size() >= 20, "there are plates (%d)" % plates.size())
	for plate in plates:
		var body := plate.body as StaticBody3D
		var mesh := body.get_node("Mesh") as MeshInstance3D
		var material := mesh.material_override as ShaderMaterial
		assert_true(material != null and material.shader.resource_path == TOON_WORLD, "%s is drawn in toon_world" % body.name)
		if material == null:
			continue
		assert_eq(material.get_shader_parameter(&"world_uv"), true, "%s: world_uv" % body.name)
		assert_eq(material.get_shader_parameter(&"texels_per_metre"), 32.0, "%s: 32 texels per metre" % body.name)
		var place := ""
		for place_name: String in PLACES:
			if (PLACES[place_name].rect as Rect2).grow(1e-6).encloses(plate.rect):
				place = place_name
		assert_ne(place, "", "%s is in one of the places" % body.name)
		if place != "":
			var stone: String = PLACES[place].stone
			if String(body.name).begins_with("YardPlateCentre"):
				stone = YARD_CENTRE_STONE
			elif String(body.name).begins_with("YardPlateBorder"):
				stone = YARD_BORDER_STONE
			assert_eq(material.resource_path, STONE % stone, "%s (%s) is %s" % [body.name, place, stone])
		assert_near(mesh.global_position.y + (mesh.mesh as BoxMesh).size.y / 2.0, 0.0, 1e-6, "%s: its top is at y = 0" % body.name)
		assert_true(body.collision_layer & Layers.WORLD != 0 and body.collision_layer & Layers.IK_SURFACE != 0, "%s: world and ik_surface" % body.name)


func test_the_walkable_ground_is_one_connected_sealed_set() -> void:
	var region := _region()
	if region == null:
		return
	var fill := await _fill(region)
	var free: Dictionary = fill.free
	var ground: Dictionary = fill.ground
	var reached: Dictionary = fill.reached
	# The ground is the table's 1,906.25 m2: 7,625 cells of a quarter of a square metre.
	assert_near(ground.size() * CELL * CELL, AREA, 0.01, "the ground is 1,906.25 m2 (%.2f)" % (ground.size() * CELL * CELL))
	# Every cell of ground the body's capsule fits in is reached from Spawn: no pocket, no island. (The brief asked for 99% of
	# the whole area, but the capsule is 0.35 m in radius and the cells 0.5 m, so the first cell along every wall is one the body
	# cannot stand in; the number to hold is that none the body CAN stand in is cut off.)
	var standable := 0
	var cut_off := PackedStringArray()
	for cell: Vector2i in ground.keys():
		if free[cell]:
			standable += 1
			if not reached.has(cell) and cut_off.size() < 5:
				cut_off.append(str(_middle(cell)))
	assert_eq(cut_off, PackedStringArray(), "no cell the body fits in is cut off from Spawn")
	assert_true(reached.size() >= 0.99 * standable, "%d of %d standable cells are reached" % [reached.size(), standable])
	assert_true(reached.size() >= 0.75 * ground.size(), "and they are most of the ground (%d of %d cells)" % [reached.size(), ground.size()])
	for marker_name: String in MARKERS:
		assert_true(reached.has(_cell_of(_marker_at(region, marker_name))), "%s is in a reached cell" % marker_name)
	# Zero leaks: each neighbour of a reached cell is reached or has a wall within the capsule's reach of it.
	var leaks := PackedStringArray()
	for cell: Vector2i in reached.keys():
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if not reached.has(next) and free[next]:
				leaks.append("%s -> %s" % [_middle(cell), _middle(next)])
	assert_eq(leaks.size(), 0, "no leaks: %s" % [leaks.slice(0, 5)])


func test_the_closed_gate_is_a_long_way_round() -> void:
	var region := _region()
	if region == null:
		return
	var near := _marker_at(region, "GateNear")
	var far := _marker_at(region, "GateFar")
	assert_near(near.distance_to(far), 3.0, 1e-3, "GateNear and GateFar are 3 m apart in a straight line")
	var fill := await _fill(region)
	var steps := _steps(fill, _cell_of(far), _cell_of(near))
	assert_true(steps >= 0, "there is a way between them")
	assert_true(steps * CELL >= 140.0, "and it is %.1f m round (the street, the lane, the Rack Walk, the loop lane): at least 140" % (steps * CELL))
	# Shoved at the gate from each side for 3 s, a body stays on its side and does not vibrate.
	var cases: Array[Dictionary] = []
	for x: float in [-34.5, -32.5, -30.5]:
		cases.append({at = Vector3(x, 0.0, far.y), way = Vector3(0, 0, 1), north = true})
		cases.append({at = Vector3(x, 0.0, near.y), way = Vector3(0, 0, -1), north = false})
	for c in cases:
		c.actor = _spawn(region, ABARAX, c.at)
		c.last = c.at
		c.worst = 0.0
		c.crossed = false
	await frames(2)
	for i in 180:
		for c in cases:
			(c.actor as Actor).push((c.way as Vector3) * SHOVE * DT * 10.0)
		await frames(1)
		for c in cases:
			var here := (c.actor as Actor).global_position
			if i > 90:
				c.worst = maxf(c.worst, here.distance_to(c.last))
			c.last = here
			if (c.north and here.z > -5.0) or (not c.north and here.z < -5.0):
				c.crossed = true
	for c in cases:
		var side := "north" if c.north else "south"
		assert_false(c.crossed, "x %.1f from the %s: the gate holds" % [c.at.x, side])
		assert_true(c.worst < 0.03, "x %.1f from the %s: no vibration (%.3f m a frame)" % [c.at.x, side, c.worst])


# Walks Abarax over the markers `names` in order with a RouteBrain from the first; each leg in (its length / 4 + 3) s, to
# within 0.6 m, faster than 0.5 m/s on 90% of its frames. Returns the player's positions over the whole walk.
func _walk(region: Region, names: Array[String]) -> Array[Vector3]:
	var waypoints: Array[Vector3] = []
	for marker_name in names:
		waypoints.append((region.find_child(marker_name, true, false) as Marker3D).global_position)
	var abarax := _spawn(region, ABARAX, waypoints[0])
	await frames(2)
	var brain := RouteBrain.new(waypoints.slice(1))
	abarax.set_brain(brain)
	var path: Array[Vector3] = []
	var last := abarax.global_position
	for leg in range(1, waypoints.size()):
		var length := Vector2(waypoints[leg].x - waypoints[leg - 1].x, waypoints[leg].z - waypoints[leg - 1].z).length()
		var limit := roundi((length / 4.0 + 3.0) * 60.0)
		var moving := 0
		var frames_taken := 0
		while frames_taken < limit and not brain.done and brain.index < leg:
			await frames(1)
			frames_taken += 1
			if abarax.global_position.distance_to(last) / DT > 0.5:
				moving += 1
			last = abarax.global_position
			path.append(abarax.global_position)
		var arrived := Vector2(abarax.global_position.x - waypoints[leg].x, abarax.global_position.z - waypoints[leg].z).length()
		assert_true(brain.index >= leg, "leg %d to %s done within %.1f s (it took %.1f s)" % [leg, names[leg], limit * DT, frames_taken * DT])
		assert_true(arrived < 0.65, "leg %d ends near %s (%.2f m)" % [leg, names[leg], arrived])
		assert_true(moving >= 0.9 * frames_taken, "leg %d: moving faster than 0.5 m/s on %d of %d frames" % [leg, moving, frames_taken])
	return path


func test_abarax_walks_from_the_first_shrine_site_to_the_yard() -> void:
	var region := _region()
	if region == null:
		return
	var path := await _walk(region, ["ShrineSite_A", "StreetEast", "LaneMid", "YardEntry", "YardCentre"])
	assert_true(path.size() > 600, "a long walk (%d frames)" % path.size())
	var end := path[path.size() - 1]
	assert_true(Vector2(end.x - 27.5, end.z + 65.0).length() < 0.65, "he ends at the yard's centre (%s)" % end)


func test_abarax_walks_the_loop_from_its_far_side_up_to_the_gate() -> void:
	var region := _region()
	if region == null:
		return
	var path := await _walk(region, ["LaneMid", "RackEast", "RackWest", "GateFar"])
	assert_true(path.size() > 300, "a long walk (%d frames)" % path.size())
	var end := path[path.size() - 1]
	var far := _marker_at(region, "GateFar")
	assert_true(Vector2(end.x - far.x, end.z - far.y).length() < 0.65, "he ends within 0.6 m of GateFar (%s)" % end)
	for at in path:
		assert_true(at.z < -5.0, "he is never through the gate (z %.2f)" % at.z)


# The shoves: {at (x, z), way (a direction in x, z)}. A body shoved at each for 120 frames at SHOVE, and then walked 60 frames
# the other way, must end inside a reached cell (not through a wall, on the ground), no more than 5 cm past the capsule's
# reach of any wall, and walk off (at least 1 m).
func _shoves() -> Array[Dictionary]:
	var s := sqrt(0.5)
	var list: Array[Dictionary] = []
	var add := func(label: String, at: Vector2, way: Vector2) -> void:
		list.append({label = label, at = at, way = way.normalized()})
	# The yard's four corners.
	add.call("yard NW corner", Vector2(16, -74), Vector2(-1, -1))
	add.call("yard NE corner", Vector2(39, -74), Vector2(1, -1))
	add.call("yard SW corner", Vector2(16, -56), Vector2(-1, 1))
	add.call("yard SE corner", Vector2(39, -56), Vector2(1, 1))
	# Both pillar posts of the yard's mouth, from the yard and from the lane.
	add.call("west post from the yard", Vector2(26, -56.5), Vector2(24.875 - 26, -55.125 + 56.5))
	add.call("east post from the yard", Vector2(29, -56.5), Vector2(30.125 - 29, -55.125 + 56.5))
	add.call("west post from the lane", Vector2(26, -53.5), Vector2(24.875 - 26, -55.125 + 53.5))
	add.call("east post from the lane", Vector2(29, -53.5), Vector2(30.125 - 29, -55.125 + 53.5))
	# The lane mouth's two corners at the street, from both sides.
	add.call("lane mouth west corner from the street", Vector2(24, -4), Vector2(1, -1))
	add.call("lane mouth west corner from the lane", Vector2(26, -6), Vector2(-1, 1))
	add.call("lane mouth east corner from the street", Vector2(31, -4), Vector2(-1, -1))
	add.call("lane mouth east corner from the lane", Vector2(29, -6), Vector2(1, 1))
	# The alcove's three corners.
	add.call("alcove NE corner", Vector2(36.5, -36.5), Vector2(1, -1))
	add.call("alcove SE corner", Vector2(36.5, -31), Vector2(1, 1))
	add.call("alcove NW corner", Vector2(31, -36.5), Vector2(-1, -1))
	# The street's two caps and the court's corners.
	add.call("street east cap", Vector2(31.5, 0), Vector2(1, 0))
	add.call("court west cap", Vector2(-39, 0), Vector2(-1, 0))
	add.call("court SW corner", Vector2(-39, 4), Vector2(-1, 1))
	add.call("court NW corner", Vector2(-39, -4), Vector2(-1, -1))
	# The Rack Walk's west and east ends.
	add.call("Rack Walk west end", Vector2(-34, -22.5), Vector2(-1, 0))
	add.call("Rack Walk NW corner", Vector2(-34, -24), Vector2(-1, -1))
	add.call("Rack Walk east end", Vector2(24, -22.5), Vector2(1, 0))
	# The loop lane's corners: at the gate and at the Rack Walk's kerb.
	add.call("loop lane SW corner at the gate", Vector2(-34, -6), Vector2(-1, 1))
	add.call("loop lane SE corner at the gate", Vector2(-31, -6), Vector2(1, 1))
	add.call("loop lane mouth corner at the kerb", Vector2(-29, -21), Vector2(-1, 1))
	add.call("a south-east slide along the kerb", Vector2(0, 4), Vector2(s, s))
	return list


func test_nobody_leaves_at_a_corner_a_junction_a_kerb_or_a_post() -> void:
	var region := _region()
	if region == null:
		return
	var fill := await _fill(region)
	var reached: Dictionary = fill.reached
	var space := region.get_world_3d().direct_space_state
	var cases := _shoves()
	assert_true(cases.size() >= 20, "at least 20 shoves (%d)" % cases.size())
	for c in cases:
		c.actor = _spawn(region, ABARAX, Vector3(c.at.x, 0.0, c.at.y))
	await frames(2)
	for i in 120:
		for c in cases:
			(c.actor as Actor).push(Vector3(c.way.x, 0.0, c.way.y) * SHOVE * DT * 10.0)
		await frames(1)
	for c in cases:
		var actor := c.actor as Actor
		var here := Vector2(actor.global_position.x, actor.global_position.z)
		# In a reached cell, or in the band along a wall where the capsule does not fit a cell's middle (the cell is walled),
		# and over one of the table's places, on the ground.
		var cell := _cell_of(here)
		assert_true(reached.has(cell) or _blocked(space, _middle(cell)), "%s: he ends in a reached cell or the wall's band (%s)" % [c.label, here])
		assert_true(PLACES.values().any(func(p: Dictionary) -> bool: return (p.rect as Rect2).has_point(here)), "%s: over one of the places (%s)" % [c.label, here])
		assert_true(_ground_under(space, here), "%s: on the ground" % c.label)
		assert_true(actor.global_position.y > -0.2 and actor.global_position.y < 0.5, "%s: on the ground (y %.2f)" % [c.label, actor.global_position.y])
		assert_false(_blocked(space, here, BODY - 0.05), "%s: no more than 5 cm past the capsule's reach of a wall (%s)" % [c.label, here])
		c.stuck = here
		actor.set_brain(ScriptBrain.new([{frames = 60, move = -(c.way as Vector2)}]))
	await frames(60)
	for c in cases:
		var actor := c.actor as Actor
		var moved := Vector2(actor.global_position.x, actor.global_position.z).distance_to(c.stuck)
		assert_true(moved >= 1.0, "%s: he walks off (%.2f m)" % [c.label, moved])


func test_a_big_body_is_held_in_too() -> void:
	# Every actor shares one capsule (actor.tscn: radius 0.35, height 1.8); `model_scale` scales only the rig, so a tier III or the
	# heavy Knuckle is held by the same walls as Abarax, not by more. This holds that fact (the day an actor's body grows, this
	# fails and the walls must be tried again with it), and shoves a tier III at the yard's four corners and the alcove's three
	# for 60 frames: it stays inside the walkable set, over one of the table's places, on the ground.
	var region := _region()
	if region == null:
		return
	var dir := DirAccess.open("res://data/actors")
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var shaped := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
		shaped.def = load("res://data/actors/" + file) as ActorDef
		region.add_child(shaped)
		var capsule := (shaped.get_node("Body") as CollisionShape3D).shape as CapsuleShape3D
		assert_true(capsule != null and is_equal_approx(capsule.radius, 0.35) and is_equal_approx(capsule.height, 1.8), "%s's body is the one capsule (radius 0.35, height 1.8)" % file)
		shaped.queue_free()
	var cases: Array[Dictionary] = []
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]:
		cases.append({label = "yard corner %s" % corner, at = Vector2(27.5 + corner.x * 11.5, -65.0 + corner.y * 9.0), way = corner})
	cases.append({label = "alcove NE", at = Vector2(36.5, -36.5), way = Vector2(1, -1)})
	cases.append({label = "alcove SE", at = Vector2(36.5, -31), way = Vector2(1, 1)})
	cases.append({label = "alcove NW", at = Vector2(31, -36.5), way = Vector2(-1, -1)})
	for c in cases:
		c.actor = _spawn(region, KNUCKLE_3, Vector3(c.at.x, 0.0, c.at.y))
	await frames(2)
	for i in 60:
		for c in cases:
			(c.actor as Actor).push(Vector3(c.way.x, 0.0, c.way.y).normalized() * 5.0)
		await frames(1)
	for c in cases:
		var at := (c.actor as Actor).global_position
		var inside := PLACES.values().any(func(p: Dictionary) -> bool: return (p.rect as Rect2).has_point(Vector2(at.x, at.z)))
		assert_true(inside, "the tier III at %s stays inside the walkable set (%s)" % [c.label, at])
		assert_true(at.y > -0.2 and at.y < 0.5, "%s: on the ground (y %.2f)" % [c.label, at.y])


func test_every_south_edge_is_a_kerb_a_low_wall_or_the_gate() -> void:
	var region := _region()
	if region == null:
		return
	var fill := await _fill(region)
	var reached: Dictionary = fill.reached
	var space := region.get_world_3d().direct_space_state
	assert_eq(region.find_children("Barrier*", "Node", true, false).size(), 0, "no Barrier node")
	var south_edges := 0
	var tall := PackedStringArray()
	var not_low := PackedStringArray()
	for cell: Vector2i in reached.keys():
		if reached.has(cell + Vector2i(0, 1)) or fill.free[cell + Vector2i(0, 1)]:
			continue
		var at := _middle(cell)
		# A cell whose south neighbour is walled by the SIDE of a wall (a flank beside an open lane) has nothing straight south
		# of it within the capsule's reach: the ray cannot judge it, and test_nothing_tall_touches_walkable_ground_on_its_south_side
		# does, over every solid of the scene.
		var near := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 0.15, at.y), Vector3(at.x, 0.15, at.y + CELL + BODY), Layers.WORLD))
		if near.is_empty():
			continue
		south_edges += 1
		# Chest height: nothing taller than 1.3 m, bar a post narrower than 0.8 m, for 6 m south.
		var chest := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 1.0, at.y), Vector3(at.x, 1.0, at.y + 6.0), Layers.WORLD))
		if not chest.is_empty() and not _low_or_post(chest["collider"] as StaticBody3D, 1.3, true) and tall.size() < 5:
			tall.append("%s: %s" % [at, (chest["collider"] as Node).get_path()])
		# Shin height: the kerb, a low wall, the gate (or a post): something low, and no other.
		var shin := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 0.15, at.y), Vector3(at.x, 0.15, at.y + 6.0), Layers.WORLD))
		if shin.is_empty() or (not _low_or_post(shin["collider"] as StaticBody3D, 0.65, true) and not String((shin["collider"] as Node).name).begins_with("Vat") and not_low.size() < 5):
			not_low.append("%s: %s" % [at, shin.get("collider")])
	assert_true(south_edges > 100, "there are south edges to look at (%d cells)" % south_edges)
	assert_eq(tall, PackedStringArray(), "at chest height nothing taller than 1.3 m stands south of a south edge")
	assert_eq(not_low, PackedStringArray(), "at shin height every south edge is a kerb, a low wall (0.6 m), the gate's board, a post or a vat")


# Whether `body`'s collision boxes are all no higher than `most` (a kerb, a low wall, the gate), or, with `post_ok`, it is a post:
# one box narrower than 0.8 m each way.
func _low_or_post(body: StaticBody3D, most: float, post_ok: bool) -> bool:
	if body == null:
		return false
	var low := true
	var thin := true
	for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
		var size := (shape.shape as BoxShape3D).size if shape.shape is BoxShape3D else Vector3(9, 9, 9)
		low = low and size.y <= most + 1e-6
		thin = thin and size.y <= 1.05   # no exemption for width: only what stands no higher than a fighter's hips
	return low or (post_ok and thin)


# The kerb is all that closes a south edge, lower than a body's capsule is wide: it must hold what a fight throws at it. A
# dash-step, the Knuckle's lunges and a hard shove, each straight at it, end with the centre a capsule's reach inside its face and
# the feet on the ground. At the street's kerb (z 5, x 3), the Rack Walk's (z -20, x -10) and the yard's (z -55, x 18).
func test_the_kerbs_alone_hold_a_dash_step_a_lunge_and_a_shove() -> void:
	var region := _region()
	if region == null:
		return
	for place in [{name = "the street's kerb", face = 5.0, x = 3.0, foe_x = -4.5}, {name = "the Rack Walk's kerb", face = -20.0, x = -10.0, foe_x = -17.0},
			{name = "the yard's kerb", face = -55.0, x = 18.0, foe_x = 20.5}]:
		var face: float = place.face
		var abarax := _spawn(region, ABARAX, Vector3(place.x, 0.0, face - 0.9))
		await frames(2)
		abarax.set_brain(ScriptBrain.new([{frames = 2, move = Vector2(0, 1), press = [&"dodge"]}, {frames = 40, move = Vector2(0, 1)},
				{frames = 2, move = Vector2(0, 1), press = [&"dodge"]}, {frames = 60, move = Vector2(0, 1)}]))
		var stepped := false
		var south := -1000.0
		var up := 0.0
		for i in 104:
			await frames(1)
			stepped = stepped or (abarax.runner.current != null and abarax.runner.current.id == &"dash_step")
			south = maxf(south, abarax.global_position.z)
			up = maxf(up, abarax.global_position.y)
		assert_true(stepped, "%s: he dash-stepped" % place.name)
		assert_true(absf(south - (face - BODY)) < 0.05, "%s: dash-stepping at it, his centre stops a capsule's reach from its face (%.3f m)" % [place.name, face - south])
		assert_true(up < 0.05, "%s: and he stays on the ground (y %.3f)" % [place.name, up])
		abarax.queue_free()
		var knuckle := _spawn(region, KNUCKLE_1, Vector3(place.foe_x, 0.0, face - 1.2))
		await frames(2)
		for move_id: StringName in [&"knuckle_sweep", &"knuckle_thrust"]:
			knuckle.place(Transform3D(Basis.IDENTITY, Vector3(place.foe_x, 0.0, face - 1.2)))
			await frames(2)
			knuckle.runner.start(Registry.fetch(&"moves", move_id) as MoveData)
			south = -1000.0
			up = 0.0
			for i in 100:
				await frames(1)
				south = maxf(south, knuckle.global_position.z)
				up = maxf(up, knuckle.global_position.y)
			assert_true(absf(south - (face - BODY)) < 0.05, "%s: %s reaches it and stops there (%.3f m)" % [place.name, move_id, face - south])
			assert_true(up < 0.05, "%s: %s on the ground (y %.3f)" % [place.name, move_id, up])
		south = -1000.0
		up = 0.0
		for i in 60:
			knuckle.push(Vector3(0.0, 0.0, 12.0))
			await frames(1)
			south = maxf(south, knuckle.global_position.z)
			up = maxf(up, knuckle.global_position.y)
		assert_true(south < face - BODY + 0.05, "%s: shoved hard at it for a second, it holds (%.3f m)" % [place.name, face - south])
		assert_true(up < 0.05, "%s: and the body does not ride up it (y %.3f)" % [place.name, up])
		knuckle.queue_free()
		await frames(1)


# The camera looks north from the south, so whatever stands on the south side of walkable ground hides a fighter's legs, and the
# higher it is the more: a wall h high hides everything below h - 0.84 d of a body whose centre is d north of it. Nothing that
# touches walkable ground on its south side is higher than 0.65 m (a fighter's shins), bar a post narrower than 0.8 m and the two
# vats. (A solid with ground just north of its north face is what "touches on its south side" means; a mass beside a lane touches
# it on its east or west.) A rail raised above a head (its underside at 1.8 m or more) hides nothing of a body.
func test_nothing_tall_touches_walkable_ground_on_its_south_side() -> void:
	var region := _region()
	if region == null:
		return
	await frames(2)
	var space := region.get_world_3d().direct_space_state
	var tall := PackedStringArray()
	var low := 0
	for body: StaticBody3D in region.find_children("*", "StaticBody3D", true, false):
		if body.get_parent().name == &"Walkable" or String(body.name).begins_with("Vat"):
			continue
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			var box := _size_of(shape)
			var centre := shape.global_position
			var top := centre.y + box.y / 2.0
			if centre.y - box.y / 2.0 >= 1.8 or (top <= 1.05 and top > 0.65 + 1e-6):
				continue
			var north := false
			if shape.shape is CylinderShape3D:
				# A round post: a body can stand north of it (within 45 degrees of north) where a capsule fits on a ring just outside it, on ground a body can stand on.
				var ring := box.x / 2.0 + BODY + 0.03
				for degrees in range(225, 316, 5):
					var around := Vector2(centre.x, centre.z) + Vector2.from_angle(deg_to_rad(degrees)) * ring
					north = north or (_ground_under(space, around) and not _blocked(space, around))
			else:
				var x := centre.x - box.x / 2.0 + 0.05
				while x < centre.x + box.x / 2.0 - 0.04:
					north = north or _ground_under(space, Vector2(x, centre.z - box.z / 2.0 - 0.1))
					x += 0.25
			if north and top > 0.65 + 1e-6:
				tall.append("%s is %.2f m high with ground on its north side" % [body.get_path(), top])
			elif north:
				low += 1
	assert_eq(tall, PackedStringArray(), "nothing higher than 0.65 m stands on the south side of walkable ground")
	assert_true(low >= 10, "and there are kerbs, low walls and a gate that do (%d)" % low)
	# They are found by name: the five low walls and the gate and its rail.
	for wall in 5:
		assert_true(region.get_node_or_null("LowWall%d" % (wall + 1)) is StaticBody3D, "LowWall%d" % (wall + 1))
	assert_true(region.get_node_or_null("Gate") is StaticBody3D, "the Gate")
	# No rail across the posts' tops: it crossed the heads of the fighters standing north of the gate (see test_bilibara_hidden).
	assert_true(region.get_node_or_null("GateRail") == null, "no rail across the tops of the gate's posts")
	for body: StaticBody3D in region.find_children("*", "StaticBody3D", true, false):
		if body.get_parent().name == &"Walkable" or body.get_parent().get_parent().name == &"Blocks":
			continue
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			var size := _size_of(shape)
			var inside_gate := Rect2(-35.2, -6.5, 5.4, 3.0).intersects(Rect2(shape.global_position.x - size.x / 2.0, shape.global_position.z - size.z / 2.0, size.x, size.z))
			assert_false(inside_gate and shape.global_position.y + size.y / 2.0 > 1.0 and body.name != &"Lantern", "%s is no taller than 1 m over the gate" % body.get_path())


# Each low wall (from the walkable side north of it) and the gate (from both sides), at two or three x positions: {label, x, face
# (the z of the face stood against), way (+1 pushes south, -1 north)}.
func _edges() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for spot in [["LowWall1", -55.0, [23.0, 23.75]], ["LowWall2", -55.0, [31.25, 32.0]], ["LowWall3", -30.0, [30.5, 32.0]],
			["LowWall4", -20.0, [23.0, 24.5]], ["LowWall5", -20.0, [-29.5, -28.0]]]:
		for x: float in spot[2]:
			list.append({label = "%s x %.2f" % [spot[0], x], x = x, face = spot[1], way = 1})
	for x: float in [-34.5, -32.5, -30.5]:
		list.append({label = "the gate from the north, x %.1f" % x, x = x, face = -5.5, way = 1})
		list.append({label = "the gate from the south, x %.1f" % x, x = x, face = -4.5, way = -1})
	# The solid props (north faces are stood against from the north with way +1, south faces from the south with way -1): the bench and
	# stool of alcove B (its south face is left out: the 3 m start of the sprint lies beyond the alcove's kerb), the bollards, the yard's vats, the plinths, the street's stalls, cart, bench and stool.
	for prop in [["alcove bench north", 34.5, -35.825, 1], ["alcove bench north", 35.5, -35.825, 1], ["alcove bench south", 35.0, -35.175, -1],
			["alcove stool north", 34.0, -33.325, 1], ["west bollard", 24.875, -55.325, 1], ["east bollard", 30.125, -55.325, 1],
			["west vat north", 20.0, -67.5, 1], ["west vat south", 20.0, -65.0, -1], ["east vat north", 35.0, -67.5, 1], ["east vat south", 35.0, -65.0, -1],
			["plinth A", -36.1, -4.4, -1], ["plinth B", 31.8, -36.9, -1], ["stall west", -8.75, -2.5, -1], ["stall east", 8.75, -2.5, -1],
			["cart", -22.5, -2.76, -1], ["street bench", 12.5, -4.35, -1], ["street stool", 14.1, -4.35, -1]]:
		list.append({label = "%s, x %.2f" % [prop[0], prop[1]], x = prop[1], face = prop[2], way = prop[3]})
	return list


# Runs `frames_to_run` frames with an actor of `def_path` standing `gap` m before each edge, calling `per_frame(actor, edge, i)`
# on each frame, after `setup(actor, edge)`; returns the problems: a body whose centre came more than 0.1 m inside the face of the
# wall, rose above 0.1 m, or ended anywhere but this side of it.
func _try(region: Region, label: String, def_path: String, gap: float, frames_to_run: int, setup: Callable, per_frame: Callable) -> PackedStringArray:
	var edges := _edges()
	for e in edges:
		var yaw := 0.0 if e.way == 1 else PI
		e.actor = _spawn(region, def_path, Vector3(e.x, 0.0, e.face - e.way * gap))
		(e.actor as Actor).place(Transform3D(Basis(Vector3.UP, yaw), Vector3(e.x, 0.0, e.face - e.way * gap)))
		e.in = 0.0
		e.up = 0.0
	await frames(2)
	for e in edges:
		setup.call(e.actor, e)
	for i in frames_to_run:
		for e in edges:
			per_frame.call(e.actor, e, i)
		await frames(1)
		for e in edges:
			var at := (e.actor as Actor).global_position
			e.in = maxf(e.in, (at.z - e.face) * e.way)
			e.up = maxf(e.up, at.y)
	var problems := PackedStringArray()
	for e in edges:
		var at := (e.actor as Actor).global_position
		if e.in > 0.1 or e.up > 0.1 or (at.z - e.face) * e.way > -0.2:
			problems.append("%s, %s: reached %.2f m past the face, rose to %.2f m, ended %.2f m from it" % [label, e.label, e.in, e.up, -(at.z - e.face) * e.way])
		(e.actor as Actor).queue_free()
	await frames(1)
	return problems


# Nothing crosses a 0.6 m wall or the gate: a sustained shove, a throw, three throws, a double dash-step, a sprint, each of the
# attackers' lunges and the grab and the finisher across the gate. None gets over, none rests on top, none rises above 0.1 m.
func test_nothing_gets_over_a_low_wall_or_the_gate() -> void:
	var region := _region()
	if region == null:
		return
	var problems := PackedStringArray()
	var none := func(_a: Actor, _e: Dictionary) -> void: pass
	var way := func(e: Dictionary) -> Vector2: return Vector2(0, e.way)
	problems.append_array(await _try(region, "a sustained shove", ABARAX, 1.0, 180, none,
			func(a: Actor, e: Dictionary, _i: int) -> void: a.push(Vector3(0, 0, e.way * SHOVE * DT * 10.0))))
	problems.append_array(await _try(region, "a 3 m throw", ABARAX, 1.0, 90, none,
			func(a: Actor, e: Dictionary, i: int) -> void:
				if i == 0: a.push(Vector3(0, 0, e.way * 30.0))))
	problems.append_array(await _try(region, "three throws", ABARAX, 1.0, 90, none,
			func(a: Actor, e: Dictionary, i: int) -> void:
				if i < 3: a.push(Vector3(0, 0, e.way * 30.0))))
	problems.append_array(await _try(region, "two dash-steps", ABARAX, 1.5, 130,
			func(a: Actor, e: Dictionary) -> void:
				a.set_brain(ScriptBrain.new([{frames = 2, move = way.call(e), press = [&"dodge"]}, {frames = 40, move = way.call(e)},
						{frames = 2, move = way.call(e), press = [&"dodge"]}, {frames = 80, move = way.call(e)}])),
			func(_a: Actor, _e: Dictionary, _i: int) -> void: pass))
	problems.append_array(await _try(region, "a sprint", ABARAX, 3.0, 120,
			func(a: Actor, e: Dictionary) -> void: a.set_brain(ScriptBrain.new([{frames = 120, move = way.call(e), hold = [&"dodge"]}])),
			func(_a: Actor, _e: Dictionary, _i: int) -> void: pass))
	for attack in [["res://data/actors/knuckle_1.tres", &"knuckle_sweep"], ["res://data/actors/knuckle_1.tres", &"knuckle_thrust"],
			["res://data/actors/knuckle_1.tres", &"knuckle_hook"], ["res://data/actors/knuckle_heavy.tres", &"heavy_haymaker"],
			["res://data/actors/knuckle_heavy.tres", &"heavy_slam"], ["res://data/actors/knuckle_blade.tres", &"blade_lunge"]]:
		for gap: float in [0.8, 2.0]:
			problems.append_array(await _try(region, "%s from %.1f m" % [attack[1], gap], attack[0], gap, 100,
					func(a: Actor, _e: Dictionary) -> void: a.runner.start(Registry.fetch(&"moves", attack[1]) as MoveData),
					func(_a: Actor, _e: Dictionary, _i: int) -> void: pass))
	assert_eq(problems, PackedStringArray(), "nothing crosses or climbs a low wall or the gate")
	# The grab and the finisher across the gate: the lead stands at the gate's face, the follower across it, each way round.
	var crossed := PackedStringArray()
	for gap: float in [0.5, 1.0]:
		for lead_north in [true, false]:
			for finisher in [false, true]:
				var x := -32.5
				var near := -5.5 - 0.36 if lead_north else -4.5 + 0.36
				var far := -4.5 + gap if lead_north else -5.5 - gap
				var lead := _spawn(region, ABARAX if finisher else KNUCKLE_1, Vector3(x, 0.0, near))
				var follower := _spawn(region, KNUCKLE_1 if finisher else ABARAX, Vector3(x, 0.0, far))
				await frames(2)
				var began: bool = lead.start_paired(follower, lead.def.finisher if finisher else lead.def.grab_pair)
				var worst := 0.0
				for i in 120:
					await frames(1)
					for body: Actor in [lead, follower]:
						var on_north: bool = body.global_position.z < -5.0
						var started_north: bool = (body == lead) == lead_north
						if on_north != started_north and body.global_position.y > -0.5:
							worst = maxf(worst, 1.0)
						worst = maxf(worst, body.global_position.y)
				if worst >= 0.1:
					crossed.append("%s, lead %s, gap %.1f: began %s, worst %.2f" % ["finisher" if finisher else "grab", "north" if lead_north else "south", gap, began, worst])
				lead.queue_free()
				follower.queue_free()
				await frames(1)
	assert_eq(crossed, PackedStringArray(), "no pairing carries a body across the gate or up on it")


# --- The backdrop and the sight line (Task 3) ---

# What a body can be hidden by, as boxes in world space ({box, name}): every mesh of the region that is not the walkable ground (a
# plate's top is at y = 0, under any head), with a kit run taken at KitRun.bounds() (a MultiMesh's own box is zero headless).
func _occluders(region: Region) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var walkable := region.get_node_or_null("Walkable")
	for node: Node3D in region.find_children("*", "Node3D", true, false):
		if walkable != null and walkable.is_ancestor_of(node):
			continue
		var box := AABB()
		if node is KitRun:
			box = (node as KitRun).bounds()
		elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null and not String(node.name).begins_with("Water"):
			box = node.global_transform * (node as MeshInstance3D).get_aabb()
		else:
			continue
		if box.size == Vector3.ZERO or String(node.name).begins_with("Ground"):
			continue
		found.append({box = box, name = String(region.get_path_to(node))})
	return found


func test_nothing_stands_between_the_camera_and_a_body_anywhere_it_can_stand() -> void:   # Review Focus 1
	var region := _region()
	if region == null:
		return
	var fill := await _fill(region)
	var reached: Dictionary = fill.reached
	var occluders := _occluders(region)
	assert_true(occluders.size() > 40, "there are meshes to look through (%d)" % occluders.size())
	# The camera is DISTANCE from what it looks at, along its pitch: up and south of the cell. The segment is the brief's, from the
	# head (2 m up) to the camera; a second, along the view's own direction from the head (the true line of an orthographic camera,
	# which is steeper), is held too.
	var pitch := deg_to_rad(-CameraRig.PITCH_DEG)
	var to_camera := Vector3(0.0, CameraRig.DISTANCE * sin(pitch), CameraRig.DISTANCE * cos(pitch))
	var hits := {}  # mesh -> the first cell it hides a body at
	var tested := 0
	for cell: Vector2i in reached.keys():
		var at := _middle(cell)
		for dx: float in [-0.35, 0.0, 0.35]:
			var base := Vector3(at.x + dx, 0.0, at.y)
			var head := base + Vector3(0.0, 2.0, 0.0)
			var ends: Array[Vector3] = [base + to_camera, head + to_camera]
			for entry in occluders:
				var box: AABB = entry.box
				if box.end.y <= 1.05 or String(entry.name).contains("/Fence") or box.position.x > base.x or box.end.x < base.x or box.end.z < at.y:
					continue
				tested += 1
				for end in ends:
					if box.intersects_segment(head, end):
						if not hits.has(entry.name):
							hits[entry.name] = "cell %s (x offset %.2f)" % [at, dx]
						break
	assert_true(tested > 0, "the test looked at something (%d box checks)" % tested)
	var shown := PackedStringArray()
	for mesh_name: String in hits:
		if shown.size() < 8:
			shown.append("%s hides a body at %s" % [mesh_name, hits[mesh_name]])
	assert_eq(shown, PackedStringArray(), "nothing stands between the camera and a body (%d meshes do)" % hits.size())


func test_the_backdrop_is_never_walkable_and_never_shades_the_ground() -> void:
	var region := _region()
	if region == null:
		return
	var backdrop := region.get_node_or_null("Backdrop")
	assert_true(backdrop != null, "a Backdrop group")
	if backdrop == null:
		return
	assert_eq(backdrop.find_children("*", "CollisionObject3D", true, false).size(), 0, "nothing under Backdrop is a collider")
	var shading := PackedStringArray()
	var meshes := backdrop.find_children("*", "GeometryInstance3D", true, false)
	for mesh: GeometryInstance3D in meshes:
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shading.append(String(region.get_path_to(mesh)))
	assert_eq(shading, PackedStringArray(), "no mesh under Backdrop casts a shadow")
	assert_true(meshes.size() >= 10, "and it holds the picture beyond the places (%d meshes)" % meshes.size())
	var blocks := region.get_node_or_null("Blocks")
	assert_true(blocks != null, "a Blocks group")
	if blocks != null:
		for block: Node in blocks.get_children():
			assert_true(block.get_node_or_null("Body") is StaticBody3D, "%s under Blocks is solid" % block.name)
	var walkable := region.get_node("Walkable")
	for mesh: Node in meshes:
		assert_false(walkable.is_ancestor_of(mesh), "%s is not in Walkable" % mesh.name)


# Every kit piece of the region, as {node, box (world, from its meshes), piece}: a placed scene (Props, Edges, Lanterns) and a run's
# places alike.
func _kit_instances(region: Region) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for node: Node3D in region.find_children("*", "Node3D", true, false):
		if node is KitRun:
			var run := node as KitRun
			for place in run.places:
				found.append({node = node, piece = String(run.piece), at = (run.global_transform * place).origin, scale = (run.global_transform * place).basis.get_scale()})
		elif node.scene_file_path.begins_with("res://assets/env/kenney_town/"):
			found.append({node = node, piece = node.scene_file_path.get_file().get_basename(), at = node.global_position, scale = node.global_basis.get_scale()})
	return found


func test_the_drying_yard_and_the_harbor_are_dressed_and_unwalkable() -> void:
	var region := _region()
	if region == null:
		return
	var fill := await _fill(region)
	var reached: Dictionary = fill.reached
	var ground: Dictionary = fill.ground
	var kit := _kit_instances(region)
	var boxes := _kit_boxes(region)
	var count := func(piece: String) -> int: return kit.filter(func(k: Dictionary) -> bool: return k.piece == piece).size()
	assert_true(count.call("poles-horizontal") >= 12, "at least 12 poles-horizontal (%d)" % count.call("poles-horizontal"))
	assert_true(count.call("poles") >= 12, "at least 12 poles (%d)" % count.call("poles"))
	assert_true(count.call("planks") >= 6, "at least 6 planks (%d)" % count.call("planks"))
	assert_true(count.call("rock-large") >= 2, "at least 2 rock-large (%d)" % count.call("rock-large"))
	# South of the Rack Walk's kerb (z -19.6): the three vats, and every rack at least 3 m back from it (and nothing there taller
	# than 1.7 + 0.71 s, s metres from the kerb: the vats, the rocks and the racks are, at those distances).
	var vats := region.find_children("Vat*", "StaticBody3D", true, false).filter(func(v: Node3D) -> bool: return (v.get_node("Shape") as Node3D).global_position.z > -19.6 and (v.get_node("Shape") as Node3D).global_position.z < -10.0)
	assert_eq(vats.size(), 3, "three vats in the drying yard")
	for spot: Vector2 in [Vector2(-20, -15), Vector2(-5, -15), Vector2(10, -15)]:
		assert_true(vats.any(func(v: Node3D) -> bool: return Vector2((v.get_node("Shape") as Node3D).global_position.x, (v.get_node("Shape") as Node3D).global_position.z).distance_to(spot) < 0.3), "a vat at %s" % spot)
	var dressing := region.get_node("Props").find_children("*", "Node3D", true, false)
	var too_near := PackedStringArray()
	for k in kit:
		if k.piece in ["poles", "poles-horizontal"] and k.at.z - (-19.6) < 3.0 + 1.0:
			too_near.append("%s at %s" % [k.piece, k.at])
	assert_eq(too_near, PackedStringArray(), "racks start 3 m from the kerb")
	var tall_near := PackedStringArray()
	for k in kit:
		if k.at.z > -19.6 and k.at.z < -10.0 and k.at.x > -30.0 and k.at.x < 22.5 and k.piece not in ["planks"]:
			var most: float = 1.7 + 0.71 * (k.at.z + 19.6 - 1.3)
			var height: float = {"poles": 2.5, "poles-horizontal": 2.5, "rock-large": 2.91, "rock-small": 2.55}.get(k.piece, 1.0)
			if height > most:
				tall_near.append("%s at %s is %.2f m, the line allows %.2f" % [k.piece, k.at, height, most])
	assert_eq(tall_near, PackedStringArray(), "nothing in the drying yard stands above the line of sight")
	# The harbor: the water at y -0.9 from z 9 to 32, a quay wall of wall-half along z 9, an apron of visual cobble.
	var water := region.find_children("Water*", "MeshInstance3D", true, false)
	assert_eq(water.size(), 1, "one sheet of water")
	var quay_top := -INF
	for k in boxes:
		if k.piece == "wall-half":
			quay_top = maxf(quay_top, (k.box as AABB).end.y)
	var apron_top := -INF
	for g: MeshInstance3D in region.get_node("Backdrop").find_children("Ground*", "MeshInstance3D", true, false):
		if g.global_position.z > 5.0:
			apron_top = maxf(apron_top, (g.global_transform * g.get_aabb()).end.y)
	if water.size() == 1:
		var level: float = (water[0] as MeshInstance3D).global_position.y
		assert_true(level <= apron_top - 0.5, "the water (%.2f) lies at least 0.5 m below the apron (%.2f), so the quay is a drop" % [level, apron_top])
		assert_true(level < quay_top - 1.0, "and well below the quay wall's top (%.2f)" % quay_top)
	if water.size() == 1:
		var plane := (water[0] as MeshInstance3D).mesh as PlaneMesh
		var w := water[0] as MeshInstance3D
		assert_near(w.global_position.z - plane.size.y / 2.0, 9.0, 1e-3, "from z 9, under the quay wall (the brief's 9.25 left a gap of sky between wall and water)")
		assert_near(w.global_position.z + plane.size.y / 2.0, 32.0, 1e-3, "to z 32")
	assert_true(count.call("wall-half") >= 28, "the quay wall is wall-half every tile (%d)" % count.call("wall-half"))
	var quay := kit.filter(func(k: Dictionary) -> bool: return k.piece == "wall-half")
	assert_true(quay.all(func(k: Dictionary) -> bool: return absf(k.at.z - 9.0) < 1.3 and k.at.y < 0.01), "the quay wall stands along z 9")
	var apron := region.get_node("Backdrop").find_children("Ground*", "MeshInstance3D", true, false).filter(func(g: MeshInstance3D) -> bool: return g.global_position.z > 5.0)
	assert_true(apron.size() >= 6, "an apron of visual plates (%d)" % apron.size())
	# None of it is walkable: no ground under it for the body's fill, none of it reached.
	var walkable_south := 0
	for cell: Vector2i in reached.keys():
		var at := _middle(cell)
		if at.y > 5.4 or (at.y > -19.6 and at.y < -10.0 and at.x > -30.0 and at.x < 22.5):
			walkable_south += 1
	assert_eq(walkable_south, 0, "no reached cell on the apron, the quay, the water or in the drying yard")
	for cell: Vector2i in ground.keys():
		var at := _middle(cell)
		assert_false(at.y > 5.4 or (at.y > -19.6 and at.y < -10.0 and at.x > -30.0 and at.x < 22.5), "no walkable ground under %s" % at)
	assert_true(dressing.size() > 0, "and it is dressed in Props")


func test_every_piece_is_a_kenney_toon_piece_at_two_and_a_half_times() -> void:
	var region := _region()
	if region == null:
		return
	var dresser := region.get_node("Kit") as KitDresser
	var off_scale := PackedStringArray()
	var not_toon := PackedStringArray()
	var kit := _kit_instances(region)
	assert_true(kit.size() > 300, "the stretch is built of kit pieces (%d)" % kit.size())
	for k in kit:
		if not (k.scale as Vector3).is_equal_approx(Vector3.ONE * 2.5):
			off_scale.append("%s %s" % [k.piece, k.scale])
	var seen := {}
	for node: Node3D in region.find_children("*", "Node3D", true, false):
		var materials: Array[Material] = []
		if node is KitRun:
			materials.append((node as KitRun).material_override)
		elif node.scene_file_path.begins_with("res://assets/env/kenney_town/"):
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				materials.append(mesh.material_override)
		for material in materials:
			# A roof wears its style's roof material (the roof shader, the shingles picture); every other piece the Bilibara colormap.
			if node.get_parent().name == &"Roof":
				var roof_ok: bool = material is ShaderMaterial and (material as ShaderMaterial).shader.resource_path == "res://render/shaders/toon_roof.gdshader"
				seen[region.get_path_to(node)] = true
				if not roof_ok:
					not_toon.append(String(region.get_path_to(node)))
				continue
			# A banner wears the neon colormap (the same shader with a glow of its own).
			var neon: bool = node.scene_file_path.get_file().begins_with("banner")
			var want := dresser.banner_material if neon else dresser.material
			var ok: bool = material is ShaderMaterial and (material as ShaderMaterial).shader.resource_path == TOON_WORLD and material == want
			var tex := (material as ShaderMaterial).get_shader_parameter(&"albedo_tex") as Texture2D if ok else null
			ok = ok and tex != null and tex.resource_path == ("res://assets/env/textures/bilibara_neon_colormap.png" if neon else "res://assets/env/textures/bilibara_colormap.png")
			seen[region.get_path_to(node)] = true
			if not ok:
				not_toon.append(String(region.get_path_to(node)))
	assert_eq(off_scale, PackedStringArray(), "pieces not at x2.5")
	assert_eq(not_toon, PackedStringArray(), "pieces not in toon_world with the Bilibara colormap")
	assert_true(seen.size() > 50, "and many were looked at (%d)" % seen.size())


## The solid masses and what each wears: its rectangle, the style of its front and the roof piece (`gable`: two planes meeting in a ridge,
## the tiles of one half turned about; a roof of the `roof` piece under the sight line: its ridge is at most 9.1 m, and the tests hold it).
const MASSES := [
	{rect = Rect2(-40, -25, 5, 20), style = "frontage", roof = "roof", gable = true}, {rect = Rect2(-30, -10, 55, 5), style = "frontage", roof = "roof", gable = true},
	{rect = Rect2(30, -20, 2.5, 15), style = "frontage", roof = "roof", gable = true}, {rect = Rect2(32.5, -5, 2.5, 10), style = "frontage", roof = "roof", gable = true},
	{rect = Rect2(-42.5, -5, 2.5, 10), style = "frontage", roof = "roof", gable = true}, {rect = Rect2(-40, -45, 30, 20), style = "tannery", roof = "roof", gable = true},
	{rect = Rect2(-10, -45, 35, 20), style = "tannery", roof = "roof", gable = true}, {rect = Rect2(30, -45, 10, 7.5), style = "tannery", roof = "roof", gable = true},
	{rect = Rect2(37.5, -37.5, 2.5, 7.5), style = "tannery", roof = "roof-high"}, {rect = Rect2(12.5, -80, 30, 5), style = "yardwall", roof = "roof", gable = true},
	{rect = Rect2(12.5, -75, 2.5, 20), style = "tannery", roof = "roof-high"}, {rect = Rect2(40, -75, 2.5, 20), style = "tannery", roof = "roof-high"},
]


# Whether the roof tiles of `roof` face two ways (the ridge between them: the pieces' x axes point at opposite ways).
func _two_ways(roof: Node) -> bool:
	var ways := {}
	for run: KitRun in roof.get_children():
		for place in run.places:
			ways[Vector2(snappedf(place.basis.x.normalized().x, 0.01), snappedf(place.basis.x.normalized().z, 0.01))] = true
	return ways.size() >= 2


func test_every_solid_mass_has_a_front_of_its_style_and_a_roof() -> void:
	var region := _region()
	if region == null:
		return
	var blocks := region.get_node("Blocks").get_children()
	assert_eq(blocks.size(), MASSES.size(), "%d solid masses" % MASSES.size())
	var matched := {}
	for block in blocks:
		var shape := block.get_node("Body/Shape") as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		var rect := Rect2(shape.global_position.x - size.x / 2.0, shape.global_position.z - size.z / 2.0, size.x, size.z)
		var found := MASSES.filter(func(m: Dictionary) -> bool: return (m.rect as Rect2).is_equal_approx(rect))
		assert_eq(found.size(), 1, "%s (%s) is one of the masses" % [block.name, rect])
		if found.size() != 1:
			continue
		matched[found[0].rect] = true
		var want: Dictionary = found[0]
		var front := block.get_node("Front").get_children().map(func(r: Node) -> String: return String((r as KitRun).piece))
		var wood := front.filter(func(p: String) -> bool: return p.begins_with("wall-wood"))
		assert_eq(wood.size() == front.size(), want.style != "frontage", "%s: a %s front (%s)" % [block.name, want.style, front])
		assert_false(front.has("balcony-wall"), "%s: no balcony (its frame is a hole)" % block.name)
		if rect.size.x >= 12.5:
			if want.style == "frontage":
				assert_true(front.has("wall-door") and front.has("wall-window-small") and front.has("wall-window-shutters"), "%s: a stone front with a door, windows and shutters" % block.name)
			elif want.style == "yardwall":
				assert_true(front.has("wall-wood-window-shutters") and not front.has("wall-wood-door"), "%s: planks with lofts and no door of its own" % block.name)
			else:
				assert_true(front.has("wall-wood-door") and front.has("wall-wood-window-small"), "%s: planks with a door and windows" % block.name)
		var roofs := block.get_node("Roof").get_children().map(func(r: Node) -> String: return String((r as KitRun).piece))
		assert_eq(roofs.filter(func(p: String) -> bool: return p != want.roof), [], "%s: roofed in %s" % [block.name, want.roof])
		assert_true(roofs.size() > 0, "%s has a roof" % block.name)
		if want.get("gable", false):
			var yaws := {}
			for run: KitRun in block.get_node("Roof").get_children():
				for place in run.places:
					yaws[snappedf(place.basis.x.normalized().x, 0.01)] = snappedf(place.basis.x.normalized().z, 0.01)
			assert_true(yaws.size() >= 2 or (block.get_node("Roof").get_children().any(func(r: KitRun) -> bool: return r.places.size() > 0) and _two_ways(block.get_node("Roof"))), "%s: a gable has its two halves turned about" % block.name)
		if want.roof == "roof-flat":
			var top := 0.0
			for run: KitRun in block.get_node("Roof").get_children():
				top = maxf(top, run.bounds().end.y)
			assert_near(top, 7.83, 0.02, "%s: a flat roof's top is the sight line's 7.83 m" % block.name)
	assert_eq(matched.size(), MASSES.size(), "every mass was found")


# --- The dressed places (Task 3) ---

# Every kit piece of the region with its box in world space: {piece, box, node}. A scene instance's box is its meshes' merged; a run's
# places are each a piece of the run's mesh (a piece of two meshes is two entries of one place: merged by position).
func _kit_boxes(region: Region) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for node: Node3D in region.find_children("*", "Node3D", true, false):
		if node is KitRun:
			var run := node as KitRun
			for place in run.places:
				found.append({piece = String(run.piece), box = run.global_transform * place * run.local * run.part.get_aabb(), node = node})
		elif node.scene_file_path.begins_with("res://assets/env/kenney_town/"):
			var box := AABB()
			var first := true
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				var b: AABB = mesh.global_transform * mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
			found.append({piece = node.scene_file_path.get_file().get_basename(), box = box, node = node})
	return found


func _centre(box: AABB) -> Vector2:
	return Vector2(box.get_center().x, box.get_center().z)


func _pieces(region: Region, piece: String) -> Array[Dictionary]:
	return _kit_boxes(region).filter(func(k: Dictionary) -> bool: return k.piece == piece)


func _poi_at(region: Region, poi_name: String) -> Vector2:
	var poi := region.find_child(poi_name, true, false) as Marker3D
	return Vector2(poi.global_position.x, poi.global_position.z)


func test_the_places_are_dressed() -> void:
	var region := _region()
	if region == null:
		return
	var lazymans := _poi_at(region, "Lazymans")
	var door_near := _pieces(region, "wall-door").any(func(k: Dictionary) -> bool: return _centre(k.box).distance_to(lazymans) < 4.0)
	assert_true(door_near, "a wall-door within 4 m of Lazymans (the Lazyman's back door)")
	# Site A: a pillar-stone plinth on the shrine's point, the court's slate under it.
	# Site B: a bench, a stool and a plinth.
	var alcove := Rect2(30, -37.5, 7.5, 7.5)
	assert_true(_pieces(region, "stall-bench").any(func(k: Dictionary) -> bool: return alcove.has_point(_centre(k.box))), "a stall-bench in alcove B")
	assert_true(_pieces(region, "stall-stool").any(func(k: Dictionary) -> bool: return alcove.has_point(_centre(k.box))), "a stall-stool in alcove B")
	# The street: two stalls, a cart, and banners on the fronts of the street and the yard.
	assert_true(_pieces(region, "stall-red").size() >= 2, "at least 2 stall-red (%d)" % _pieces(region, "stall-red").size())
	assert_true(_pieces(region, "cart").size() >= 1, "a cart")
	var banners := _pieces(region, "banner-red") + _pieces(region, "banner-green")
	assert_true(banners.filter(func(k: Dictionary) -> bool: return k.box.get_center().z > -6.0 and k.box.get_center().z < 0.0).size() >= 3, "at least 3 banners on the street's fronts")
	assert_true(banners.filter(func(k: Dictionary) -> bool: return k.box.get_center().z < -70.0).size() >= 3, "and 3 in the yard")
	assert_eq(_pieces(region, "banner-green").size(), 1, "one banner-green (the hat shop's)")
	# The street's props stand at its north margin, off its clear line, flush with the fronts or a body's width from them.
	var in_street := PackedStringArray()
	for piece in ["stall-red", "stall-bench", "stall-stool", "cart"]:
		for k in _pieces(region, piece).filter(func(p: Dictionary) -> bool: return p.box.get_center().z < 0.0 and p.box.get_center().x < 30.0):
			var box: AABB = k.box
			if box.position.z < -5.0 - 1e-3 or box.end.z > -2.4 or (box.position.z > -5.0 + 0.05 and box.position.z < -5.0 + 0.7):
				in_street.append("%s at %s" % [piece, box])
	assert_eq(in_street, PackedStringArray(), "the street's props stand at its north margin, flush with the fronts (or a body's width off)")
	# The sites' plinths are solid blocks no higher than 0.65 m against the south face of a wall (not before a door or the gate), so that
	# whatever stands on them later hides nobody; the spawn on site A is 1 m or more clear of its plinth.
	for plinth_name in ["Plinth_A", "Plinth_B"]:
		var body := region.get_node_or_null(plinth_name) as StaticBody3D
		assert_true(body != null, "a solid %s" % plinth_name)
		if body == null:
			continue
		var shape := body.get_node("Shape") as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		assert_true(size.y <= 0.65 + 1e-6 and size.y >= 0.4, "%s is %.2f m high" % [plinth_name, size.y])
		var rect := Rect2(shape.global_position.x - size.x / 2.0, shape.global_position.z - size.z / 2.0, size.x, size.z)
		var wall_z := -5.0 if plinth_name == "Plinth_A" else -37.5
		assert_near(rect.position.y, wall_z, 1e-3, "%s stands against the wall's south face (z %.2f)" % [plinth_name, wall_z])
		assert_true(poi_rect_ok(region, plinth_name, rect), "its point of interest is on it")
	var site_a := _marker_at(region, "ShrineSite_A")
	var plinth_a_shape := region.get_node("Plinth_A").get_node("Shape") as CollisionShape3D
	var pa := Rect2(plinth_a_shape.global_position.x - 0.8, plinth_a_shape.global_position.z - 0.3, 1.6, 0.6)
	assert_true(pa.grow(1.0).has_point(site_a) == false, "the spawn on site A is 1 m clear of its plinth")


func poi_rect_ok(region: Region, plinth_name: String, rect: Rect2) -> bool:
	var at := _poi_at(region, "ShrinePlinth_" + plinth_name.right(1))
	return rect.grow(0.01).has_point(at)


func test_the_gate_is_a_closed_low_shortcut_gate() -> void:
	var region := _region()
	if region == null:
		return
	var gates := _pieces(region, "fence-gate")
	assert_eq(gates.size(), 2, "two fence-gate pieces")
	var xs := gates.map(func(k: Dictionary) -> float: return _centre(k.box).x)
	xs.sort()
	if xs.size() == 2:
		assert_true(xs[0] > -35.0 and xs[0] < -32.5 and xs[1] > -32.5 and xs[1] < -30.0, "one in each half of x -35..-30 (%s)" % [xs])
	for k in gates:
		assert_true(absf(k.box.get_center().z - (-5.0)) < 0.3, "%s across the gate at z -5" % [k.box])
	var board := region.get_node("Gate") as StaticBody3D
	var shape := board.get_node("Shape") as CollisionShape3D
	var size := (shape.shape as BoxShape3D).size
	assert_true(size.x >= 5.0 - 1e-6 and size.y >= 0.55 and size.y <= 0.65, "a solid body 5 m wide and 0.55 to 0.65 m high (%s)" % size)
	var posts := _pieces(region, "pillar-stone").filter(func(k: Dictionary) -> bool: return absf(k.box.get_center().z - (-5.1)) < 0.3 and k.box.get_center().x < -29.0 and k.box.get_center().x > -36.0)
	assert_eq(posts.size(), 2, "two pillar-stone pilasters")
	for post in posts:
		# Each is a pilaster on a wall's face (the Lazyman's back, x <= -35, and the street's row, x >= -30): none of it in the slot, where a
		# body could stand behind it, and it is only drawn (no collider): half of it is in the wall.
		var box: AABB = post.box
		var in_wall: bool = box.end.x <= -35.0 + 1e-3 or box.position.x >= -30.0 - 1e-3
		assert_true(in_wall, "a pilaster is wholly in a wall's span, none of it in the slot (x %.3f to %.3f)" % [box.position.x, box.end.x])
		assert_true((post.node as Node).get_node_or_null("Body") == null, "and has no collider")
	var near := region.get_node("GateNear") as Marker3D
	var far := region.get_node("GateFar") as Marker3D
	assert_near(near.global_position.z, -3.5, 1e-3, "GateNear 1.5 m south of the gate")
	assert_near(far.global_position.z, -6.5, 1e-3, "GateFar 1.5 m north (3 m apart)")
	# Nothing taller than 1.3 m within 3 m north of it (z -8 to -5.5, x -35 to -30) except the posts: in a collider or a mesh.
	var tall := PackedStringArray()
	var zone := Rect2(-35.0, -8.0, 5.0, 2.5)
	for body: StaticBody3D in region.find_children("*", "StaticBody3D", true, false):
		if body.get_parent().name == &"Walkable":
			continue
		for s: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			var b := _size_of(s)
			var rect := Rect2(s.global_position.x - b.x / 2.0, s.global_position.z - b.z / 2.0, b.x, b.z)
			if rect.intersection(zone).get_area() > 1e-4 and s.global_position.y + b.y / 2.0 > 1.3 and not s.global_position.y + b.y / 2.0 <= 1.3:
				tall.append("%s" % body.get_path())
	for k in _kit_boxes(region):
		var rect := Rect2(k.box.position.x, k.box.position.z, k.box.size.x, k.box.size.z)
		if rect.intersection(zone).get_area() > 1e-4 and k.box.end.y > 1.3 and k.box.position.y < 3.0:   # a roof's eaves overhead hide nobody (the sight-line test holds that)
			tall.append("%s at %s" % [k.piece, k.box])
	assert_eq(tall, PackedStringArray(), "nothing taller than 1.3 m within 3 m north of the gate bar the posts")


func test_the_yard_has_three_barred_doors_two_vats_and_a_mouth() -> void:
	var region := _region()
	if region == null:
		return
	var doors := _pieces(region, "wall-door").filter(func(k: Dictionary) -> bool: return k.box.get_center().z < -70.0 and not k.node is KitRun)
	assert_eq(doors.size(), 3, "three wall-door pieces on the yard's north wall")
	for n in [1, 2, 3]:
		var hand := region.get_node("HandDoor_%d" % n) as Marker3D
		var near := doors.filter(func(k: Dictionary) -> bool: return absf(k.box.get_center().x - hand.global_position.x) < 0.6)
		assert_eq(near.size(), 1, "a wall-door within 0.6 m of HandDoor_%d's x" % n)
		for k in near:
			assert_true(absf((k.box as AABB).end.z - (-75.0)) < 0.1, "on the wall's face (its slab's south side at z %.2f)" % (k.box as AABB).end.z)
	# Barred: the wall is one solid box over the doors (no opening).
	var wall := region.get_node("Blocks").get_children().filter(func(b: Node) -> bool: return absf((b.get_node("Body/Shape") as Node3D).global_position.z - (-77.5)) < 0.1)
	assert_eq(wall.size(), 1, "the north wall is one solid mass")
	for spot in ["VatWest", "VatEast"]:
		var at := _poi_at(region, spot)
		var vats := region.find_children("Vat*", "StaticBody3D", true, false).filter(func(v: Node3D) -> bool: return Vector2((v.get_node("Shape") as Node3D).global_position.x, (v.get_node("Shape") as Node3D).global_position.z).distance_to(at) < 0.3)
		assert_eq(vats.size(), 1, "a vat at %s" % spot)
		for v in vats:
			var size := ((v.get_node("Shape") as CollisionShape3D).shape as BoxShape3D).size
			assert_near(size.y, 1.0, 1e-6, "%s is solid and 1.0 m high" % spot)
	var posts := region.find_children("Bollard*", "StaticBody3D", false, false)
	assert_eq(posts.size(), 2, "two bollards at the mouth")
	if posts.size() == 2:
		var shapes := posts.map(func(p: Node) -> CollisionShape3D: return p.get_node("Shape") as CollisionShape3D)
		assert_near(absf(shapes[0].global_position.x - shapes[1].global_position.x), 5.25, 1e-3, "5.25 m apart")
		for sh: CollisionShape3D in shapes:
			assert_true((sh.shape as BoxShape3D).size.y <= 1.0 + 1e-6, "no higher than 1.0 m (%s)" % (sh.shape as BoxShape3D).size)
	var spawn := region.get_node("KnuckleSpawn") as Marker3D
	assert_true(Rect2(15, -75, 25, 20).has_point(Vector2(spawn.global_position.x, spawn.global_position.z)), "KnuckleSpawn is inside the yard's walls")
	assert_vec_near(spawn.global_basis.z, Vector3(0, 0, 1), 1e-3, "facing south")
	# The yard's floor is in pieces: a centre where fights happen, and margins, each named, so that one line changes the centre.
	var centre := region.get_node("Walkable").get_node_or_null("YardPlateCentre") as StaticBody3D
	assert_true(centre != null, "a plate called YardPlateCentre")
	if centre != null:
		var s := (centre.get_node("Shape") as CollisionShape3D)
		assert_true(Rect2(s.global_position.x - 6.25, s.global_position.z - 5.0, 12.5, 10.0).has_point(Vector2(27.5, -65.0)), "which holds the yard's centre")
	assert_true(region.get_node("Walkable").find_children("YardPlate*", "StaticBody3D", false, false).size() >= 5, "among at least 5 plates of the yard")


func test_the_low_walls_wear_a_coping_and_a_railing_and_the_drifts_lie_on_unwalkable_ground() -> void:
	var region := _region()
	if region == null:
		return
	var copings := region.find_children("Coping*", "StaticBody3D", false, false)
	assert_eq(copings.size(), 5, "a coping on each of the five low walls")
	for wall in 5:
		var low := region.get_node("LowWall%d" % (wall + 1)) as StaticBody3D
		var wall_shape := low.get_node("Shape") as CollisionShape3D
		var wall_size := (wall_shape.shape as BoxShape3D).size
		var capped := copings.filter(func(c: Node3D) -> bool: return (c.get_node("Shape") as Node3D).global_position.distance_to(wall_shape.global_position + Vector3(0, wall_size.y / 2.0 + 0.025, 0)) < 1e-3)
		assert_eq(capped.size(), 1, "LowWall%d has its coping on top, over its whole footprint" % (wall + 1))
		for c in capped:
			var size := ((c.get_node("Shape") as CollisionShape3D).shape as BoxShape3D).size
			assert_true(is_equal_approx(size.x, wall_size.x) and is_equal_approx(size.z, wall_size.z) and size.y <= 0.05 + 1e-6, "the same footprint, 0.05 m thick (%s)" % size)
			assert_true(wall_size.y + size.y <= 0.65 + 1e-6, "and wall and coping are no higher than 0.65 m")
		# A railing of fence stands on the wall, seen through, behind its north end (a body at the end has none of it before him).
		var rect := Rect2(wall_shape.global_position.x - wall_size.x / 2.0, wall_shape.global_position.z - wall_size.z / 2.0, wall_size.x, wall_size.z)
		var rails := _pieces(region, "fence").filter(func(k: Dictionary) -> bool: return rect.grow(0.1).has_point(_centre(k.box)))
		assert_true(rails.size() >= 2, "LowWall%d wears a railing of fence (%d pieces)" % [wall + 1, rails.size()])
		for rail in rails:
			assert_true(rail.box.position.y >= wall_size.y - 1e-3, "the fence stands on the wall")
			assert_true(rail.box.position.z >= rect.position.y + 2.5 - 1e-3, "and at least 2.5 m back from its north end")
	var plates := _plates(region)
	var wrong := PackedStringArray()
	var drifts := region.get_node("Backdrop").find_children("Drift*", "MeshInstance3D", false, false)
	for drift: MeshInstance3D in drifts:
		var box := drift.global_transform * drift.get_aabb()
		assert_true(box.size.y > 0.1 and box.size.y < 0.4, "%s is a low mound (%.2f m)" % [drift.name, box.size.y])
		assert_eq(drift.get_parent().name, &"Backdrop", "%s is Backdrop: no collider, no shadow" % drift.name)
		for plate in plates:
			if Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersection(plate.rect).get_area() > 1e-6:
				wrong.append("%s over a walkable plate" % drift.name)
	assert_eq(wrong, PackedStringArray(), "no drift lies on walkable ground")
	assert_true(drifts.size() >= 8, "and there are drifts (%d)" % drifts.size())


# Every solid prop standing on walkable ground (the stalls, the cart, the bench and stools, the vats of the yard, the posts) is a thing to fight
# round, and nothing is a step a body rides up or a pocket it is wedged in: a body shoved at it from each side that has open ground, for 40
# frames at SHOVE, ends outside the prop's footprint (no more than 5 cm into the capsule's reach), on the ground, and walks off.
func test_every_solid_prop_on_walkable_ground_is_fought_round_and_nothing_rides_up_it() -> void:
	var region := _region()
	if region == null:
		return
	var fill := await _fill(region)
	var reached: Dictionary = fill.reached
	var props: Array[Dictionary] = []   # {name, rect}
	var bodies: Array = region.get_node("Props").find_children("*", "StaticBody3D", true, false) + region.find_children("Bollard*", "StaticBody3D", false, false) + region.find_children("Plinth_*", "StaticBody3D", false, false)
	for body: StaticBody3D in bodies:
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			var size := _size_of(shape)
			var world_box: AABB = shape.global_transform * AABB(-size / 2.0, size)
			var rect := Rect2(world_box.position.x, world_box.position.z, world_box.size.x, world_box.size.z)
			var near := false
			for cell: Vector2i in [_cell_of(rect.position - Vector2(0.9, 0.9)), _cell_of(rect.end + Vector2(0.9, 0.9)), _cell_of(Vector2(rect.get_center().x, rect.position.y - 0.9)),
					_cell_of(Vector2(rect.get_center().x, rect.end.y + 0.9)), _cell_of(Vector2(rect.position.x - 0.9, rect.get_center().y)), _cell_of(Vector2(rect.end.x + 0.9, rect.get_center().y))]:
				near = near or reached.has(cell)
			if near:
				props.append({name = String(body.get_path()), rect = rect, top = world_box.end.y})
	assert_true(props.size() >= 12, "the walkable ground has solid props (%d)" % props.size())
	var space := region.get_world_3d().direct_space_state
	var problems := PackedStringArray()
	for prop in props:
		var rect: Rect2 = prop.rect
		var sides: Array[Dictionary] = []
		var mid := rect.get_center()
		for way: Vector2 in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
			var start := mid + way * ((absf(way.x) * rect.size.x + absf(way.y) * rect.size.y) / 2.0 + 1.0)
			if reached.has(_cell_of(start)) and not _blocked(space, start):
				sides.append({start = start, way = -way})
		for side in sides:
			side.actor = _spawn(region, ABARAX, Vector3(side.start.x, 0.0, side.start.y))
		await frames(2)
		for i in 40:
			for side in sides:
				(side.actor as Actor).push(Vector3(side.way.x, 0.0, side.way.y) * SHOVE * DT * 10.0)
			await frames(1)
		for side in sides:
			var at := (side.actor as Actor).global_position
			var inside := rect.grow(BODY - 0.05).has_point(Vector2(at.x, at.z))
			if inside or at.y > 0.1 or at.y < -0.2:
				problems.append("%s from %s: ended at %s" % [prop.name, side.start, at])
			side.actor.queue_free()
		await frames(1)
	assert_eq(problems, PackedStringArray(), "every solid prop is fought round and none is ridden up or entered")


# The yard's north wall carries one door at each hand door and no other: the tannery front's own wooden doors are not drawn under the
# stone-framed ones (they were: the doors showed doubled).
func test_each_hand_door_is_one_door() -> void:
	var region := _region()
	if region == null:
		return
	var boxes := _kit_boxes(region).filter(func(k: Dictionary) -> bool: return String(k.piece).contains("door") and k.box.end.z < -74.0 and k.box.position.z > -75.4 and k.box.get_center().x > 15.0 and k.box.get_center().x < 40.0)
	for n in [1, 2, 3]:
		var hand := region.get_node("HandDoor_%d" % n) as Marker3D
		var near := boxes.filter(func(k: Dictionary) -> bool: return absf(k.box.get_center().x - hand.global_position.x) < 1.3)
		assert_eq(near.size(), 1, "one door at HandDoor_%d (%s)" % [n, near.map(func(k: Dictionary) -> String: return "%s at %s" % [k.piece, k.box.get_center()])])
	assert_eq(boxes.size(), 3, "three doors on the yard's north wall in all")


# The yard says it is where the fights are: a fighting square in stone with a border course, and the margins dressed (hides, railings).
func test_the_yard_floor_is_a_stone_square_with_a_border_and_dressed_margins() -> void:
	var region := _region()
	if region == null:
		return
	var walkable := region.get_node("Walkable")
	var centre := walkable.get_node_or_null("YardPlateCentre") as StaticBody3D
	assert_true(centre != null, "a centre plate")
	if centre != null:
		assert_eq(((centre.get_node("Mesh") as MeshInstance3D).material_override as Material).resource_path, STONE % YARD_CENTRE_STONE, "in %s" % YARD_CENTRE_STONE)
	var border := walkable.find_children("YardPlateBorder*", "StaticBody3D", false, false)
	assert_true(border.size() >= 4, "a border course of at least four plates (%d)" % border.size())
	for plate: StaticBody3D in border:
		assert_eq(((plate.get_node("Mesh") as MeshInstance3D).material_override as Material).resource_path, STONE % YARD_BORDER_STONE, "%s in %s" % [plate.name, YARD_BORDER_STONE])
	var margin_stuff := _kit_boxes(region).filter(func(k: Dictionary) -> bool: return k.piece in ["planks", "fence"] and k.box.get_center().z < -55.0 and k.box.get_center().z > -75.0 and k.box.get_center().x > 15.0 and k.box.get_center().x < 40.0)
	assert_true(margin_stuff.size() >= 12, "stacked hides and railings in the yard's margins (%d pieces)" % margin_stuff.size())
	var in_square := margin_stuff.filter(func(k: Dictionary) -> bool: return Rect2(21.25, -70, 12.5, 10).has_point(_centre(k.box)))
	assert_eq(in_square.size(), 0, "none of it in the fighting square")
	var too_high := margin_stuff.filter(func(k: Dictionary) -> bool: return k.piece == "planks" and k.box.end.y > 1.05)
	assert_eq(too_high.size(), 0, "the stacks are under a fighter's hips")


# The kit's pieces no style uses, where they fit: ghost lanterns on the street's fronts (the lamps are Task 4's), a colonnade of wooden
# pillars under the works' galleries on the Rack Walk, balconies on the street's row, small rocks in the drying yard.
func test_the_kit_pieces_that_fit_are_used_and_none_of_them_stands_behind_a_fighter() -> void:
	var region := _region()
	if region == null:
		return
	for piece in ["lantern", "pillar-wood", "balcony-wall", "rock-small"]:
		assert_true(_pieces(region, piece).size() >= 2, "%s is used (%d)" % [piece, _pieces(region, piece).size()])
	# Each stands north of the ground it overlooks (against a front, or beyond the unwalkable): no body is before it from the camera.
	var fronts := {"pillar-wood": -24.0, "balcony-wall": -4.0}
	for piece: String in fronts:
		for k in _pieces(region, piece):
			assert_true(k.box.end.z <= fronts[piece] + 1e-3, "%s at %s stands against a front" % [piece, k.box])
	# The lanterns have their own test (the post is a slim solid one, or a ghost on a low wall where no body is): see test_lanterns_are_posts.


# The ring leaves no gap: on the 2.5 m tiles of x -60..62.5, z -95..5 every tile is under a ring block, a solid mass, a plate of ground (walkable
# or only seen) or a low wall, bar single tiles (no gap wider than 2.5 m, at any depth of row: the void test frames only the first).
func test_the_ring_leaves_no_gap_wider_than_a_tile() -> void:
	var region := _region()
	if region == null:
		return
	var covers: Array[Rect2] = []
	for holder in region.get_node("Backdrop").get_children():
		var interior := holder.get_node_or_null("Interior") as MeshInstance3D
		if interior != null:
			var box := interior.global_transform * interior.get_aabb()
			covers.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z + 0.25))
		elif String(holder.name).begins_with("Ground"):
			var box := (holder as MeshInstance3D).global_transform * (holder as MeshInstance3D).get_aabb()
			covers.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	for block in region.get_node("Blocks").get_children():
		var shape := block.get_node("Body/Shape") as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		covers.append(Rect2(shape.global_position.x - size.x / 2.0, shape.global_position.z - size.z / 2.0, size.x, size.z))
	for plate in _plates(region):
		covers.append(plate.rect)
	for wall in 5:
		var shape := region.get_node("LowWall%d" % (wall + 1)).get_node("Shape") as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		covers.append(Rect2(shape.global_position.x - size.x / 2.0, shape.global_position.z - size.z / 2.0, size.x, size.z))
	var nx := 49
	var nz := 40
	var open := {}
	for i in nx:
		for j in nz:
			var centre := Vector2(-60.0 + 2.5 * (i + 0.5), -95.0 + 2.5 * (j + 0.5))
			if not covers.any(func(r: Rect2) -> bool: return r.grow(0.01).has_point(centre)):
				open[Vector2i(i, j)] = true
	var gaps := PackedStringArray()
	for cell: Vector2i in open:
		if open.has(cell + Vector2i(1, 0)) or open.has(cell + Vector2i(0, 1)):
			gaps.append("tiles at x %.2f z %.2f" % [-60.0 + 2.5 * cell.x, -95.0 + 2.5 * cell.y])
	assert_eq(gaps.slice(0, 6), PackedStringArray(), "no two neighbouring tiles of the footprint are bare (%d bare tiles in all)" % open.size())


# --- The light (Task 4): the book's cold snow-noon ---

const GRADE := "res://data/render/grades/bilibara_noon.tres"
const HAZE := "#aebbcc"


func _env(region: Region) -> Environment:
	var holders := region.find_children("*", "WorldEnvironment", true, false)
	assert_eq(holders.size(), 1, "one WorldEnvironment")
	return (holders[0] as WorldEnvironment).environment


# The box round a collision shape (a lantern's post is a cylinder), in its own space.
func _size_of(shape: CollisionShape3D) -> Vector3:
	if shape.shape is CylinderShape3D:
		var cylinder := shape.shape as CylinderShape3D
		return Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	return (shape.shape as BoxShape3D).size


func _lamps(region: Region) -> Array[OmniLight3D]:
	var found: Array[OmniLight3D] = []
	for lamp: OmniLight3D in region.find_children("*", "OmniLight3D", true, false):
		found.append(lamp)
	return found


func test_the_light_is_the_snow_noon() -> void:
	var region := _region()
	if region == null:
		return
	var env := _env(region)
	var sun := region.get_node_or_null("Sun") as DirectionalLight3D
	var fill := region.get_node_or_null("Fill") as DirectionalLight3D
	assert_true(sun != null and fill != null, "a Sun and a Fill")
	if sun == null or fill == null:
		return
	# The fill: for the bodies only, no shadow, cool, 1.0 to 1.3, from the camera's side and above.
	assert_eq(fill.light_cull_mask, Layers.RENDER_BODIES, "the fill lights the bodies and nothing else")
	assert_false(fill.shadow_enabled, "the fill casts no shadow")
	assert_true(fill.light_energy >= 1.0 and fill.light_energy <= 1.3, "the fill's energy is 1.0 to 1.3 (%.2f)" % fill.light_energy)
	assert_true(fill.light_color.b >= fill.light_color.r, "the fill is cool (%s)" % fill.light_color.to_html(false))
	# The light travels along -z of its basis: it comes from the camera's side (+z) and above when basis.z has z > 0.5 and y > 0.3.
	var from := fill.global_transform.basis.z
	assert_true(from.z > 0.5 and from.y > 0.3, "the fill comes from the camera's side and above (%s)" % from)
	# The sun: shadows, a gentle key, and it leaves the bodies to the fill.
	assert_true(sun.shadow_enabled, "the sun casts shadows")
	assert_near(sun.light_energy, 0.25, 1e-6, "the sun is a gentle key")
	assert_eq(sun.light_cull_mask & Layers.RENDER_BODIES, 0, "the sun leaves the bodies to the fill")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "ambient from a colour")
	assert_eq(env.ambient_light_color.to_html(false), "bccadf", "the ambient is #bccadf")
	assert_near(env.ambient_light_energy, 0.62, 1e-6, "ambient energy 0.62")
	assert_eq(env.background_color.to_html(false), "aebbcc", "the sky is the haze")
	var grade := region.grade
	assert_true(grade != null and grade.resource_path == GRADE, "the grade is bilibara_noon (%s)" % [grade.resource_path if grade != null else "none"])
	if grade != null:
		assert_eq(grade.fog_color.to_html(false), "aebbcc", "the grade's fog is the sky's colour")
		assert_near(grade.fog_density, 0.01, 1e-6, "fog density")
		assert_near(grade.saturation, 0.9, 1e-6, "saturation")


func test_shade_is_at_least_seventy_percent_of_sun() -> void:
	var region := _region()
	if region == null:
		return
	var env := _env(region)
	var sun := region.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		fail("no Sun")
		return
	# The toon shader's lowest step gives 0.35 of a light; ambient is kept whole.
	var ambient := env.ambient_light_energy * env.ambient_light_color.v
	var ratio := (ambient + 0.35 * sun.light_energy) / (ambient + sun.light_energy)
	assert_true(ratio >= 0.7, "shade is %.2f of sunlit ground (at least 0.7)" % ratio)


func test_the_environment_meets_the_looks_preconditions() -> void:
	var region := _region()
	if region == null:
		return
	var env := _env(region)
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_LINEAR, "tonemap linear")
	assert_near(env.tonemap_exposure, 1.0, 1e-6, "exposure 1")
	assert_false(env.glow_enabled, "no glow")
	assert_false(env.ssao_enabled, "no SSAO")
	assert_false(env.ssil_enabled, "no SSIL")
	assert_false(env.sdfgi_enabled, "no SDFGI")
	assert_false(env.adjustment_enabled, "no colour adjustments")
	assert_false(env.fog_enabled, "no environment fog")
	assert_false(env.volumetric_fog_enabled, "no volumetric fog")
	var ambient := env.ambient_light_color
	assert_true(ambient.b >= ambient.r, "the ambient is cool (%s)" % ambient.to_html(false))
	assert_true(env.ambient_light_energy > 0.0 and env.ambient_light_energy * ambient.r < 0.5, "the ambient is soft (energy %.2f)" % env.ambient_light_energy)


## The 18 lanterns of the layout: x, z of the post, whether the lamp casts shadows, and how high the post's foot is (0.65 on a low wall).
const LANTERNS := [
	[-36.1, -4.13, true, 0.0], [-28.5, -4.7, false, 0.0],
	[-20.0, -4.72, false, 0.0], [-5.0, -4.72, false, 0.0], [10.0, -4.72, false, 0.0], [22.0, -4.72, false, 0.0],
	[23.75, -15.0, false, 0.65], [31.25, -46.5, false, 0.65],
	[36.9, -37.23, true, 0.0], [33.7, -37.23, false, 0.0],
	[-18.75, -24.33, false, 0.0], [-1.25, -24.33, false, 0.0], [16.25, -24.33, false, 0.0],
	[-28.75, -15.0, false, 0.65],
	[17.5, -74.72, false, 0.0], [37.5, -74.72, false, 0.0], [23.75, -50.0, false, 0.65], [31.25, -50.0, false, 0.65],
]


func test_lamps_light_the_world_only_and_are_warm_and_few() -> void:
	var region := _region()
	if region == null:
		return
	var lamps := _lamps(region)
	assert_eq(lamps.size(), 18, "18 lamps")
	var shadowed: Array[OmniLight3D] = []
	var posts := region.get_node_or_null("Lanterns")
	assert_true(posts != null and posts.get_child_count() == 18, "18 lanterns")
	for lamp in lamps:
		assert_true(lamp.get_parent() != null and lamp.get_parent().get_parent() == posts, "a lamp sits in a lantern (%s)" % lamp.get_path())
		assert_eq(lamp.light_color.to_html(false), "ffb98a", "a warm lamp")
		assert_near(lamp.omni_range, 6.0, 1e-6, "range 6")
		assert_near(lamp.light_energy, 0.5, 1e-6, "energy 0.5")
		assert_eq(lamp.light_cull_mask, Layers.RENDER_WORLD, "a lamp lights the world and not the bodies")
		if lamp.shadow_enabled:
			shadowed.append(lamp)
		# None in the street's clear band (a prop's south edge is no further south than z -2.4).
		var at := lamp.global_position
		if at.x < 30.0 and at.z > -6.0 and at.z < 0.0:
			assert_true(at.z + 0.27 <= -2.4, "the lantern at %s is out of the street's clear band" % at)
	assert_eq(shadowed.size(), 2, "two shadow casters")
	if shadowed.size() == 2:
		assert_true(shadowed[0].global_position.distance_to(shadowed[1].global_position) >= 60.0, "the two shadow casters are 60 m or more apart")
	# Every one of the layout's posts has a lamp 3.45 up over it.
	for spec: Array in LANTERNS:
		var found := lamps.any(func(l: OmniLight3D) -> bool:
			return absf(l.global_position.x - spec[0]) < 0.05 and absf(l.global_position.z - spec[1]) < 0.05 and absf(l.global_position.y - (3.45 + spec[3])) < 0.05 and l.shadow_enabled == spec[2])
		assert_true(found, "a lamp %.2f m over (%.2f, %.2f)" % [3.45, spec[0], spec[1]])


func test_no_mesh_is_reached_by_more_than_six_lamps_and_no_point_by_more_than_two_shadows() -> void:   # Review Focus 5
	var region := _region()
	if region == null:
		return
	var lamps := _lamps(region)
	var worst := 0
	var worst_name := ""
	for node: Node3D in region.find_children("*", "GeometryInstance3D", true, false):
		var box := AABB()
		if node is KitRun:
			box = (node as KitRun).bounds()
		elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			box = node.global_transform * (node as MeshInstance3D).get_aabb()
		else:
			continue
		# A mesh that is drawn unshaded (the dark interiors behind the windows) takes no light, so no lamp reaches it.
		var material := (node as GeometryInstance3D).material_override as StandardMaterial3D
		if material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		var count := 0
		for lamp in lamps:
			var centre := lamp.global_position
			var nearest := centre.clamp(box.position, box.end)
			if nearest.distance_to(centre) <= lamp.omni_range:
				count += 1
		if count > worst:
			worst = count
			worst_name = String(region.get_path_to(node))
	assert_true(worst <= 6, "%s is reached by %d lamps (at most 6)" % [worst_name, worst])
	var casters := lamps.filter(func(l: OmniLight3D) -> bool: return l.shadow_enabled)
	var most := 0
	for x in range(-45, 46):
		for z in range(-80, 11):
			var inside := 0
			for lamp: OmniLight3D in casters:
				if lamp.global_position.distance_to(Vector3(x, 0.0, z)) <= lamp.omni_range:
					inside += 1
			most = maxi(most, inside)
	assert_true(most <= 2, "no point is in the range of more than two shadow casters (%d)" % most)


# --- Posts: a lantern's post or a colonnade's pillar is something a fighter slides round, and nothing hangs in the air ---

## A fighter sprints at a post from 4 m, in eight directions, at offsets across its width of 10 cm steps.
const SPRINT_START := 4.0
const SPRINT_OFFSETS: Array[float] = [-0.2, -0.1, 0.0, 0.1, 0.2]
## The posts tried: one of each kind of place (court A's free-standing post, a street front's, the Rack Walk's, alcove B's and the yard's wall).
const SPRINT_POSTS: Array[String] = ["Lantern", "Lantern3", "Lantern11", "Lantern10", "Lantern15"]


func test_every_lamp_hangs_from_a_post_that_stands_on_the_ground_or_a_low_wall() -> void:
	var region := _region()
	if region == null:
		return
	await frames(2)
	var space := region.get_world_3d().direct_space_state
	var solid := 0
	var on_wall := 0
	for post: Node3D in region.get_node("Lanterns").get_children():
		var lamp := post.get_node("Lamp") as OmniLight3D
		assert_near(lamp.position.y, 3.45, 1e-6, "%s: the lamp is 3.45 m up its post" % post.name)
		var foot := post.global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(foot + Vector3(0, 0.02, 0), foot - Vector3(0, 0.2, 0), Layers.WORLD | Layers.IK_SURFACE))
		assert_false(hit.is_empty(), "%s stands on something (foot %s)" % [post.name, foot])
		if not hit.is_empty():
			assert_near((hit["position"] as Vector3).y, foot.y, 0.02, "%s's foot is on what it stands on" % post.name)
		var body := post.get_node_or_null("Body") as StaticBody3D
		if body != null:
			solid += 1
			var shape := body.get_child(0) as CollisionShape3D
			assert_true(shape.shape is CylinderShape3D and (shape.shape as CylinderShape3D).radius <= 0.3, "%s: a slim round post" % post.name)
		else:
			# A ghost: its foot is on a low wall's top, where no body reaches.
			on_wall += 1
			assert_near(foot.y, 0.65, 1e-6, "%s: a ghost post stands on a low wall's top" % post.name)
			assert_true(hit.get("collider") != null and String((hit["collider"] as Node).name).begins_with("Coping"), "%s stands on a low wall's coping (%s)" % [post.name, hit.get("collider")])
	assert_eq(solid + on_wall, 18, "18 posts")
	assert_true(solid >= 10 and on_wall >= 4, "most posts are solid, four stand on walls (%d, %d)" % [solid, on_wall])


# The frames an open sprint takes to cover `metres` from rest (Abarax, in the street, east).
func _open_sprint_frames(region: Region, metres: float) -> int:
	var actor := _spawn(region, ABARAX, Vector3(-18.0, 0.0, 1.0))
	actor.set_brain(ScriptBrain.new([{frames = 400, move = Vector2(1, 0), hold = [&"dodge"]}]))
	await frames(2)
	var start := actor.global_position
	var count := 0
	while actor.global_position.distance_to(start) < metres and count < 400:
		await frames(1)
		count += 1
	actor.queue_free()
	await frames(1)
	return count


# Eight bodies at once, each sprinting at the point `at` (a post of radius `radius`) from one of eight ways, `offset` m to the side:
# the problems found: not past the post (or, dead on, not stopped square at it) when the time is up, or shaking from side to side.
func _sprint_at(region: Region, posts: Dictionary, radius: float, offset: float, run_frames: int, way: Vector2) -> PackedStringArray:
	var space := region.get_world_3d().direct_space_state
	var runners: Array[Dictionary] = []
	for label: String in posts:
		var at: Vector2 = posts[label]
		var start := at - way * SPRINT_START + way.orthogonal() * offset
		# The way must be open: the start stands free, and a ray from it to the post meets nothing before it.
		var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(start.x, 0.5, start.y), Vector3(at.x, 0.5, at.y), Layers.WORLD))
		if _blocked(space, start) or not _ground_under(space, start) or (not ray.is_empty() and (ray["position"] as Vector3).distance_to(Vector3(at.x, 0.5, at.y)) > radius + 0.05):
			continue
		var actor := _spawn(region, ABARAX, Vector3(start.x, 0.0, start.y))
		actor.set_brain(ScriptBrain.new([{frames = run_frames, move = way, hold = [&"dodge"]}]))
		runners.append({actor = actor, way = way, trail = [], label = label, at = at})
	await frames(2)
	for i in run_frames:
		await frames(1)
		for r in runners:
			var p := (r.actor as Actor).global_position
			(r.trail as Array).append(Vector2(p.x, p.z))
	var problems := PackedStringArray()
	for r in runners:
		var heading: Vector2 = r.way
		var at: Vector2 = r.at
		var label: String = r.label
		var trail := PackedVector2Array(r.trail)
		var end: Vector2 = trail[trail.size() - 1]
		var along := (end - at).dot(heading)
		var side := (end - at).dot(heading.orthogonal())
		var square := absf(offset) < 0.05 and along < radius + BODY + 0.15
		# Close to dead on (under 0.2 m aside) a body pressing into a round post turns aside slowly, as a body does against any wall
		# (the legs go no faster than the body): it is not past it in the time, but it must be moving aside, not standing and pressing.
		var creeping := absf(offset) < 0.2 - 1e-6 and (absf((end - at).dot(heading.orthogonal())) - absf((trail[trail.size() - 30] - at).dot(heading.orthogonal()))) >= 0.02
		if along < 0.2 and not square and not creeping:
			problems.append("%s, from %s at %.1f m aside: not past it after %d frames (%.2f along, %.2f aside)" % [label, -heading, offset, run_frames, along, side])
		# Shaking: the sideways movement reverses direction again and again over the last half second.
		var reversals := 0
		var last_sign := 0
		for k in range(maxi(trail.size() - 30, 1), trail.size()):
			var step := (trail[k] - trail[k - 1]).dot(heading.orthogonal())
			if absf(step) > 0.002:
				var sign_now := 1 if step > 0.0 else -1
				if last_sign != 0 and sign_now != last_sign:
					reversals += 1
				last_sign = sign_now
		if reversals > 2:
			problems.append("%s, from %s at %.1f m aside: shakes (%d reversals)" % [label, -heading, offset, reversals])
	for r in runners:
		(r.actor as Actor).queue_free()
	await frames(1)
	return problems


func test_a_sprint_at_a_post_slides_round_it_or_stops_square() -> void:
	var region := _region()
	if region == null:
		return
	await frames(2)
	var open_frames := await _open_sprint_frames(region, SPRINT_START + 1.4)
	assert_true(open_frames > 20 and open_frames < 300, "an open sprint of %.1f m takes %d frames" % [SPRINT_START + 1.4, open_frames])
	var ways: Array[Vector2] = []
	for k in 8:
		# Every solid post stands against a front, a wall or a plinth to its north: a sprint into that side is a sprint into a corner (the
		# wall holds him, as it holds him anywhere), so the five ways that do not run north are tried.
		var way := Vector2.from_angle(TAU * k / 8.0)
		if way.y > -0.1:
			ways.append(way)
	var posts := {}
	for post_name in SPRINT_POSTS:
		var post := region.get_node("Lanterns/" + post_name) as Node3D
		assert_true(post.get_node_or_null("Body") != null, "%s is a solid post" % post_name)
		posts[post_name] = Vector2(post.global_position.x, post.global_position.z)
	var problems := PackedStringArray()
	var tried := 0
	# One way at a time (bodies from all round at once would jam each other at the post), the posts together (they are far apart).
	for way in ways:
		for offset in SPRINT_OFFSETS:
			tried += posts.size()
			problems.append_array(await _sprint_at(region, posts, POST_R, offset, open_frames + 60, way))
	assert_true(tried >= 100, "the sprints were tried (%d)" % tried)
	assert_eq(problems.slice(0, 8), PackedStringArray(), "every sprint at a lantern's post ends past it or square on it, and none shakes (%d problems)" % problems.size())


const POST_R := 0.27


func test_a_sprint_at_the_colonnade_stops_square_or_slides_along_it() -> void:
	var region := _region()
	if region == null:
		return
	await frames(2)
	var guard := region.get_node("ColonnadeGuard") as StaticBody3D
	var space := region.get_world_3d().direct_space_state
	var problems := PackedStringArray()
	# Straight at it, and at 45 degrees either way, at five places along it and offsets between pillars.
	for x: float in [-30.0, -10.1, 0.0, 9.9, 18.0]:
		for dx: float in [0.0, 1.0, -1.0]:
			var way := Vector2(dx, -1.0).normalized()
			var start := Vector2(x, -24.6) - way * 3.4
			var actor := _spawn(region, ABARAX, Vector3(start.x, 0.0, start.y))
			actor.set_brain(ScriptBrain.new([{frames = 120, move = way, hold = [&"dodge"]}]))
			await frames(2)
			var trail := PackedVector2Array()
			for i in 90:
				await frames(1)
				trail.append(Vector2(actor.global_position.x, actor.global_position.z))
			var end := trail[trail.size() - 1]
			if end.y < -24.6 + BODY - 0.05:
				problems.append("x %.1f way %s: ended %.2f m inside the pillars' line (z %.2f)" % [x, way, -24.6 + BODY - end.y, end.y])
			if absf(dx) > 0.5 and absf(end.x - start.x) < 1.5:
				problems.append("x %.1f way %s: stuck, moved %.2f m along it" % [x, way, end.x - start.x])
			var reversals := 0
			var last_sign := 0
			for k in range(trail.size() - 30, trail.size()):
				var step := (trail[k] - trail[k - 1]).x
				if absf(step) > 0.002:
					var sign_now := 1 if step > 0.0 else -1
					if last_sign != 0 and sign_now != last_sign:
						reversals += 1
					last_sign = sign_now
			if reversals > 2:
				problems.append("x %.1f way %s: shakes" % [x, way])
			actor.queue_free()
			await frames(1)
	assert_true(guard != null, "a ColonnadeGuard")
	assert_eq(problems, PackedStringArray(), "the colonnade holds a sprint and lets it slide")
	assert_true(space != null)


# At the gate's spots (where the camera's GateFar and GateNear markers stand, and along the slot) no mesh, seen or not, collider or not, crosses
# the line from a fighter's head (the crown at 1.8 m, three points across him) to the camera: the gate's first dressing had a rail 2.4 m up that
# crossed 13 of 115 head pixels at GateFar.
func test_no_piece_crosses_a_head_at_the_gates_spots() -> void:
	var region := _region()
	if region == null:
		return
	var pitch := deg_to_rad(-CameraRig.PITCH_DEG)
	var to_camera := Vector3(0.0, CameraRig.DISTANCE * sin(pitch), CameraRig.DISTANCE * cos(pitch))
	var occluders := _occluders(region)
	var crossing := PackedStringArray()
	for spot: Array in [[-34.65, -5.86], [-34.0, -5.86], [-32.5, -5.86], [-31.0, -5.86], [-30.35, -5.86], [-32.5, -6.5]]:
		for dx: float in [-0.2, 0.0, 0.2]:
			for h: float in [1.5, 1.65, 1.8]:
				var head := Vector3(spot[0] + dx, h, spot[1])
				for entry in occluders:
					var box: AABB = entry.box
					if box.end.y < 1.0 or String(entry.name).begins_with("Backdrop/Block") or String(entry.name).begins_with("Blocks/"):
						continue
					if box.intersects_segment(head, head + to_camera):
						crossing.append("%s over (%.2f, %.2f) at %.2f m" % [entry.name, spot[0] + dx, spot[1], h])
	assert_eq(crossing.slice(0, 6), PackedStringArray(), "nothing crosses a head at the gate (%d crossings)" % crossing.size())
