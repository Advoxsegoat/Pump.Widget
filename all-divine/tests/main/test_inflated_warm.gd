extends TestCase
## The shaders a thicker body is drawn with are built with a region's first frames (InflatedWarm), before the first one walks in: the yard's
## waves name the heavy Knuckle, so the yard makes the thicker character shader and the thicker mark passes of the first RimMarks.WARM
## marks, and draws them (a hidden box at the player's feet) for Rig.WARM_FRAMES frames; a region whose waves are all thin makes none.

const MAIN := "res://main/main.tscn"


func _main() -> Main:
	Game.reset()
	return track((load(MAIN) as PackedScene).instantiate()) as Main


func test_the_yard_draws_the_heavys_shaders_before_he_is_sent() -> void:
	var main := _main()
	assert_true(main.arena().waves.any(func(w: ArenaWave) -> bool: return w.defs.any(func(d: ActorDef) -> bool: return d.body_inflate > 0.0)), "the yard sends a thicker body")
	var warm := get_tree().get_nodes_in_group(InflatedWarm.GROUP)
	assert_eq(warm.size(), 1, "one warming box is drawn with the yard's first frames")
	if warm.is_empty():
		return
	var box := warm[0].get_child(0) as MeshInstance3D
	assert_true(box.material_override is ShaderMaterial and (box.material_override as ShaderMaterial).shader == InflatedShader.of(Rig.TOON_SHADER), "with the thicker character shader")
	var passes := 0
	var pass_material := box.material_overlay as ShaderMaterial
	while pass_material != null:
		assert_true(InflatedShader.is_inflated(pass_material.shader), "and a thicker mark pass")
		passes += 1
		pass_material = pass_material.next_pass as ShaderMaterial
	assert_eq(passes, RimMarks.WARM, "for each of the first %d marks" % RimMarks.WARM)
	for i in Rig.WARM_FRAMES + 2:
		await get_tree().physics_frame
	assert_eq(get_tree().get_nodes_in_group(InflatedWarm.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).size(), 0, "and it is gone after them")


func test_no_thicker_body_no_warming() -> void:
	var thin: Array = [load("res://data/actors/knuckle_1.tres"), load("res://data/actors/abarax.tres")]
	var rig := track((load("res://data/actors/abarax.tres") as ActorDef).rig_scene.instantiate()) as Rig
	assert_eq(InflatedWarm.start(rig, thin), null, "a wave of thin bodies makes none")
	assert_eq(get_tree().get_nodes_in_group(InflatedWarm.GROUP).size(), 0)
