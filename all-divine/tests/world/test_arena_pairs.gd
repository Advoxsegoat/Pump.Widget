extends TestCase
## F9 (Arena.reset) and F5 (Main.switch_region) pressed while a foe holds, or is held by, a paired move (a grab, a finisher) or
## is locked on: the pair is ended before the foe is taken away, the player ends standing at the Spawn with full bars and one
## wave, no stale pair, and nothing errors (the engine's errors fail a test).

const MAIN := "res://main/main.tscn"
const TIMINGS: Array[int] = [2, 9, 25, 47, 70]


func before_each() -> void:
	Arena.reset_spawn_counts()


func after_each() -> void:
	Game.reset()


func _main() -> Main:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	return main


func _foe(main: Main) -> Actor:
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	return foe


# A grab in progress at `frames_in`: the Knuckle leads, Abarax is the follower. Returns the foe.
func _grab(main: Main, frames_in: int) -> Actor:
	var foe := _foe(main)
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, 0.0, 5.0)))
	main.player.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 6.2)))
	await frames(2)
	assert_true(foe.start_paired(main.player, foe.def.grab_pair), "the grab starts")
	await frames(frames_in)
	return foe


func _finisher(main: Main, frames_in: int) -> Actor:
	var foe := _foe(main)
	foe.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, 0.0, 5.0)))
	main.player.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 6.0)))
	await frames(2)
	foe.stats.damage_posture(1000.0)
	assert_true(main.player.start_paired(foe, main.player.def.finisher), "the finisher starts")
	await frames(frames_in)
	return foe


func _assert_reset_state(main: Main, label: String) -> void:
	await frames(3)
	var player := main.player
	assert_false(player.dead, "%s: alive" % label)
	assert_true(player.paired_with == null and player.pair == null, "%s: no stale pair" % label)
	assert_eq(player.stats.hp, player.stats.max_hp, "%s: full HP" % label)
	assert_true(Vector2(player.global_position.x - main.region.spawn().origin.x, player.global_position.z - main.region.spawn().origin.z).length() < 0.1,
			"%s: at Spawn (%s)" % [label, player.global_position])
	assert_true(player.collision_layer & Layers.ACTOR != 0, "%s: on the actor layer" % label)
	var foes := get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP).filter(func(n: Node) -> bool: return main.region.is_ancestor_of(n))
	assert_eq(foes.size(), 1, "%s: one wave" % label)


func test_f9_mid_grab_stands_abarax_up_at_spawn() -> void:
	for t in TIMINGS:
		var main := _main()
		await _grab(main, t)
		main.arena().reset()
		await _assert_reset_state(main, "F9 grab +%d" % t)
		main.queue_free()
		await frames(1)


func test_f5_mid_grab_stands_abarax_up_at_spawn() -> void:
	for t in TIMINGS:
		var main := _main()
		await _grab(main, t)
		main.switch_region()
		await frames(2)
		main.switch_region()  # and back to the yard, whose first wave is what the state is checked against
		await _assert_reset_state(main, "F5 grab +%d" % t)
		main.queue_free()
		await frames(1)


func test_f9_and_f5_mid_finisher() -> void:
	for t in TIMINGS:
		for key in [&"reset", &"switch"]:
			var main := _main()
			await _finisher(main, t)
			if key == &"reset":
				main.arena().reset()
			else:
				main.switch_region()
				await frames(2)
				main.switch_region()
			await _assert_reset_state(main, "%s finisher +%d" % [key, t])
			main.queue_free()
			await frames(1)


func test_f9_with_a_lock_on_leaves_no_error_on_the_next_draw_or_frames() -> void:
	var main := _main()
	await frames(3)
	var brain := PlayerBrain.new()
	brain.view_yaw = main.camera_rig.yaw()
	main.player.set_brain(brain)
	brain.lock.target = _foe(main)
	main.camera_rig.lock_target = brain.lock.target
	# F9 lands between physics frames: the draw that follows sees the freed foe before any physics tick.
	main.arena().reset()
	main.hud.notification(CanvasItem.NOTIFICATION_DRAW)
	assert_eq(main.hud.reticle_at(), null, "no reticle on a foe that is gone")
	await frames(4)
	assert_true(brain.lock.target == null or is_instance_valid(brain.lock.target), "the lock is let go")
	assert_true(main.camera_rig.lock_target == null or is_instance_valid(main.camera_rig.lock_target), "and the camera's")
	# Same through F5.
	brain.lock.target = _foe(main)
	main.switch_region()
	main.switch_region()
	main.hud.notification(CanvasItem.NOTIFICATION_DRAW)
	await frames(4)
