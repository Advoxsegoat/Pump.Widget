class_name ClipChecker
extends RefCounted
## Checks that a move's clip, its marks and its data agree. A problem is a line of text that starts with
## the id of what is wrong ("palm_jab: hitbox 'palm_l' turned on at f10 is never off"); no problems means
## the empty array. Nothing here raises an error: a bad file is reported, not thrown.
##
## The rules, per move (check_move):
##   an ATTACK has, for each hitbox id, hitbox_on before hitbox_off; at least one cancel_open; and exactly
##       one recovery, at or after the last hitbox_off
##   a DODGE has iframes_on before iframes_off
##   every move has at least one sfx and one fx
##   every mark is a known kind and lies within [0, the clip's length]
##   cancel_open's `into` names existing moves; hitbox ids are hitboxes of the rig; hitstop is 3 to 6 frames
##   on a stepped clip (metadata step_fps above 0) every mark is on the 1/step_fps grid
## and per actor (check_actor): each required clip exists and is not a T-pose, the moveset names existing
## moves, and each move the actor can start or cancel into is checked against the actor's rig.
## check_all runs every actor in the Registry, and reports the moves no actor can reach, since those
## have no rig to be checked against.

## A mark may be this far (seconds) outside the clip or off its step grid.
const TOLERANCE := 1e-3
const HITSTOP_MIN := 3
const HITSTOP_MAX := 6
## A bone within this many degrees of its rest rotation counts as not moved.
const REST_DEGREES := 1.0
## Metadata on a clip: the rate at which it is shown stepped; 0 or none means smooth.
const STEP_FPS_META := &"step_fps"


