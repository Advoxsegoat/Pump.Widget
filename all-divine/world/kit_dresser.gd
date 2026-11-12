class_name KitDresser
extends Node
## Draws the kit pieces of a region in a material of the region's own: the builder's `kit` line (tools/world/build_region.gd)
## puts one of these in the region. The kit has a single colormap, and a piece placed from its file keeps the material it
## was imported with; saving a different material on every piece would write each piece's mesh into the scene again, so
## the scene holds this one node and the pieces take the material as the region enters the tree.

## The material every kit piece under the parent is drawn in.
@export var material: Material


func _ready() -> void:
	dress(get_parent(), material)


## Sets `material` on the meshes of every instanced piece of the kit (a scene from assets/env/kenney_town/) under `root`, and
## on every MultiMeshInstance3D of the group `kit_multimesh` (the builder's runs of one piece).
static func dress(root: Node, kit_material: Material) -> void:
	if kit_material == null or root == null:
		return
	for node in root.find_children("*", "Node3D", true, false):
		if node is MultiMeshInstance3D and node.is_in_group(&"kit_multimesh"):
			(node as MultiMeshInstance3D).material_override = kit_material
		elif node.scene_file_path.begins_with("res://assets/env/kenney_town/"):
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				mesh.material_override = kit_material
