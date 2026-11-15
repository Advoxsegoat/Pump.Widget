class_name StoryReel
extends Main
## Plays one scene on a real Main so that the owner's tools can see it: the storyboard's frames and the animatic.
##
##   tools/storyboard.sh <scene>   (this with --capture, then the sheet)
##   tools/animatic.sh <scene>     (this under Movie Maker, then ffmpeg)
##
## User arguments (after `--`): `--scene=<id>` (the folder under scenes/story; required), `--capture` and `--out=<dir>`,
## `--empty-too` (with --capture: each frame is also saved as <out>/frames/empty-NN.png with Abarax hidden, so that a test can
## tell which pixels are his), `--draw-all` (with --capture: draw every frame of the scene, as the animatic must; the tools leave
## it off: see below), `--no-player-settings` (the tools pass it: the picture is made on the default settings, never
## the player's).
##
## The game is set up as a scene's rehearsal: the arena is quiet (no wave, no foe), Abarax stands, without a hand to move him,
## at the scene's `rehearsal.abarax` mark (or the region's spawn when it has none), and WAIT_FRAMES ticks later the Director
## plays the scene (Director.play, with `allow_any_state`, and a first viewing: `skip_always` off). TAIL_FRAMES ticks after
## the scene is over (the glide home included) the run quits.
##
## With `--capture` it saves, at each shot's key frame (ShotText.key_frames), the exact picture of the window (640 by 360, the
## HUD, bars and dialogue box as they are) to <out>/frames/shot-NN.png. Without it, it burns a caption into the picture
## (CineOverlay.burn_in, ShotText.burn_in): the shot, what is not seen in a silent video (a sound or music cue, a clip that is
## not made yet, a stand-in portrait). It leaves the game as it found it: nothing is paused and no moment is on when it quits.
##
## A storyboard needs only its key frames, and drawing is most of the time a frame takes: with `--capture` the reel plays the scene
## with the render loop off (as the Director's own tests do) and turns it on for DRAW_BEFORE ticks before each key frame and
## DRAW_AFTER after it, so that the picture is the one a run that drew every frame would have taken (tests/render/test_story_shots.gd
## holds it: byte for byte).
##
## Exit codes: 0 when the scene was played to its end; 1 when it was refused, given up, did not end, or the window was not
## 640 by 360 for a capture; 2 for a wrong command line (no scene, or one that does not exist).

## Ticks before the scene begins (the picture settles: the look warms up, Abarax comes to rest).
const WAIT_FRAMES := 30
## Ticks the run goes on after the scene is over.
const TAIL_FRAMES := 60
## Ticks past the scene's own length (and the tail) after which it is given up as never ending.
const GRACE_FRAMES := 240
const PICTURE := Vector2i(640, 360)
## Ticks drawn before a key frame and after it when the rest of the scene is played undrawn.
const DRAW_BEFORE := 3
const DRAW_AFTER := 2

var scene_id: StringName = &""
var capture := false
var out_dir := ""
var empty_too := false
var draw_all := false

var _shots: SceneShots
var _director: Director
var _ticks := 0
var _began := -1
var _finished_at := -1
var _total := 0
var _targets := PackedInt32Array()
var _next := 0
var _status := 0
var _problem := ""
var _stopped := false
var _size_wrong := false
var _taking := false


## The tool's own arguments from `args`: {scene, capture, out, empty}.
static func read_arguments(args: PackedStringArray) -> Dictionary:
	var found := {"scene": "", "capture": false, "out": "", "empty": false, "draw_all": false}
	for arg in args:
		if arg.begins_with("--scene="):
			found["scene"] = arg.trim_prefix("--scene=")
		elif arg == "--capture":
			found["capture"] = true
		elif arg == "--empty-too":
			found["empty"] = true
		elif arg == "--draw-all":
			found["draw_all"] = true
		elif arg.begins_with("--out="):
			found["out"] = arg.trim_prefix("--out=")
	return found


func _ready() -> void:
	var arguments := read_arguments(OS.get_cmdline_user_args())
	scene_id = StringName(arguments["scene"])
	capture = arguments["capture"]
	out_dir = arguments["out"]
	empty_too = arguments["empty"]
	draw_all = arguments["draw_all"]
	super()
	var path := "res://scenes/story/%s/shots.tres" % scene_id
	if scene_id == &"" or not ResourceLoader.exists(path):
		_stop("no scene '%s' (give --scene=<a folder of scenes/story>)" % scene_id, 2)
		return
	_shots = load(path) as SceneShots
	if _shots == null:
		_stop("'%s' is not a scene's shot list" % path, 2)
		return
	if capture:
		if out_dir == "":
			_stop("--capture needs --out=<dir>", 2)
			return
		if out_dir.is_relative_path():
			out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
		_targets = StoryboardPage.ShotText.key_frames(_shots)
	var fight := arena()
	if fight != null:
		fight.automatic = false
		fight.clear_foes()
	player.set_brain(Brain.new())
	hud.hints_visible = false
	var rehearsal := _shots.mark(&"rehearsal.abarax")
	if rehearsal != null and rehearsal.space == SceneMark.Space.REGION:
		player.place(Transform3D(Basis(Vector3.UP, deg_to_rad(rehearsal.yaw_deg)), rehearsal.position))
	camera_rig.snap_now()


