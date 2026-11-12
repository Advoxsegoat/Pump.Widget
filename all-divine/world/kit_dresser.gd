@tool
class_name KitDresser
extends Node
## Draws the kit pieces of a region in a material of the region's own: the builder's `kit` line (tools/world/build_region.gd)
## puts one of these in the region. The kit has a single colormap, and a piece placed from its file keeps the material it
## was imported with; saving a different material on every piece would write each piece's mesh into the scene again, so
## the scene holds this one node and the pieces take the material as the region enters the tree. It is a tool script so
## that the editor, where the scenes are opened and changed, shows the same colours; and it dresses a kit piece added to
## the region after it is ready (a piece placed in the editor, a run a script lays) as that piece enters the tree.

## The material every kit piece under the parent is drawn in.
@export var material: Material


func _ready() -> void:
	dress(get_parent(), material)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


# A node that has come into the tree anywhere: dressed if it is a kit piece under this dresser's region.
func _on_node_added(node: Node) -> void:
	var region := get_parent()
	if region != null and node != self and region.is_ancestor_of(node):
		dress_piece(node, material)


## Sets `material` on the meshes of every instanced piece of the kit (a scene from assets/env/kenney_town/) under `root`, and
## on every MultiMeshInstance3D of the group `kit_multimesh` (the builder's runs of one piece).
static func dress(root: Node, kit_material: Material) -> void:
	if kit_material == null or root == null:
		return
	for node in root.find_children("*", "Node3D", true, false):
		dress_piece(node, kit_material)


## Dresses `node` alone if it is a kit piece: a run of the group `kit_multimesh`, or the root of an instanced piece of the kit.
static func dress_piece(node: Node, kit_material: Material) -> void:
	if kit_material == null:
		return
	if node is MultiMeshInstance3D and node.is_in_group(&"kit_multimesh"):
		(node as MultiMeshInstance3D).material_override = kit_material
	elif node is Node3D and node.scene_file_path.begins_with("res://assets/env/kenney_town/"):
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = kit_material
