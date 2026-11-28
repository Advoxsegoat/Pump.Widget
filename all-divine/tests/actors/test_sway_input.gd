extends TestCase
## Sway and duck from the pad and the keys: a direction pressed with guard held (or on the frame guard goes down) is a
## sway, or a duck when it points down the screen; a direction already held when guard goes down starts nothing; the
## side of a sway and of a dash-step is the screen's direction against the way he faces; while guard is held he stands
## his ground; and the dash-step takes the roll's place (it keeps his facing, never makes him invulnerable, stops at
## walls and bodies, and sprints when the key is held after it). The roll is gone from every clip, move and window.
##
## Abarax stands at the origin facing +Z unless a test says otherwise. A PlayerBrain is driven through its hooks
## (KeysBrain), and `Inputs` itself through key and stick events, as tests/core/test_inputs.gd does.

const ABARAX := "res://data/actors/abarax.tres"
const LIB := "res://assets/anim/abarax/library.tres"
const SWAY := &"sway_left_slip"
const DUCK := &"duck_slip"
## Where a dash-step goes (metres) and how many frames it takes.
const DASH_TRAVEL := 1.3
const DASH_FRAMES := 18


## A PlayerBrain that reads its controls from steps instead of the devices:
##   frames    how many frames the step lasts
##   hold      actions held on every frame of the step
##   press     actions pressed on its first frame
##   dir       the screen direction (x right, y down) that goes down on its first frame
##   stick     the movement stick, screen, held on every frame
##   face      a world point he is asked to keep facing
class KeysBrain extends PlayerBrain:
	var steps: Array
	var _step := 0
	var _frame := -1
	var _current := {}

	func _init(with_steps: Array) -> void:
		steps = with_steps

	func think(actor: Actor, delta: float) -> Intent:
		_frame += 1
		while _step < steps.size() and _frame >= int(steps[_step].get("frames", 0)):
			_step += 1
			_frame = 0
		_current = steps[_step] if _step < steps.size() else {}
		var intent := super.think(actor, delta)
		if _current.has("face"):
			intent.face_target = _current["face"]
		return intent

	func pressed_actions() -> Array[StringName]:
		var out: Array[StringName] = []
		if _frame == 0:
			for action in _current.get("press", []):
				out.append(StringName(action))
		return out

	func held_actions() -> Array[StringName]:
		var out: Array[StringName] = []
		for action in _current.get("hold", []):
			out.append(StringName(action))
		return out

	func direction_pressed() -> Vector2:
		return _current.get("dir", Vector2.ZERO) if _frame == 0 else Vector2.ZERO

	func screen_move() -> Vector2:
		return _current.get("stick", Vector2.ZERO)


# --- helpers ---

# Plays `steps` for the actor (a KeysBrain's or a ScriptBrain's) and `after` frames more, recording what started.
# {actor, started [[id, frame], ...], ended [[id, frame, cancelled], ...], frames [{frame, move, position, facing, speed,
# sprinting, parry, guarding}, ...]}.
func _play(brain: Brain, total: int, yaw := 0.0, at := Vector3.ZERO, arena: Node3D = null) -> Dictionary:
	if arena == null:
		arena = TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), brain, at)
	actor.place(Transform3D(Basis(Vector3.UP, yaw), at))
	var run := {"arena": arena, "actor": actor, "started": [], "ended": [], "frames": []}
	_watch(run, actor)
	while actor.frame < total:
		await frames(1)
		_snap(run, actor)
	return run


func _watch(run: Dictionary, actor: Actor) -> void:
	actor.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append([m.id, actor.frame]))
	actor.runner.move_ended.connect(func(m: MoveData, cancelled: bool) -> void: run["ended"].append([m.id, actor.frame, cancelled]))


func _snap(run: Dictionary, actor: Actor) -> void:
	var current := actor.runner.current
	run["frames"].append({
		"frame": actor.frame,
		"move": current.id if current != null else &"",
		"position": actor.global_position,
		"facing": actor.facing(),
		"speed": actor.locomotion.speed,
		"sprinting": actor.locomotion.sprinting,
		"parry": actor.runner.parry_window,
		"guarding": actor.guarding,
		"iframes": actor.is_invulnerable(),
	})


func _at(run: Dictionary, f: int) -> Dictionary:
	for state: Dictionary in run["frames"]:
		if state["frame"] == f:
			return state
	fail("no state for frame %d" % f)
	return {"position": Vector3.INF, "facing": Vector3.INF, "move": &"", "guarding": false}


func _ids(run: Dictionary) -> Array:
	return run["started"].map(func(s: Array) -> StringName: return s[0])


# --- a direction with guard held ---

func test_a_direction_pressed_with_guard_held_sways_within_two_frames() -> void:
	# Guard is held from frame 1 (the raise, then the stance); the screen's right goes down on frame 40.
	var brain := KeysBrain.new([
		{"frames": 1, "press": [&"guard"], "hold": [&"guard"]},
		{"frames": 38, "hold": [&"guard"]},
		{"frames": 1, "hold": [&"guard"], "dir": Vector2.RIGHT},
		{"frames": 30, "hold": [&"guard"]},
	])
	var run: Dictionary = await _play(brain, 70)
	assert_true(_at(run, 39)["guarding"], "the stance was up")
	var sways: Array = run["started"].filter(func(s: Array) -> bool: return String(s[0]).begins_with("sway_"))
	assert_eq(sways.size(), 1, "one sway: %s" % [run["started"]])
	if not sways.is_empty():
		assert_true(sways[0][1] <= 42, "it started on frame %d, by the second frame after the press on 40" % sways[0][1])
		assert_eq(sways[0][0], SWAY, "the screen's right, with him facing +Z, is his left")


