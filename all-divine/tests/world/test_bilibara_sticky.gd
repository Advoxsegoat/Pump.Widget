extends TestCase
## Nothing in the Bilibara stretch holds a body (the owner's rule: nothing is sticky). Abarax, run by a ScriptBrain, walks (the stick
## alone: a jog), sprints (dodge held) and hops (dodge tapped every 40 frames) at the things a body can run at: the 13 solid lantern
## posts, the house corners at the lane's mouth, the gate's curb, a vat, a kerb's end and the colonnade's end. A post is run at along
## its wall (on the hug line and 15 cm off it), at 45 degrees either way (aimed at it and 25 cm to either side) and dead on from the
## south (dead on, 1 cm, 5 cm and 10 cm aside); a corner at 45 degrees on its point and along each of its two faces.
##
## "Held" is how long the thing has the body: from the first frame the body touches it (a post: its own body; a corner: within 0.45 m
## of its point) to the last, and then, for a walk and a sprint, until the legs have their speed back (a third of a free run's), or the
## body has come to rest against something else (a wall that the stick still pushes it into is not the post's hold). A hop is held by
## the touch alone, on the frames its own dodge move is not playing: its legs are slow between hops whatever stands near. The rule: no run is held more than 15 frames (a quarter of a
## second). The table of every worst case goes to out/sticky_held.txt.

const BILIBARA := "res://world/bilibara/bilibara.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const BODY := 0.35
## The metres a body starts from its target, and the frames a run lasts.
const START := 4.0
const RUN_FRAMES := 180
## No run is held longer than this, in frames.
const LIMIT := 15
## A corner's contact counts within this of its point.
const POINT_REACH := 0.45
const MODES: Array[String] = ["walk", "sprint", "hop"]
## The posts' wall is this far from the post's middle (build_region's POST_WALL_GAP).
const WALL_GAP := 0.28
## Corners {point, out (the diagonal away from the thing), whether it stands in a wall's corner}: the lane's mouth, a vat, a kerb's end, the
## colonnade's end and the gate's curb. The last two stand against a wall: a 45-degree run that goes round their point ends in the angle
## between them and the wall, which holds a body as an inside corner does anywhere, so those two are run on their point and along their faces.
const CORNERS := {
	"lane mouth west (25, -5)": [Vector2(25, -5), Vector2(1, 1), false],
	"lane mouth east (30, -5)": [Vector2(30, -5), Vector2(-1, 1), false],
	"west vat (21.25, -65)": [Vector2(21.25, -65), Vector2(1, 1), false],
	"east vat (33.75, -65)": [Vector2(33.75, -65), Vector2(-1, 1), false],
	"kerb's end (30, -20)": [Vector2(30, -20), Vector2(-1, 1), false],
	"colonnade's end (20.2, -24.6)": [Vector2(20.2, -24.6), Vector2(1, 1), true],
	"gate's curb (-30, -4.5)": [Vector2(-30, -4.5), Vector2(1, 1), true],
}


func after_each() -> void:
	Game.reset()


func _spawn(region: Region, at: Vector3) -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.def = load(ABARAX) as ActorDef
	actor.position = at
	actor.set_brain(Brain.new())
	region.add_child(actor)
	return actor


func _steps(mode: String, way: Vector2) -> Array:
	match mode:
		"walk":
			return [{frames = RUN_FRAMES, move = way}]
		"sprint":
			return [{frames = RUN_FRAMES, move = way, hold = [&"dodge"]}]
	var steps := []
	for i in RUN_FRAMES / 40 + 1:
		steps.append({frames = 1, move = way, press = [&"dodge"], hold = [&"dodge"]})
		steps.append({frames = 39, move = way})
	return steps


# Runs the jobs {start, heading, mode, body (a post's) or point (a corner's)} together, far apart from each other: for each, the frames
# it touched its thing (0 or 1) and its legs' speed, and where it was.
func _run(region: Region, jobs: Array) -> Array:
	var actors: Array[Actor] = []
	for job: Dictionary in jobs:
		var actor := _spawn(region, Vector3(job.start.x, 0.0, job.start.y))
		actor.set_brain(ScriptBrain.new(_steps(job.mode, job.heading)))
		actors.append(actor)
	await frames(2)
	var out: Array[Dictionary] = []
	for job in jobs:
		out.append({touch = [], speed = [], at = [], busy = []})
	for i in RUN_FRAMES:
		await frames(1)
		for k in actors.size():
			var actor := actors[k]
			var job: Dictionary = jobs[k]
			var touched := 0
			for c in actor.get_slide_collision_count():
				var hit := actor.get_slide_collision(c)
				if absf(hit.get_normal().y) > 0.5:
					continue
				if job.has("body"):
					touched = 1 if hit.get_collider() == job.body else touched
				else:
					var p := hit.get_position()
					touched = 1 if Vector2(p.x, p.z).distance_to(job.point) < POINT_REACH else touched
			out[k].touch.append(touched)
			out[k].busy.append(1 if actor.runner.busy() else 0)
			out[k].speed.append(actor.locomotion.speed)
			out[k].at.append(Vector2(actor.global_position.x, actor.global_position.z))
	for actor in actors:
		actor.queue_free()
	await frames(1)
	return out


