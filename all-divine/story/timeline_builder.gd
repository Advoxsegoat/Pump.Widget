class_name TimelineBuilder
extends RefCounted
## Turns a scene's shots into the one Animation its timeline plays, an AnimationPlayer animation the owner can open and
## edit in the Godot editor (tools/story/bake_timeline.gd writes it out; SceneShots.timeline then points at the edited
## copy, which plays instead of the generated one).
##
## Time in the animation is the scene's frames over 60, counted from the start of the glide in: a shot's frame `f` is at
## `(lead_in + f) / 60`. The tracks:
##   CineCamera:shot      a discrete value track: the index of the shot, a key at each shot's start
##   CineCamera:progress  a linear value track: 0 at a shot's start and 1 at its end, and from one shot to the next a cut
##   CineCamera:letterbox a linear value track, only when the scene is letterboxed: the bars slide in over 30 frames from 0
##                        and out over the last 30
##   Director             method tracks calling `_cue(kind: StringName, payload: Dictionary)` at the frame each thing
##                        happens: `&"beat"` (an ActorBeat: actor, clip, loop, blend, move_to, pace, face, look,
##                        placeholder), `&"line"` (speaker, text, expr, hold; a hold of 0 is the overlay's default),
##                        `&"sound"` (id, at_ref), `&"music"` (id) and `&"end"` at the last shot's end minus the return
##                        blend. Every payload also has `shot` (its id) and `frame` (the scene frame it falls on). An
##                        animation key holds one call, and two keys at one time replace each other, so a frame that has
##                        several things happening uses one more track for each, in the order of the data (a shot's beats,
##                        then its lines, then its cues), `end` last. A walk (`move_to`) is one call at its frame and
##                        nothing at a cut: the walk runs on across it (StoryWalk).
## The tracks' paths are relative to the AnimationPlayer's root: a node with a CineCamera child and a Director child.

## The names of the nodes the tracks write to and call, under the player's root.
const CAMERA := &"CineCamera"
const CUE_NODE := &"Director"
## The name of the generated animation.
const ANIMATION := &"scene"
## Frames before the last shot's end that the cast's clips fade back to locomotion.
const RETURN_BLEND := 15
## Frames the bars take to slide in, and out.
const BARS_FRAMES := 30
## A shot's progress reaches 1 this many seconds before its end, so that the next shot's first key (0) is a cut and not
## a ramp over a frame; half a millisecond is far under the physics step.
const PROGRESS_EDGE := 0.0005
## The picture turns by a smoothstep, whose fastest swing is this many times the average one.
const SWING_PEAK := 1.5
## The most degrees a frame may turn the picture in the glide back, and the most frames that glide is lengthened to.
const MAX_TURN_PER_FRAME := 3.0
const MAX_RETURN_FRAMES := 60

## Why the last `build` gave null; empty after one that built.
static var last_error := ""


## The animation for `scene`, or null when the checker has any problem with it (a gap, an overlap, a shot under 12 frames, a
## glide out of range, a call past its shot's end, ...), `last_error` then holding its first line. A listed placeholder is not one.
static func build(scene: SceneShots) -> Animation:
	last_error = ""
	var checker := ShotChecker.new()
	for line in checker.check(scene):
		if not checker.is_placeholder(line):  # a clip not made yet is listed, not refused, in a draft
			last_error = line
			return null
	var anim := Animation.new()
	anim.length = (scene.lead_in + scene.length() + return_frames(scene)) / 60.0
	anim.loop_mode = Animation.LOOP_NONE
	_camera_tracks(anim, scene)
	if scene.letterbox:
		_letterbox_track(anim, scene)
	_cue_tracks(anim, scene)
	return anim


## The frames the glide back to the game's camera takes after the last shot: the scene's `lead_out`, lengthened (to 60 at
## most) when the last shot is turned far from the game's yaw, so that the picture's fastest swing is no more than
## MAX_TURN_PER_FRAME degrees a frame. The Director's glide out and this timeline's end both use it. The turn is the last shot's
## yaw (an orbit's end; an over-the-shoulder shot's from `world`, a Callable as CinePose.solve takes, when given).
static func return_frames(scene: SceneShots, world := Callable()) -> int:
	if scene.shots.is_empty():
		return scene.lead_out
	var last := scene.shots[scene.shots.size() - 1]
	var yaw := last.yaw_to_deg if last.move == Shot.CamMove.ORBIT else last.yaw_deg
	if world.is_valid():
		yaw = CinePose.solve(last, 1.0, world).yaw_deg
	var turn := absf(rad_to_deg(angle_difference(deg_to_rad(yaw), deg_to_rad(CameraRig.YAW_DEG))))
	var needed := mini(MAX_RETURN_FRAMES, ceili(SWING_PEAK * turn / MAX_TURN_PER_FRAME))
	return maxi(scene.lead_out, needed)


