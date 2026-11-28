class_name TestAbaraxFeather
extends TestCase
## The feather of Abarax's left ear (fix round 2): it passes through nothing (its blade's edges against the skinned triangles
## of the scarf, the shirt, the sleeves, the neck and the head, on every frame of a long list of poses), it does not snap when
## he is placed or revived, it does not whip in a fight, and a frozen actor holds it exactly still.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const YARD := "res://world/training_yard/training_yard.tscn"
## What the feather's edges are tested against.
const SOLIDS: Array[String] = ["Abarax_Scarf", "Male_Peasant_Body", "Male_Peasant_Arms", "Abarax_Head"]
## The feather's mesh vertices farther than this from its tie (at rest, model space) are its blade: the link, ring, beads and
## cord within it hang at the ear and the jaw by design and are not tested.
const BLADE_FROM := 0.05
const LOBE := Vector3(0.090, 1.712, -0.028)  # where the feather is tied (the builder's FEATHER_TIE), in model space
## The poses: clips played through at their own pace on a rig standing in place (the scarf's test does the same).
const CLIPS: Array[StringName] = [&"idle", &"palm_jab", &"palm_cross", &"palm_hook", &"palm_heavy", &"dash_step", &"guard_hold", &"flinch", &"hop",
		&"death", &"getup", &"sway_left_slip", &"sway_back_slip", &"duck_slip"]
## Eight directions of running, 40 frames each.
const RUNS: Array[Vector2] = [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1)]


# --- skinning by hand ---

