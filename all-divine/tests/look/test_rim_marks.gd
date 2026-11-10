extends TestCase
## The rim's two passes and the marks they share (render/rim_marks.gd; Rig.aura). Headless: what the rig puts over its
## meshes while a rim is on and takes off again, and that every body with a rim on holds a mark of its own.
## tests/render/test_rim_matrix.gd checks the pixels the passes draw.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const ABARAX := "res://data/palettes/abarax.tres"
const ROSE := Color("e8607e")


func _rig() -> Rig:
	var rig := track(load(RIG).instantiate()) as Rig
	rig.apply_palette(load(ABARAX) as Palette)
	return rig


func _meshes(rig: Rig) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in rig.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		found.append(node as MeshInstance3D)
	return found


func test_marks_are_taken_lowest_first_and_given_back() -> void:
	var before := RimMarks.taken()
	var a := RimMarks.take()
	var b := RimMarks.take()
	assert_true(a >= RimMarks.FIRST and a <= RimMarks.LAST, "a mark is 1 to 255, never 0, which is no body (%d)" % a)
	assert_true(b > a, "the next is another, higher (%d, %d)" % [a, b])
	assert_eq(RimMarks.taken(), before + 2)
	RimMarks.give_back(a)
	assert_eq(RimMarks.take(), a, "a mark given back is the next taken: the lowest free")
	RimMarks.give_back(a)
	RimMarks.give_back(b)
	assert_eq(RimMarks.taken(), before)
	RimMarks.give_back(0)
	assert_eq(RimMarks.taken(), before, "giving back no mark changes nothing")


func test_with_every_mark_taken_the_last_is_shared() -> void:
	var held: Array[int] = []
	while RimMarks.taken() < RimMarks.LAST:
		held.append(RimMarks.take())
	assert_eq(RimMarks.take(), RimMarks.LAST, "one more than there are: the last, shared")
	for mark in held:
		RimMarks.give_back(mark)


func test_each_mark_has_its_own_copy_of_the_two_shaders() -> void:
	assert_true(RimMarks.mark_shader(1) == RimMarks.MARK_SHADER, "mark 1's are the files themselves")
	assert_true(RimMarks.hull_shader(1) == RimMarks.HULL_SHADER)
	assert_true(RimMarks.MARK_SHADER.code.contains("\nstencil_mode write, compare_always, 1;\n"), "the mark pass writes its mark wherever it is drawn")
	assert_true(RimMarks.HULL_SHADER.code.contains("\nstencil_mode read, write, compare_not_equal, 1;\n"), "the hull is lit where the mark is another, and takes the mark")
	var mark := RimMarks.mark_shader(7)
	var hull := RimMarks.hull_shader(7)
	assert_eq(mark.code, RimMarks.MARK_SHADER.code.replace("compare_always, 1;", "compare_always, 7;"), "mark 7's differ in that number only")
	assert_eq(hull.code, RimMarks.HULL_SHADER.code.replace("compare_not_equal, 1;", "compare_not_equal, 7;"))
	assert_true(RimMarks.mark_shader(7) == mark and RimMarks.hull_shader(7) == hull, "and are made once")
	assert_eq(RimMarks.hull_shader(255).code, RimMarks.HULL_SHADER.code.replace("compare_not_equal, 1;", "compare_not_equal, 255;"))
	# The copies compile (a headless run compiles shaders, as Forward+): their uniforms are the file's.
	var names := hull.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
	assert_eq(names, ["rim_color", "rim_strength", "rim_width"], "the hull takes a colour, a strength and a width, and no push")


func test_a_shader_with_no_stencil_line_is_handed_back_as_it_is() -> void:
	var plain := Shader.new()
	plain.code = "shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n"
	var got: Shader = quietly(func() -> Shader: return RimMarks.with_reference(plain, 9))
	assert_true(got == plain, "there is nowhere to write the mark: the shader comes back unchanged (and an error says so)")


