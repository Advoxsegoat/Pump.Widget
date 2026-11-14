class_name Main
extends Node
## The game: a region (the training yard by default, with its Arena sending waves of Knuckles; F5 switches to the
## courtyard and back), Abarax in it and the camera on him, drawn by the PixelStage in the screen look, with the Hud
## over it.
##
## When ready, the game goes to PLAY; Abarax stands at the region's spawn with the player's hands on him (a
## PlayerBrain turned by the camera's yaw); the camera takes him as its target and snaps to him; the stage
## puts on the look (data/render/default_settings.tres) in the region's grade; and the Arena, if the region is one, begins
## its first wave with him as its target.
##
## F1 (a pad's Select) shows or hides the controls list; F2 enters the Bilibara stretch; F3 shows or hides the debug overlay; F4 turns the screen look off
## and on; F5 switches the region; F6, F7 and F8 spawn a tier I, II or III Knuckle and F9 resets the fight (the Arena's
## debug keys, which Main passes on); F11 or Alt+Enter switches between
## borderless fullscreen, where the game starts, and a 1280x720 window (WindowToggle); the menu button (Esc,
## Start) pauses, and the pause menu (Menu, in the Hud's picture) shows while it is paused: its Resume row or the menu button
## resumes. While it is open F5 to F9 do nothing and every other event goes to the menu. This node runs while the game
## is paused (to hear the menu button and give the menu its events); the stage, and so the world in it, stops.
##
## With --selftest (a user argument: godot -- --selftest) Abarax fights one tier I Knuckle in the yard through a
## scripted circuit instead (selftest_circuit: approach, jab, cross, hook, sway, duck, dash-step, guard, heavy) for SELFTEST_FRAMES
## physics frames, and the arena does nothing by itself but send that one Knuckle; the SelfTest autoload
## (core/self_test.gd), listening for errors since before this scene loaded, then quits: 0 if none was logged, else 1.

const DEFAULT_SETTINGS := preload("res://data/render/default_settings.tres")
const SELFTEST_FRAMES := 600
const YARD := "res://world/training_yard/training_yard.tscn"
const COURTYARD := "res://world/courtyard/courtyard.tscn"
const BILIBARA := "res://world/bilibara/bilibara.tscn"
## The keys Main reads itself (F1 to F9 and F11; Alt+Enter is WindowToggle's) and the pad button it reads (Select), which the controls
## screen's capture refuses to bind: a key bound to a game action would be taken here first and never reach the fight.
const OWN_KEYS: Array[Key] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F11]
const OWN_BUTTONS: Array[JoyButton] = [JOY_BUTTON_BACK]
## How far Abarax walks toward the Knuckle in the self-test before he waits for it, and the stick's push.
const SELFTEST_APPROACH := 2.0
const SELFTEST_WALK_PUSH := 0.6
## Frames to stand while the Knuckle closes on him, and between the circuit's blows.
const SELFTEST_WAIT := 90
const SELFTEST_PAUSE := 20
## Frames a palm, a sway, a duck, a dash-step, a guard and a heavy take, recovery included.
const SELFTEST_PALM_FRAMES := 24
## The hook is the longest of the three: it plays out (a press while it plays would be lost) before the sway.
const SELFTEST_HOOK_FRAMES := 95
const SELFTEST_SWAY_FRAMES := 26
const SELFTEST_DUCK_FRAMES := 30
const SELFTEST_DASH_FRAMES := 24
## The guard is pressed every SELFTEST_GUARD_REPEAT frames for SELFTEST_GUARD_FRAMES: a blow of the Knuckle's can land as he
## dash-steps back and flinch him (a flinch takes no guard until it is over), and a press made then would be lost; the
## next, within the 9 frames a press is kept, is not.
const SELFTEST_GUARD_FRAMES := 50
const SELFTEST_GUARD_REPEAT := 10
const SELFTEST_HEAVY_FRAMES := 70

@onready var stage: PixelStage = $PixelStage
@onready var region: Region = $PixelStage/World/Region
@onready var hud: Hud = $PixelStage/Hud/Hud
@onready var player: Actor = $PixelStage/World/Player
@onready var camera_rig: CameraRig = $PixelStage/World/CameraRig
@onready var overlay: DebugOverlay = $DebugOverlay
@onready var menu: Menu = $PixelStage/Hud/Menu

## Whether the screen look is on (F4).
var look_on := true
## The window F11 and Alt+Enter switch: the game's own, unless a test gives it another before Main is ready.
var window: Window = null
## What the menu's Quit does: ends the game. A test puts its own here.
var quit_game: Callable = func() -> void: get_tree().quit()


