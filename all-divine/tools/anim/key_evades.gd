class_name EvadeKeyer
extends SceneTree
## Keys the layers of the sway, duck and dash-step clips (assets/anim/layers/{sway_*,duck_*,dash_step*}.json). A layer of
## fifteen bones of dense per-frame rotations cannot be keyed by hand, so each clip is written down here as a peak pose and
## a timing curve, and this tool works out the rest:
##
##   tools/godot.sh -s res://tools/anim/key_evades.gd                  writes every layer file
##   tools/godot.sh -s res://tools/anim/key_evades.gd -- --check       exits 1 if a file is not what the table makes (within a rounding step)
##   tools/godot.sh -s res://tools/anim/key_evades.gd -- --report      writes nothing; prints what each clip does (metres)
##   ... -- --only=sway_left_slip,duck_slip                           (with any of them) only those clips
##
## tests/anim/test_key_evades.gd holds the committed files to --check, so a changed table that was not written fails. The
## comparison is within a rounding step (see differences): the values are rounded as they are written, and one on the edge of a
## step can round the other way on another machine's floating point.
##
## How a clip is made. Every clip is UAL2's guard stance (guard_hold's first frame) held for its length (clips.cfg), and its
## layer says how Abarax leaves that stance and comes back to it. The table (PEAKS, TEMPOS, DASH) gives a clip's pose at its
## peak; CURVES says how far toward it the body is on each frame (a monotone cubic through the points, so nothing overshoots
## a peak; each curve's peak is a point of its own, falling after it, so the clip is at its furthest on that frame and not
## somewhere along a plateau, and always before its evade window closes). For each frame the pose is the peak scaled by that fraction:
##   move    where the hips go (metres, toward his left / up / ahead): the weight shift, the dip, the lunge
##   turns   how much each spine bone and the head turn, as (lean toward his left, pitch with the top forward, twist toward
##           his left) degrees, about the bone's own joint in the body's own directions
##   feet    (dashes) how far each foot reaches along the travel, and how high it lifts on the way
## The legs are then solved, two-bone IK from each hip to where its foot must be (the guard stance's place, or the stride's), so
## the feet need no keys; and each calf is twisted about its bone to the guard stance's bend plane, because the rig's foot IK
## places the knee toward a pole along the calf's -Z and would bend the leg another way otherwise (test_foot_ik).
## The result is written as the rotations that, laid over the guard stance (ClipBuilder.apply_layer), give that pose: bone
## entries in Euler degrees (YXZ), and the hips' travel as "@pelvis_move".
##
## The bones spine_01 and the fingers are not keyed: guard_hold has no rotation track for spine_01 to lay a layer on.

# By path rather than by class name, so the tool also runs before the project has been imported.
const Builder := preload("res://tools/anim/clip_builder.gd")
const RIG := "res://actors/abarax/abarax_rig.tscn"
const LIBRARY := "res://assets/anim/abarax/library.tres"
const LAYERS := "res://assets/anim/layers/"
const GUARD_CLIP := &"guard_hold"
## The bones a layer may turn, in the order they are written.
const EMIT: Array[String] = ["pelvis", "spine_02", "spine_03", "neck_01", "Head", "thigh_l", "calf_l", "foot_l", "thigh_r",
		"calf_r", "foot_r", "clavicle_l", "clavicle_r"]
## The bones `turns` may name, parent before child.
const CHAIN: Array[String] = ["pelvis", "spine_02", "spine_03", "neck_01", "Head"]

const LEFT := Vector3(1.0, 0.0, 0.0)
const AHEAD := Vector3(0.0, 0.0, 1.0)

