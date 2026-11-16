extends TestCase
## Feel: a press shows on the body within two frames (the spec's input response). Abarax stands idle in
## an arena twice from the same start, once pressing palm on frame 11 and once not; by frame 13 at the
## latest his lead hand must be at least 1 cm from where it is in the run without the press. The jab
## leads with palm_l, the hitbox on hand_l; the hook, the cross before it and the heavy palm with hand_r.

const ABARAX := "res://data/actors/abarax.tres"
const PRESS_FRAME := 11
## Frames after the press frame by which the hand must have moved: the spec's two. It is the window the runs are read over, not what
## the tests hold: the game answers a press in MEASURED frames (the pose changes on the frame of the press itself) and each case
## asserts that, so a press acted on one frame late (the spec would still be met) fails. A heavy tapped from rest shows one frame
## later (HEAVY_FROM_REST, measured: from every cancel window it shows at once).
const LIMIT := 2
const MEASURED := 0
const HEAVY_FROM_REST := 1
const HAND := &"hand_l"
const MOVED := 0.01


# The lead hand's global position after each actor frame, up to a few frames past the limit.
func _hand_by_frame(press: bool) -> Dictionary:
	var arena := TestArena.make(self)
	var steps := [{"frames": PRESS_FRAME - 1}, {"frames": 1, "press": [&"palm"] if press else []}, {"frames": 10}]
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var hands := {}
	while actor.frame < PRESS_FRAME + LIMIT + 3:
		await frames(1)
		hands[actor.frame] = actor.rig.bone_global(HAND)
	arena.queue_free()
	await frames(1)
	return hands


func test_jab_moves_the_hand_within_two_frames() -> void:
	var still: Dictionary = await _hand_by_frame(false)
	var jab: Dictionary = await _hand_by_frame(true)
	for f in range(1, PRESS_FRAME):
		if still.has(f) and jab.has(f):
			assert_true((jab[f] as Vector3).distance_to(still[f]) < 1e-5, "the runs match before the press (frame %d)" % f)
	var first := -1
	for f in range(PRESS_FRAME, PRESS_FRAME + LIMIT + 1):
		if not (still.has(f) and jab.has(f)):
			fail("no hand position for frame %d" % f)
			continue
		if first < 0 and (jab[f] as Vector3).distance_to(still[f]) >= MOVED:
			first = f
	assert_true(first >= PRESS_FRAME and first <= PRESS_FRAME + MEASURED,
			"the hand had not moved %s m by frame %d (pressed on %d; the game answers in %d frames, the spec allows %d)" % [MOVED, PRESS_FRAME + MEASURED, PRESS_FRAME, MEASURED, LIMIT])


# The hand's global position after each actor frame up to `last`, for an actor playing `steps` alone in an arena.
func _hands(steps: Array, last: int, hand: StringName) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var hands := {}
	while actor.frame < last:
		await frames(1)
		hands[actor.frame] = actor.rig.bone_global(hand)
	arena.queue_free()
	await frames(1)
	return hands


# Asserts that `hand` moves at least 1 cm from where it is in the run `without`, within LIMIT frames of `press_frame`,
# the frame `with` presses on, and that the runs match before it.
func _assert_motion_within_two_frames(with: Array, without: Array, press_frame: int, hand: StringName, what: String, allowed := MEASURED) -> void:
	var still: Dictionary = await _hands(without, press_frame + LIMIT + 3, hand)
	var moved: Dictionary = await _hands(with, press_frame + LIMIT + 3, hand)
	for f in range(1, press_frame):
		assert_true((moved[f] as Vector3).distance_to(still[f]) < 1e-5, "%s: the runs match before the press (frame %d)" % [what, f])
	var first := -1
	for f in range(press_frame, press_frame + LIMIT + 1):
		if first < 0 and (moved[f] as Vector3).distance_to(still[f]) >= MOVED:
			first = f
	assert_true(first >= press_frame and first <= press_frame + allowed,
			"%s: the hand had not moved %s m by frame %d (pressed on %d; the game answers in %d frames, the spec allows %d)" % [what, MOVED, press_frame + allowed, press_frame, allowed, LIMIT])


