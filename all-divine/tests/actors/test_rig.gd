extends TestCase
## Abarax's rig (actors/abarax/abarax_rig.tscn, script actors/rig.gd): the AnimationTree layout, stepped
## move playback, the move crossfade, and the hitboxes and hurtbox. Headless: the tree is advanced by
## Rig.tick only, so everything here is read straight after a tick.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const MODEL := "res://assets/characters/abarax/abarax.glb"
const LIB := "res://assets/anim/abarax/library.tres"

# The gameplay time of the move that _play and _tick are playing, as the move runner keeps it.
var _move_time := 0.0


func rig() -> Rig: return track(load(RIG).instantiate())


func test_stepped_time() -> void:
	assert_near(Rig.stepped_time(0.13, 12), 1.0 / 12, 1e-6); assert_near(Rig.stepped_time(0.25, 12), 0.25, 1e-6)
	assert_near(Rig.stepped_time(0.01, 12), 1.0 / 12, 1e-6); assert_eq(Rig.stepped_time(0.0, 12), 0.0)
	assert_near(Rig.stepped_time(0.13, 0), 0.13, 1e-9)
	# Frame 15 at 60 Hz is 3/12 s exactly; float noise below the grid must not drop it a step.
	assert_near(Rig.stepped_time(15 / 60.0, 12), 3.0 / 12, 1e-6)
	assert_near(Rig.stepped_time(0.4, 24), 0.375, 1e-6)
	assert_near(Rig.stepped_time(-0.1, 12), -0.1, 1e-9, "no step before the start")


func test_tree_layout() -> void:
	var r := rig()
	var root := r.tree.tree_root as AnimationNodeBlendTree
	assert_ne(root, null, "the tree root is a blend tree")
	assert_true(root.get_node(&"loco") is AnimationNodeBlendSpace1D, "loco")
	assert_true(root.get_node(&"loco_scale") is AnimationNodeTimeScale, "loco_scale")
	for n in [&"move_a", &"move_b"]:
		assert_true(root.get_node(n) is AnimationNodeAnimation, n)
	for n in [&"seek_a", &"seek_b"]:
		assert_true(root.get_node(n) is AnimationNodeTimeSeek, n)
	for n in [&"move_ab", &"move_blend"]:
		assert_true(root.get_node(n) is AnimationNodeBlend2, n)
	# [input node, input index, output node] for every connection.
	var links := {}
	var conns: Array = root.get(&"node_connections")
	for i in range(0, conns.size(), 3):
		links["%s/%d" % [conns[i], conns[i + 1]]] = StringName(conns[i + 2])
	assert_eq(links, {
		"loco_scale/0": &"loco",
		"seek_a/0": &"move_a",
		"seek_b/0": &"move_b",
		"move_ab/0": &"seek_a",
		"move_ab/1": &"seek_b",
		"move_blend/0": &"loco_scale",
		"move_blend/1": &"move_ab",
		"output/0": &"move_blend",
	})


func test_locomotion_points_are_clip_ground_speeds() -> void:
	var r := rig()
	var lib := load(LIB) as AnimationLibrary
	var loco := (r.tree.tree_root as AnimationNodeBlendTree).get_node(&"loco") as AnimationNodeBlendSpace1D
	assert_eq(loco.get_blend_point_count(), 4)
	var want := {&"idle": 0.0}
	for n in [&"walk", &"jog", &"sprint"]:
		want[n] = float(lib.get_animation(n).get_meta("ground_speed"))
	for i in loco.get_blend_point_count():
		var point := loco.get_blend_point_name(i)
		assert_true(want.has(point), "point %d is called %s" % [i, point])
		assert_eq((loco.get_blend_point_node(i) as AnimationNodeAnimation).animation, point, "point %s plays its own clip" % point)
		assert_near(loco.get_blend_point_position(i), want.get(point, -1.0), 1e-4, "point %s" % point)
	assert_eq(loco.sync_mode, AnimationNodeBlendSpace1D.SYNC_MODE_INDEPENDENT, "sync on: the clips out of the blend keep running")
	assert_true(loco.max_space >= float(want[&"sprint"]) and loco.min_space <= 0.0, "the space holds every point")


