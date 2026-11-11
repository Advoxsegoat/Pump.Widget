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
##   a DODGE is a sway or duck, with an evade window in place of invulnerability, or a dash-step, which is never
##       invulnerable: a DODGE whose `evade` is NONE carries no iframes marks (and no evade marks)
##   a REACTION other than the death has exactly one recovery
##   every move has at least one sfx and one fx (a sway or duck sounds from the rules of the evade, not from a mark)
##   every fx names an FxDef in the Registry kind `fx` and every sfx a SoundCue in the kind `sounds` (a mark with
##       no name, or one the data does not have, is reported), and the bone each effect rides is a bone of the rig:
##       an fx's own `bone`, else its FxDef's, and the FxDef's of a tell (glint, perilous_rose) and of a charge_hold
##       (charge_glow), as ActorFx shows them, so an effect made for another rig is not shown at an actor's feet
##   every hit profile of a move is a HitProfile with hitstop_frames 3 to 6
##   parry_on/parry_off, guard_on/guard_off, airborne_on/airborne_off and hyperarmour_on/hyperarmour_off come as
##       on-then-off pairs
##   every mark is a known kind and lies within [0, the clip's length]
##   cancel_open's `into` names existing moves; hitbox ids are hitboxes of the rig; `neutral_variant`
##       and every `directional` target name existing moves; and so does `imitates` (a feint: its tell wears the rim of that move's blow, and a
##       name that is no move would show no rim and say nothing)
##   tell's `kind` is glint or perilous; charge_hold is only in an ATTACK and names a profile it has
##   on a stepped clip (metadata step_fps above 0) every mark is on the 1/step_fps grid
##   for an actor of team ENEMY, every ATTACK has a tell at least TELL_LEAD frames before its first
##       hitbox_on (the player must be able to see it coming), and a move with a perilous profile has a
##       tell of kind perilous
## per paired move (check_pair: a finisher or a grab, PairedMove), given the clips of its two moves:
##   the lead's clip, with the hit-stop of every blow it lands, is no longer than the pair's max_length (spec 4.4: a
##       finisher keeps the player 1.5 s at most, press to control; the lead is free when its clip ends)
##   every pair_hit, in either clip, names (`profile`) one of the pair's `hits`, whatever the kind of its move
##   every hit profile of the pair is a HitProfile with hitstop_frames 3 to 6
## and per actor (check_actor): each required clip exists and is not a T-pose, the moveset, the reactions, the
## pairs (its finisher and its grab_pair) and the dodge chain (the sways and ducks it starts by tempo) name existing moves, each move the actor can start, react with, cancel
## into (as the windows open for it: MoveRunner.window_of) or play in one of its pairs is checked against the actor's
## rig and team, and each of its pairs is checked with the clips of its rig. A move that `imitates` another imitates one
## whose clip is in the actor's rig and has a hitbox_on: the blow whose rim it wears. An enemy's brain (ActorDef.brain) presses
## only actions of the moveset (each attack's own, and the feint's when it feints), and every press of an attack's
## combo, with the extra blow when the brain extends combos, is taken by a cancel window of the move before it.
## check_all runs every actor in the Registry, and reports the moves no actor can reach and the pairs no actor
## uses, since those have no rig to be checked against.

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
	"hyperarmour": [&"hyperarmour_on", &"hyperarmour_off"],
	"evade": [&"evade_on", &"evade_off"],
}
## The frame every evade window opens on, so that a sway or duck pressed at the last moment is safe from its second frame.
const EVADE_OPENS := 2
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
		# A sway or duck has its evade window, a dash-step nothing: neither is invulnerable, so neither has iframes.
		if iframes["count"] > 0:
			out.append("%s: is a dodge with no invulnerability (a sway, duck or dash-step) but its clip has iframes marks" % id)
		for problem: String in iframes["problems"]:
			out.append("%s: %s" % [id, problem])
	elif move.kind == MoveData.Kind.REACTION and move.id != DEATH:
		_check_one_recovery(id, marks, "reaction", out)
	for label: String in WINDOW_PAIRS:
		var kinds: Array = WINDOW_PAIRS[label]
		var checked := _check_windows(marks, kinds[0], kinds[1], func(_m: Dictionary) -> String: return label)
		for problem: String in checked["problems"]:
			out.append("%s: %s" % [id, problem])
	_check_evade(id, move, marks, out)
	if move.kind != MoveData.Kind.ATTACK:
		for mark in _of_kind(marks, &"charge_hold"):
			out.append("%s: charge_hold at f%d is only allowed in an attack" % [id, Marks.frame_of(mark["time"])])
	if move.neutral_variant != &"" and not move_ids.has(String(move.neutral_variant)):
		out.append("%s: neutral_variant is the unknown move '%s'" % [id, move.neutral_variant])
	for side in move.directional:
		if not move_ids.has(String(move.directional[side])):
			out.append("%s: directional '%s' is the unknown move '%s'" % [id, side, move.directional[side]])
	if move.imitates != &"" and not move_ids.has(String(move.imitates)):
		out.append("%s: imitates the unknown move '%s'" % [id, move.imitates])
	for kind in [&"sfx", &"fx"]:
		if _of_kind(marks, kind).is_empty() and move.evade == MoveData.Evade.NONE:
			out.append("%s: has no %s" % [id, kind])
	return out


