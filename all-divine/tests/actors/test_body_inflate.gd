extends TestCase
## A body drawn thicker (ActorDef.body_inflate, Rig.set_body_inflate, Task 14e): the toon shader pushes each vertex out along its
## normal, and only the picture grows. The rim's passes and an afterimage of the body grow with it; nothing the game measures
## moves, whatever the amount. How it looks (no cracks, nothing changed at 0) is tests/render/test_body_inflate_shots.gd.

const DEFS := ["abarax", "knuckle_1", "knuckle_2", "knuckle_3", "knuckle_blade", "knuckle_drummer", "knuckle_heavy"]
const HEAVY := "res://data/actors/knuckle_heavy.tres"
const AMOUNT := 0.03


func _def(id: String) -> ActorDef:
	return load("res://data/actors/%s.tres" % id) as ActorDef


# The def of `id` with its body thickened by `metres`.
func _thick(id: String, metres: float) -> ActorDef:
	var def := _def(id).duplicate() as ActorDef
	def.body_inflate = metres
	return def


func test_only_the_heavy_is_drawn_thicker() -> void:
	for id in DEFS:
		if id == "knuckle_heavy":
			assert_true(_def(id).body_inflate >= 0.02 and _def(id).body_inflate <= 0.05, "the heavy: %.3f m, between 2 and 5 cm" % _def(id).body_inflate)
		else:
			assert_eq(_def(id).body_inflate, 0.0, "%s is drawn as the model is" % id)
	assert_eq(ActorDef.new().body_inflate, 0.0, "a new def draws the model as it is")


func test_the_shaders_get_the_inflate_in_the_models_own_units() -> void:
	var arena := TestArena.make(self)
	var heavy := TestArena.spawn(arena, _thick("knuckle_heavy", AMOUNT), ScriptBrain.new([]), Vector3.ZERO, "Heavy")
	await frames(2)
	var rig := heavy.rig
	assert_near(rig.body_inflate, AMOUNT, 1e-9)
	var model_units := AMOUNT / 1.18
	assert_near(rig.shader_inflate(), model_units, 1e-6, "the Model is 1.18 times larger: the shader pushes by %.4f so the body grows %.3f m" % [model_units, AMOUNT])
	for mesh in rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false):
		var material := (mesh as MeshInstance3D).material_override as ShaderMaterial
		assert_near(float(material.get_shader_parameter(&"inflate")), model_units, 1e-6, "%s is drawn with it" % mesh.name)
	rig.aura(Color.RED, 1.0)
	assert_near(float(rig.rim_material().get_shader_parameter(&"inflate")), model_units, 1e-6, "the rim's hull pass grows from the thicker body")
	var overlay := ((rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D).material_overlay as ShaderMaterial
	assert_near(float(overlay.get_shader_parameter(&"inflate")), model_units, 1e-6, "and so does its mark pass")
	rig.apply_palette(heavy.def.palette)  # a dye replaces the material
	var mesh0 := rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert_near(float((mesh0.material_override as ShaderMaterial).get_shader_parameter(&"inflate")), model_units, 1e-6, "a new palette keeps it")
	var pose := Afterimage.capture(rig)
	assert_near(float(pose["inflate"]), model_units, 1e-6, "the afterimage's capture carries it")
	var image := Afterimage.spawn(rig, Color.WHITE, 12, pose)
	await frames(1)
	var found := 0
	for node in image.find_children("*", "MeshInstance3D", true, false):
		var depth := (node as MeshInstance3D).material_override as ShaderMaterial
		assert_near(float(depth.get_shader_parameter(&"inflate")), model_units, 1e-6, "the copy's depth pass grows with the body")
		assert_near(float((depth.next_pass as ShaderMaterial).get_shader_parameter(&"inflate")), model_units, 1e-6, "and its colour pass")
		found += 1
	assert_true(found > 0, "the copy has meshes (%d)" % found)


func test_a_body_at_zero_is_given_zero() -> void:
	var arena := TestArena.make(self)
	var abarax := TestArena.spawn(arena, _def("abarax"), ScriptBrain.new([]), Vector3.ZERO, "Abarax")
	await frames(1)
	assert_eq(abarax.rig.shader_inflate(), 0.0)
	for mesh in abarax.rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false):
		assert_eq(float(((mesh as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(&"inflate")), 0.0)


# The numbers the game measures of a heavy playing the haymaker, drawn `metres` thicker: its hurtbox, each hitbox's place and size,
# its body capsule, where its feet and hands are and where it stands.
func _measured(metres: float) -> Dictionary:
	var origin := Vector3.ZERO
	var arena := TestArena.make(self)
	var heavy := TestArena.spawn(arena, _thick("knuckle_heavy", metres), ScriptBrain.new([{"frames": 1, "press": [&"palm"]}, {"frames": 200}]), Vector3.ZERO, "Heavy")
	heavy.place(Transform3D(Basis.IDENTITY, origin))
	var out := {}
	for at in [10, 40, 44, 70]:
		await Duel.play_to(self, heavy, at)
		var hits := {}
		for zone in heavy.rig.get_node(^"Hitboxes").get_children():
			var shape := heavy.rig.hitbox_shape(StringName(zone.name))
			hits[zone.name] = [shape.global_transform.origin - origin, shape.global_basis.get_scale(), shape.shape.get_debug_mesh().get_aabb().size]
		var bones := {}
		for bone in [&"foot_l", &"foot_r", &"hand_l", &"hand_r", &"Head"]:
			bones[bone] = heavy.rig.shown_pose(bone).origin
		var hurt := heavy.rig.hurtbox.get_node(^"shape") as CollisionShape3D
		out[at] = {"hits": hits, "bones": bones, "hurt": hurt.global_transform.origin - origin, "hurt_scale": hurt.global_basis.get_scale(),
				"stands": heavy.global_position - origin, "radius": heavy.spacing.radius()}
	arena.free()
	return out


func test_nothing_the_game_measures_moves() -> void:
	var plain: Dictionary = await _measured(0.0)
	var thick: Dictionary = await _measured(0.05)
	for at in [10, 40, 44, 70]:
		assert_eq(str(thick[at]), str(plain[at]), "frame %d of the haymaker: hitboxes, hurtbox, body capsule, feet, hands and place are the same drawn 5 cm thicker" % at)
