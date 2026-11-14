extends TestCase
## A corpse is still: once an actor dies its body stops breathing, planting its feet and looking about. A dead Knuckle and
## a dead Abarax, after the death clip has played out, show the same pose tick after tick (a living body, which breathes,
## does not), whatever is near to look at, and a body stood up again (Actor.revive) lives once more.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLE := "res://data/actors/knuckle_2.tres"
## The bones that breathing, the feet and the head move.
const BONES: Array[StringName] = [&"spine_02", &"spine_03", &"clavicle_l", &"foot_l", &"foot_r", &"Head", &"pelvis"]


func after_each() -> void:
	Game.reset()


func _poses(actor: Actor) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bone in BONES:
		poses.append(actor.rig.shown_pose(bone))
	return poses


# The most any listed bone moved between two sets of poses, in metres.
func _drift(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, a[i].origin.distance_to(b[i].origin))
		worst = maxf(worst, (a[i].basis.x - b[i].basis.x).length())
		worst = maxf(worst, (a[i].basis.z - b[i].basis.z).length())
	return worst


func _scene(def_path: String) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(def_path) as ActorDef, Brain.new(), Vector3.ZERO, "Body")
	# Something to look at, close by, in front of him.
	var poi := Marker3D.new()
	poi.position = Vector3(0.5, 1.5, 2.5)
	poi.add_to_group(Actor.POI_GROUP)
	arena.add_child(poi)
	return {"arena": arena, "actor": actor, "poi": poi}


func _lie_still_test(def_path: String, who: String) -> void:
	var scene := _scene(def_path)
	var actor: Actor = scene["actor"]
	await frames(30)
	var living_a := _poses(actor)
	await frames(37)
	var living_b := _poses(actor)
	assert_true(_drift(living_a, living_b) > 1e-4, "%s alive breathes (it moves %.5f)" % [who, _drift(living_a, living_b)])
	actor.die()
	await frames(240)  # the clip has played out, and the body is held on its last pose
	assert_true(actor.dead)
	var first := _poses(actor)
	await frames(37)
	var second := _poses(actor)
	await frames(61)
	var third := _poses(actor)
	assert_true(_drift(first, second) < 1e-5, "%s dead lies still (%.7f)" % [who, _drift(first, second)])
	assert_true(_drift(second, third) < 1e-5, "and still (%.7f)" % _drift(second, third))
	assert_false(actor.rig.breathing.active, "%s does not breathe" % who)
	assert_false(actor.rig.foot_planter.planting, "plants no feet")
	for look in actor.rig.looks:
		assert_eq(look.influence, 0.0, "looks at nothing")
	assert_eq(actor.rig.looking_at(), null, "no head turned to the lantern")


func test_a_dead_knuckle_lies_still() -> void:
	await _lie_still_test(KNUCKLE, "the Knuckle")


func test_dead_abarax_lies_still_until_he_is_stood_up() -> void:
	await _lie_still_test(ABARAX, "Abarax")
	# Stood up again, he lives: breathing, planting and looking are back.
	var actor := get_tree().get_nodes_in_group(Actor.GROUP).filter(func(a: Node) -> bool: return a.name == "Body" and a.is_inside_tree())[0] as Actor
	actor.revive(Transform3D())
	await frames(240)
	assert_true(actor.rig.breathing.active, "he breathes again")
	assert_true(actor.rig.foot_planter.planting, "plants his feet")
	var a := _poses(actor)
	await frames(37)
	assert_true(_drift(a, _poses(actor)) > 1e-4, "and moves with his breath")


# The most any foot of `actor` moved in one frame while `frames_to_watch` frames went by, from the frame before it died on.
func _foot_travel(actor: Actor, frames_to_watch: int) -> float:
	var last := {}
	var worst := 0.0
	var died_at := -1
	for i in frames_to_watch:
		await frames(1)
		if actor.dead and died_at < 0:
			died_at = i
		for foot in Actor.FEET:
			var at := actor.rig.bone_global(foot)
			if died_at >= 0 and last.has(foot):
				worst = maxf(worst, at.distance_to(last[foot]))
			last[foot] = at
		if died_at >= 0 and i > died_at + 20:
			break
	assert_true(died_at >= 0, "the body died")
	return worst


func test_a_body_killed_lying_does_not_pop_a_foot_on_the_death_frame() -> void:
	var run := Duel.make(self, [], [], 1.2, null, null)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await frames(30)
	b.stats.hp = 1.0
	b.stats.damage_posture(1000.0)
	assert_true(a.start_paired(b, a.def.finisher), "the finisher starts")
	var travel := await _foot_travel(b, 200)
	assert_true(travel <= 0.01, "no foot moves more than 1 cm in a frame once it is dead (%.3f m)" % travel)


func test_a_body_killed_in_a_grab_does_not_pop_a_foot() -> void:
	var arena := TestArena.make(self)
	var foe := TestArena.spawn(arena, load("res://data/actors/knuckle_1.tres") as ActorDef, Brain.new(), Vector3(0, 0, 1.2), "Foe")
	foe.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.2)))
	var victim := TestArena.spawn(arena, load(ABARAX) as ActorDef, Brain.new(), Vector3.ZERO, "Victim")
	await frames(30)
	victim.stats.hp = 1.0
	assert_true(foe.start_paired(victim, foe.def.grab_pair), "the grab starts")
	var travel := await _foot_travel(victim, 200)
	assert_true(travel <= 0.01, "no foot moves more than 1 cm in a frame once it is dead (%.3f m)" % travel)
