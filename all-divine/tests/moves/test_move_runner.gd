extends TestCase
## The move runner inside an actor: a press starts a move on its own frame; the clip's marks turn the
## hitboxes and invulnerability on and off on the frames they sit on; a press made up to 9 frames before a
## cancel window opens comes out on the window's first frame, and an older one is dropped; the roll goes
## as far as its clip's root motion (times the move's root_motion_scale), along the stick if it is pushed;
## and holding dodge through a roll sprints after it.
##
## Each test stands Abarax in an arena with a ScriptBrain. A move frame counts the actor's frames since
## the move started: 0 is the frame it started on. The jab's lead hand is palm_l (the clips' marks say so;
## test_move_data.gd checks them).

const ABARAX := "res://data/actors/abarax.tres"
const DT := 1.0 / 60


## Plays `steps` and then `after` more frames, and returns what happened, frame by frame:
##   actor     the Actor
##   started   [[move id, actor frame], ...] from move_started
##   ended     [[move id, actor frame, cancelled], ...] from move_ended
##   frames    one Dictionary per actor frame (the state after that frame): frame, move (its id, or &""),
##             invulnerable, hitboxes (active ids), position, facing, speed, sprinting
## The actor starts at the origin facing `yaw`.
func _run(steps: Array, after: int, yaw := 0.0) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	actor.rotation.y = yaw
	actor.locomotion.facing_yaw = yaw
	var run := {"actor": actor, "started": [], "ended": [], "frames": []}
	actor.runner.move_started.connect(func(m: MoveData) -> void: run["started"].append([m.id, actor.frame]))
	actor.runner.move_ended.connect(func(m: MoveData, cancelled: bool) -> void:
		run["ended"].append([m.id, actor.frame, cancelled]))
	var total := after
	for step: Dictionary in steps:
		total += int(step["frames"])
	while actor.frame < total:
		await frames(1)
		var current := actor.runner.current
		run["frames"].append({
			"frame": actor.frame,
			"move": current.id if current != null else &"",
			"invulnerable": actor.is_invulnerable(),
			"hitboxes": actor.rig.active_hitboxes(),
			"position": actor.global_position,
			"facing": actor.facing(),
			"speed": actor.locomotion.speed,
			"sprinting": actor.locomotion.sprinting,
		})
	return run


# The actor frame `id` first started on, or -1.
func _start_of(run: Dictionary, id: StringName) -> int:
	for entry: Array in run["started"]:
		if entry[0] == id:
			return entry[1]
	return -1


# The move frames of `id` (from its first start) whose frame state passes `pick`.
func _move_frames(run: Dictionary, id: StringName, pick: Callable) -> Array:
	var start := _start_of(run, id)
	var found := []
	for state: Dictionary in run["frames"]:
		if state["move"] == id and pick.call(state):
			found.append(state["frame"] - start)
	return found


# The frame state after actor frame `f`.
func _at(run: Dictionary, f: int) -> Dictionary:
	for state: Dictionary in run["frames"]:
		if state["frame"] == f:
			return state
	fail("no state for frame %d" % f)
	return {"position": Vector3.INF, "facing": Vector3.INF, "speed": NAN, "sprinting": false}


func _count(run: Dictionary, pick: Callable) -> int:
	return run["frames"].filter(pick).size()


func _jab() -> MoveData:
	return Registry.fetch(&"moves", &"palm_jab") as MoveData


func _roll() -> MoveData:
	return Registry.fetch(&"moves", &"dodge_roll") as MoveData


func test_palm_when_idle_starts_jab_the_same_frame() -> void:
	var run: Dictionary = await _run([{"frames": 10}, {"frames": 1, "press": [&"palm"]}], 5)
	assert_eq(run["started"], [[&"palm_jab", 11]])
	assert_eq(_at(run, 10)["move"], &"", "nothing before the press")
	assert_eq(_at(run, 11)["move"], &"palm_jab", "running on the press frame itself")


