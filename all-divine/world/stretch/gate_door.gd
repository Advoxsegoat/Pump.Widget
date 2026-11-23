class_name GateDoor
extends Node
## One gate of the stretch, made by the run (a child of it named `Gate_<id>`): the boards its `GateDef` names, taken away when its flag is
## set. Opening is not a scene and holds no one: the boards stop blocking on the very frame (their collision layer goes to 0), then
## sink `drop` metres over SINK_FRAMES play frames and are hidden. A gate whose flag is already set when the run starts is open from the
## first frame with no sinking.
##
## A board the def asks for (`board` not empty) is built here: a solid slate box 0.6 m high on world and ik_surface like the layout's own
## curbs, a `StaticBody3D` named for the gate, a child of the region. Built before the player is placed, so that where he stands is
## answered with it in.

## Play frames a board takes to sink.
const SINK_FRAMES := 45
## How high a built board stands.
const BOARD_HEIGHT := 0.6
## How much of the sinking is eased: the rest is linear, so that it never stops dead and never drops more than 1.5 times its mean.
const EASE := 0.25
const STONE := preload("res://world/materials/slate_pale.tres")

## The data.
var def: GateDef

var _run: StretchRun
var _boards: Array[Node3D] = []
var _rests: Array[float] = []  # each board's y before it sank
var _open := false
var _sinking := false
var _frames := 0
var _counted := -1


## Makes the door for `gate_def` under `run`: its boards found (or built) in the run's region, open now when the world remembers its flag.
static func make(run: StretchRun, gate_def: GateDef) -> GateDoor:
	var door := GateDoor.new()
	door.def = gate_def
	door._run = run
	door.name = "Gate_%s" % gate_def.id
	run.add_child(door)
	door._gather(run.region)
	run.world_changed.connect(door._on_world_changed)
	if run.flag(gate_def.opens_on):
		door.open(false)
	return door


## Takes the gate away: its boards stop blocking now and, `animated`, sink over SINK_FRAMES play frames and are hidden; not animated,
## they are gone now.
func open(animated := true) -> void:
	if _open or _sinking:
		if not animated and _sinking:
			_finish()
		return
	for board in _boards:
		_unblock(board)
	if animated and not _boards.is_empty():
		_sinking = true
		_frames = 0
		_counted = Game.play_frames
	else:
		_sink_to(1.0)
		_finish()


## Whether the gate is open: its boards have sunk (not merely stopped blocking).
func is_open() -> bool:
	return _open


## Whether the gate has been opened: its boards no longer block, whether or not they have finished sinking.
func is_released() -> bool:
	return _open or _sinking


## Whether a body at `at` (x, z) would stand in a board that is still shut (a built board's rectangle grown by the body).
func shuts(at: Vector2) -> bool:
	if _open or _sinking or def.board.size == Vector2.ZERO:
		return false
	return def.board.grow(StretchGround.BODY).has_point(at)


func _physics_process(_delta: float) -> void:
	if not _sinking or Game.play_frames == _counted:
		return
	_counted = Game.play_frames
	_frames += 1
	var t := minf(float(_frames) / float(SINK_FRAMES), 1.0)
	_sink_to(lerpf(t, smoothstep(0.0, 1.0, t), EASE))
	if _frames >= SINK_FRAMES:
		_finish()


func _on_world_changed(flag: StringName) -> void:
	if flag == def.opens_on:
		open(true)


# The boards of this gate: the nodes it names, and, if it has a board of its own, that board built.
func _gather(region: Node) -> void:
	for node_name in def.nodes:
		var node := region.find_child(node_name, true, false) as Node3D
		if node != null:
			_boards.append(node)
	if def.board.size != Vector2.ZERO:
		_boards.append(_build(region))
	for board in _boards:
		_rests.append(board.position.y)


func _build(region: Node) -> Node3D:
	var body := StaticBody3D.new()
	body.name = String(def.id)
	body.collision_layer = Layers.WORLD | Layers.IK_SURFACE
	body.collision_mask = 0
	var size := Vector3(def.board.size.x, BOARD_HEIGHT, def.board.size.y)
	var centre := def.board.get_center()
	var at := Vector3(centre.x, BOARD_HEIGHT / 2.0, centre.y)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = STONE
	mesh.position = at
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var shape_box := BoxShape3D.new()
	shape_box.size = size
	shape.shape = shape_box
	shape.position = at
	body.add_child(shape)
	region.add_child(body)
	return body


# Takes the collision off a board and everything solid under it, now.
func _unblock(board: Node) -> void:
	if board is CollisionObject3D:
		(board as CollisionObject3D).collision_layer = 0
	for child in board.find_children("*", "CollisionObject3D", true, false):
		(child as CollisionObject3D).collision_layer = 0


# Every board is `share` (0 to 1) of the way down.
func _sink_to(share: float) -> void:
	for i in _boards.size():
		var board := _boards[i]
		var y := _rests[i] - def.drop * share
		board.position = Vector3(board.position.x, y, board.position.z)


func _finish() -> void:
	_sinking = false
	_sink_to(1.0)
	for board in _boards:
		board.visible = false
	_open = true
