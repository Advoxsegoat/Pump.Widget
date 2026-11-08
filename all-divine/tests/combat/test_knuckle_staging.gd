extends TestCase
## The Knuckle in paired moves, staged in the game's placement as test_finisher_staging.gd stages the finisher, with the
## bodies as Bodies' capsules (torso 0.13 m, head 0.10 m, limbs thinner):
##   finisher  Abarax's finisher still lands on every tier: on knuckle_1 and on knuckle_3 (4% larger), each pair_hit's
##             striking hand is at most REACH short of the victim's head or torso and at most SINK inside it, and the
##             two bodies pass at most SINK into each other on any frame (F1 Task 10's reach and contact criteria)
##   grab      a Knuckle's grab that takes hold starts its grab_pair (knuckle_grab: knuckle_grab_hold on the Knuckle,
##             grabbed on Abarax) with knuckle_1 and with knuckle_3 as the lead, and Task 10's staging criteria hold on it:
##             reach and contact as above, Abarax's planted feet (ankle PLANTED high or lower) slide SKATE at most from the
##             first blow on, neither clip pops (the lead's pelvis, head and feet LEAD_STEP a 12 fps step, Abarax's
##             VICTIM_FRAME a frame, the hands across joins), and walls behind and beside Abarax hold both; a grab that
##             cannot be staged (Abarax turned past the facing gate, or a wall between their chests) is a HIT that staggers
##
## Finisher fighters: `a` (PLAYER, Abarax's own def) at the origin facing +Z, `b` (a Knuckle tier) a metre in front facing
## back. b's posture is broken on frame 1 (PostureBreaker); a presses palm on frame 10. Grab fighters: the Knuckle at the
## origin facing +Z presses interact (its grab) on frame 1, and Abarax (his own def) stands GRAB_GAP in front, facing it.

const REACH := 0.08
const SINK := 0.05
const PALM_ON := 10
const TIERS := {"knuckle_1": "res://data/actors/knuckle_1.tres", "knuckle_3": "res://data/actors/knuckle_3.tres"}
const SKATE := 0.05
const PLANTED := 0.10
const LEAD_STEP := 0.25
const VICTIM_FRAME := 0.15
const GRAB_GAP := 1.0
const CAPSULE_RADIUS := 0.35
const PAIR := "res://data/pairs/knuckle_grab.tres"
const O := HitResult.Outcome


# A copy of the tier at `path` with HP enough to live through what it is dealt (so the pair plays the same to its end).
static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 1000.0
	return def


# Plays Abarax's finisher on the Knuckle of `def` from a's palm on PALM_ON until neither is paired, and records each frame
# of it: [{frame, overlap (Bodies.overlap of a's capsules and b's), hit (the striking hand's [gap, target] on a pair_hit
# frame, or null)}].
func _finisher_on(def: ActorDef) -> Array:
	var steps := [{"frames": PALM_ON - 1}, {"frames": 1, "press": [&"palm"]}, {"frames": 400}]
	var run := Duel.make(self, steps, [], 1.0, def, load(Duel.ABARAX) as ActorDef)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	track(PostureBreaker.make(a, b))
	var hit_now := [false]
	a.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
		if kind == &"pair_hit":
			hit_now[0] = true)
	await Duel.play_to(self, a, PALM_ON - 1)
	var rows := []
	while a.frame < PALM_ON + 300:
		await frames(1)
		if a.frame == PALM_ON:
			assert_eq(a.paired_with, b, "the palm starts the finisher on %s" % def.id)
		if a.paired_with == null and b.paired_with == null and a.frame > PALM_ON:
			break
		var a_caps := Bodies.of(a.rig)
		var b_caps := Bodies.of(b.rig)
		var hit: Variant = null
		if hit_now[0]:
			hit_now[0] = false
			var left := Bodies.strike_gap(a_caps, b_caps, "hand_l")
			var right := Bodies.strike_gap(a_caps, b_caps, "hand_r")
			hit = left if left[0] < right[0] else right
		rows.append({"frame": a.frame, "overlap": Bodies.overlap(a_caps, b_caps), "hit": hit})
	(run["arena"] as Node).free()
	return rows