# The meshes called `names` of `r`, ready to be skinned: {mi, verts, bones, weights, indices, binds}.
static func _prepare(r: Rig, names: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for node in r.skeleton.get_children():
		var mi := node as MeshInstance3D
		if mi == null or not names.has(String(mi.name)):
			continue
		var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var binds: Array[StringName] = []
		for i in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(i)
			if bone < 0:
				bone = r.skeleton.find_bone(mi.skin.get_bind_name(i))
			binds.append(StringName(r.skeleton.get_bone_name(bone)))
		found.append({"name": String(mi.name), "skin": mi.skin, "verts": arrays[Mesh.ARRAY_VERTEX], "bones": arrays[Mesh.ARRAY_BONES],
				"weights": arrays[Mesh.ARRAY_WEIGHTS], "indices": arrays[Mesh.ARRAY_INDEX], "binds": binds})
	return found


# The skinned vertices of a prepared mesh as the last tick shows them.
static func _skin(r: Rig, mesh: Dictionary) -> PackedVector3Array:
	var skin: Skin = mesh["skin"]
	var poses: Array[Transform3D] = []
	for i in skin.get_bind_count():
		poses.append(r.shown_pose(mesh["binds"][i]) * skin.get_bind_pose(i))
	var verts: PackedVector3Array = mesh["verts"]
	var bones: PackedInt32Array = mesh["bones"]
	var weights: PackedFloat32Array = mesh["weights"]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for v in verts.size():
		var at := Vector3.ZERO
		for k in 4:
			var w := weights[v * 4 + k]
			if w > 0.0:
				at += w * (poses[bones[v * 4 + k]] * verts[v])
		out[v] = at
	return out


# How many of the feather blade's edges pass through a triangle of each solid, now: {solid name: count}.
static func crossings(r: Rig, feather: Dictionary, blade: PackedInt32Array, solids: Array[Dictionary]) -> Dictionary:
	var fv := _skin(r, feather)
	var low := Vector3.INF
	var high := -Vector3.INF
	for i in blade:
		low = low.min(fv[i])
		high = high.max(fv[i])
	var box := AABB(low, high - low).grow(0.01)
	var found := {}
	var indices: PackedInt32Array = feather["indices"]
	var edges: Array = []
	for t in indices.size() / 3:
		var a := indices[t * 3]
		var b := indices[t * 3 + 1]
		var c := indices[t * 3 + 2]
		if blade.has(a) and blade.has(b) and blade.has(c):
			edges.append([fv[a], fv[b]])
			edges.append([fv[b], fv[c]])
			edges.append([fv[c], fv[a]])
	for solid in solids:
		var sv := _skin(r, solid)
		var si: PackedInt32Array = solid["indices"]
		var near: Array = []
		for t in si.size() / 3:
			var p0 := sv[si[t * 3]]
			var p1 := sv[si[t * 3 + 1]]
			var p2 := sv[si[t * 3 + 2]]
			if box.intersects(AABB(p0.min(p1).min(p2), p0.max(p1).max(p2) - p0.min(p1).min(p2))):
				near.append([p0, p1, p2])
		var count := 0
		for e in edges:
			for tri in near:
				if Geometry3D.segment_intersects_triangle(e[0], e[1], tri[0], tri[1], tri[2]) != null:
					count += 1
					break
		if count > 0:
			found[solid["name"]] = count
	return found


# The vertices of the feather's blade (indices into its mesh): those that are farther than BLADE_FROM from the lobe at rest.
static func blade_vertices(feather: Dictionary) -> PackedInt32Array:
	var blade := PackedInt32Array()
	var verts: PackedVector3Array = feather["verts"]
	for v in verts.size():
		if verts[v].distance_to(LOBE) > BLADE_FROM:
			blade.append(v)
	return blade


# --- the feather goes through nothing ---

func test_the_feather_passes_through_nothing_in_any_pose() -> void:
	var table := {}
	var frames_looked := 0
	var cases: Array = []
	for warm in [40, 83]:  # each twice, after 40 and after 83 ticks of standing (the spring is in another state)
		for clip in CLIPS:
			cases.append([clip, warm])
	for entry in cases:
		var clip: StringName = entry[0]
		var warm: int = entry[1]
		var r: Rig = track(load(RIG).instantiate())
		if not _has_feather(r):
			return
		var feather := _prepare(r, ["Abarax_Feather"])[0]
		var blade := blade_vertices(feather)
		assert_true(blade.size() > 20, "the blade's vertices were found (%d)" % blade.size())
		var solids := _prepare(r, SOLIDS)
		for i in warm:
			await frames(1)
			r.tick(1.0 / 60)
		var steps := 1
		if clip == &"getup":
			# He gets up from lying (the scarf's test says the same: played from idle the pose snaps and the scarf whips into it).
			# The get-up clip played from standing crosses once (the scarf, on the frame the body snaps to the floor); the game never
			# plays it so, and from lying it is clean: so lie him down first, as a death does, and let him lie a while.
			r.play_move(&"death", 0.15)
			for f in int(r.tree.get_animation(&"death").length * 60) + 20:
				await frames(1)
				r.set_move_time(minf(f / 60.0, r.tree.get_animation(&"death").length))
				r.tick(1.0 / 60)
		if clip != &"idle":
			r.play_move(clip, 0.15)
			steps = int(r.tree.get_animation(clip).length * 60) + 1
		var through := {}
		var bad := 0
		var bad_frames := PackedInt32Array()
		for f in steps:
			await frames(1)
			if clip != &"idle":
				r.set_move_time(f / 60.0)
			r.tick(1.0 / 60)
			frames_looked += 1
			var now := crossings(r, feather, blade, solids)
			if not now.is_empty():
				bad += 1
				bad_frames.append(f)
				for key in now:
					through[key] = maxi(through.get(key, 0), now[key])
		table["%s after %d" % [clip, warm]] = "%d of %d frames %s" % [bad, steps, through]
		assert_eq(bad, 0, "%s after %d ticks: the feather's edges went through %s on %d of %d frames (%s)" % [clip, warm, through, bad, steps, bad_frames])
		r.free()
	print("feather crossings by pose: ", table)
	assert_true(frames_looked > 300, "the poses were played (%d frames)" % frames_looked)


func test_the_feather_passes_through_nothing_running_in_eight_directions() -> void:
	var arena := TestArena.make(self)
	var steps: Array = []
	for dir in RUNS:
		steps.append({"frames": 40, "move": dir.normalized()})
	steps.append({"frames": 30})
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, ScriptBrain.new(steps))
	await frames(10)
	if not _has_feather(actor.rig):
		return
	var feather := _prepare(actor.rig, ["Abarax_Feather"])[0]
	var blade := blade_vertices(feather)
	var solids := _prepare(actor.rig, SOLIDS)
	var bad := 0
	var through := {}
	for f in RUNS.size() * 40 + 30:
		await frames(1)
		var now := crossings(actor.rig, feather, blade, solids)
		if not now.is_empty():
			bad += 1
			for key in now:
				through[key] = maxi(through.get(key, 0), now[key])
	assert_eq(bad, 0, "running: the feather's edges went through %s on %d frames" % [through, bad])