## Frames of each tempo's clip and the timing of its leaning: [frame, how far toward the peak, 0 to 1]. One curve for the
## three kinds of clip in a tempo, so the three are the same shape.
const CURVES := {
	&"slip": [[0, 0.0], [2, 0.2], [5, 0.78], [8, 1.0], [12, 0.93], [17, 0.35], [22, 0.0]],
	&"quick": [[0, 0.0], [2, 0.38], [4, 0.92], [6, 1.0], [8, 0.96], [12, 0.3], [16, 0.0]],
	&"flurry": [[0, 0.0], [1.5, 0.45], [3, 0.95], [4, 1.0], [6, 0.9], [9, 0.28], [12, 0.0]],
}
const FRAMES := {&"slip": 22, &"quick": 16, &"flurry": 12}
## The duck's own timing and frames (it is held longer than its sway).
const DUCK_CURVES := {
	&"slip": [[0, 0.0], [3, 0.35], [7, 1.0], [14, 0.92], [20, 0.35], [26, 0.0]],
	&"quick": [[0, 0.0], [2, 0.4], [4, 0.95], [6, 1.0], [11, 0.93], [14, 0.35], [18, 0.0]],
	&"flurry": [[0, 0.0], [1.5, 0.45], [3, 0.95], [4, 1.0], [8, 0.93], [11, 0.3], [14, 0.0]],
}
const DUCK_FRAMES := {&"slip": 26, &"quick": 18, &"flurry": 14}
## How much of the Slip peak each tempo makes (uniformly: the same shape, smaller). The sways' head travel (0.33 m at Slip)
## and dip come to 0.26 m and 0.10 m at Quick and 0.22 m and 0.09 m at Flurry.
const SWAY_SIZE := {&"slip": 1.0, &"quick": 0.78, &"flurry": 0.66}
const DUCK_SIZE := {&"slip": 1.1, &"quick": 0.83, &"flurry": 0.8}

## The Slip sway toward his left, at its peak: the hips go over the left leg and sink, the spine bends over that leg and a
## little forward (into the slip, which also shows on a camera that looks along his left), the shoulders tilt with it, the
## head keeps more upright than the spine. The right sway is this mirrored.
const SWAY_LEFT := {
	"move": Vector3(0.17, -0.095, 0.03),
	"turns": {"pelvis": Vector3(5.0, 7.0, 4.0), "spine_02": Vector3(10.0, 9.0, -4.0), "spine_03": Vector3(9.0, 5.0, -3.0),
			"neck_01": Vector3(-8.0, 0.0, 0.0), "Head": Vector3(-10.0, 0.0, 0.0)},
}
## How far the hips sink in the Slip sway to his right (the stance, front foot his left, lets the head fall further that way,
## so the hips sink less to keep the dip in its band).
const RIGHT_SINK := 0.07
## The Slip pull back: the hips go back and sink, the spine folds away from the line and a little to the right (a slip as it
## pulls, which a camera along his line shows), the chin tucks (the head and neck pitch forward).
const SWAY_BACK := {
	"move": Vector3(-0.05, -0.105, -0.115),
	"turns": {"pelvis": Vector3(-2.0, -6.0, 0.0), "spine_02": Vector3(-5.0, -14.3, 0.0), "spine_03": Vector3(-4.0, -12.6, 0.0),
			"neck_01": Vector3(0.0, 10.0, 0.0), "Head": Vector3(0.0, 13.5, 0.0)},
}
## The Slip duck at its peak (the Slip is 1.1 times this): the hips drop and go back, the spine folds forward, the head
## comes up to look ahead.
const DUCK := {
	"move": Vector3(0.0, -0.27, -0.06),
	"turns": {"pelvis": Vector3(0.0, 8.0, 0.0), "spine_02": Vector3(0.0, 20.0, 0.0), "spine_03": Vector3(0.0, 8.0, 0.0),
			"neck_01": Vector3(0.0, -12.0, 0.0), "Head": Vector3(0.0, -14.0, 0.0)},
}