func test_the_finisher_lands_on_every_tier() -> void:
	for tier: String in TIERS:
		var rows: Array = await _finisher_on(_tough(TIERS[tier]))
		var hits := rows.filter(func(r: Dictionary) -> bool: return r["hit"] != null)
		assert_eq(hits.size(), 3, "three blows on %s" % tier)
		for row: Dictionary in hits:
			var hit: Array = row["hit"]
			assert_true(hit[0] <= REACH, "%s: the blow on frame %d reaches %s: %.3f m short" % [tier, row["frame"], hit[1], hit[0]])
			assert_true(hit[0] >= -SINK, "%s: and is not %.3f m inside it (frame %d)" % [tier, -hit[0], row["frame"]])
		var worst := [-INF, "", "", -1]
		for row: Dictionary in rows:
			if row["overlap"][0] > worst[0]:
				worst = [row["overlap"][0], row["overlap"][1], row["overlap"][2], row["frame"]]
		assert_true(rows.size() > 60, "the pair played on %s (%d frames)" % [tier, rows.size()])
		assert_true(worst[0] <= SINK, "%s: at worst %.3f m of a's %s in b's %s, on frame %d" % [tier, worst[0], worst[1], worst[2], worst[3]])


# --- the grab ---

# The Knuckle of the tier at `tier_path` grabbing Abarax, who stands GRAB_GAP in front of it, facing it turned by
# `turn_deg`: {arena, k, abarax, got [Abarax's got_hit outcome names], started [the moves Abarax started]}.
func _grab_run(tier_path: String, turn_deg := 0.0) -> Dictionary:
	var arena := TestArena.make(self)
	var k := TestArena.spawn(arena, load(tier_path) as ActorDef, ScriptBrain.new([{"frames": 1, "press": [&"interact"]}, {"frames": 400}]),
			Vector3.ZERO, "Knuckle")
	k.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var at := Vector3(0, 0, GRAB_GAP)
	var abarax := TestArena.spawn(arena, load(Duel.ABARAX) as ActorDef, ScriptBrain.new([]), at, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, PI + deg_to_rad(turn_deg)), at))
	var run := {"arena": arena, "k": k, "abarax": abarax, "got": [], "started": []}
	abarax.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: run["got"].append(O.keys()[r.outcome]))
	abarax.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append(m.id))
	return run


# Plays the grab of `run` until it takes hold and the pair is over (or `limit` frames), recording each paired frame:
# [{frame, overlap, hit (the lead's striking hand's [gap, target] on a pair_hit frame, or null), feet {foot: Abarax's}}].
func _play_grab(run: Dictionary, limit := 300) -> Array:
	var k: Actor = run["k"]
	var abarax: Actor = run["abarax"]
	var hit_now := [false]
	k.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
		if kind == &"pair_hit":
			hit_now[0] = true)
	var rows := []
	var held := false
	while k.frame < limit:
		await frames(1)
		if abarax.paired_with == k:
			held = true
		elif held and k.paired_with == null:
			break
		if not held:
			continue
		var k_caps := Bodies.of(k.rig)
		var a_caps := Bodies.of(abarax.rig)
		var hit: Variant = null
		if hit_now[0]:
			hit_now[0] = false
			var left := Bodies.strike_gap(k_caps, a_caps, "hand_l")
			var right := Bodies.strike_gap(k_caps, a_caps, "hand_r")
			hit = left if left[0] < right[0] else right
		var feet := {}
		for foot in [&"foot_l", &"foot_r"]:
			feet[foot] = abarax.rig.bone_global(foot)
		rows.append({"frame": k.frame, "overlap": Bodies.overlap(k_caps, a_caps), "hit": hit, "feet": feet,
				"k": k.global_position, "abarax": abarax.global_position})
	return rows


