class_name ClipShots
extends RefCounted
## What a clip looks like in the game's own picture (640x360 from the gameplay camera): Abarax on a bare stage, turned to face
## down, up, left or right of the screen, at the frame of a clip where his head is furthest from where the guard stance has
## it. For the checks of how far a dodge moves on screen: the head in game pixels, and how many pixels of his silhouette
## are not the guard stance's. Abarax stands still on the stage (the clip's root travel is not played).
##
## Use: var shots := ClipShots.new(); await shots.open(self); var m := await shots.measure(&"sway_left_slip", &"down").
## `open` builds the stage under `host`; `close` frees it.

## The guard stance every clip is measured against.
const GUARD := &"guard_hold"
## A pixel is the body's when its colour differs from the empty stage's by more than this (summed over red, green, blue).
const BODY_THRESHOLD := 0.06
## How many physics ticks a pose is held before it is drawn, so what hangs off the body (the scarf) is at rest.
const SETTLE_TICKS := 45
## The way Abarax is turned (about the vertical) to face each side of the screen, found at open from where his forward
## points on screen.
const FACINGS: Array[StringName] = [&"down", &"up", &"left", &"right"]

var stage: PixelStage
var rig: Rig
var camera: CameraRig
var _yaw := {}  # facing -> radians
var _empty := {}  # facing -> Image of the stage without him
var _guard := {}  # facing -> {mask, head}


func open(host: Node) -> void:
	var def := load("res://data/actors/abarax.tres") as ActorDef
	stage = (load("res://render/pixel_stage.tscn") as PackedScene).instantiate() as PixelStage
	stage.visible = false
	host.add_child(stage)
	ContactSheet._furnish(stage.world)
	for child in stage.world.get_children():
		if child is DirectionalLight3D:
			(child as DirectionalLight3D).shadow_enabled = false  # a shadow is no part of the body
	var middle := Node3D.new()
	stage.world.add_child(middle)
	rig = def.rig_scene.instantiate() as Rig
	stage.world.add_child(rig)
	rig.apply_palette(def.palette)
	rig.hide_parts(def.hidden_parts)
	rig.set_model_scale(def.model_scale)
	camera = CameraRig.new()
	camera.target = middle
	camera.stage = stage
	stage.world.add_child(camera)
	camera.snap_now()
	await RenderingServer.frame_post_draw
	var origin := camera.camera.unproject_position(Vector3.UP * 0.9)
	for yaw in [0.0, PI / 2.0, PI, -PI / 2.0]:
		var ahead := camera.camera.unproject_position(Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 1.0) + Vector3.UP * 0.9) - origin
		var side: StringName
		if absf(ahead.x) > absf(ahead.y):
			side = &"right" if ahead.x > 0.0 else &"left"
		else:
			side = &"down" if ahead.y > 0.0 else &"up"
		_yaw[side] = yaw


func close() -> void:
	if stage != null:
		stage.queue_free()


# Draws `clip` at `frame` with Abarax facing `facing`; returns the picture.
func _shot(clip: StringName, frame: int, facing: StringName) -> Image:
	await rig.get_tree().physics_frame
	rig.global_transform = Transform3D(Basis(Vector3.UP, _yaw[facing]), Vector3.ZERO)
	rig.play_move(clip, 0.0)
	rig.set_move_time(frame / 60.0)
	for tick in SETTLE_TICKS:
		rig.tick(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	return stage.world.get_texture().get_image()


func _mask(image: Image, empty: Image) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y)
			var b := empty.get_pixel(x, y)
			mask[y * image.get_width() + x] = 1 if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > BODY_THRESHOLD else 0
	return mask


# The empty stage and the guard stance as seen facing `facing`, drawn once.
func _prepare(facing: StringName) -> void:
	if _guard.has(facing):
		return
	rig.visible = false
	_empty[facing] = await _shot(GUARD, 0, facing)
	rig.visible = true
	var image := await _shot(GUARD, 0, facing)
	_guard[facing] = {"mask": _mask(image, _empty[facing]), "head": camera.camera.unproject_position(rig.shown_pose(&"Head").origin)}


## The frame of `clip` where the head is furthest from the guard stance's (in the body's own frame, so the same for every
## facing).
func peak_frame(clip: StringName) -> int:
	var guard := _body_head(GUARD, 0)
	var anim := rig.tree.get_animation(clip)
	var best := -1.0
	var frame := 0
	for f in Marks.frame_of(anim.length) + 1:
		var off := (_body_head(clip, f) - guard).length()
		if off > best:
			best = off
			frame = f
	return frame


# Where the clip has the head at `frame`, in the body's frame.
func _body_head(clip: StringName, frame: int) -> Vector3:
	rig.play_move(clip, 0.0)
	rig.set_move_time(frame / 60.0)
	rig.tick(1.0 / 60.0)
	return rig.global_transform.basis.inverse() * (rig.animated_pose(&"Head").origin - rig.global_position)


## {frame, head, silhouette} of `clip` at its peak frame facing `facing`: `head` is how far the head moved on screen from the
## guard stance's, in game pixels; `silhouette` how many pixels of the body differ from the guard stance's.
func measure(clip: StringName, facing: StringName, frame := -1) -> Dictionary:
	await _prepare(facing)
	if frame < 0:
		frame = await peak_frame(clip)
	var image := await _shot(clip, frame, facing)
	var mask := _mask(image, _empty[facing])
	var guard: PackedByteArray = _guard[facing]["mask"]
	var changed := 0
	for i in mask.size():
		if mask[i] != guard[i]:
			changed += 1
	var head := camera.camera.unproject_position(rig.shown_pose(&"Head").origin)
	return {"frame": frame, "head": head.distance_to(_guard[facing]["head"] as Vector2), "silhouette": changed}
