extends TestCase
## ActorFx: what an actor shows and sounds when its moves' marks pass and when it is hit. Fighters are the Duel's
## (a at the origin, b a metre in front; a far b, at 6 m, is out of reach, so a swing hits nothing).
##
## A frame is the actor's; after `await frames(1)` the test is at the end of a tick, where Sfx holds what that
## tick played (it forgets at the start of each). The jab (pressed on frame 1) sounds its whoosh on frame 6 (its f5)
## and starts its trail and lands on frame 11 (its f10).

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const FX_IDS: Array[StringName] = [&"hit_spark", &"palm_trail", &"roll_dust", &"glint", &"perilous_rose", &"charge_glow"]
const ROSE := Color("e8607e")


# The live effects of `id`, in the order they were shown.
func _live(id: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node in get_tree().get_nodes_in_group(ActorFx.GROUP):
		if node.get_meta(&"fx", &"") == id:
			found.append(node)
	return found


# What Sfx played on each of the actor's frames up to `last`: {frame: [ids]}.
func _sounds(a: Actor, last: int) -> Dictionary:
	var by_frame := {}
	while a.frame < last:
		await frames(1)
		by_frame[a.frame] = Sfx.last_played().duplicate()
	return by_frame


func _fixture_move(a: Actor, marks: Array, id := &"fixture") -> MoveData:
	var clip := a.rig.tree.get_animation(&"palm_jab").duplicate(true) as Animation
	Marks.write(clip, marks)
	a.rig.tree.get_animation_library(&"").add_animation(id, clip)
	var move := MoveData.new()
	move.id = id
	move.kind = MoveData.Kind.OTHER
	move.clip = id
	move.root_motion = false
	return move


func _mark(frame: int, kind: StringName, args := {}) -> Dictionary:
	return {"time": Marks.time_of(frame), "kind": kind, "args": args}


func test_every_fx_def_is_data_with_a_scene_that_rides_a_bone_of_the_rig() -> void:
	var rig := (load("res://actors/abarax/abarax_rig.tscn") as PackedScene).instantiate() as Node
	var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for id in FX_IDS:
		var def := Registry.fetch(&"fx", id) as FxDef
		assert_ne(def, null, "the FxDef %s" % id)
		if def == null:
			continue
		assert_eq(def.id, id)
		assert_true(def.scene != null and def.lifetime > 0.0, "%s has a scene and a lifetime" % id)
		var node := def.scene.instantiate()
		assert_true(node is GPUParticles3D, "%s is a particle effect" % id)
		node.free()
		assert_true(def.bone == &"" or skeleton.find_bone(def.bone) >= 0, "%s rides a bone Abarax has (%s)" % [id, def.bone])
	rig.free()


func test_the_hit_spark_is_twelve_gold_and_white_texels_over_a_fifth_of_a_second() -> void:
	var spark := (Registry.fetch(&"fx", &"hit_spark") as FxDef).scene.instantiate() as GPUParticles3D
	assert_eq(spark.amount, 12)
	assert_near(spark.lifetime, 0.2, 1e-6)
	assert_true(spark.one_shot, "a burst")
	var quad := spark.draw_pass_1 as QuadMesh
	assert_vec_near(Vector3(quad.size.x, quad.size.y, 0.0), Vector3(PixelSnap.TEXEL, PixelSnap.TEXEL, 0.0), 1e-6, "one texel each")
	var colours := ((spark.process_material as ParticleProcessMaterial).color_initial_ramp as GradientTexture1D).gradient.colors
	assert_true(colours.has(Color("e8c170")) and colours.has(Color.WHITE), "gold #e8c170 and white: %s" % [colours])
	spark.free()


func test_marks_spawn_their_fx_and_sounds() -> void:
	# A jab at nothing: its whoosh on frame 6 (f5), one palm_trail on its left hand on frame 11 (f10).
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 60}], [], 6.0)
	var a: Actor = run["a"]
	var sounds := await _sounds(a, 12)
	for f in sounds:
		assert_eq(sounds[f], [&"palm_whoosh"] as Array if f == 6 else [], "frame %d" % f)
	var trails := _live(&"palm_trail")
	assert_eq(trails.size(), 1, "one trail")
	assert_true(trails[0].get_parent() is BoneAttachment3D and trails[0].get_parent().bone_name == &"hand_l", "riding the left hand")
	assert_eq(_live(&"hit_spark").size(), 0, "no spark: nothing was hit")
	var trail := trails[0]
	await frames(40)
	assert_false(is_instance_valid(trail), "and it is gone after its lifetime (0.4 s)")


