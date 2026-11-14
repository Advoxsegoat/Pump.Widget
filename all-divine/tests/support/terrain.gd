class_name TestTerrain
extends RefCounted
## Uneven ground for the foot tests, built under `parent` (a TestArena, whose floor is at y = 0). Each
## piece is a StaticBody3D with a visible mesh. The physics layers are the game's: `world` is what the body
## walks on and `ik_surface` is what the feet stand on. A slope or a ledge is the same shape on both; stairs
## are steps on `ik_surface` and a smooth ramp on `world`, so the body glides up them while the feet find
## each step.

## How far each piece reaches across (along z), centred on z = 0.
const WIDTH := 8.0
## The slope's length along x, from its foot at the origin.
const SLOPE_LENGTH := 8.0
## The ledge: its top, and how far back from its edge it reaches.
const LEDGE_TOP := 1.0
const LEDGE_DEPTH := 8.0
## The landing at the top of the stairs.
const LANDING := 2.0


## A slope rising `deg` degrees toward +X from the floor: its surface is y = x · tan(deg), from x = 0 to
## SLOPE_LENGTH. Someone standing on it facing +Z (across it) has the uphill side on his left.
static func slope(parent: Node3D, deg: float) -> void:
	var angle := deg_to_rad(deg)
	var thickness := 0.5
	var length := SLOPE_LENGTH / cos(angle)
	var body := _body(parent, "Slope", _layers(["world", "ik_surface"]))
	# A slab tilted about z, its top face's lower edge on the line x = 0, y = 0.
	var tilt := Basis(Vector3.BACK, angle)
	var centre := tilt * Vector3(length / 2, -thickness / 2, 0)
	_add_box(body, Vector3(length, thickness, WIDTH), Transform3D(tilt, centre), true)


## `count` steps climbing toward +X from the floor at x = 0, each `rise` high and `run` deep: step i's tread
## is at y = (i + 1) · rise, from x = i · run to (i + 1) · run, with a landing LANDING long at the top. The
## steps are on `ik_surface` only. On `world` a ramp runs through the middle of every tread (y = rise ·
## (x / run + 1/2), starting half a run before the first step, where it meets the floor), and the landing is
## on both.
static func stairs(parent: Node3D, rise: float, run: float, count: int) -> void:
	var steps := _body(parent, "Steps", _layers(["ik_surface"]))
	for i in count:
		var height := (i + 1) * rise
		_add_box(steps, Vector3(run, height, WIDTH), Transform3D(Basis(), Vector3((i + 0.5) * run, height / 2, 0)), true)
	var top := count * rise
	var landing := _body(parent, "Landing", _layers(["world", "ik_surface"]))
	_add_box(landing, Vector3(LANDING, top, WIDTH), Transform3D(Basis(), Vector3(count * run + LANDING / 2, top / 2, 0)), true)
	# The ramp: from (-run / 2, 0) to the middle of the top tread ((count - 1/2) · run, count · rise).
	var ramp := _body(parent, "Ramp", _layers(["world"]))
	var angle := atan2(rise, run)
	var thickness := 0.5
	var length := count * run / cos(angle)
	var tilt := Basis(Vector3.BACK, angle)
	var start := Vector3(-run / 2, 0, 0)
	_add_box(ramp, Vector3(length, thickness, WIDTH), Transform3D(tilt, start + tilt * Vector3(length / 2, -thickness / 2, 0)), false)


## A platform LEDGE_TOP high whose edge is at x = 0: its top reaches from x = -LEDGE_DEPTH to 0. Past the
## edge there is nothing for LEDGE_TOP metres down (the arena's floor).
static func ledge(parent: Node3D) -> void:
	var body := _body(parent, "Ledge", _layers(["world", "ik_surface"]))
	_add_box(body, Vector3(LEDGE_DEPTH, LEDGE_TOP, WIDTH), Transform3D(Basis(), Vector3(-LEDGE_DEPTH / 2, LEDGE_TOP / 2, 0)), true)


## A box on `ik_surface` only, from `from` to `to` (opposite corners): something under the feet that the
## body does not stand on. Returns it, so a test can take it away.
static func ik_block(parent: Node3D, from: Vector3, to: Vector3) -> StaticBody3D:
	var body := _body(parent, "IKBlock", _layers(["ik_surface"]))
	_add_box(body, (to - from).abs(), Transform3D(Basis(), (from + to) / 2), true)
	return body


static func _body(parent: Node3D, body_name: String, layers: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layers
	body.collision_mask = 0
	parent.add_child(body, true)
	return body


static func _add_box(body: StaticBody3D, size: Vector3, at: Transform3D, visible: bool) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = at
	body.add_child(shape)
	if visible:
		var mesh := BoxMesh.new()
		mesh.size = size
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.transform = at
		body.add_child(instance)


static func _layers(names: Array) -> int:
	var bits := 0
	for layer_name: String in names:
		bits |= TestArena.layer_bit(layer_name)
	return bits