# The frames a run was held (see the top).
func _held(run: Dictionary, mode: String, cruise: float) -> int:
	var touch: Array = run.touch
	var busy: Array = run.busy
	var first := -1
	var last := -1
	for i in touch.size():
		# A hop's own move (the dodge-step and its recovery) is not the thing's hold: a hop is held while it can act and does not.
		if touch[i] == 1 and (mode != "hop" or busy[i] == 0):
			first = first if first >= 0 else i
			last = i
	if first < 0:
		return 0
	var end := last
	if mode != "hop":
		var speed: Array = run.speed
		var at: Array = run.at
		while end < speed.size() - 1 and speed[end] < 0.35 * cruise and at[end].distance_to(at[end + 1]) > 0.003:
			end += 1
	return end - first + 1


# Whether a body's ball overlaps the world at `at` (x, z).
func _occupied(space: PhysicsDirectSpaceState3D, at: Vector2) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = BODY - 0.03
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), Vector3(at.x, 0.5, at.y))
	query.collision_mask = Layers.WORLD
	return not space.intersect_shape(query, 1).is_empty()


func _blocked(space: PhysicsDirectSpaceState3D, from: Vector2, to: Vector2) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = BODY - 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), Vector3(from.x, 0.5, from.y))
	query.motion = Vector3(to.x - from.x, 0.0, to.y - from.y)
	query.collision_mask = Layers.WORLD
	var fraction := space.cast_motion(query)
	return fraction[0] < 1.0


# A free run's top legs' speed, by mode, in the middle of the yard.
func _cruises(region: Region) -> Dictionary:
	var out := {}
	for mode in MODES:
		var runs: Array = await _run(region, [{start = Vector2(27.5, -58), heading = Vector2(0, -1), mode = mode, point = Vector2(1e9, 1e9)}])
		var top := 0.0
		for v: float in runs[0].speed:
			top = maxf(top, v)
		out[mode] = top
	return out


# The cases of a post: [{label, start, heading}] (the post's wall to its north, its middle at `at`).
func _post_cases(at: Vector2, crowded: bool) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var wall_z := at.y - WALL_GAP
	for dx: int in [-1, 1]:
		for dz: float in [0.0, 0.15]:
			cases.append({label = "along the wall, %s, %.2f off the hug line" % ["east" if dx > 0 else "west", dz], start = Vector2(at.x + dx * START, wall_z + BODY + dz), heading = Vector2(-dx, 0)})
	for off: float in [0.0] if crowded else [0.0, 0.01, 0.05, 0.1]:
		cases.append({label = "dead on from the south, %.2f aside" % off, start = Vector2(at.x + off, at.y + START), heading = Vector2(0, -1)})
	if not crowded:
		for dx: int in [-1, 1]:
			var heading := Vector2(-dx, -1.0).normalized()
			for a: float in [0.0, -0.25, 0.25]:
				cases.append({label = "at 45 degrees from the %s, aimed %.2f aside" % ["south-east" if dx > 0 else "south-west", a], start = at + heading.orthogonal() * a - heading * START, heading = heading})
	return cases


# The cases of a corner (its point, and `out`, the diagonal away from the thing).
func _corner_cases(point: Vector2, out: Vector2, in_a_wall: bool) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var heading := -out.normalized()
	for a: float in [0.0] if in_a_wall else [0.0, 0.05, 0.2, -0.1]:
		cases.append({label = "at 45 degrees, aimed %.2f aside" % a, start = point + heading.orthogonal() * a - heading * START, heading = heading})
	cases.append({label = "along its first face", start = Vector2(point.x - out.x * START, point.y + out.y * BODY), heading = Vector2(out.x, 0)})
	cases.append({label = "along its second face", start = Vector2(point.x + out.x * BODY, point.y - out.y * START), heading = Vector2(0, out.y)})
	return cases