func test_hook_and_heavy_show_motion_within_two_frames() -> void:
	# The heavy from rest, with the right hand, on frame 11, as the jab is above.
	await _assert_motion_within_two_frames(
			[{"frames": PRESS_FRAME - 1}, {"frames": 1, "press": [&"heavy"]}, {"frames": 10}],
			[{"frames": PRESS_FRAME + 10}], PRESS_FRAME, &"hand_r", "the heavy palm", HEAVY_FROM_REST)
	# The hook out of the cross: a jab (frame 1), the cross (frame 16, by a press on 15), then a palm on frame 38, two
	# frames into the cross's window (open from its f20, frame 36), against the cross going on.
	var chain := [{"frames": 1, "press": [&"palm"]}, {"frames": 13}, {"frames": 1, "press": [&"palm"]}, {"frames": 22}]
	await _assert_motion_within_two_frames(chain + [{"frames": 1, "press": [&"palm"]}, {"frames": 10}],
			chain + [{"frames": 11}], 38, &"hand_r", "the hook")


# --- Every way the player can act, from rest and from each cancel window that takes it ---------------------------------
#
# The player's actions are: palm, heavy (a tap, and the release of a charge), guard, the dodge (the hop at rest, a
# dash-step with the stick), the sway (left, right, back, and the base one) and the duck. Each is pressed on the first frame
# its window is open: the cancel_open marks of the move that is playing say when. Two runs from the same start, one pressing
# and one not; within LIMIT frames of the press, any of six points of the body (the pelvis, the head, both hands and both feet)
# must be at least 1 cm from where it is in the run without the press. The move a context plays is started by the test, which
# is what a press into the window before it would have done, so the windows are all reachable (a parry and a catch need a foe).
#
# Environment PRESS_TABLE=1 prints a line a case: the table in the report.

## Where the body is read.
const POINTS: Array[StringName] = [&"pelvis", &"Head", &"hand_l", &"hand_r", &"foot_l", &"foot_r"]
## The release of a charge shows this many frames after it (see that test).
const RELEASE_LIMIT := 4
## The frame a context move is started on (and, from rest, the press is on the one after: PRESS_FRAME).
const START_FRAME := 10
## The moves a window is taken from, besides rest: every Abarax move that has a cancel window taking a player's action.
const CONTEXTS: Array[StringName] = [&"palm_jab", &"palm_cross", &"palm_hook", &"palm_heavy", &"hop", &"dash_step",
		&"guard_raise", &"parry", &"catch", &"guard_hit", &"sway_left_slip", &"duck_slip", &"counter_hook", &"counter_rise",
		# The palm windows of the rest of Abarax's moves (each takes a palm): the clears, the other dash-steps, the quick and flurry
		# ducks and sways, the slips.
		&"clear_backpalm", &"clear_wave", &"dash_step_back", &"dash_step_left", &"dash_step_right", &"duck_flurry", &"duck_quick",
		&"sway_back_flurry", &"sway_back_quick", &"sway_left_flurry", &"sway_left_quick", &"sway_right_flurry", &"sway_right_quick",
		&"sway_back_slip", &"sway_right_slip"]

var _controls := {}
var _table: Array[String] = []


# The actions as they are pressed: its name, the button, what is held with it, the stick and the evade direction.
func _action(name: String) -> Dictionary:
	match name:
		"palm":
			return {"button": &"palm"}
		"heavy":
			return {"button": &"heavy"}
		"guard":
			return {"button": &"guard", "hold": [&"guard"]}
		"hop":
			return {"button": &"dodge"}
		"dash_step ahead":
			return {"button": &"dodge", "move": Vector2(0, 1)}
		"dash_step left":
			return {"button": &"dodge", "move": Vector2(1, 0)}
		"dash_step right":
			return {"button": &"dodge", "move": Vector2(-1, 0)}
		"dash_step back":
			return {"button": &"dodge", "move": Vector2(0, -1)}
		"sway ahead":
			return {"button": &"sway", "dir": Vector2(0, 1)}
		"sway left":
			return {"button": &"sway", "dir": Vector2(1, 0)}
		"sway right":
			return {"button": &"sway", "dir": Vector2(-1, 0)}
		"sway back":
			return {"button": &"sway", "dir": Vector2(0, -1)}
		"duck":
			return {"button": &"duck", "dir": Vector2(0, -1)}
	return {}


