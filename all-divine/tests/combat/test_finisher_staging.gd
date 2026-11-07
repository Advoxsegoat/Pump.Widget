extends TestCase
## How the Open Hand finisher is staged, in the game's placement: what the two bodies do to each other over every
## frame of the pair. The bodies are Bodies' capsules (torso 0.13 m, head 0.10 m, limbs thinner).
##   control  from the palm press to the first press that starts a move: 90 frames at most, hit-stop included
##            (spec 4.4: a finisher is 1.5 s at most, and combat never stalls)
##   reach    each pair_hit lands: the striking hand is at most 0.08 m short of the victim's head or torso above the
##            pelvis, and at most 0.05 m inside it
##   contact  no part of either body is more than 0.05 m inside the other's, on any frame
##   skating  after alignment (from the first blow), each planted foot of the follower (ankle 0.10 m or lower) moves
##            0.05 m at most over its plant: each fighter moves by its own clip's root motion
##   aligning from the edge of reach (1.59 m, 59 degrees off, the victim facing toward or away): the follower moves
##            0.10 m at most and turns 20 degrees at most a frame, and the lead's lunge is 0.6 m at most
##   clips    the lead's joints (pelvis, head, hands, feet) move 0.25 m at most from one 12 fps step to the next, the
##            victim's 0.15 m at most from one frame to the next
##   walls    a wall 0.6 m behind the victim and one 0.4 m to its side: neither capsule ends a frame in a wall, the pair
##            plays out, and a survivor gets up in the open
##
## Fighters are the Duel's: `a` (PLAYER Abarax) at the origin facing +Z, `b` (an ENEMY copy of Abarax) a metre in front
## facing back. b's posture is broken on frame 1 (PostureBreaker); a presses palm on frame 10.

const CAP := 90
const REACH := 0.08
const SINK := 0.05
const SKATE := 0.05
const PLANTED := 0.10
const ALIGN_SHIFT := 0.10
const ALIGN_TURN_DEG := 20.0
const LUNGE := 0.6
const LEAD_STEP := 0.25
const VICTIM_FRAME := 0.15
const JOINTS: Array[StringName] = [&"pelvis", &"Head", &"hand_l", &"hand_r", &"foot_l", &"foot_r"]
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const PALM_ON := 10
const CAPSULE_RADIUS := 0.35
const PALM := [{"frames": PALM_ON - 1}, {"frames": 1, "press": [&"palm"]}, {"frames": 400}]


func _foe(hp: float) -> ActorDef:
	var def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	def.max_hp = hp
	return def


# The Duel with b of `hp` broken on frame 1, then placed at `b_at` (if given) before a's steps press palm.
func _duel(hp := 60.0, b_at: Variant = null, a_steps := PALM) -> Dictionary:
	var run := Duel.make(self, a_steps, [], 1.0, _foe(hp))
	track(PostureBreaker.make(run["a"], run["b"]))
	await Duel.play_to(self, run["b"], 1)
	if b_at is Transform3D:
		(run["b"] as Actor).place(b_at)
	return run


# Plays the finisher of `run` from a's palm on PALM_ON until neither is paired (at most `limit` frames more), and
# records each frame of it: [{frame, a, b (positions), b_yaw, overlap, hit (the striking hand's [gap, target] on a
# pair_hit frame, or null), feet {foot: position}}].
func _play(run: Dictionary, limit := 300) -> Array:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var hit_now := [false]
	a.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
		if kind == &"pair_hit":
			hit_now[0] = true)
	await Duel.play_to(self, a, PALM_ON - 1)
	var rows := []
	var until := a.frame + limit
	while a.frame < until:
		await frames(1)
		if a.frame == PALM_ON:
			assert_eq(a.paired_with, b, "the palm starts the finisher")
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
		var feet := {}
		for foot in FEET:
			feet[foot] = b.rig.bone_global(foot)
		rows.append({"frame": a.frame, "a": a.global_position, "b": b.global_position, "b_yaw": b.rotation.y,
				"overlap": Bodies.overlap(a_caps, b_caps), "hit": hit, "feet": feet})
	return rows


func _hits(rows: Array) -> Array:
	return rows.filter(func(r: Dictionary) -> bool: return r["hit"] != null)


