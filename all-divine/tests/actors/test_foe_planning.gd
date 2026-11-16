extends TestCase
## A foe's way round a wall costs the game nothing it would notice (Task 15c, fix round 1). The planner is a breadth-first search over a
## grid of up to 33 x 33 cells with a shape query for each; the first version ran it on every frame for every foe who found no way (a wall
## over 19 m, a closed room, a shut gate) and for every foe on the frame all eight lost their line together: 17 to 82 ms a step, 62 ms for
## eight foes behind a 6 m wall.
##
## The rule, held here in the thread's own processor time (FrameMeter): with up to eight foes in each of the places below, no physics step
## costs more than STEP_OVER ms more than the same fight cost on the base (d11e1b7, the brain before Task 15c), and the quietest
## FrameMeter.WINDOW steps' mean is within QUIET_OVER ms of the base's. A foe plans at most PLAN_RATE ways a second, and one who has
## no way at all (a shut gate, a closed room) goes to the nearest place to his target he can reach and waits there.
##
## The base's numbers, thread time, ms, on a machine at a load of 1: the range of its longest step and of its quietest 120 steps over eight runs
## (nine for the 6 m wall), and the head before this round (402cf55, three runs).
##   place                       base longest   base quiet    402cf55 longest   402cf55 quiet
##   40 m wall, 3 foes           9.8 - 16.6     1.32 - 1.47   27.3 - 35.8       14.7 - 15.7
##   40 m wall, 8 foes           4.2 - 7.8      2.71 - 3.07   75.1 - 83.6       43.7
##   closed room, 8 foes         4.6 - 8.1      2.65 - 3.10   130.7 - 139.6     75.8 - 76.3
##   6 m wall, 8 foes step in    4.7 - 15.4     2.66 - 3.11   46.6 - 51.1       2.7 - 3.1
##   gate, 8 foes step in        6.4 - 11.4     2.70 - 2.96   5.5 - 9.7         2.9 - 3.0
##   town shut gate, 3 foes      3.1 - 4.3      1.37 - 1.61   23.7 - 29.2       1.7 - 1.9
## BASE holds the largest of each, so a bound is the worst the base was seen to do, plus the rule's allowance. The base's rare long step (a
## sound or a hit effect starting) is in it: it is 5 to 10 ms where it happens.

## These fights are judged by positions, moves and clocks, never by a picture: a rendered run plays them with the drawing off (TestRunner).
const DRAWS := false

const FAR := 40.0
const FRAMES := 600
const STEP_OVER := 8.0
const QUIET_OVER := 0.5
## Plans a foe may make in a second, over a fight with a still target. A person does not see a foe look for his way once a second; one
## who does it every frame is what the cost was.
const PLAN_RATE := 0.5
const KNUCKLES := ["knuckle_1", "knuckle_1", "knuckle_1"]
const FOES_AT := [Vector2(-1.2, -2.3), Vector2(0.0, -2.6), Vector2(1.2, -2.3)]
const TOWN_FRAMES := 800
const BILIBARA := "res://world/bilibara/bilibara.tscn"

## [longest step, quietest window] of the base (d11e1b7) in each place: the largest of its runs, ms of thread time.
const BASE := {
	"wall40x3": [16.6, 1.47],
	"wall40x8": [7.8, 3.07],
	"room8": [8.1, 3.10],
	"wall6x8": [15.4, 3.11],
	"gate8": [11.4, 2.96],
	"town": [4.3, 1.61],
}


static func _eight() -> Array:
	var kinds: Array = []
	for i in 8:
		kinds.append("knuckle_1")
	return kinds


static func _row(y: float, stagger := 0.5) -> Array:
	var row: Array = []
	for i in 8:
		row.append(Vector2(-3.5 + i, y - (i % 2) * stagger))
	return row


static func _walls(place: String) -> Array:
	match place:
		"wall6":
			return [[Vector3(0, 1.5, 0), Vector3(6, 3, 0.2)]]
		"wall40":
			return [[Vector3(0, 1.5, 0), Vector3(40, 3, 0.2)]]
		"room":
			return [[Vector3(0, 1.5, 1.5), Vector3(3, 3, 0.2)], [Vector3(0, 1.5, -1.5), Vector3(3, 3, 0.2)], [Vector3(1.5, 1.5, 0), Vector3(0.2, 3, 3)], [Vector3(-1.5, 1.5, 0), Vector3(0.2, 3, 3)]]
		"gate":
			return [[Vector3(-6.0, 1.5, 0), Vector3(10, 3, 0.8)], [Vector3(6.0, 1.5, 0), Vector3(10, 3, 0.8)]]
	return []


