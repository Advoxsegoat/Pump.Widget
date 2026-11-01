class_name ClipChecker
extends RefCounted
## Checks that a move's clip, its marks and its data agree. A problem is a line of text that starts with
## the id of what is wrong ("palm_jab: hitbox 'palm_l' turned on at f10 is never off"); no problems means
## the empty array. Nothing here raises an error: a bad file is reported, not thrown.
##
## The rules, per move (check_move):
##   an ATTACK has, for each hitbox id, hitbox_on before hitbox_off; at least one cancel_open; and exactly
##       one recovery, at or after the last hitbox_off; at least one entry in `hits`; and every hitbox_on
##       names (`profile`) one of those entries
##   a DODGE has iframes_on before iframes_off
##   a REACTION other than the death has exactly one recovery
##   every move has at least one sfx and one fx
##   every fx names an FxDef in the Registry kind `fx` and every sfx a SoundCue in the kind `sounds` (a mark with
##       no name, or one the data does not have, is reported), and an fx's optional `bone` is a bone of the rig
##   every hit profile of a move is a HitProfile with hitstop_frames 3 to 6
##   parry_on/parry_off, guard_on/guard_off and airborne_on/airborne_off come as on-then-off pairs
##   every mark is a known kind and lies within [0, the clip's length]
##   cancel_open's `into` names existing moves; hitbox ids are hitboxes of the rig; `neutral_variant`
##       names an existing move
##   tell's `kind` is glint or perilous; charge_hold is only in an ATTACK and names a profile it has
##   on a stepped clip (metadata step_fps above 0) every mark is on the 1/step_fps grid
##   for an actor of team ENEMY, every ATTACK has a tell at least TELL_LEAD frames before its first
##       hitbox_on (the player must be able to see it coming), and a move with a perilous profile has a
##       tell of kind perilous
## and per actor (check_actor): each required clip exists and is not a T-pose, the moveset and the
## reactions name existing moves, and each move the actor can start, react with or cancel into is checked
## against the actor's rig and team.
## check_all runs every actor in the Registry, and reports the moves no actor can reach, since those
## have no rig to be checked against.

## The mark kinds that name something in the data: kind -> [the Registry kind it is looked up in, what to call it].
const NAMED := {
	&"fx": [&"fx", "effect"],
	&"sfx": [&"sounds", "sound cue"],
}
## A mark may be this far (seconds) outside the clip or off its step grid.
const TOLERANCE := 1e-3
const HITSTOP_MIN := 3
const HITSTOP_MAX := 6
## An enemy attack's tell comes at least this many frames before its first hitbox_on: 200 ms.
const TELL_LEAD := 12
const TELL_KINDS: Array[StringName] = [&"glint", &"perilous"]
## The windows a clip opens and closes without arguments, by the name its problems call them: an on mark,
## then an off mark.
const WINDOW_PAIRS := {
	"parry": [&"parry_on", &"parry_off"],
	"guard": [&"guard_on", &"guard_off"],
	"airborne": [&"airborne_on", &"airborne_off"],
}
## The reaction that needs no recovery: the clip ends with the actor on the ground.
const DEATH := &"death"
## A bone within this many degrees of its rest rotation counts as not moved.
const REST_DEGREES := 1.0
## Metadata on a clip: the rate at which it is shown stepped; 0 or none means smooth.
const STEP_FPS_META := &"step_fps"


