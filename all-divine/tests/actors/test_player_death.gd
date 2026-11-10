extends TestCase
## The player's death in the training yard: the death clip, then three seconds later the arena resets and Abarax gets up
## at the Spawn with full bars, through his getup move, and is himself again when it is over.

const YARD := "res://world/training_yard/training_yard.tscn"
const ABARAX := "res://data/actors/abarax.tres"


func before_each() -> void:
	Arena.reset_spawn_counts()


func after_each() -> void:
	Game.reset()


func _arena() -> Arena:
	var arena := track((load(YARD) as PackedScene).instantiate()) as Arena
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.name = "Player"
	player.def = load(ABARAX) as ActorDef
	player.set_brain(Brain.new())
	arena.add_child(player)
	player.place(arena.spawn())
	arena.begin(player)
	return arena


func test_death_then_reset_then_getup_at_spawn() -> void:
	var arena := _arena()
	var player := arena.player
	player.place(Transform3D(Basis(), Vector3(4, 0, 2)))
	player.stats.take_damage(20.0)
	var started: Array[StringName] = []
	player.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	player.die()
	assert_true(player.dead, "dead")
	await frames(30)
	assert_eq(started, [&"death"] as Array[StringName], "his death clip plays")
	assert_true(player.dead, "and he is still dead a half second on")
	assert_vec_near(player.global_position, Vector3(4, 0, 2), 0.5, "where he fell")
	await frames(140)
	assert_true(player.dead, "dead for the whole of the three seconds (2.8 s)")
	await frames(20)
	assert_false(player.dead, "then he is up")
	assert_vec_near(player.global_position, arena.spawn().origin, 1e-3, "at Spawn")
	assert_eq(player.stats.hp, player.stats.max_hp, "with full HP")
	assert_eq(started.back(), &"getup", "through his getup move")
	assert_true(player.runner.busy() and player.runner.current.id == &"getup", "playing it")
	assert_true(player.collision_layer & Layers.ACTOR != 0, "he is on the actor layer again")
	assert_true(player.rig.hurtbox.collision_layer != 0, "and can be hit again")
	var foes := arena.get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP).filter(func(n: Node) -> bool: return arena.is_ancestor_of(n))
	assert_eq(foes.size(), 1, "the wave began again")
	# The get up plays out, and he is free.
	await frames(120)
	assert_false(player.runner.busy(), "the get up is over")
	player.set_brain(ScriptBrain.new([{frames = 30, move = Vector2(0, 1)}]))
	var from := player.global_position
	await frames(30)
	assert_true(player.global_position.distance_to(from) > 0.5, "and he walks")


func test_a_second_death_works_the_same() -> void:
	var arena := _arena()
	var player := arena.player
	for round in 2:
		player.die()
		await frames(190)
		assert_false(player.dead, "up after death %d" % (round + 1))
		await frames(120)
	assert_eq(player.stats.hp, player.stats.max_hp)
