class_name GroundWave
extends Node3D
## A ring that spreads over the ground from a point and fades (the readability pass's heavy and perilous waves), or, as a
## billboard standing at a point in the air, a small ring that does the same (Abarax's parry ring). It grows to
## `max_radius` over `seconds` (physics time, so it stands still while the game is paused) and fades as it grows, then
## frees itself. Its look is render/shaders/ground_ring.gdshader.
##
## `make` builds one; whoever shows it adds it to the world and says where.

const SHADER := preload("res://render/shaders/ground_ring.gdshader")
## A wave lies this high above the ground, so the floor does not cut it, and below a body's feet.
const LIFT := 0.02
## The part of a wave's time it shows at full strength before it fades.
const FADE_FROM := 0.45
## The group every wave is in: for tests.
const GROUP := &"ground_waves"

## The radius the ring ends at, in metres, and how long it takes.
var max_radius := 1.0
var seconds := 0.4
## Whether it faces the camera instead of lying down.
var billboard := false
## The radius it starts at: 0 for a wave that spreads from a point, or a ring that is already there and goes outward.
var start_radius := 0.0

var _age := 0.0
var _mesh: MeshInstance3D
var _material: ShaderMaterial


## A wave of `radius` metres over `seconds`, in `color`, with a ring `ring_width` thick and a disc of `fill_alpha` inside;
## `billboard` stands it facing the camera.
## `from_radius` is where it starts (default: from nothing).
static func make(radius: float, seconds_: float, color: Color, ring_width: float, fill_alpha: float, face_camera := false, from_radius := 0.0) -> GroundWave:
	var wave := GroundWave.new()
	wave.start_radius = from_radius
	wave.max_radius = radius
	wave.seconds = seconds_
	wave.billboard = face_camera
	wave.name = "GroundWave"
	wave.add_to_group(GROUP)
	wave._build(color, ring_width, fill_alpha)
	return wave


## The ring's radius now, in metres.
func radius() -> float:
	return lerpf(start_radius, max_radius, _grown())


## How much of the ring shows now: all of it for the first FADE_FROM of its time, so that it reads as it spreads, then less
## and less to nothing.
func visibility() -> float:
	var t := clampf(_age / maxf(seconds, 0.001), 0.0, 1.0)
	return 1.0 - smoothstep(FADE_FROM, 1.0, t)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= seconds:
		queue_free()
		return
	_show()


func _build(color: Color, ring_width: float, fill_alpha: float) -> void:
	var plane := PlaneMesh.new()
	var extent := max_radius * 1.05
	plane.size = Vector2(extent * 2.0, extent * 2.0)
	if billboard:
		plane.orientation = PlaneMesh.FACE_Z
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = -1
	_material.set_shader_parameter(&"ring_color", color)
	_material.set_shader_parameter(&"extent", extent)
	_material.set_shader_parameter(&"ring_width", ring_width)
	_material.set_shader_parameter(&"fill_alpha", fill_alpha)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = plane
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_show()


# How far the wave has grown, 0 to 1: it eases out, fast at first.
func _grown() -> float:
	var t := clampf(_age / maxf(seconds, 0.001), 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)


func _show() -> void:
	_material.set_shader_parameter(&"radius", radius())
	_material.set_shader_parameter(&"fade", visibility())
	if billboard and is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			global_basis = camera.global_basis  # its +Z is toward the camera, which the quad's face is
