extends TestCase
## What the camera shows of the people while a line is up: the bars and the dialogue box cover the picture's top and bottom,
## and a shot that holds a line is framed in the free band between them (CinePose.solve, CineOverlay.free_band). Measured
## with the game's own camera: the rows a 1.8 m figure standing at the aim covers on the picture, and how many of them are under
## a bar, the box or its name tab.

const STAGE_SCENE := preload("res://render/pixel_stage.tscn")
const FIXTURE := "res://scenes/story/fixture_yard_entrance/shots.tres"
const PLACES := {&"abarax": Vector3(0, 0, 5), &"knuckle": Vector3(-1.2, 0, 2.4)}
const HEIGHT := 1.8
## The most of the subject's rows that may be covered, and the share at the top of them that is the head.
const MAX_HIDDEN := 0.15
const HEAD := 0.15

var stage: PixelStage
var rig: CameraRig


func before_each() -> void:
	stage = track(STAGE_SCENE.instantiate()) as PixelStage
	var target := Node3D.new()
	stage.world.add_child(target)
	target.position = PLACES[&"abarax"]
	rig = CameraRig.new()
	rig.target = target
	rig.stage = stage
	stage.world.add_child(rig)
	target.reset_physics_interpolation()
	rig.snap_now()


func _world() -> Callable:
	return func(name: StringName) -> Variant: return PLACES.get(name, null)


func _shot(framing: Shot.Framing, aim: StringName, height: float, with_line := true) -> Shot:
	var shot := Shot.new()
	shot.framing = framing
	shot.aim = aim
	shot.aim_height = height
	shot.length = 60
	if with_line:
		shot.lines.append(DialogueLine.new())
	return shot


# The rows (first, last) a figure standing at `at` covers once the rig shows `pose`.
func _rows(pose: CinePose, at: Vector3) -> Vector2:
	rig.cine = pose
	rig.cine_weight = 1.0
	rig._apply()
	var feet := rig.camera.unproject_position(at).y - PixelSnap.MARGIN
	var head := rig.camera.unproject_position(at + Vector3.UP * HEIGHT).y - PixelSnap.MARGIN
	return Vector2(head, feet)


# The share of the rows `rows` that are under a bar, the box or the tab, given where the free band is.
func _hidden(rows: Vector2, band: Vector2i) -> float:
	var covered := maxf(0.0, band.x - rows.x) + maxf(0.0, rows.y - band.y)
	return minf(covered, rows.y - rows.x) / (rows.y - rows.x)


func test_a_person_in_a_shot_with_a_line_is_in_the_free_band() -> void:
	var band := CineOverlay.free_band(true)
	var shots := {
		"wide": [_shot(Shot.Framing.WIDE, &"abarax", 1.0), &"abarax"],
		"medium": [_shot(Shot.Framing.MEDIUM, &"knuckle", 1.0), &"knuckle"],
		"close": [_shot(Shot.Framing.CLOSE, &"abarax", 1.5), &"abarax"],
		"insert": [_shot(Shot.Framing.INSERT, &"abarax", 1.0), &"abarax"],
	}
	for key in shots:
		var shot: Shot = shots[key][0]
		var at: Vector3 = PLACES[shots[key][1]]
		var after := _rows(CinePose.solve(shot, 0.0, _world(), null, true), at)
		assert_true(_hidden(after, band) <= MAX_HIDDEN, "%s: %.0f%% of the subject is covered (rows %s)" % [key, _hidden(after, band) * 100.0, after])
		var head_end := after.x + (after.y - after.x) * HEAD
		assert_true(after.x >= band.x and head_end <= band.y, "%s: the head is inside the free band %s (rows %s)" % [key, band, after])
		# What it was: the aim in the middle of the picture, at the game's pitch, under the old box (its tab began at row 231).
		var old := CinePose.solve(shot, 0.0, _world(), null, true)
		old.aim = Vector3(at.x, shot.aim_height, at.z)
		old.pitch_deg = -40.0
		var before := _rows(old, at)
		print("FRAMING %s: covered before %.0f%%, after %.0f%%" % [key, _hidden(before, Vector2i(44, 231)) * 100.0, _hidden(after, band) * 100.0])


func test_an_over_the_shoulder_shot_keeps_both_figures_in_view() -> void:
	var scene := (load(FIXTURE) as SceneShots).duplicate_deep()
	var shot: Shot = scene.shots[3]
	assert_eq(shot.framing, Shot.Framing.OVER_SHOULDER)
	var band := CineOverlay.free_band(true)
	var pose := CinePose.solve(shot, 0.0, _world(), null, true)
	var subject := _rows(pose, PLACES[&"abarax"])
	var foreground := _rows(pose, PLACES[&"knuckle"])
	assert_true(1.0 - _hidden(subject, band) >= 0.95, "the subject is %.0f%% visible (rows %s)" % [(1.0 - _hidden(subject, band)) * 100.0, subject])
	assert_true(1.0 - _hidden(foreground, band) >= 0.70, "the foreground figure is %.0f%% visible (rows %s)" % [(1.0 - _hidden(foreground, band)) * 100.0, foreground])
	print("FRAMING over the shoulder: subject %.0f%% visible, foreground %.0f%%" % [(1.0 - _hidden(subject, band)) * 100.0, (1.0 - _hidden(foreground, band)) * 100.0])