func test_root_motion_track_set() -> void:
	var r := rig()
	var skel := ClipBuilder.skeleton_path(load(MODEL))
	assert_eq(r.tree.root_motion_track, NodePath("Model/%s:root" % skel))
	assert_eq(r.tree.root_node, NodePath(".."))
	assert_eq(r.tree.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	var library := r.tree.get_animation_library(&"")
	assert_eq(library.get_animation_list(), (load(LIB) as AnimationLibrary).get_animation_list(), "the Abarax clips, in the library under the default name")
	assert_eq(library.get_animation(&"palm_jab"), (load(LIB) as AnimationLibrary).get_animation(&"palm_jab"), "the clips themselves are the library's, not copies")
	assert_eq(r.skeleton, r.get_node(NodePath("Model/%s" % skel)))


func test_move_pose_matches_clip_time_and_holds_between_steps() -> void:
	var r := rig(); r.play_move(&"palm_jab", 0.0); r.set_move_time(0.25); r.tick(0.0)
	var a: Animation = r.tree.get_animation(&"palm_jab")
	var tr := a.find_track(NodePath("Model/%s:hand_l" % ClipBuilder.skeleton_path(load("res://assets/characters/abarax/abarax.glb"))), Animation.TYPE_ROTATION_3D)
	var want := a.rotation_track_interpolate(tr, 0.25)
	var got := r.skeleton.get_bone_pose_rotation(r.skeleton.find_bone("hand_l"))
	assert_true(got.is_equal_approx(want) or got.angle_to(want) < 0.002)
	r.set_move_time(0.27); r.tick(1.0 / 60)
	assert_true(r.skeleton.get_bone_pose_rotation(r.skeleton.find_bone("hand_l")).angle_to(want) < 0.002)


func test_smooth_clip_follows_move_time_exactly() -> void:
	# dodge_roll has step_fps 0: the pose is at the gameplay time itself, whatever delta the tick had.
	var r := rig(); r.play_move(&"dodge_roll", 0.0)
	var a: Animation = r.tree.get_animation(&"dodge_roll")
	var tr := a.find_track(NodePath("Model/%s:spine_02" % ClipBuilder.skeleton_path(load(MODEL))), Animation.TYPE_ROTATION_3D)
	var bone := r.skeleton.find_bone("spine_02")
	for t in [0.1, 0.27, 0.3]:
		r.set_move_time(t); r.tick(0.5)
		var got := r.skeleton.get_bone_pose_rotation(bone)
		assert_true(_angle(got, a.rotation_track_interpolate(tr, t)) < 1e-5, "t = %s" % t)


func test_root_travel_stays_out_of_the_pose() -> void:
	# The roll's root track carries ~5 m of travel; it is root motion, so the root bone stays home.
	var r := rig(); r.play_move(&"dodge_roll", 0.0); r.set_move_time(0.45); r.tick(1.0 / 60)
	assert_vec_near(r.skeleton.get_bone_pose_position(r.skeleton.find_bone("root")), Vector3.ZERO, 1e-4)


func test_crossfade_between_moves() -> void:
	var r := rig()
	r.play_move(&"palm_jab", 0.0); r.set_move_time(0.1); r.tick(1.0 / 60)
	assert_near(r.move_weight(), 1.0, 1e-6)
	r.play_move(&"palm_cross", 0.1)
	for i in 3:
		r.tick(1.0 / 60)
	# The first move went into move_a and this one into move_b, so move_ab's amount is the new slot's weight.
	assert_near(float(r.tree.get(&"parameters/move_ab/blend_amount")), 0.5, 0.05, "three ticks into a 0.1 s blend_in")
	assert_near(r.move_weight(), 1.0, 1e-6, "the move layer stays up through a move-to-move blend")
	for i in 3:
		r.tick(1.0 / 60)
	assert_near(float(r.tree.get(&"parameters/move_ab/blend_amount")), 1.0, 1e-6, "done after 0.1 s")
	r.play_move(&"palm_jab", 0.0); r.tick(0.0)
	assert_near(float(r.tree.get(&"parameters/move_ab/blend_amount")), 0.0, 1e-6, "the third move goes back to move_a")


func test_cancel_inside_blend_in_does_not_jump_the_pose() -> void:
	# A cancel two ticks into a move's blend_in: the shown pose changes over the cancel tick no more than it
	# did over the tick before (within 1.5 times, per bone). Here the move before is locomotion, not a move
	# in the other slot, so this holds without a snapshot; the next test is the one that needs it.
	var r := rig()
	_play(r, &"palm_jab", 0.1)
	_tick(r)
	var before := _positions(r)
	_tick(r)
	var cancel_from := _positions(r)
	_play(r, &"palm_cross", 0.1)
	_tick(r)
	assert_eq(_worst_jump(before, cancel_from, _positions(r)), "")


func test_cancel_inside_a_move_to_move_crossfade_does_not_jump_the_pose() -> void:
	# The jab, then the cross fading in over it, then a roll while the cross is still fading in: the roll
	# would take the jab's slot, which still shows a share of the pose. With no time passing, the cancel must
	# change nothing that is shown: a rig that was cancelled and one with the same history that was not are
	# alike, bone for bone, modifiers included (so none is applied twice to the held pose).
	for blend_in: float in [0.1, 0.05]:
		var r := rig(); var control := rig()
		_jab_then_cross(r, blend_in); _jab_then_cross(control, blend_in)
		var ab := float(r.tree.get(Rig.MOVE_AB))
		assert_true(ab > 0.0 and ab < 1.0, "the first two moves are still crossfading (%s)" % ab)
		_play(r, &"dodge_roll", blend_in)
		r.tick(0.0); control.tick(0.0)
		assert_eq(_worst_difference(r, control, true), "", "blend_in %s" % blend_in)


func test_cancelled_into_move_fades_in_over_the_held_pose_and_takes_over() -> void:
	# Then time passes: the roll fades in over the held pose in blend_in seconds, and after that the clips
	# show the roll and nothing else, as on a rig that played it alone.
	var r := rig(); var alone := rig()
	_jab_then_cross(r, 0.1)
	_play(r, &"dodge_roll", 0.1)
	for i in 7:
		_tick(r)
	assert_near(float(r.tree.get(Rig.MOVE_AB)), 0.0, 1e-6, "the fade is done, onto the slot the jab left")
	_play(alone, &"dodge_roll", 0.0)
	for i in 7:
		_tick(alone)
	assert_eq(_worst_difference(r, alone, false), "", "only the roll shows")


func test_cancel_holds_the_pose_in_a_one_key_clip_of_the_rigs_own() -> void:
	# The slot the fading move was in is loaded with SNAPSHOT_CLIP: one key on each rotation track (and on the
	# pelvis's position), holding the pose the tree showed. The clip is in this rig's library, not the actor's.
	var r := rig(); var other := rig()
	_play(r, &"palm_jab", 0.1)
	_tick(r); _tick(r)
	_play(r, &"palm_cross", 0.1)
	_tick(r)
	assert_false(r.tree.has_animation(Rig.SNAPSHOT_CLIP), "none until a move is cancelled mid-fade")
	var hand := r.skeleton.get_bone_pose_rotation(r.skeleton.find_bone(&"hand_l"))
	var pelvis := r.skeleton.get_bone_pose_position(r.skeleton.find_bone(&"pelvis"))
	_play(r, &"palm_jab", 0.1)
	assert_true(r.tree.has_animation(Rig.SNAPSHOT_CLIP))
	var held := r.tree.get_animation(Rig.SNAPSHOT_CLIP)
	var path := "Model/%s:" % ClipBuilder.skeleton_path(load(MODEL))
	var rotation := held.find_track(NodePath(path + "hand_l"), Animation.TYPE_ROTATION_3D)
	var position := held.find_track(NodePath(path + "pelvis"), Animation.TYPE_POSITION_3D)
	assert_true(rotation >= 0 and position >= 0, "a key track for the hand's turn and the pelvis's place")
	for t in held.get_track_count():
		assert_eq(held.track_get_key_count(t), 1, "track %d (%s)" % [t, held.track_get_path(t)])
	assert_true(_angle(held.track_get_key_value(rotation, 0) as Quaternion, hand) < 1e-4, "the hand as the clips had it")
	assert_vec_near(held.track_get_key_value(position, 0) as Vector3, pelvis, 1e-5, "and the pelvis")
	var slots := [(r.tree.tree_root as AnimationNodeBlendTree).get_node(&"move_a") as AnimationNodeAnimation,
			(r.tree.tree_root as AnimationNodeBlendTree).get_node(&"move_b") as AnimationNodeAnimation]
	assert_eq([slots[0].animation, slots[1].animation].count(Rig.SNAPSHOT_CLIP), 1, "in one slot; the new move is in the other")
	assert_eq([slots[0].animation, slots[1].animation].count(&"palm_jab"), 1)
	assert_false(other.tree.has_animation(Rig.SNAPSHOT_CLIP), "another rig of the actor does not have it")
	assert_false((load(LIB) as AnimationLibrary).has_animation(Rig.SNAPSHOT_CLIP), "nor does the actor's library")


func test_cancel_after_the_fade_is_done_needs_no_snapshot() -> void:
	var r := rig()
	_play(r, &"palm_jab", 0.1)
	for i in 8:
		_tick(r)
	_play(r, &"palm_cross", 0.1)
	for i in 8:
		_tick(r)
	_play(r, &"palm_jab", 0.1)
	assert_false(r.tree.has_animation(Rig.SNAPSHOT_CLIP), "the fade is over: the other slot shows nothing, and the move takes it")


func test_move_layer_fades_in_and_out() -> void:
	var r := rig()
	assert_near(r.move_weight(), 0.0, 1e-6, "locomotion only at first")
	r.play_move(&"palm_jab", 0.05)
	r.tick(1.0 / 60)
	assert_near(r.move_weight(), 1.0 / 3, 1e-4, "one tick into a 0.05 s blend_in")
	r.tick(1.0 / 60); r.tick(1.0 / 60)
	assert_near(r.move_weight(), 1.0, 1e-4)
	r.stop_move(0.1)
	for i in 3:
		r.tick(1.0 / 60)
	assert_near(r.move_weight(), 0.5, 1e-4, "halfway through a 0.1 s blend_out")
	for i in 3:
		r.tick(1.0 / 60)
	assert_near(r.move_weight(), 0.0, 1e-4)
	assert_near(float(r.tree.get(&"parameters/move_blend/blend_amount")), 0.0, 1e-4, "the tree has it too")
	r.play_move(&"palm_cross", 0.0)
	assert_near(r.move_weight(), 1.0, 1e-6, "a zero blend_in is at once, before any tick")


func test_locomotion_sets_speed_and_direction() -> void:
	var r := rig()
	r.set_locomotion(5.0, false); r.tick(1.0 / 60)
	assert_near(float(r.tree.get(&"parameters/loco/blend_position")), 5.0, 1e-6)
	assert_near(float(r.tree.get(&"parameters/loco_scale/scale")), 1.0, 1e-6)
	r.set_locomotion(1.0, true); r.tick(1.0 / 60)
	assert_near(float(r.tree.get(&"parameters/loco/blend_position")), 1.0, 1e-6)
	assert_near(float(r.tree.get(&"parameters/loco_scale/scale")), -1.0, 1e-6, "backward plays the cycle in reverse")


func test_rigs_do_not_share_move_slots() -> void:
	# Two rigs from one scene: a move in one must not change the clip the other's slot plays.
	var a := rig(); var b := rig()
	a.play_move(&"palm_jab", 0.0); b.play_move(&"dodge_roll", 0.0)
	var a_slot := (a.tree.tree_root as AnimationNodeBlendTree).get_node(&"move_a") as AnimationNodeAnimation
	var b_slot := (b.tree.tree_root as AnimationNodeBlendTree).get_node(&"move_a") as AnimationNodeAnimation
	assert_eq(a_slot.animation, &"palm_jab")
	assert_eq(b_slot.animation, &"dodge_roll")
	var scene_root := (load(RIG) as PackedScene).instantiate()
	var fresh := (scene_root.get_node("AnimationTree") as AnimationTree).tree_root as AnimationNodeBlendTree
	assert_ne((fresh.get_node(&"move_a") as AnimationNodeAnimation).animation, &"palm_jab", "the scene's own tree is untouched")
	scene_root.free()


func test_bone_global_is_current_after_a_tick() -> void:
	var r := rig()
	r.position = Vector3(2.0, 0.0, -1.0)
	r.play_move(&"palm_jab", 0.0); r.set_move_time(0.0); r.tick(0.0)
	var head := r.bone_global(&"Head")
	assert_true(head.y > 1.3 and head.y < 2.0, "the head is %s m up" % head.y)
	assert_near(head.x, 2.0, 0.3, "and moves with the rig")
	var before := r.bone_global(&"hand_l")
	r.set_move_time(0.25); r.tick(1.0 / 60)
	assert_true(r.bone_global(&"hand_l").distance_to(before) > 0.05, "the hand moved within the same tick")


func test_hitbox_toggle() -> void:
	var r := rig(); r.set_hitbox_active(&"palm_r", true)
	assert_eq(r.active_hitboxes(), [&"palm_r"])
	r.set_hitbox_active(&"palm_l", true)
	assert_eq(r.active_hitboxes(), [&"palm_l", &"palm_r"])
	for id in [&"palm_l", &"palm_r"]:
		assert_false((r.get_node("Hitboxes/%s/zone" % id) as Area3D).monitoring, "%s only holds its shape: the scanner looks" % id)
	r.set_hitbox_active(&"palm_r", false); r.set_hitbox_active(&"palm_l", false)
	assert_eq(r.active_hitboxes(), [])


func test_hitbox_shape_and_hurtbox() -> void:
	var r := rig()
	assert_eq(r.hitbox_shape(&"palm_l"), r.get_node("Hitboxes/palm_l/zone/shape"))
	assert_eq(r.hitbox_shape(&"palm_r"), r.get_node("Hitboxes/palm_r/zone/shape"))
	assert_eq(r.hurtbox, r.get_node("Hurtbox"))
	assert_eq(quietly(func() -> Variant: return r.hitbox_shape(&"no_such_hitbox")), null)


func test_hitboxes_ride_the_hands() -> void:
	var r := rig()
	var skel_path := "../../Model/%s" % ClipBuilder.skeleton_path(load(MODEL))
	var hitbox_bit := _layer_bit("hitbox")
	var hurtbox_bit := _layer_bit("hurtbox")
	for pair in [[&"palm_l", "hand_l"], [&"palm_r", "hand_r"]]:
		var attach := r.get_node("Hitboxes/%s" % pair[0]) as BoneAttachment3D
		assert_ne(attach, null, pair[0])
		assert_eq(attach.bone_name, pair[1], pair[0])
		assert_true(attach.use_external_skeleton, "%s uses the model's skeleton" % pair[0])
		assert_eq(attach.external_skeleton, NodePath(skel_path), pair[0])
		assert_eq(attach.get_skeleton(), r.skeleton, pair[0])
		var zone := attach.get_node("zone") as Area3D
		assert_eq(zone.collision_layer, hitbox_bit, "%s is on the hitbox layer only" % pair[0])
		assert_eq(zone.collision_mask, hurtbox_bit, "%s looks for hurtboxes" % pair[0])
		assert_false(zone.monitoring, "%s starts off" % pair[0])
		var shapes := zone.find_children("*", "CollisionShape3D", false, false)
		assert_eq(shapes.size(), 1, pair[0])
		var sphere := (shapes[0] as CollisionShape3D).shape as SphereShape3D
		if sphere == null:
			fail("%s is a sphere" % pair[0])
		else:
			assert_near(sphere.radius, 0.18, 1e-6, pair[0])
	# BoneAttachment3D follows the skeleton when it updates, which is once a frame.
	r.play_move(&"palm_jab", 0.0); r.set_move_time(0.25); r.tick(0.0)
	await frames(1)
	assert_vec_near((r.get_node("Hitboxes/palm_l") as Node3D).global_position, r.bone_global(&"hand_l"), 1e-3)
	assert_vec_near((r.get_node("Hitboxes/palm_r") as Node3D).global_position, r.bone_global(&"hand_r"), 1e-3)


func test_hurtbox_is_a_body_capsule() -> void:
	var r := rig()
	var hurt := r.get_node("Hurtbox") as Area3D
	assert_ne(hurt, null)
	assert_eq(hurt.collision_layer, _layer_bit("hurtbox"))
	var shapes := hurt.find_children("*", "CollisionShape3D", false, false)
	assert_eq(shapes.size(), 1)
	var holder := shapes[0] as CollisionShape3D
	var capsule := holder.shape as CapsuleShape3D
	if capsule == null:
		fail("a capsule")
	else:
		assert_near(capsule.radius, 0.35, 1e-6)
		assert_near(capsule.height, 1.7, 1e-6)
	assert_vec_near(holder.position, Vector3(0, 0.9, 0), 1e-6)


func test_unknown_clip_or_hitbox_changes_nothing() -> void:
	var r := rig()
	r.play_move(&"palm_jab", 0.0); r.tick(0.0)
	quietly(func() -> void: r.play_move(&"no_such_clip", 0.0))
	var slot_a := (r.tree.tree_root as AnimationNodeBlendTree).get_node(&"move_a") as AnimationNodeAnimation
	var slot_b := (r.tree.tree_root as AnimationNodeBlendTree).get_node(&"move_b") as AnimationNodeAnimation
	assert_eq(slot_a.animation, &"palm_jab")
	assert_eq(slot_b.animation, &"idle", "the other slot was not taken")
	quietly(func() -> void: r.set_hitbox_active(&"no_such_hitbox", true))
	assert_eq(r.active_hitboxes(), [])


func test_marks_node_takes_every_mark_kind() -> void:
	var r := rig()
	var sink := r.get_node("Marks")
	assert_true(sink is MarkSink)
	for kind in Marks.KINDS:
		assert_true(sink.has_method(kind), kind)
		sink.call(kind, {})


# Starts `clip` as a move.
func _play(r: Rig, clip: StringName, blend_in: float) -> void:
	r.play_move(clip, blend_in)
	_move_time = 0.0


# One physics tick of the move: its time moves on by DT and the rig is ticked.
func _tick(r: Rig) -> void:
	_move_time += 1.0 / 60
	r.set_move_time(_move_time)
	r.tick(1.0 / 60)


# The jab, two ticks, and the cross, one tick: the cross is fading in over the jab.
func _jab_then_cross(r: Rig, blend_in: float) -> void:
	_play(r, &"palm_jab", blend_in)
	_tick(r); _tick(r)
	_play(r, &"palm_cross", blend_in)
	_tick(r)


# The first bone that is not where it is on `other`, to a millimetre, in the pose shown (`shown`) or in the clips'
# pose, without the modifiers; "" if there is none, else a line saying which and how far.
func _worst_difference(r: Rig, other: Rig, shown: bool) -> String:
	for b in r.skeleton.get_bone_count():
		var bone := StringName(r.skeleton.get_bone_name(b))
		var here := r.bone_global(bone) if shown else r.animated_pose(bone).origin
		var there := other.bone_global(bone) if shown else other.animated_pose(bone).origin
		if here.distance_to(there) > 0.001:
			return "%s is %.4f m from where it is on the other rig" % [bone, here.distance_to(there)]
	return ""


# Where every bone is in the pose the last tick showed: bone name -> world position.
func _positions(r: Rig) -> Dictionary:
	var out := {}
	for b in r.skeleton.get_bone_count():
		var bone := StringName(r.skeleton.get_bone_name(b))
		out[bone] = r.bone_global(bone)
	return out


# The worst bone for a pose that jumps: the one whose move over the last tick (`before` to `after`) is most
# beyond 1.5 times its move over the tick before (`earlier` to `before`), and 2 mm more for a bone that was
# still. "" when there is none; else a line saying which bone and how far it went.
func _worst_jump(earlier: Dictionary, before: Dictionary, after: Dictionary) -> String:
	var worst := ""
	var excess := 0.0
	for bone: StringName in earlier:
		var last := (before[bone] as Vector3).distance_to(after[bone])
		var prior := (earlier[bone] as Vector3).distance_to(before[bone])
		if last - 1.5 * prior - 0.002 > excess:
			excess = last - 1.5 * prior - 0.002
			worst = "%s moved %.3f m over the cancel tick and %.3f m over the tick before" % [bone, last, prior]
	return worst


# The angle between two rotations. Quaternion.angle_to goes through acos, which turns the length error
# of a sampled (not quite unit) key into milliradians; this does not.
func _angle(a: Quaternion, b: Quaternion) -> float:
	var d := a.normalized().inverse() * b.normalized()
	return 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w))


# The collision_layer bit of the 3D physics layer called `layer_name` in project.godot.
func _layer_bit(layer_name: String) -> int:
	var bit := Layers.bit(layer_name)
	if bit == 0:
		fail("no physics layer called %s" % layer_name)
	return bit