## One fight in an arena of its own: `kinds` engaged with a still Abarax at `player_at`, behind the walls of `place`.
func _fight(place: String, origin: Vector3, kinds: Array, player_at: Vector3, foes_at: Array, parent: Node3D = null) -> Dictionary:
	var arena := parent
	if arena == null:
		arena = TestArena.make(self)
		arena.position = origin
		for w: Array in _walls(place):
			TestArena.wall(arena, w[0], w[1])
	if AttackTokens.of(arena) == null:
		arena.add_child(AttackTokens.new())
	var player := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 1000.0), Brain.new(), player_at, "A")
	player.place(Transform3D(Basis(Vector3.UP, PI), origin + player_at))
	var foes: Array[Actor] = []
	for i in kinds.size():
		var def := load("res://data/actors/%s.tres" % kinds[i]) as ActorDef
		var at := Vector3(foes_at[i].x, 0, foes_at[i].y)
		var brain := EnemyBrain.new(def.brain, 7 + i)
		var foe := TestArena.spawn(arena, def, brain, at, "Foe%d" % (i + 1))
		foe.place(Transform3D(Basis(Vector3.UP, atan2(-(player_at.x - at.x), -(player_at.z - at.z))), origin + at))
		brain.target = player
		brain.mode = EnemyBrain.Mode.ENGAGED
		brain._engage(foe)
		foes.append(foe)
	return {"arena": arena, "player": player, "foes": foes}


## The plans a foe has made so far (-1 where the brain does not count them: the base).
static func _plans(foe: Actor) -> int:
	var count: Variant = foe.brain.get("plans")
	return int(count) if count != null else -1


## Plays `run` for `frames_n` steps under a FrameMeter; the player is healed each frame. Returns the meter.
func _timed(run: Dictionary, frames_n := FRAMES, step := {}) -> FrameMeter:
	var meter := FrameMeter.new()
	meter.attach(get_tree())
	for f in frames_n:
		await frames(1)
		(run["player"] as Actor).stats.refill()
		if not step.is_empty() and f == step["frame"]:
			(run["player"] as Actor).place(Transform3D(Basis(Vector3.UP, PI), step["to"]))  # he ducks behind the wall: every foe loses his line on this frame
	await get_tree().process_frame
	meter.detach()
	if OS.get_environment("FOE_PLAN_SPIKES") != "":
		var spikes := []
		for i in meter.cpu.size():
			if meter.cpu[i] > 6000:
				spikes.append("%d:%.0f" % [i, meter.cpu[i] / 1000.0])
		_report("spikes (frame:ms) %s\n" % [spikes])
	return meter


func _free(run: Dictionary, keep_arena := false) -> void:
	for node in Sfx.playing_nodes():
		node.stop()
	OS.delay_msec(150)
	if keep_arena:
		for foe: Actor in run["foes"]:
			foe.free()
		(run["player"] as Actor).free()
	elif is_instance_valid(run["arena"]):
		(run["arena"] as Node).free()


## Plays the place and holds its cost; `label` is its key in BASE. The report line (FOE_PLAN_REPORT=<file>) is the table's row.
func _hold_cost(label: String, place: String, kinds: Array, player_at: Vector3, foes_at: Array, step := {}) -> Dictionary:
	var run := _fight(place, Vector3.ZERO, kinds, player_at, foes_at)
	var meter := await _timed(run, FRAMES, step)
	var held := meter.held()
	var plans: Array = []
	for foe: Actor in run["foes"]:
		plans.append(_plans(foe))
	var line := "%s: longest %.2f ms, quietest %d steps %.2f ms (thread time); plans per foe %s; final %s\n" % [label, held["max"], FrameMeter.WINDOW, held["mean"], plans,
			(run["foes"] as Array).map(func(a: Actor) -> String: return "(%.1f,%.1f)" % [a.global_position.x, a.global_position.z])]
	_report(line)
	var result := {"longest": held["max"], "quiet": held["mean"], "plans": plans, "foes": (run["foes"] as Array).map(func(a: Actor) -> Vector3: return a.global_position), "label": label}
	_free(run)
	if BASE.has(label):
		var base: Array = BASE[label]
		assert_true(held["max"] <= base[0] + STEP_OVER, "%s: the longest physics step is %.2f ms, at most %.1f ms over the base's %.2f (%s)" % [label, held["max"], STEP_OVER, base[0], line.strip_edges()])
		assert_true(held["mean"] <= base[1] + QUIET_OVER, "%s: the quietest %d steps average %.2f ms, at most %.1f ms over the base's %.2f (%s)" % [label, FrameMeter.WINDOW, held["mean"], QUIET_OVER, base[1], line.strip_edges()])
	return result


