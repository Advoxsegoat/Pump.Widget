class_name HaymakerKeyer
extends SceneTree
## Keys the layer of the heavy Knuckle's haymaker (assets/anim/layers/heavy_haymaker.json), which makes the hook it is cut from wind
## up like a haymaker: the body turned away and loaded on its back foot, the fist drawn back past his head, the lead shoulder down, held,
## and then unwound through the blow. The same tool and the same kind of table as key_counters.gd:
##
##   tools/godot.sh -s res://tools/anim/key_haymaker.gd            writes the layer file
##   tools/godot.sh -s res://tools/anim/key_haymaker.gd -- --report  writes nothing; prints the wind-up beside the tier I hook's
##   tools/godot.sh -s res://tools/anim/key_haymaker.gd -- --check   exits 1 if the file is not what the table makes (within a rounding step)
##
## Then rebuild the library (tools/anim/build_library.gd) to lay it over. Like the counters' it reads the clip from the library, takes
## the layer now on it off again (the committed JSON) and works from that bare clip, so running it twice writes the same file.
##
## What the layer does (SPEC), over frames START to END (the glint to the blow; every mark stays where it is, and the layer is nothing
## at its first and last frame, so the blow is the clip's own, at its own reach, on its own frame):
##   twist     how far (degrees) the body is turned away from the target, about the vertical: the pelvis, spine_02 and spine_03 take
##             their SHARES of it and the neck and head turn back, so he keeps his eyes on what he is going to hit
##   lean      the spine pitched back (degrees, split between spine_02 and spine_03) over the hips
##   shift     where the hips go (metres, toward his left / up / ahead): the weight onto the back foot
##   drop      the lead (left) shoulder's drop (degrees of roll of the clavicle)
##   fist      the striking (right) hand's place relative to its shoulder (x toward his left, y up, z ahead, metres), by two-bone IK
##             from the shoulder, at the weight given: drawn back past the line of the head
## Each is a curve of [frame, value] points, eased (smoothstep) between points. The feet stay where the clip has them (the legs are
## solved two-bone from the moved hips), so he does not skate. The layer is Euler degrees (YXZ) per frame, laid after the clip's own
## rotation (ClipBuilder.apply_layer), with the hips' shift as "@pelvis_move".

# By path rather than by class name, so the tool also runs before the project has been imported.
const Counters := preload("res://tools/anim/key_counters.gd")
const Builder := preload("res://tools/anim/clip_builder.gd")
const LIBRARY := "res://assets/anim/abarax/library.tres"
const LAYERS := "res://assets/anim/layers/"
const CLIP := &"heavy_haymaker"
## The tier I hook the wind-up is held against, and where each blow is (the hook's hitbox on f40, the haymaker's on f42).
const HOOK := &"knuckle_hook"
const HOOK_BLOW := 40
const BLOW := 42
## The layer's first and last frames: the glint, and the blow.
const START := 4
const END := 42

