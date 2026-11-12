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
	"W1 court A": {rect = Rect2(-40, -5, 10, 10), stone = "slate"},
	"W2 Rue Caillou": {rect = Rect2(-30, -5, 62.5, 10), stone = "cobble"},
	"W3 the Tanneries lane": {rect = Rect2(25, -55, 5, 50), stone = "tan_earth"},
	"W4 the Rack Walk": {rect = Rect2(-35, -25, 60, 5), stone = "tan_earth"},
	"W5 the loop lane": {rect = Rect2(-35, -20, 5, 15), stone = "tan_earth"},
	"W6 alcove B": {rect = Rect2(30, -37.5, 7.5, 7.5), stone = "slate"},
	"W7 the Tanneries yard": {rect = Rect2(15, -75, 25, 20), stone = "tan_earth"},
}
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
	"ShrinePlinth_A": [-35, 0, 1.0], "ShrinePlinth_B": [36.25, -33.75, 1.0], "ShortcutGate": [-32.5, -5, 1.0],
	"YardGate": [27.5, -55, 1.4], "YardCentre": [27.5, -65, 1.0], "VatWest": [20, -66.25, 1.0], "VatEast": [35, -66.25, 1.0],
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
			assert_eq(material.resource_path, STONE % PLACES[place].stone, "%s (%s) is %s" % [body.name, place, PLACES[place].stone])
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
		thin = thin and size.x < 0.8 and size.z < 0.8
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
			var box := (shape.shape as BoxShape3D).size
			var centre := shape.global_position
			var top := centre.y + box.y / 2.0
			if centre.y - box.y / 2.0 >= 1.8 or (box.x < 0.8 and box.z < 0.8):
				continue
			var x := centre.x - box.x / 2.0 + 0.05
			var north := false
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
	var rail := region.get_node_or_null("GateRail") as StaticBody3D
	assert_true(rail != null, "the GateRail")
	if rail != null:
		var shape := rail.get_node("Shape") as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		assert_true(size.y <= 0.12 + 1e-6 and size.z <= 0.12 + 1e-6, "the rail is no thicker than 0.12 m (%s)" % size)
		assert_true(shape.global_position.y - size.y / 2.0 >= 2.4 - 1e-6, "its underside is at 2.4 m or higher")
		assert_true(shape.global_position.x - size.x / 2.0 <= -35.125 + 1e-3 and shape.global_position.x + size.x / 2.0 >= -29.875 - 1e-3, "across the tops of the two posts")


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
				if box.size.x < 0.8 or box.position.x > base.x or box.end.x < base.x or box.end.z < at.y:
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
			var height: float = {"poles": 2.5, "poles-horizontal": 2.5, "rock-large": 2.91}.get(k.piece, 1.0)
			if height > most:
				tall_near.append("%s at %s is %.2f m, the line allows %.2f" % [k.piece, k.at, height, most])
	assert_eq(tall_near, PackedStringArray(), "nothing in the drying yard stands above the line of sight")
	# The harbor: the water at y -0.9 from z 9.25 to 32, a quay wall of wall-half along z 9, an apron of visual cobble.
	var water := region.find_children("Water*", "MeshInstance3D", true, false).filter(func(w: MeshInstance3D) -> bool: return is_equal_approx(w.global_position.y, -0.9))
	assert_eq(water.size(), 1, "one sheet of water at y -0.9")
	if water.size() == 1:
		var plane := (water[0] as MeshInstance3D).mesh as PlaneMesh
		var w := water[0] as MeshInstance3D
		assert_near(w.global_position.z - plane.size.y / 2.0, 9.25, 1e-3, "from z 9.25")
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
			var ok: bool = material is ShaderMaterial and (material as ShaderMaterial).shader.resource_path == TOON_WORLD and material == dresser.material
			var tex := (material as ShaderMaterial).get_shader_parameter(&"albedo_tex") as Texture2D if ok else null
			ok = ok and tex != null and tex.resource_path == "res://assets/env/textures/bilibara_colormap.png"
			seen[region.get_path_to(node)] = true
			if not ok:
				not_toon.append(String(region.get_path_to(node)))
	assert_eq(off_scale, PackedStringArray(), "pieces not at x2.5")
	assert_eq(not_toon, PackedStringArray(), "pieces not in toon_world with the Bilibara colormap")
	assert_true(seen.size() > 50, "and many were looked at (%d)" % seen.size())
