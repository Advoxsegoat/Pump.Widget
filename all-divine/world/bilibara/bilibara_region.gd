extends Region
## The Bilibara stretch: a Region that lays a soft dark ellipse flat under every actor in the scene tree (render/shaders/contact_shadow.gdshader).
## On pale snow it is what plants a fighter. The sun's shadow of a body is short at noon and is no shadow at all where a front already shades the
## ground, so it cannot be what does it. The ellipse follows the actor each frame, hides with him and is freed with him.

const SHADER := preload("res://render/shaders/contact_shadow.gdshader")
## Metres from side to side, and above the ground (clear of z-fighting, below the soles).
const SIZE := 1.9
const LIFT := 0.012

var _holder: Node3D
var _mesh: QuadMesh
var _material: ShaderMaterial
var _shadows := {}  # Actor -> MeshInstance3D


func _ready() -> void:
	_holder = Node3D.new()
	_holder.name = "ContactShadows"
	add_child(_holder)
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(SIZE, SIZE)
	_mesh.orientation = PlaneMesh.FACE_Y
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = -1  # before the other transparent things
	set_process(true)


func _process(_delta: float) -> void:
	for key: Variant in _shadows.keys():
		if not is_instance_valid(key) or not (key as Node).is_inside_tree():
			var gone := _shadows[key] as Node
			_shadows.erase(key)
			_holder.remove_child(gone)
			gone.queue_free()
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor == null:
			continue
		if not _shadows.has(actor):
			var shadow := MeshInstance3D.new()
			shadow.name = "Shadow_%s" % actor.name
			shadow.mesh = _mesh
			shadow.material_override = _material
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shadow.layers = Layers.RENDER_WORLD
			shadow.top_level = true
			_holder.add_child(shadow)
			_shadows[actor] = shadow
		var mesh := _shadows[actor] as MeshInstance3D
		mesh.global_position = actor.global_position + Vector3(0.0, LIFT, 0.0)
		mesh.visible = actor.is_visible_in_tree()