## What is wrong with the actor `def`: its rig, its required clips, its moveset, its pairs, and every move it can
## start, cancel into or play in a pair (see the top of this file).
func check_actor(def: ActorDef) -> PackedStringArray:
	return _check_actor(def, {}, {})


## check_actor for every actor in the Registry, each problem once, then a problem for every move in the
## Registry that no actor's moveset (or cancel chain from it, or pair) reaches, and for every pair in the Registry
## that no actor uses.
func check_all() -> PackedStringArray:
	var out := PackedStringArray()
	var reached := {}
	var paired := {}
	for actor_id in Registry.ids(&"actors"):
		var def := Registry.fetch(&"actors", StringName(actor_id)) as ActorDef
		if def == null:
			out.append("%s: is not an ActorDef" % actor_id)
			continue
		for problem in _check_actor(def, reached, paired):
			if not out.has(problem):
				out.append(problem)
	for move_id in Registry.ids(&"moves"):
		if not reached.has(String(move_id)):
			out.append("%s: no actor's moveset reaches this move (directly or by cancelling), so its clip cannot be checked" % move_id)
	for pair_id in Registry.ids(&"pairs"):
		if not paired.has(String(pair_id)):
			out.append("%s: no actor uses this pair (as its finisher or grab_pair), so its clips cannot be checked" % pair_id)
	return out


## What is wrong with the paired move `pair`, given `lead` and `follow`, the clips of its lead and follow moves (see
## the top of this file). That its moves exist is check_actor's to say.
func check_pair(pair: PairedMove, lead: Animation, follow: Animation) -> PackedStringArray:
	var out := PackedStringArray()
	var id := String(pair.id)
	var hit_stop := 0.0
	for mark in _of_kind(Marks.read(lead), &"pair_hit"):
		var profile: Variant = pair.hits.get(StringName(str(mark["args"].get("profile", ""))))
		if profile is HitProfile:
			hit_stop += (profile as HitProfile).hitstop_frames / float(Marks.RATE)
	if lead.length + hit_stop > pair.max_length + TOLERANCE:
		out.append("%s: the lead's clip '%s' and the hit-stop of its blows are %.2f s, longer than the pair's max_length of %.2f s"
				% [id, pair.lead_move, lead.length + hit_stop, pair.max_length])
	_check_profiles(id, pair.hits, out)
	for anim in [lead, follow]:
		for mark in _of_kind(Marks.read(anim), &"pair_hit"):
			var where := "pair_hit at f%d" % Marks.frame_of(mark["time"])
			var profile := str(mark["args"].get("profile", ""))
			if profile.is_empty():
				out.append("%s: %s has no profile" % [id, where])
			elif not pair.hits.has(StringName(profile)):
				out.append("%s: %s names unknown profile '%s' (the pair has %s)" % [id, where, profile, ", ".join(PackedStringArray(pair.hits.keys()))])
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
			elif kind == &"fx" and not args.has("bone"):
				_check_fx_bone(id, where, StringName(named), bone_names, out)
		&"tell":
			if not args.has("kind"):
				out.append("%s: %s has no kind (glint or perilous)" % [id, where])
			elif not TELL_KINDS.has(StringName(str(args["kind"]))):
				out.append("%s: %s has the kind '%s', not glint or perilous" % [id, where, args["kind"]])
			else:
				_check_fx_bone(id, where, ActorFx.TELL_FX[StringName(str(args["kind"]))], bone_names, out)
		&"charge_hold":
			_check_fx_bone(id, where, ActorFx.CHARGE_FX, bone_names, out)
		&"cancel_open":
			var into: Variant = args.get("into")
			if not into is Dictionary or (into as Dictionary).is_empty():
				out.append("%s: %s has no 'into' (action -> move)" % [id, where])
			else:
				for action in into:
					if not move_ids.has(String(into[action])):
						out.append("%s: %s goes into unknown move '%s' (on %s)" % [id, where, into[action], action])