## What is wrong with `move` and its clip `anim`, given the ids of the rig's hitboxes and of every move.
func check_move(move: MoveData, anim: Animation, hitbox_ids: PackedStringArray, move_ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var id := String(move.id)
	var marks := Marks.read(anim)
	var step_fps := int(anim.get_meta(STEP_FPS_META, 0))
	for mark in marks:
		_check_mark(id, mark, anim, step_fps, hitbox_ids, move_ids, out)
	if move.kind == MoveData.Kind.ATTACK:
		_check_attack(id, marks, out)
	elif move.kind == MoveData.Kind.DODGE:
		var iframes := _check_windows(marks, &"iframes_on", &"iframes_off", func(_m: Dictionary) -> String: return "iframes")
		if iframes["count"] == 0:
			out.append("%s: dodge has no iframes_on" % id)
		for problem: String in iframes["problems"]:
			out.append("%s: %s" % [id, problem])
	for kind in [&"sfx", &"fx"]:
		if _of_kind(marks, kind).is_empty():
			out.append("%s: has no %s" % [id, kind])
	return out


## What is wrong with the actor `def`: its rig, its required clips, its moveset, and every move it can
## start or cancel into (see the top of this file).
func check_actor(def: ActorDef) -> PackedStringArray:
	return _check_actor(def, {})


## check_actor for every actor in the Registry, each problem once, then a problem for every move in the
## Registry that no actor's moveset (or cancel chain from it) reaches.
func check_all() -> PackedStringArray:
	var out := PackedStringArray()
	var reached := {}
	for actor_id in Registry.ids(&"actors"):
		var def := Registry.fetch(&"actors", StringName(actor_id)) as ActorDef
		if def == null:
			out.append("%s: is not an ActorDef" % actor_id)
			continue
		for problem in _check_actor(def, reached):
			if not out.has(problem):
				out.append(problem)
	for move_id in Registry.ids(&"moves"):
		if not reached.has(String(move_id)):
			out.append("%s: no actor's moveset reaches this move (directly or by cancelling), so its clip cannot be checked" % move_id)
	return out


## True if `anim` leaves `skeleton` in its rest pose: every rotation key of every bone is within
## REST_DEGREES of the bone's rest rotation. A clip with no rotation tracks leaves the rest pose showing
## too. (Bones the clip does not name are not in the skeleton and are skipped.)
static func is_t_pose(anim: Animation, skeleton: Skeleton3D) -> bool:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := skeleton.find_bone(String(anim.track_get_path(t).get_concatenated_subnames()))
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		for k in anim.track_get_key_count(t):
			if _angle(rest, anim.track_get_key_value(t, k)) > deg_to_rad(REST_DEGREES):
				return false
	return true


# --- a move ---

func _check_mark(id: String, mark: Dictionary, anim: Animation, step_fps: int, hitbox_ids: PackedStringArray,
		move_ids: PackedStringArray, out: PackedStringArray) -> void:
	var kind: StringName = mark["kind"]
	var time: float = mark["time"]
	var args: Dictionary = mark["args"]
	var where := "%s at f%d" % [kind, Marks.frame_of(time)]
	if not Marks.KINDS.has(kind):
		out.append("%s: unknown mark kind '%s' at f%d" % [id, kind, Marks.frame_of(time)])
		return
	if time < -TOLERANCE or time > anim.length + TOLERANCE:
		out.append("%s: %s is outside the clip (f0 to f%d)" % [id, where, Marks.frame_of(anim.length)])
	if step_fps > 0 and absf(time - roundf(time * step_fps) / step_fps) > TOLERANCE:
		out.append("%s: %s is off the %d fps step grid" % [id, where, step_fps])
	match kind:
		&"hitbox_on", &"hitbox_off":
			var hitbox := String(args.get("id", ""))
			if hitbox.is_empty():
				out.append("%s: %s has no id" % [id, where])
			elif not hitbox_ids.has(hitbox):
				out.append("%s: hitbox '%s' (%s) is not in the rig (it has %s)" % [id, hitbox, where, ", ".join(hitbox_ids)])
		&"cancel_open":
			var into: Variant = args.get("into")
			if not into is Dictionary or (into as Dictionary).is_empty():
				out.append("%s: %s has no 'into' (action -> move)" % [id, where])
			else:
				for action in into:
					if not move_ids.has(String(into[action])):
						out.append("%s: %s goes into unknown move '%s' (on %s)" % [id, where, into[action], action])
		&"hitstop":
			var frames: Variant = args.get("frames")
			if not (frames is int or frames is float):
				out.append("%s: %s has no frames" % [id, where])
			elif int(frames) < HITSTOP_MIN or int(frames) > HITSTOP_MAX:
				out.append("%s: %s has %d frames, outside %d to %d" % [id, where, int(frames), HITSTOP_MIN, HITSTOP_MAX])


func _check_attack(id: String, marks: Array[Dictionary], out: PackedStringArray) -> void:
	var hitboxes := _check_windows(marks, &"hitbox_on", &"hitbox_off", func(m: Dictionary) -> String: return "hitbox '%s'" % m["args"].get("id", ""))
	if hitboxes["count"] == 0:
		out.append("%s: attack has no hitbox_on" % id)
	for problem: String in hitboxes["problems"]:
		out.append("%s: %s" % [id, problem])
	if _of_kind(marks, &"cancel_open").is_empty():
		out.append("%s: attack has no cancel_open" % id)
	var recoveries := _of_kind(marks, &"recovery")
	if recoveries.size() != 1:
		out.append("%s: attack has %d recovery marks, needs exactly one" % [id, recoveries.size()])
	else:
		var last_off := -INF
		for m in _of_kind(marks, &"hitbox_off"):
			last_off = maxf(last_off, m["time"])
		if recoveries[0]["time"] < last_off - TOLERANCE:
			out.append("%s: recovery at f%d is before the last hitbox_off (f%d)" % [id, Marks.frame_of(recoveries[0]["time"]), Marks.frame_of(last_off)])


# Walks `marks` in time order and checks every window `on_kind` .. `off_kind` opens and closes, one
# window at a time per key (`label_of(mark)` names the key: a hitbox's id, or just "iframes").
# Returns {"count": how many on marks there were, "problems": PackedStringArray, each without a prefix}.
func _check_windows(marks: Array[Dictionary], on_kind: StringName, off_kind: StringName, label_of: Callable) -> Dictionary:
	var problems := PackedStringArray()
	var count := 0
	var open := {}  # label -> frame it was turned on
	for mark in marks:
		var kind: StringName = mark["kind"]
		if kind != on_kind and kind != off_kind:
			continue
		var label: String = label_of.call(mark)
		var frame := Marks.frame_of(mark["time"])
		if kind == on_kind:
			count += 1
			if open.has(label):
				problems.append("%s turned on at f%d while it was already on (since f%d)" % [label, frame, open[label]])
			open[label] = frame
		elif open.has(label):
			open.erase(label)
		else:
			problems.append("%s turned off at f%d before it was turned on" % [label, frame])
	for label: String in open:
		problems.append("%s turned on at f%d is never off" % [label, open[label]])
	return {"count": count, "problems": problems}


func _of_kind(marks: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for mark in marks:
		if mark["kind"] == kind:
			found.append(mark)
	return found


# The angle between two rotations, in radians. Quaternion.angle_to goes through acos, which cannot tell
# a rotation from its negation (the same orientation); this can.
static func _angle(a: Quaternion, b: Quaternion) -> float:
	var d := a.normalized().inverse() * b.normalized()
	return 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w))


