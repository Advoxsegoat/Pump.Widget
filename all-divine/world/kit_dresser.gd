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
## The material of the banner pieces (a piece whose file starts with `banner`), where a region has neon: they glow in colours of their own.
@export var banner_material: Material


func _ready() -> void:
	dress(get_parent(), material, banner_material)


# Listens from _enter_tree (which runs each time the region comes into the tree) and not from _ready (which runs once), so
# that a region that leaves the tree and returns goes on dressing what is added to it.
func _enter_tree() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


# A node that has come into the tree anywhere: dressed if it is a kit piece under this dresser's region.
func _on_node_added(node: Node) -> void:
	var region := get_parent()
	if region != null and node != self and region.is_ancestor_of(node):
		dress_piece(node, material, banner_material)


## Sets `material` on the meshes of every instanced piece of the kit (a scene from assets/env/kenney_town/) under `root`, and
## on every MultiMeshInstance3D of the group `kit_multimesh` (the builder's runs of one piece).
static func dress(root: Node, kit_material: Material, banner: Material = null) -> void:
	if kit_material == null or root == null:
		return
	for node in root.find_children("*", "Node3D", true, false):
		dress_piece(node, kit_material, banner)


## Dresses `node` alone if it is a kit piece: a run of the group `kit_multimesh`, or the root of an instanced piece of the kit.
static func dress_piece(node: Node, kit_material: Material, banner: Material = null) -> void:
	if kit_material == null:
		return
	if node is MultiMeshInstance3D and node.is_in_group(&"kit_multimesh"):
		# A run the builder gave a material of its own (a roof) keeps it.
		if (node as MultiMeshInstance3D).material_override == null:
			(node as MultiMeshInstance3D).material_override = kit_material
	elif node is Node3D and node.scene_file_path.begins_with("res://assets/env/kenney_town/"):
		var wears := banner if banner != null and node.scene_file_path.get_file().begins_with("banner") else kit_material
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = wears