# The effect `effect` that a mark shows (an fx mark with no bone of its own, a tell, a charge) rides the bone its FxDef
# names: that bone is one of the rig's `bone_names` (none: not checked), or the effect would show at the actor's feet.
func _check_fx_bone(id: String, where: String, effect: StringName, bone_names: PackedStringArray, out: PackedStringArray) -> void:
	if bone_names.is_empty() or not Registry.ids(&"fx").has(String(effect)):
		return
	var def := Registry.fetch(&"fx", effect) as FxDef
	if def != null and def.bone != &"" and not bone_names.has(String(def.bone)):
		out.append("%s: %s shows the effect '%s', which rides the bone '%s' the rig does not have" % [id, where, effect, def.bone])


# What is wrong with a move's `hits`, whatever its kind: each is a HitProfile, and its hit-stop is in range.
func _check_hits(id: String, move: MoveData, out: PackedStringArray) -> void:
	_check_profiles(id, move.hits, out)


# What is wrong with `hits` (a move's or a pair's, profile name -> HitProfile) of the move or pair `id`.
func _check_profiles(id: String, hits: Dictionary, out: PackedStringArray) -> void:
	for profile_name in hits:
		var profile: Variant = hits[profile_name]
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


# A move with an evade has exactly one evade window, opening on EVADE_OPENS; a move without one has no evade marks.
# (An unpaired window is reported by the window pairs.)
func _check_evade(id: String, move: MoveData, marks: Array[Dictionary], out: PackedStringArray) -> void:
	var opens := _of_kind(marks, &"evade_on")
	if move.evade == MoveData.Evade.NONE:
		if not opens.is_empty() or not _of_kind(marks, &"evade_off").is_empty():
			out.append("%s: has evade marks but its evade is NONE" % id)
		return
	if opens.is_empty():
		out.append("%s: an evade move has no evade window" % id)
	elif opens.size() > 1:
		out.append("%s: an evade move needs exactly one evade window, not %d" % [id, opens.size()])
	else:
		var frame := Marks.frame_of(opens[0]["time"])
		if frame != EVADE_OPENS:
			out.append("%s: the evade window opens at f%d, not f%d" % [id, frame, EVADE_OPENS])


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

# The pairs of `def`: its finisher and its grab_pair, those it has.
static func _pairs_of(def: ActorDef) -> Array[PairedMove]:
	var found: Array[PairedMove] = []
	for pair in [def.finisher, def.grab_pair]:
		if pair != null:
			found.append(pair)
	return found