func test_a_sway_shows_in_the_pose_within_two_frames() -> void:
	# The pose is what the player sees: the head is off the line by the second frame after the press.
	var held := {"frames": 30, "hold": [&"guard"]}
	var with := KeysBrain.new([held, {"frames": 1, "hold": [&"guard"], "dir": Vector2.RIGHT}, {"frames": 10, "hold": [&"guard"]}])
	var without := KeysBrain.new([held, {"frames": 11, "hold": [&"guard"]}])
	var head := {}
	for pair in [["with", with], ["without", without]]:
		var arena := TestArena.make(self)
		var actor := TestArena.spawn(arena, load(ABARAX), pair[1])
		var seen := []
		while actor.frame < 42:
			await frames(1)
			seen.append(actor.rig.bone_global(&"Head"))
		head[pair[0]] = seen
		arena.queue_free()
		await frames(1)
	var moved := false
	for i in range(30, 33):
		moved = moved or (head["with"][i] as Vector3).distance_to(head["without"][i]) > 0.01
	assert_true(moved, "the head had moved 1 cm by frame 33 (pressed on 31)")


func test_guard_and_a_direction_on_the_same_frame_is_a_sway_not_a_parry() -> void:
	var brain := KeysBrain.new([
		{"frames": 5},
		{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "dir": Vector2.RIGHT},
		{"frames": 60, "hold": [&"guard"]},
	])
	var run: Dictionary = await _play(brain, 66)
	assert_eq(run["started"], [[SWAY, 6]], "the sway, on the frame of the press, and no guard raise")
	assert_false(run["frames"].any(func(s: Dictionary) -> bool: return s["parry"]), "and no parry window opens")
	assert_true(_at(run, 66)["guarding"], "he holds guard still: the stance is up once the sway is out")


func test_a_direction_already_held_when_guard_goes_down_starts_nothing() -> void:
	# Review Focus 2. The direction went down on frame 3, with no guard held: nothing. Guard goes down on frame 12 with the
	# direction still held (no press of it that frame): the raise, and no sway.
	var brain := KeysBrain.new([
		{"frames": 2},
		{"frames": 1, "dir": Vector2.RIGHT, "stick": Vector2.RIGHT},
		{"frames": 8, "stick": Vector2.RIGHT},
		{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "stick": Vector2.RIGHT},
		{"frames": 40, "hold": [&"guard"], "stick": Vector2.RIGHT},
	])
	var run: Dictionary = await _play(brain, 52)
	assert_eq(_ids(run), [&"guard_raise"], "only the raise: %s" % [run["started"]])


func test_a_direction_held_through_real_keys_before_guard_starts_nothing() -> void:
	# The same through the real Inputs: D down, then Q, with the real PlayerBrain.
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), PlayerBrain.new())
	var run := {"started": [], "ended": []}
	_watch(run, actor)
	_key_event(KEY_D, true)
	await frames(6)
	_key_event(KEY_Q, true)
	await frames(30)
	_key_event(KEY_Q, false)
	_key_event(KEY_D, false)
	await frames(2)
	assert_eq(_ids(run), [&"guard_raise"], "a direction that was down before guard is no sway: %s" % [run["started"]])


func test_a_direction_pressed_after_guard_through_real_keys_sways() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), PlayerBrain.new())
	var run := {"started": [], "ended": []}
	_watch(run, actor)
	_key_event(KEY_Q, true)
	await frames(30)
	_key_event(KEY_D, true)
	await frames(3)
	_key_event(KEY_Q, false)
	_key_event(KEY_D, false)
	await frames(2)
	var sways: Array = _ids(run).filter(func(id: StringName) -> bool: return String(id).begins_with("sway_"))
	assert_eq(sways, [SWAY], "Q then D: a sway, which started: %s" % [run["started"]])


func test_down_ducks_whatever_way_he_faces() -> void:
	for yaw in [0.0, PI / 2, PI, -PI / 2]:
		var brain := KeysBrain.new([
			{"frames": 1, "press": [&"guard"], "hold": [&"guard"]},
			{"frames": 30, "hold": [&"guard"]},
			{"frames": 1, "hold": [&"guard"], "dir": Vector2.DOWN},
			{"frames": 5, "hold": [&"guard"]},
		])
		var run: Dictionary = await _play(brain, 37, yaw)
		assert_true(run["started"].any(func(s: Array) -> bool: return s[0] == DUCK and s[1] <= 33), "facing yaw %s: a duck by frame 33: %s" % [yaw, run["started"]])
		run["arena"].queue_free()
		await frames(1)


func test_a_direction_within_forty_five_degrees_of_down_ducks_and_further_off_sways() -> void:
	var rows := [
		[Vector2.DOWN, DUCK],
		[Vector2(1, 1).normalized(), DUCK],
		[Vector2(-1, 1).normalized(), DUCK],
		[Vector2(1, 0.8).normalized(), SWAY],
		[Vector2.UP, &"sway_back_slip"],
		[Vector2.LEFT, &"sway_right_slip"],
	]
	for row: Array in rows:
		var brain := KeysBrain.new([
			{"frames": 5},
			{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "dir": row[0]},
			{"frames": 5, "hold": [&"guard"]},
		])
		var run: Dictionary = await _play(brain, 11)
		assert_eq(_ids(run), [row[1]], "the screen direction %s" % row[0])
		run["arena"].queue_free()
		await frames(1)


