extends TestCase
## What the player aims with is the game's own camera, never the dip's: with the mouse held still, the cursor's ground point, and so
## Abarax's facing, are the same on every frame whether the finisher's dip leans the camera in or not, and a lock-on pressed in a
## dip picks from the game's picture. (A recording injects the cursor, so only a live mouse can show it.) A scene's camera is not
## the dip's: the player has no control in one.

const MAIN := "res://main/main.tscn"
const FORCED_ON := 90
const PIXELS := [Vector2(576, 250), Vector2(100, 100), Vector2(320, 180), Vector2(600, 60), Vector2(50, 300), Vector2(400, 330), Vector2(200, 40)]
const SETTINGS_PATH := "user://settings_moment_aim_test.cfg"


# A player's hands that hold the mouse still on `px` (the real cursor_ground path, a fixed pixel of the window).
class MouseBrain:
	extends PlayerBrain
	var px := Vector2(576, 250)

	func mouse_position(_actor: Actor) -> Vector2:
		return px


# Puts the first wave's Knuckle in front of Abarax and starts his finisher on it, on the 90th physics frame it lives.
class Forcer:
	extends Node
	var main: Main
	var _n := 0

	func _physics_process(_delta: float) -> void:
		_n += 1
		if _n != FORCED_ON:
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
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	Game.reset()


func _hands() -> Array:
	var steps := [{"frames": 20, "device": null}, {"frames": 25, "move": Vector2(0, -1), "device": null}, {"frames": 120, "device": null}]
	for i in 8:
		steps.append({"frames": 14, "device": null})
		steps.append({"frames": 1, "press": [&"palm"], "hold": [&"palm"], "device": null})
	return steps


# A fight on the keyboard and mouse with the mouse held on `px`, two more Knuckles about, a finisher forced on frame 90: Abarax's yaw,
# the cursor's ground point and the camera's weight on each of `count` frames.
func _fight(dips: bool, px: Vector2, count := 330) -> Dictionary:
	Settings.set_value("camera/dips", dips)
	Game.reset()
	Arena.reset_spawn_counts()
	Director.reset_spawn_counts()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(1)
	var brain := MouseBrain.new()
	brain.view_yaw = main.camera_rig.yaw()
	brain.px = px
	main.player.set_brain(brain)
	for i in 2:
		main.arena().debug_key(KEY_F6)
	var forcer := Forcer.new()
	forcer.main = main
	main.add_child(forcer)
	var hands := track(ScriptedHands.new(_hands()))
	var out := {yaws = [], cursors = [], weights = []}
	for i in count:
		await frames(1)
		out.yaws.append(main.player.rotation.y)
		out.cursors.append(Inputs.cursor_read)
		out.weights.append(main.camera_rig.cine_weight)
	main.queue_free()
	hands.queue_free()
	InputFeed.release()
	await frames(3)
	return out


func test_a_still_mouse_aims_the_same_with_the_dip_on_and_off() -> void:
	for px: Vector2 in PIXELS:
		var on := await _fight(true, px)
		var off := await _fight(false, px)
		assert_eq(on.weights.max(), 1.0, "%s: the dip played in the first fight" % px)
		assert_eq(off.weights.max(), 0.0, "%s: and not in the second" % px)
		var worst_yaw := 0.0
		var worst_cursor := 0.0
		for i in on.yaws.size():
			worst_yaw = maxf(worst_yaw, absf(angle_difference(on.yaws[i], off.yaws[i])))
			if on.cursors[i] is Vector3 and off.cursors[i] is Vector3:
				worst_cursor = maxf(worst_cursor, (on.cursors[i] as Vector3).distance_to(off.cursors[i]))
		# (the same to the rounding of a camera rebuilt from its angles: a millionth of a radian, a hundredth of a millimetre)
		assert_true(worst_yaw <= 1e-4, "%s: his yaw is the same on every frame (off by %.4f degrees at most)" % [px, rad_to_deg(worst_yaw)])
		assert_true(worst_cursor <= 1e-3, "%s: and so is the cursor's ground point (off by %.4f m at most)" % [px, worst_cursor])


func test_a_lock_on_pressed_in_a_dip_picks_from_the_games_picture() -> void:
	Game.change(Game.State.PLAY)
	var parts := StoryStage.make(self)
	var player: Actor = parts.player
	var wide := StoryStage.knuckle(parts.region, Vector3(10.5, 0, 0), PI, "Wide")  # in the game's picture (10.75 m), out of the dipped rig's (its middle is 0.5 m west)
	var near := StoryStage.knuckle(parts.region, Vector3(0, 0, 3.5), PI, "Near")
	var other := StoryStage.knuckle(parts.region, Vector3(-1.0, 0, 0.0), PI, "Pair")
	var candidates := [wide, near]
	var along := Vector3(1, 0, 0)
	await frames(2)
	assert_true(LockOn.pick(player, candidates, along, parts.rig) == wide, "control: with no dip the foe straight ahead is the pick")
	var cam := Director.watch_moments(player, parts.rig, parts.hud)
	cam.moment(&"finisher", other)
	await frames(45)
	assert_eq(parts.rig.cine_weight, 1.0, "the dip is at its top")
	assert_true(LockOn.pick(player, candidates, along, parts.rig) == wide, "in the dip the pick is the same: the game's picture chooses")
	assert_true(LockOn.next(player, near, candidates, true, parts.rig) == wide, "and so is the switch to the right")


func test_a_scenes_camera_is_what_he_aims_with() -> void:
	Game.change(Game.State.PLAY)
	var parts := StoryStage.make(self)
	await frames(3)
	var director := Director.new()
	assert_true(director.begin((load("res://scenes/story/fixture_yard_entrance/shots.tres") as SceneShots).duplicate_deep(), parts.region, parts.rig, parts.hud, parts.stage))
	await frames(20)
	assert_true(parts.rig.cine_weight > 0.0, "the scene's camera is on")
	assert_false(parts.rig._aims_with_game(), "and it is the one he aims through: only a dip's is left out of his aim")
	director.abort()