# The moves `def` can start with no move before them, as ids: its moveset, its reactions, both moves of each of its
# pairs, and the move each attack of its brain starts. A name that is not a move, or a brain attack whose action the
# moveset lacks, is a problem in `out`.
func _start_moves(def: ActorDef, move_ids: PackedStringArray, out: PackedStringArray) -> Array[String]:
	var found: Array[String] = []
	if def.brain != null:
		for option in def.brain.attacks:
			if option != null and def.moveset.has(option.action):
				found.append(String(def.moveset[option.action]))
			else:
				out.append("%s: brain attack presses '%s', which its moveset lacks" % [def.id, option.action if option != null else &""])
		if def.brain.feint_chance > 0.0 and not def.moveset.has(EnemyBrain.FEINT_ACTION):
			out.append("%s: brain feints, but its moveset has no feint ('%s')" % [def.id, EnemyBrain.FEINT_ACTION])
	if def.chain != null:
		# the chain starts a sway or duck by its tempo (Actor.move_for), whatever the moveset and the windows name; the sides of
		# each follow from its `directional`
		for role: String in ["sway_moves", "duck_moves"]:
			for move_id: StringName in def.chain.get(role):
				if move_ids.has(String(move_id)):
					found.append(String(move_id))
				else:
					out.append("%s: its chain's %s names unknown move '%s'" % [def.id, role, move_id])
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
	for pair in _pairs_of(def):
		for role in [&"lead_move", &"follow_move"]:
			var move_id := String(pair.get(role))
			if move_ids.has(move_id):
				found.append(move_id)
			else:
				out.append("%s: %s is the unknown move '%s'" % [pair.id, role, move_id])
	return found


# The problems of `def`'s dodge chain lists: each holds exactly three entries (Slip, Quick, Flurry); each entry is a move (an
# unknown one is reported by _start_moves), a sway's evade is SWAY and a duck's DUCK, and its clip has an evade_on and an evade_off
# mark. A wrong entry would throw some other move when the key is pressed at that tempo, and a short list would fall back to Slip.
func _check_chain(def: ActorDef, tree: AnimationTree, move_ids: PackedStringArray, out: PackedStringArray) -> void:
	if def.chain == null:
		return
	for role: String in ["sway_moves", "duck_moves"]:
		var list: Array = def.chain.get(role)
		var want := MoveData.Evade.SWAY if role == "sway_moves" else MoveData.Evade.DUCK
		var want_name := "SWAY" if role == "sway_moves" else "DUCK"
		if list.size() != 3:
			out.append("%s: its chain's %s holds %d moves, not three (Slip, Quick, Flurry)" % [def.id, role, list.size()])
		for move_id: StringName in list:
			if not move_ids.has(String(move_id)):
				continue
			var move := Registry.fetch(&"moves", move_id) as MoveData
			if move == null:
				continue
			if move.evade != want:
				out.append("%s: its chain's %s names '%s', whose evade is not %s" % [def.id, role, move_id, want_name])
			if tree.has_animation(move.clip):
				var marks := Marks.read(tree.get_animation(move.clip))
				if _of_kind(marks, &"evade_on").is_empty() or _of_kind(marks, &"evade_off").is_empty():
					out.append("%s: its chain's %s names '%s', whose clip has no evade_on and evade_off marks" % [def.id, role, move_id])


# The moves one can get to from `move` (whose clip is `anim`) while the actor of `def` plays it, as ids: the targets of
# its cancel windows as they open for that actor (MoveRunner.window_of: a shared reaction's only into the actor's own
# moves), and its neutral variant. Only moves that exist; a name that is not one is check_move's problem.
func _moves_after(move: MoveData, anim: Animation, move_ids: PackedStringArray, def: ActorDef) -> Array[String]:
	var found: Array[String] = []
	for mark in Marks.read(anim):
		if mark["kind"] == &"cancel_open" and mark["args"].get("into") is Dictionary:
			for target in MoveRunner.window_of(move, mark["args"]["into"], def).values():
				if move_ids.has(String(target)):
					found.append(String(target))
	if move_ids.has(String(move.neutral_variant)):
		found.append(String(move.neutral_variant))
	for target in move.directional.values():
		if move_ids.has(String(target)):
			found.append(String(target))
	return found