func test_the_cross_trail_rides_the_right_hand() -> void:
	var run := Duel.make(self, [{"frames": 60}], [], 6.0)
	var a: Actor = run["a"]
	a.runner.start(Registry.fetch(&"moves", &"palm_cross") as MoveData)
	await Duel.play_to(self, a, 16)
	var trails := _live(&"palm_trail")
	assert_eq(trails.size(), 1)
	assert_true(trails[0].get_parent() is BoneAttachment3D and trails[0].get_parent().bone_name == &"hand_r", "the cross is thrown with the right")


func test_a_full_charge_glows_and_hums() -> void:
	# The heavy palm held from frame 1 is at its mark from frame 11 and full 40 frames later, on frame 51: the glow is
	# shown on the spine and the hum sounds then, and not before (the whoosh of the blow comes later, at f15).
	var steps := [{"frames": 1, "press": [&"heavy"], "hold": [&"heavy"]}, {"frames": 70, "hold": [&"heavy"]}]
	var run := Duel.make(self, steps, [], 6.0)
	var a: Actor = run["a"]
	var sounds := await _sounds(a, 50)
	assert_eq(_live(&"charge_glow").size(), 0, "nothing glows while the charge builds")
	for f in sounds:
		assert_false(sounds[f].has(&"charge_hum"), "no hum on frame %d" % f)
	sounds = await _sounds(a, 51)
	assert_eq(sounds[51], [&"charge_hum"] as Array, "the hum, as it fills")
	var glows := _live(&"charge_glow")
	assert_eq(glows.size(), 1, "and the glow")
	assert_true(glows[0].get_parent() is BoneAttachment3D and glows[0].get_parent().bone_name == &"spine_03", "on his chest")


func test_a_charge_let_go_early_shows_nothing() -> void:
	var steps := [{"frames": 1, "press": [&"heavy"], "hold": [&"heavy"]}, {"frames": 19, "hold": [&"heavy"]}, {"frames": 60}]
	var run := Duel.make(self, steps, [], 6.0)
	var sounds := await _sounds(run["a"], 70)
	for f in sounds:
		assert_false(sounds[f].has(&"charge_hum"), "no hum on frame %d" % f)
	assert_eq(_live(&"charge_glow").size(), 0)


func test_a_roll_sounds_its_cloth_and_landing_and_kicks_up_dust_at_the_feet() -> void:
	var run := Duel.make(self, [{"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)}, {"frames": 60}], [], 6.0)
	var a: Actor = run["a"]
	var sounds := await _sounds(a, 30)
	var heard := []
	for f in sounds:
		for id in sounds[f]:
			heard.append([f, id])
	assert_eq(heard, [[1, &"roll_cloth"], [15, &"roll_land"]], "the cloth as it starts, the landing at f14")
	var dust := _live(&"roll_dust")
	assert_eq(dust.size(), 1, "one puff")
	assert_false(dust[0].get_parent() is BoneAttachment3D, "left on the ground, not riding a bone")


func test_a_hit_plays_impact_surface_and_voice_layers() -> void:
	# The target's poise (20) is more than the jab's 6: no flinch, so no reaction move to add its own sounds.
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 60}], [], 1.0, Duel.def(ActorDef.Team.ENEMY, 20.0))
	var a: Actor = run["a"]
	var sounds := await _sounds(a, 11)
	assert_eq(sounds[11], [&"impact_palm", &"surface_cloth"] as Array, "the blow's impact and the target's cloth; its voice is empty, which plays nothing")
	# The same with a voice: three layers, in the order impact, surface, voice.
	(run["arena"] as Node).free()
	var voiced := Duel.def(ActorDef.Team.ENEMY, 20.0)
	voiced.hurt_voice = &"catch_snap"
	var again := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 60}], [], 1.0, voiced)
	var heard := await _sounds(again["a"], 11)
	assert_eq(heard[11], [&"impact_palm", &"surface_cloth", &"catch_snap"] as Array, "three layers")


