class_name TestAbaraxPortrait
extends TestCase
## Abarax's model follows the owner's drawing (Portraits Task 3): a top-knot, a forelock, a feather on spring
## bones from his left ear and a ring in his right. What the game measures does not move because of it: a seeded
## fight plays out to the same hashes it had with the plain model, and every part is only a look.

const YARD := "res://world/training_yard/training_yard.tscn"
const ABARAX := "res://data/actors/abarax.tres"
## The checkpoints (every 100 physics frames of the seeded fight below) as they were with the model before the
## portrait work. The hash is this file's own (positions to the millimetre, HP, posture, stamina, the move), not
## Arena.state_hash, which holds the engine's frame counter and so depends on the tests that ran before.
const FIGHT_HASHES: Array[int] = [2130462679, 3661614394, 578355242, 584745297, 3329243264, 3247021830]


func before_each() -> void:
	Arena.reset_spawn_counts()


func after_each() -> void:
	Game.reset()


# The yard with Abarax in it, driven by a script of walks, jabs, a dash-step and a guard, and its first wave of Knuckles
# thinking with the brains' seeded dice.
func _fight_hashes() -> Array[int]:
	var arena := track((load(YARD) as PackedScene).instantiate()) as Arena
	arena.automatic = false
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.name = "Player"
	player.def = load(ABARAX) as ActorDef
	player.set_brain(ScriptBrain.new([
		{"frames": 40, "move": Vector2(0, 1)}, {"frames": 1, "press": [&"palm"]}, {"frames": 50},
		{"frames": 1, "press": [&"palm"]}, {"frames": 50}, {"frames": 1, "move": Vector2(1, 0), "press": [&"dodge"]},
		{"frames": 60}, {"frames": 60, "move": Vector2(-1, 1)}, {"frames": 1, "press": [&"palm"]}, {"frames": 60},
		{"frames": 60, "hold": [&"guard"]}, {"frames": 120, "move": Vector2(0, -1)}, {"frames": 1, "press": [&"palm"]},
		{"frames": 200}]))
	arena.add_child(player)
	arena.begin(player)
	var hashes: Array[int] = []
	for checkpoint in 6:
		await frames(100)
		var parts: Array = []
		for node in arena.get_tree().get_nodes_in_group(Actor.GROUP):
			var actor := node as Actor
			if actor == null or actor.stats == null:
				continue
			var at := actor.global_position
			parts.append_array([roundi(at.x * 1000.0), roundi(at.y * 1000.0), roundi(at.z * 1000.0),
					roundi(actor.stats.hp * 10.0), roundi(actor.stats.posture * 10.0), roundi(actor.stats.stamina * 10.0),
					String(actor.runner.current.id) if actor.runner.current != null else ""])
		hashes.append(parts.hash())
	return hashes


const RIG := "res://actors/abarax/abarax_rig.tscn"
const PARTS: PackedStringArray = ["Abarax_Topknot", "Abarax_Forelock", "Abarax_Feather", "Abarax_EarRing", "Abarax_Stubble"]
const FEATHER_BONE_LENGTH := 0.15
## The drawing's feather, 1.8 cm of it from the neck's collar would be inside the shirt: the least distance any of the
## feather's points (the ring, the beads, the root of the feather, the middle of it and its tip) may come to a vertex of the
## body (the shirt and sleeves, and the head's own neck) in the five poses below. The meshes' vertices lie 1-2 cm apart
## (they are decimated), so a point 1.5 cm or more from every one of them is out of the surface.
const CLEAR_OF_BODY := 0.015
## The poses the clearance is kept in: idle, a jab, a dash-step, the guard and a flinch. Each is played through at its own pace.
const POSES: Array[StringName] = [&"idle", &"palm_jab", &"dash_step", &"guard_hold", &"flinch"]


func _def() -> ActorDef:
	return load(ABARAX) as ActorDef


# The feather's tip: the end of feather_02 (the bone's origin plus its length along its +Y), in the world.
static func _tip(r: Rig) -> Vector3:
	var end := r.shown_pose(&"feather_02")
	return end.origin + end.basis.y.normalized() * FEATHER_BONE_LENGTH


# The tip in the head's own frame, so that what the head does is not counted as the feather's swing.
static func _tip_in_head(r: Rig) -> Vector3:
	return r.shown_pose(&"Head").affine_inverse() * _tip(r)


# The points of the feather that must stay out of the body.
static func _feather_points(r: Rig) -> Array[Vector3]:
	var first := r.shown_pose(&"feather_01")
	var second := r.shown_pose(&"feather_02")
	return [first.origin + first.basis.y.normalized() * 0.026, first.origin + first.basis.y.normalized() * 0.05,
			second.origin, second.origin + second.basis.y.normalized() * FEATHER_BONE_LENGTH * 0.5, _tip(r)]