## What is wrong with `move` and its clip `anim`, given the ids of the rig's hitboxes and of every move,
## when the actor that plays it is on `team`. `bone_names` are the bones of the rig's skeleton, for the bones fx
## marks name; none means they are not checked. The effects and sounds the marks name are looked up in the Registry.
func check_move(move: MoveData, anim: Animation, hitbox_ids: PackedStringArray, move_ids: PackedStringArray,
		team := ActorDef.Team.PLAYER, bone_names := PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	var id := String(move.id)
	var marks := Marks.read(anim)
	var step_fps := int(anim.get_meta(STEP_FPS_META, 0))
	for mark in marks:
		_check_mark(id, mark, anim, step_fps, hitbox_ids, move_ids, bone_names, out)
	_check_hits(id, move, out)
	if move.kind == MoveData.Kind.ATTACK:
		_check_attack(id, move, marks, out)
		if team == ActorDef.Team.ENEMY:
			_check_tells(id, move, marks, out)
	elif move.kind == MoveData.Kind.DODGE:
		var iframes := _check_windows(marks, &"iframes_on", &"iframes_off", func(_m: Dictionary) -> String: return "iframes")
		if iframes["count"] == 0:
			out.append("%s: dodge has no iframes_on" % id)
		for problem: String in iframes["problems"]:
			out.append("%s: %s" % [id, problem])
	elif move.kind == MoveData.Kind.REACTION and move.id != DEATH:
		_check_one_recovery(id, marks, "reaction", out)
	for label: String in WINDOW_PAIRS:
		var kinds: Array = WINDOW_PAIRS[label]
		var checked := _check_windows(marks, kinds[0], kinds[1], func(_m: Dictionary) -> String: return label)
		for problem: String in checked["problems"]:
			out.append("%s: %s" % [id, problem])
	if move.kind != MoveData.Kind.ATTACK:
		for mark in _of_kind(marks, &"charge_hold"):
			out.append("%s: charge_hold at f%d is only allowed in an attack" % [id, Marks.frame_of(mark["time"])])
	if move.neutral_variant != &"" and not move_ids.has(String(move.neutral_variant)):
		out.append("%s: neutral_variant is the unknown move '%s'" % [id, move.neutral_variant])
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
		move_ids: PackedStringArray, bone_names: PackedStringArray, out: PackedStringArray) -> void:
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
		&"fx", &"sfx":
			var named := String(args.get("name", ""))
			var looked_up: Array = NAMED[kind]
			if named.is_empty():
				out.append("%s: %s has no name (an %s)" % [id, where, looked_up[1]])
			elif not Registry.ids(looked_up[0]).has(named):
				out.append("%s: %s names the unknown %s '%s' (data/%s/ has %s)" % [id, where, looked_up[1], named, looked_up[0], ", ".join(Registry.ids(looked_up[0]))])
			if kind == &"fx" and args.has("bone") and not bone_names.is_empty() and not bone_names.has(String(args["bone"])):
				out.append("%s: %s rides the bone '%s', which the rig does not have" % [id, where, args["bone"]])
		&"tell":
			if not args.has("kind"):
				out.append("%s: %s has no kind (glint or perilous)" % [id, where])
			elif not TELL_KINDS.has(StringName(str(args["kind"]))):
				out.append("%s: %s has the kind '%s', not glint or perilous" % [id, where, args["kind"]])
		&"cancel_open":
			var into: Variant = args.get("into")
			if not into is Dictionary or (into as Dictionary).is_empty():
				out.append("%s: %s has no 'into' (action -> move)" % [id, where])
			else:
				for action in into:
					if not move_ids.has(String(into[action])):
						out.append("%s: %s goes into unknown move '%s' (on %s)" % [id, where, into[action], action])


# What is wrong with a move's `hits`, whatever its kind: each is a HitProfile, and its hit-stop is in range.
func _check_hits(id: String, move: MoveData, out: PackedStringArray) -> void:
	for profile_name in move.hits:
		var profile: Variant = move.hits[profile_name]
		if not profile is HitProfile:
			out.append("%s: hits['%s'] is not a HitProfile" % [id, profile_name])
		elif profile.hitstop_frames < HITSTOP_MIN or profile.hitstop_frames > HITSTOP_MAX:
			out.append("%s: profile '%s' has hitstop_frames %d, outside %d to %d" % [id, profile_name, profile.hitstop_frames, HITSTOP_MIN, HITSTOP_MAX])


func _check_attack(id: String, move: MoveData, marks: Array[Dictionary], out: PackedStringArray) -> void:
	var hitboxes := _check_windows(marks, &"hitbox_on", &"hitbox_off", func(m: Dictionary) -> String: return "hitbox '%s'" % m["args"].get("id", ""))
	if hitboxes["count"] == 0:
		out.append("%s: attack has no hitbox_on" % id)
	for problem: String in hitboxes["problems"]:
		out.append("%s: %s" % [id, problem])
	if move.hits.is_empty():
		out.append("%s: attack has no hits (an entry in `hits` for each way it hurts)" % id)
	else:
		for mark in _of_kind(marks, &"hitbox_on"):
			_check_profile_of(id, mark, move, out)
		for mark in _of_kind(marks, &"charge_hold"):
			_check_profile_of(id, mark, move, out)
	if _of_kind(marks, &"cancel_open").is_empty():
		out.append("%s: attack has no cancel_open" % id)
	_check_one_recovery(id, marks, "attack", out)


