@tool
class_name KitRun
extends MultiMeshInstance3D
## A run of one mesh of one kit piece, drawn as one MultiMesh: the builder's `block` lays its walls and roofs this way, so
## that a street's worth of wall tiles is a few draws and not one for every tile. The scene holds where the pieces stand
## (`places`) and the mesh, not the instance buffer; the MultiMesh is made from them as the run enters the tree (a headless
## game keeps no instance data, and these places are what its tests read).

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