func test_jab_hitbox_active_frames_10_to_14() -> void:
	var run: Dictionary = await _run([{"frames": 10}, {"frames": 1, "press": [&"palm"]}], 40)
	var lead := func(s: Dictionary) -> bool: return s["hitboxes"].has(&"palm_l")
	assert_eq(_move_frames(run, &"palm_jab", lead), range(10, 15))
	assert_eq(_count(run, func(s: Dictionary) -> bool: return not s["hitboxes"].is_empty()), 5, "no other hitbox, no other frame")
	assert_eq(run["ended"], [[&"palm_jab", 46, false]], "the jab's 35 frames, then it ends by itself")


func test_roll_iframes_are_13_frames() -> void:
	var run: Dictionary = await _run([{"frames": 10}, {"frames": 1, "press": [&"dodge"]}], 40)
	var invulnerable := func(s: Dictionary) -> bool: return s["invulnerable"]
	assert_eq(_move_frames(run, &"dodge_roll", invulnerable), range(3, 16))
	assert_eq(_count(run, invulnerable), 13, "and at no other time")
	assert_eq(run["ended"], [[&"dodge_roll", 41, false]], "30 frames")


func test_buffered_palm_comes_out_on_window_open() -> void:
	# Jab from frame 11; palm again at jab f11 (frame 22), four frames before its cancel window opens.
	var run: Dictionary = await _run([
		{"frames": 10}, {"frames": 1, "press": [&"palm"]},
		{"frames": 10}, {"frames": 1, "press": [&"palm"]},
	], 30)
	assert_eq(run["started"], [[&"palm_jab", 11], [&"palm_cross", 26]], "the cross at jab f15")
	assert_eq(run["ended"].front(), [&"palm_jab", 26, true], "cancelling the jab")


func test_buffered_dodge_comes_out_on_recovery() -> void:
	# Dodge at jab f14 (frame 25): the f15 window takes only palm, so it waits for the f20 one.
	var run: Dictionary = await _run([
		{"frames": 10}, {"frames": 1, "press": [&"palm"]},
		{"frames": 13}, {"frames": 1, "press": [&"dodge"]},
	], 30)
	assert_eq(run["started"], [[&"palm_jab", 11], [&"dodge_roll", 31]], "the roll at jab f20")
	assert_eq(run["ended"].front(), [&"palm_jab", 31, true])


func test_too_early_dodge_expires() -> void:
	# Dodge at jab f10 (frame 21): 10 frames old when the dodge window opens at f20, one past the buffer.
	var run: Dictionary = await _run([
		{"frames": 10}, {"frames": 1, "press": [&"palm"]},
		{"frames": 9}, {"frames": 1, "press": [&"dodge"]},
	], 40)
	assert_eq(run["started"], [[&"palm_jab", 11]], "no roll")
	assert_eq(run["ended"], [[&"palm_jab", 46, false]], "the jab runs to its f35")


func test_large_delta_fires_every_mark_once() -> void:
	# Two ticks of 0.3 s: the first passes f5 to f18, so it turns the hitbox on and off again inside one
	# tick; the second passes f20 and the clip's end (f35). (Two ticks of 0.1 s would stop at f12, before
	# the hitbox_off at f15, so they could not show hitbox_off arriving once.)
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new([]))
	var got: Array = []
	actor.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void: got.append(kind))
	var jab := _jab()
	actor.runner.start(jab)
	actor.runner.tick(Intent.new(), 0.3)
	var hitboxes_after_first := actor.rig.active_hitboxes()
	actor.runner.tick(Intent.new(), 0.3)
	var want := Marks.read(actor.rig.tree.get_animation(jab.clip)).map(func(m: Dictionary) -> StringName: return m["kind"])
	assert_eq(got, want, "every mark of the clip, in its order")
	assert_eq(got.count(&"hitbox_on"), 1)
	assert_eq(got.count(&"hitbox_off"), 1)
	assert_eq(hitboxes_after_first, [] as Array[StringName], "on and off in one tick leaves it off")
	assert_false(actor.runner.busy(), "the second tick passes the clip's end")


