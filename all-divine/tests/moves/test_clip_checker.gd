extends TestCase
## The clip checker: the rules a move's clip must keep, run on fixtures built in code, then on the real data.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const LIB := "res://assets/anim/abarax/library.tres"
const BAD_DATA := "res://tests/fixtures/moves/bad_data"
const REACH_DATA := "res://tests/fixtures/moves/reach_data"
const PAIR_DATA := "res://tests/fixtures/moves/pair_data"
const FINISHER := "res://data/pairs/finisher_open_hand.tres"
const HITBOXES: PackedStringArray = ["palm_l", "palm_r"]
const MOVES: PackedStringArray = ["palm_jab", "palm_cross", "dodge_roll"]
## The bones of Abarax's rig that an `fx` mark may name (a few of them).
const BONES: PackedStringArray = ["hand_l", "hand_r", "Head"]
## The args of an sfx and an fx mark that name a cue and an effect the data has.
const SFX := {"name": &"palm_whoosh"}
const FX := {"name": &"palm_trail"}


func after_each() -> void:
	Registry.scan()


# --- fixtures ---

func _m(frame: int, kind: StringName, args := {}) -> Dictionary:
	return {"time": Marks.time_of(frame), "kind": kind, "args": args}


# A clip `frames` long (at 60 Hz) with `marks`, played stepped at `step_fps` (0: smooth).
func _anim(frames: int, step_fps: int, marks: Array) -> Animation:
	var a := Animation.new()
	a.length = Marks.time_of(frames)
	a.set_meta("step_fps", step_fps)
	Marks.write(a, marks)
	return a


# A HitProfile with the given hit-stop and perilous kind.
func _profile(hitstop := 3, perilous := HitProfile.Perilous.NONE) -> HitProfile:
	var p := HitProfile.new()
	p.hitstop_frames = hitstop
	p.perilous = perilous
	return p


# A move of `kind`. An attack comes with the one profile, palm, that the jab's hitbox_on names.
func _move(id: StringName, kind: MoveData.Kind) -> MoveData:
	var move := MoveData.new()
	move.id = id
	move.kind = kind
	move.clip = id
	if kind == MoveData.Kind.ATTACK:
		move.hits = {&"palm": _profile()}
	return move


# The jab of the F0 table (the hit-stop is the profile's now), with `without` kinds left out and `extra`
# marks added.
func _jab_marks(without: Array = [], extra: Array = []) -> Array:
	var marks := [
		_m(5, &"sfx", {"name": &"palm_whoosh"}),
		_m(10, &"hitbox_on", {"id": &"palm_l", "profile": &"palm"}),
		_m(10, &"fx", {"name": &"palm_trail"}),
		_m(15, &"hitbox_off", {"id": &"palm_l"}),
		_m(15, &"cancel_open", {"into": {&"palm": &"palm_cross"}}),
		_m(20, &"recovery"),
		_m(20, &"cancel_open", {"into": {&"palm": &"palm_cross", &"dodge": &"dodge_roll"}}),
	]
	return marks.filter(func(m: Dictionary) -> bool: return not without.has(m["kind"])) + extra


func _roll_marks(without: Array = [], extra: Array = []) -> Array:
	var marks := [
		_m(0, &"sfx", {"name": &"roll_cloth"}),
		_m(3, &"iframes_on"),
		_m(14, &"fx", {"name": &"roll_dust"}),
		_m(14, &"sfx", {"name": &"roll_land"}),
		_m(16, &"iframes_off"),
		_m(20, &"recovery"),
		_m(22, &"cancel_open", {"into": {&"palm": &"palm_jab", &"dodge": &"dodge_roll"}}),
	]
	return marks.filter(func(m: Dictionary) -> bool: return not without.has(m["kind"])) + extra


func _jab(marks: Array = _jab_marks()) -> PackedStringArray:
	return ClipChecker.new().check_move(_move(&"palm_jab", MoveData.Kind.ATTACK), _anim(35, 12, marks), HITBOXES, MOVES)


# check_move for `move` on a clip with `marks` (smooth, 60 frames), as an actor of `team` would play it.
func _check(move: MoveData, marks: Array, team := ActorDef.Team.PLAYER) -> PackedStringArray:
	return ClipChecker.new().check_move(move, _anim(60, 0, marks), HITBOXES, MOVES, team)


# The marks of an attack whose hitbox is on at frame `on` (it carries the profile palm) and that has a tell
# of `tell_kind` at frame `tell_at` (-1: none).
func _attack_marks(on: int, tell_at := -1, tell_kind := &"glint") -> Array:
	var marks := [
		_m(0, &"sfx", {"name": &"palm_whoosh"}),
		_m(0, &"fx", {"name": &"palm_trail"}),
		_m(on, &"hitbox_on", {"id": &"palm_l", "profile": &"palm"}),
		_m(on + 5, &"hitbox_off", {"id": &"palm_l"}),
		_m(on + 5, &"cancel_open", {"into": {&"palm": &"palm_cross"}}),
		_m(on + 10, &"recovery"),
	]
	if tell_at >= 0:
		marks.append(_m(tell_at, &"tell", {"kind": tell_kind}))
	return marks


func _roll(marks: Array = _roll_marks()) -> PackedStringArray:
	return ClipChecker.new().check_move(_move(&"dodge_roll", MoveData.Kind.DODGE), _anim(30, 0, marks), HITBOXES, MOVES)


# True if some problem contains every one of `fragments`.
func _has_problem(problems: PackedStringArray, fragments: Array) -> bool:
	for problem in problems:
		var all := true
		for fragment: String in fragments:
			all = all and problem.contains(fragment)
		if all:
			return true
	return false


# A rig scene like Abarax's, but with the library `clips` ({name: Animation}) in its AnimationTree.
func _rig_with(clips: Dictionary) -> PackedScene:
	var rig := (load(RIG) as PackedScene).instantiate()
	var library := AnimationLibrary.new()
	for clip_name: String in clips:
		library.add_animation(clip_name, clips[clip_name])
	var tree := rig.get_node("AnimationTree") as AnimationTree
	tree.remove_animation_library(&"")
	tree.add_animation_library(&"", library)
	var scene := PackedScene.new()
	assert_eq(scene.pack(rig), OK)
	rig.free()
	return scene


