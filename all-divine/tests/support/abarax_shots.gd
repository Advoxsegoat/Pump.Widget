class_name AbaraxShots
extends RefCounted
## One actor as the game's camera draws it, for the look of a model: a PixelStage with the rig of an ActorDef dressed
## as the def says (palette, hidden parts, scale), turned to a facing and shot at the game's zoom (1: 32 pixels to the
## metre, 640x360) or closer. Pictures are the World viewport's own, without its one-pixel margin.
##
## Use: var shots := AbaraxShots.new(); await shots.open(self); var image := await shots.shot(def, yaw_deg).
## `open` builds the stage under `host`; `close` frees it. Needs a display.

## How many physics ticks the pose is held before it is drawn, so what hangs off the body (the scarf, the feather) is at rest.
const SETTLE_TICKS := 90
const SIZE := Vector2i(640, 360)

var stage: PixelStage
var camera: CameraRig
var rig: Rig
var _middle: Node3D
var _rig_def: ActorDef


func open(host: Node) -> void:
	stage = (load("res://render/pixel_stage.tscn") as PackedScene).instantiate() as PixelStage
	stage.visible = false
	host.add_child(stage)
	ContactSheet._furnish(stage.world)
	for child in stage.world.get_children():
		if child is DirectionalLight3D:
			(child as DirectionalLight3D).shadow_enabled = false
	_middle = Node3D.new()
	stage.world.add_child(_middle)
	camera = CameraRig.new()
	camera.target = _middle
	camera.stage = stage
	stage.world.add_child(camera)
	camera.snap_now()
	await RenderingServer.frame_post_draw


func close() -> void:
	if stage != null:
		stage.queue_free()


## Puts `def`'s actor on the stage facing `yaw_deg` (0 faces the camera at the game's yaw; the actor's own +X, his left, goes
## to the camera's left when he faces it), standing at `clip`'s `frame` (the idle if there is no clip). Returns nothing; draw
## it with `draw`.
func pose(def: ActorDef, yaw_deg: float, clip := &"", frame := 0, mark := false) -> void:
	if rig != null:
		stage.world.remove_child(rig)
		rig.free()
	rig = def.rig_scene.instantiate() as Rig
	stage.world.add_child(rig)
	rig.apply_palette(def.palette)
	rig.hide_parts(def.hidden_parts)
	rig.set_model_scale(def.model_scale)
	rig.set_body_inflate(def.body_inflate)
	rig.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3.ZERO)
	if clip != &"":
		rig.play_move(clip, 0.0)
		rig.set_move_time(frame / 60.0)
	for tick in SETTLE_TICKS:
		rig.tick(1.0 / 60.0)


## The game camera (zoom 1) or, with `zoom` above 1, a close one aimed at the head at `pitch_deg` (the cine layer's own
## framing). Returns the picture, 640x360.
func draw(zoom := 1, pitch_deg := -40.0) -> Image:
	await rig.get_tree().physics_frame
	if zoom > 1:
		var shot := CinePose.new()
		shot.aim = rig.shown_pose(&"Head").origin + Vector3(0.0, 0.02, 0.0)
		shot.focus = shot.aim
		shot.zoom = zoom
		shot.pitch_deg = pitch_deg
		camera.cine = shot
		camera.cine_weight = 1.0
	else:
		camera.cine = null
		camera.cine_weight = 0.0
	camera.snap_now()
	for i in 3:
		await RenderingServer.frame_post_draw
	var full := stage.world.get_texture().get_image()
	return full.get_region(Rect2i(Vector2i.ONE, SIZE))


## One call: the actor of `def` at `yaw_deg` and `clip`/`frame`, drawn at `zoom`.
func shot(def: ActorDef, yaw_deg: float, zoom := 1, clip := &"", frame := 0, pitch_deg := -40.0) -> Image:
	pose(def, yaw_deg, clip, frame)
	return await draw(zoom, pitch_deg)


## Holds `clip` at `frame` for one physics tick more (the pose is already set up by `pose` with the clip): what the rig does
## as a game's tick does, so a spring bone swings as it would.
func step(clip: StringName, frame: int) -> void:
	rig.play_move(clip, 0.0)
	rig.set_move_time(frame / 60.0)
	rig.tick(1.0 / 60.0)


## A `size` piece of `image` (a picture of this stage) centred on the head, as it was drawn, `scale` times larger by whole pixels.
func head_crop(image: Image, size := Vector2i(80, 60), scale := 5, raise := 0.0) -> Image:
	var head := camera.camera.unproject_position(rig.shown_pose(&"Head").origin + Vector3(0.0, raise, 0.0)) - Vector2.ONE
	var rect := Rect2i(Vector2i(head.round()) - size / 2, size).intersection(Rect2i(Vector2i.ZERO, SIZE))
	var piece := image.get_region(rect)
	piece.resize(rect.size.x * scale, rect.size.y * scale, Image.INTERPOLATE_NEAREST)
	return piece