# The feather's edges against the skinned triangles on every frame of a seeded fight: {frames, bad, through, moves, first} (the moves the
# frames that crossed were in, what they went through at most, and the first such frame).
func _crossings_in_fight(seed_number: int, wave: int, count: int) -> Dictionary:
	var found := {"frames": 0, "bad": 0, "through": {}, "moves": {}, "first": -1}
	var parts := {}
	await FightBot.play(self, seed_number, [wave], count, true, func(player: Actor, f: int) -> void:
		if parts.is_empty():
			parts["feather"] = _prepare(player.rig, ["Abarax_Feather"])[0]
			parts["blade"] = blade_vertices(parts["feather"])
			parts["solids"] = _prepare(player.rig, SOLIDS)
		found["frames"] += 1
		var now := crossings(player.rig, parts["feather"], parts["blade"], parts["solids"])
		if now.is_empty():
			return
		found["bad"] += 1
		found["first"] = f if found["first"] < 0 else found["first"]
		var move := String(player.runner.current.id) if player.runner.current != null else "-"
		found["moves"][move] = found["moves"].get(move, 0) + 1
		for key in now:
			found["through"][key] = maxi(found["through"].get(key, 0), now[key]))
	return found


# Two seeded fights of 1,500 frames against real foes (a reactive brain: walks, palms, sways, ducks, dash-steps, guards; the player cannot
# die). Both crossed on the model of fix round 2: the first through the left sleeve in `palm_cross` (a fist past the ear, 44 of 160 frames
# of the last 160), the second through the scarf in a `stagger`.
func test_the_feather_passes_through_nothing_in_a_seeded_fight_with_palm_cross() -> void:
	var found := await _crossings_in_fight(12, 10, 1500)
	print("feather in seeded fight 12 (wave 10): ", found)
	assert_true(found["frames"] == 1500, "the fight ran (%d frames)" % found["frames"])
	assert_eq(found["bad"], 0, "the feather's edges went through %s on %d of 1500 frames (the first %d, in %s)" % [found["through"], found["bad"], found["first"], found["moves"]])


func test_the_feather_passes_through_nothing_in_a_seeded_fight_with_staggers() -> void:
	var found := await _crossings_in_fight(12, 11, 1500)
	print("feather in seeded fight 12 (wave 11): ", found)
	assert_true(found["frames"] == 1500, "the fight ran (%d frames)" % found["frames"])
	assert_eq(found["bad"], 0, "the feather's edges went through %s on %d of 1500 frames (the first %d, in %s)" % [found["through"], found["bad"], found["first"], found["moves"]])


# The attack clips, and those that move his body most: each is played below while he turns.
const ATTACKS: Array[StringName] = [&"palm_jab", &"palm_cross", &"palm_hook", &"palm_heavy", &"counter_hook", &"counter_rise", &"catch", &"parry",
		&"finisher", &"dash_step", &"dash_step_left", &"dash_step_right", &"dash_step_back", &"hop"]
## The rate a fight turns him (LocomotionTuning.turn_rate_deg), in degrees a frame; he turns one way for TURN_RUN frames, then the other, as
## he does from one foe to the next.
const TURN_PER_FRAME := 12.0
const TURN_RUN := 18


func test_the_feather_passes_through_nothing_in_any_attack_while_he_turns() -> void:
	var table := {}
	for clip in ATTACKS:
		var r: Rig = track(load(RIG).instantiate())
		if not _has_feather(r):
			return
		var feather := _prepare(r, ["Abarax_Feather"])[0]
		var blade := blade_vertices(feather)
		var solids := _prepare(r, SOLIDS)
		for i in 60:
			await frames(1)
			r.tick(1.0 / 60)
		r.play_move(clip, 0.15)
		var steps := int(r.tree.get_animation(clip).length * 60) + 1
		var bad := 0
		var through := {}
		var first := -1
		for f in steps:
			await frames(1)
			r.set_move_time(f / 60.0)
			r.rotation.y += deg_to_rad(TURN_PER_FRAME) * (1.0 if (f / TURN_RUN) % 2 == 0 else -1.0)
			r.tick(1.0 / 60)
			var now := crossings(r, feather, blade, solids)
			if not now.is_empty():
				bad += 1
				first = f if first < 0 else first
				for key in now:
					through[key] = maxi(through.get(key, 0), now[key])
		table[clip] = "%d of %d frames %s" % [bad, steps, through]
		assert_eq(bad, 0, "%s while turning: the feather's edges went through %s on %d of %d frames (the first, %d)" % [clip, through, bad, steps, first])
		r.free()
	print("feather crossings in attacks while turning: ", table)