func _ready() -> void:
	if window == null:
		window = get_window()
	if Game.state != Game.State.PLAY:
		Game.change(Game.State.PLAY)
	player.place(region.spawn())
	var hands := PlayerBrain.new()
	hands.view_yaw = camera_rig.yaw()
	player.set_brain(hands)
	camera_rig.target = player
	camera_rig.stage = stage
	camera_rig.snap_now()
	overlay.actor = player
	Settings.apply_window(window)
	Settings.changed.connect(_on_setting_changed)
	menu.window = window
	menu.quit_requested.connect(func() -> void: quit_game.call())
	window.min_size = Vector2i(PixelSnap.INTERNAL)
	Game.state_changed.connect(_on_game_state_changed)
	_apply_look()
	_enter_region()
	if SelfTest.active:
		start_selftest()


func _unhandled_input(event: InputEvent) -> void:
	if Game.state == Game.State.PAUSE and menu.capturing():
		# A binding waits for its button: the menu has the event first and nothing else is done with it, so that the game's own keys
		# (which it refuses, saying so) do none of their own work meanwhile.
		menu.handle(event)
		get_viewport().set_input_as_handled()
		return
	if WindowToggle.is_toggle(event):
		WindowToggle.apply(window)
		Settings.note_window_mode(window.mode)
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_F3:
				overlay.visible = not overlay.visible
				get_viewport().set_input_as_handled()
				return
			KEY_F4:
				look_on = not look_on
				_apply_look()
				get_viewport().set_input_as_handled()
				return
			KEY_F2:
				enter_stretch()
				get_viewport().set_input_as_handled()
				return
			KEY_F5:
				if Game.state == Game.State.PAUSE:
					return  # the debug keys are for the fight, not the menu
				switch_region()
				get_viewport().set_input_as_handled()
				return
			KEY_F6, KEY_F7, KEY_F8, KEY_F9:
				if Game.state == Game.State.PAUSE:
					return
				# The arena lives in the stage's own viewport, which the window's keys never reach.
				if arena() != null and arena().debug_key(key.keycode):
					get_viewport().set_input_as_handled()
				return
			KEY_F1:
				hud.toggle_hints()
				get_viewport().set_input_as_handled()
				return
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed and pad.button_index == JOY_BUTTON_BACK:
		hud.toggle_hints()
		get_viewport().set_input_as_handled()
		return
	if Game.state == Game.State.PAUSE:
		# The menu takes the rest, and what it does with it (resuming too) is its own.
		if menu.handle(event):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"menu"):
		if Game.state == Game.State.PLAY or Game.state == Game.State.CUTSCENE:  # a scene can be paused as the fight is
			Game.change(Game.State.PAUSE)
		get_viewport().set_input_as_handled()


## The arena of the region, or null when it is not one (the courtyard).
func arena() -> Arena:
	return region as Arena


## Switches to the other region (the training yard from the courtyard, the courtyard from the yard; F5): the player is
## put at its spawn (standing, with full bars, if he was dead), the camera snaps to him, the look takes its grade, and an
## arena begins its first wave. The old region, and any foes in it, are freed.
func switch_region() -> void:
	_go_to(COURTYARD if region.scene_file_path == YARD else YARD)


# Replaces the region with the scene `to` (switch_region says what it does).
func _go_to(to: String) -> void:
	if Director.current() != null:
		Director.current().abort()  # a scene cannot go on in another place: it gives the fight back first
	var old := region
	if old is Arena:
		(old as Arena).clear_foes()  # ends what holds them (pairs, the lock) before they go with the region
	player.runner.stop()
	var world := old.get_parent()
	world.remove_child(old)
	old.queue_free()
	region = (load(to) as PackedScene).instantiate() as Region
	region.name = "Region"
	world.add_child(region)
	world.move_child(region, 0)
	if player.dead:
		player.revive(region.spawn())
	else:
		player.place(region.spawn())
		player.stats.refill()
	camera_rig.snap_now()
	_apply_look()
	_enter_region()


## Enters the Bilibara stretch (F2, the debug key): what switch_region does, with that scene. It is a plain region, so no
## arena runs and the Hud follows none.
func enter_stretch() -> void:
	_go_to(BILIBARA)


## Starts the self-test's circuit: Abarax fights the tier I Knuckle the arena sends, through selftest_circuit, and the
## SelfTest autoload ends the game SELFTEST_FRAMES physics frames from now, saying how it ended.
func start_selftest() -> void:
	var fight := arena()
	if fight == null:
		push_error("Main: the self-test fights in the training yard, which is not the region (%s)" % region.name)
		return
	fight.begin(player)
	player.set_brain(ScriptBrain.new(selftest_circuit()))
	SelfTest.begin(SELFTEST_FRAMES, func() -> String:
		var foe := fight.enemies()[0]
		return "Abarax at %d HP, the Knuckle at %d HP" % [ceili(player.stats.hp), ceili(foe.stats.hp)])