# A clip that holds the skeleton's rest pose for its whole length (ruling P2): what "T-pose" means here.
func _rest_pose_clip(length: float) -> Animation:
	var scene := load(RIG) as PackedScene
	var rig := scene.instantiate()
	var skeleton := rig.get_node("Model").find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var a := Animation.new()
	a.length = length
	for bone in skeleton.get_bone_count():
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Model/%s:%s" % [rig.get_node("Model").get_path_to(skeleton), skeleton.get_bone_name(bone)]))
		a.rotation_track_insert_key(t, 0.0, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
		a.rotation_track_insert_key(t, length, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
	rig.free()
	return a


# The real clips under the names the checker asks for, so only the one under test can be wrong.
func _real_clips() -> Dictionary:
	var library := load(LIB) as AnimationLibrary
	var clips := {}
	for n in library.get_animation_list():
		clips[String(n)] = library.get_animation(n)
	return clips


func _actor(rig: PackedScene, moveset := {}, required := PackedStringArray(["idle", "walk", "jog", "sprint"])) -> ActorDef:
	var def := ActorDef.new()
	def.id = &"fixture"
	def.rig_scene = rig
	def.moveset = moveset
	def.required_clips = required
	return def


# --- the rules, one by one ---

func test_valid_attack_has_no_problems() -> void:
	assert_eq(_jab(), PackedStringArray())


func test_valid_dodge_has_no_problems() -> void:
	assert_eq(_roll(), PackedStringArray())


func test_hitbox_never_turned_off_is_reported() -> void:
	var problems := _jab(_jab_marks([&"hitbox_off"]))
	assert_true(_has_problem(problems, ["never off", "palm_l"]), "\n".join(problems))


func test_hitbox_turned_off_before_it_is_on_is_reported() -> void:
	var marks := _jab_marks([&"hitbox_on", &"hitbox_off"], [_m(15, &"hitbox_on", {"id": &"palm_l"}), _m(10, &"hitbox_off", {"id": &"palm_l"})])
	var problems := _jab(marks)
	assert_true(_has_problem(problems, ["palm_l", "before"]), "\n".join(problems))


func test_hitbox_turned_on_twice_is_reported() -> void:
	var problems := _jab(_jab_marks([], [_m(12, &"hitbox_on", {"id": &"palm_l"})]))
	assert_false(problems.is_empty())
	assert_true(_has_problem(problems, ["palm_l", "already on"]), "\n".join(problems))


func test_each_hitbox_is_judged_on_its_own() -> void:
	# palm_r goes on and never off, while palm_l is fine.
	var problems := _jab(_jab_marks([], [_m(10, &"hitbox_on", {"id": &"palm_r", "profile": &"palm"})]))
	assert_true(_has_problem(problems, ["never off", "palm_r"]), "\n".join(problems))
	assert_false(_has_problem(problems, ["never off", "palm_l"]), "\n".join(problems))


func test_two_hits_by_one_hitbox_are_fine() -> void:
	var marks := _jab_marks([&"recovery"], [_m(25, &"hitbox_on", {"id": &"palm_l", "profile": &"palm"}), _m(30, &"hitbox_off", {"id": &"palm_l"}), _m(30, &"recovery")])
	assert_eq(_jab(marks), PackedStringArray(), "on, off, on, off, and the recovery after the last off")


func test_an_attack_with_no_hitbox_is_reported() -> void:
	var problems := _jab(_jab_marks([&"hitbox_on", &"hitbox_off"]))
	assert_true(_has_problem(problems, ["no hitbox_on"]), "\n".join(problems))


func test_hitbox_that_the_rig_does_not_have_is_reported() -> void:
	var marks := _jab_marks([&"hitbox_on", &"hitbox_off"], [_m(10, &"hitbox_on", {"id": &"palm_x", "profile": &"palm"}), _m(15, &"hitbox_off", {"id": &"palm_x"})])
	var problems := _jab(marks)
	assert_true(_has_problem(problems, ["palm_x", "rig"]), "\n".join(problems))


func test_hitbox_mark_without_an_id_is_reported() -> void:
	var problems := _jab(_jab_marks([&"hitbox_on"], [_m(10, &"hitbox_on")]))
	assert_true(_has_problem(problems, ["hitbox_on", "no id"]), "\n".join(problems))


func test_attack_without_a_cancel_window_is_reported() -> void:
	var problems := _jab(_jab_marks([&"cancel_open"]))
	assert_true(_has_problem(problems, ["cancel_open"]), "\n".join(problems))


func test_attack_without_recovery_is_reported() -> void:
	var problems := _jab(_jab_marks([&"recovery"]))
	assert_true(_has_problem(problems, ["recovery"]), "\n".join(problems))


func test_attack_with_two_recoveries_is_reported() -> void:
	var problems := _jab(_jab_marks([], [_m(25, &"recovery")]))
	assert_true(_has_problem(problems, ["recovery", "2"]), "\n".join(problems))


func test_recovery_before_the_last_hitbox_off_is_reported() -> void:
	var problems := _jab(_jab_marks([&"recovery"], [_m(15, &"recovery")]))
	assert_eq(problems, PackedStringArray(), "a recovery on the frame of hitbox_off is allowed: at or after")
	problems = _jab(_jab_marks([&"recovery"], [_m(10, &"recovery")]))
	assert_true(_has_problem(problems, ["recovery", "hitbox_off"]), "\n".join(problems))


func test_dodge_without_iframes_is_reported() -> void:
	var problems := _roll(_roll_marks([&"iframes_on", &"iframes_off"]))
	assert_true(_has_problem(problems, ["iframes"]), "\n".join(problems))


func test_iframes_never_turned_off_are_reported() -> void:
	var problems := _roll(_roll_marks([&"iframes_off"]))
	assert_true(_has_problem(problems, ["iframes", "never off"]), "\n".join(problems))


func test_iframes_off_before_on_is_reported() -> void:
	var problems := _roll(_roll_marks([&"iframes_on", &"iframes_off"], [_m(16, &"iframes_on"), _m(3, &"iframes_off")]))
	assert_true(_has_problem(problems, ["iframes", "before"]), "\n".join(problems))


func test_an_attack_needs_no_iframes_and_a_dodge_needs_no_hitbox() -> void:
	assert_eq(_jab(), PackedStringArray())
	assert_eq(_roll(), PackedStringArray())


func test_move_without_sfx_is_reported() -> void:
	var problems := _jab(_jab_marks([&"sfx"]))
	assert_true(_has_problem(problems, ["sfx"]), "\n".join(problems))
	problems = _roll(_roll_marks([&"sfx"]))
	assert_true(_has_problem(problems, ["sfx"]), "\n".join(problems))


func test_move_without_fx_is_reported() -> void:
	var problems := _jab(_jab_marks([&"fx"]))
	assert_true(_has_problem(problems, ["fx"]), "\n".join(problems))
	problems = _roll(_roll_marks([&"fx"]))
	assert_true(_has_problem(problems, ["fx"]), "\n".join(problems))


func test_unknown_fx_or_sfx_name_is_reported() -> void:
	# Every fx names an FxDef in data/fx/ (the Registry kind fx) and every sfx a SoundCue in data/sounds/ (sounds).
	var problems := _jab(_jab_marks([], [_m(25, &"fx", {"name": &"no_such_fx"}), _m(30, &"sfx", {"name": &"no_such_cue"})]))
	assert_true(_has_problem(problems, ["fx", "f25", "no_such_fx"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["sfx", "f30", "no_such_cue"]), "\n".join(problems))
	assert_eq(problems.size(), 2, "only those two: \n" + "\n".join(problems))
	# The two kinds are separate: a sound is not an effect, nor an effect a sound.
	problems = _jab(_jab_marks([], [_m(25, &"fx", {"name": &"impact_palm"}), _m(30, &"sfx", {"name": &"palm_trail"})]))
	assert_true(_has_problem(problems, ["fx", "impact_palm"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["sfx", "palm_trail"]), "\n".join(problems))
	# A mark that names nothing is as wrong.
	problems = _jab(_jab_marks([], [_m(25, &"fx"), _m(30, &"sfx", {"name": &""})]))
	assert_true(_has_problem(problems, ["fx", "f25", "no name"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["sfx", "f30", "no name"]), "\n".join(problems))
	assert_eq(_jab(_jab_marks([], [_m(25, &"fx", {"name": &"hit_spark"}), _m(30, &"sfx", {"name": &"impact_heavy"})])), PackedStringArray(), "real names pass")


func test_an_fx_mark_that_names_a_bone_the_rig_does_not_have_is_reported() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	var checker := ClipChecker.new()
	var good := _jab_marks([], [_m(25, &"fx", {"name": &"palm_trail", "bone": &"hand_r"})])
	assert_eq(checker.check_move(move, _anim(35, 12, good), HITBOXES, MOVES, ActorDef.Team.PLAYER, BONES), PackedStringArray())
	var bad := _jab_marks([], [_m(25, &"fx", {"name": &"palm_trail", "bone": &"hand_x"})])
	var problems := checker.check_move(move, _anim(35, 12, bad), HITBOXES, MOVES, ActorDef.Team.PLAYER, BONES)
	assert_true(_has_problem(problems, ["fx", "f25", "hand_x", "bone"]), "\n".join(problems))
	assert_eq(checker.check_move(move, _anim(35, 12, bad), HITBOXES, MOVES), PackedStringArray(), "with no bones to go by, none is checked")


func test_other_moves_need_sfx_and_fx_too() -> void:
	var move := _move(&"gesture", MoveData.Kind.OTHER)
	var checker := ClipChecker.new()
	assert_true(_has_problem(checker.check_move(move, _anim(30, 0, []), HITBOXES, MOVES), ["sfx"]))
	assert_eq(checker.check_move(move, _anim(30, 0, [_m(0, &"sfx", SFX), _m(0, &"fx", FX)]), HITBOXES, MOVES), PackedStringArray())


func test_mark_off_the_step_grid_is_reported() -> void:
	# Stepped at 12 fps the clip shows a new pose every 5 frames; a mark at frame 12 would fire between poses.
	var problems := _jab(_jab_marks([], [_m(12, &"fx", FX)]))
	assert_true(_has_problem(problems, ["12 fps step grid", "f12"]), "\n".join(problems))
	problems = _jab(_jab_marks([], [_m(25, &"fx", FX), _m(30, &"fx", FX)]))
	assert_eq(problems, PackedStringArray(), "frames 25 and 30 are on the grid")


func test_a_smooth_clip_has_no_grid() -> void:
	assert_eq(_roll(_roll_marks([], [_m(7, &"fx", FX)])), PackedStringArray())


func test_the_grid_is_the_clips_own_step_rate() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	var marks := _jab_marks([], [_m(2, &"fx", FX)])
	var checker := ClipChecker.new()
	assert_true(_has_problem(checker.check_move(move, _anim(35, 12, marks), HITBOXES, MOVES), ["12 fps step grid"]))
	assert_true(_has_problem(checker.check_move(move, _anim(35, 24, marks), HITBOXES, MOVES), ["24 fps step grid"]), "f2 is on neither grid, f5 is on both")
	assert_eq(checker.check_move(move, _anim(35, 0, marks), HITBOXES, MOVES), PackedStringArray())


func test_a_mark_outside_the_clip_is_reported() -> void:
	var problems := _jab(_jab_marks([], [_m(40, &"fx", FX)]))
	assert_true(_has_problem(problems, ["f40", "outside"]), "\n".join(problems))
	var early := _anim(35, 0, _jab_marks([], [{"time": -0.05, "kind": &"fx", "args": FX}]))
	problems = ClipChecker.new().check_move(_move(&"palm_jab", MoveData.Kind.ATTACK), early, HITBOXES, MOVES)
	assert_true(_has_problem(problems, ["outside"]), "\n".join(problems))


func test_a_mark_on_the_last_frame_is_inside() -> void:
	# The clip stores 0.583333 for 35 frames; the mark at frame 35 is 3e-7 s later and still counts as inside.
	var a := _anim(35, 12, _jab_marks([], [_m(35, &"fx", FX)]))
	a.length = 0.583333
	assert_eq(ClipChecker.new().check_move(_move(&"palm_jab", MoveData.Kind.ATTACK), a, HITBOXES, MOVES), PackedStringArray())


func test_cancel_into_unknown_move_is_reported() -> void:
	var problems := _jab(_jab_marks([&"cancel_open"], [_m(20, &"cancel_open", {"into": {&"palm": &"palm_hook"}}), _m(15, &"cancel_open", {"into": {&"palm": &"palm_cross"}})]))
	assert_true(_has_problem(problems, ["unknown move", "palm_hook"]), "\n".join(problems))
	assert_eq(problems.size(), 1, "only the hook is wrong: \n" + "\n".join(problems))


func test_cancel_open_without_a_target_is_reported() -> void:
	var problems := _jab(_jab_marks([&"cancel_open"], [_m(15, &"cancel_open")]))
	assert_true(_has_problem(problems, ["cancel_open", "into"]), "\n".join(problems))


func test_an_unknown_mark_kind_is_reported() -> void:
	var problems := _jab(_jab_marks([], [_m(10, &"hitbox_onn", {"id": &"palm_l"})]))
	assert_true(_has_problem(problems, ["hitbox_onn", "kind"]), "\n".join(problems))


func test_a_hitstop_mark_is_an_unknown_kind_now() -> void:
	# F0 had a hitstop mark. Hit-stop is the HitProfile's now, so an old clip that still has one is wrong.
	var problems := _jab(_jab_marks([], [_m(10, &"hitstop", {"frames": 3})]))
	assert_true(_has_problem(problems, ["hitstop", "kind", "f10"]), "\n".join(problems))


func test_every_problem_starts_with_the_move_id() -> void:
	var problems := _jab(_jab_marks([&"sfx", &"hitbox_off"]))
	assert_true(problems.size() >= 2)
	for problem in problems:
		assert_true(problem.begins_with("palm_jab: "), problem)


func test_the_problems_name_the_frame() -> void:
	var problems := _jab(_jab_marks([], [_m(10, &"hitbox_on")]))
	assert_true(_has_problem(problems, ["hitbox_on", "no id", "f10"]), "\n".join(problems))


# --- hit profiles ---

func test_hitbox_profile_must_exist() -> void:
	var marks := _jab_marks([&"hitbox_on"], [_m(10, &"hitbox_on", {"id": &"palm_l", "profile": &"slam"})])
	var problems := _jab(marks)
	assert_true(_has_problem(problems, ["unknown profile", "slam", "f10"]), "\n".join(problems))
	assert_eq(problems.size(), 1, "\n".join(problems))


func test_hitbox_without_a_profile_is_reported() -> void:
	var problems := _jab(_jab_marks([&"hitbox_on"], [_m(10, &"hitbox_on", {"id": &"palm_l"})]))
	assert_true(_has_problem(problems, ["hitbox_on", "no profile", "f10"]), "\n".join(problems))


func test_every_hitbox_of_an_attack_names_one_of_its_profiles() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	move.hits = {&"palm": _profile(), &"heavy": _profile(6)}
	var marks := _jab_marks([&"hitbox_on"], [_m(10, &"hitbox_on", {"id": &"palm_l", "profile": &"heavy"})])
	assert_eq(_check(move, marks), PackedStringArray())


func test_attack_without_hits_is_reported() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	move.hits = {}
	var problems := _check(move, _jab_marks())
	assert_true(_has_problem(problems, ["no hits"]), "\n".join(problems))
	assert_eq(problems.size(), 1, "the hitbox's profile is not also called unknown: \n" + "\n".join(problems))


func test_hits_of_other_moves_are_not_required() -> void:
	assert_eq(_roll(), PackedStringArray(), "the roll has no hits and needs none")


func test_a_hit_profiles_hitstop_must_be_three_to_six_frames() -> void:
	for frames in [2, 7, 0, 12]:
		var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
		move.hits = {&"palm": _profile(frames)}
		var problems := _check(move, _jab_marks())
		assert_true(_has_problem(problems, ["palm_jab", "'palm'", "hitstop_frames", str(frames)]), "frames %d: %s" % [frames, "\n".join(problems)])
	for frames in [3, 4, 5, 6]:
		var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
		move.hits = {&"palm": _profile(frames)}
		assert_eq(_check(move, _jab_marks()), PackedStringArray(), "frames %d" % frames)


func test_every_profile_is_held_to_the_hitstop_range_even_one_no_hitbox_uses() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	move.hits = {&"palm": _profile(), &"spare": _profile(9)}
	assert_true(_has_problem(_check(move, _jab_marks()), ["'spare'", "hitstop_frames", "9"]))


func test_a_hits_entry_that_is_not_a_hit_profile_is_reported() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	move.hits = {&"palm": _profile(), &"odd": "not a profile"}
	var problems := _check(move, _jab_marks())
	assert_true(_has_problem(problems, ["'odd'", "not a HitProfile"]), "\n".join(problems))
	assert_eq(problems.size(), 1, "\n".join(problems))


# --- windows, tells and charge holds ---

func test_unpaired_parry_window_is_reported() -> void:
	# (The jab is stepped at 12 fps, so these marks sit on its 5-frame grid.)
	for window in ["parry", "guard", "airborne", "hyperarmour"]:
		var on := StringName(window + "_on")
		var off := StringName(window + "_off")
		var problems := _jab(_jab_marks([], [_m(5, on)]))
		assert_true(_has_problem(problems, [window, "never off", "f5"]), "%s: %s" % [window, "\n".join(problems)])
		problems = _jab(_jab_marks([], [_m(5, off)]))
		assert_true(_has_problem(problems, [window, "before", "f5"]), "%s: %s" % [window, "\n".join(problems)])
		problems = _jab(_jab_marks([], [_m(0, on), _m(5, off), _m(30, on)]))
		assert_true(_has_problem(problems, [window, "never off", "f30"]), "%s: %s" % [window, "\n".join(problems)])
		assert_eq(_jab(_jab_marks([], [_m(5, on), _m(10, off)])), PackedStringArray(), "%s: on then off is fine" % window)


func test_each_window_kind_is_judged_on_its_own() -> void:
	var problems := _jab(_jab_marks([], [_m(5, &"parry_on"), _m(10, &"guard_off")]))
	assert_true(_has_problem(problems, ["parry", "never off"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["guard", "before"]), "\n".join(problems))


func test_reaction_without_recovery_is_reported() -> void:
	var move := _move(&"flinch", MoveData.Kind.REACTION)
	var marks := [_m(0, &"sfx", SFX), _m(0, &"fx", FX)]
	var problems := _check(move, marks)
	assert_true(_has_problem(problems, ["flinch", "recovery"]), "\n".join(problems))
	assert_eq(_check(move, marks + [_m(12, &"recovery")]), PackedStringArray())
	problems = _check(move, marks + [_m(12, &"recovery"), _m(14, &"recovery")])
	assert_true(_has_problem(problems, ["recovery", "2"]), "\n".join(problems))


func test_a_death_needs_no_recovery() -> void:
	var death := _move(&"death", MoveData.Kind.REACTION)
	assert_eq(_check(death, [_m(0, &"sfx", SFX), _m(0, &"fx", FX)]), PackedStringArray())


func test_a_reaction_needs_no_hits_or_hitbox() -> void:
	var move := _move(&"stagger", MoveData.Kind.REACTION)
	assert_eq(_check(move, [_m(0, &"sfx", SFX), _m(0, &"fx", FX), _m(20, &"recovery")]), PackedStringArray())


func test_tell_kind_must_be_glint_or_perilous() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	for kind in [&"glint", &"perilous"]:
		assert_eq(_check(move, _attack_marks(20, 0, kind)), PackedStringArray(), str(kind))
	var problems := _check(move, _attack_marks(20, 0, &"flash"))
	assert_true(_has_problem(problems, ["tell", "kind", "flash", "f0"]), "\n".join(problems))
	problems = _check(move, _attack_marks(20) + [_m(0, &"tell")])
	assert_true(_has_problem(problems, ["tell", "no kind", "f0"]), "\n".join(problems))


func test_enemy_attack_needs_a_tell_twelve_frames_ahead() -> void:
	var move := _move(&"knuckle_jab", MoveData.Kind.ATTACK)
	var enemy := ActorDef.Team.ENEMY
	var problems := _check(move, _attack_marks(15, 10), enemy)
	assert_true(_has_problem(problems, ["knuckle_jab", "tell", "12", "f15"]), "tell at f10, hitbox_on at f15: " + "\n".join(problems))
	assert_true(_has_problem(_check(move, _attack_marks(20), enemy), ["tell"]), "no tell at all")
	assert_true(_has_problem(_check(move, _attack_marks(20, 25), enemy), ["tell"]), "a tell after the blow is no warning")
	assert_true(_has_problem(_check(move, _attack_marks(17, 6), enemy), ["tell"]), "11 frames ahead is not enough")
	assert_eq(_check(move, _attack_marks(17, 5), enemy), PackedStringArray(), "12 frames ahead is")
	assert_eq(_check(move, _attack_marks(20, 0, &"perilous"), enemy), PackedStringArray(), "either kind of tell warns")


func test_the_tell_is_ahead_of_the_first_hitbox() -> void:
	# A second blow later in the clip is not warned separately: the tell is ahead of the first hitbox_on.
	var move := _move(&"knuckle_jab", MoveData.Kind.ATTACK)
	var marks := _attack_marks(20, 5) + [_m(26, &"hitbox_on", {"id": &"palm_r", "profile": &"palm"}), _m(28, &"hitbox_off", {"id": &"palm_r"})]
	assert_eq(_check(move, marks, ActorDef.Team.ENEMY), PackedStringArray())


func test_the_player_needs_no_tell() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	assert_eq(_check(move, _attack_marks(5)), PackedStringArray())
	assert_eq(_check(move, _attack_marks(5), ActorDef.Team.PLAYER), PackedStringArray())


func test_only_attacks_of_enemies_need_a_tell() -> void:
	var feint := _move(&"knuckle_feint", MoveData.Kind.OTHER)
	assert_eq(_check(feint, [_m(0, &"sfx", SFX), _m(0, &"fx", FX)], ActorDef.Team.ENEMY), PackedStringArray())


func test_perilous_hit_needs_a_perilous_tell() -> void:
	var enemy := ActorDef.Team.ENEMY
	for perilous in [HitProfile.Perilous.SWEEP, HitProfile.Perilous.THRUST, HitProfile.Perilous.GRAB]:
		var move := _move(&"knuckle_sweep", MoveData.Kind.ATTACK)
		move.hits = {&"palm": _profile(3, perilous)}
		var problems := _check(move, _attack_marks(20, 0, &"glint"), enemy)
		assert_true(_has_problem(problems, ["knuckle_sweep", "perilous", "tell"]), "perilous %d: %s" % [perilous, "\n".join(problems)])
		assert_eq(problems.size(), 1, "the glint is a tell ahead of the blow; only the kind is wrong: \n" + "\n".join(problems))
		assert_eq(_check(move, _attack_marks(20, 0, &"perilous"), enemy), PackedStringArray(), "perilous %d with its tell" % perilous)


func test_a_perilous_tell_on_an_ordinary_move_is_fine() -> void:
	var move := _move(&"knuckle_jab", MoveData.Kind.ATTACK)
	assert_eq(_check(move, _attack_marks(20, 0, &"perilous"), ActorDef.Team.ENEMY), PackedStringArray())


func test_charge_hold_is_only_in_an_attack_and_names_a_profile_it_has() -> void:
	var hold := {"action": &"palm", "frames": 12, "profile": &"heavy"}
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	move.hits = {&"palm": _profile(), &"heavy": _profile(6)}
	assert_eq(_check(move, _attack_marks(20) + [_m(10, &"charge_hold", hold)]), PackedStringArray())
	var problems := _check(move, _attack_marks(20) + [_m(10, &"charge_hold", {"action": &"palm", "frames": 12, "profile": &"slam"})])
	assert_true(_has_problem(problems, ["charge_hold", "unknown profile", "slam", "f10"]), "\n".join(problems))
	problems = _check(move, _attack_marks(20) + [_m(10, &"charge_hold", {"action": &"palm", "frames": 12})])
	assert_true(_has_problem(problems, ["charge_hold", "no profile", "f10"]), "\n".join(problems))
	for kind in [MoveData.Kind.DODGE, MoveData.Kind.OTHER, MoveData.Kind.REACTION]:
		var other := _move(&"gesture", kind)
		problems = _check(other, [_m(0, &"sfx", SFX), _m(0, &"fx", FX), _m(10, &"charge_hold", hold)])
		assert_true(_has_problem(problems, ["gesture", "charge_hold", "attack", "f10"]), "kind %d: %s" % [kind, "\n".join(problems)])


func test_a_neutral_variant_must_be_a_move() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	move.neutral_variant = &"palm_cross"
	assert_eq(_check(move, _jab_marks()), PackedStringArray())
	move.neutral_variant = &"palm_hook"
	var problems := _check(move, _jab_marks())
	assert_true(_has_problem(problems, ["palm_jab", "neutral_variant", "unknown move", "palm_hook"]), "\n".join(problems))


# --- the T-pose rule, on clips and on an actor ---

func test_a_clip_that_holds_the_rest_pose_is_a_t_pose() -> void:
	var skeleton := _skeleton()
	assert_true(ClipChecker.is_t_pose(_rest_pose_clip(1.0), skeleton))
	skeleton.free()


func test_the_real_required_clips_are_not_t_poses() -> void:
	var skeleton := _skeleton()
	var library := load(LIB) as AnimationLibrary
	for n in ["idle", "walk", "jog", "sprint"]:
		assert_false(ClipChecker.is_t_pose(library.get_animation(n), skeleton), n)
	skeleton.free()


func test_one_bone_leaving_the_rest_pose_by_more_than_a_degree_is_enough() -> void:
	var skeleton := _skeleton()
	var a := _rest_pose_clip(1.0)
	var bone := skeleton.find_bone("upperarm_l")
	var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var track := -1
	for i in a.get_track_count():
		if a.track_get_path(i).get_concatenated_subnames() == "upperarm_l":
			track = i
	assert_ne(track, -1)
	a.rotation_track_insert_key(track, 0.5, rest * Quaternion(Vector3.FORWARD, deg_to_rad(0.9)))
	assert_true(ClipChecker.is_t_pose(a, skeleton), "0.9 degrees is still the rest pose")
	a.rotation_track_insert_key(track, 0.5, rest * Quaternion(Vector3.FORWARD, deg_to_rad(1.5)))
	assert_false(ClipChecker.is_t_pose(a, skeleton), "1.5 degrees is not")
	# And the same rotation written as the negated quaternion (the same orientation) counts as no change.
	a.rotation_track_insert_key(track, 0.5, Quaternion(-rest.x, -rest.y, -rest.z, -rest.w))
	assert_true(ClipChecker.is_t_pose(a, skeleton), "q and -q are one rotation")
	skeleton.free()


func test_t_pose_required_clip_is_reported() -> void:
	var clips := _real_clips()
	clips["idle"] = _rest_pose_clip(1.0)
	var problems := ClipChecker.new().check_actor(_actor(_rig_with(clips)))
	assert_true(_has_problem(problems, ["fixture", "idle", "T-pose"]), "\n".join(problems))
	assert_eq(problems.size(), 1, "walk, jog and sprint are fine: \n" + "\n".join(problems))


func test_a_t_pose_that_is_not_required_is_not_reported() -> void:
	var clips := _real_clips()
	clips["emote"] = _rest_pose_clip(1.0)
	assert_eq(ClipChecker.new().check_actor(_actor(_rig_with(clips))), PackedStringArray())


func test_missing_required_clip_is_reported() -> void:
	var clips := _real_clips()
	clips.erase("sprint")
	var problems := ClipChecker.new().check_actor(_actor(_rig_with(clips)))
	assert_true(_has_problem(problems, ["fixture", "sprint", "missing"]), "\n".join(problems))


func test_an_actor_without_a_rig_is_reported() -> void:
	var problems := ClipChecker.new().check_actor(_actor(null))
	assert_true(_has_problem(problems, ["fixture", "rig_scene"]), "\n".join(problems))


# --- an actor's moves ---

func test_an_actors_moveset_must_name_moves_that_exist() -> void:
	var problems := ClipChecker.new().check_actor(_actor(load(RIG), {&"palm": &"no_such_move"}))
	assert_true(_has_problem(problems, ["fixture", "no_such_move", "unknown move"]), "\n".join(problems))


func test_an_actors_move_and_the_moves_it_cancels_into_are_checked() -> void:
	# The real jab, reached through the moveset, cancels into the cross and the roll: all three are checked,
	# and with the real data nothing is wrong.
	assert_eq(ClipChecker.new().check_actor(_actor(load(RIG), {&"palm": &"palm_jab"})), PackedStringArray())


func test_a_move_whose_clip_the_rig_lacks_is_reported() -> void:
	var clips := _real_clips()
	clips.erase("palm_cross")
	var problems := ClipChecker.new().check_actor(_actor(_rig_with(clips), {&"palm": &"palm_jab"}))
	assert_true(_has_problem(problems, ["palm_cross", "clip", "rig"]), "\n".join(problems))


func test_the_team_of_an_actor_decides_whether_its_attacks_need_tells() -> void:
	# The real jab and cross, which have no tell: fine for the player, wrong for an enemy.
	var player := ClipChecker.new().check_actor(_actor(load(RIG), {&"palm": &"palm_jab"}))
	assert_eq(player, PackedStringArray())
	var def := _actor(load(RIG), {&"palm": &"palm_jab"})
	def.team = ActorDef.Team.ENEMY
	var problems := ClipChecker.new().check_actor(def)
	assert_true(_has_problem(problems, ["palm_jab", "tell"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["palm_cross", "tell"]), "the cross is reached by the jab's cancel window: \n" + "\n".join(problems))


func test_an_actors_reactions_must_name_moves_that_exist() -> void:
	var def := _actor(load(RIG), {&"palm": &"palm_jab"})
	def.reactions = {&"flinch": &"no_such_reaction"}
	var problems := ClipChecker.new().check_actor(def)
	assert_true(_has_problem(problems, ["fixture", "reaction", "flinch", "unknown move", "no_such_reaction"]), "\n".join(problems))


func test_check_all_follows_reactions_and_neutral_variants() -> void:
	# tests/fixtures/moves/reach_data: an actor whose moveset starts `start` and whose reaction `flinch`
	# is `answer`; `start`'s neutral variant is `variant`; `stray` is named by nothing. Reached moves are
	# checked (they are OTHER moves on the idle clip without marks, so each reports its missing sfx);
	# unreached ones are reported as such.
	assert_eq(Registry.scan(REACH_DATA), PackedStringArray())
	var problems := ClipChecker.new().check_all()
	for id in ["start", "answer", "variant"]:
		assert_true(_has_problem(problems, [id, "has no sfx"]), "%s is checked: \n%s" % [id, "\n".join(problems)])
		assert_false(_has_problem(problems, [id, "no actor"]), "%s is reached: \n%s" % [id, "\n".join(problems)])
	assert_true(_has_problem(problems, ["stray", "no actor"]), "\n".join(problems))
	assert_false(_has_problem(problems, ["stray", "has no sfx"]), "an unreached move is not checked: \n" + "\n".join(problems))


# --- pairs ---

# A pair whose lead is the jab and follow the cross, with one hit `f1` of `hitstop` frames, and `max_length`.
func _pair(hitstop := 4, max_length := 1.5) -> PairedMove:
	var pair := PairedMove.new()
	pair.id = &"fixture_pair"
	pair.lead_move = &"palm_jab"
	pair.follow_move = &"palm_cross"
	pair.max_length = max_length
	pair.hits = {&"f1": _profile(hitstop)}
	return pair


# check_pair for `pair` with a stepped lead clip of `frames` frames and the marks `lead_marks`, and a follow clip
# with `follow_marks`.
func _check_pair(pair: PairedMove, lead_marks: Array, follow_marks := [], frames := 60) -> PackedStringArray:
	return ClipChecker.new().check_pair(pair, _anim(frames, 12, lead_marks), _anim(60, 0, follow_marks))


func test_a_valid_pair_has_no_problems() -> void:
	assert_eq(_check_pair(_pair(), [_m(10, &"pair_hit", {"profile": &"f1"})]), PackedStringArray())


func test_a_pair_hit_must_name_one_of_the_pairs_hits() -> void:
	# Whatever the kind of the move it is in: a pair's moves are not attacks, and their blows are the pair's.
	var problems := _check_pair(_pair(), [_m(10, &"pair_hit", {"profile": &"f9"}), _m(20, &"pair_hit")],
			[_m(30, &"pair_hit", {"profile": &"f8"})])
	assert_true(_has_problem(problems, ["fixture_pair", "pair_hit at f10", "unknown profile 'f9'", "f1"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["fixture_pair", "pair_hit at f20", "no profile"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["fixture_pair", "pair_hit at f30", "unknown profile 'f8'"]), "in the follow clip too: \n" + "\n".join(problems))
	assert_eq(problems.size(), 3, "\n".join(problems))


func test_a_pair_whose_lead_clip_with_its_hit_stop_is_longer_than_its_max_length_is_reported() -> void:
	# Spec 4.4 caps the player's wait, hit-stop included: the lead's clip and the hit-stop of every blow it lands. Two
	# blows of 4 frames (0.133 s) on an 82-frame clip are 1.5 s; on 83 frames, 1.52 s.
	var marks := [_m(10, &"pair_hit", {"profile": &"f1"}), _m(30, &"pair_hit", {"profile": &"f1"})]
	assert_eq(_check_pair(_pair(), marks, [], 82), PackedStringArray(), "1.5 s is not longer")
	var problems := _check_pair(_pair(), marks, [], 83)
	assert_true(_has_problem(problems, ["fixture_pair", "palm_jab", "hit-stop", "1.52 s", "max_length", "1.50 s"]), "\n".join(problems))


func test_a_pairs_hits_are_held_to_the_hitstop_range() -> void:
	var marks := [_m(10, &"pair_hit", {"profile": &"f1"})]
	var problems := _check_pair(_pair(7), marks)
	assert_true(_has_problem(problems, ["fixture_pair", "profile 'f1'", "hitstop_frames 7"]), "\n".join(problems))
	var odd := _pair()
	odd.hits[&"f2"] = MoveData.new()
	problems = _check_pair(odd, marks)
	assert_true(_has_problem(problems, ["fixture_pair", "hits['f2'] is not a HitProfile"]), "\n".join(problems))


func test_an_actors_pairs_and_their_moves_are_checked() -> void:
	var def := _actor(load(RIG), {&"palm": &"palm_jab"})
	def.finisher = load(FINISHER)
	assert_eq(ClipChecker.new().check_actor(def), PackedStringArray(), "the real finisher")
	var short := (load(FINISHER) as PairedMove).duplicate() as PairedMove
	short.hits = short.hits.duplicate()
	short.hits.erase(&"f2")
	def.finisher = short
	var problems := ClipChecker.new().check_actor(def)
	var f2_at := -1  # where the real finisher lands the blow of f2: its clip's marks say
	for m in Marks.read((load(LIB) as AnimationLibrary).get_animation(&"finisher")):
		if m["kind"] == &"pair_hit" and m["args"].get("profile") == &"f2":
			f2_at = Marks.frame_of(m["time"])
	assert_true(f2_at >= 0, "the finisher lands an f2")
	assert_true(_has_problem(problems, ["finisher_open_hand", "pair_hit at f%d" % f2_at, "unknown profile 'f2'"]), "\n".join(problems))
	var lost := _pair()
	lost.lead_move = &"no_such_lead"
	def.finisher = null
	def.grab_pair = lost
	problems = ClipChecker.new().check_actor(def)
	assert_true(_has_problem(problems, ["fixture_pair", "lead_move", "unknown move", "no_such_lead"]), "\n".join(problems))


func test_check_all_reaches_a_pairs_moves_through_the_actors_that_use_it() -> void:
	# tests/fixtures/moves/pair_data: an actor whose finisher is the pair `used` (lead `lead`, follow `follow`), and a
	# pair `stray` (lead `stray_lead`) that no actor uses. Reached moves are checked (OTHER moves on the idle clip
	# without marks, so each reports its missing sfx); the stray pair and its lead are reported as unused.
	assert_eq(Registry.scan(PAIR_DATA), PackedStringArray())
	var problems := ClipChecker.new().check_all()
	for id: String in ["lead", "follow"]:
		assert_true(problems.has(id + ": has no sfx"), "%s is checked: \n%s" % [id, "\n".join(problems)])
		assert_false(Array(problems).any(func(p: String) -> bool: return p.begins_with(id + ": no actor")),
				"%s is reached: \n%s" % [id, "\n".join(problems)])
	assert_true(_has_problem(problems, ["stray_lead", "no actor"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["stray", "no actor uses this pair"]), "\n".join(problems))
	assert_false(_has_problem(problems, ["used:"]), "the used pair is fine: \n" + "\n".join(problems))


# --- the real data ---

func test_real_data_passes() -> void:
	assert_eq(Registry.scan(), PackedStringArray())
	assert_eq(ClipChecker.new().check_all(), PackedStringArray())


func test_real_data_has_the_f0_moves_and_abarax() -> void:
	# Later work adds moves and actors, so this names what must be there and not how many there are.
	var moves := Array(Registry.ids(&"moves"))
	for id in ["dodge_roll", "palm_cross", "palm_hook", "palm_heavy", "palm_jab"]:
		assert_true(moves.has(id), "the move %s" % id)
	assert_true(Array(Registry.ids(&"actors")).has("abarax"), "the actor abarax")


func test_check_all_reports_what_is_wrong_and_the_moves_nobody_can_use() -> void:
	# tests/fixtures/moves/bad_data: an actor whose one move is an attack on the idle clip (no marks at all),
	# and a move that no actor's moveset reaches.
	assert_eq(Registry.scan(BAD_DATA), PackedStringArray())
	var problems := ClipChecker.new().check_all()
	assert_true(_has_problem(problems, ["dull", "no hitbox_on"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["dull", "sfx"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["stray", "no actor"]), "\n".join(problems))
	for problem in problems:
		assert_true(problem.begins_with("dull: ") or problem.begins_with("stray: ") or problem.begins_with("fixture_actor: "), problem)


# --- the command line (tools/clip_check.gd), run as a child Godot ---

func test_the_command_line_says_ok_and_exits_zero() -> void:
	var run := _run_cli([])
	assert_eq(run["code"], 0, "\n".join(run["lines"]))
	var ok := "clip_check: %d moves, %d actors OK" % [Registry.ids(&"moves").size(), Registry.ids(&"actors").size()]
	assert_true(Array(run["lines"]).has(ok), "wanted '%s' in:\n%s" % [ok, "\n".join(run["lines"])])


func test_the_command_line_prints_each_problem_and_exits_one() -> void:
	var run := _run_cli(["--data=" + BAD_DATA])
	var lines: Array = run["lines"]
	assert_eq(run["code"], 1, "\n".join(run["lines"]))
	assert_true(lines.has("clip_check: dull: attack has no hitbox_on"), "\n".join(run["lines"]))
	assert_true(lines.any(func(line: String) -> bool: return line.begins_with("clip_check: stray: no actor")), "\n".join(run["lines"]))
	assert_false(lines.any(func(line: String) -> bool: return line.ends_with("actors OK")), "no OK line after problems")


func test_the_command_line_rejects_what_it_does_not_know() -> void:
	assert_eq(_run_cli(["--bogus"])["code"], 2)


# Runs tools/clip_check.gd in a headless child Godot on this project. Returns {code, lines}.
func _run_cli(args: Array[String]) -> Dictionary:
	var argv := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/clip_check.gd", "--"])
	argv.append_array(PackedStringArray(args))
	var output := []
	var code := OS.execute(OS.get_executable_path(), argv, output, true)
	return {"code": code, "lines": str(output[0]).split("\n")}


func _skeleton() -> Skeleton3D:
	var rig := (load(RIG) as PackedScene).instantiate()
	var skeleton := rig.get_node("Model").find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skeleton.owner = null
	skeleton.get_parent().remove_child(skeleton)
	rig.free()
	return skeleton


func test_the_bone_an_effect_rides_by_its_data_is_checked_against_the_rig() -> void:
	# An fx mark without a bone rides its FxDef's (palm_trail: hand_l), a glint tell the glint's (hand_r) and a perilous
	# tell the perilous rose's (Head): each is a bone the rig must have, as a bone a mark names is.
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	var checker := ClipChecker.new()
	var marks := _jab_marks([], [_m(5, &"tell", {"kind": &"glint"}), _m(15, &"tell", {"kind": &"perilous"})])
	assert_eq(checker.check_move(move, _anim(35, 12, marks), HITBOXES, MOVES, ActorDef.Team.PLAYER, BONES), PackedStringArray(),
			"Abarax's bones have them all")
	var problems := checker.check_move(move, _anim(35, 12, marks), HITBOXES, MOVES, ActorDef.Team.PLAYER, PackedStringArray(["pelvis"]))
	assert_true(_has_problem(problems, ["fx at f10", "hand_l", "palm_trail"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["tell at f5", "hand_r", "glint"]), "\n".join(problems))
	assert_true(_has_problem(problems, ["tell at f15", "Head", "perilous_rose"]), "\n".join(problems))