# --- an actor ---

# check_actor, also noting in `reached` (move id -> true) every move it checked.
func _check_actor(def: ActorDef, reached: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var id := String(def.id)
	if def.rig_scene == null:
		out.append("%s: has no rig_scene" % id)
		return out
	var rig := def.rig_scene.instantiate()
	var tree := rig.get_node_or_null("AnimationTree") as AnimationTree
	var skeletons := rig.find_children("*", "Skeleton3D", true, false)
	var skeleton: Skeleton3D = skeletons[0] if not skeletons.is_empty() else null
	if tree == null:
		out.append("%s: the rig has no AnimationTree" % id)
		rig.free()
		return out
	var hitbox_ids := PackedStringArray()
	var hitboxes := rig.get_node_or_null("Hitboxes")
	if hitboxes != null:
		for child in hitboxes.get_children():
			hitbox_ids.append(String(child.name))
	for clip in def.required_clips:
		if not tree.has_animation(clip):
			out.append("%s: required clip '%s' is missing from the rig" % [id, clip])
		elif skeleton != null and is_t_pose(tree.get_animation(clip), skeleton):
			out.append("%s: required clip '%s' is a T-pose (every bone stays within %s degrees of its rest pose)" % [id, clip, REST_DEGREES])
	var move_ids := Registry.ids(&"moves")
	var queue: Array[String] = []
	for action in def.moveset:
		var move_id := String(def.moveset[action])
		if move_ids.has(move_id):
			queue.append(move_id)
		else:
			out.append("%s: moveset '%s' names unknown move '%s'" % [id, action, move_id])
	var seen := {}  # the moves of this actor already checked
	var next := 0
	while next < queue.size():
		var move_id := queue[next]
		next += 1
		if seen.has(move_id):
			continue
		seen[move_id] = true
		reached[move_id] = true
		var move := Registry.fetch(&"moves", StringName(move_id)) as MoveData
		if move == null:
			out.append("%s: is not a MoveData" % move_id)
		elif not tree.has_animation(move.clip):
			out.append("%s: clip '%s' is not in the rig of %s" % [move_id, move.clip, id])
		else:
			var anim := tree.get_animation(move.clip)
			out.append_array(check_move(move, anim, hitbox_ids, move_ids))
			for mark in Marks.read(anim):
				if mark["kind"] == &"cancel_open" and mark["args"].get("into") is Dictionary:
					for target in mark["args"]["into"].values():
						if move_ids.has(String(target)):
							queue.append(String(target))
	rig.free()
	return out
