class_name TestSpringReset
extends TestCase
## Resetting the springs (Rig.reset_springs, which Actor.place calls: a spawn, a region change, a revive) leaves them exactly as they
## were set: every property of every joint of the scarf's simulator and the feather's, after one reset and after a hundred, is what
## it was; a reset rig's scarf hangs where a never-reset rig's hangs, and in a seeded fight that begins with Main's own place the
## scarf's bones are where they are in the same fight without one. (Fix round 3: the engine gives the joints of a rebuilt setting
## its defaults, radius 0.1, stiffness 1, no drag, no gravity, and the scarf swung on those from the first frame of the game.)

const RIG := "res://actors/abarax/abarax_rig.tscn"
var dbg: Array = []
var dbgs: Array = []
# The head's and the feet's poses in every frame of the fights of _scarf_in_fight, by whether he was placed.
var poses := {}
const SCARF: Array[StringName] = [&"scarf_01", &"scarf_02", &"scarf_03", &"scarf_04"]


# Every property of both simulators (their settings and each joint's own) by node name and property name.
static func dump(r: Rig) -> Dictionary:
	var out := {}
	for spring: SpringBoneSimulator3D in r.skeleton.find_children("*", "SpringBoneSimulator3D", false, false):
		for property in spring.get_property_list():
			if property["usage"] & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR) != 0:
				out["%s/%s" % [spring.name, property["name"]]] = spring.get(property["name"])
	return out


