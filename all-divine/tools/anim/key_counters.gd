class_name CounterKeyer
extends SceneTree
## Keys the layers of the four counters and clear-outs (assets/anim/layers/{counter_hook,counter_rise,clear_backpalm,clear_wave}.json),
## which make the pack clips they are cut from move the way the fight needs:
##
##   tools/godot.sh -s res://tools/anim/key_counters.gd            writes the four layer files
##   tools/godot.sh -s res://tools/anim/key_counters.gd -- --report  writes nothing; prints what each clip does
##   tools/godot.sh -s res://tools/anim/key_counters.gd -- --check   exits 1 if a file is not what the table makes (within a rounding step)
##   ... -- --only=counter_hook,clear_wave                         (with either) only those clips
##
## Then rebuild the library (tools/anim/build_library.gd) to lay them over. It reads each clip from the library, takes the layer
## now on it off again (the committed JSON), and works from that bare clip, so running it twice writes the same files.
##
## What a layer does, per clip (SPECS):
##   start    the clip begins as the guard stance and becomes its own pose over its first `ease` frames (a smoothstep: every bone but the
##            legs and the hips turn toward the guard stance's by the share that is left, and the hips go to where it has them). The rig
##            blends a move in over 0.05 s, and a blend of two poses is not planted where each end is: legs bent for a crouch at a third of
##            the way do not put the foot where a third of the hip's drop does. A start that is already the guard stance blends into
##            nothing (the jab is one), and a counter out of a sway, a duck or rest has nothing to drag.
##   legs     for the first `hold` frames each foot is held where the guard stance has it along the ground, and eases to where the
##            clip has it by frame `hold` (a smoothstep), its height always the clip's own, the legs solved two-bone from the hip. A counter
##            starts out of a sway, a duck, the guard stance or rest, where the feet are planted in the guard stance's places;
##            the pack clips begin in their own wide stances, and the blend into them dragged the planted feet 0.14 to 0.34 m
##            in a frame. A foot that steps lifts before it travels.
##   arms     `guard`: the arm's bones ease toward the guard stance's (by the weights given: frame, 0 to 1), so a hand is not
##            left up in the air after the blow and the off hand stays where a boxer keeps it. `path`: the hand goes through
##            the points given (frame, then x toward his left, y and z ahead, metres) by two-bone IK from the shoulder,
##            at the weights given, so the back palm's arm sweeps across and the wave's palm goes to the floor. The points are
##            offsets from the shoulder as the clip has it that frame (the clip twists the body through them), except `floor`:
##            the y is then a height above the floor.
## The layers are Euler degrees (YXZ) per frame, laid after the clip's own rotation (ClipBuilder.apply_layer).

# By path rather than by class name, so the tool also runs before the project has been imported.
const Builder := preload("res://tools/anim/clip_builder.gd")
const RIG := "res://actors/abarax/abarax_rig.tscn"
const LIBRARY := "res://assets/anim/abarax/library.tres"
const LAYERS := "res://assets/anim/layers/"
const GUARD_CLIP := &"guard_hold"

## The bones eased from the guard stance into the clip's pose over the clip's first `ease` frames (SPECS): the whole body but the legs,
## which `hold` solves.
const EASED: Array[String] = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r", "upperarm_l",
		"lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"]
const LEGS: Array[String] = ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
const ARMS_L: Array[String] = ["upperarm_l", "lowerarm_l", "hand_l"]
const ARMS_R: Array[String] = ["upperarm_r", "lowerarm_r", "hand_r"]

