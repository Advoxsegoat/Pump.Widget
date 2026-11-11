class_name SlamRing
extends Node3D
## The heavy Knuckle's ground slam, drawn on the ground (data/fx/slam_warning.tres and slam_wave.tres). Both are in the red
## of a perilous attack's own wave (the readability tuning's wave_color), never the gold of a clear-out.
##
## The warning (`wave` false) is the ring as it stands: the whole radius of the blow's hitbox, there from its first frame
## and growing stronger up to the blow, so that a player standing outside it can see he is safe and one inside it can see
## how far he has to go. The tell's own wave (ActorFx, 1.8 m) is smaller than this blow and grows from nothing, so it cannot
## say where this one lands. The wave (`wave` true) is a GroundWave of the same radius, going out at the blow.
##
## It lies on the ground, never over a body (the ring's shader is read against the depth buffer, as the waves' are).

## The group every ring is in, and the one its kind is in: for tests.
const GROUP := &"slam_ring"
const WARNING_GROUP := &"slam_warning"
const WAVE_GROUP := &"slam_wave"
## How strong the warning shows at its first frame; it climbs to full by `seconds`.
const WARNING_START := 0.4

## The radius of the ring: the slam's hitbox (slam_ring in the knuckle's rig).
@export var radius := 2.2
## How long the warning stands: from the tell to the blow.
@export var seconds := 0.65
## Whether this is the wave at the blow instead of the warning before it.
@export var wave := false

var _age := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	add_to_group(GROUP)
	var tuning := ActorFx.TUNING
	if wave:
		add_to_group(WAVE_GROUP)
		var out := GroundWave.make(radius, tuning.wave_seconds, tuning.wave_color, tuning.wave_ring_width, tuning.wave_fill_alpha)
		add_child(out)
		out.position = Vector3.UP * GroundWave.LIFT
		return
	add_to_group(WARNING_GROUP)
	var plane := PlaneMesh.new()
	var extent := radius * 1.05
	plane.size = Vector2(extent * 2.0, extent * 2.0)
	_material = ShaderMaterial.new()
	_material.shader = GroundWave.SHADER
	_material.render_priority = -1
	_material.set_shader_parameter(&"ring_color", tuning.wave_color)
	_material.set_shader_parameter(&"extent", extent)
	_material.set_shader_parameter(&"ring_width", tuning.wave_ring_width)
	_material.set_shader_parameter(&"fill_alpha", tuning.wave_fill_alpha)
	_material.set_shader_parameter(&"radius", radius)
	_material.set_shader_parameter(&"fade", WARNING_START)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = plane
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.position = Vector3.UP * GroundWave.LIFT


func _physics_process(delta: float) -> void:
	if wave:
		return
	_age += delta
	if _age >= seconds:
		queue_free()
		return
	_material.set_shader_parameter(&"fade", lerpf(WARNING_START, 1.0, _age / maxf(seconds, 0.001)))


## The radius the warning shows now, in metres (0 for the wave: its own GroundWave shows its radius).
func shown_radius() -> float:
	return float(_material.get_shader_parameter(&"radius")) if _material != null else 0.0


## The colour the warning is drawn in.
func shown_colour() -> Color:
	return _material.get_shader_parameter(&"ring_color") as Color if _material != null else Color.TRANSPARENT