func test_every_tier_has_the_grab_pair() -> void:
	for path: String in ["res://data/actors/knuckle_1.tres", "res://data/actors/knuckle_2.tres", "res://data/actors/knuckle_3.tres"]:
		assert_eq((load(path) as ActorDef).grab_pair, load(PAIR), path)
	var pair := load(PAIR) as PairedMove
	assert_eq([pair.lead_move, pair.follow_move, pair.moment, pair.follow_ends_down], [&"knuckle_grab_hold", &"grabbed", &"grab", true])


func test_a_grab_takes_hold_and_its_blows_land_on_every_tier() -> void:
	for tier: String in TIERS:
		var run := _grab_run(TIERS[tier])
		var abarax: Actor = run["abarax"]
		var rows: Array = await _play_grab(run)
		var hits := rows.filter(func(r: Dictionary) -> bool: return r["hit"] != null)
		assert_true(rows.size() > 30, "%s's grab takes hold and the pair plays (%d frames)" % [tier, rows.size()])
		assert_eq(run["got"], ["HIT", "HIT", "HIT"], "%s: the grab itself is no blow; the pair's three are" % tier)
		assert_eq(abarax.stats.hp, 100.0 - 32.0, "%s: 8, 8 and 16" % tier)
		for row: Dictionary in hits:
			var hit: Array = row["hit"]
			assert_true(hit[0] <= REACH, "%s: the blow on frame %d reaches %s: %.3f m short" % [tier, row["frame"], hit[1], hit[0]])
			assert_true(hit[0] >= -SINK, "%s: and is not %.3f m inside it (frame %d)" % [tier, -hit[0], row["frame"]])
		var worst := [-INF, "", "", -1]
		for row: Dictionary in rows:
			if row["overlap"][0] > worst[0]:
				worst = [row["overlap"][0], row["overlap"][1], row["overlap"][2], row["frame"]]
		assert_true(worst[0] <= SINK, "%s: at worst %.3f m of the Knuckle's %s in Abarax's %s, on frame %d" % [tier, worst[0], worst[1], worst[2], worst[3]])
		if not hits.is_empty():
			var first: int = hits[0]["frame"]
			for foot in [&"foot_l", &"foot_r"]:
				var plant: Variant = null
				var slide := [0.0, -1]
				for row: Dictionary in rows:
					if row["frame"] < first:
						continue
					var at: Vector3 = row["feet"][foot]
					if at.y > PLANTED:
						plant = null
						continue
					if plant == null:
						plant = at
					var moved := Vector2(at.x - plant.x, at.z - plant.z).length()
					if moved > slide[0]:
						slide = [moved, row["frame"]]
				assert_true(slide[0] <= SKATE, "%s: Abarax's %s slides %.3f m while planted (to frame %d)" % [tier, foot, slide[0], slide[1]])
		var got_up := false
		for i in 120:
			await frames(1)
			got_up = got_up or (abarax.runner.current != null and abarax.runner.current.id == &"getup")
		assert_true(got_up, "%s: Abarax, alive, gets up" % tier)
		await frames(60)
		assert_true(abarax.rig.bone_global(&"Head").y - abarax.global_position.y > 1.4, "%s: and stands" % tier)
		(run["arena"] as Node).free()


func test_the_grab_pairs_clips_do_not_pop() -> void:
	# The lead's pelvis, head and feet move LEAD_STEP at most a 12 fps step and Abarax's VICTIM_FRAME at most a frame; the
	# hands are held to it only across a join.
	var rig: Rig = track((load(TIERS["knuckle_1"]) as ActorDef).rig_scene.instantiate())
	var pair := load(PAIR) as PairedMove
	for role in [&"lead_move", &"follow_move"]:
		var clip := (Registry.fetch(&"moves", pair.get(role)) as MoveData).clip
		var anim := rig.tree.get_animation(clip)
		var step := ClipMotion.step_of(anim)
		var limit := LEAD_STEP if step > 1 else VICTIM_FRAME
		var joins: PackedFloat32Array = anim.get_meta("joins", PackedFloat32Array())
		var joints: Array[StringName] = [&"pelvis", &"Head", &"foot_l", &"foot_r", &"hand_l", &"hand_r"]
		var at := ClipMotion.poses(rig, clip, joints)
		var worst := [0.0, &"", -1]
		for frame: int in at:
			if not at.has(frame - step):
				continue
			var across := Array(joins).any(func(t: float) -> bool: return t * 60.0 >= frame - step - 1e-3 and t * 60.0 <= frame + 1e-3)
			for joint in joints:
				if String(joint).begins_with("hand") and not across:
					continue
				var moved: float = (at[frame][joint] as Vector3).distance_to(at[frame - step][joint])
				if moved > worst[0]:
					worst = [moved, joint, frame]
		assert_true(worst[0] <= limit, "%s: the %s moves %.3f m to f%d (at most %.2f)" % [clip, worst[1], worst[0], worst[2], limit])