## The dash-steps: [frames, the timing of the lean, the timing of the stride]. The lean is a low lunge in the way of the
## travel; the stride (how far apart the feet are, 0 the guard stance, 1 the lunge) opens by frame 4, is held, and closes by
## frame 12; a foot lifts on the way out and on the way in.
const DASH_FRAMES := 18
const DASH_LEAN := [[0, 0.0], [2, 0.55], [4, 1.0], [10, 1.0], [14, 0.3], [18, 0.0]]
const DASH_STRIDE := [[0, 0.0], [4, 1.0], [7, 1.0], [12, 0.0], [18, 0.0]]
## How far ahead of the hips the leading foot is at the lunge, and how far behind them the trailing foot, along the travel.
const LUNGE_LEAD := 0.34
const LUNGE_TRAIL := 0.26
## How high a foot lifts at the middle of a stride's opening or closing (the sine of the way across it, over 4 s(1-s)).
const FOOT_LIFT := 0.10
## The peak lunge of each dash, by way: the hips sink and lean into the travel, the spine folds the same way, the head keeps up.
const DASH_PEAKS := {
	&"ahead": {"move": Vector3(0.0, -0.34, 0.0), "turns": {"pelvis": Vector3(0.0, 6.0, 0.0), "spine_02": Vector3(0.0, 12.0, 0.0),
			"spine_03": Vector3(0.0, 8.0, 0.0), "neck_01": Vector3(0.0, -8.0, 0.0), "Head": Vector3(0.0, -12.0, 0.0)}},
	&"back": {"move": Vector3(0.0, -0.34, -0.02), "turns": {"pelvis": Vector3(0.0, -3.0, 0.0), "spine_02": Vector3(0.0, -8.0, 0.0),
			"spine_03": Vector3(0.0, -6.0, 0.0), "neck_01": Vector3(0.0, 6.0, 0.0), "Head": Vector3(0.0, 10.0, 0.0)}},
	&"left": {"move": Vector3(0.04, -0.34, 0.0), "turns": {"pelvis": Vector3(4.0, 0.0, 0.0), "spine_02": Vector3(7.0, 0.0, 0.0),
			"spine_03": Vector3(5.0, 0.0, 0.0), "neck_01": Vector3(-5.0, 0.0, 0.0), "Head": Vector3(-7.0, 0.0, 0.0)}},
}
## Where each dash goes (the body's directions) and which foot leads it. The right dash is the left one mirrored.
const DASH_WAYS := {
	&"dash_step": {"way": AHEAD, "peak": &"ahead", "lead": "l", "mirror": false},
	&"dash_step_back": {"way": -AHEAD, "peak": &"back", "lead": "r", "mirror": false},
	&"dash_step_left": {"way": LEFT, "peak": &"left", "lead": "l", "mirror": false},
	&"dash_step_right": {"way": -LEFT, "peak": &"left", "lead": "r", "mirror": true},
}


## The rounding of a bone's rotations (degrees) and of the hips' travel (metres) as they are written.
const TURN_STEP := 0.001
const MOVE_STEP := 0.0001
## A value is the table's within this many rounding steps (a value on the edge of a step can fall either way).
const STEPS_ALLOWED := 1.5


## What is different between a layer file's text `committed` and the text `made` of the table, one line each; empty when they
## are the same layer within a rounding step: the same bones, the same frames, every value within STEPS_ALLOWED steps.
static func differences(made: String, committed: String) -> PackedStringArray:
	var out := PackedStringArray()
	var a := JSON.new()
	var b := JSON.new()
	if a.parse(made) != OK or b.parse(committed) != OK or not a.data is Dictionary or not b.data is Dictionary:
		out.append("a layer is not a JSON object")
		return out
	var want: Dictionary = a.data
	var have: Dictionary = b.data
	for bone: String in want:
		if not have.has(bone):
			out.append("bone %s is missing" % bone)
	for bone: String in have:
		if not want.has(bone):
			out.append("bone %s is not in the table's layer" % bone)
	for bone: String in want:
		if not have.has(bone):
			continue
		var step := MOVE_STEP if bone == "@pelvis_move" else TURN_STEP
		var wanted: Array = want[bone]
		var found: Array = have[bone]
		if wanted.size() != found.size():
			out.append("bone %s has %d frames, the table makes %d" % [bone, found.size(), wanted.size()])
			continue
		for i in wanted.size():
			for j in 4:
				if absf(float(wanted[i][j]) - float(found[i][j])) > step * STEPS_ALLOWED + 1e-9:
					out.append("bone %s, key %d: %s, the table makes %s" % [bone, i, found[i], wanted[i]])
					break
	return out