func test_a_turned_camera_turns_the_direction_with_it() -> void:
	# The camera looks along +X (yaw -PI/2 turns screen up from -Z to... wherever): a press of the screen's right is the
	# world direction the stick would go, so the side follows the world.
	var brain := KeysBrain.new([
		{"frames": 5},
		{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "dir": Vector2.RIGHT},
		{"frames": 5, "hold": [&"guard"]},
	])
	brain.view_yaw = PI
	var run: Dictionary = await _play(brain, 11)
	assert_eq(_ids(run), [&"sway_right_slip"], "screen right is world -X with the camera turned half way round, his right facing +Z")


func test_the_side_follows_the_screen_against_his_facing() -> void:
	# Facing +X, his right is +Z: a press toward +Z is a lean to his right, toward -Z to his left, toward -X a pull back,
	# toward +X (straight ahead) a slip to his left.
	var rows := [
		[Vector2(0, 1), &"sway_right_slip"],
		[Vector2(0, -1), SWAY],
		[Vector2(-1, 0), &"sway_back_slip"],
		[Vector2(1, 0), SWAY],
	]
	for row: Array in rows:
		var run: Dictionary = await _play(ScriptBrain.new([{"frames": 3}, {"frames": 1, "press": [&"sway"], "evade_dir": row[0]}, {"frames": 3}]), 7, PI / 2)
		assert_eq(_ids(run), [row[1]], "a press toward %s while facing +X" % row[0])
		run["arena"].queue_free()
		await frames(1)


func test_move_data_side_of_cuts_the_circle_at_thirty_and_a_hundred_and_fifty_degrees() -> void:
	var facing := Vector3(0, 0, 1)
	var rows := [[0.0, &""], [29.0, &""], [-29.0, &""], [31.0, &"left"], [90.0, &"left"], [149.0, &"left"],
			[-31.0, &"right"], [-90.0, &"right"], [-149.0, &"right"], [151.0, &"back"], [180.0, &"back"], [-151.0, &"back"]]
	for row: Array in rows:
		# Degrees counted toward his left (+X when he faces +Z).
		var dir := Vector2(sin(deg_to_rad(row[0])), cos(deg_to_rad(row[0])))
		assert_eq(MoveData.side_of(dir, facing), row[1], "%s degrees to his left" % row[0])
	assert_eq(MoveData.side_of(Vector2.ZERO, facing), &"", "no direction is straight ahead")


# --- the stick flicks and the keys ---

func test_the_stick_flicks_past_point_six_and_rearms_below_point_three_five() -> void:
	var devices: Array[int] = [0]
	_stick(0, 0.0, 0.0)
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)
	var presses := []
	for i in 60:
		_stick(0, 0.6 + (0.02 if i % 2 == 0 else -0.02), 0.0)
		await frames(1)
		var dir := Inputs.direction_pressed_this_frame(devices)
		if dir != Vector2.ZERO:
			presses.append(dir)
	assert_eq(presses, [Vector2(1, 0)], "a stick dwelling at the threshold is one press, to the right")
	_stick(0, 0.0, 0.0)
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)
	presses = []
	for v in [0.3, 0.7, 1.0, 0.8, 0.4, 0.0, 0.7, 0.0]:
		_stick(0, 0.0, v)
		await frames(1)
		var dir := Inputs.direction_pressed_this_frame(devices)
		if dir != Vector2.ZERO:
			presses.append(dir)
	assert_eq(presses, [Vector2(0, 1), Vector2(0, 1)], "two flicks down, each let go below 0.35, are two presses")
	_stick(0, 0.0, -0.9)
	await frames(1)
	assert_eq(Inputs.direction_pressed_this_frame(devices), Vector2(0, -1), "up is negative y on the screen")
	_stick(0, 0.0, 0.0)
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)


func test_a_stick_flicked_on_the_diagonal_is_one_press_along_it() -> void:
	var devices: Array[int] = [0]
	_stick(0, 0.0, 0.0)
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)
	var presses := []
	for v in [0.3, 0.5, 0.8, 0.9, 0.9]:
		_stick(0, v, v)
		await frames(1)
		var dir := Inputs.direction_pressed_this_frame(devices)
		if dir != Vector2.ZERO:
			presses.append(dir)
	assert_eq(presses.size(), 1, "the two axes pass 0.6 together or one after the other: one press, not two")
	if presses.size() == 1:
		assert_vec_near(Vector3(presses[0].x, presses[0].y, 0), Vector3(1, 1, 0).normalized(), 1e-4, "of length 1, down and right")
	_stick(0, 0.0, 0.0)
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)


func test_a_move_key_is_a_press_on_the_frame_it_goes_down_and_not_while_it_is_held() -> void:
	var devices: Array[int] = [0]
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)
	_key_event(KEY_D, true)
	await frames(1)
	assert_eq(Inputs.direction_pressed_this_frame(devices), Vector2(1, 0), "D: right")
	await frames(1)
	assert_eq(Inputs.direction_pressed_this_frame(devices), Vector2.ZERO, "held: not again")
	_key_event(KEY_W, true)
	await frames(1)
	assert_eq(Inputs.direction_pressed_this_frame(devices), Vector2(0, -1), "W goes down with D held: up, W alone")
	_key_event(KEY_W, false)
	_key_event(KEY_D, false)
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)
	_key_event(KEY_A, true)
	_key_event(KEY_S, true)
	await frames(1)
	var both := Inputs.direction_pressed_this_frame(devices)
	assert_vec_near(Vector3(both.x, both.y, 0), Vector3(-1, 1, 0).normalized(), 1e-4, "two keys on one frame make the diagonal, length 1")
	_key_event(KEY_A, false)
	_key_event(KEY_S, false)
	await frames(1)
	Inputs.direction_pressed_this_frame(devices)