static func _differences(was: Dictionary, now: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in was:
		if not now.has(key) or not is_same(was[key], now[key]) and str(was[key]) != str(now[key]):
			lines.append("%s: %s -> %s" % [key, was[key], now.get(key)])
	for key in now:
		if not was.has(key):
			lines.append("%s: (none) -> %s" % [key, now[key]])
	return lines


# A rig on its own, in the tree, ticked `count` times standing.
func _rig(count: int) -> Rig:
	var r: Rig = track(load(RIG).instantiate())
	await frames(1)
	for i in count:
		r.tick(1.0 / 60)
	return r


func test_a_reset_leaves_every_property_of_every_joint_as_it_was() -> void:
	var r := await _rig(5)
	var was := dump(r)
	assert_true(was.size() > 60, "the dump has the settings and the joints (%d properties)" % was.size())
	assert_true(was.has("Scarf/settings/0/joints/3/gravity"), "the scarf's last joint is in the dump")
	assert_true(was.has("Feather/settings/0/joints/2/stiffness"), "the feather's last joint is in the dump")
	r.reset_springs()
	r.tick(1.0 / 60)
	var once := _differences(was, dump(r))
	assert_eq(once, [] as Array[String], "after one reset these differ: %s" % [once])
	await frames(2)  # the engine does more after the frame a restart was made in
	r.tick(1.0 / 60)
	var later := _differences(was, dump(r))
	assert_eq(later, [] as Array[String], "two frames after one reset these differ: %s" % [later])
	for i in 99:
		r.reset_springs()
		await frames(1)
		r.tick(1.0 / 60)
	var hundred := _differences(was, dump(r))
	assert_eq(hundred, [] as Array[String], "after a hundred resets these differ: %s" % [hundred])


# Where the scarf's and the feather's tips are, in the head's frame.
static func _tips(r: Rig) -> Array[Vector3]:
	var head := r.shown_pose(&"Head")
	return [head.affine_inverse() * r.shown_pose(&"scarf_04").origin, head.affine_inverse() * r.shown_pose(&"feather_03").origin]


func test_the_scarf_hangs_after_a_reset_where_it_hangs_without_one() -> void:
	var never := await _rig(0)
	var reset := await _rig(0)
	for i in 400:
		if i == 5:
			reset.reset_springs()
		never.tick(1.0 / 60)
		reset.tick(1.0 / 60)
	var a := _tips(never)
	var b := _tips(reset)
	assert_true(a[0].distance_to(b[0]) < 0.001, "the scarf's tip at rest is %.1f mm from where a never-reset rig's is (at most 1)" % (a[0].distance_to(b[0]) * 1000.0))
	assert_true(a[1].distance_to(b[1]) < 0.001, "the feather's tip at rest is %.1f mm from where a never-reset rig's is (at most 1)" % (a[1].distance_to(b[1]) * 1000.0))


# The scarf's bones, in the world, in every frame of a seeded fight (`placed`: Main's own place first).
func _scarf_in_fight(placed: bool, count: int) -> Array:
	var log: Array = []
	var head_poses: Array[String] = []
	await FightBot.play(self, 9, [9], count, placed, func(player: Actor, _f: int) -> void:
		var row := PackedVector3Array()
		for bone in SCARF:
			row.append(player.rig.shown_pose(bone).origin)
		row.append(player.global_position)
		head_poses.append(var_to_str(player.rig.shown_pose(&"Head")) + var_to_str(player.rig.shown_pose(&"foot_l")) + var_to_str(player.rig.shown_pose(&"foot_r")))
		log.append(row))
	poses[placed] = head_poses
	return log


func test_a_fight_that_begins_with_a_place_has_the_scarf_a_fight_without_one_has() -> void:
	var without: Array = await _scarf_in_fight(false, 600)
	var with: Array = await _scarf_in_fight(true, 600)
	assert_eq(with.size(), 600, "the fight with a place ran")
	assert_eq(without.size(), 600, "the fight without one ran")
	var fight_apart := 0.0
	var settled := 0  # the first frame from which every later frame agrees to a millimetre
	var worst := 0.0
	for f in 600:
		fight_apart = maxf(fight_apart, (with[f] as PackedVector3Array)[4].distance_to((without[f] as PackedVector3Array)[4]))
		var apart := 0.0
		for k in 4:
			apart = maxf(apart, (with[f] as PackedVector3Array)[k].distance_to((without[f] as PackedVector3Array)[k]))
		if apart > 0.001:
			settled = f + 1
			worst = maxf(worst, apart)
	assert_true(poses[true] == poses[false], "the head's and the feet's poses are the same in every frame, placed or not (the restart leaves the other modifiers as they were)")
	assert_eq(fight_apart, 0.0, "the two fights are the same fight (the player's places differ by %.4f m)" % fight_apart)
	print("scarf, placed vs never placed: the two agree to a millimetre from frame ", settled, " (worst before that ", snappedf(worst * 1000.0, 0.1), " mm)")
	assert_true(settled <= 30, "the two scarves agree to a millimetre only from frame %d (worst %.1f mm before it)" % [settled, worst * 1000.0])


# --- nothing snaps when he is put somewhere ---

const CHAINS := {&"feather_01": &"Head", &"feather_02": &"Head", &"feather_03": &"Head", &"scarf_01": &"neck_01", &"scarf_02": &"neck_01", &"scarf_03": &"neck_01", &"scarf_04": &"neck_01"}


# A bone's direction (its +Y) in the frame of `parent`.
static func _direction(r: Rig, bone: StringName, parent: StringName) -> Vector3:
	return (r.shown_pose(parent).basis.inverse() * r.shown_pose(bone).basis.y).normalized()


# The most any bone of the feather's chain (first) and of the scarf (second) turns in one frame, over the `count` frames from now (the
# first is measured against the pose now shown, so it is the frame after a place), in the head's and the neck's frames.
func _worst_turn(actor: Actor, count: int) -> Array[float]:
	var before := {}
	for bone in CHAINS:
		before[bone] = _direction(actor.rig, bone, CHAINS[bone])
	var worst: Array[float] = [0.0, 0.0]
	for i in count:
		await frames(1)
		for bone in CHAINS:
			var now := _direction(actor.rig, bone, CHAINS[bone])
			var which := 0 if String(bone).begins_with("feather") else 1
			worst[which] = maxf(worst[which], rad_to_deg(now.angle_to(before[bone])))
			before[bone] = now
	return worst


# An Abarax who has run for a second (the scarf streams behind him) or stood still (it hangs), then does `what` (a place, a revive), then
# is watched for 31 frames: the worst turn of each chain (see _worst_turn).
func _after(what: Callable, running: bool, lying := false) -> Array[float]:
	var arena := TestArena.make(self)
	var steps: Array = [{"frames": 70, "move": Vector2(1, 0)}] if running else [{"frames": 70}]
	var actor := TestArena.spawn(arena, load("res://data/actors/abarax.tres") as ActorDef, ScriptBrain.new(steps))
	await frames(75)
	if lying:
		actor.stats.take_damage(actor.stats.max_hp)
		actor.die()
		await frames(160)
	what.call(actor)
	return await _worst_turn(actor, 31)


const TURNED_ABOUT := Transform3D(Basis(Vector3.UP, PI), Vector3(5, 0, 0))
const FAR := Transform3D(Basis(Vector3.UP, 2.0), Vector3(60, 0, -40))
const REVIVED := Transform3D(Basis(Vector3.UP, 0.5), Vector3(-3, 0, 2))


func test_nothing_snaps_when_he_is_placed_turned_about() -> void:
	var worst := await _after(func(actor: Actor) -> void: actor.place(TURNED_ABOUT), false)
	assert_true(worst[0] <= 20.0, "placed 5 m off and turned about: a bone of the feather turned %.0f degrees in a frame in the first 31 (at most 20)" % worst[0])
	assert_true(worst[1] <= 20.0, "placed 5 m off and turned about: a bone of the scarf turned %.0f degrees in a frame in the first 31 (at most 20)" % worst[1])


func test_nothing_snaps_when_he_changes_region() -> void:
	var worst := await _after(func(actor: Actor) -> void: actor.place(FAR), false)
	assert_true(worst[0] <= 20.0, "a region change: a bone of the feather turned %.0f degrees in a frame in the first 31 (at most 20)" % worst[0])
	assert_true(worst[1] <= 20.0, "a region change: a bone of the scarf turned %.0f degrees in a frame in the first 31 (at most 20)" % worst[1])


func test_a_chain_streaming_behind_a_runner_hangs_when_he_is_placed() -> void:
	# From a run the body goes to standing at the place (its speed is zeroed) and the scarf from streaming to hanging: that change is the
	# pose's, 20.3 degrees of the tip at the first frame today (35 before the restart ran the chain to rest); the limit here is 25.
	var worst := await _after(func(actor: Actor) -> void: actor.place(TURNED_ABOUT), true)
	assert_true(worst[0] <= 20.0, "placed while running: a bone of the feather turned %.0f degrees in a frame in the first 31 (at most 20)" % worst[0])
	assert_true(worst[1] <= 25.0, "placed while running: a bone of the scarf turned %.0f degrees in a frame in the first 31 (at most 25)" % worst[1])


func test_nothing_snaps_when_he_is_revived_from_lying() -> void:
	var worst := await _after(func(actor: Actor) -> void: actor.revive(REVIVED), true, true)
	assert_true(worst[0] <= 20.0, "revived from lying: a bone of the feather turned %.0f degrees in a frame in the first 31 (at most 20)" % worst[0])
	assert_true(worst[1] <= 20.0, "revived from lying: a bone of the scarf turned %.0f degrees in a frame in the first 31 (at most 20)" % worst[1])