## The player for `scene`: the generated animation in a new AnimationPlayer, or, when `scene.timeline` is set, the
## AnimationPlayer of that scene instead. Either way the player is a child of a root node (`Cutscene`) that has the
## CineCamera among its children, ready to be added to the tree; the node that takes the `_cue` calls is to be a child of
## that root named `Director` (the Director puts itself there, and the baked scene has a stand-in). Null when the scene
## cannot be built or its own timeline has no player.
static func player_for(scene: SceneShots) -> AnimationPlayer:
	if scene.timeline != null:
		var root := scene.timeline.instantiate()
		var found := root.find_children("*", "AnimationPlayer", true, false)
		if found.is_empty():
			root.free()
			return null
		return found[0] as AnimationPlayer
	var anim := build(scene)
	if anim == null:
		return null
	var root := Node.new()
	root.name = "Cutscene"
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	var library := AnimationLibrary.new()
	library.add_animation(ANIMATION, anim)
	player.add_animation_library("", library)
	root.add_child(player)
	root.add_child(CineCamera.new())
	return player


## The name of the animation to play on `player`: the generated one, or the first the owner's copy has.
static func animation_of(player: AnimationPlayer) -> StringName:
	if player.has_animation(ANIMATION):
		return ANIMATION
	var names := player.get_animation_list()
	return StringName(names[0]) if not names.is_empty() else &""


static func _camera_tracks(anim: Animation, scene: SceneShots) -> void:
	var shot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(shot_track, NodePath("%s:shot" % CAMERA))
	anim.track_set_interpolation_type(shot_track, Animation.INTERPOLATION_NEAREST)
	anim.value_track_set_update_mode(shot_track, Animation.UPDATE_DISCRETE)
	var progress := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(progress, NodePath("%s:progress" % CAMERA))
	anim.track_set_interpolation_type(progress, Animation.INTERPOLATION_LINEAR)
	anim.value_track_set_update_mode(progress, Animation.UPDATE_CONTINUOUS)
	for i in scene.shots.size():
		var shot := scene.shots[i]
		var start := (scene.lead_in + shot.start) / 60.0
		anim.track_insert_key(shot_track, start, i)
		anim.track_insert_key(progress, start, 0.0)
		anim.track_insert_key(progress, start + shot.length / 60.0 - PROGRESS_EDGE, 1.0)


static func _letterbox_track(anim: Animation, scene: SceneShots) -> void:
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath("%s:letterbox" % CAMERA))
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	var total := roundi(anim.length * 60.0)
	anim.track_insert_key(track, 0.0, 0.0)
	anim.track_insert_key(track, BARS_FRAMES / 60.0, 1.0)
	anim.track_insert_key(track, (total - BARS_FRAMES) / 60.0, 1.0)
	anim.track_insert_key(track, total / 60.0, 0.0)


# The calls, in order: by frame, and at one frame in the order of the data.
static func _cue_tracks(anim: Animation, scene: SceneShots) -> void:
	var events: Array[Dictionary] = []
	for shot in scene.shots:
		var base := scene.lead_in + shot.start
		for beat in shot.beats:
			events.append({"frame": base + beat.at, "kind": &"beat", "payload": _beat_payload(beat)})
		for line in shot.lines:
			events.append({"frame": base + line.at, "kind": &"line", "payload": {
				"speaker": line.speaker, "text": line.text, "expr": line.expr, "hold": line.hold}})
		for cue in shot.cues:
			var kind := &"sound" if cue.kind == CueEvent.Kind.SOUND else &"music"
			var payload := {"id": cue.id}
			if kind == &"sound":
				payload["at_ref"] = cue.at_ref
			events.append({"frame": base + cue.at, "kind": kind, "payload": payload})
		for event in events:
			if not event.payload.has("shot"):
				event.payload["shot"] = shot.id
	events.append({"frame": scene.total_frames() - scene.lead_out - RETURN_BLEND, "kind": &"end", "payload": {"shot": scene.shots[scene.shots.size() - 1].id}})
	for i in events.size():
		events[i]["index"] = i
	# The engine's sort is not stable above 16 elements: equal frames are told apart by their place in the data.
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.frame < b.frame or (a.frame == b.frame and a.index < b.index))
	var tracks: Array[int] = []
	var taken := {}  # frame -> how many calls are already on it
	for event in events:
		var used: int = taken.get(event.frame, 0)
		taken[event.frame] = used + 1
		while tracks.size() <= used:
			var track := anim.add_track(Animation.TYPE_METHOD)
			anim.track_set_path(track, NodePath(String(CUE_NODE)))
			tracks.append(track)
		event.payload["frame"] = event.frame
		anim.track_insert_key(tracks[used], event.frame / 60.0, {"method": &"_cue", "args": [event.kind, event.payload]})


static func _beat_payload(beat: ActorBeat) -> Dictionary:
	return {
		"actor": beat.actor, "clip": beat.clip, "loop": beat.loop, "blend": beat.blend, "move_to": beat.move_to,
		"pace": int(beat.pace), "face": beat.face, "look": beat.look, "placeholder": beat.placeholder,
	}