## Per clip: `lean` ([[frame, degrees]...]: the spine pitched forward over the hips by that much, split between spine_02 and spine_03: the
## rising palm starts bent over, its fist at the hip), `ease` (the frames over which it starts as the guard stance and becomes its own pose), `hold` (see legs), `pelvis` ([[frame, x left, y up, z ahead]...] metres added to where the clip has the
## hips, as ClipBuilder.PELVIS_MOVE does: the wave sinks to reach the floor), and its arms: {side: {guard: [[frame, weight]...], path: [[frame, x, y, z]...],
## path_weight: [[frame, weight]...]}}. Weights are linear between the points, then eased.
const SPECS := {
	&"counter_hook": {
		"ease": 4,
		"hold": 32,
		"l": {"guard": [[0, 1.0], [33, 1.0]]},
		"r": {"guard": [[0, 0.0], [10, 0.0], [16, 1.0], [33, 1.0]]},
	},
	&"counter_rise": {
		"lean": [[0, 0.0], [3, -34.0], [8, -8.0], [12, 0.0]],
		"ease": 7,
		"hold": 32,
		"l": {"guard": [[0, 1.0], [36, 1.0]]},
		"r": {
			# up from below: low in front of the hips as the body is still down, through the blow to above the shoulder, and home
			"path": [[2, 0.12, -0.48, 0.02], [5, 0.04, -0.2, 0.4], [8, 0.03, 0.02, 0.42], [10, 0.03, 0.17, 0.3], [14, 0.04, 0.05, 0.2]],
			"path_weight": [[0, 0.0], [2, 1.0], [14, 1.0], [18, 0.0]],
			"guard": [[0, 0.0], [13, 0.0], [20, 1.0], [36, 1.0]],
		},
	},
	&"clear_backpalm": {
		"ease": 7,
		"hold": 32,
		"l": {"guard": [[0, 1.0], [44, 1.0]]},
		"r": {
			"path": [[4, -0.37, -0.15, -0.13], [8, -0.39, -0.15, 0.03], [12, -0.37, -0.15, 0.13], [14, -0.07, -0.15, 0.38], [16, 0.30, -0.15, 0.25], [20, 0.38, -0.15, 0.07], [24, 0.39, -0.15, 0.00]],
			"path_weight": [[0, 0.0], [4, 1.0], [24, 1.0], [28, 0.0]],
			"guard": [[0, 0.0], [22, 0.0], [30, 1.0], [44, 1.0]],
		},
	},
	&"clear_wave": {
		"ease": 12,
		"hold": 32,
		"pelvis": [[0, 0.0, 0.0, 0.0], [4, 0.0, -0.03, 0.01], [12, 0.0, -0.34, 0.18], [20, 0.0, -0.34, 0.18], [30, 0.0, -0.12, 0.05], [38, 0.0, 0.0, 0.0]],
		"l": {"guard": [[0, 1.0], [48, 1.0]]},
		"r": {
			"path": [[8, 0.1, 0.8, 0.1], [12, 0.15, 0.3, 0.3], [14, 0.0, 0.18, 0.25], [16, -0.2, 0.18, 0.2], [18, -0.28, 0.18, 0.0], [20, -0.25, 0.2, -0.15], [24, -0.1, 0.25, -0.25]],
			"floor": true,
			"path_weight": [[0, 0.0], [8, 0.0], [12, 1.0], [24, 1.0], [32, 0.0]],
			"guard": [[0, 0.0], [24, 0.0], [36, 1.0], [48, 1.0]],
		},
	},
}


func _initialize() -> void:
	var only := PackedStringArray()
	var report := false
	var check := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--report":
			report = true
		elif arg == "--check":
			check = true
		elif arg == "--debug":
			pass  # lists the frames a hand misses its path on
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		else:
			printerr("key_counters.gd: unknown argument '%s'" % arg)
			quit(2)
			return
	if not root.is_inside_tree():
		await process_frame
	var made := generate(only)
	for line: String in made["report"]:
		print(line)
	var wrong := 0
	for clip: String in made["files"]:
		var path := LAYERS + clip + ".json"
		if check:
			if not FileAccess.file_exists(path):
				printerr("key_counters.gd: %s is missing" % path)
				wrong += 1
				continue
			var found := differences(made["files"][clip], FileAccess.get_file_as_string(path))
			if not found.is_empty():
				printerr("key_counters.gd: %s is not what the table makes (within a rounding step): %s" % [path, found[0]])
				wrong += 1
		elif not report:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(made["files"][clip])
			file.close()
	quit(1 if wrong > 0 else 0)


## What is different between a layer file's text `committed` and the text `made` of the table, one line each; the same comparison
## as the sways' (EvadeKeyer.differences): empty when the same bones and frames and every value within 1.5 rounding steps.
static func differences(made: String, committed: String) -> PackedStringArray:
	return preload("res://tools/anim/key_evades.gd").differences(made, committed)


## Every clip's layer: {"files": {clip name: the text of its layer file}, "report": [one line per clip]}, for the clips named in `only`
## (all of them if it is empty). Works from the library as built with the layers now committed (it takes them off first), so it
## makes the same files whether or not they are laid on.
static func generate(only := PackedStringArray()) -> Dictionary:
	var solver := _Solver.new()
	var library := load(LIBRARY) as AnimationLibrary
	var files := {}
	var report := PackedStringArray()
	for clip: StringName in SPECS:
		if not only.is_empty() and not only.has(String(clip)):
			continue
		var made := solver.make(clip, library.get_animation(clip), SPECS[clip])
		files[String(clip)] = made["text"]
		report.append(made["report"])
	return {"files": files, "report": report}


