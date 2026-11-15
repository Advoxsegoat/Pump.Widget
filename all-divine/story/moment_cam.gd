class_name MomentCam
extends Node
## Listens to the player's combat moments and, for the finisher, plays the finisher's camera dip: the one-shot scene
## data/story/moments/finisher.tres, tuned by data/tuning/story.tres, through the same Director and cine layer a scene uses (a
## moment has no cast, no brains, no state, no Hud and no world of its own: Director's class comment says what it leaves out).
## A grab has no dip. It only ever watches: nothing of the fight reads it, so the same fight plays frame for frame with the dip on
## or off.
##
## The dip plays when the player's setting `camera/dips` and the tuning's `moment_dip_on` are both on (asked on each finisher; a
## dip that is playing when one is turned off, in the pause menu say, goes out by its own way out). A second finisher while one
## dips restarts the dip from the picture the camera shows. Made by Director.watch_moments, under the camera rig.

const NAME := &"MomentCam"
const FINISHER := preload("res://data/story/moments/finisher.tres")
## The share of its frames the slow-motion beat (moment_slow_frames) lets the fighters act on: Melee.slow's, as the chain's own is.
const SLOW_SHARE := 0.4
## The shortest dip, and the longest the shot may be (a moment is 90 frames at most, the glides included).
const MIN_FRAMES := 12

## The tuning in force: data/tuning/story.tres, unless a test gives it another.
var tuning: StoryTuning = preload("res://data/tuning/story.tres")

var _player: Actor
var _rig: CameraRig
var _hud: Hud
var _director: Director = null

## The moment playing now, or null.
var director: Director:
	get:
		return _director if is_instance_valid(_director) and _director.phase != Director.Phase.DONE else null


## The scene a moment of `tuning` plays: the finisher's, its one shot as long as `moment_frames` says (12 frames to what leaves
## the 90 of a moment's most after the glides) and at the zoom `moment_zoom` says. A copy: the file's own is never changed.
static func scene_for(tuning: StoryTuning) -> SceneShots:
	var scene := FINISHER.duplicate_deep() as SceneShots
	var most := ShotChecker.MOMENT_MAX_FRAMES - scene.lead_in - scene.lead_out
	scene.shots[0].length = clampi(tuning.moment_frames, MIN_FRAMES, most)
	scene.shots[0].zoom = clampi(tuning.moment_zoom, int(CinePose.ZOOM_MIN), int(CinePose.ZOOM_MAX))
	return scene


## Listens to `player`'s moments from now on (and to no one else's): the dip is made on `rig`'s camera and leaves `hud` alone.
func watch(player: Actor, rig: CameraRig, hud: Hud) -> void:
	if _player != null and is_instance_valid(_player) and _player.combat_moment.is_connected(_on_moment):
		_player.combat_moment.disconnect(_on_moment)
	_player = player
	_rig = rig
	_hud = hud
	if _player != null and not _player.combat_moment.is_connected(_on_moment):
		_player.combat_moment.connect(_on_moment)


## A combat moment of `kind` between the player and `other`: the finisher dips the camera toward the middle of the two (a dip already
## playing starts over from where it is); anything else, and any finisher while the dips are off, does nothing.
func moment(kind: StringName, other: Actor) -> void:
	if kind != &"finisher" or other == null or not _wanted():
		return
	var playing := director
	if playing != null:
		playing.restart_moment(_player, other)
		return
	if Director.current() != null:
		return  # a scene has the camera
	var made := Director.new()
	if not made.begin_moment(scene_for(tuning), _rig, _hud, _player, other):
		made.free()
		return
	made.may_go_on = _wanted
	made.hold_frames = roundi(tuning.moment_hold_share * float(made.scene.length()))
	_director = made
	if tuning.moment_slow_frames > 0:
		Melee.slow(tuning.moment_slow_frames, SLOW_SHARE)


# Whether a dip may play: the player's switch and the tuning's.
func _wanted() -> bool:
	return tuning.moment_dip_on and Settings.get_value("camera/dips") == true


func _on_moment(kind: StringName) -> void:
	if is_instance_valid(_player) and _player.paired_with != null:
		moment(kind, _player.paired_with)