func test_a_jab_that_flinches_plays_each_layer_once_and_the_flinch_its_cloth() -> void:
	# The Duel's target (poise 5) flinches at the jab's 6, with a voice. The blow plays impact, surface and voice
	# once each; the flinch adds cloth moving (roll_cloth), not a second surface_cloth over the blow's.
	var voiced := Duel.def(ActorDef.Team.ENEMY, 5.0)
	voiced.hurt_voice = &"catch_snap"
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 60}], [], 1.0, voiced)
	var b: Actor = run["b"]
	var heard := await _sounds(run["a"], 11)
	assert_eq(b.runner.current.id if b.runner.current != null else &"", &"flinch", "the jab flinched it")
	var layers: Array = heard[11]
	for id in [&"impact_palm", &"surface_cloth", &"catch_snap", &"roll_cloth"]:
		assert_eq(layers.count(id), 1, "%s once: %s" % [id, layers])
	assert_eq(layers.size(), 4, "and nothing else: %s" % [layers])


func test_a_hit_shows_a_spark_flashes_the_body_white_and_shakes_the_camera() -> void:
	var stage := track(STAGE_SCENE.instantiate()) as PixelStage
	var camera := CameraRig.new()
	camera.stage = stage
	stage.world.add_child(camera)
	var jab := (Registry.fetch(&"moves", &"palm_jab") as MoveData).duplicate() as MoveData
	var palm := (jab.hits[&"palm"] as HitProfile).duplicate() as HitProfile
	palm.shake = 0.4
	jab.hits = {&"palm": palm}
	var run := Duel.make(self, [{"frames": 60}], [], 1.0, Duel.def(ActorDef.Team.ENEMY, 20.0))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var landed: Array[HitEvent] = []
	a.hit_landed.connect(func(_r: HitResult, e: HitEvent) -> void: landed.append(e))
	a.runner.start(jab)
	await Duel.play_to(self, a, 10)
	assert_eq(landed.size(), 1, "the jab landed")
	assert_eq(_live(&"hit_spark").size(), 1, "one spark")
	var spark := _live(&"hit_spark")[0] as Node3D
	assert_vec_near(spark.global_position, landed[0].point, 1e-4, "where the hand met the body")
	assert_false(spark.get_parent() is BoneAttachment3D, "left in the world")
	var material := (b.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(material.get_shader_parameter(&"flash_color"), Color.WHITE, "the target flashes white")
	assert_near(material.get_shader_parameter(&"flash_amount"), 1.0, 1e-6, "all the way, and holds through the hit-stop")
	assert_near(camera.trauma, 0.4, 0.05, "and the camera shakes by the profile's 0.4 (less the frame of decay since)")
	var other := a.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert_near((other.material_override as ShaderMaterial).get_shader_parameter(&"flash_amount"), 0.0, 1e-6, "the attacker does not")


func test_a_blow_that_whiffs_shows_and_sounds_nothing_of_a_hit() -> void:
	var stage := track(STAGE_SCENE.instantiate()) as PixelStage
	var camera := CameraRig.new()
	camera.stage = stage
	stage.world.add_child(camera)
	var roll := [{"frames": 4}, {"frames": 1, "press": [&"dodge"], "move": Vector2(0, -1)}, {"frames": 40}]
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 40}], roll, 2.0)
	var a: Actor = run["a"]
	var outcomes := []
	a.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(r.outcome))
	var impacts := 0
	var sounds := await _sounds(a, 30)
	for f in sounds:
		impacts += (sounds[f] as Array).count(&"impact_palm")
	assert_true(outcomes.has(HitResult.Outcome.WHIFF), "the hand did pass through the rolling body")
	assert_eq(impacts, 0, "but no impact sounded")
	assert_eq(_live(&"hit_spark").size(), 0, "no spark")
	assert_eq(camera.trauma, 0.0, "no shake")