func test_walls_hold_both_and_the_grab_plays_or_falls_back_cleanly() -> void:
	# A wall's face 0.6 m behind Abarax (z GRAB_GAP + 0.6) and another's 0.4 m to his side (x 0.4): no capsule ends a frame
	# in a wall, and the grab either plays out with Abarax back on his feet, or is the staggering HIT.
	for tier: String in TIERS:
		var run := _grab_run(TIERS[tier])
		var k: Actor = run["k"]
		var abarax: Actor = run["abarax"]
		var behind := GRAB_GAP + 0.6
		TestArena.wall(run["arena"], Vector3(0, 1.5, behind + 0.25), Vector3(8, 3, 0.5))
		TestArena.wall(run["arena"], Vector3(0.4 + 0.25, 1.5, 0), Vector3(0.5, 3, 8))
		var deepest := -INF
		var paired := false
		for i in 330:
			await frames(1)
			paired = paired or abarax.paired_with == k
			for actor: Actor in [k, abarax]:
				var p := actor.global_position
				deepest = maxf(deepest, maxf(p.z + CAPSULE_RADIUS - behind, p.x + CAPSULE_RADIUS - 0.4))
		assert_true(deepest <= 0.01, "%s: no capsule ends a frame in a wall (deepest %.3f m)" % [tier, deepest])
		assert_eq([k.paired_with, abarax.paired_with], [null, null], "%s: nothing is left paired" % tier)
		if paired:
			assert_true((run["started"] as Array).has(&"getup"), "%s: the grab played, and Abarax got up: %s" % [tier, run["started"]])
		else:
			assert_eq(run["got"], ["GRABBED"], "%s: or it fell back to the staggering hit" % tier)
		assert_true(abarax.rig.bone_global(&"Head").y - abarax.global_position.y > 1.4, "%s: Abarax stands" % tier)
		(run["arena"] as Node).free()


func test_a_grab_that_cannot_be_staged_is_a_staggering_hit() -> void:
	# The same checks as the finisher's: Abarax turned past the facing gate (the Knuckle's finisher_facing_deg, 30), or a
	# wall between their chests. The grab still takes hold of him, as a HIT that staggers, and nothing is paired.
	var turned := _grab_run(TIERS["knuckle_1"], 60.0)
	await Duel.play_to(self, turned["k"], 60)
	assert_eq(turned["got"], ["GRABBED"], "turned 60 degrees away: the grab takes hold")
	assert_eq([(turned["k"] as Actor).paired_with, (turned["abarax"] as Actor).paired_with], [null, null], "unpaired")
	assert_true((turned["started"] as Array).has(&"stagger"), "and he staggers: %s" % [turned["started"]])
	(turned["arena"] as Node).free()
	var walled := _grab_run(TIERS["knuckle_1"])
	TestArena.wall(walled["arena"], Vector3(0, 1.5, 0.45), Vector3(4, 3, 0.04))
	await Duel.play_to(self, walled["k"], 60)
	assert_eq(walled["got"], ["GRABBED"], "with a wall between their chests: the grab takes hold")
	assert_eq([(walled["k"] as Actor).paired_with, (walled["abarax"] as Actor).paired_with], [null, null], "unpaired")
	assert_true((walled["started"] as Array).has(&"stagger"), "and he staggers: %s" % [walled["started"]])
	(walled["arena"] as Node).free()
