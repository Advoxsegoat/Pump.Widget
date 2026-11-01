extends TestCase
## Rig.flash: the body goes a colour for a moment, by the toon shader's flash_color and flash_amount, which fade
## linearly as the rig ticks (a rig that is frozen by hit-stop does not tick, so a flash holds through it). The
## picture is checked on a display in tests/render/test_toon_palette.gd. Headless.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const PALETTE := "res://data/palettes/abarax.tres"
const ROSE := Color("e8607e")
const FRAME := 1.0 / 60.0


func _rig(with_palette := true) -> Rig:
	var rig := track((load(RIG) as PackedScene).instantiate()) as Rig
	if with_palette:
		rig.apply_palette(load(PALETTE) as Palette)
	return rig


# The one material the rig's meshes are drawn with.
func _material(rig: Rig) -> ShaderMaterial:
	var meshes := rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	return (meshes[0] as MeshInstance3D).material_override as ShaderMaterial


func _amount(rig: Rig) -> float:
	return _material(rig).get_shader_parameter(&"flash_amount")


func test_flash_sets_and_fades_the_shader_parameter() -> void:
	var rig := _rig()
	rig.flash(Color.WHITE, 2.0 * FRAME)
	assert_eq(_material(rig).get_shader_parameter(&"flash_color"), Color.WHITE)
	assert_near(_amount(rig), 1.0, 1e-6, "full as it starts")
	rig.tick(FRAME)
	assert_near(_amount(rig), 0.5, 1e-6, "half a frame later... a frame later, of two")
	rig.tick(FRAME)
	assert_near(_amount(rig), 0.0, 1e-6, "gone after its two frames")
	rig.tick(FRAME)
	assert_near(_amount(rig), 0.0, 1e-6, "and stays gone")


func test_a_longer_flash_fades_linearly() -> void:
	var rig := _rig()
	rig.flash(ROSE, 0.25)
	assert_eq(_material(rig).get_shader_parameter(&"flash_color"), ROSE)
	for i in 15:
		assert_near(_amount(rig), 1.0 - i / 15.0, 1e-4, "after %d of 15 frames" % i)
		rig.tick(FRAME)
	assert_near(_amount(rig), 0.0, 1e-4, "and out at 0.25 s")


func test_the_flash_holds_while_the_rig_does_not_tick() -> void:
	# What hit-stop does: the rig is not ticked, so a flash that starts as the blow lands shows through the freeze.
	var rig := _rig()
	rig.flash(Color.WHITE, 2.0 * FRAME)
	await frames(4)
	assert_near(_amount(rig), 1.0, 1e-6)


func test_a_new_flash_replaces_the_one_before() -> void:
	var rig := _rig()
	rig.flash(Color.WHITE, 0.5)
	rig.tick(0.25)
	rig.flash(ROSE, 0.25)
	assert_eq(_material(rig).get_shader_parameter(&"flash_color"), ROSE, "the new colour")
	assert_near(_amount(rig), 1.0, 1e-6, "from the top again")
	rig.tick(0.125)
	assert_near(_amount(rig), 0.5, 1e-6, "over the new time")


func test_a_flash_of_no_time_is_no_flash() -> void:
	var rig := _rig()
	rig.flash(Color.WHITE, 0.0)
	assert_near(_amount(rig), 0.0, 1e-6)
	rig.flash(Color.WHITE, -1.0)
	assert_near(_amount(rig), 0.0, 1e-6)


func test_a_flash_is_one_rigs_own() -> void:
	var one := _rig()
	var two := _rig()
	one.flash(Color.WHITE, 0.5)
	assert_near(_amount(one), 1.0, 1e-6)
	assert_near(_amount(two), 0.0, 1e-6, "the other body is not flashed")


func test_a_rig_with_no_palette_has_nothing_to_flash_and_does_not_mind() -> void:
	# The model keeps the materials it was imported with, which have no flash; flashing does nothing and is no error.
	var rig := _rig(false)
	rig.flash(Color.WHITE, 0.1)
	rig.tick(FRAME)
	assert_eq(rig.palette, null)