# The problems of the combos of `def`'s brain: each press of an attack's combo (and, when the brain extends combos, its
# last press once more) must be taken by a cancel window of the move before it, as the windows open for this actor
# (MoveRunner.window_of; any of the move's windows will do). A press no window takes is reported once, and the rest of
# that combo is not followed.
func _check_combos(def: ActorDef, tree: AnimationTree, move_ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if def.brain == null:
		return out
	for option in def.brain.attacks:
		if option == null or not def.moveset.has(option.action):
			continue  # reported with the start moves
		var chains: Array[PackedStringArray] = [option.combo]
		if def.brain.extend_combo_chance > 0.0 and not option.combo.is_empty():
			var longer := option.combo.duplicate()
			longer.append(option.combo[option.combo.size() - 1])
			chains.append(longer)
		for chain in chains:
			var move_id := String(def.moveset[option.action])
			for i in chain.size():
				var move := Registry.fetch(&"moves", StringName(move_id)) as MoveData if move_ids.has(move_id) else null
				if move == null or not tree.has_animation(move.clip):
					break  # reported where the move is checked
				var takes := {}
				for mark in Marks.read(tree.get_animation(move.clip)):
					if mark["kind"] == &"cancel_open" and mark["args"].get("into") is Dictionary:
						takes.merge(MoveRunner.window_of(move, mark["args"]["into"], def))
				if not takes.has(StringName(chain[i])) and not takes.has(String(chain[i])):
					var problem := "%s: brain attack '%s' presses '%s' after '%s', which no cancel window of it takes" % [def.id, option.action, chain[i], move_id]
					if not out.has(problem):
						out.append(problem)
					break
				move_id = String(takes.get(StringName(chain[i]), takes.get(String(chain[i]))))
	return out


# The move `move` imitates (if it names one that exists: check_move reports a name that is no move) has a blow to imitate
# as the actor `actor_id` plays it: its clip is in the rig (`tree`) and has a hitbox_on. ActorFx reads that clip's marks for
# the rim of the feint's tell, and with no hitbox_on there, or no clip, it shows none.
func _check_imitated(move: MoveData, tree: AnimationTree, move_ids: PackedStringArray, actor_id: String, out: PackedStringArray) -> void:
	if move.imitates == &"" or not move_ids.has(String(move.imitates)):
		return
	var model := Registry.fetch(&"moves", move.imitates) as MoveData
	if model == null:
		out.append("%s: imitates '%s', which is not a MoveData" % [move.id, move.imitates])
	elif not tree.has_animation(model.clip):
		out.append("%s: imitates '%s', whose clip '%s' is not in the rig of %s" % [move.id, move.imitates, model.clip, actor_id])
	elif _of_kind(Marks.read(tree.get_animation(model.clip)), &"hitbox_on").is_empty():
		out.append("%s: imitates '%s', which has no hitbox_on: there is no blow whose rim to wear" % [move.id, move.imitates])


# check_actor, also noting in `reached` (move id -> true) every move it checked, and in `paired` (pair id -> true)
# every pair.
func _check_actor(def: ActorDef, reached: Dictionary, paired: Dictionary) -> PackedStringArray:
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
			_check_imitated(move, tree, move_ids, id, out)
			queue.append_array(_moves_after(move, anim, move_ids, def))
	_check_chain(def, tree, move_ids, out)
	out.append_array(_check_combos(def, tree, move_ids))
	for pair in _pairs_of(def):
		paired[String(pair.id)] = true
		var clips: Array[Animation] = []
		for role in [&"lead_move", &"follow_move"]:
			var move: MoveData = Registry.fetch(&"moves", pair.get(role)) as MoveData if move_ids.has(String(pair.get(role))) else null
			if move != null and tree.has_animation(move.clip):
				clips.append(tree.get_animation(move.clip))
		if clips.size() == 2:  # a move or a clip that is missing has been reported above
			out.append_array(check_pair(pair, clips[0], clips[1]))
	rig.free()
	return out