## How the twist is shared out (they add to 1), and how much of it the neck and head turn back (each a share of the whole twist).
const SHARES := {"pelvis": 0.25, "spine_02": 0.4, "spine_03": 0.35}
const LOOK_BACK := {"neck_01": 0.35, "Head": 0.4}
const SPEC := {
	"twist": [[4, 0.0], [9, 40.0], [16, 42.0], [24, 38.0], [31, 32.0], [36, 26.0], [42, 0.0]],
	"lean": [[4, 0.0], [14, 6.0], [36, 8.0], [42, 0.0]],
	"shift": [[4, 0.0, 0.0, 0.0], [14, -0.07, -0.05, -0.16], [36, -0.08, -0.06, -0.18], [42, 0.0, 0.0, 0.0]],
	"drop": [[4, 0.0], [14, -10.0], [36, -12.0], [42, 0.0]],
	"fist": [[4, -0.05, 0.0, 0.0], [13, -0.1, 0.05, -0.43], [36, -0.1, 0.06, -0.44], [42, -0.05, 0.0, 0.0]],
	"fist_weight": [[4, 0.0], [13, 1.0], [32, 1.0], [40, 0.0]],
}
const LEGS: Array[String] = ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
const EMIT: Array[String] = ["pelvis", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_r", "lowerarm_r", "hand_r"]


func _initialize() -> void:
	var report := false
	var check := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--report":
			report = true
		elif arg == "--check":
			check = true
		else:
			printerr("key_haymaker.gd: unknown argument '%s'" % arg)
			quit(2)
			return
	if not root.is_inside_tree():
		await process_frame
	var made := generate()
	for line: String in made["report"]:
		print(line)
	var path := LAYERS + String(CLIP) + ".json"
	var wrong := 0
	if check:
		if not FileAccess.file_exists(path):
			printerr("key_haymaker.gd: %s is missing" % path)
			wrong += 1
		else:
			var found := differences(made["text"], FileAccess.get_file_as_string(path))
			if not found.is_empty():
				printerr("key_haymaker.gd: %s is not what the table makes (within a rounding step): %s" % [path, found[0]])
				wrong += 1
	elif not report:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(made["text"])
		file.close()
	quit(1 if wrong > 0 else 0)


## What is different between the layer file's text `committed` and the text `made` of the table, one line each (as the sways' and counters').
static func differences(made: String, committed: String) -> PackedStringArray:
	return preload("res://tools/anim/key_evades.gd").differences(made, committed)


## The layer: {"text": the file's text, "report": [lines]}. Works from the library as built with the layer now committed (it takes it off
## first), so it makes the same file whether or not it is laid on.
static func generate() -> Dictionary:
	var solver := _Keyer.new()
	var library := load(LIBRARY) as AnimationLibrary
	return solver.make_layer(library.get_animation(CLIP), library.get_animation(HOOK))


## A body to measure poses on, for the tests: its `measured(anim, frame)` is what a pose measures (chest, fist_behind, back_share,
## lead_shoulder: see there), its `placed(anim, frame, bones)` where bones are. It stands in the tree until it is freed with its last
## reference.
static func measurer() -> RefCounted:
	return _Keyer.new()


## Where each of `bones` is (skeleton space, metres: the body at the origin facing +Z) in the pose of `anim` at `frame`, its layer on.
static func positions(anim: Animation, frame: int, bones: Array[String]) -> Dictionary:
	return _Keyer.new().placed(anim, frame, bones)


class _Keyer:
	extends Counters._Solver

	func placed(anim: Animation, frame: int, bones: Array[String]) -> Dictionary:
		_skeleton.reset_bone_poses()
		_pose_from(anim, minf(frame / 60.0, anim.length), {})
		var out := {}
		for bone in bones:
			out[bone] = _g(bone).origin
		return out

	# The layer for `anim` (the haymaker's bare clip, its old layer taken off) and the report beside `hook`.
	func make_layer(anim: Animation, hook: Animation) -> Dictionary:
		var frames := roundi(anim.length * 60.0)
		var old := {}
		var path := LAYERS + String(CLIP) + ".json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				old = parsed
		var keys := {}
		var emit: Array[String] = EMIT.duplicate()
		emit.append_array(LEGS)
		for bone in emit:
			keys[bone] = []
		var moves := []
		var worst_foot := 0.0
		var worst_hand := 0.0
		for frame in range(START, END + 1):
			_skeleton.reset_bone_poses()
			_pose_from(anim, minf(frame / 60.0, anim.length), old)
			_ref.clear()
			var base := {}
			for bone in _skeleton.get_bone_count():
				var name := _skeleton.get_bone_name(bone)
				_ref[name] = _skeleton.get_bone_global_pose(bone)
				base[name] = _skeleton.get_bone_pose_rotation(bone)
			var twist := _curve(SPEC["twist"], frame)
			var lean := _curve(SPEC["lean"], frame)
			var drop := _curve(SPEC["drop"], frame)
			var shift := _along_eased(SPEC["shift"], frame)
			var active := absf(twist) + absf(lean) + absf(drop) + shift.length() > 1e-6
			if active:
				for name: String in SHARES:
					_turn(name, Vector3.UP, -twist * SHARES[name])
				for name: String in LOOK_BACK:
					_turn(name, Vector3.UP, twist * LOOK_BACK[name])
				for name in ["spine_02", "spine_03"]:
					_pitch(name, -lean * 0.5)
				_turn("clavicle_l", Vector3.BACK, drop)
				if shift != Vector3.ZERO:
					var pelvis := _skeleton.find_bone("pelvis")
					_skeleton.set_bone_pose_position(pelvis, _skeleton.get_bone_pose_position(pelvis) + Builder.ROOT_STANDS.inverse() * shift)
			moves.append([frame, snappedf(shift.x, 0.0001), snappedf(shift.y, 0.0001), snappedf(shift.z, 0.0001)])
			if active:
				for side in ["l", "r"]:
					var foot: String = "foot_" + side
					worst_foot = maxf(worst_foot, _solve("thigh_" + side, "calf_" + side, foot, (_ref[foot] as Transform3D).origin, true))
				var weight := _curve(SPEC["fist_weight"], frame)
				if weight > 0.0:
					var hand_now: Vector3 = _g("hand_r").origin
					var target := _g("upperarm_r").origin + _along(SPEC["fist"], frame)
					worst_hand = maxf(worst_hand, _bend_to("upperarm_r", "lowerarm_r", "hand_r", hand_now.lerp(target, weight)))
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
		var lines := PackedStringArray()
		lines.append("%s: feet at most %.4f m off their places, the fist at most %.4f m off its path" % [CLIP, worst_foot, worst_hand])
		lines.append_array(_comparison(anim, hook, old))
		return {"text": _text(out), "report": lines}

	# Bends the arm `top`, `mid`, `end` to put its end at `target`, the elbow staying on the side of the line it is on now (the arm as it
	# stands after the turns, so a target at the hand's own place leaves the arm exactly as it is); returns how far the end is off.
	func _bend_to(top: String, mid: String, end: String, target: Vector3) -> float:
		var root_at := _g(top).origin
		var l1 := (_g(mid).origin - root_at).length()
		var l2 := (_g(end).origin - _g(mid).origin).length()
		var axis := target - root_at
		var d := clampf(axis.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
		var u := axis.normalized()
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var pole := _g(mid).origin - root_at
		pole -= u * pole.dot(u)
		if pole.length() < 1e-5:
			pole = Vector3.BACK
		var elbow := root_at + u * a + pole.normalized() * h
		var end_basis := _g(end).basis
		_set_global_basis(top, _arc(_g(mid).origin - root_at, elbow - root_at) * _g(top).basis)
		_set_global_basis(mid, _arc(_g(end).origin - _g(mid).origin, target - _g(mid).origin) * _g(mid).basis)
		_set_global_basis(end, end_basis)
		return (_g(end).origin - target).length()

	# Turns `bone` by `degrees` about `axis` (the skeleton's directions, through the bone's own joint), its children with it.
	func _turn(name: String, axis: Vector3, degrees: float) -> void:
		var index := _skeleton.find_bone(name)
		var parent := _parent_basis(name)
		var local := Basis(_skeleton.get_bone_pose_rotation(index))
		_skeleton.set_bone_pose_rotation(index, (parent.inverse() * Basis(axis, deg_to_rad(degrees)) * parent * local).get_rotation_quaternion())

	# The curve of [[frame, value]...] at `frame`, eased between points.
	func _curve(points: Array, frame: float) -> float:
		return _eased(points, frame)

	# The point of [[frame, x, y, z]...] at `frame`, eased between points.
	func _along_eased(points: Array, frame: float) -> Vector3:
		if frame <= points[0][0]:
			return Vector3(points[0][1], points[0][2], points[0][3])
		for i in points.size() - 1:
			if frame <= points[i + 1][0]:
				var t := smoothstep(0.0, 1.0, (frame - points[i][0]) / float(points[i + 1][0] - points[i][0]))
				return Vector3(points[i][1], points[i][2], points[i][3]).lerp(Vector3(points[i + 1][1], points[i + 1][2], points[i + 1][3]), t)
		var last: Array = points[points.size() - 1]
		return Vector3(last[1], last[2], last[3])

	# What the pose of `anim` at `frame` measures (the clip as it stands, its layer on): chest (degrees the shoulders are turned away from the
	# target: the right shoulder going back is positive), fist_behind (metres the striking hand is behind the head), back_share (0 over the
	# back foot, 1 over the front one: where the hips stand between the feet), lead_shoulder (metres up of the lead shoulder).
	func measured(anim: Animation, frame: int) -> Dictionary:
		_skeleton.reset_bone_poses()
		_pose_from(anim, minf(frame / 60.0, anim.length), {})
		var line := _g("clavicle_r").origin - _g("clavicle_l").origin
		var feet := [_g("foot_l").origin, _g("foot_r").origin]
		var back: Vector3 = feet[0] if (feet[0] as Vector3).z < (feet[1] as Vector3).z else feet[1]
		var front: Vector3 = feet[1] if (feet[0] as Vector3).z < (feet[1] as Vector3).z else feet[0]
		var span := maxf(front.z - back.z, 0.05)
		return {
			"chest": rad_to_deg(atan2(-line.z, -line.x)),
			"fist_behind": _g("Head").origin.z - _g("hand_r").origin.z,
			"back_share": (_g("pelvis").origin.z - back.z) / span,
			"lead_shoulder": _g("clavicle_l").origin.y,
		}

	# The wind-up of the haymaker beside the hook's, at the same share of the way from the glint to the blow.
	func _comparison(anim: Animation, hook: Animation, old: Dictionary) -> PackedStringArray:
		var lines := PackedStringArray()
		lines.append("share  frame(hook)  chest turned away: heavy / hook   fist behind head (m)   hips between feet (0 back, 1 front)   lead shoulder (m)")
		for share in [0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]:
			var f := roundi(START + share * (BLOW - START))
			var g := roundi(START + share * (HOOK_BLOW - START))
			var a := measured(anim, f)
			var b := measured(hook, g)
			lines.append("%.2f   f%d (f%d)    %6.1f / %6.1f deg        %5.2f / %5.2f            %5.2f / %5.2f                    %5.3f / %5.3f" % [share, f, g,
					a["chest"], b["chest"], a["fist_behind"], b["fist_behind"], a["back_share"], b["back_share"], a["lead_shoulder"], b["lead_shoulder"]])
		return lines
