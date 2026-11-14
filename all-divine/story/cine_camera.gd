class_name CineCamera
extends Node3D
## The node a scene's timeline animates: it holds the camera's part of the timeline (which shot, how far through it, how
## far the bars are in) and each physics frame hands the CameraRig the pose the shot solves to. The timeline
## (TimelineBuilder) writes `shot`, `progress` and `letterbox` as its tracks; an owner's edited timeline may write any of
## the four.
##
## The Director gives it its parts (`scene`, `world`, `rig`, `overlay`, `hud`) and sets the rig's `cine_weight` itself (the
## glide in and out): this node only says where the camera is when the weight is above 0. A shot with a `blend_in`
## glides from the pose the camera was showing when the shot began, over that many frames, by CinePose.blend (not the
## first shot: the Director's glide in is that one). A HANDHELD shot lifts the rig's trauma to its `shake` each frame, a
## trauma already higher (a blow) being left alone.
##
## It runs after the AnimationPlayer (its physics priority is later), counts its own physics frames, and so stops and goes
## on with the tree when it is paused.
##
## STOPPING THE ANIMATIONPLAYER DOES NOT GIVE ANYTHING BACK: the rig's weight, the bars and the suppressed Hud stay up. ONLY
## FREEING THIS NODE (or its parent) OR CALLING release() DOES. Whoever stops a scene early must do one of the two. Leaving the tree mid-scene (the node that plays the timeline is freed, a region
## changes) it gives everything back (`release`): the rig's weight and pose, the bars, the dialogue box, the Hud.

## The animated properties.
@export var shot := 0
@export var progress := 0.0
@export_range(0.0, 1.0) var letterbox := 0.0
@export_range(0.0, 1.0) var shake := 0.0

var scene: SceneShots
## world.call(name: StringName) -> Variant: where a target name is (a Vector3 on the floor) or null; see CinePose.solve.
var world: Callable
var rig: CameraRig
var overlay: CineOverlay
## The Hud the Director suppressed for the scene; given back on release.
var hud: Hud

var _pose: CinePose = null  # what the camera was handed last frame
var _glide_from: CinePose = null
var _last_shot := -1
var _since := 0  # physics frames in the current shot


func _init() -> void:
	name = TimelineBuilder.CAMERA
	process_physics_priority = 10


func _physics_process(_delta: float) -> void:
	if scene == null or scene.shots.is_empty() or not is_instance_valid(rig):
		return
	var index := clampi(shot, 0, scene.shots.size() - 1)
	var current := scene.shots[index]
	if index != _last_shot:
		_glide_from = _pose if _last_shot >= 0 and current.blend_in > 0 else null
		_last_shot = index
		_since = 0
	var pose := CinePose.solve(current, progress, world, _pose, scene.letterbox)
	if _glide_from != null and _since < current.blend_in:
		pose = CinePose.blend(_glide_from, pose, float(_since) / float(current.blend_in))
	_since += 1
	_pose = pose
	rig.cine = pose
	var trauma := shake
	if current.move == Shot.CamMove.HANDHELD:
		trauma = maxf(trauma, current.shake)
	if trauma > 0.0:
		rig.trauma = maxf(rig.trauma, trauma)
	if is_instance_valid(overlay):
		overlay.letterbox = letterbox


## Gives back what the scene took: the rig is the game camera again, the bars are out and the box is closed, the Hud draws.
## Harmless when there is nothing to give back, and when the parts are gone.
func release() -> void:
	if is_instance_valid(rig):
		rig.cine_weight = 0.0
		rig.cine = null
	if is_instance_valid(overlay):
		overlay.letterbox = 0.0
		overlay.close()
	if is_instance_valid(hud):
		hud.scene_fade = -1.0
		hud.suppressed = false
	_pose = null
	_glide_from = null
	_last_shot = -1


func _exit_tree() -> void:
	release()
