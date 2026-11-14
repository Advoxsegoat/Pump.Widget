class_name InflatedWarm
extends Node3D
## Has the renderer build, with a region's first frames, the shaders a thicker body (ActorDef.body_inflate) is drawn with, so that the
## first one of them to walk in, and the first tell that lights its rim, build nothing: the same reason Rig.warm_rim has Abarax wear the
## rims a fight will light. The thicker variants (InflatedShader) are shaders only such a body uses, so Abarax's warming does not cover
## them. A box a centimetre wide is hidden under the floor at the player's feet, drawn with the thicker character shader and, over it,
## the thicker mark pass of each of the first RimMarks.WARM marks, for Rig.WARM_FRAMES frames; then it goes. A region whose waves name no
## such body makes none.

const GROUP := &"inflated_warm"

var _left := Rig.WARM_FRAMES


## One under `rig`, if any of `defs` is thicker; null if none is.
static func start(rig: Rig, defs: Array) -> InflatedWarm:
	if not defs.any(func(d: ActorDef) -> bool: return d != null and d.body_inflate > 0.0):
		return null
	var warm := InflatedWarm.new()
	warm.name = "InflatedWarm"
	warm.add_to_group(GROUP)
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.01
	box.mesh = mesh
	box.position = Vector3(0.0, -0.3, 0.0)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := ShaderMaterial.new()
	body.shader = InflatedShader.of(Rig.TOON_SHADER)
	box.material_override = body
	var chain: ShaderMaterial = null
	for mark in range(RimMarks.FIRST + RimMarks.WARM - 1, RimMarks.FIRST - 1, -1):
		chain = Rig._rim_pass(InflatedShader.of(RimMarks.mark_shader(mark)), Rig.RIM_MARK_PRIORITY, chain)
	box.material_overlay = chain
	warm.add_child(box)
	rig.add_child(warm)
	return warm


func _physics_process(_delta: float) -> void:
	_left -= 1
	if _left <= 0:
		queue_free()
