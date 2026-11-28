extends TestCase
## A body that runs at a solid thing the world marks (DEFLECTS) goes along it at its own speed: an unmarked wall, which a body runs
## at 45 degrees, is gone along at the speed its legs slow to (they follow the speed it slides at, which falls at every frame, so that
## the body crawls); a marked one is gone along at the speed it was run at. Dead on a post, a body goes round it; at a wall it stands.

const ABARAX := "res://data/actors/abarax.tres"
## What the world marks a solid body with (Actor's DEFLECTS).
const DEFLECTS := &"deflects"



# Abarax run at 45 degrees (east and north) at a wall 10 m wide along z = -2 (a box with its south face there), from (-2, 0), for 60
# frames; the metres he went east along it.
func _along(mark: Variant) -> float:
	var arena := TestArena.make(self)
	var wall := TestArena.wall(arena, Vector3(0, 1, -3), Vector3(20, 2, 2))
	if mark != null:
		wall.set_meta(DEFLECTS, mark)
	var way := Vector2(1, -1).normalized()
	var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, ScriptBrain.new([{frames = 90, move = way, hold = [&"dodge"]}]), Vector3(-3, 0, -0.5))
	await frames(2)
	await frames(80)
	var x := actor.global_position.x
	arena.queue_free()
	return x + 3.0


func test_a_body_goes_along_a_marked_wall_at_the_speed_it_ran_and_along_an_unmarked_one_crawls() -> void:
	var plain: float = await _along(null)
	var smooth: float = await _along(&"smooth")
	assert_true(smooth > plain * 1.6, "along a marked wall %.2f m in 80 frames, along an unmarked one %.2f m" % [smooth, plain])


# Dead on a slim post a body goes round it on the side it is offset to; at a smooth wall it stands.
func test_dead_on_a_slim_post_a_body_goes_round_it_and_at_a_wall_it_stands() -> void:
	for kind in [&"slim", &"smooth"]:
		var arena := TestArena.make(self)
		var post := TestArena.wall(arena, Vector3(0, 1, -4), Vector3(0.5, 2, 0.5))
		post.set_meta(DEFLECTS, kind)
		var actor := TestArena.spawn(arena, load(ABARAX) as ActorDef, ScriptBrain.new([{frames = 120, move = Vector2(0, -1)}]), Vector3(0.0, 0, 0))
		await frames(2)
		await frames(100)
		var x := absf(actor.global_position.x)
		if kind == &"slim":
			assert_true(actor.global_position.z < -4.0, "dead on a slim post he is past it (z %.2f)" % actor.global_position.z)
		else:
			assert_true(x < 0.05 and actor.global_position.z > -3.5, "dead on a post that only smooths he stands at it (x %.2f, z %.2f)" % [x, actor.global_position.z])
		arena.queue_free()
		await frames(1)