func _report(line: String) -> void:
	var path := OS.get_environment("FOE_PLAN_REPORT")
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	f.seek_end()
	f.store_string(line)
	f.close()


func _hold_rate(result: Dictionary, label: String) -> void:
	var seconds := FRAMES / 60.0
	for count: int in result["plans"]:
		if count >= 0:
			assert_true(count / seconds <= PLAN_RATE, "%s: a foe plans at most %.1f ways a second (%d plans in %.0f s)" % [label, PLAN_RATE, count, seconds])


func test_three_foes_behind_a_forty_metre_wall() -> void:
	var r := await _hold_cost("wall40x3", "wall40", KNUCKLES, Vector3(0, 0, 0.7), FOES_AT)
	_hold_rate(r, "wall40x3")


func test_eight_foes_behind_a_forty_metre_wall() -> void:
	var r := await _hold_cost("wall40x8", "wall40", _eight(), Vector3(0, 0, 0.7), _row(-2.3))
	_hold_rate(r, "wall40x8")


func test_eight_foes_round_a_closed_room() -> void:
	var r := await _hold_cost("room8", "room", _eight(), Vector3(0, 0, 0), _row(-3.3))
	_hold_rate(r, "room8")


func test_eight_foes_behind_a_six_metre_wall() -> void:
	# The player stands in front of the wall with the eight round him, then steps behind it: all eight lose the line on one frame.
	var r := await _hold_cost("wall6x8", "wall6", _eight(), Vector3(0, 0, -3.2), _row(-5.6, 1.0), {"frame": 30, "to": Vector3(0, 0, 0.7)})
	_hold_rate(r, "wall6x8")


func test_eight_foes_and_a_player_behind_a_gate() -> void:
	var gate_row: Array = []
	for i in 8:
		gate_row.append(Vector2(-3.5 + i, 5.5 + (i % 2) * 1.0))
	var r := await _hold_cost("gate8", "gate", _eight(), Vector3(0, 0, 3.5), gate_row, {"frame": 30, "to": Vector3(0, 0, -2.0)})
	_hold_rate(r, "gate8")


func test_a_foe_at_the_towns_shut_gate_plans_a_few_times_and_waits_facing_the_player() -> void:
	# Three foes in the court south of the town's shut shortcut gate with the player in the loop lane beyond it (the review's place): no way
	# round within the grid. The first version planned on every frame for about 800 frames at 11 ms a call. The gate's face is 3.9 m from him.
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Node3D
	await frames(2)
	var player_at := Vector3(-32.5, 0, -8.0)
	var run := _fight("none", Vector3.ZERO, KNUCKLES, player_at, [Vector2(-32.5, -1.0), Vector2(-34.0, 0.0), Vector2(-31.0, 0.0)], region)
	var meter := await _timed(run, TOWN_FRAMES)
	var held := meter.held()
	var plans: Array = []
	var ends: Array = []
	for foe: Actor in run["foes"]:
		plans.append(_plans(foe))
		var to := Vector2(player_at.x - foe.global_position.x, player_at.z - foe.global_position.z)
		ends.append([to.length(), absf(rad_to_deg(angle_difference(foe.rotation.y, Locomotion.yaw_of(to))))])
	_report("town: longest %.2f ms, quietest %d steps %.2f ms; plans per foe in %d frames %s; (distance to him, degrees off facing him) %s\n" % [held["max"], FrameMeter.WINDOW, held["mean"], TOWN_FRAMES, plans, ends])
	var label := "town"
	var base: Array = BASE[label]
	assert_true(held["max"] <= base[0] + STEP_OVER, "%s: the longest physics step is %.2f ms, at most %.1f ms over the base's %.2f" % [label, held["max"], STEP_OVER, base[0]])
	assert_true(held["mean"] <= base[1] + QUIET_OVER, "%s: the quietest %d steps average %.2f ms, at most %.1f ms over the base's %.2f" % [label, FrameMeter.WINDOW, held["mean"], QUIET_OVER, base[1]])
	for i in plans.size():
		assert_true(plans[i] < 0 or plans[i] <= PLAN_RATE * TOWN_FRAMES / 60.0, "%s: foe %d plans at most %.1f ways a second (%d plans in %d frames)" % [label, i, PLAN_RATE, plans[i], TOWN_FRAMES])
		assert_true(ends[i][0] <= 4.8, "%s: foe %d waits at the nearest place he can reach, not further than 4.8 m from the player (%.1f m)" % [label, i, ends[i][0]])
		assert_true(ends[i][1] <= 30.0, "%s: foe %d waits facing the player (%.0f degrees off)" % [label, i, ends[i][1]])
	_free(run, true)
	Game.reset()