# The frames of `context` (a move id, or rest) on which pressing `button` starts something new: the first window that takes the
# button, and each later one that sends it to another move. From rest: PRESS_FRAME. A sway, duck or dodge pressed in the
# window of a sway or duck that avoided nothing waits for its redodge_frame (the whiff rule: mashing covers half of a stretch).
func _press_frames(context: StringName, button: StringName) -> Array[int]:
	var frames_found: Array[int] = []
	if context == &"rest":
		frames_found.append(PRESS_FRAME)
		return frames_found
	var move := Registry.fetch(&"moves", context) as MoveData
	var anim := load("res://assets/anim/abarax/%s.tres" % move.clip) as Animation
	var last := &""
	for m in Marks.read(anim):
		if m["kind"] != &"cancel_open":
			continue
		var into: Dictionary = m["args"].get("into", {})
		if not into.has(button) or into[button] == last:
			continue
		last = into[button]
		var at: int = Marks.frame_of(m["time"])
		if move.evade != MoveData.Evade.NONE and MoveRunner.BARRED_ACTIONS.has(button):
			at = maxi(at, move.redodge_frame)
		frames_found.append(START_FRAME + at)
	return frames_found


# The body's points on each actor frame from 1 to `last`, for an actor in `context` that is given `steps`. `release` is a
# frame the actor's heavy was let go of in the steps (nothing else changes there).
func _points_by_frame(context: StringName, steps: Array, last: int) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var seen := {}
	while actor.frame < last:
		await frames(1)
		if context != &"rest" and actor.frame == START_FRAME:
			actor.runner.start(Registry.fetch(&"moves", context) as MoveData)
		var here := PackedVector3Array()
		for point in POINTS:
			here.append(actor.rig.bone_global(point))
		seen[actor.frame] = here
	arena.queue_free()
	await frames(1)
	return seen


# The first frame from `press` on where a point is 1 cm from the control's, or -1.
func _first_motion(control: Dictionary, pressed: Dictionary, press: int, until: int) -> int:
	for f in range(press, until + 1):
		var a: PackedVector3Array = control[f]
		var b: PackedVector3Array = pressed[f]
		for i in a.size():
			if a[i].distance_to(b[i]) >= MOVED:
				return f
	return -1


func _steps_of(action: Dictionary, press: int, hold_before := false) -> Array:
	var step := {"frames": 1, "press": [action["button"]], "hold": action.get("hold", [])}
	if action.has("dir"):
		step["evade_dir"] = action["dir"]
	if action.has("move"):
		step["move"] = action["move"]
	return [{"frames": press - 1}, step, {"frames": 12, "hold": action.get("hold", []), "move": action.get("move", Vector2.ZERO)}]


# One case: `what` is pressed in `context` on `press`. Returns the frames it took to show (the table's number), asserting the
# two runs agree up to the press and that it showed in the measured frames (MEASURED; HEAVY_FROM_REST for a heavy tapped from rest).
func _case(context: StringName, name: String, press: int) -> int:
	var action := _action(name)
	var until := press + LIMIT + 3
	var key := "%s@%d" % [context, press]
	if not _controls.has(key):
		_controls[key] = await _points_by_frame(context, [{"frames": until + 1}], until)
	var control: Dictionary = _controls[key]
	var pressed: Dictionary = await _points_by_frame(context, _steps_of(action, press), until)
	for f in range(1, press):
		var a: PackedVector3Array = control[f]
		var b: PackedVector3Array = pressed[f]
		for i in a.size():
			assert_true(a[i].distance_to(b[i]) < 1e-5, "%s, %s: the runs match before the press (frame %d)" % [context, name, f])
	var first := _first_motion(control, pressed, press, until)
	var took := first - press if first >= 0 else -1
	var allowed := HEAVY_FROM_REST if context == &"rest" and name == "heavy" else MEASURED
	_table.append("%-16s %-16s pressed on frame %3d: moved after %d frames" % [context, name, press, took])
	assert_true(first >= press and took <= allowed, "%s, %s: no point of the body had moved %s m by frame %d (pressed on %d; the game answers in %d frames, the spec allows %d)" % [context, name, MOVED, press + allowed, press, allowed, LIMIT])
	return took


