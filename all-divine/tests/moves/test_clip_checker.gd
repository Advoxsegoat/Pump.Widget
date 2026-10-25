extends TestCase
## The clip checker: the rules a move's clip must keep, run on fixtures built in code, then on the real data.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const LIB := "res://assets/anim/abarax/library.tres"
const BAD_DATA := "res://tests/fixtures/moves/bad_data"
const HITBOXES: PackedStringArray = ["palm_l", "palm_r"]
const MOVES: PackedStringArray = ["palm_jab", "palm_cross", "dodge_roll"]


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


func _move(id: StringName, kind: MoveData.Kind) -> MoveData:
	var move := MoveData.new()
	move.id = id
	move.kind = kind
	move.clip = id
	return move


# The jab of the F0 table, with `without` kinds left out and `extra` marks added.
func _jab_marks(without: Array = [], extra: Array = []) -> Array:
	var marks := [
		_m(5, &"sfx", {"name": &"palm_whoosh"}),
		_m(10, &"hitbox_on", {"id": &"palm_l"}),
		_m(10, &"fx", {"name": &"palm_trail"}),
		_m(10, &"hitstop", {"frames": 3}),
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
	var problems := _jab(_jab_marks([], [_m(10, &"hitbox_on", {"id": &"palm_r"})]))
	assert_true(_has_problem(problems, ["never off", "palm_r"]), "\n".join(problems))
	assert_false(_has_problem(problems, ["never off", "palm_l"]), "\n".join(problems))


func test_two_hits_by_one_hitbox_are_fine() -> void:
	var marks := _jab_marks([&"recovery"], [_m(25, &"hitbox_on", {"id": &"palm_l"}), _m(30, &"hitbox_off", {"id": &"palm_l"}), _m(30, &"recovery")])
	assert_eq(_jab(marks), PackedStringArray(), "on, off, on, off, and the recovery after the last off")


func test_an_attack_with_no_hitbox_is_reported() -> void:
	var problems := _jab(_jab_marks([&"hitbox_on", &"hitbox_off"]))
	assert_true(_has_problem(problems, ["no hitbox_on"]), "\n".join(problems))


func test_hitbox_that_the_rig_does_not_have_is_reported() -> void:
	var marks := _jab_marks([&"hitbox_on", &"hitbox_off"], [_m(10, &"hitbox_on", {"id": &"palm_x"}), _m(15, &"hitbox_off", {"id": &"palm_x"})])
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


func test_other_moves_need_sfx_and_fx_too() -> void:
	var move := _move(&"gesture", MoveData.Kind.OTHER)
	var checker := ClipChecker.new()
	assert_true(_has_problem(checker.check_move(move, _anim(30, 0, []), HITBOXES, MOVES), ["sfx"]))
	assert_eq(checker.check_move(move, _anim(30, 0, [_m(0, &"sfx"), _m(0, &"fx")]), HITBOXES, MOVES), PackedStringArray())


func test_mark_off_the_step_grid_is_reported() -> void:
	# Stepped at 12 fps the clip shows a new pose every 5 frames; a mark at frame 12 would fire between poses.
	var problems := _jab(_jab_marks([], [_m(12, &"fx", {"name": &"extra"})]))
	assert_true(_has_problem(problems, ["12 fps step grid", "f12"]), "\n".join(problems))
	problems = _jab(_jab_marks([], [_m(25, &"fx", {"name": &"extra"}), _m(30, &"fx", {"name": &"extra"})]))
	assert_eq(problems, PackedStringArray(), "frames 25 and 30 are on the grid")


func test_a_smooth_clip_has_no_grid() -> void:
	assert_eq(_roll(_roll_marks([], [_m(7, &"fx", {"name": &"extra"})])), PackedStringArray())


func test_the_grid_is_the_clips_own_step_rate() -> void:
	var move := _move(&"palm_jab", MoveData.Kind.ATTACK)
	var marks := _jab_marks([], [_m(2, &"fx", {"name": &"extra"})])
	var checker := ClipChecker.new()
	assert_true(_has_problem(checker.check_move(move, _anim(35, 12, marks), HITBOXES, MOVES), ["12 fps step grid"]))
	assert_true(_has_problem(checker.check_move(move, _anim(35, 24, marks), HITBOXES, MOVES), ["24 fps step grid"]), "f2 is on neither grid, f5 is on both")
	assert_eq(checker.check_move(move, _anim(35, 0, marks), HITBOXES, MOVES), PackedStringArray())


func test_a_mark_outside_the_clip_is_reported() -> void:
	var problems := _jab(_jab_marks([], [_m(40, &"fx", {"name": &"extra"})]))
	assert_true(_has_problem(problems, ["f40", "outside"]), "\n".join(problems))
	var early := _anim(35, 0, _jab_marks([], [{"time": -0.05, "kind": &"fx", "args": {"name": &"extra"}}]))
	problems = ClipChecker.new().check_move(_move(&"palm_jab", MoveData.Kind.ATTACK), early, HITBOXES, MOVES)
	assert_true(_has_problem(problems, ["outside"]), "\n".join(problems))


func test_a_mark_on_the_last_frame_is_inside() -> void:
	# The clip stores 0.583333 for 35 frames; the mark at frame 35 is 3e-7 s later and still counts as inside.
	var a := _anim(35, 12, _jab_marks([], [_m(35, &"fx", {"name": &"extra"})]))
	a.length = 0.583333
	assert_eq(ClipChecker.new().check_move(_move(&"palm_jab", MoveData.Kind.ATTACK), a, HITBOXES, MOVES), PackedStringArray())


func test_cancel_into_unknown_move_is_reported() -> void:
	var problems := _jab(_jab_marks([&"cancel_open"], [_m(20, &"cancel_open", {"into": {&"palm": &"palm_hook"}}), _m(15, &"cancel_open", {"into": {&"palm": &"palm_cross"}})]))
	assert_true(_has_problem(problems, ["unknown move", "palm_hook"]), "\n".join(problems))
	assert_eq(problems.size(), 1, "only the hook is wrong: \n" + "\n".join(problems))


func test_cancel_open_without_a_target_is_reported() -> void:
	var problems := _jab(_jab_marks([&"cancel_open"], [_m(15, &"cancel_open")]))
	assert_true(_has_problem(problems, ["cancel_open", "into"]), "\n".join(problems))


func test_hitstop_out_of_range_is_reported() -> void:
	for frames in [8, 2, 0]:
		var problems := _jab(_jab_marks([&"hitstop"], [_m(10, &"hitstop", {"frames": frames})]))
		assert_true(_has_problem(problems, ["hitstop", str(frames)]), "frames %d: %s" % [frames, "\n".join(problems)])
	for frames in [3, 4, 5, 6]:
		assert_eq(_jab(_jab_marks([&"hitstop"], [_m(10, &"hitstop", {"frames": frames})])), PackedStringArray(), "frames %d" % frames)


func test_hitstop_without_frames_is_reported() -> void:
	var problems := _jab(_jab_marks([&"hitstop"], [_m(10, &"hitstop")]))
	assert_true(_has_problem(problems, ["hitstop"]), "\n".join(problems))


func test_an_unknown_mark_kind_is_reported() -> void:
	var problems := _jab(_jab_marks([], [_m(10, &"hitbox_onn", {"id": &"palm_l"})]))
	assert_true(_has_problem(problems, ["hitbox_onn", "kind"]), "\n".join(problems))


func test_every_problem_starts_with_the_move_id() -> void:
	var problems := _jab(_jab_marks([&"sfx", &"hitbox_off"]))
	assert_true(problems.size() >= 2)
	for problem in problems:
		assert_true(problem.begins_with("palm_jab: "), problem)


func test_the_problems_name_the_frame() -> void:
	var problems := _jab(_jab_marks([&"hitstop"], [_m(10, &"hitstop", {"frames": 8})]))
	assert_true(_has_problem(problems, ["f10"]), "\n".join(problems))


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


# --- the real data ---

func test_real_data_passes() -> void:
	assert_eq(Registry.scan(), PackedStringArray())
	assert_eq(ClipChecker.new().check_all(), PackedStringArray())


func test_real_data_has_three_moves_and_one_actor() -> void:
	assert_eq(Array(Registry.ids(&"moves")), ["dodge_roll", "palm_cross", "palm_jab"])
	assert_eq(Array(Registry.ids(&"actors")), ["abarax"])


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
	assert_true(Array(run["lines"]).has("clip_check: 3 moves, 1 actors OK"), "\n".join(run["lines"]))


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