func test_control_returns_within_ninety_frames_of_the_press() -> void:
	# a mashes dodge (with the stick pushed, a roll) every frame after the palm: the first roll is when he has control
	# again.
	var steps := [{"frames": PALM_ON - 1}, {"frames": 1, "press": [&"palm"]}]
	for i in 200:
		steps.append({"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)})
	var run: Dictionary = await _duel(60.0, null, steps)
	var a: Actor = run["a"]
	var rolled := [-1]
	a.runner.move_started.connect(func(m: MoveData) -> void:
		if m.id == &"dodge_roll" and rolled[0] < 0:
			rolled[0] = a.frame)
	await Duel.play_to(self, a, PALM_ON)
	assert_eq(a.paired_with, run["b"], "the finisher started")
	await Duel.play_to(self, a, PALM_ON + 150)
	assert_true(rolled[0] > 0, "he rolls at last")
	assert_true(rolled[0] - PALM_ON <= CAP, "control is back %d frames after the press, hit-stop included" % (rolled[0] - PALM_ON))


func test_every_pair_hit_lands_on_the_head_or_chest() -> void:
	var rows: Array = await _play(await _duel())
	var hits := _hits(rows)
	assert_eq(hits.size(), 3, "three blows")
	for row: Dictionary in hits:
		var hit: Array = row["hit"]
		assert_true(hit[0] <= REACH, "the blow on frame %d reaches %s: %.3f m short" % [row["frame"], hit[1], hit[0]])
		assert_true(hit[0] >= -SINK, "and is not %.3f m inside it (frame %d)" % [-hit[0], row["frame"]])


func test_neither_body_passes_through_the_other() -> void:
	var rows: Array = await _play(await _duel())
	var worst := [-INF, "", "", -1]
	for row: Dictionary in rows:
		if row["overlap"][0] > worst[0]:
			worst = [row["overlap"][0], row["overlap"][1], row["overlap"][2], row["frame"]]
	assert_true(rows.size() > 60, "the pair played (%d frames)" % rows.size())
	assert_true(worst[0] <= SINK, "at worst %.3f m of a's %s in b's %s, on frame %d" % worst)


func test_the_follower_does_not_skate() -> void:
	var rows: Array = await _play(await _duel())
	var first := -1
	for row: Dictionary in rows:
		if row["hit"] != null:
			first = row["frame"]
			break
	assert_true(first > 0, "a blow landed")
	for foot in FEET:
		var plant: Variant = null
		var worst := [0.0, -1]
		for row: Dictionary in rows:
			if row["frame"] < first:
				continue
			var at: Vector3 = row["feet"][foot]
			if at.y > PLANTED:
				plant = null
				continue
			if plant == null:
				plant = at
			var slide := Vector2(at.x - plant.x, at.z - plant.z).length()
			if slide > worst[0]:
				worst = [slide, row["frame"]]
		assert_true(worst[0] <= SKATE, "b's %s slides %.3f m while planted (to frame %d)" % [foot, worst[0], worst[1]])


func test_alignment_from_the_edge_of_reach() -> void:
	for side: float in [1.0, -1.0]:
		for away: bool in [false, true]:
			var off := deg_to_rad(59.0) * side
			var at := Vector3(sin(off), 0.0, cos(off)) * 1.59
			var toward_a := atan2(-at.x, -at.z)
			var b_at := Transform3D(Basis(Vector3.UP, toward_a + (PI if away else 0.0)), at)
			var label := "%s side, facing %s" % ["left" if side > 0 else "right", "away" if away else "toward"]
			var run: Dictionary = await _duel(60.0, b_at)
			var rows: Array = await _play(run)
			var hits := _hits(rows)
			assert_eq(hits.size(), 3, "three blows (%s)" % label)
			if hits.is_empty():
				(run["arena"] as Node).free()
				continue
			var first: int = hits[0]["frame"]
			var b_shift := 0.0
			var lunge := 0.0
			var turn := 0.0
			var last_yaw: float = b_at.basis.get_euler().y
			for row: Dictionary in rows:
				turn = maxf(turn, absf(rad_to_deg(angle_difference(last_yaw, row["b_yaw"]))))
				last_yaw = row["b_yaw"]
				if row["frame"] <= first:
					b_shift = maxf(b_shift, Vector2(row["b"].x - at.x, row["b"].z - at.z).length())
					lunge = maxf(lunge, Vector2(row["a"].x, row["a"].z).length())
			assert_true(b_shift <= ALIGN_SHIFT, "b moves %.3f m while aligning (%s)" % [b_shift, label])
			assert_true(turn <= ALIGN_TURN_DEG, "b turns %.1f degrees in a frame at most (%s)" % [turn, label])
			assert_true(lunge <= LUNGE, "a lunges %.3f m (%s)" % [lunge, label])
			for row: Dictionary in hits:
				var hit: Array = row["hit"]
				assert_true(hit[0] <= REACH and hit[0] >= -SINK, "the blow on frame %d lands (%.3f m, %s)" % [row["frame"], hit[0], label])
			(run["arena"] as Node).free()


func test_the_pairs_clips_do_not_pop() -> void:
	var rig: Rig = track((load(Duel.ABARAX) as ActorDef).rig_scene.instantiate())
	var pair := load("res://data/pairs/finisher_open_hand.tres") as PairedMove
	for role in [&"lead_move", &"follow_move"]:
		var clip := (Registry.fetch(&"moves", pair.get(role)) as MoveData).clip
		var anim := rig.tree.get_animation(clip)
		var step := 5 if role == &"lead_move" else 1
		var limit := LEAD_STEP if role == &"lead_move" else VICTIM_FRAME
		var last := {}
		var worst := [0.0, &"", -1]
		rig.play_move(clip, 0.0)
		var f := 0
		while f <= Marks.frame_of(anim.length):
			rig.set_move_time(f / 60.0)
			rig.tick(1.0 / 60.0)
			for joint in JOINTS:
				var at := rig.animated_pose(joint).origin - rig.global_position
				if last.has(joint) and at.distance_to(last[joint]) > worst[0]:
					worst = [at.distance_to(last[joint]), joint, f]
				last[joint] = at
			f += step
		assert_true(worst[0] <= limit, "%s: the %s moves %.3f m to frame %d (at most %.2f)" % [clip, worst[1], worst[0], worst[2], limit])


# A wall: a box of `size` whose centre is `at`, on the world layer.
func _wall(arena: Node3D, at: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = at  # before it is in the tree, so that it is never anywhere else (the arena is at the origin)
	arena.add_child(wall)


# How far a capsule standing at `p` is into the walls whose faces are at z `behind_z` and x `side_x`: its deepest.
static func _into_walls(p: Vector3, behind_z: float, side_x: float) -> float:
	return maxf(p.z + CAPSULE_RADIUS - behind_z, p.x + CAPSULE_RADIUS - side_x)


func test_walls_hold_both_fighters_and_a_survivor_gets_up_in_the_open() -> void:
	# b stands at z 1 facing a: a wall's face 0.6 m behind it (z 1.6) and another's 0.4 m to its side (x 0.4).
	var run: Dictionary = await _duel(1000.0)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	_wall(run["arena"], Vector3(0, 1.5, 1.6 + 0.25), Vector3(8, 3, 0.5))
	_wall(run["arena"], Vector3(0.4 + 0.25, 1.5, 0), Vector3(0.5, 3, 8))
	var rows: Array = await _play(run)
	assert_true(rows.size() > 60, "the pair plays (%d frames)" % rows.size())
	assert_eq(_hits(rows).size(), 3, "all three blows")
	var deepest := -INF
	for row: Dictionary in rows:
		deepest = maxf(deepest, maxf(_into_walls(row["a"], 1.6, 0.4), _into_walls(row["b"], 1.6, 0.4)))
	var got_up := false
	for i in 150:
		await frames(1)
		got_up = got_up or (b.runner.current != null and b.runner.current.id == &"getup")
		for actor: Actor in [a, b]:
			deepest = maxf(deepest, _into_walls(actor.global_position, 1.6, 0.4))
	assert_true(got_up, "b gets up")
	assert_true(deepest <= 0.01, "no capsule ends a frame in a wall (deepest %.3f m)" % deepest)
	assert_true(b.rig.bone_global(&"Head").y - b.global_position.y > 1.4, "b stands")
	assert_eq([a.paired_with, b.paired_with], [null, null], "the pair is over")
