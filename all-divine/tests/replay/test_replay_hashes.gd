extends TestCase
## A recording says what it is and checks itself: a header (format version, seed, policy, how many frames), the fight's state hash
## every `hash_every` frames and at the end; a replay compares as it goes and stops at the first hash that differs; a file that is cut
## short, from a format the game does not know or with a debug key in it is refused before any fight. A pause is not part of a
## recording: the frames it stops and the presses that open and close it are left out, and the fight replays without it.
##
## The world is the yard's arena with Abarax (a PlayerBrain) in it, begun with seed 1: Main is not needed to test what the recorder and
## the replayer do, and is a sixth of the cost under the software renderer.

const YARD := "res://world/training_yard/training_yard.tscn"
const LEFT := Vector2(-1, 0)


func after_each() -> void:
	InputFeed.release()
	get_tree().paused = false
	Game.reset()
	await frames(1)


# A new yard, begun with the dice of seed 1, and Abarax with a PlayerBrain in it: {arena, player}.
func _world() -> Dictionary:
	Game.reset()
	Arena.start_seed(1)
	var arena := track((load(YARD) as PackedScene).instantiate()) as Arena
	var player := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	player.name = "Player"
	player.def = load("res://data/actors/abarax.tres") as ActorDef
	player.set_brain(PlayerBrain.new())
	arena.add_child(player)
	arena.begin(player)
	return {"arena": arena, "player": player}


# The hands: walk, jab, walk the other way, jab, guard.
func _hands() -> Array:
	return [{"frames": 10}, {"frames": 25, "move": Vector2(0, -1)}, {"frames": 1, "press": [&"palm"], "hold": [&"palm"]}, {"frames": 15},
			{"frames": 25, "move": Vector2(1, 0.5)}, {"frames": 1, "press": [&"palm"], "hold": [&"palm"]}, {"frames": 30}]


# Records `count` frames of `hands` in a new world, a hash every `every`: the recording (closed). The world is freed.
func _make_recording(hands: Array, count: int, every := 20) -> InputRecording:
	var world := _world()
	var recorder := track(InputRecorder.new()) as InputRecorder
	recorder.arena = world["arena"]
	recorder.hash_every = every
	recorder.begin(YARD, 1, 0)
	var driver := track(ScriptedHands.new(hands))
	while recorder.recording().frames.size() < count:
		await frames(1)
	recorder.close()
	recorder.set_physics_process(false)
	var rec := recorder.recording()
	for node: Node in [driver, recorder, world["arena"]]:
		node.queue_free()
	await frames(2)
	InputFeed.release()
	return rec


# Plays `rec` into a new world: [the checkpoint it diverged at or -1, the recorded hash, the hash it got, whether it finished].
func _replay(rec: InputRecording) -> Array:
	var world := _world()
	var replayer := track(InputReplayer.new()) as InputReplayer
	replayer.arena = world["arena"]
	var result := [-1, 0, 0, false]
	replayer.diverged.connect(func(at: int, recorded: int, got: int) -> void:
		result[0] = at
		result[1] = recorded
		result[2] = got)
	replayer.finished.connect(func() -> void: result[3] = true)
	replayer.play(rec)
	while replayer.playing():
		await frames(1)
	replayer.queue_free()
	(world["arena"] as Node).queue_free()
	await frames(2)
	InputFeed.release()
	return result


func test_a_recording_carries_a_header_and_the_hash_every_so_often_and_at_the_end() -> void:
	var rec := await _make_recording(_hands(), 65)
	assert_eq(rec.version, InputRecording.VERSION, "the format's version")
	assert_eq(rec.frame_count, rec.frames.size(), "how many frames")
	assert_eq(rec.seed, 1)
	assert_eq(rec.policy, "", "no policy: a person's")
	var checkpoints: Array = rec.hashes.keys()
	checkpoints.sort()
	assert_eq(checkpoints, [20, 40, 60, rec.frames.size()], "a hash every 20 frames and one at the end: %s" % [checkpoints])
	assert_eq(rec.problem(), "", "and it is a recording the game can use")


func test_a_replay_that_agrees_finishes_and_one_edited_input_diverges_at_the_next_hash() -> void:
	var rec := await _make_recording(_hands(), 65)
	var good := await _replay(rec)
	assert_eq(good[0], -1, "no divergence")
	assert_true(good[3], "and it finished")
	var edited := rec.duplicate(true) as InputRecording
	edited.frames[30]["move"] = Vector2(0, 1)  # a step the other way, on frame 30
	var bad := await _replay(edited)
	assert_eq(bad[0], 40, "diverged at the first checkpoint after the edit")
	assert_ne(bad[1], bad[2], "the hash recorded and the hash got differ")
	assert_false(bad[3], "and it did not go on to finish")


func test_a_recording_that_cannot_be_used_says_why() -> void:
	var rec := InputRecording.new()
	rec.frames.append(InputRecording.idle())
	rec.frame_count = 1
	assert_eq(rec.problem(), "", "a whole recording")
	rec.frame_count = 5
	assert_true(rec.problem().contains("cut short"), "fewer frames than it says: %s" % rec.problem())
	rec.frame_count = 1
	rec.version = 99
	assert_true(rec.problem().contains("format"), "a version the game does not know: %s" % rec.problem())
	rec.version = InputRecording.VERSION
	rec.debug_keys = true
	assert_true(rec.problem().contains("debug key"), "a debug key pressed: %s" % rec.problem())


func test_a_pause_and_the_presses_that_open_and_close_it_are_not_in_the_recording() -> void:
	# the same hands, with the game paused for 100 frames in the middle and a menu press either side of it
	var world := _world()
	# under a node that runs through a pause, as Main does (it hears the menu button)
	var holder := track(Node.new())
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	var recorder := InputRecorder.new()
	holder.add_child(recorder)
	recorder.arena = world["arena"]
	recorder.begin(YARD, 1, 0)
	var steps := _hands()
	steps.insert(2, {"frames": 1, "press": [&"menu"]})  # the press that opens it, in the middle of the walk
	steps.insert(4, {"frames": 1, "press": [&"menu"]})  # and the press that closes it
	var driver := track(ScriptedHands.new(steps))
	while recorder.recording().frames.size() < 20:
		await frames(1)
	get_tree().paused = true
	await frames(100)
	get_tree().paused = false
	while recorder.recording().frames.size() < 62:
		await frames(1)
	recorder.close()
	recorder.set_physics_process(false)
	var paused := recorder.recording()
	for entry: Dictionary in paused.frames:
		assert_false((entry["pressed"] as PackedStringArray).has("menu") or (entry["held"] as PackedStringArray).has("menu"), "no menu press is kept")
	assert_eq(paused.frames.size(), 62, "the hundred paused frames are not in it")
	for node: Node in [driver, recorder, world["arena"]]:
		node.queue_free()
	await frames(2)
	InputFeed.release()
	var again := await _replay(paused)
	assert_eq(again[0], -1, "the paused recording replays, without pausing, to the hashes it recorded: %s" % [again])
	assert_true(again[3])
