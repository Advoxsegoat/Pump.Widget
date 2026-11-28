class_name StretchGround
extends RefCounted
## What can be stood on in the stretch: the question the saved game asks of a place before it puts the player there, and the
## flood fill the tests (and the level checker) ask of the whole place.
##
## A point is standing ground when the visible floor (`ik_surface`) is under it at y = 0 and the body's own capsule, reduced to a
## ball low down (0.35 m wide, 0.5 m up), overlaps nothing on `world`: not a wall, a post, a vat or a closed gate. The ground
## is under the ball, never in it. Both queries need the region to be in the tree and its physics to have stepped once.

## The body's capsule is this wide in radius (actor.tscn): its centre never gets nearer a wall than this.
const BODY := 0.35
## The flood fill's cells, in metres, and where it looks: a little more than the whole stretch.
const CELL := 0.5
const GRID_X := Vector2i(-90, 90)
const GRID_Z := Vector2i(-165, 25)
## How far the floor may be from y = 0 under a standing point, and how far the point itself may be above or below it.
const FLOOR_SLACK := 0.01
const POINT_SLACK := 0.25

## The flood fill, made once for the scene as it stands (a gate that has opened is another scene: `solid_signature`).
static var _memo := {}


## Whether a body can stand at `point` in `region`: floor under it at y = 0 (within FLOOR_SLACK), the point within POINT_SLACK of
## that floor, and no `world` body in the way of its capsule.
static func stands(region: Region, point: Vector3) -> bool:
	if not is_finite(point.x) or not is_finite(point.y) or not is_finite(point.z) or absf(point.y) > POINT_SLACK:
		return false
	var space := region.get_world_3d().direct_space_state
	var flat := Vector2(point.x, point.z)
	return ground_under(space, flat) and not blocked(space, flat)


## Whether `ik_surface` is under (x, z) at y = 0. The ray starts a hand's breadth up (inside a vat or a post it then finds the plate
## under it) and a hair off the point, which is often on the very face of a box (a ray along a face finds nothing).
static func ground_under(space: PhysicsDirectSpaceState3D, point: Vector2) -> bool:
	var at := point + Vector2(0.013, 0.007)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 0.05, at.y), Vector3(at.x, -0.5, at.y), Layers.IK_SURFACE))
	return not hit.is_empty() and absf((hit["position"] as Vector3).y) < FLOOR_SLACK


## Whether the body's capsule, reduced to a ball low down (a 0.35 m capsule 0.5 m up), overlaps something on `world` at `at`
## (x, z); `radius` is the ball's.
static func blocked(space: PhysicsDirectSpaceState3D, at: Vector2, radius := BODY) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 2.0 * radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), Vector3(at.x, 0.5, at.y))
	query.collision_mask = Layers.WORLD
	return not space.intersect_shape(query, 1).is_empty()


## The cells (keyed by `cell_of`, `Vector2i(floori(x / CELL), floori(z / CELL))`) walked to from the region's `Spawn`, as `fill` makes them.
static func reached(region: Region) -> Dictionary:
	return fill(region)["reached"]


## The cell (a Vector2i) a point (x, z) is in, and where its middle is.
static func cell_of(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))


static func middle(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## The flood fill from Spawn on CELL cells: `{free: cells whose capsule overlaps no wall (true), ground: cells with ground under
## their middle, reached: cells walked to from Spawn (a free ground cell next to a reached one)}`. Made once per scene.
static func fill(region: Region) -> Dictionary:
	var key := "%s|%d" % [region.scene_file_path, solid_signature(region)]
	if _memo.has(key):
		return _memo[key]
	var space := region.get_world_3d().direct_space_state
	var free := {}
	var ground := {}
	for cx in range(GRID_X.x, GRID_X.y):
		for cz in range(GRID_Z.x, GRID_Z.y):
			if ground_under(space, middle(Vector2i(cx, cz))):
				ground[Vector2i(cx, cz)] = true
	var reached_cells := {}
	var queue: Array[Vector2i] = []
	var spawn := region.spawn().origin
	var start := cell_of(Vector2(spawn.x, spawn.z))
	var near := func(cell: Vector2i) -> bool:
		if not free.has(cell):
			free[cell] = not blocked(space, middle(cell))
		return free[cell]
	if ground.has(start) and near.call(start):
		reached_cells[start] = true
		queue.append(start)
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if not reached_cells.has(next) and ground.has(next) and near.call(next):
				reached_cells[next] = true
				queue.append(next)
	# What the leak check asks of the neighbours of the reached cells, and which of the ground is free.
	for cell: Vector2i in reached_cells.keys():
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			near.call(cell + step)
	for cell: Vector2i in ground.keys():
		near.call(cell)
	_memo[key] = {free = free, ground = ground, reached = reached_cells}
	return _memo[key]


## A number that changes when a gate opens or shuts (Task 5): the names and collision layers of the bodies that are children of `region`.
## A board built at run time is one more body; a board lowered has layer 0. Two regions of the same scene with the same gates hash alike.
static func solid_signature(region: Node) -> int:
	var parts: Array = []
	for child in region.get_children():
		var body := child as StaticBody3D
		if body != null:
			parts.append([String(body.name), body.collision_layer])
	return parts.hash()