func test_an_aura_draws_the_mark_pass_then_the_hull_over_every_mesh_and_takes_them_off() -> void:
	var rig := _rig()
	var before := RimMarks.taken()
	for mesh in _meshes(rig):
		assert_true(mesh.material_overlay == null, "%s: nothing over it before any aura" % mesh.name)
	rig.aura(ROSE, 0.5)
	assert_eq(RimMarks.taken(), before + 1, "a rim that is on holds a mark")
	var hull := rig.rim_material()
	assert_true(hull != null, "the hull's material")
	var first := _meshes(rig)[0].material_overlay as ShaderMaterial
	assert_true(first != null and first != hull, "the pass over each mesh is the mark pass")
	if first == null:
		return
	assert_true(first.next_pass == hull, "and the hull is drawn after it")
	assert_true(first.render_priority < hull.render_priority, "every body's mark is drawn before any body's hull (%d, %d)" % [first.render_priority, hull.render_priority])
	assert_true(first.render_priority > Material.RENDER_PRIORITY_MIN, "and after the screen look's quad")
	var mark := 0
	for candidate in range(RimMarks.FIRST, RimMarks.LAST + 1):
		if first.shader == RimMarks.mark_shader(candidate):
			mark = candidate
			break
	assert_true(mark > 0, "the mark pass writes a mark")
	assert_true(hull.shader == RimMarks.hull_shader(mark), "and the hull reads the same one (%d)" % mark)
	for mesh in _meshes(rig):
		assert_true(mesh.material_overlay == first, "%s wears the passes" % mesh.name)
	assert_eq(hull.get_shader_parameter(&"rim_color"), ROSE)
	rig.clear_aura()
	for mesh in _meshes(rig):
		assert_true(mesh.material_overlay == null, "%s: taken off with the aura" % mesh.name)
	assert_eq(RimMarks.taken(), before, "and the mark given back")
	# A held aura (a tell drives it every frame) is the same passes, put on once.
	rig.hold_aura(ROSE, 0.7)
	rig.hold_aura(ROSE, 0.8)
	assert_eq(RimMarks.taken(), before + 1, "holding it again takes no second mark")
	assert_near(float(hull.get_shader_parameter(&"rim_strength")), 0.8, 1e-6)
	rig.clear_aura()
	assert_eq(RimMarks.taken(), before)


func test_an_aura_that_runs_out_gives_its_mark_back() -> void:
	var rig := _rig()
	var before := RimMarks.taken()
	rig.aura(ROSE, 0.1)
	assert_eq(RimMarks.taken(), before + 1)
	for i in 8:
		rig.tick(1.0 / 60)
	assert_false(rig.aura_active(), "over after its tenth of a second")
	assert_eq(RimMarks.taken(), before)
	assert_true(_meshes(rig)[0].material_overlay == null)


func test_two_bodies_with_rims_on_hold_different_marks() -> void:
	var a := _rig()
	var b := _rig()
	a.aura(ROSE, 1.0)
	b.aura(Color.WHITE, 1.0)
	assert_true(a.rim_material().shader != b.rim_material().shader, "each hull reads its own body's mark")
	assert_true((_meshes(a)[0].material_overlay as ShaderMaterial).shader != (_meshes(b)[0].material_overlay as ShaderMaterial).shader, "which its own mark pass writes")
	var mark_shader_of_a := (_meshes(a)[0].material_overlay as ShaderMaterial).shader
	a.clear_aura()
	var c := _rig()
	c.aura(ROSE, 1.0)
	assert_true((_meshes(c)[0].material_overlay as ShaderMaterial).shader == mark_shader_of_a, "a mark given back is used again: a fight goes round the same few")
	b.clear_aura()
	c.clear_aura()


func test_a_body_freed_with_its_rim_on_gives_its_mark_back() -> void:
	var before := RimMarks.taken()
	var rig := load(RIG).instantiate() as Rig
	add_child(rig)
	rig.apply_palette(load(ABARAX) as Palette)
	rig.aura(ROSE, 5.0)
	assert_eq(RimMarks.taken(), before + 1)
	rig.free()
	assert_eq(RimMarks.taken(), before)


# The rig finds its body's meshes once, when it is set up: a rim that is driven every frame does not walk the model
# again, and a mesh that joins the model later (an effect riding a bone) is no part of the body and gets no rim.
func test_the_rim_goes_on_the_bodys_own_meshes_found_once() -> void:
	var rig := _rig()
	var body := _meshes(rig)
	var extra := MeshInstance3D.new()
	extra.mesh = BoxMesh.new()
	rig.skeleton.add_child(extra)
	rig.hold_aura(ROSE, 1.0)
	assert_true(extra.material_overlay == null, "a mesh added after the rig was set up is not the body's")
	for mesh in body:
		assert_true(mesh.material_overlay != null, "%s is" % mesh.name)
	rig.clear_aura()
	assert_true(extra.material_overlay == null)
	# And a palette put on again dresses the same meshes.
	rig.apply_palette(load(ABARAX) as Palette)
	assert_true(extra.material_override == null, "nor is it dressed in the palette")
	extra.free()