## Every clip's layer: {"files": {clip name: the text of its layer file}, "report": [one line per clip]}, for the clips
## named in `only` (all of them if it is empty).
static func generate(only := PackedStringArray()) -> Dictionary:
	var solver := _Solver.new()
	var files := {}
	var report := PackedStringArray()
	for spec: Dictionary in _specs():
		if not only.is_empty() and not only.has(spec["name"]):
			continue
		var made := solver.make(spec)
		files[spec["name"]] = made["text"]
		report.append(made["report"])
	return {"files": files, "report": report}


# One clip: {name, frames, curve, peak {move, turns}, way, kind (&"sway", &"duck", &"dash"), and for a dash its way entry}.
static func _specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tempo: StringName in FRAMES:
		for side in [&"left", &"right", &"back"]:
			var base: Dictionary = SWAY_BACK if side == &"back" else SWAY_LEFT.duplicate(true)
			if side == &"right":
				var lower: Vector3 = base["move"]
				base["move"] = Vector3(lower.x, -RIGHT_SINK, lower.z)
			var peak := _scaled(_mirrored(base, side == &"right"), SWAY_SIZE[tempo])
			out.append({"name": "sway_%s_%s" % [side, tempo], "frames": FRAMES[tempo], "curve": CURVES[tempo], "peak": peak,
					"way": {&"left": LEFT, &"right": -LEFT, &"back": -AHEAD}[side], "kind": &"sway"})
		out.append({"name": "duck_%s" % tempo, "frames": DUCK_FRAMES[tempo], "curve": DUCK_CURVES[tempo],
				"peak": _scaled(DUCK, DUCK_SIZE[tempo]), "way": Vector3.DOWN, "kind": &"duck"})
	for dash: StringName in DASH_WAYS:
		var entry: Dictionary = DASH_WAYS[dash]
		out.append({"name": String(dash), "frames": DASH_FRAMES, "curve": DASH_LEAN,
				"peak": _mirrored(DASH_PEAKS[entry["peak"]], entry["mirror"]), "way": entry["way"], "kind": &"dash", "dash": entry})
	return out


# The pose `peak` with every number times `k`.
static func _scaled(peak: Dictionary, k: float) -> Dictionary:
	var turns := {}
	for bone: String in peak["turns"]:
		turns[bone] = (peak["turns"][bone] as Vector3) * k
	return {"move": (peak["move"] as Vector3) * k, "turns": turns}


# The pose mirrored left to right when `mirror`: sideways moves, leans and twists change sign, pitches do not.
static func _mirrored(peak: Dictionary, mirror: bool) -> Dictionary:
	if not mirror:
		return peak
	var turns := {}
	for bone: String in peak["turns"]:
		var t: Vector3 = peak["turns"][bone]
		turns[bone] = Vector3(-t.x, t.y, -t.z)
	var move: Vector3 = peak["move"]
	return {"move": Vector3(-move.x, move.y, move.z), "turns": turns}


func _initialize() -> void:
	var only := PackedStringArray()
	var check := false
	var report := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--check":
			check = true
		elif arg == "--report":
			report = true
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		else:
			printerr("key_evades.gd: unknown argument '%s'" % arg)
			quit(2)
			return
	if not root.is_inside_tree():
		await process_frame  # the rig takes poses once it is in the tree
	var made := generate(only)
	for line: String in made["report"]:
		print(line)
	var wrong := 0
	for clip: String in made["files"]:
		var path := LAYERS + clip + ".json"
		if check:
			if not FileAccess.file_exists(path):
				printerr("key_evades.gd: %s is missing" % path)
				wrong += 1
				continue
			var found := differences(made["files"][clip], FileAccess.get_file_as_string(path))
			if not found.is_empty():
				printerr("key_evades.gd: %s is not what the table makes (within a rounding step): %s" % [path, found[0]])
				wrong += 1
		elif not report:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(made["files"][clip])
			file.close()
	quit(1 if wrong > 0 else 0)