# The worst held frames over the jobs {label, thing, start, heading, mode, ...}; the table lines go to `table`.
func _worst(region: Region, jobs: Array, cruises: Dictionary, table: PackedStringArray) -> Array:
	var space := region.get_world_3d().direct_space_state
	var worst := 0
	var worst_label := ""
	var run_count := 0
	# Jobs of one batch must be far apart: those of the two close alcove posts go in a batch of their own.
	var batches := {}
	for job: Dictionary in jobs:
		var key: String = "%s|%s|%s" % [job.mode, job.label, job.batch]
		if not batches.has(key):
			batches[key] = []
		batches[key].append(job)
	for key: String in batches:
		var batch: Array = batches[key]
		var live: Array = []
		for job: Dictionary in batch:
			# A start that is not free, or a way with something else in it (a bench, a cart) before the target: not a case here.
			var target: Vector2 = job.target
			if _blocked(space, job.start, target - job.heading * 0.9):
				continue
			live.append(job)
		if live.is_empty():
			continue
		var runs: Array = await _run(region, live)
		for k in live.size():
			var job: Dictionary = live[k]
			var held := _held(runs[k], job.mode, cruises[job.mode])
			run_count += 1
			if held > worst:
				worst = held
				worst_label = "%s, %s, %s" % [job.thing, job.label, job.mode]
			if OS.get_environment("STICKY_ALL") == "1":
				table.append("%3d  %s, %s, %s" % [held, job.thing, job.label, job.mode])
			if held > LIMIT:
				table.append("HELD %3d  %s, %s, %s" % [held, job.thing, job.label, job.mode])
	return [worst, worst_label, run_count]


func _write(name: String, table: PackedStringArray) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path("res://out/").path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(table) + "\n")
		file.close()


func test_no_run_at_a_lantern_post_is_held_more_than_fifteen_frames() -> void:
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	await frames(2)
	var cruises: Dictionary = await _cruises(region)
	var jobs: Array = []
	var posts := 0
	for post: Node3D in region.get_node("Lanterns").get_children():
		var body := post.get_node_or_null("Body") as StaticBody3D
		if body == null:
			continue
		posts += 1
		var at := Vector2(post.global_position.x, post.global_position.z)
		# A bench, a cart or a stall within a metre and a half of the post: a pocket a body can be pushed into, which no post's shape opens.
		var space := region.get_world_3d().direct_space_state
		var crowded := false
		for dx: float in [-0.95, 0.95]:
			for dz: float in [0.1, 0.6]:
				crowded = crowded or _occupied(space, at + Vector2(dx, dz))
		for c in _post_cases(at, crowded):
			for mode in MODES:
				jobs.append({thing = String(post.name), label = c.label, start = c.start, heading = c.heading, mode = mode, body = body, target = at,
						batch = 1 if absf(at.x - 36.9) < 0.1 else 0})
	var table := PackedStringArray()
	var result: Array = await _worst(region, jobs, cruises, table)
	_write("sticky_held_posts.txt", table)
	assert_eq(posts, 13, "13 solid posts")
	assert_true(result[2] > 200, "the runs were made (%d)" % result[2])
	assert_eq(table.slice(0, 8), PackedStringArray(), "no run at a post is held more than %d frames (the worst: %d, %s; %d runs)" % [LIMIT, result[0], result[1], result[2]])


func test_no_run_at_a_corner_is_held_more_than_fifteen_frames() -> void:
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	await frames(2)
	var cruises: Dictionary = await _cruises(region)
	var jobs: Array = []
	for corner_name: String in CORNERS:
		var point: Vector2 = CORNERS[corner_name][0]
		for c in _corner_cases(point, CORNERS[corner_name][1], CORNERS[corner_name][2]):
			for mode in MODES:
				jobs.append({thing = corner_name, label = c.label, start = c.start, heading = c.heading, mode = mode, point = point, target = point, batch = 0})
	var table := PackedStringArray()
	var result: Array = await _worst(region, jobs, cruises, table)
	_write("sticky_held_corners.txt", table)
	assert_true(result[2] > 60, "the runs were made (%d)" % result[2])
	assert_eq(table.slice(0, 8), PackedStringArray(), "no run at a corner is held more than %d frames (the worst: %d, %s; %d runs)" % [LIMIT, result[0], result[1], result[2]])


const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"
const KNUCKLE_BRAIN := "res://data/brains/knuckle_1.tres"
const FOE_FRAMES := 540
## What is not yet true of the foes, with why: a place named here is held to its own ceiling (frames), and the test fails with "remove its
## entry" once the place meets LIMIT, so that a cure cannot go unnoticed.
const FOES_NOT_YET := {
}