# The passes over `rig`'s first mesh, in the order they are chained.
func _chain(rig: Rig) -> Array[ShaderMaterial]:
	var chain: Array[ShaderMaterial] = []
	var material := _meshes(rig)[0].material_overlay as ShaderMaterial
	while material != null:
		chain.append(material)
		material = material.next_pass as ShaderMaterial
	return chain


# Each mark's two shaders are new to the renderer the first time something is drawn with them, and it builds them on
# that frame: the first frame of a tell took twice as long as the next. So the rims a fight goes round (the first
# RimMarks.WARM marks) are drawn once when a region loads: a body wears their passes, showing nothing, for a few frames.
func test_warming_a_rig_draws_the_first_marks_passes_unseen_for_a_few_frames() -> void:
	var rig := _rig()
	RimMarks.forget()
	var taken := RimMarks.taken()
	rig.warm_rim()
	assert_eq(RimMarks.made(), 2 * RimMarks.WARM, "the two shaders of each of the first %d marks are made" % RimMarks.WARM)
	var chain := _chain(rig)
	assert_eq(chain.size(), 2 * RimMarks.WARM, "and the body wears them all, one pass after another")
	if chain.size() != 2 * RimMarks.WARM:
		return
	for i in RimMarks.WARM:
		var mark := RimMarks.FIRST + i
		var mark_pass := chain[2 * i]
		var hull := chain[2 * i + 1]
		assert_true(mark_pass.shader == RimMarks.mark_shader(mark), "mark %d's mark pass" % mark)
		assert_true(hull.shader == RimMarks.hull_shader(mark), "then its hull")
		assert_eq(mark_pass.render_priority, Rig.RIM_MARK_PRIORITY, "drawn where an aura's is")
		assert_eq(hull.render_priority, Rig.RIM_MARK_PRIORITY + 1)
		var strength: Variant = hull.get_shader_parameter(&"rim_strength")
		assert_true(strength == null or float(strength) == 0.0, "a hull with no strength shows nothing (%s)" % str(strength))
	for mesh in _meshes(rig):
		assert_true(mesh.material_overlay == chain[0], "%s wears the passes" % mesh.name)
	assert_eq(RimMarks.taken(), taken, "warming holds no mark")
	assert_false(rig.aura_active(), "and is no aura")
	# Taking each of those marks now makes nothing.
	var held: Array[int] = []
	for i in RimMarks.WARM:
		var mark := RimMarks.take()
		held.append(mark)
		RimMarks.mark_shader(mark)
		RimMarks.hull_shader(mark)
	assert_eq(RimMarks.made(), 2 * RimMarks.WARM, "a rim that comes on later finds its shaders made (marks %s)" % str(held))
	for mark in held:
		RimMarks.give_back(mark)
	# Drawn, they come off.
	for i in Rig.WARM_FRAMES - 1:
		await get_tree().process_frame
	assert_true(_meshes(rig)[0].material_overlay == chain[0], "they stay for %d frames, to be drawn at least once" % Rig.WARM_FRAMES)
	await get_tree().process_frame
	await get_tree().process_frame
	for mesh in _meshes(rig):
		assert_true(mesh.material_overlay == null, "%s: and then are taken off" % mesh.name)


func test_an_aura_takes_over_from_the_warming_passes() -> void:
	var rig := _rig()
	rig.warm_rim()
	rig.hold_aura(ROSE, 1.0)
	var mark_pass := _meshes(rig)[0].material_overlay as ShaderMaterial
	assert_true(mark_pass != null and mark_pass.next_pass == rig.rim_material(), "the aura's own two passes are what the body wears")
	for i in Rig.WARM_FRAMES + 2:
		await get_tree().process_frame
	for mesh in _meshes(rig):
		assert_true(mesh.material_overlay == mark_pass, "%s: the end of the warming leaves them on" % mesh.name)
	# With an aura on there is nothing to warm with: the body's passes are the aura's.
	rig.warm_rim()
	assert_true(_meshes(rig)[0].material_overlay == mark_pass, "warming again changes nothing while it shows")
	rig.clear_aura()
	for i in Rig.WARM_FRAMES + 2:
		await get_tree().process_frame
		assert_true(_meshes(rig)[0].material_overlay == null, "and nothing is left over the body when it goes")