# The mark names a profile (its `profile` argument), and the move has it.
func _check_profile_of(id: String, mark: Dictionary, move: MoveData, out: PackedStringArray) -> void:
	var where := "%s at f%d" % [mark["kind"], Marks.frame_of(mark["time"])]
	var profile := str(mark["args"].get("profile", ""))
	if profile.is_empty():
		out.append("%s: %s has no profile" % [id, where])
	elif not move.hits.has(StringName(profile)):
		out.append("%s: %s names unknown profile '%s' (the move has %s)" % [id, where, profile, ", ".join(PackedStringArray(move.hits.keys()))])


# The move has exactly one `recovery` mark, and it is not before the last hitbox_off (if there is one).
func _check_one_recovery(id: String, marks: Array[Dictionary], what: String, out: PackedStringArray) -> void:
	var recoveries := _of_kind(marks, &"recovery")
	if recoveries.size() != 1:
		out.append("%s: %s has %d recovery marks, needs exactly one" % [id, what, recoveries.size()])
	else:
		var last_off := -INF
		for m in _of_kind(marks, &"hitbox_off"):
			last_off = maxf(last_off, m["time"])
		if recoveries[0]["time"] < last_off - TOLERANCE:
			out.append("%s: recovery at f%d is before the last hitbox_off (f%d)" % [id, Marks.frame_of(recoveries[0]["time"]), Marks.frame_of(last_off)])


# The readability rules of an enemy attack (spec 3.5): a tell the player can react to.
func _check_tells(id: String, move: MoveData, marks: Array[Dictionary], out: PackedStringArray) -> void:
	var hitboxes := _of_kind(marks, &"hitbox_on")
	if not hitboxes.is_empty():
		var first := Marks.frame_of(hitboxes[0]["time"])
		var warned := false
		for tell in _of_kind(marks, &"tell"):
			warned = warned or Marks.frame_of(tell["time"]) <= first - TELL_LEAD
		if not warned:
			out.append("%s: enemy attack has no tell at least %d frames before its first hitbox_on (f%d)" % [id, TELL_LEAD, first])
	var perilous_profile := ""
	for profile_name in move.hits:
		var profile: Variant = move.hits[profile_name]
		if profile is HitProfile and profile.perilous != HitProfile.Perilous.NONE:
			perilous_profile = str(profile_name)
	if perilous_profile != "" and not _of_kind(marks, &"tell").any(func(m: Dictionary) -> bool: return str(m["args"].get("kind")) == "perilous"):
		out.append("%s: profile '%s' is perilous, so the attack needs a tell of kind perilous" % [id, perilous_profile])


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

# The moves `def` can start with no move before them, as ids: its moveset and its reactions. A name that is
# not a move is a problem in `out`. Further sources of reachable moves (the pair it grabs with, F1 Task 10,
# and the attacks of its brain, Task 13) are added here.
func _start_moves(def: ActorDef, move_ids: PackedStringArray, out: PackedStringArray) -> Array[String]:
	var found: Array[String] = []
	for action in def.moveset:
		var move_id := String(def.moveset[action])
		if move_ids.has(move_id):
			found.append(move_id)
		else:
			out.append("%s: moveset '%s' names unknown move '%s'" % [def.id, action, move_id])
	for reaction in def.reactions:
		var move_id := String(def.reactions[reaction])
		if move_ids.has(move_id):
			found.append(move_id)
		else:
			out.append("%s: reaction '%s' names unknown move '%s'" % [def.id, reaction, move_id])
	return found


# The moves one can get to from `move` (whose clip is `anim`) while it plays, as ids: the targets of its
# cancel windows, and its neutral variant. Only moves that exist; a name that is not one is check_move's
# problem.
func _moves_after(move: MoveData, anim: Animation, move_ids: PackedStringArray) -> Array[String]:
	var found: Array[String] = []
	for mark in Marks.read(anim):
		if mark["kind"] == &"cancel_open" and mark["args"].get("into") is Dictionary:
			for target in mark["args"]["into"].values():
				if move_ids.has(String(target)):
					found.append(String(target))
	if move_ids.has(String(move.neutral_variant)):
		found.append(String(move.neutral_variant))
	return found


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
	var bone_names := PackedStringArray()
	if skeleton != null:
		for bone in skeleton.get_bone_count():
			bone_names.append(skeleton.get_bone_name(bone))
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
	var queue := _start_moves(def, move_ids, out)
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
			out.append_array(check_move(move, anim, hitbox_ids, move_ids, def.team, bone_names))
			queue.append_array(_moves_after(move, anim, move_ids))
	rig.free()
	return out