## The self-test's circuit, as ScriptBrain steps from the spawn against the Knuckle wave 0 sent (arena.enemies()[0]):
## walk toward it, wait for it to come, jab, cross, hook, sway aside, duck, dash-step back, guard, heavy. He faces and aims at it throughout.
func selftest_circuit() -> Array:
	var foe := arena().enemies()[0]
	var start := _flat(region.spawn().origin)
	var toward := (_flat(foe.global_position) - start).normalized()
	var face := {face_target = foe, aim_target = foe}
	var guard := []
	for i in SELFTEST_GUARD_FRAMES / SELFTEST_GUARD_REPEAT:
		guard.append({frames = 1, press = [&"guard"], hold = [&"guard"]}.merged(face))
		guard.append({frames = SELFTEST_GUARD_REPEAT - 1, hold = [&"guard"]}.merged(face))
	return [
		{frames = SELFTEST_PAUSE}.merged(face),
		_leg(toward, SELFTEST_WALK_PUSH, SELFTEST_APPROACH, player.def.locomotion).merged(face),
		{frames = SELFTEST_WAIT}.merged(face),
		{frames = 1, press = [&"palm"]}.merged(face),
		{frames = SELFTEST_PALM_FRAMES}.merged(face),
		{frames = 1, press = [&"palm"]}.merged(face),
		{frames = SELFTEST_PALM_FRAMES}.merged(face),
		{frames = 1, press = [&"palm"]}.merged(face),
		{frames = SELFTEST_HOOK_FRAMES}.merged(face),
		{frames = 1, press = [&"sway"], evade_dir = Vector2(-toward.y, toward.x)}.merged(face),
		{frames = SELFTEST_SWAY_FRAMES}.merged(face),
		{frames = 1, press = [&"duck"]}.merged(face),
		{frames = SELFTEST_DUCK_FRAMES}.merged(face),
		{frames = 1, move = -toward, press = [&"dodge"]}.merged(face),
		{frames = SELFTEST_DASH_FRAMES}.merged(face),
	] + guard + [
		{frames = 1, press = [&"heavy"], hold = [&"heavy"]}.merged(face),
		{frames = SELFTEST_HEAVY_FRAMES}.merged(face),
	]


# What a region gives the game when it is entered: the Hud follows its arena (none in the courtyard), and an arena runs
# the fight by itself, begun with the player unless the self-test is on (it asks for what it wants, start_selftest).
# And the rims a fight will light are drawn, unseen, with the region's first frames (Rig.warm_rim): those frames build
# everything the region shows, and a rim that comes on later then builds nothing.
func _enter_region() -> void:
	player.rig.warm_rim()
	Afterimage.warm(player.rig, Rig.WARM_FRAMES)
	var fight := arena()
	if fight != null:  # a thicker body the waves send has its own shaders: built now, not when he walks in
		var defs: Array = []
		for wave in fight.waves:
			defs.append_array(wave.defs)
		InflatedWarm.start(player.rig, defs)
	hud.bind(player, camera_rig, stage, fight)
	if fight != null:
		fight.automatic = not SelfTest.active
		if not SelfTest.active:
			fight.begin(player)


# The look on (default_settings, each strength times its Settings percent) or off (RenderSettings.off()), in the
# region's grade.
func _apply_look() -> void:
	stage.apply_settings(Settings.look_of(DEFAULT_SETTINGS) if look_on else DEFAULT_SETTINGS.off(), region.grade)


# Any way out of the pause leaves the buttons held and pressed in it out of the fight (Inputs.quarantine).
func _on_game_state_changed(from: Game.State, to: Game.State) -> void:
	if from == Game.State.PAUSE and (to == Game.State.PLAY or to == Game.State.CUTSCENE):
		Inputs.quarantine()


# A look setting changed: the stage takes it now.
func _on_setting_changed(key: String) -> void:
	if key.begins_with("look/"):
		_apply_look()


# A ScriptBrain step pushing the stick `push` along `dir` for as long as it takes, from rest, to cover
# `distance` once the actor has coasted to a stop after it: d = v t - v^2 / (2 accel) + v^2 / (2 decel).
static func _leg(dir: Vector2, push: float, distance: float, tuning: LocomotionTuning) -> Dictionary:
	var v := Locomotion.new(tuning).target_speed(push, false)
	var seconds := (distance + v * v / (2.0 * tuning.accel) - v * v / (2.0 * tuning.decel)) / v
	return {frames = maxi(1, roundi(seconds * Engine.physics_ticks_per_second)), move = dir * push}


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
