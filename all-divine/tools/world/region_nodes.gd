extends RefCounted
## What every part of the region builder needs to put nodes in a region: the root, the parent groups, unique names, bodies
## and boxes, the Kenney pieces and their bounds and meshes, and the problems of the layout. tools/world/build_region.gd's
## Builder is one, and tools/world/region_blocks.gd takes one as an argument (typed) to lay ground and buildings in it.

# By path rather than by class name, so the tool also runs before the project has been imported.
const LAYERS := preload("res://core/layers.gd")
const KENNEY_DIR := "res://assets/env/kenney_town/"
const KENNEY := KENNEY_DIR + "%s.glb"
## Kenney pieces are this many times their size: a tile of 2.5 m, a wall 2.5 m tall.
const SCALE := 2.5
const TILE := 2.5

## What went wrong in the layout, each with its line (problem), and the layout's path for those lines.
var problems := PackedStringArray()
var layout := ""
## The collision bits of `world` and `ik_surface`.
var world_and_feet := 0

var _root: Node3D
var _counts := {}  # how many nodes of each name so far
var _line := 0
var _boxes := {}  # the bounds of each Kenney piece loaded so far, by name
var _part_cache := {}  # the meshes of each, by name


# The bounds of a Kenney piece's meshes in its own space, unscaled; a zero box (and a problem) if there is
# no such piece.
func local_box(piece: String) -> AABB:
	if _boxes.has(piece):
		return _boxes[piece]
	var path := KENNEY % piece
	if not ResourceLoader.exists(path):
		problem("no Kenney piece '%s' (%s)" % [piece, path])
		return AABB()
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	var boxes: Array[AABB] = []
	mesh_boxes(scene, Transform3D(), boxes)
	scene.free()
	if boxes.is_empty():
		problem("the Kenney piece '%s' has no mesh" % piece)
		return AABB()
	var box := boxes[0]
	for b in boxes:
		box = box.merge(b)
	_boxes[piece] = box
	return box

# The meshes of a Kenney piece, each with its transform in the piece's own space ({mesh, local}): what a MultiMesh of the
# piece is made of. Empty (and a problem) if there is no such piece.
func mesh_parts(piece: String) -> Array:
	if _part_cache.has(piece):
		return _part_cache[piece]
	var path := KENNEY % piece
	if not ResourceLoader.exists(path):
		problem("no Kenney piece '%s' (%s)" % [piece, path])
		return []
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	var found: Array = []
	collect_parts(scene, Transform3D(), found)
	scene.free()
	if found.is_empty():
		problem("the Kenney piece '%s' has no mesh" % piece)
		return []
	_part_cache[piece] = found
	return found

func collect_parts(node: Node, to_root: Transform3D, found: Array) -> void:
	for child in node.get_children():
		if child is Node3D:
			var t := to_root * (child as Node3D).transform
			if child is MeshInstance3D:
				found.append({mesh = (child as MeshInstance3D).mesh, local = t})
			collect_parts(child, t, found)

# The bounds of each mesh under `node`, in the space `to_root` takes `node`'s space to.
func mesh_boxes(node: Node, to_root: Transform3D, boxes: Array[AABB]) -> void:
	for child in node.get_children():
		if child is Node3D:
			var t := to_root * (child as Node3D).transform
			if child is MeshInstance3D:
				boxes.append(t * (child as MeshInstance3D).get_aabb())
			mesh_boxes(child, t, boxes)

# --- nodes ---

func make_model(piece: String, parent: Node3D, model_name: String) -> Node3D:
	var model := (load(KENNEY % piece) as PackedScene).instantiate() as Node3D
	model.name = model_name
	parent.add_child(model)
	return model

func make_body(body_name: String, parent: Node3D, layers: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layers
	body.collision_mask = 0
	parent.add_child(body)
	return body

# A box shape on `body` (and, with a material, a box mesh in it).
func add_box(body: StaticBody3D, size: Vector3, at: Transform3D, material: Material) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = unique_name("Shape", body)
	collision.shape = shape
	collision.transform = at
	body.add_child(collision)
	if material != null:
		var mesh := BoxMesh.new()
		mesh.size = size
		var instance := MeshInstance3D.new()
		instance.name = unique_name("Mesh", body)
		instance.mesh = mesh
		instance.material_override = material
		instance.transform = at
		body.add_child(instance)

# The child of the root called `group_name`, made the first time.
func group_node(group_name: String) -> Node3D:
	var node := _root.get_node_or_null(NodePath(group_name)) as Node3D
	if node == null:
		node = Node3D.new()
		node.name = group_name
		_root.add_child(node)
	return node

# `base`, or base1, base2, ... once there is more than one (counted per parent when `parent` is given).
func unique_name(base: String, parent: Node = null) -> String:
	var key := base if parent == null else "%s/%s" % [parent.get_instance_id(), base]
	_counts[key] = _counts.get(key, 0) + 1
	var n: int = _counts[key]
	return base if n == 1 else base + str(n)

static func pascal(piece: String) -> String:
	var out := ""
	for part in piece.split("-"):
		out += part.capitalize()
	return out

func problem(what: String) -> void:
	problems.append("%s:%d: %s" % [layout, _line, what])
