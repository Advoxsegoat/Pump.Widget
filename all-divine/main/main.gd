class_name Main
extends Node
## The game: a region (the courtyard), Abarax in it and the camera on him, drawn by the PixelStage in the
## screen look.
##
## When ready, the game goes to PLAY; Abarax stands at the region's spawn with the player's hands on him (a
## PlayerBrain turned by the camera's yaw); the camera takes him as its target and snaps to him; and the stage
## puts on the look (data/render/default_settings.tres) in the region's grade.
##
## F3 shows or hides the debug overlay; F4 turns the screen look off and on; F11 or Alt+Enter switches between
## borderless fullscreen, where the game starts, and a 1280x720 window (WindowToggle); the menu button (Esc,
## Start) pauses and resumes, and "Paused" shows while it is paused (PauseLabel). This node runs while the game
## is paused (to hear the menu button); the stage, and so the world in it, stops.
##
## With --selftest (a user argument: godot -- --selftest) Abarax runs a scripted circuit of the courtyard instead
## (selftest_circuit) for SELFTEST_FRAMES physics frames; the SelfTest autoload (core/self_test.gd), listening
## for errors since before this scene loaded, then quits: 0 if none was logged, else 1.

const DEFAULT_SETTINGS := preload("res://data/render/default_settings.tres")
const SELFTEST_FRAMES := 600
## How far from the fountain's centre the self-test's walk stops (its basin is 2.5 m across the radius).
const SELFTEST_FOUNTAIN_DISTANCE := 4.0
## How far the self-test walks, at SELFTEST_WALK_PUSH on the stick, before it jogs the rest of the way.
const SELFTEST_WALK := 1.0
const SELFTEST_WALK_PUSH := 0.4
## About how far a dodge roll takes him (its MoveData scales the clip's root motion to about 3 m).
const SELFTEST_ROLL := 3.0
## Frames to stand between the circuit's legs: long enough for a jog to come to a stop.
const SELFTEST_PAUSE := 20
## Frames a roll and a jab take, recovery included.
const SELFTEST_MOVE_FRAMES := 40

@onready var stage: PixelStage = $PixelStage
@onready var region: Region = $PixelStage/World/Region
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
	if event.is_action_pressed(&"menu"):
		if Game.state == Game.State.PLAY:
			Game.change(Game.State.PAUSE)
		elif Game.state == Game.State.PAUSE:
			Game.change(Game.State.PLAY)
		get_viewport().set_input_as_handled()


## Starts the self-test's circuit: Abarax runs selftest_circuit, and the SelfTest autoload ends the game
## SELFTEST_FRAMES physics frames from now, saying how far from StairsTop he ended.
func start_selftest() -> void:
	player.set_brain(ScriptBrain.new(selftest_circuit()))
	var top := (region.get_node(^"StairsTop") as Node3D).global_position
	SelfTest.begin(SELFTEST_FRAMES, func() -> String:
		return "Abarax ended %.2f m from StairsTop" % player.global_position.distance_to(top))


## The self-test's circuit, as ScriptBrain steps from the spawn: walk, then jog, to the fountain; roll back the
## way he came; jab; jog to StairsTop, up the stairs. Each leg is timed from the actor's locomotion tuning to
## cover its distance from rest and coast to a stop.
func selftest_circuit() -> Array:
	var tuning := player.def.locomotion
	var start := _flat(region.spawn().origin)
	var fountain := _flat((region.get_node(^"PointsOfInterest/Fountain") as Node3D).global_position)
	var top := _flat((region.get_node(^"StairsTop") as Node3D).global_position)
	var toward := (fountain - start).normalized()
	var by_fountain := fountain - toward * SELFTEST_FOUNTAIN_DISTANCE
	var rolled_to := by_fountain - toward * SELFTEST_ROLL
	return [
		{frames = SELFTEST_PAUSE},
		_leg(toward, SELFTEST_WALK_PUSH, SELFTEST_WALK, tuning),
		{frames = SELFTEST_PAUSE},
		_leg(toward, 1.0, start.distance_to(by_fountain) - SELFTEST_WALK, tuning),
		{frames = SELFTEST_PAUSE},
		{frames = 1, move = -toward, press = [&"dodge"]},
		{frames = SELFTEST_MOVE_FRAMES},
		{frames = 1, press = [&"palm"]},
		{frames = SELFTEST_MOVE_FRAMES},
		_leg((top - rolled_to).normalized(), 1.0, rolled_to.distance_to(top), tuning),
	]


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