# The body's vertices as the last tick shows them: the shirt, the sleeves and the neck of the head's mesh (its vertices
# that stand below the ear), skinned by hand from the bones' shown poses. Returns an Array of PackedVector3Array.
static func _body_vertices(r: Rig) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for node in r.skeleton.get_children():
		var mi := node as MeshInstance3D
		if mi == null or not ["Male_Peasant_Body", "Male_Peasant_Arms", "Abarax_Head"].has(String(mi.name)):
			continue
		var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var skin := mi.skin
		var poses: Array[Transform3D] = []
		for i in skin.get_bind_count():
			var bone := skin.get_bind_bone(i)
			if bone < 0:
				bone = r.skeleton.find_bone(skin.get_bind_name(i))
			poses.append(r.shown_pose(StringName(r.skeleton.get_bone_name(bone))) * skin.get_bind_pose(i))
		for v in verts.size():
			var at := Vector3.ZERO
			for k in 4:
				var w := weights[v * 4 + k]
				if w > 0.0:
					at += w * (poses[bones[v * 4 + k]] * verts[v])
			if mi.name == &"Abarax_Head" and verts[v].y > 1.62:
				continue
			found.append(at)
	return found


# The least distance of a feather point from the body's vertices.
static func _clearance(r: Rig, body: Array[Vector3]) -> float:
	var least := INF
	for p in _feather_points(r):
		for v in body:
			least = minf(least, p.distance_to(v))
	return least


# True if the rig has the feather's bones; a test that reads them says so first and goes no further without them.
func _has_feather(r: Rig) -> bool:
	var has := r.skeleton.find_bone("feather_01") >= 0 and r.skeleton.find_bone("feather_02") >= 0
	assert_true(has, "the rig has the feather's bones")
	return has


func test_a_seeded_fight_plays_out_as_it_did() -> void:
	var hashes := await _fight_hashes()
	assert_eq(hashes, FIGHT_HASHES, "the fight's six checkpoints")


func test_the_parts_are_on_abarax_and_shown() -> void:
	var r: Rig = track(load(RIG).instantiate())
	var found := {}
	for mesh in r.skeleton.find_children("*", "MeshInstance3D", false, false):
		found[String(mesh.name)] = (mesh as MeshInstance3D).visible
	for part in PARTS:
		assert_true(found.has(part), "the model has %s" % part)
		assert_true(found.get(part, false), "and shows it")
	assert_eq(_def().hidden_parts.size(), 0, "Abarax hides nothing")


func test_no_other_actor_wears_them() -> void:
	# The Knuckles have a model of their own; if any def's model had one of the parts, it would have to hide it.
	var dir := DirAccess.open("res://data/actors")
	var checked := 0
	for file in dir.get_files():
		if not file.ends_with(".tres") or file == "abarax.tres":
			continue
		var def := load("res://data/actors/%s" % file) as ActorDef
		var r := def.rig_scene.instantiate() as Rig
		for mesh in r.find_children("*", "MeshInstance3D", true, false):
			if PARTS.has(String(mesh.name)):
				assert_true(def.hidden_parts.has(String(mesh.name)), "%s hides %s" % [file, mesh.name])
		r.free()
		checked += 1
	assert_true(checked >= 6, "the Knuckles' defs were looked at (%d)" % checked)


func test_the_feather_hangs_from_his_left_ear() -> void:
	var r: Rig = track(load(RIG).instantiate())
	var skeleton := r.skeleton
	assert_true(skeleton.find_bone("feather_01") >= 0 and skeleton.find_bone("feather_02") >= 0, "the feather's two bones are in the skeleton")
	if skeleton.find_bone("feather_01") < 0:
		return
	assert_eq(skeleton.get_bone_name(skeleton.get_bone_parent(skeleton.find_bone("feather_01"))), "Head")
	assert_eq(skeleton.get_bone_name(skeleton.get_bone_parent(skeleton.find_bone("feather_02"))), "feather_01")
	var lobe := skeleton.get_bone_global_rest(skeleton.find_bone("feather_01")).origin  # at rest, in the model's own space
	assert_true(lobe.x > 0.07 and lobe.x < 0.11, "on his left (+X): %s" % lobe)
	assert_true(lobe.y > 1.63 and lobe.y < 1.70, "at the lobe's height: %s" % lobe)
	assert_true(lobe.z > -0.03 and lobe.z < 0.05, "level with the ear, not the face: %s" % lobe)