func _physics_process(_delta: float) -> void:
	if _stopped or _shots == null:
		return
	_ticks += 1
	if _began < 0:
		if _ticks == WAIT_FRAMES:
			_begin()
		return
	if not capture:
		_burn_in()
	elif not draw_all:
		RenderingServer.render_loop_enabled = _picture_wanted()
	if _finished_at >= 0 and _ticks - _finished_at >= TAIL_FRAMES:
		_stop("", _status if not _size_wrong else 1)
	elif _finished_at < 0 and _ticks - _began > _total + TAIL_FRAMES + GRACE_FRAMES:
		_stop("the scene did not end (%d ticks in, it is %d frames long)" % [_ticks - _began, _total], 1)


## Whether the tick that brings the scene to frame `coming` (from the first shot's first frame) is drawn when only the key frames
## `targets` and their neighbours are: DRAW_BEFORE ticks before each and DRAW_AFTER after it.
static func is_drawn(coming: int, targets: PackedInt32Array) -> bool:
	for target in targets:
		if coming >= target - DRAW_BEFORE and coming <= target + DRAW_AFTER:
			return true
	return false


# Whether the picture of the coming tick is wanted: a key frame is near (see DRAW_BEFORE), or one is being taken. Before the scene
# begins and after it ends nothing is drawn but the key frames' neighbours: the wait is drawn (the look warms up), the tail is not.
func _picture_wanted() -> bool:
	if _taking or not is_instance_valid(_director) or _director.phase == Director.Phase.DONE:
		return _taking or _began < 0
	return is_drawn(_director.frame + 1 - _shots.lead_in, _targets)


func _process(_delta: float) -> void:
	if not capture or _stopped or _began < 0 or _next >= _targets.size():
		return
	if not is_instance_valid(_director) or _director.phase == Director.Phase.DONE:
		return
	if _director.frame < _shots.lead_in + _targets[_next]:
		return
	var index := _next
	_next += 1
	_taking = true
	if empty_too:
		get_tree().paused = true   # both pictures of the same instant (the camera may be moving)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != PICTURE:
		_size_wrong = true
		printerr("StoryReel: the window is %dx%d, not %dx%d: run it through tools/storyboard.sh (it sets the window's size)" % [image.get_width(), image.get_height(), PICTURE.x, PICTURE.y])
	_save(image, "frames/shot-%02d.png" % (index + 1))
	if empty_too:
		player.visible = false
		await RenderingServer.frame_post_draw
		_save(get_viewport().get_texture().get_image(), "frames/empty-%02d.png" % (index + 1))
		player.visible = true
		get_tree().paused = false
	_taking = false


func _save(image: Image, name: String) -> void:
	var path := out_dir.path_join(name)
	var err := image.save_png(path)
	if err != OK:
		printerr("StoryReel: cannot write %s: %s" % [path, error_string(err)])
		_status = 1


func _begin() -> void:
	Director.allow_any_state = true
	Director.skip_always = false
	_director = Director.play(scene_id, self)
	if _director == null:
		_stop("the scene was refused: %s" % Director.last_refusal, 1)
		return
	_began = _ticks
	_total = _director.total_frames()
	_director.refused.connect(func(reason: StringName) -> void:
		_status = 1
		_stop("the scene was given up: %s" % reason, 1))
	_director.finished.connect(func(_skipped: bool) -> void: _finished_at = _ticks)


# The caption for this frame of the scene, on the overlay the Director made (a missing overlay is the glide's edge: nothing yet).
# (A freed Director compares equal to null in GDScript: `_began` says whether the scene was begun.)
func _burn_in() -> void:
	if not is_instance_valid(_director):
		return
	for child in hud.get_parent().get_children():
		var overlay := child as CineOverlay
		if overlay != null:
			if _director.phase == Director.Phase.LEAD_OUT:
				overlay.burn_in = "GLIDE OUT"
			else:
				overlay.burn_in = StoryboardPage.ShotText.burn_in(_shots, _director.frame - _shots.lead_in)


func _stop(why: String, code: int) -> void:
	if _stopped:
		return
	_stopped = true
	RenderingServer.render_loop_enabled = true
	if why != "":
		printerr("StoryReel: " + why)
	if capture and code == 0 and _next < _targets.size():
		printerr("StoryReel: only %d of %d frames were taken" % [_next, _targets.size()])
		code = 1
	_give_back_settings()
	get_tree().quit(code)
