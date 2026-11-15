extends Region
## The Bilibara stretch: a Region that lays a soft dark ellipse flat under every actor in the scene tree (render/shaders/contact_shadow.gdshader).
## On pale snow it is what plants a fighter. The sun's shadow of a body is short at noon and is no shadow at all where a front already shades the
## ground, so it cannot be what does it. The ellipses are one MultiMesh (one draw call for all of them, however many fighters): each frame it holds
## one for every actor that is in the tree and shown, under his feet.

const SHADER := preload("res://render/shaders/contact_shadow.gdshader")
## Metres from side to side, and above the ground (clear of z-fighting, below the soles).
const SIZE := 1.9
const LIFT := 0.012
## The most ellipses the MultiMesh holds to begin with (it grows by doubling when a fight has more bodies).
const FIRST_ROOM := 16

var _holder: Node3D
var _multi: MultiMesh
var _material: ShaderMaterial
var _inked: Array[Rig] = []  # the rigs this region gave the rim's dark edge: it takes it back from them when it leaves the tree
var _points := PackedVector3Array()  # where each ellipse is now (a MultiMesh keeps its transforms with the renderer, which a headless run has not)


func _ready() -> void:
	_holder = Node3D.new()
	_holder.name = "ContactShadows"
	add_child(_holder)
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = -1  # before the other transparent things
	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.mesh = quad
	_multi.instance_count = FIRST_ROOM
	_multi.visible_instance_count = 0
	_multi.custom_aabb = AABB(Vector3(-200, -1, -400), Vector3(600, 2, 600))
	var shadows := MultiMeshInstance3D.new()
	shadows.name = "Shadows"
	shadows.multimesh = _multi
	shadows.material_override = _material
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadows.layers = Layers.RENDER_WORLD
	shadows.top_level = true
	_holder.add_child(shadows)
	set_process(true)


func _process(_delta: float) -> void:
	var under: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor != null and actor.is_inside_tree() and actor.is_visible_in_tree():
			under.append(actor.global_position + Vector3(0.0, LIFT, 0.0))
			_ink(actor.rig)
	if under.size() > _multi.instance_count:
		# Changing the count empties the instances: all of them are set again below.
		var room := _multi.instance_count
		while room < under.size():
			room *= 2
		_multi.instance_count = room
	for i in under.size():
		_multi.set_instance_transform(i, Transform3D(Basis(), under[i]))
	_multi.visible_instance_count = under.size()
	_points = PackedVector3Array(under)


# The stretch's pale ground is what a rim's dark edge is for (Rig.RIM_INK_PX): every body in the tree has it, a foe from its first frame.
func _ink(rig: Rig) -> void:
	if rig != null and rig.rim_ink_px != Rig.RIM_INK_PX:
		rig.rim_ink_px = Rig.RIM_INK_PX
		if not _inked.has(rig):
			_inked.append(rig)


# A body that goes on to another region (the player's) has no edge there.
func _exit_tree() -> void:
	for rig in _inked:
		if is_instance_valid(rig):
			rig.rim_ink_px = 0.0
	_inked.clear()


## Where the ellipses lie now, one for each actor in the tree that is shown: for the tests.
func shadow_points() -> PackedVector3Array:
	return _points
