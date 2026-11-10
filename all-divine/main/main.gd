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
## F1 (a pad's Select) shows or hides the controls list; F3 shows or hides the debug overlay; F4 turns the screen look off
## and on; F5 switches the region; F6, F7 and F8 spawn a tier I, II or III Knuckle and F9 resets the fight (the Arena's
## debug keys, which Main passes on); F11 or Alt+Enter switches between
## borderless fullscreen, where the game starts, and a 1280x720 window (WindowToggle); the menu button (Esc,
## Start) pauses and resumes, and "Paused" shows while it is paused (PauseLabel). This node runs while the game
## is paused (to hear the menu button); the stage, and so the world in it, stops.
##
## With --selftest (a user argument: godot -- --selftest) Abarax fights one tier I Knuckle in the yard through a
## scripted circuit instead (selftest_circuit: approach, jab, cross, hook, roll, guard, heavy) for SELFTEST_FRAMES
## physics frames, and the arena does nothing by itself but send that one Knuckle; the SelfTest autoload
## (core/self_test.gd), listening for errors since before this scene loaded, then quits: 0 if none was logged, else 1.

const DEFAULT_SETTINGS := preload("res://data/render/default_settings.tres")
const SELFTEST_FRAMES := 600
const YARD := "res://world/training_yard/training_yard.tscn"
const COURTYARD := "res://world/courtyard/courtyard.tscn"
## How far Abarax walks toward the Knuckle in the self-test before he waits for it, and the stick's push.
const SELFTEST_APPROACH := 2.0
const SELFTEST_WALK_PUSH := 0.6
## Frames to stand while the Knuckle closes on him, and between the circuit's blows.
const SELFTEST_WAIT := 90
const SELFTEST_PAUSE := 20
## Frames a palm, a roll, a guard and a heavy take, recovery included.
const SELFTEST_PALM_FRAMES := 24
## The hook is the longest of the three: it plays out (a press while it plays would be lost) before the roll.
const SELFTEST_HOOK_FRAMES := 95
const SELFTEST_ROLL_FRAMES := 40
const SELFTEST_GUARD_FRAMES := 50
const SELFTEST_HEAVY_FRAMES := 70

@onready var stage: PixelStage = $PixelStage
@onready var region: Region = $PixelStage/World/Region
@onready var hud: Hud = $PixelStage/Hud/Hud
@onready var player: Actor = $PixelStage/World/Player
@onready var camera_rig: CameraRig = $PixelStage/World/CameraRig
@onready var overlay: DebugOverlay = $DebugOverlay

## Whether the screen look is on (F4).
var look_on := true
## The window F11 and Alt+Enter switch: the game's own, unless a test gives it another.
@onready var window: Window = get_window()


func _ready() -> void:
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
	_apply_look()
	_enter_region()
	if SelfTest.active:
		start_selftest()


func _unhandled_input(event: InputEvent) -> void:
	if WindowToggle.is_toggle(event):
		WindowToggle.apply(window)
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
			KEY_F5:
				switch_region()
				get_viewport().set_input_as_handled()
				return
			KEY_F6, KEY_F7, KEY_F8, KEY_F9:
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
	if event.is_action_pressed(&"menu"):
		if Game.state == Game.State.PLAY:
			Game.change(Game.State.PAUSE)
		elif Game.state == Game.State.PAUSE:
			Game.change(Game.State.PLAY)
		get_viewport().set_input_as_handled()


## The arena of the region, or null when it is not one (the courtyard).
func arena() -> Arena:
	return region as Arena


## Switches to the other region (the training yard from the courtyard, the courtyard from the yard; F5): the player is
## put at its spawn (standing, with full bars, if he was dead), the camera snaps to him, the look takes its grade, and an
## arena begins its first wave. The old region, and any foes in it, are freed.
func switch_region() -> void:
	var to := COURTYARD if region.scene_file_path == YARD else YARD
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
## walk toward it, wait for it to come, jab, cross, hook, roll back, guard, heavy. He faces and aims at it throughout.
func selftest_circuit() -> Array:
	var foe := arena().enemies()[0]
	var start := _flat(region.spawn().origin)
	var toward := (_flat(foe.global_position) - start).normalized()
	var face := {face_target = foe, aim_target = foe}
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
		{frames = 1, move = -toward, press = [&"dodge"]},
		{frames = SELFTEST_ROLL_FRAMES}.merged(face),
		{frames = SELFTEST_GUARD_FRAMES, press = [&"guard"], hold = [&"guard"]}.merged(face),
		{frames = 1, press = [&"heavy"], hold = [&"heavy"]}.merged(face),
		{frames = SELFTEST_HEAVY_FRAMES}.merged(face),
	]


# What a region gives the game when it is entered: the Hud follows its arena (none in the courtyard), and an arena runs
# the fight by itself, begun with the player unless the self-test is on (it asks for what it wants, start_selftest).
# And the rims a fight will light are drawn, unseen, with the region's first frames (Rig.warm_rim): those frames build
# everything the region shows, and a rim that comes on later then builds nothing.
func _enter_region() -> void:
	player.rig.warm_rim()
	var fight := arena()
	hud.bind(player, camera_rig, stage, fight)
	if fight != null:
		fight.automatic = not SelfTest.active
		if not SelfTest.active:
			fight.begin(player)


# The look on (default_settings) or off (RenderSettings.off()), in the region's grade.
func _apply_look() -> void:
	stage.apply_settings(DEFAULT_SETTINGS if look_on else DEFAULT_SETTINGS.off(), region.grade)


# A ScriptBrain step pushing the stick `push` along `dir` for as long as it takes, from rest, to cover
# `distance` once the actor has coasted to a stop after it: d = v t - v^2 / (2 accel) + v^2 / (2 decel).
static func _leg(dir: Vector2, push: float, distance: float, tuning: LocomotionTuning) -> Dictionary:
	var v := Locomotion.new(tuning).target_speed(push, false)
	var seconds := (distance + v * v / (2.0 * tuning.accel) - v * v / (2.0 * tuning.decel)) / v
	return {frames = maxi(1, roundi(seconds * Engine.physics_ticks_per_second)), move = dir * push}


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