## Solves the poses of one clip at a time on Abarax's skeleton, in the guard stance.
class _Solver:
	extends RefCounted

	var _rig: Node
	var _skeleton: Skeleton3D
	var _pose := {}    # bone -> [position, rotation] of the guard stance
	var _global := {}  # bone -> Transform3D of the guard stance, in the skeleton's space

	func _init() -> void:
		_rig = (load(RIG) as PackedScene).instantiate()
		# In the tree: a skeleton outside it does not take poses.
		(Engine.get_main_loop() as SceneTree).root.add_child(_rig)
		_skeleton = _rig.find_children("*", "Skeleton3D", true, false)[0]
		var anim := (load(LIBRARY) as AnimationLibrary).get_animation(GUARD_CLIP)
		_skeleton.reset_bone_poses()
		for i in anim.get_track_count():
			var bone := _skeleton.find_bone(String(anim.track_get_path(i).get_concatenated_subnames()))
			if bone < 0:
				continue
			match anim.track_get_type(i):
				Animation.TYPE_ROTATION_3D:
					_skeleton.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(i, 0.0))
				Animation.TYPE_POSITION_3D:
					_skeleton.set_bone_pose_position(bone, anim.position_track_interpolate(i, 0.0))
		for bone in _skeleton.get_bone_count():
			var name := _skeleton.get_bone_name(bone)
			_pose[name] = [_skeleton.get_bone_pose_position(bone), _skeleton.get_bone_pose_rotation(bone)]
			_global[name] = _skeleton.get_bone_global_pose(bone)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _rig != null:
			_rig.free()

	# The clip's layer text and a line saying what it does.
	func make(spec: Dictionary) -> Dictionary:
		var frames: int = spec["frames"]
		var way: Vector3 = spec["way"]
		var layer := {}
		for bone in EMIT:
			layer[bone] = []
		var moves := []
		var head0: Vector3 = (_global["Head"] as Transform3D).origin
		var pelvis0: Vector3 = (_global["pelvis"] as Transform3D).origin
		var peak_head := Vector3.ZERO
		var peak_along := -INF
		var worst_foot := 0.0
		var stride_four := Vector2.ZERO
		for frame in frames + 1:
			var k := _curve(spec["curve"], frame)
			var pose := _scaled(spec["peak"], k)
			var stride := _curve(DASH_STRIDE, frame) if spec["kind"] == &"dash" else 0.0
			worst_foot = maxf(worst_foot, _solve(pose, spec.get("dash", {}), stride))
			var head := _g("Head").origin - head0
			var along := head.dot(way)
			if along > peak_along + 1e-6:
				peak_along = along
				peak_head = head
			if frame == 4 and spec["kind"] == &"dash":
				var lead: String = spec["dash"]["lead"]
				var trail := "r" if lead == "l" else "l"
				stride_four = Vector2((_g("foot_" + lead).origin - _g("pelvis").origin).dot(way), -(_g("foot_" + trail).origin - _g("pelvis").origin).dot(way))
			var turns := _layer_now()
			for bone in EMIT:
				var v: Vector3 = turns[bone]
				(layer[bone] as Array).append([frame, snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)])
			var mv: Vector3 = pose["move"]
			moves.append([frame, snappedf(mv.x, 0.0001), snappedf(mv.y, 0.0001), snappedf(mv.z, 0.0001)])
		var line := "%-18s head %.3f along its way, %.3f lower, at (left %.3f, ahead %.3f) from the guard stance at the frame of most travel" % [spec["name"], peak_along, -peak_head.y, peak_head.x, peak_head.z]
		if spec["kind"] == &"dash":
			line += "; feet at f4: lead %.3f ahead of the hips, trail %.3f behind" % [stride_four.x, stride_four.y]
		line += "; the feet are %.4f m off" % worst_foot
		var out := {}
		for bone in EMIT:
			var moved := false
			for key: Array in layer[bone]:
				if absf(key[1]) > 0.002 or absf(key[2]) > 0.002 or absf(key[3]) > 0.002:
					moved = true
			if moved:
				out[bone] = layer[bone]
		out["@pelvis_move"] = moves
		return {"text": _text(out), "report": line}

	# The skeleton in `pose` (see the top of the file), the feet where they must be.
	func _solve(pose: Dictionary, dash: Dictionary, stride: float) -> float:
		for name: String in _pose:
			var bone := _skeleton.find_bone(name)
			_skeleton.set_bone_pose_position(bone, _pose[name][0])
			_skeleton.set_bone_pose_rotation(bone, _pose[name][1])
		var move: Vector3 = pose["move"]
		# The pelvis's position is in the root's frame, which stands the skeleton up: (x, -ahead, up).
		_skeleton.set_bone_pose_position(_skeleton.find_bone("pelvis"),
				(_pose["pelvis"][0] as Vector3) + Builder.ROOT_STANDS.inverse() * move)
		var turns: Dictionary = pose["turns"]
		for bone in CHAIN:
			if turns.has(bone):
				_turn(bone, _world_turn(turns[bone]))
		var worst := 0.0
		for side in ["l", "r"]:
			worst = maxf(worst, _solve_leg(side, _foot_target(side, dash, stride)))
		return worst

	# Where the foot of `side` must be: the guard stance's place, or in a dash's stride moved along the travel.
	func _foot_target(side: String, dash: Dictionary, stride: float) -> Vector3:
		var target: Vector3 = (_global["foot_" + side] as Transform3D).origin
		if dash.is_empty() or stride <= 0.0:
			return target
		var way: Vector3 = dash["way"]
		var pelvis := _g("pelvis").origin
		var base_axial := target.dot(way)
		var wanted := pelvis.dot(way) + (LUNGE_LEAD if side == dash["lead"] else -LUNGE_TRAIL)
		var axial := lerpf(base_axial, wanted, stride)
		target += way * (axial - base_axial)
		target.y += FOOT_LIFT * 4.0 * stride * (1.0 - stride)
		return target

	func _g(name: String) -> Transform3D:
		return _skeleton.get_bone_global_pose(_skeleton.find_bone(name))

	func _parent_basis(name: String) -> Basis:
		return _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(_skeleton.find_bone(name))).basis

	# The world rotation of (lean toward his left, pitch with the top forward, twist toward his left) degrees.
	func _world_turn(v: Vector3) -> Basis:
		return Basis(Vector3.UP, deg_to_rad(v.z)) * Basis(Vector3.RIGHT, deg_to_rad(v.y)) * Basis(AHEAD, deg_to_rad(-v.x))

	# Turns `bone` by the world rotation `rotation` about its own joint, its children with it.
	func _turn(bone: String, rotation: Basis) -> void:
		var index := _skeleton.find_bone(bone)
		var parent := _parent_basis(bone)
		var local := Basis(_skeleton.get_bone_pose_rotation(index))
		_skeleton.set_bone_pose_rotation(index, (parent.inverse() * rotation * parent * local).get_rotation_quaternion())

	func _set_global_basis(bone: String, basis: Basis) -> void:
		_skeleton.set_bone_pose_rotation(_skeleton.find_bone(bone), (_parent_basis(bone).inverse() * basis).get_rotation_quaternion())

	func _arc(from: Vector3, to: Vector3) -> Basis:
		var axis := from.normalized().cross(to.normalized())
		if axis.length() < 1e-7:
			return Basis.IDENTITY
		return Basis(axis.normalized(), from.normalized().angle_to(to.normalized()))

	# Bends leg `side` from its hip to put its foot at `target`, in the plane the guard stance bends it in; returns how far
	# the foot is off (when the leg cannot reach).
	func _solve_leg(side: String, target: Vector3) -> float:
		var thigh := "thigh_" + side
		var calf := "calf_" + side
		var foot := "foot_" + side
		var hip := _g(thigh).origin
		var l1 := ((_global[calf] as Transform3D).origin - (_global[thigh] as Transform3D).origin).length()
		var l2 := ((_global[foot] as Transform3D).origin - (_global[calf] as Transform3D).origin).length()
		var axis := target - hip
		var d := minf(axis.length(), l1 + l2 - 1e-4)
		var u := axis.normalized()
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var pole: Vector3 = (_global[calf] as Transform3D).origin - (_global[thigh] as Transform3D).origin
		pole -= u * pole.dot(u)
		var knee := hip + u * a + pole.normalized() * h
		_set_global_basis(thigh, _arc(_g(calf).origin - hip, knee - hip) * _g(thigh).basis)
		_set_global_basis(calf, _arc(_g(foot).origin - _g(calf).origin, target - _g(calf).origin) * _g(calf).basis)
		# The rig's foot IK puts the knee toward a pole along the calf's -Z: twist the calf until that lies in the bend plane
		# as it does in the guard stance.
		var base_axis := ((_global[foot] as Transform3D).origin - (_global[calf] as Transform3D).origin).normalized()
		var base_forward: Vector3 = -(_global[calf] as Transform3D).basis.z
		base_forward = (base_forward - base_axis * base_forward.dot(base_axis)).normalized()
		var base_hip: Vector3 = (_global[thigh] as Transform3D).origin - (_global[calf] as Transform3D).origin
		var base_bend := (base_hip - base_axis * base_hip.dot(base_axis)).normalized()
		var want := base_bend.signed_angle_to(base_forward, base_axis)
		var now_axis := (target - _g(calf).origin).normalized()
		var now_forward: Vector3 = -_g(calf).basis.z
		now_forward = (now_forward - now_axis * now_forward.dot(now_axis)).normalized()
		var now_hip := hip - _g(calf).origin
		var now_bend := (now_hip - now_axis * now_hip.dot(now_axis)).normalized()
		_set_global_basis(calf, Basis(now_axis, want - now_bend.signed_angle_to(now_forward, now_axis)) * _g(calf).basis)
		_set_global_basis(foot, (_global[foot] as Transform3D).basis)
		return (_g(foot).origin - target).length()

	# The layer value (Euler YXZ degrees) of each emitted bone for the pose now on the skeleton.
	func _layer_now() -> Dictionary:
		var out := {}
		for bone in EMIT:
			var index := _skeleton.find_bone(bone)
			var turn := Basis(_pose[bone][1] as Quaternion).inverse() * Basis(_skeleton.get_bone_pose_rotation(index))
			out[bone] = turn.get_euler(EULER_ORDER_YXZ) * (180.0 / PI)
		return out

	# A monotone cubic through [frame, value] points: smooth, and no overshoot past a peak's value.
	func _curve(points: Array, frame: float) -> float:
		var n := points.size()
		if frame <= points[0][0]:
			return points[0][1]
		if frame >= points[n - 1][0]:
			return points[n - 1][1]
		var deltas := []
		for i in n - 1:
			deltas.append((points[i + 1][1] - points[i][1]) / (points[i + 1][0] - points[i][0]))
		var slopes := [0.0]
		for i in range(1, n - 1):
			slopes.append(0.0 if deltas[i - 1] * deltas[i] <= 0.0 else 2.0 * deltas[i - 1] * deltas[i] / (deltas[i - 1] + deltas[i]))
		slopes.append(0.0)
		for i in n - 1:
			if frame <= points[i + 1][0]:
				var dx: float = points[i + 1][0] - points[i][0]
				var t: float = (frame - points[i][0]) / dx
				var t2: float = t * t
				var t3: float = t2 * t
				return (2 * t3 - 3 * t2 + 1) * points[i][1] + (t3 - 2 * t2 + t) * dx * slopes[i] \
						+ (-2 * t3 + 3 * t2) * points[i + 1][1] + (t3 - t2) * dx * slopes[i + 1]
		return 0.0

	# The pose `peak` with every number times `k`.
	func _scaled(peak: Dictionary, k: float) -> Dictionary:
		var turns := {}
		for bone: String in peak["turns"]:
			turns[bone] = (peak["turns"][bone] as Vector3) * k
		return {"move": (peak["move"] as Vector3) * k, "turns": turns}

	# One bone to a line, as the repository's other layer files are, keys on it.
	func _text(layer: Dictionary) -> String:
		var lines := PackedStringArray()
		for bone: String in layer:
			var keys := PackedStringArray()
			for key: Array in layer[bone]:
				keys.append("[%s]" % ", ".join(PackedStringArray(key.map(func(x: Variant) -> String: return str(x)))))
			lines.append("\t%s: [%s]" % [JSON.stringify(bone), ", ".join(keys)])
		return "{\n%s\n}\n" % ",\n".join(lines)