func test_tells_show_glint_or_rose() -> void:
	var stage := track(STAGE_SCENE.instantiate()) as PixelStage
	var camera := CameraRig.new()
	camera.stage = stage
	stage.world.add_child(camera)
	var run := Duel.make(self, [{"frames": 60}], [], 6.0)
	var a: Actor = run["a"]
	var move := _fixture_move(a, [_mark(2, &"tell", {"kind": &"glint"}), _mark(8, &"tell", {"kind": &"perilous"}), _mark(20, &"recovery")])
	var material := (a.rig.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override as ShaderMaterial
	a.runner.start(move)
	var sounds := await _sounds(a, 2)
	assert_eq(sounds[2], [&"tell_glint"] as Array, "the glint's sound on its frame")
	assert_eq(_live(&"glint").size(), 1, "and the glint")
	assert_eq(_live(&"perilous_rose").size(), 0, "not the rose")
	assert_near(material.get_shader_parameter(&"flash_amount"), 0.0, 1e-6, "no flash for a glint")
	sounds = await _sounds(a, 8)
	assert_eq(sounds[8], [&"perilous_sting"] as Array, "the perilous tell's sting")
	assert_eq(_live(&"perilous_rose").size(), 1, "its rose")
	assert_eq(material.get_shader_parameter(&"flash_color"), ROSE, "and the body flashes rose")
	assert_near(material.get_shader_parameter(&"flash_amount"), 1.0, 0.1, "for a quarter of a second")
	await frames(20)
	assert_true(material.get_shader_parameter(&"flash_amount") < 0.4, "fading")
	await frames(10)
	assert_near(material.get_shader_parameter(&"flash_amount"), 0.0, 1e-6, "gone by 0.25 s")


func test_a_shake_mark_shakes_the_camera_by_its_strength() -> void:
	var stage := track(STAGE_SCENE.instantiate()) as PixelStage
	var camera := CameraRig.new()
	camera.stage = stage
	stage.world.add_child(camera)
	var run := Duel.make(self, [{"frames": 60}], [], 6.0)
	var a: Actor = run["a"]
	a.runner.start(_fixture_move(a, [_mark(3, &"shake", {"strength": 0.5}), _mark(20, &"recovery")]))
	await Duel.play_to(self, a, 2)
	assert_eq(camera.trauma, 0.0)
	await Duel.play_to(self, a, 3)
	assert_near(camera.trauma, 0.5, 0.05, "a half-strength shake (less what one frame of decay took)")


func test_a_name_no_data_has_warns_and_shows_nothing() -> void:
	var run := Duel.make(self, [{"frames": 60}], [], 6.0)
	var a: Actor = run["a"]
	var move := _fixture_move(a, [_mark(2, &"fx", {"name": &"no_such_fx"}), _mark(2, &"sfx", {"name": &"no_such_cue"}), _mark(20, &"recovery")])
	a.runner.start(move)
	# Each is a warning, which is an engine print a green run has none of (quietly cannot await a frame, so the
	# printing is switched off by hand here).
	var printing := Engine.print_error_messages
	Engine.print_error_messages = false
	await Duel.play_to(self, a, 2)
	Engine.print_error_messages = printing
	assert_eq(get_tree().get_nodes_in_group(ActorFx.GROUP).size(), 0, "no effect")
	assert_eq(Sfx.last_unknown(), [&"no_such_cue"] as Array, "the sound is recorded as one no cue has")
	var shown: Variant = quietly(func() -> Variant: return (a.get_node("ActorFx") as ActorFx).show_fx(&"no_such_fx"))
	assert_eq(shown, null, "and asking for the effect gives nothing back")
