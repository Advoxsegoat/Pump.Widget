extends TestCase
## The heavy Knuckle's gait (F1 Task 14d, fix round 1): a big body's stride is longer, so its locomotion clips play at a cadence of
## their own (LocomotionTuning.cadence) and its feet hold the floor as a body's own would. Measured on a flat floor, the actor
## walking, jogging and sprinting along +X for 3 s: `slide` is how fast a stance foot goes back against the body, in the clips'
## own pose, against how fast the body goes (1 is a planted foot: no slide), `toe` the lowest the toes get against the floor.

const HEAVY := "res://data/actors/knuckle_heavy.tres"
const TIER_1 := "res://data/actors/knuckle_1.tres"
const TIER_3 := "res://data/actors/knuckle_3.tres"
const ABARAX := "res://data/actors/abarax.tres"
const GAITS := {&"walk": [0.5, false], &"jog": [1.0, false], &"sprint": [1.0, true]}
const TOES: Array[StringName] = [&"ball_leaf_l", &"ball_leaf_r"]


# {speed (the body's, m/s), slide (the lower foot's ground speed over the body's, as it is shown, averaged over the frames: a planted
# foot is 0), toe (the lowest toe y)}, for `def_path` at `gait`, over the 8 s after the first 2 s (several cycles).
func _gait(def_path: String, gait: StringName) -> Dictionary:
	var arena := TestArena.make(self)
	var spec: Array = GAITS[gait]
	var steps := [{"frames": 30}, {"frames": 700, "move": Vector2(spec[0], 0), "hold": [&"dodge"] if spec[1] else []}]
	var def := (load(def_path) as ActorDef).duplicate() as ActorDef
	def.max_stamina = 100000.0  # a sprint of 12 s must not tire him
	var actor := TestArena.spawn(arena, def, ScriptBrain.new(steps), Vector3(-10, 0, 0), "Walker")
	actor.place(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-10, 0, 0)))
	var toe := INF
	var body := 0.0
	var slide := 0.0
	var n := 0
	var last_body := actor.global_position
	var last_feet := {}
	for f in 640:
		await frames(1)
		var feet := {}
		for foot: StringName in [&"foot_l", &"foot_r"]:
			feet[foot] = actor.rig.bone_global(foot)
		if f >= 140 and not last_feet.is_empty():
			var v := Vector2(actor.global_position.x - last_body.x, actor.global_position.z - last_body.z).length() * 60.0
			var lower: StringName = &"foot_l" if feet[&"foot_l"].y <= feet[&"foot_r"].y else &"foot_r"
			var d: Vector3 = feet[lower] - last_feet[lower]
			body += v
			slide += Vector2(d.x, d.z).length() * 60.0 / maxf(v, 0.01)
			n += 1
			for t in TOES:
				toe = minf(toe, actor.rig.bone_global(t).y - actor.global_position.y)
		last_body = actor.global_position
		last_feet = feet
	var out := {"speed": body / maxf(n, 1), "slide": slide / maxf(n, 1), "toe": toe}
	arena.free()
	return out


func test_a_big_bodys_feet_hold_the_floor_as_a_tier_ones_do() -> void:
	# His lower foot's ground speed over the body's is within 5 points of tier I's in the walk, jog and sprint (it was 11, 1 and 7
	# points further off before the cadence), and his toes are never more than 1 cm under the floor.
	for gait: StringName in GAITS:
		var one := await _gait(TIER_1, gait)
		var big := await _gait(HEAVY, gait)
		assert_true(absf(big["slide"] - one["slide"]) <= 0.05, "%s: his lower foot goes %.3f of the body's speed, tier I's %.3f" % [gait, big["slide"], one["slide"]])
		assert_true(big["toe"] >= -0.01, "%s: his toes go to %.3f m (tier I's %.3f)" % [gait, big["toe"], one["toe"]])


func test_his_cadence_is_slower_than_the_clips_and_every_other_actors_is_the_clips() -> void:
	var heavy := (load(HEAVY) as ActorDef).locomotion
	assert_true(heavy.cadence > 0.55 and heavy.cadence < 0.8, "his cycles run at %.2f of the clips' rate" % heavy.cadence)
	for path in [ABARAX, TIER_1, TIER_3, "res://data/actors/knuckle_2.tres"]:
		assert_eq((load(path) as ActorDef).locomotion.cadence, 1.0, "%s plays the clips at their own rate" % path.get_file())


func test_nobody_elses_gait_changes() -> void:
	# Frozen at the base commit: the lower foot's speed over the body's, and the lowest toe, of Abarax, tier I and tier III.
	var base := {
		ABARAX: {&"walk": [0.247, -0.012], &"jog": [0.634, 0.009], &"sprint": [0.686, -0.008]},
		TIER_1: {&"walk": [0.247, -0.012], &"jog": [0.634, 0.009], &"sprint": [0.686, -0.008]},
		TIER_3: {&"walk": [0.253, -0.012], &"jog": [0.639, 0.009], &"sprint": [0.691, -0.009]},
	}
	for path: String in base:
		for gait: StringName in GAITS:
			var m := await _gait(path, gait)
			assert_near(m["slide"], base[path][gait][0], 0.002, "%s %s: the lower foot (%.3f)" % [path.get_file(), gait, m["slide"]])
			assert_near(m["toe"], base[path][gait][1], 0.002, "%s %s: the toe (%.3f)" % [path.get_file(), gait, m["toe"]])

