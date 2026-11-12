@tool
class_name KitRun
extends MultiMeshInstance3D
## A run of one mesh of one kit piece, drawn as one MultiMesh: the builder's `block` lays its walls and roofs this way, so
## that a street's worth of wall tiles is a few draws and not one for every tile. The scene holds where the pieces stand
## (`places`) and the mesh, not the instance buffer; the MultiMesh is made from them as the run enters the tree (a headless
## game keeps no instance data, and these places are what its tests read).
##
## Note for anyone who measures one: a MultiMesh's own box (`multimesh.get_aabb()`, and so a mesh's box under this node) is
## ZERO in a headless run, and right only under a display. A test that asks where a run is, or how big, asks `bounds()`,
## which is made from the places and the piece's own box and means the same in both.

## The kit piece this is a mesh of (its file's name), and the mesh itself.
@export var piece: StringName
@export var part: Mesh
## The mesh's own transform inside the piece (a piece made of several meshes has one run to each).
@export var local := Transform3D.IDENTITY
## The piece's transform at each place it stands.
@export var places: Array[Transform3D] = []


func _ready() -> void:
	var made := MultiMesh.new()
	made.transform_format = MultiMesh.TRANSFORM_3D
	made.mesh = part
	made.instance_count = places.size()
	for i in places.size():
		made.set_instance_transform(i, places[i] * local)
	multimesh = made


## The box of the whole run in world space: every place's piece (the mesh's own transform inside it) merged, from the places
## and the mesh's own box and not from the MultiMesh, so that it is the same headless and under a display. An empty AABB
## when the run has no places or no mesh.
func bounds() -> AABB:
	if part == null or places.is_empty():
		return AABB()
	var box := part.get_aabb()
	var all := AABB()
	for i in places.size():
		var here := global_transform * places[i] * local * box if is_inside_tree() else transform * places[i] * local * box
		all = here if i == 0 else all.merge(here)
	return all