func test_the_rig_springs_the_feather_and_only_the_feather_and_the_scarf() -> void:
	var r: Rig = track(load(RIG).instantiate())
	var springs := r.skeleton.find_children("*", "SpringBoneSimulator3D", false, false)
	assert_eq(springs.size(), 2, "the scarf's spring and the feather's")
	var feather: SpringBoneSimulator3D = null
	for spring: SpringBoneSimulator3D in springs:
		if spring.get_root_bone_name(0) == "feather_01":
			feather = spring
	assert_true(feather != null, "a spring on feather_01")
	if feather == null:
		return
	assert_eq(feather.get_end_bone_name(0), "feather_02")
	assert_true(feather.is_end_bone_extended(0), "its end extended by the feather's length")
	assert_near(feather.get_end_bone_length(0), FEATHER_BONE_LENGTH, 1e-6)
	var plain: Rig = track(load(RIG).instantiate())
	for spring in plain.skeleton.find_children("*", "SpringBoneSimulator3D", false, false):
		if (spring as SpringBoneSimulator3D).get_root_bone_name(0) == "feather_01":
			(spring as SkeletonModifier3D).active = false
	for rr: Rig in [r, plain]:
		rr.set_locomotion(5.546, false)
	var worst := 0.0
	for i in 60:
		r.tick(1.0 / 60)
		plain.tick(1.0 / 60)
		for bone in r.skeleton.get_bone_count():
			var bone_name := StringName(r.skeleton.get_bone_name(bone))
			if not String(bone_name).begins_with("feather_"):
				worst = maxf(worst, (r.bone_global(bone_name) - plain.bone_global(bone_name)).length())
	assert_true(worst < 1e-4, "every other bone is where it would be without the feather's spring (%.5f m)" % worst)


func test_the_feather_swings_in_a_dash_step_and_comes_to_rest() -> void:
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 60}, {"frames": 1, "move": Vector2(0, 1), "press": [&"dodge"]}, {"frames": 200}])
	var actor := TestArena.spawn(arena, _def(), brain)
	await frames(60)
	if not _has_feather(actor.rig):
		return
	var rest := _tip_in_head(actor.rig)
	var far := 0.0
	var stepped := false
	for i in 40:
		await frames(1)
		stepped = stepped or actor.runner.busy()
		far = maxf(far, _tip_in_head(actor.rig).distance_to(rest))
	assert_true(stepped, "he dash-stepped")
	assert_true(far > 0.02, "the tip swung %.1f cm from where it hangs at rest in the head's frame (more than 2 cm)" % (far * 100.0))
	await frames(60)
	assert_true(not actor.runner.busy(), "the step is over")
	var before := _tip_in_head(actor.rig)
	var worst := 0.0
	for i in 20:
		await frames(1)
		var now := _tip_in_head(actor.rig)
		worst = maxf(worst, now.distance_to(before))
		before = now
	assert_true(worst < 0.002, "within 60 frames of standing still the tip moves under 2 mm a frame (%.2f mm)" % (worst * 1000.0))


func test_a_paused_game_holds_the_feather_still() -> void:
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 40}, {"frames": 1, "move": Vector2(0, 1), "press": [&"dodge"]}, {"frames": 200}])
	var actor := TestArena.spawn(arena, _def(), brain)
	await frames(50)
	if not _has_feather(actor.rig):
		return
	get_tree().paused = true
	var held := _tip(actor.rig)
	await frames(10)
	var still := _tip(actor.rig)
	get_tree().paused = false
	assert_vec_near(still, held, 1e-6, "ten frames paused in the middle of the swing, the feather has not moved")
	await frames(10)
	assert_true(_tip(actor.rig).distance_to(held) > 0.001, "and moves again when the game goes on")


func test_the_feather_stays_off_the_shoulder_and_neck_in_five_poses() -> void:
	var worst := {}
	for clip in POSES:
		var r: Rig = track(load(RIG).instantiate())
		if not _has_feather(r):
			return
		for i in 40:
			await frames(1)
			r.tick(1.0 / 60)
		var body := _body_vertices(r)
		assert_true(body.size() > 500, "the body's vertices were found (%d)" % body.size())
		var least := INF
		if clip != &"idle":
			r.play_move(clip, 0.15)
		for f in int(r.tree.get_animation(clip).length * 60) + 1:
			await frames(1)
			if clip != &"idle":
				r.set_move_time(f / 60.0)
			r.tick(1.0 / 60)
			least = minf(least, _clearance(r, _body_vertices(r)))
		worst[clip] = "%.3f" % least
		assert_true(least >= CLEAR_OF_BODY, "%s: a point of the feather came within %.3f m of the body" % [clip, least])
		r.free()
	assert_eq(worst.size(), POSES.size(), "every pose was played (%s)" % [worst])