# --- hit-stop ---

func test_a_sway_buffered_during_hit_stop_comes_out_when_it_ends() -> void:
	# Review Focus 2. Hit-stop of 10 frames starts after frame 5; the sway is pressed on frame 8, inside it. The frames
	# frozen do not age the press, and the way it was pressed (toward -X: to his right) goes with it.
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new([
			{"frames": 7}, {"frames": 1, "press": [&"sway"], "evade_dir": Vector2(-1, 0)}, {"frames": 30}]))
	var run := {"started": [], "ended": []}
	_watch(run, actor)
	while actor.frame < 5:
		await frames(1)
	actor.freeze(10)
	while actor.frame < 40:
		await frames(1)
	assert_eq(run["started"], [[&"sway_right_slip", 16]], "out on the first frame he is free, with its side")


# --- the planted guard ---

func test_he_stands_his_ground_while_guard_is_held_and_walks_when_it_is_let_go() -> void:
	var brain := KeysBrain.new([
		{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "stick": Vector2.RIGHT},
		{"frames": 50, "hold": [&"guard"], "stick": Vector2.RIGHT},
		{"frames": 30, "stick": Vector2.RIGHT},
	])
	var run: Dictionary = await _play(brain, 81)
	assert_true(_at(run, 50)["guarding"], "the stance is up")
	assert_vec_near(_at(run, 50)["position"], Vector3.ZERO, 1e-3, "and he has not moved with the stick pushed")
	assert_vec_near(_at(run, 40)["position"], Vector3.ZERO, 1e-3)
	var walked: Vector3 = _at(run, 81)["position"]
	assert_true(walked.x > 0.5, "let go of guard, the legs are his again: %s" % walked)


func test_a_planted_guard_still_turns_to_its_target() -> void:
	var brain := KeysBrain.new([
		{"frames": 1, "press": [&"guard"], "hold": [&"guard"], "face": Vector3(5, 0, 0)},
		{"frames": 60, "hold": [&"guard"], "face": Vector3(5, 0, 0), "stick": Vector2(0, -1)},
	])
	var run: Dictionary = await _play(brain, 61)
	assert_vec_near(_at(run, 61)["position"], Vector3.ZERO, 1e-3, "he stays")
	assert_true((_at(run, 61)["facing"] as Vector3).dot(Vector3.RIGHT) > 0.99, "and faces the target: %s" % [_at(run, 61)["facing"]])


func test_the_planted_guard_is_the_tunings() -> void:
	assert_true((load("res://data/tuning/combat_abarax.tres") as CombatTuning).guard_planted, "Abarax plants his guard")
	assert_false(CombatTuning.new().guard_planted, "and a tuning that says nothing does not")


# --- the dash-step ---

func test_dodge_with_the_stick_dash_steps_that_way_and_keeps_his_facing() -> void:
	# Facing +Z. His left is +X, his right -X, ahead +Z, behind -Z.
	var rows := [
		[Vector2(1, 0), &"dash_step_left", Vector3(1, 0, 0)],
		[Vector2(-1, 0), &"dash_step_right", Vector3(-1, 0, 0)],
		[Vector2(0, 1), &"dash_step", Vector3(0, 0, 1)],
		[Vector2(0, -1), &"dash_step_back", Vector3(0, 0, -1)],
	]
	for row: Array in rows:
		var run: Dictionary = await _play(ScriptBrain.new([{"frames": 5}, {"frames": 1, "press": [&"dodge"], "move": row[0]}, {"frames": 40}]), 46)
		assert_eq(run["started"], [[row[1], 6]], "toward %s" % row[0])
		assert_eq(run["ended"], [[row[1], 24, false]], "18 frames")
		var moved: Vector3 = _at(run, 46)["position"] - _at(run, 5)["position"]
		assert_near(moved.dot(row[2]), DASH_TRAVEL, 0.05, "1.3 m along the stick: %s" % moved)
		assert_vec_near(moved, row[2] * DASH_TRAVEL, 0.06, "and nowhere else")
		assert_vec_near(_at(run, 6)["facing"], Vector3(0, 0, 1), 1e-6, "he still faces ahead on its first frame")
		assert_vec_near(_at(run, 24)["facing"], Vector3(0, 0, 1), 1e-6, "and on its last")
		assert_false(run["frames"].any(func(s: Dictionary) -> bool: return s["iframes"]), "never invulnerable")
		run["arena"].queue_free()
		await frames(1)


func test_dodge_with_the_stick_at_rest_hops() -> void:
	var run: Dictionary = await _play(ScriptBrain.new([{"frames": 5}, {"frames": 1, "press": [&"dodge"]}, {"frames": 50}]), 56)
	assert_eq(_ids(run), [&"hop"], "no stick: the hop, as before")