func _run_actions(button: StringName, names: Array[String]) -> void:
	_table.clear()
	for context: StringName in [&"rest"] + CONTEXTS:
		for press in _press_frames(context, button):
			for name in names:
				await _case(context, name, press)
	if OS.get_environment("PRESS_TABLE") != "":
		for line in _table:
			print(line)


func test_palm_shows_motion_within_two_frames_from_rest_and_from_each_window() -> void:
	await _run_actions(&"palm", ["palm"])


func test_heavy_tap_shows_motion_within_two_frames_from_rest_and_from_each_window() -> void:
	await _run_actions(&"heavy", ["heavy"])


func test_guard_shows_motion_within_two_frames_from_rest_and_from_each_window() -> void:
	await _run_actions(&"guard", ["guard"])


func test_the_hop_and_the_dash_steps_show_motion_within_two_frames() -> void:
	await _run_actions(&"dodge", ["hop", "dash_step ahead", "dash_step left", "dash_step right", "dash_step back"])


func test_every_sway_shows_motion_within_two_frames() -> void:
	await _run_actions(&"sway", ["sway ahead", "sway left", "sway right", "sway back"])


func test_the_duck_shows_motion_within_two_frames() -> void:
	await _run_actions(&"duck", ["duck"])


func test_the_release_of_a_charged_heavy_shows_motion_within_two_frames() -> void:
	# The heavy is pressed on frame 11 and held: the clip waits at its charge mark (frame 10 of the clip, so from game frame 21).
	# One run lets go on frame RELEASE, the other keeps holding: the right hand must be 1 cm apart within RELEASE_LIMIT frames.
	# That is four, not LIMIT's two, and it is the clip's doing: the heavy palm is drawn at 12 poses a second (a new pose every
	# fifth frame), the charge mark is on one pose (frame 10) and the strike is the next (frame 15), so the move goes on at the
	# release but the body shows it four frames later, as a snap. Measured, not tuned: it is on the owner's list.
	# RELEASE_LIMIT is the measured 4, so a release acted on one frame late (the hold read a frame late) fails here. A press acted
	# on late does not: the charge starts late in both runs, and the release's own delay is unchanged.
	var release := 35
	var until := release + RELEASE_LIMIT + 3
	var hold := {"frames": 1, "press": [&"heavy"], "hold": [&"heavy"]}
	var kept: Dictionary = await _points_by_frame(&"rest", [{"frames": PRESS_FRAME - 1}, hold, {"frames": until, "hold": [&"heavy"]}], until)
	var let_go: Dictionary = await _points_by_frame(&"rest", [{"frames": PRESS_FRAME - 1}, hold, {"frames": release - PRESS_FRAME - 1, "hold": [&"heavy"]}, {"frames": until}], until)
	for f in range(1, release):
		for i in POINTS.size():
			assert_true((kept[f][i] as Vector3).distance_to(let_go[f][i]) < 1e-5, "the runs match until the release (frame %d)" % f)
	var first := _first_motion(kept, let_go, release, until)
	assert_true(first >= release and first - release <= RELEASE_LIMIT, "no point of the body had moved %s m by frame %d (let go on %d)" % [MOVED, release + RELEASE_LIMIT, release])
	_table.append("heavy charge     release          let go on frame %3d: moved after %d frames" % [release, first - release])
	if OS.get_environment("PRESS_TABLE") != "":
		print(_table[-1])
