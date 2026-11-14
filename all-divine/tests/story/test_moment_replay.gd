extends TestCase
## The dip never touches the simulation: a fight with a finisher in it records and replays as recorded with the dip on and with it
## off, a recording made with it on replays as recorded with it off (and the other way about), and the two recordings of the same
## fight say the same thing from first to last frame. `camera/dips` is not among the settings a recording keeps (a setting that
## changes no fight is not part of one).
##
## The fight is the yard's first wave through the real Main, a finisher forced on its Knuckle on a fixed frame of the game (the
## Knuckle put a metre in front of him, then Actor.start_paired with his def's finisher: the signal and the pair are the game's).

const MAIN := "res://main/main.tscn"
const FRAMES := 300
const FORCED_ON := 90
const SETTINGS_PATH := "user://settings_moment_replay_test.cfg"


# Puts the first wave's Knuckle in front of Abarax and starts his finisher on it, on the `at`th physics frame it lives.
class Forcer:
	extends Node
	var main: Main
	var at := FORCED_ON
	var _n := 0

	func _physics_process(_delta: float) -> void:
		_n += 1
		if _n != at:
			return
		var player := main.player
		var foe := main.arena().enemies()[0]
		var forward := Basis(Vector3.UP, player.rotation.y) * Vector3(0, 0, 1)
		foe.place(Transform3D(Basis(Vector3.UP, player.rotation.y + PI), player.global_position + forward))
		player.start_paired(foe, player.def.finisher)


func before_each() -> void:
	RenderingServer.render_loop_enabled = false
	Settings.path = SETTINGS_PATH
	Game.reset()


func after_each() -> void:
	RenderingServer.render_loop_enabled = true
	InputFeed.release()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	for file in [SETTINGS_PATH, "user://moment_a.tres", "user://moment_b.tres"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	Game.reset()


func _main() -> Main:
	Game.reset()
	Arena.reset_spawn_counts()
	Director.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	return main


func _hands() -> Array:
	return [{"frames": 20}, {"frames": 25, "move": Vector2(0, -1)}, {"frames": 1, "press": [&"palm"], "hold": [&"palm"]}, {"frames": 200}]


# Plays the fight in a new Main with the dip `dips` and, if `rec` is given, the recording into it; else records it to `path`. What
# it came to: {rec, top: the camera's fullest dip, moments: the finishers announced, diverged: [...], finished: how many replays ended}.
func _fight(dips: bool, path := "", rec: InputRecording = null) -> Dictionary:
	Settings.set_value("camera/dips", dips)
	var main := _main()
	var out := {rec = rec, top = 0.0, moments = 0, diverged = [], finished = 0}
	main.player.combat_moment.connect(func(kind: StringName) -> void: out.moments += 1 if kind == &"finisher" else 0)
	var hands: Node = null
	if rec == null:
		main.start_recording(path)
	else:
		main.start_replay(rec)
		main._replayer.diverged.connect(func(at: int, recorded: int, got: int) -> void: out.diverged.append([at, recorded, got]))
		main._replayer.finished.connect(func() -> void: out.finished += 1)
	var forcer := Forcer.new()
	forcer.main = main
	main.add_child(forcer)
	if rec == null:
		hands = track(ScriptedHands.new(_hands()))
	var count := FRAMES if rec == null else rec.frame_count
	for i in count + 2:
		await frames(1)
		out.top = maxf(out.top, main.camera_rig.cine_weight)
	if rec == null:
		assert_eq(main.save_recording(), OK)
		out.rec = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
		if hands != null:
			hands.queue_free()
		InputFeed.release()
	main.queue_free()
	await frames(3)
	return out


func _without_cursor(rec: InputRecording) -> Array:
	return rec.frames.map(func(frame: Dictionary) -> Dictionary:
		var kept := frame.duplicate()
		kept.erase("cursor")
		return kept)


func test_a_fight_with_a_finisher_replays_as_recorded_with_the_dip_on_or_off() -> void:
	var a := await _fight(true, "user://moment_a.tres")
	assert_eq(a.moments, 1, "the finisher began in the recording")
	assert_eq(a.top, 1.0, "and the camera dipped all the way while it was made")
	var rec: InputRecording = a.rec
	assert_true(rec != null and rec.problem() == "", "the recording is a good one: %s" % (rec.problem() if rec != null else "none"))
	if rec == null:
		return
	assert_false(rec.settings.has("camera/dips"), "the dips setting is not among those a recording keeps")
	assert_true(Main.end_is_compared(rec), "a replay of it ends with a hash to agree with")
	for dips in [true, false]:
		var replay := await _fight(dips, "", rec)
		assert_eq(replay.moments, 1, "dips %s: the finisher began in the replay" % dips)
		assert_eq(replay.top, 1.0 if dips else 0.0, "dips %s: and the camera %s" % [dips, "dipped" if dips else "stayed the game's"])
		assert_eq(replay.diverged, [], "dips %s: the fight is as recorded at every checkpoint" % dips)
		assert_eq(replay.finished, 1, "dips %s: and the replay ends" % dips)


func test_a_recording_made_with_the_dip_off_is_the_same_as_one_made_with_it_on() -> void:
	var on := await _fight(true, "user://moment_a.tres")
	var off := await _fight(false, "user://moment_b.tres")
	assert_eq(off.top, 0.0, "the second fight had no dip")
	assert_eq(on.top, 1.0, "the first had one")
	var rec_on: InputRecording = on.rec
	var rec_off: InputRecording = off.rec
	assert_true(rec_on != null and rec_off != null)
	if rec_on == null or rec_off == null:
		return
	assert_eq(rec_on.hashes, rec_off.hashes, "the fight's state hash is the same at every checkpoint, the finisher's frames among them")
	# (the mouse's ground point is where a still cursor points through the camera, which leans in: the one control the dip can move)
	assert_eq(_without_cursor(rec_on), _without_cursor(rec_off), "and so are the controls, the cursor's ground point apart")
	assert_eq(rec_on.settings, rec_off.settings, "and the settings the recording keeps")
	var replay := await _fight(true, "", rec_off)
	assert_eq([replay.diverged, replay.finished, replay.top], [[], 1, 1.0], "the one made without the dip replays as recorded with it")
