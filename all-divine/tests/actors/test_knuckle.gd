extends TestCase
## The Knuckle of the Hand: its rig (actors/knuckle/knuckle_rig.tscn, the model tools/anim/build_knuckle.py builds) plays
## Abarax's clip library, and its three tiers (data/actors/knuckle_{1,2,3}.tres) are drawn and numbered as the brief
## says: tier I without the hood and pauldron, tier II without the pauldron, tier III with both, 4% larger.

const RIG := "res://actors/knuckle/knuckle_rig.tscn"
const TIERS := ["res://data/actors/knuckle_1.tres", "res://data/actors/knuckle_2.tres", "res://data/actors/knuckle_3.tres"]
const PARTS: PackedStringArray = ["Knuckle_Head", "Knuckle_Hair", "Knuckle_Beard", "Knuckle_Body", "Knuckle_Legs",
		"Knuckle_Arms", "Knuckle_Boots", "Knuckle_Hood", "Knuckle_Pauldron"]
## What each tier hides, and how much larger it is.
const HIDDEN := [["Knuckle_Hood", "Knuckle_Pauldron"], ["Knuckle_Pauldron"], []]
const SCALES := [1.0, 1.0, 1.04]
## HP, poise and posture of each tier.
const NUMBERS := [[60.0, 5.0, 60.0], [90.0, 10.0, 80.0], [130.0, 20.0, 100.0]]
## The tiers' main colours: the hood of tier II and the metal of tier III (palette slots 7 and 8).
const HOOD_SLOT := 7
const METAL_SLOT := 8


func _rig(path: String) -> Rig:
	var rig := (load(path) as PackedScene).instantiate() as Rig
	track(rig)
	return rig


func _visible_parts(rig: Rig) -> PackedStringArray:
	var shown := PackedStringArray()
	for mesh in rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).visible:
			shown.append(String(mesh.name))
	shown.sort()
	return shown


func test_knuckle_plays_the_shared_library() -> void:
	# Every track of every clip of the library resolves on the knuckle's rig: each bone track on a bone of its skeleton
	# at the path the clips name, each mark track on its Marks. The rest pose is Abarax's, so a clip poses both alike.
	var knuckle := _rig(RIG)
	var abarax := _rig("res://actors/abarax/abarax_rig.tscn")
	var library := knuckle.tree.get_animation_library(&"")
	var clips := library.get_animation_list()
	assert_eq(knuckle.tree.get_animation(&"palm_jab"), abarax.tree.get_animation(&"palm_jab"), "the same clips: Abarax's library")
	assert_true(clips.size() >= 26, "the library (%d clips)" % clips.size())
	var unresolved := []
	for clip in clips:
		if clip == Rig.SNAPSHOT_CLIP:
			continue
		var anim := library.get_animation(clip)
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			var node := knuckle.get_node_or_null(NodePath(path.get_concatenated_names()))
			if node == null:
				unresolved.append("%s: %s" % [clip, path])
			elif node is Skeleton3D and (node as Skeleton3D).find_bone(String(path.get_concatenated_subnames())) < 0:
				unresolved.append("%s: %s (no such bone)" % [clip, path])
	assert_eq(unresolved, [], "every track resolves")
	assert_eq(knuckle.skeleton.get_bone_count(), 65, "65 bones: no scarf")
	for bone in knuckle.skeleton.get_bone_count():
		var name := knuckle.skeleton.get_bone_name(bone)
		var other := abarax.skeleton.find_bone(name)
		assert_true(other >= 0, "%s is one of Abarax's bones" % name)
		if other >= 0:
			assert_vec_near(knuckle.skeleton.get_bone_global_rest(bone).origin, abarax.skeleton.get_bone_global_rest(other).origin,
					1e-4, "%s rests where Abarax's does" % name)
	for rig in [knuckle, abarax]:
		rig.play_move(&"palm_jab", 0.0)
		rig.set_move_time(20.0 / 60.0)
		rig.tick(1.0 / 60.0)
	for bone in [&"hand_l", &"hand_r", &"Head", &"foot_l", &"pelvis"]:
		assert_vec_near(knuckle.bone_global(bone), abarax.bone_global(bone), 1e-3, "palm_jab f20 puts %s where it puts Abarax's" % bone)