func test_a_blow_during_a_dash_step_lands() -> void:
	# Review Focus 5. a (PLAYER) jabs on frame 1 and the hand lands on frame 11. b, a metre in front, dash-steps sideways
	# on frame 9: two frames in, it has hardly left the hand's line. A dash-step is no invulnerability and no evade.
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 40}],
			[{"frames": 8}, {"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)}, {"frames": 40}])
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var got := []
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: got.append([HitResult.Outcome.keys()[r.outcome], b.frame]))
	await Duel.play_to(self, a, 30)
	assert_eq(got.front() if not got.is_empty() else [], ["HIT", 11], "the jab lands on its first live frame: %s" % [got])
	assert_eq(b.stats.hp, 92.0, "and takes 8 HP")
	assert_false(b.runner.evaded, "nothing was evaded")


func test_a_dash_step_stops_at_a_wall_and_at_a_body() -> void:
	var arena := TestArena.make(self)
	TestArena.wall(arena, Vector3(1.3, 1.0, 0.0), Vector3(1.0, 2.0, 4.0))  # its near face at x = 0.8
	var run: Dictionary = await _play(ScriptBrain.new([{"frames": 5}, {"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)}, {"frames": 40}]), 46, 0.0, Vector3.ZERO, arena)
	var actor: Actor = run["actor"]
	var radius := (actor.get_node(^"Body") as CollisionShape3D).shape.get("radius") as float
	var own_spacing := actor.spacing.radius()
	var x: float = _at(run, 46)["position"].x
	assert_true(x > 0.2, "he moved: %s" % x)
	assert_true(x <= 0.8 - radius + 0.02, "and stopped at the wall, not %s m in (his radius is %s)" % [x, radius])
	run["arena"].queue_free()
	await frames(1)
	var arena2 := TestArena.make(self)
	var other := TestArena.spawn(arena2, load(ABARAX), Brain.new(), Vector3(1.0, 0, 0), "Other")
	other.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(1.0, 0, 0)))
	var run2: Dictionary = await _play(ScriptBrain.new([{"frames": 5}, {"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)}, {"frames": 40}]), 46, 0.0, Vector3.ZERO, arena2)
	var apart: float = (_at(run2, 46)["position"] as Vector3).distance_to(other.global_position)
	assert_true(apart >= own_spacing + other.spacing.radius() - 0.02, "he did not pass through the body: %s apart" % apart)
	assert_true(apart < 1.0, "but he did step toward it: %s apart" % apart)


func test_holding_dodge_after_a_dash_step_sprints() -> void:
	var east := Vector2(1, 0)
	var run: Dictionary = await _play(ScriptBrain.new([
		{"frames": 5},
		{"frames": 1, "press": [&"dodge"], "hold": [&"dodge"], "move": east},
		{"frames": 90, "hold": [&"dodge"], "move": east},
		{"frames": 40, "move": east},
	]), 136)
	var tuning: LocomotionTuning = (load(ABARAX) as ActorDef).locomotion
	assert_eq(run["started"], [[&"dash_step_left", 6]], "holding does not dash-step again")
	assert_false(run["frames"].any(func(s: Dictionary) -> bool: return s["sprinting"] and s["frame"] <= 6 + DASH_FRAMES), "no sprint during the dash-step")
	var held := _at(run, 96)
	assert_true(held["sprinting"], "sprinting after it")
	assert_near(held["speed"], tuning.sprint_speed, 1e-6, "at sprint_speed")
	assert_false(_at(run, 136)["sprinting"], "let go: no sprint")


# --- the flow ---

func test_a_parry_flows_into_a_sway() -> void:
	# b taps guard on frame 6 and the jab (which lands on frame 11) is parried: b plays `parry`. It presses a sway on frame
	# 15, in the hit-stop; the sway starts at the parry's f3 (frame 17, after the 3 frozen frames), well before a riposte could.
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 80}],
			[{"frames": 5}, {"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 8}, {"frames": 1, "press": [&"sway"], "evade_dir": Vector2(-1, 0)}, {"frames": 60}])
	var b: Actor = run["b"]
	var started := []
	b.runner.move_started.connect(func(m: MoveData) -> void: started.append([m.id, b.frame]))
	await Duel.play_to(self, b, 40)
	var names: Array = started.map(func(s: Array) -> StringName: return s[0])
	assert_eq(names.slice(0, 3), [&"guard_raise", &"parry", &"sway_left_slip"], "raise, parry, then the sway: %s" % [started])
	if started.size() >= 3:
		var parry_at: int = started[1][1]
		assert_eq(started[2][1], parry_at + 3 + 3, "the sway on the parry's f3, where its first window opens, after the parry's 3 frozen frames")


# --- the window marks and the roll's end ---

func test_every_window_that_took_the_roll_takes_a_sway_a_duck_and_a_dash_step() -> void:
	var lib := load(LIB) as AnimationLibrary
	var windows := 0
	for clip in lib.get_animation_list():
		for mark in Marks.read(lib.get_animation(clip)):
			if mark["kind"] != &"cancel_open":
				continue
			var into: Dictionary = mark["args"].get("into", {})
			if not into.has(&"dodge"):
				continue
			windows += 1
			assert_eq(into.get(&"dodge"), &"dash_step", "%s f%d: dodge" % [clip, Marks.frame_of(mark["time"])])
			assert_eq(into.get(&"sway"), &"sway_left_slip", "%s f%d: sway" % [clip, Marks.frame_of(mark["time"])])
			assert_eq(into.get(&"duck"), &"duck_slip", "%s f%d: duck" % [clip, Marks.frame_of(mark["time"])])
	assert_true(windows >= 9, "the jab, cross, hook, heavy, hop, flinch, stagger, guard hit and guard raise had one each: %d" % windows)


func test_the_guard_raise_and_the_reactions_of_a_guard_open_a_window_into_sway_and_duck() -> void:
	var lib := load(LIB) as AnimationLibrary
	var raise := _window_at(lib, &"guard_raise", 10)
	assert_eq(raise.get(&"sway"), &"sway_left_slip", "the raise, at its parry_off (f10)")
	assert_eq(raise.get(&"duck"), &"duck_slip")
	for clip in [&"parry", &"catch", &"guard_hit"]:
		var window := _window_of_clip(lib, clip)
		assert_false(window.is_empty(), "%s has a window" % clip)
		assert_eq(window.get(&"sway"), &"sway_left_slip", "%s: sway" % clip)
		assert_eq(window.get(&"duck"), &"duck_slip", "%s: duck" % clip)
	var parry := _window_at(lib, &"parry", 8)
	assert_eq(parry.get(&"palm"), &"palm_jab", "the parry's riposte is still in its window at f8")
	assert_eq(parry.get(&"sway"), &"sway_left_slip", "the sway opens with it")


func _window_at(lib: AnimationLibrary, clip: StringName, frame: int) -> Dictionary:
	for mark in Marks.read(lib.get_animation(clip)):
		if mark["kind"] == &"cancel_open" and Marks.frame_of(mark["time"]) == frame:
			return mark["args"].get("into", {})
	return {}


func _window_of_clip(lib: AnimationLibrary, clip: StringName) -> Dictionary:
	for mark in Marks.read(lib.get_animation(clip)):
		if mark["kind"] == &"cancel_open":
			return mark["args"].get("into", {})
	return {}


func test_no_clip_or_move_names_the_roll_any_more() -> void:
	var roll := "dodge" + "_roll"  # joined, so that the scan for res:// paths does not take the old files for paths
	assert_false(Registry.ids(&"moves").has(roll), "no move")
	var lib := load(LIB) as AnimationLibrary
	assert_false(lib.has_animation(StringName(roll)), "no clip")
	assert_false(FileAccess.file_exists("res://assets/anim/abarax/%s.tres" % roll), "no clip file")
	assert_false(FileAccess.file_exists("res://data/moves/%s.tres" % roll), "no move file")
	for clip in lib.get_animation_list():
		for mark in Marks.read(lib.get_animation(clip)):
			if mark["kind"] == &"cancel_open":
				assert_false((mark["args"].get("into", {}) as Dictionary).values().has(StringName(roll)), "%s opens a window into the roll" % clip)
	var def := load(ABARAX) as ActorDef
	assert_eq(def.moveset.get(&"dodge"), &"dash_step", "Abarax's dodge is the dash-step")
	assert_eq(def.moveset.get(&"sway"), &"sway_left_slip")
	assert_eq(def.moveset.get(&"duck"), &"duck_slip")
	assert_false(FileAccess.get_file_as_string("res://assets/anim/clips.cfg").contains("[%s]" % roll), "no clips.cfg entry")


# --- Inputs plumbing ---

func _key_event(physical_keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _stick(device: int, x: float, y: float) -> void:
	for pair in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
		var event := InputEventJoypadMotion.new()
		event.device = device
		event.axis = pair[0]
		event.axis_value = pair[1]
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func after_each() -> void:
	for key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q]:
		_key_event(key, false)
	_stick(0, 0.0, 0.0)
	await frames(1)


# --- fix round 1 ---

# Abarax (a PLAYER copy) holding guard through `steps` more frames, who starts `move_id` himself at the end of frame `at`,
# with `freeze` frames of hit-stop on it, and presses a sway toward his right on frame `press`. Returns the run.
func _defence_run(move_id: StringName, at: int, freeze: int, press: int, total: int) -> Dictionary:
	var arena := TestArena.make(self)
	var steps := [{"frames": at + press - 1, "hold": [&"guard"]}, {"frames": 1, "press": [&"sway"], "evade_dir": Vector2(-1, 0), "hold": [&"guard"]},
			{"frames": total, "hold": [&"guard"]}]
	var actor := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new(steps))
	var run := {"arena": arena, "actor": actor, "started": [], "ended": []}
	_watch(run, actor)
	while actor.frame < at:
		await frames(1)
	actor.runner.start(Registry.fetch(&"moves", move_id) as MoveData)
	if freeze > 0:
		actor.freeze(freeze)
	run["at"] = at
	while actor.frame < at + press + total:
		await frames(1)
	return run


func test_a_sway_pressed_on_any_frame_of_a_defence_comes_out() -> void:
	# Each defence move is started by hand on frame 5; the sway is pressed on each frame k after it (k = 1 is the move's
	# f1), with and without hit-stop on the move's first frames. None is swallowed.
	var lengths := {&"guard_raise": 14, &"parry": 24, &"guard_hit": 21, &"catch": 30}
	for id: StringName in lengths:
		for freeze in [0, 4]:
			for k in range(1, int(lengths[id]) + 3):
				var run: Dictionary = await _defence_run(id, 5, freeze, k, 40)
				var swayed: Array = run["started"].filter(func(s: Array) -> bool: return String(s[0]).begins_with("sway_"))
				assert_eq(swayed.size(), 1, "%s, hit-stop %d, sway pressed on its frame %d: %s" % [id, freeze, k, run["started"]])
				run["arena"].queue_free()
				await frames(1)


func test_a_sway_after_a_guard_tap_answers_within_two_frames() -> void:
	for gap in range(1, 10):
		var brain := KeysBrain.new([
			{"frames": 4},
			{"frames": 1, "press": [&"guard"], "hold": [&"guard"]},
			{"frames": gap - 1, "hold": [&"guard"]},
			{"frames": 1, "hold": [&"guard"], "dir": Vector2.RIGHT},
			{"frames": 40, "hold": [&"guard"]},
		])
		var run: Dictionary = await _play(brain, 5 + gap + 40)
		var sways: Array = run["started"].filter(func(s: Array) -> bool: return String(s[0]).begins_with("sway_"))
		var pressed := 5 + gap
		assert_eq(sways.size(), 1, "guard on 5, direction on %d: %s" % [pressed, run["started"]])
		if sways.size() == 1:
			assert_true(sways[0][1] - pressed <= 2, "the sway started on %d, %d frames after its press" % [sways[0][1], sways[0][1] - pressed])
		run["arena"].queue_free()
		await frames(1)


func test_a_sway_after_a_parry_starts_by_its_third_free_frame() -> void:
	await _assert_free_frame(&"parry", 3)


func test_a_sway_after_a_guard_hit_starts_by_its_sixth_free_frame() -> void:
	await _assert_free_frame(&"guard_hit", 6)


func test_a_sway_after_a_catch_starts_by_its_eighth_free_frame() -> void:
	await _assert_free_frame(&"catch", 8)


# The reaction is on from the end of frame 5 with 3 frames of hit-stop, and the sway is pressed on frame 6, inside it: it
# starts on the `free`th frame after the hit-stop (the reaction's f<free>), when its first window opens.
func _assert_free_frame(id: StringName, free: int) -> void:
	var run: Dictionary = await _defence_run(id, 5, 3, 1, 40)
	var swayed: Array = run["started"].filter(func(s: Array) -> bool: return String(s[0]).begins_with("sway_"))
	assert_eq(swayed.size(), 1, "%s: %s" % [id, run["started"]])
	if swayed.size() == 1:
		assert_eq(swayed[0][1], 5 + 3 + free, "%s: the sway on its free frame %d (the press was on frame 6)" % [id, free])


func test_a_guarded_blow_twelve_frames_before_the_next_leaves_time_to_sway_it() -> void:
	# b guards (raised on frame 1: its parry window is over by 11). a's jab lands on frame 13 and is GUARDED; c's, from behind,
	# lands on frame 25, twelve frames later. b presses a sway on frame 14 (the first after the blow): the second is EVADED.
	var arena := TestArena.make(self)
	var b := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new([
			{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 12, "hold": [&"guard"]},
			{"frames": 1, "press": [&"sway"], "evade_dir": Vector2(-1, 0), "hold": [&"guard"]}, {"frames": 60, "hold": [&"guard"]}]), Vector3(0, 0, 1), "B")
	b.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1)))
	var a := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new([{"frames": 2}, {"frames": 1, "press": [&"palm"]}, {"frames": 60}]), Vector3.ZERO, "A")
	a.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var c := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new([{"frames": 14}, {"frames": 1, "press": [&"palm"]}, {"frames": 60}]), Vector3(0, 0, 2), "C")
	c.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 2)))
	var got := []
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: got.append([HitResult.Outcome.keys()[r.outcome], b.frame]))
	await Duel.play_to(self, b, 40)
	assert_eq(got, [["GUARDED", 13], ["EVADED", 25]], "the first guarded, the second, twelve frames on, evaded")