# Three Knuckles set on a player who stands still on the far side of a thing from them (the thing between the foes and him, on their straight
# line): the longest run of frames a foe presses on a solid thing without moving (a collision with something that is not the ground, and
# under a centimetre moved in the frame), and the nearest any foe came to the player.
func _chase(region: Region, player_at: Vector2, foes_at: Array[Vector2]) -> Dictionary:
	var abarax := _spawn(region, Vector3(player_at.x, 0.0, player_at.y))
	var foes: Array[Actor] = []
	for at in foes_at:
		var foe := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
		foe.def = load(KNUCKLE_1) as ActorDef
		foe.position = Vector3(at.x, 0.0, at.y)
		var brain := Watched.new(load(KNUCKLE_BRAIN) as BrainDef, 7)
		brain.target = abarax
		foe.set_brain(brain)
		region.add_child(foe)
		brain.mode = EnemyBrain.Mode.ENGAGED
		foes.append(foe)
	await frames(2)
	var run: Array[int] = []
	var longest: Array[int] = []
	var last: Array[Vector3] = []
	for foe in foes:
		run.append(0)
		longest.append(0)
		last.append(foe.global_position)
	var nearest := INF
	for i in FOE_FRAMES:
		await frames(1)
		for k in foes.size():
			var foe := foes[k]
			var touching := false
			for c in foe.get_slide_collision_count():
				var hit := foe.get_slide_collision(c)
				if absf(hit.get_normal().y) < 0.5 and not hit.get_collider() is Actor:
					touching = true
			var moved := foe.global_position.distance_to(last[k])
			last[k] = foe.global_position
			# A press is a foe whose brain asks his legs to go, who touches a thing and does not move: one who stands by choice is not held.
			var asked := (foe.brain as Watched).asked.length() > 0.1
			run[k] = run[k] + 1 if asked and touching and moved < 0.01 and not foe.runner.busy() else 0
			longest[k] = maxi(longest[k], run[k])
			nearest = minf(nearest, Vector2(foe.global_position.x - abarax.global_position.x, foe.global_position.z - abarax.global_position.z).length())
	for foe in foes:
		foe.queue_free()
	abarax.queue_free()
	await frames(1)
	return {longest = longest, nearest = nearest}


func test_three_foes_set_on_a_player_behind_a_post_a_corner_and_a_vat_press_on_nothing_more_than_fifteen_frames() -> void:
	var region := track((load(BILIBARA) as PackedScene).instantiate()) as Region
	await frames(2)
	# The foes come from a few metres apart (a crowd that all runs at the one spot jams on itself, which is not what a thing does to it). The
	# foes' straight line to him meets, in turn: the street's post at (-5, -4.72) along its front, the lane mouth's corner at (25, -5), the
	# west vat.
	var places := {
		"the post at (-5, -4.72)": [Vector2(-6.6, -4.6), [Vector2(0.0, -4.6), Vector2(2.5, -4.1), Vector2(5.0, -3.6)] as Array[Vector2]],
		"the corner at (25, -5)": [Vector2(27.5, -9.0), [Vector2(19.0, -1.6), Vector2(18.0, -2.8), Vector2(17.0, -1.6)] as Array[Vector2]],
		"the west vat (20, -66.25)": [Vector2(20.0, -62.0), [Vector2(18.2, -71.0), Vector2(20.0, -73.0), Vector2(21.8, -71.0)] as Array[Vector2]],
	}
	var table := PackedStringArray()
	var worst := 0
	for label: String in places:
		var result: Dictionary = await _chase(region, places[label][0], places[label][1])
		var longest: Array = result.longest
		table.append("%s: longest press by each foe %s frames, the nearest any came to the player %.1f m" % [label, longest, result.nearest])
		var here := 0
		for frames_pressed: int in longest:
			here = maxi(here, frames_pressed)
		if FOES_NOT_YET.has(label):
			var ceiling: int = FOES_NOT_YET[label][0]
			assert_true(here > LIMIT, "%s: no foe presses more than %d frames now (%d): remove its entry from FOES_NOT_YET" % [label, LIMIT, here])
			assert_true(here <= ceiling, "%s: not yet within %d frames, and no worse than %d (%d): %s" % [label, LIMIT, ceiling, here, FOES_NOT_YET[label][1]])
		else:
			worst = maxi(worst, here)
		assert_true(result.nearest < 3.5, "%s: the foes came to the player (%.1f m)" % [label, result.nearest])
	_write("sticky_held_foes.txt", table)
	assert_true(worst <= LIMIT, "no foe presses on a thing more than %d frames (the worst: %d; %s)" % [LIMIT, worst, "; ".join(table)])


## An EnemyBrain that remembers how hard it asked the legs to go on its last frame.
class Watched extends EnemyBrain:
	var asked := Vector2.ZERO

	func think(actor: Actor, delta: float) -> Intent:
		var intent := super(actor, delta)
		asked = intent.move if intent != null else Vector2.ZERO
		return intent