func test_the_rig_has_the_knuckles_hitboxes_and_no_spring_bone() -> void:
	var rig := _rig(RIG)
	var ids := PackedStringArray()
	for child in rig.get_node(^"Hitboxes").get_children():
		ids.append(String(child.name))
	assert_eq(ids, PackedStringArray(["palm_l", "palm_r", "foot_r", "slam_ring"]))
	assert_eq((rig.get_node(^"Hitboxes/foot_r") as BoneAttachment3D).bone_name, "foot_r")
	assert_ne(rig.hurtbox, null, "a hurtbox")
	assert_ne(rig.warp, null, "the orientation warp")
	assert_ne(rig.breathing, null, "breathing")
	assert_ne(rig.hit_reaction, null, "hit reactions")
	assert_ne(rig.foot_planter, null, "the feet")
	assert_eq(rig.looks.size(), 2, "the neck's and the head's look")
	assert_eq(rig.skeleton.find_children("*", "SpringBoneSimulator3D", true, false), [], "no spring bone")


func test_tiers_hide_their_parts_and_scale() -> void:
	var arena := TestArena.make(self)
	var heads: Array[float] = []
	for i in TIERS.size():
		var def := load(TIERS[i]) as ActorDef
		var actor := TestArena.spawn(arena, def, ScriptBrain.new([]), Vector3(i * 2.0, 0, 0), "K%d" % (i + 1))
		var shown := PARTS.duplicate()
		for part: String in HIDDEN[i]:
			shown.remove_at(shown.find(part))
		shown.sort()
		assert_eq(_visible_parts(actor.rig), shown, "%s shows %s" % [def.id, shown])
		assert_eq(def.hidden_parts, PackedStringArray(HIDDEN[i]), "%s's hidden_parts" % def.id)
		assert_near(def.model_scale, SCALES[i], 1e-6, "%s's model_scale" % def.id)
		actor.rig.tick(1.0 / 60.0)
		# The clips' pose, without the breath (whose phase comes from the actor's name) or the feet over it.
		heads.append(actor.rig.animated_pose(&"Head").origin.y - actor.global_position.y)
		var hurtbox := actor.rig.hurtbox.get_node(^"shape") as CollisionShape3D
		assert_near(hurtbox.global_basis.get_scale().y, SCALES[i], 1e-4, "%s's hurtbox is scaled with it" % def.id)
	assert_near(heads[2] / heads[0], 1.04, 1e-3, "tier III's head stands 4%% higher (%.3f m against %.3f m)" % [heads[2], heads[0]])
	assert_near(heads[1], heads[0], 1e-4, "tier II's as tier I's")


func test_a_larger_tier_travels_further_by_root_motion() -> void:
	# Its clips' root travel grows with it, so its planted feet do not skate: knuckle_3 (1.04) goes 4% further on the
	# same root-motion move as knuckle_1.
	var arena := TestArena.make(self)
	var travel: Array[float] = []
	for i in [0, 2]:
		var actor := TestArena.spawn(arena, load(TIERS[i]) as ActorDef, ScriptBrain.new([]), Vector3(i * 3.0, 0, 0), "K%d" % (i + 1))
		await frames(1)
		var from := actor.global_position
		actor.runner.start(Registry.fetch(&"moves", &"dash_step") as MoveData, true)
		while actor.runner.busy():
			await frames(1)
		travel.append(Vector2(actor.global_position.x - from.x, actor.global_position.z - from.z).length())
	assert_true(travel[0] > 1.0, "the dash-step travels (%.3f m)" % travel[0])
	assert_near(travel[1] / travel[0], 1.04, 0.01, "%.3f m against %.3f m" % [travel[1], travel[0]])


func test_a_hidden_part_the_model_lacks_is_reported() -> void:
	var rig := _rig(RIG)
	var unknown: PackedStringArray = quietly(func() -> PackedStringArray: return rig.hide_parts(PackedStringArray(["Knuckle_Hood", "Knuckle_Cape"])))
	assert_eq(unknown, PackedStringArray(["Knuckle_Cape"]), "the unknown part is returned")
	assert_false((rig.get_node(^"Model").find_child("Knuckle_Hood", true, false) as MeshInstance3D).visible, "the known one is hidden")