func test_start_fires_the_marks_at_time_zero() -> void:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new([]))
	var got: Array = []
	actor.runner.mark.connect(func(kind: StringName, args: Dictionary) -> void: got.append([kind, args]))
	actor.runner.start(_roll())
	assert_eq(got, [[&"sfx", {"name": &"roll_cloth"}]], "the roll's f0 sound, on the start itself")
	actor.runner.tick(Intent.new(), DT)
	assert_eq(got.size(), 1, "and not again on the next tick")


func test_roll_root_motion_matches_clip() -> void:
	# No stick: the roll goes along the facing the actor already has (here a yaw of 0.7).
	var yaw := 0.7
	var run: Dictionary = await _run([{"frames": 5}, {"frames": 1, "press": [&"dodge"]}], 40, yaw)
	assert_eq(run["started"], [[&"dodge_roll", 6]])
	assert_eq(run["ended"], [[&"dodge_roll", 36, false]])
	var actor: Actor = run["actor"]
	var roll := _roll()
	var clip := actor.rig.tree.get_animation(roll.clip)
	var root := clip.find_track(actor.rig.tree.root_motion_track, Animation.TYPE_POSITION_3D)
	assert_true(root >= 0, "the roll's clip has a root track")
	var travel := clip.position_track_interpolate(root, clip.length) - clip.position_track_interpolate(root, 0.0)
	travel.y = 0.0
	var want := Basis(Vector3.UP, yaw) * travel * roll.root_motion_scale
	var moved: Vector3 = _at(run, 36)["position"] - _at(run, 5)["position"]
	moved.y = 0.0
	var along := Vector3(sin(yaw), 0, cos(yaw))
	assert_near(moved.dot(along), want.length(), 0.02, "along the facing")
	assert_vec_near(moved, want, 0.02, "and nowhere else")
	assert_true(want.length() > 2.5 and want.length() < 3.5, "about 3 m: %s" % want.length())
	assert_vec_near(_at(run, 46)["position"], _at(run, 36)["position"], 1e-3, "and it stops there")


func test_roll_snaps_to_stick_direction() -> void:
	# Facing +Z, roll with the stick pushed east: the roll faces east on its first frame (a turn would
	# take 7 or 8 frames) and goes east.
	var run: Dictionary = await _run([{"frames": 5}, {"frames": 1, "press": [&"dodge"], "move": Vector2(1, 0)}], 40)
	assert_eq(run["started"], [[&"dodge_roll", 6]])
	assert_vec_near(_at(run, 5)["facing"], Vector3(0, 0, 1), 1e-6)
	assert_vec_near(_at(run, 6)["facing"], Vector3(1, 0, 0), 1e-6, "snapped on the roll's first frame")
	var actor: Actor = run["actor"]
	assert_near(actor.locomotion.facing_yaw, PI / 2, 1e-6, "locomotion faces that way too")
	var moved: Vector3 = _at(run, 36)["position"] - _at(run, 5)["position"]
	assert_true(moved.x > 2.5, "rolled %s east" % moved.x)
	assert_near(moved.z, 0.0, 0.02, "and not along the old facing")


func test_sprint_after_held_roll() -> void:
	# Press and hold dodge with the stick pushed: the roll (frames 6 to 36), then a sprint while dodge
	# stays held; let go, and back down to a jog.
	var east := Vector2(1, 0)
	var run: Dictionary = await _run([
		{"frames": 5},
		{"frames": 1, "press": [&"dodge"], "hold": [&"dodge"], "move": east},
		{"frames": 90, "hold": [&"dodge"], "move": east},
		{"frames": 40, "move": east},
	], 0)
	var tuning: LocomotionTuning = (load(ABARAX) as ActorDef).locomotion
	assert_eq(run["started"], [[&"dodge_roll", 6]], "holding does not roll again")
	assert_eq(_count(run, func(s: Dictionary) -> bool: return s["sprinting"] and s["frame"] <= 36), 0, "no sprint during the roll")
	var held := _at(run, 96)
	assert_true(held["sprinting"], "sprinting after the roll")
	assert_near(held["speed"], tuning.sprint_speed, 1e-6, "at sprint_speed")
	var released := _at(run, 136)
	assert_false(released["sprinting"])
	assert_near(released["speed"], tuning.jog_speed, 1e-6, "let go: jog")