func test_guard_held_through_a_parry_is_a_guard_when_it_ends() -> void:
	# b taps guard before a's jab lands (a parry) and keeps it held; a's next jab, long after the parry is over, is GUARDED.
	var run := Duel.make(self, [{"frames": 1, "press": [&"palm"]}, {"frames": 60}, {"frames": 1, "press": [&"palm"]}, {"frames": 40}],
			[{"frames": 5}, {"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 150, "hold": [&"guard"]}])
	var b: Actor = run["b"]
	var got := []
	b.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: got.append(HitResult.Outcome.keys()[r.outcome]))
	await Duel.play_to(self, b, 120)
	assert_eq(got, ["PARRIED", "GUARDED"], "parried, then, with guard held, guarded")


func test_guard_held_through_a_catch_is_a_guard_when_it_ends() -> void:
	var solo: Dictionary = await _play(ScriptBrain.new([{"frames": 90, "hold": [&"guard"]}]), 2)
	var a: Actor = solo["actor"]
	a.runner.start(Registry.fetch(&"moves", &"catch") as MoveData)
	while a.frame < 50:
		await frames(1)
	assert_true(a.guarding, "guard still held: the stance is up when the catch is over")
	assert_false(a.runner.parry_window, "and no fresh parry window comes with it")


func test_a_parry_played_out_with_guard_held_brings_the_stance_back() -> void:
	var solo: Dictionary = await _play(ScriptBrain.new([{"frames": 80, "hold": [&"guard"]}]), 2)
	var a: Actor = solo["actor"]
	a.runner.start(Registry.fetch(&"moves", &"parry") as MoveData)
	while a.frame < 40:
		await frames(1)
	assert_true(a.guarding, "the stance is up when the parry is over")
	assert_false(a.runner.parry_window, "and no fresh parry window comes with it")


func test_a_dash_step_on_a_diagonal_travels_the_diagonal() -> void:
	for degrees in [45.0, 20.0, 70.0, -45.0, -20.0, 100.0, 135.0, 160.0]:
		var dir := Vector2(sin(deg_to_rad(degrees)), cos(deg_to_rad(degrees)))  # degrees toward his left, from ahead (+Z)
		var run: Dictionary = await _play(ScriptBrain.new([{"frames": 5}, {"frames": 1, "press": [&"dodge"], "move": dir}, {"frames": 40}]), 46)
		var moved: Vector3 = _at(run, 46)["position"] - _at(run, 5)["position"]
		assert_vec_near(moved, Vector3(dir.x, 0, dir.y) * DASH_TRAVEL, 0.05, "%s degrees off his facing: %s" % [degrees, moved])
		assert_vec_near(_at(run, 24)["facing"], Vector3(0, 0, 1), 1e-6, "%s degrees: he faces as he did" % degrees)
		run["arena"].queue_free()
		await frames(1)


func test_a_dash_steps_four_sides_are_equal_quarters_and_a_sways_are_not() -> void:
	var dash := Registry.fetch(&"moves", &"dash_step") as MoveData
	var sway := Registry.fetch(&"moves", &"sway_left_slip") as MoveData
	assert_eq([dash.side_ahead_deg, dash.side_back_deg], [45.0, 135.0])
	assert_eq([sway.side_ahead_deg, sway.side_back_deg], [30.0, 150.0])
	var facing := Vector3(0, 0, 1)
	assert_eq(MoveData.side_of(Vector2.from_angle(PI / 2 - deg_to_rad(40.0)), facing, 45.0, 135.0), &"", "40 degrees: ahead for a dash-step")
	assert_eq(MoveData.side_of(Vector2.from_angle(PI / 2 - deg_to_rad(40.0)), facing), &"left", "and a side for a sway")


func _use_device(device: int) -> void:
	for pressed in [true, false]:
		var event: InputEvent
		if device == Inputs.Device.GAMEPAD:
			var button := InputEventJoypadButton.new()
			button.button_index = JOY_BUTTON_BACK
			button.pressed = pressed
			event = button
		else:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_F8
			key.keycode = KEY_F8
			key.pressed = pressed
			event = key
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _guard_facing_run(device: int, foe_at: Vector3) -> Dictionary:
	_use_device(device)
	var arena := TestArena.make(self)
	var foe := TestArena.spawn(arena, load("res://data/actors/knuckle_1.tres"), Brain.new(), foe_at, "Foe")
	foe.place(Transform3D(Basis.IDENTITY, foe_at))
	var brain := KeysBrain.new([{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 60, "hold": [&"guard"]}])
	var run: Dictionary = await _play(brain, 40, 0.0, Vector3.ZERO, arena)
	_use_device(Inputs.Device.KEYBOARD_MOUSE)
	return run


func test_a_pad_guard_with_no_lock_turns_to_the_nearest_foe() -> void:
	var behind: Dictionary = await _guard_facing_run(Inputs.Device.GAMEPAD, Vector3(0, 0, -2.5))
	assert_true((_at(behind, 40)["facing"] as Vector3).dot(Vector3(0, 0, -1)) > 0.99, "a foe behind him within 3.5 m: he comes round: %s" % [_at(behind, 40)["facing"]])
	assert_vec_near(_at(behind, 40)["position"], Vector3.ZERO, 1e-3, "and stays where he stands")
	behind["arena"].queue_free()
	await frames(1)
	var far: Dictionary = await _guard_facing_run(Inputs.Device.GAMEPAD, Vector3(0, 0, -5.0))
	assert_vec_near(_at(far, 40)["facing"], Vector3(0, 0, 1), 1e-6, "a foe at 5 m: he does not")
	far["arena"].queue_free()
	await frames(1)
	var mouse: Dictionary = await _guard_facing_run(Inputs.Device.KEYBOARD_MOUSE, Vector3(0, 0, -2.5))
	assert_vec_near(_at(mouse, 40)["facing"], Vector3(0, 0, 1), 1e-6, "on the keyboard and mouse the cursor decides, not the foe")


func test_a_direction_that_went_down_while_he_was_held_is_not_a_press() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), PlayerBrain.new())
	var other := TestArena.spawn(arena, load(ABARAX), Brain.new(), Vector3(5, 0, 0), "Other")
	var run := {"started": [], "ended": []}
	_watch(run, actor)
	_key_event(KEY_Q, true)
	await frames(30)
	actor.paired_with = other
	_key_event(KEY_D, true)
	await frames(5)
	actor.paired_with = null
	await frames(5)
	_key_event(KEY_Q, false)
	_key_event(KEY_D, false)
	await frames(2)
	var sways: Array = _ids(run).filter(func(id: StringName) -> bool: return String(id).begins_with("sway_"))
	assert_eq(sways, [], "D went down while he was paired: no sway when he is free: %s" % [run["started"]])


func test_a_direction_that_went_down_across_a_pause_is_not_a_press() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), PlayerBrain.new())
	var run := {"started": [], "ended": []}
	_watch(run, actor)
	_key_event(KEY_Q, true)
	await frames(30)
	get_tree().paused = true
	_key_event(KEY_D, true)
	await frames(5)
	get_tree().paused = false
	await frames(5)
	_key_event(KEY_Q, false)
	_key_event(KEY_D, false)
	await frames(2)
	var sways: Array = _ids(run).filter(func(id: StringName) -> bool: return String(id).begins_with("sway_"))
	assert_eq(sways, [], "D went down while the game was paused: no sway: %s" % [run["started"]])