func test_tiers_have_their_numbers() -> void:
	var abarax := load(Duel.ABARAX) as ActorDef
	var palettes: Array[Palette] = []
	for i in TIERS.size():
		var def := load(TIERS[i]) as ActorDef
		var id := "knuckle_%d" % (i + 1)
		assert_eq(String(def.id), id)
		assert_eq(def.team, ActorDef.Team.ENEMY, "%s is an enemy" % id)
		assert_eq([def.max_hp, def.poise, def.max_posture], NUMBERS[i], "%s's HP, poise and posture" % id)
		assert_eq(def.rig_scene.resource_path, RIG, "%s's rig" % id)
		assert_eq(def.reactions, abarax.reactions, "%s reacts with the shared reaction moves (death among them)" % id)
		assert_eq(def.combat.resource_path, "res://data/tuning/combat_knuckle.tres", "%s's tuning" % id)
		assert_eq(def.finisher, null, "%s finishes no one" % id)
		assert_ne(def.palette, null, "%s has a palette" % id)
		palettes.append(def.palette)
	assert_eq(palettes[1].tone(HOOD_SLOT, Palette.BASE).to_html(false), "9a2a2a", "tier II wears the Hand's red hood")
	assert_eq(palettes[2].tone(METAL_SLOT, Palette.BASE).to_html(false), "c8a04a", "tier III's metal is brass")
	# Tier III wears black: its coat's deepest tone is near black. Its lit tones, and tier II's, are lifted so that the coat
	# and the legs show on the yard's dark floor at night (tests/render/test_yard_shot.gd); in the light each tier's coat, legs
	# and boots are still darker than those of the tier below it, and every slot's tones still run from light to dark.
	assert_true(palettes[2].tone(3, Palette.DEEP).v < 0.1, "tier III's main is black in its shadows")
	for slot: int in [3, 5, 6]:
		var values: Array[float] = []
		for palette in palettes:
			values.append(palette.tone(slot, Palette.BASE).v)
		assert_true(values[2] < values[1] and values[1] < values[0], "%s: tier III's is darker than tier II's, and that than tier I's (%s)" % [palettes[0].slot_names[slot], values])
	for palette in palettes:
		for slot in Palette.SLOTS:
			if palette.slot_names[slot] != "":
				assert_true(palette.tone(slot, Palette.HIGHLIGHT).v >= palette.tone(slot, Palette.BASE).v and palette.tone(slot, Palette.BASE).v > palette.tone(slot, Palette.SHADE).v
						and palette.tone(slot, Palette.SHADE).v > palette.tone(slot, Palette.DEEP).v, "%s %s: highlight, base, shade and deep run from light to dark" % [palette.id, palette.slot_names[slot]])
	assert_ne(palettes[0], palettes[1])