## Solves one clip at a time on Abarax's skeleton.
class _Solver:
	extends RefCounted

	var _rig: Node
	var _skeleton: Skeleton3D
	var _guard := {}    # bone -> its local rotation in the guard stance
	var _guard_g := {}  # bone -> Transform3D of the guard stance, in the skeleton's space
	var _ref := {}      # bone -> Transform3D of the clip's own pose at the frame being solved

	func _init() -> void:
		_rig = (load(RIG) as PackedScene).instantiate()
		(Engine.get_main_loop() as SceneTree).root.add_child(_rig)
		_skeleton = _rig.find_children("*", "Skeleton3D", true, false)[0]
		var anim := (load(LIBRARY) as AnimationLibrary).get_animation(GUARD_CLIP)
		_skeleton.reset_bone_poses()
		_pose_from(anim, 0.0, {})
		for bone in _skeleton.get_bone_count():
			var name := _skeleton.get_bone_name(bone)
			_guard[name] = _skeleton.get_bone_pose_rotation(bone)
			_guard_g[name] = _skeleton.get_bone_global_pose(bone)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _rig != null:
			_rig.free()

	# Poses the skeleton from `anim` at `time` (rotation tracks, and the pelvis's position; the root's travel is left out), with
	# the layer rotations `taken_off` (bone -> [keys, frame]) taken back off, so the pose is the clip's own without a layer.
	func _pose_from(anim: Animation, time: float, taken_off: Dictionary) -> void:
		for i in anim.get_track_count():
			var bone := _skeleton.find_bone(String(anim.track_get_path(i).get_concatenated_subnames()))
			if bone < 0:
				continue
			var name := _skeleton.get_bone_name(bone)
			match anim.track_get_type(i):
				Animation.TYPE_ROTATION_3D:
					var rotation := anim.rotation_track_interpolate(i, time)
					if taken_off.has(name):
						rotation = rotation * Builder._layer_rotation(taken_off[name], time * Builder.KEY_RATE).inverse()
					_skeleton.set_bone_pose_rotation(bone, rotation)
				Animation.TYPE_POSITION_3D:
					if name == "pelvis":
						var at := anim.position_track_interpolate(i, time)
						if taken_off.has("@pelvis_move"):
							at -= Builder.ROOT_STANDS.inverse() * Builder._layer_move(taken_off["@pelvis_move"], time * Builder.KEY_RATE)
						_skeleton.set_bone_pose_position(bone, at)

	func make(clip: StringName, anim: Animation, spec: Dictionary) -> Dictionary:
		var frames := roundi(anim.length * 60.0)
		var old := {}
		var path := LAYERS + String(clip) + ".json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				old = parsed
		var emit: Array[String] = LEGS.duplicate()
		emit.append_array(EASED)
		var keys := {}
		for bone in emit:
			keys[bone] = []
		var worst_foot := 0.0
		var worst_hand := 0.0
		var moves := []
		var hold: int = spec["hold"]
		for frame in frames + 1:
			_skeleton.reset_bone_poses()
			_pose_from(anim, minf(frame / 60.0, anim.length), old)
			_ref.clear()
			var base := {}
			for bone in _skeleton.get_bone_count():
				var name := _skeleton.get_bone_name(bone)
				_ref[name] = _skeleton.get_bone_global_pose(bone)
				base[name] = _skeleton.get_bone_pose_rotation(bone)
			var shift := _along(spec["pelvis"], frame) if spec.has("pelvis") else Vector3.ZERO
			var eased: int = spec.get("ease", 0)
			var left_over := 0.0  # how much of the guard stance is left in the pose on this frame
			if frame < eased:
				var left := 1.0 - smoothstep(0.0, 1.0, float(frame) / eased)
				left_over = left
				for name in EASED:
					var bone := _skeleton.find_bone(name)
					_skeleton.set_bone_pose_rotation(bone, (base[name] as Quaternion).slerp(_guard[name], left))
				shift += ((_guard_g["pelvis"] as Transform3D).origin - (_ref["pelvis"] as Transform3D).origin) * left
			if spec.has("lean"):
				var lean := _along_scalar(spec["lean"], frame)
				for name in ["spine_02", "spine_03"]:
					_pitch(name, lean * 0.5)
			if shift != Vector3.ZERO:
				var pelvis := _skeleton.find_bone("pelvis")
				_skeleton.set_bone_pose_position(pelvis, _skeleton.get_bone_pose_position(pelvis) + Builder.ROOT_STANDS.inverse() * shift)
				moves.append([frame, snappedf(shift.x, 0.0001), snappedf(shift.y, 0.0001), snappedf(shift.z, 0.0001)])
			else:
				moves.append([frame, 0.0, 0.0, 0.0])
			if frame < hold:
				var s := smoothstep(0.0, 1.0, float(frame) / hold)
				for side in ["l", "r"]:
					var foot: String = "foot_" + side
					var clip_foot: Vector3 = (_ref[foot] as Transform3D).origin
					var guard_foot: Vector3 = (_guard_g[foot] as Transform3D).origin
					# the foot stays where the guard stance has it along the ground and rises or falls as the clip has it: a foot that
					# steps lifts first, and a planted one does not slide; it is the guard stance's height too while the pose is eased in
					var target := guard_foot.lerp(clip_foot, s)
					target.y = lerpf(guard_foot.y, clip_foot.y, 1.0 - left_over)
					worst_foot = maxf(worst_foot, _solve("thigh_" + side, "calf_" + side, foot, target, true))
			for side in ["l", "r"]:
				if not spec.has(side):
					continue
				var arm: Dictionary = spec[side]
				var names: Array[String] = ARMS_L if side == "l" else ARMS_R
				if arm.has("path"):
					var w := _eased(arm["path_weight"], frame)
					if w > 0.0:
						var hand_now: Vector3 = _g("hand_" + side).origin
						var shoulder: Vector3 = _g(names[0]).origin
						var target := shoulder + _along(arm["path"], frame)
						if arm.get("floor", false):
							target.y = _along(arm["path"], frame).y
						var missed := _solve(names[0], names[1], names[2], hand_now.lerp(target, w), false)
						if missed > 0.04 and OS.get_cmdline_user_args().has("--debug"):
							print("  %s f%d misses by %.2f: wants %s, shoulder at %s" % [clip, frame, missed, hand_now.lerp(target, w), (_ref[names[0]] as Transform3D).origin])
						worst_hand = maxf(worst_hand, missed)
				if arm.has("guard"):
					var g := _eased(arm["guard"], frame)
					if g > 0.0:
						for name in names:
							var bone := _skeleton.find_bone(name)
							var now := _skeleton.get_bone_pose_rotation(bone)
							_skeleton.set_bone_pose_rotation(bone, now.slerp(_guard[name], g))
			for bone in emit:
				var turn := Basis(base[bone] as Quaternion).inverse() * Basis(_skeleton.get_bone_pose_rotation(_skeleton.find_bone(bone)))
				var v := turn.get_euler(EULER_ORDER_YXZ) * (180.0 / PI)
				(keys[bone] as Array).append([frame, snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)])
		var out := {}
		out["@pelvis_move"] = moves
		for bone in emit:
			for key: Array in keys[bone]:
				if absf(key[1]) > 0.002 or absf(key[2]) > 0.002 or absf(key[3]) > 0.002:
					out[bone] = keys[bone]
					break
		var shoulder := (_g("upperarm_r").origin)
		return {"text": _text(out), "report": "%-15s feet at most %.4f m off their hold, hands at most %.4f m off their path (his right shoulder ends at %s, an arm reaches %.2f m)" % [clip, worst_foot, worst_hand, shoulder, ((_ref["lowerarm_r"] as Transform3D).origin - (_ref["upperarm_r"] as Transform3D).origin).length() + ((_ref["hand_r"] as Transform3D).origin - (_ref["lowerarm_r"] as Transform3D).origin).length()]}

	# The weight at `frame` of points [[frame, weight]...]: linear between them, eased, and the end values outside.
	func _eased(points: Array, frame: float) -> float:
		if frame <= points[0][0]:
			return points[0][1]
		for i in points.size() - 1:
			if frame <= points[i + 1][0]:
				var t: float = (frame - points[i][0]) / float(points[i + 1][0] - points[i][0])
				return lerpf(points[i][1], points[i + 1][1], smoothstep(0.0, 1.0, t))
		return points[points.size() - 1][1]

	# The value of [[frame, value]...] at `frame`: linear between them, the end values outside.
	func _along_scalar(points: Array, frame: float) -> float:
		if frame <= points[0][0]:
			return points[0][1]
		for i in points.size() - 1:
			if frame <= points[i + 1][0]:
				return lerpf(points[i][1], points[i + 1][1], (frame - points[i][0]) / float(points[i + 1][0] - points[i][0]))
		return points[points.size() - 1][1]

	# Pitches `bone` forward by `degrees` about its own joint, in the body's own directions, its children with it.
	func _pitch(name: String, degrees: float) -> void:
		var index := _skeleton.find_bone(name)
		var parent := _parent_basis(name)
		var local := Basis(_skeleton.get_bone_pose_rotation(index))
		_skeleton.set_bone_pose_rotation(index, (parent.inverse() * Basis(Vector3.RIGHT, deg_to_rad(degrees)) * parent * local).get_rotation_quaternion())

	# The point of [[frame, x, y, z]...] at `frame`: linear between them, the first and last outside.
	func _along(points: Array, frame: float) -> Vector3:
		if frame <= points[0][0]:
			return Vector3(points[0][1], points[0][2], points[0][3])
		for i in points.size() - 1:
			if frame <= points[i + 1][0]:
				var t: float = (frame - points[i][0]) / float(points[i + 1][0] - points[i][0])
				return Vector3(points[i][1], points[i][2], points[i][3]).lerp(Vector3(points[i + 1][1], points[i + 1][2], points[i + 1][3]), t)
		var last: Array = points[points.size() - 1]
		return Vector3(last[1], last[2], last[3])

	func _g(name: String) -> Transform3D:
		return _skeleton.get_bone_global_pose(_skeleton.find_bone(name))

	func _parent_basis(name: String) -> Basis:
		return _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(_skeleton.find_bone(name))).basis

	func _set_global_basis(bone: String, basis: Basis) -> void:
		_skeleton.set_bone_pose_rotation(_skeleton.find_bone(bone), (_parent_basis(bone).inverse() * basis).get_rotation_quaternion())

	func _arc(from: Vector3, to: Vector3) -> Basis:
		var axis := from.normalized().cross(to.normalized())
		if axis.length() < 1e-7:
			return Basis.IDENTITY
		return Basis(axis.normalized(), from.normalized().angle_to(to.normalized()))

	# Bends the two-bone chain `top`, `mid`, `end` (a leg or an arm) from its root to put its end at `target`, in the plane the clip's
	# own pose bends it in; returns how far the end is off (when the chain cannot reach). A leg's calf is twisted to the bend plane the
	# rig's foot IK expects (test_foot_ik).
	func _solve(top: String, mid: String, end: String, target: Vector3, leg: bool) -> float:
		var root_at := _g(top).origin
		var l1 := ((_ref[mid] as Transform3D).origin - (_ref[top] as Transform3D).origin).length()
		var l2 := ((_ref[end] as Transform3D).origin - (_ref[mid] as Transform3D).origin).length()
		var axis := target - root_at
		var d := minf(axis.length(), l1 + l2 - 1e-4)
		var u := axis.normalized()
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var pole: Vector3 = (_ref[mid] as Transform3D).origin - (_ref[top] as Transform3D).origin
		pole -= u * pole.dot(u)
		if pole.length() < 1e-5:
			pole = Vector3.FORWARD
		var knee := root_at + u * a + pole.normalized() * h
		_set_global_basis(top, _arc(_g(mid).origin - root_at, knee - root_at) * _g(top).basis)
		_set_global_basis(mid, _arc(_g(end).origin - _g(mid).origin, target - _g(mid).origin) * _g(mid).basis)
		if leg:
			var base_axis := ((_ref[end] as Transform3D).origin - (_ref[mid] as Transform3D).origin).normalized()
			var base_forward: Vector3 = -(_ref[mid] as Transform3D).basis.z
			base_forward = (base_forward - base_axis * base_forward.dot(base_axis)).normalized()
			var base_hip: Vector3 = (_ref[top] as Transform3D).origin - (_ref[mid] as Transform3D).origin
			var base_bend := (base_hip - base_axis * base_hip.dot(base_axis)).normalized()
			var want := base_bend.signed_angle_to(base_forward, base_axis)
			var now_axis := (target - _g(mid).origin).normalized()
			var now_forward: Vector3 = -_g(mid).basis.z
			now_forward = (now_forward - now_axis * now_forward.dot(now_axis)).normalized()
			var now_hip := root_at - _g(mid).origin
			var now_bend := (now_hip - now_axis * now_hip.dot(now_axis)).normalized()
			_set_global_basis(mid, Basis(now_axis, want - now_bend.signed_angle_to(now_forward, now_axis)) * _g(mid).basis)
		_set_global_basis(end, (_ref[end] as Transform3D).basis)
		return (_g(end).origin - target).length()

	func _text(layer: Dictionary) -> String:
		var lines := PackedStringArray()
		for bone: String in layer:
			var keys := PackedStringArray()
			for key: Array in layer[bone]:
				keys.append("[%s]" % ", ".join(PackedStringArray(key.map(func(x: Variant) -> String: return str(x)))))
			lines.append("\t%s: [%s]" % [JSON.stringify(bone), ", ".join(keys)])
		return "{\n%s\n}\n" % ",\n".join(lines)
