extends TestCase
## The Bilibara stretch's physics frame, headless (the spec's 3.6 budget as a proxy: the container has no GPU, so the cost of what the
## game does each step is held here and the cost of drawing it in tests/render/test_bilibara_cost.gd). The main scene in the stretch
## (the region's 1,000 pieces, its lamps and shadows, the HUD, the camera) in two plays of the physics step:
##
##   the walk   Abarax on a RouteBrain from the first shrine site, along the street, up the lane and into the yard's centre
##              (about 122 m: 1,400 frames)
##   the fight  three tier I Knuckles set on him in the yard, he walking laps round the yard's centre so that they chase and swing (the
##              stretch's worst: Actor._deflect at work on four bodies, the contact shadows and the three-foe brain)
##
## Each holds the quietest 120 steps' mean, the 99th percentile and the longest step, in the thread's own processor time (FrameMeter:
## see tests/support/frame_meter.gd for why that and not the wall clock). The walk's mean is the plan's 2.0 ms; the fight's is the
## combat budget's headless bound (tests/perf/test_combat_perf.gd, 3.0 ms; a rendered run takes its 4.0 ms). The longest step's
## bound is about twice what ten runs measured and under 40 ms (a hitch is what a player feels, and neither the mean nor the
## percentile sees a rare one). PERF_REPORT=1 prints both clocks.

const MAIN := "res://main/main.tscn"
const FOE := "res://data/actors/knuckle_1.tres"
const WALK: Array[String] = ["ShrineSite_A", "StreetEast", "LaneMid", "YardEntry", "YardCentre"]
const MOST_WALK_FRAMES := 2400
const FIGHT_FRAMES := 1200
const WALK_MEAN_MS := 2.0
const WALK_P99_MS := 4.0
const WALK_LONGEST_MS := 13.0
const FIGHT_MEAN_MS := 3.0
## What a rendered run is held to (the render shards cost the physics step more), as the combat budget's.
const FIGHT_MEAN_RENDERED_MS := 4.0
const FIGHT_P99_MS := 8.0
const FIGHT_LONGEST_MS := 25.0
## The yard's centre, and the laps Abarax walks in the fight (radius, metres).
const CENTRE := Vector3(27.5, 0.0, -65.0)
const LAP := 3.0

var _meter: FrameMeter
var _main: Main


func after_each() -> void:
	if _meter != null:
		_meter.detach()
	Game.reset()


func _stretch() -> Main:
	_meter = FrameMeter.new()  # one for each play: the test object is the same for both
	Game.reset()
	_main = track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	_main.enter_stretch()
	await frames(2)
	return _main


func _marker(name_: String) -> Vector3:
	return (_main.region.find_child(name_, true, false) as Marker3D).global_position


func _report(label: String, held: Dictionary) -> void:
	if OS.get_environment("PERF_REPORT") != "":
		print("PERF %s: %d steps; %s" % [label, held["count"], _meter.both()])


func test_the_walk_across_the_stretch_takes_the_step_no_more_than_two_ms() -> void:
	var main := await _stretch()
	var waypoints: Array[Vector3] = []
	for marker_name in WALK:
		waypoints.append(_marker(marker_name))
	main.player.place(Transform3D(Basis(), waypoints[0]))
	var brain := RouteBrain.new(waypoints.slice(1))
	main.player.set_brain(brain)
	await frames(2)
	_meter.attach(get_tree())
	var taken := 0
	while not brain.done and taken < MOST_WALK_FRAMES:
		await frames(1)
		taken += 1
	await get_tree().process_frame
	_meter.detach()
	var held := _meter.held()
	_report("the walk", held)
	assert_true(brain.done, "Abarax walked to the yard's centre (%d frames)" % taken)
	assert_true(held["count"] >= 600, "timed %d physics steps, 600 at least" % held["count"])
	assert_true(held["mean"] <= WALK_MEAN_MS, "the walk: a physics step takes %.3f ms in the quietest stretch (%s, budget %.1f ms); %s" % [held["mean"], held["basis"], WALK_MEAN_MS, _meter.both()])
	assert_true(held["p99"] <= WALK_P99_MS, "the walk: the 99th percentile of a physics step is %.3f ms (%s, budget %.1f ms); %s" % [held["p99"], held["basis"], WALK_P99_MS, _meter.both()])
	assert_true(held["max"] <= WALK_LONGEST_MS, "the walk: the longest physics step takes %.3f ms (%s, budget %.1f ms): a hitch a player feels; %s" % [held["max"], held["basis"], WALK_LONGEST_MS, _meter.both()])


func test_three_knuckles_in_the_yard_take_the_step_no_more_than_the_combat_budget() -> void:
	var main := await _stretch()
	# He cannot be killed in the minute: a fight with the player gone costs less.
	main.player.stats.max_hp = 1.0e9
	main.player.stats.hp = 1.0e9
	var lap: Array[Vector3] = []
	for k in 8:
		for i in 8:
			lap.append(CENTRE + Vector3(LAP, 0.0, 0.0).rotated(Vector3.UP, TAU * float(i) / 8.0))
	main.player.place(Transform3D(Basis(), lap[0]))
	main.player.set_brain(RouteBrain.new(lap))
	var foes: Array[Actor] = []
	for spot: Vector3 in [Vector3(-5.0, 0.0, -4.0), Vector3(5.0, 0.0, -4.0), Vector3(0.0, 0.0, -6.5)]:
		var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
		foe.def = load(FOE) as ActorDef
		foe.position = CENTRE + spot
		main.region.add_child(foe)
		foes.append(foe)
	await frames(2)
	_meter.attach(get_tree())
	await frames(FIGHT_FRAMES)
	await get_tree().process_frame
	_meter.detach()
	var alive := 0
	for foe in foes:
		if not foe.dead:
			alive += 1
	var held := _meter.held()
	_report("three Knuckles", held)
	var mean_budget := FIGHT_MEAN_MS if DisplayServer.get_name() == "headless" else FIGHT_MEAN_RENDERED_MS
	assert_eq(alive, 3, "the three foes were still there at the end: a fight with them gone costs less")
	assert_true(held["count"] >= FIGHT_FRAMES, "timed %d physics steps" % held["count"])
	assert_true(held["mean"] <= mean_budget, "three Knuckles: a physics step takes %.3f ms in the quietest stretch (%s, budget %.1f ms); %s" % [held["mean"], held["basis"], mean_budget, _meter.both()])
	assert_true(held["p99"] <= FIGHT_P99_MS, "three Knuckles: the 99th percentile of a physics step is %.3f ms (%s, budget %.1f ms); %s" % [held["p99"], held["basis"], FIGHT_P99_MS, _meter.both()])
	assert_true(held["max"] <= FIGHT_LONGEST_MS, "three Knuckles: the longest physics step takes %.3f ms (%s, budget %.1f ms): a hitch a player feels; %s" % [held["max"], held["basis"], FIGHT_LONGEST_MS, _meter.both()])