# A flinch on `def`'s actor `victim` from a jab, while its brain presses dodge (with the stick pushed) on every frame
# from the flinch's f20, when its cancel window is open: [the ids of the moves it starts, whether the flinch was
# cancelled].
func _dodge_out_of_a_flinch(def: ActorDef) -> Array:
	var steps := [{"frames": 25}]
	for i in 30:
		steps.append({"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)})
	var arena := TestArena.make(self)
	var victim := TestArena.spawn(arena, def, ScriptBrain.new(steps), Vector3.ZERO, "Victim")
	await frames(1)
	var started := []
	var cancelled := [null]
	victim.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	victim.runner.move_ended.connect(func(m: MoveData, was_cancelled: bool) -> void:
		if m.id == &"flinch":
			cancelled[0] = was_cancelled)
	victim.runner.start(Registry.fetch(&"moves", &"flinch") as MoveData)
	await frames(50)
	return [started, cancelled[0]]


func test_a_shared_reaction_opens_its_window_only_into_the_actors_own_moves() -> void:
	# The reactions are Abarax's clips, and their cancel windows name his moves: the flinch's takes a dodge into his
	# dash-step. Abarax dash-steps out of it; a Knuckle, whose dodge is its feint, plays it out (it never dash-steps with
	# his dash-step, nor jabs with his jab after), and its dodge press starts its own feint only once the flinch is over.
	var abarax: Array = await _dodge_out_of_a_flinch(Duel.def(ActorDef.Team.PLAYER, 10.0))
	assert_eq((abarax[0] as Array).slice(0, 2), [&"flinch", &"dash_step_left"], "Abarax dash-steps out of the flinch: %s" % [abarax[0]])
	assert_eq(abarax[1], true, "cutting it short")
	var knuckle: Array = await _dodge_out_of_a_flinch(load(TIERS[0]) as ActorDef)
	assert_eq(knuckle[1], false, "the Knuckle plays the flinch out: %s" % [knuckle[0]])
	assert_false((knuckle[0] as Array).has(&"dash_step_left"), "and never dash-steps with Abarax's dash-step")


func test_abaraxs_reaction_windows_are_all_his_own_moves() -> void:
	# So the rule changes nothing for him: every window of every reaction he has opens into the move his moveset names
	# for that action.
	var abarax := load(Duel.ABARAX) as ActorDef
	var rig := _rig("res://actors/abarax/abarax_rig.tscn")
	var foreign := []
	for reaction: StringName in abarax.reactions:
		var move := Registry.fetch(&"moves", abarax.reactions[reaction]) as MoveData
		for m in Marks.read(rig.tree.get_animation(move.clip)):
			if m["kind"] != &"cancel_open":
				continue
			var into: Dictionary = m["args"].get("into", {})
			for action: StringName in into:
				if abarax.moveset.get(action) != into[action]:
					foreign.append([move.id, action, into[action]])
			assert_eq(MoveRunner.window_of(move, into, abarax), into, "%s's window is all open for Abarax" % move.id)
	assert_eq(foreign, [])


func test_a_broken_knuckle_1_is_finished() -> void:
	# A knuckle_1 (60 HP) whose posture breaks reels in the shared posture_broken and is open to Abarax's finisher: his
	# palm on frame 10 pairs them, the three blows (15, 15 and 30) kill it, and it dies once, where it lies, with no
	# death clip.
	var abarax := (load(Duel.ABARAX) as ActorDef)
	var run := Duel.make(self, [{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 200}], [], 1.0,
			load(TIERS[0]) as ActorDef, abarax)
	var a: Actor = run["a"]
	var k: Actor = run["b"]
	track(PostureBreaker.make(a, k))
	await Duel.play_to(self, k, 1)
	assert_true(k.stats.posture_broken, "the knuckle's posture is broken")
	assert_eq(k.runner.current.id if k.runner.current != null else &"", &"posture_broken", "it reels")
	assert_true(k.is_in_group(Actor.FINISHABLE_GROUP), "and is finishable")
	var died := [0]
	k.died.connect(func() -> void: died[0] += 1)
	await Duel.play_to(self, a, 10)
	assert_eq([a.paired_with, k.paired_with], [k, a], "the palm starts the finisher on it")
	assert_eq(a.runner.current.id, &"finisher")
	while a.paired_with != null or k.paired_with != null:
		await frames(1)
	assert_eq(died[0], 1, "the finisher kills it, once")
	assert_eq(k.stats.hp, 0.0)
	assert_ne(k.runner.current.id if k.runner.current != null else &"", &"death", "without the death clip")
	assert_true(k.rig.bone_global(&"Head").y - k.global_position.y < 0.4, "it lies where the finisher left it")


func test_a_part_named_twice_is_hidden_and_not_reported() -> void:
	var rig := _rig(RIG)
	var unknown: PackedStringArray = quietly(func() -> PackedStringArray: return rig.hide_parts(PackedStringArray(["Knuckle_Hood", "Knuckle_Hood"])))
	assert_eq(unknown, PackedStringArray(), "a name given twice is still one the model has")
	assert_false((rig.get_node(^"Model").find_child("Knuckle_Hood", true, false) as MeshInstance3D).visible, "and it is hidden")


func test_model_scale_is_held_to_a_sane_range() -> void:
	for property in ActorDef.new().get_property_list():
		if property["name"] == "model_scale":
			assert_eq(property["hint"], PROPERTY_HINT_RANGE, "model_scale is a range")
			assert_eq(String(property["hint_string"]).split(",").slice(0, 2), PackedStringArray(["0.5", "1.5"]), "from 0.5 to 1.5")
			return
	fail("ActorDef has no model_scale")