# --- nothing snaps when he is put somewhere: tests/actors/test_spring_reset.gd ---

# A bone's direction (its +Y) in the frame of `parent`.
static func _direction(r: Rig, bone: StringName, parent: StringName) -> Vector3:
	return (r.shown_pose(parent).basis.inverse() * r.shown_pose(bone).basis.y).normalized()


# --- a frozen actor holds it still ---

func test_a_frozen_actor_holds_the_feather_exactly_still() -> void:
	var arena := TestArena.make(self)
	var brain := ScriptBrain.new([{"frames": 40}, {"frames": 1, "move": Vector2(0, 1), "press": [&"dodge"]}, {"frames": 200}])
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, brain)
	await frames(50)
	if not _has_feather(actor.rig):
		return
	actor.freeze(30)
	await frames(1)
	var held := TestAbaraxPortrait._tip(actor.rig)
	var worst := 0.0
	for i in 20:
		await frames(1)
		worst = maxf(worst, TestAbaraxPortrait._tip(actor.rig).distance_to(held))
	assert_eq(worst, 0.0, "twenty frames into a hit-stop the feather has moved %.6f m" % worst)
	await frames(30)
	assert_true(TestAbaraxPortrait._tip(actor.rig).distance_to(held) > 0.001, "and swings on once the freeze is over")


# --- it does not whip ---

func _has_feather(r: Rig) -> bool:
	var has := r.skeleton.find_bone("feather_01") >= 0 and r.skeleton.find_bone("feather_02") >= 0 and r.skeleton.find_bone("feather_03") >= 0
	assert_true(has, "the rig has the feather's bones")
	return has


# A fight in the yard: Abarax driven by a script of walks, chains of palms (jab, cross, hook), sways, ducks, dash-steps and
# a guard, three Knuckles on seeded dice. Returns {worst, over20, frames}: the most any feather bone turned in a frame
# in the head's frame, and in how many frames one turned more than 20 degrees.
func _fight(script: Array) -> Dictionary:
	Arena.reset_spawn_counts()
	var arena := track((load(YARD) as PackedScene).instantiate()) as Arena
	arena.automatic = false
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.name = "Player"
	player.def = load(ABARAX) as ActorDef
	player.set_brain(ScriptBrain.new(script))
	arena.add_child(player)
	arena.begin(player)
	var before := {}
	var worst := 0.0
	var over := 0
	var total := 0
	for i in 20:
		await frames(1)
	for f in 1500:
		await frames(1)
		var moved := false
		for bone in [&"feather_01", &"feather_02", &"feather_03"]:
			var now := _direction(player.rig, bone, &"Head")
			if before.has(bone):
				var turn := rad_to_deg(now.angle_to(before[bone]))
				worst = maxf(worst, turn)
				moved = moved or turn > 20.0
			before[bone] = now
		over += 1 if moved else 0
		total += 1
	Game.reset()
	return {"worst": worst, "over20": over, "frames": total}


func test_the_feather_does_not_whip_in_a_fight() -> void:
	var chain: Array = []
	for i in 6:
		chain.append({"frames": 1, "press": [&"palm"]})
		chain.append({"frames": 22})
	var script_a: Array = [{"frames": 30, "move": Vector2(0, 1)}] + chain + [
		{"frames": 1, "move": Vector2(1, 0), "press": [&"dodge"]}, {"frames": 40}] + chain + [
		{"frames": 1, "press": [&"sway"], "evade_dir": Vector2(1, 0)}, {"frames": 40},
		{"frames": 1, "press": [&"duck"], "evade_dir": Vector2(0, 1)}, {"frames": 40}] + chain + [
		{"frames": 60, "hold": [&"guard"]}, {"frames": 60, "move": Vector2(-1, -1)}] + chain + chain
	var script_b: Array = [{"frames": 20, "move": Vector2(-1, 1)}] + chain + chain + [{"frames": 90, "hold": [&"guard"]}] + chain
	for script in [script_a, script_b]:
		var found := await _fight(script)
		print("feather in a fight: ", found)
		assert_true(found["worst"] <= 45.0, "a feather bone turned %.0f degrees in one frame (at most 45)" % found["worst"])
		assert_true(found["over20"] <= found["frames"] * 0.03, "%d of %d frames had a feather bone turn more than 20 degrees (at most 3 per cent)" % [found["over20"], found["frames"]])
