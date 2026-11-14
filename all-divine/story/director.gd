class_name Director
extends Node
## Plays a scene in the live game: it takes the fight as it is, plays the scene, and hands the fight back with no seam.
##
## The scene is data (SceneShots) and the timeline TimelineBuilder makes of it plays in an AnimationPlayer under a `Cutscene`
## root that this node is added to, named `Director`: the timeline's method tracks call `_cue` here, one line each. What a
## scene does to the people in it is only what a brain does: each actor of the cast is given a DirectorBrain (the old one is
## kept for the hand-back), whose walks, facings and looks the beats set, and whose clips are laid over the rig by the
## timeline's time, so the actors' own bodies do the acting (locomotion, feet, head) and nobody is moved any other way.
##
## The phases:
##   WAITING   the scene has been asked for but not begun: it waits (START_WAIT frames at most) for hit-stop and the slow-down
##             to be over and for every live actor of the cast to be on the floor and out of a pair (a pair is waited for
##             up to PAIR_WAIT frames, and one that does not end gives the scene up). If all is settled it begins in the call.
##   LEAD_IN   the camera glides from the game's pose to the first shot over `lead_in` frames (CameraRig.cine_weight 0 to 1);
##             the first frame's picture is the game's own. The fight is taken as it is: whatever move a live actor was in is
##             stopped at that frame (nothing it had begun lands, no window stays open, no effect stays on), what it had
##             buffered is forgotten, the Hud is hidden and the game is in CUTSCENE.
##   PLAY      the shots.
##   LEAD_OUT  at the last shot's end control comes back AT ONCE, with the camera still gliding home over `return_frames`
##             frames from the last shot to wherever the game's camera now is: the live actors have their old brains, the
##             spawned ones their `after`, the game is in PLAY and the Hud is shown. Nothing that went down during the scene
##             is a press (Inputs.quarantine), no foe begins an attack for REST_FRAMES, and the cast's bars are as they were.
##   DONE
## A first viewing cannot be skipped; later ones can (skip): the cast is put where the scene leaves it and the glide home
## takes SKIP_LEAD_OUT frames from the picture the camera shows then.
##
## It runs before the actors it drives (physics priority -10) and the timeline before it (-20), so a beat that arrives on a
## frame is acted on by that frame's actors. Once it is DONE the node is freed with its Cutscene root: read what you need
## from `finished`.

enum Phase { WAITING, LEAD_IN, PLAY, LEAD_OUT, DONE }

## The scene has begun (the clock is at 0).
signal started(scene_id: StringName)
## The scene was asked for and given up: `reason` is Director.last_refusal's value.
signal refused(reason: StringName)
## The scene is over and the camera is home; `skipped` says whether it was cut short.
signal finished(skipped: bool)
## A music cue, signalled and not played (there is no music system yet).
signal music_cue(id: StringName)
## A line has come up in the dialogue box.
signal line_shown(speaker: StringName, text: String)

## Frames the wait for hit-stop, the slow-down and the floor may last, and for a pair to end.
const START_WAIT := 36
const PAIR_WAIT := 90
## Frames the cast's clips fade back to locomotion before the last shot's end (the timeline's own number).
const RETURN_BLEND := TimelineBuilder.RETURN_BLEND
## Frames of the glide home when a scene is skipped.
const SKIP_LEAD_OUT := 20
## The most degrees any bone of an actor may differ from idle at the hand-back.
const POSE_MATCH_DEG := 4.0
## A body is at its mark within this many metres.
const ARRIVE := StoryWalk.ARRIVAL
## Frames after the hand-back that no foe begins an attack: the player has his hands back before anyone swings at him.
const REST_FRAMES := 30
## Frames a foe whose swing the scene stopped is left free to settle back to its stance, before it is held like the rest.
const SETTLE_FRAMES := 10
const ACTOR_SCENE := "res://actors/actor.tscn"
## How high above a mark the head follows it.
const LOOK_HEIGHT := 1.5

## Why the last begin was refused (empty after one that was not).
static var last_refusal: StringName = &""
## Tools play scenes whatever the game is doing.
static var allow_any_state := false
## Tools skip a scene that has not been seen.
static var skip_always := false

static var _current: Director = null
static var _spawned := {}  # actor name -> how many have been made, for the dice of the brains they get

var scene: SceneShots
## Scene frames since the clock started, the lead-in included: the wait does not count. A cue of frame `f` arrives when it is `f`.
var frame := 0
var phase: Phase = Phase.WAITING
## Cast name to the actor, once the scene has begun (a dropped optional actor is not there).
var cast := {}

var _region: Node3D
var _rig: CameraRig
var _hud: Hud
var _root: Node
var _player: AnimationPlayer
var _camera: CineCamera
var _overlay: CineOverlay
var _world_root: Node
var _waited := 0
var _dropped := {}  # cast name -> true
var _starts := {}  # cast name -> Transform3D as the scene began (a spawn: its mark)
var _marks := {}  # mark name -> Vector3, in the region
var _brains := {}  # Actor -> its DirectorBrain
var _old_brains := {}  # live Actor -> the brain it had
var _held_brains := {}  # non-cast Actor -> the brain it had, while it is held
var _was_guarding := {}  # Actor -> whether its guard stance was up when the scene began
var _bars := {}  # Actor -> its Stats as the scene began (Stats.save)
var _clips := {}  # Actor -> {clip, loop, from, length, until}: the clip being driven, `from` the frame it began on
var _look_at := {}  # Actor -> the name its head follows
var _face_at := {}  # Actor -> the name its body faces
var _settling := {}  # non-cast Actor -> the frame its freeze begins
var _return_frames := 0
var _lead_out_at := 0  # the frame the hand-back and the glide home began on
var _lead_out_length := 1
var _weight_from := 1.0
var _bars_from := 0.0
var _skipping := false
var _frozen_world := {}  # name -> Vector3: where the targets were when the scene was skipped (the camera holds still)
var _handed_back := false


## Plays the scene `scene_id` (res://scenes/story/<id>/shots.tres) in the game `host` (a Main): finds the camera rig (group
## `camera_rig`), the stage and the Hud under it and begins. Null if the scene is unknown or refused (Director.last_refusal
## says why, and nothing was changed); a scene that is taken but must wait for a pair to end can still be given up later
## (`refused`).
static func play(scene_id: StringName, host: Node) -> Director:
	last_refusal = &""
	var path := "res://scenes/story/%s/shots.tres" % scene_id
	if not ResourceLoader.exists(path):
		last_refusal = StringName("unknown_scene:%s" % scene_id)
		return null
	var shots := load(path) as SceneShots
	var rig := host.get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	var hud := host.get("hud") as Hud
	var region := host.get("region") as Node3D
	if shots == null or rig == null or hud == null or region == null:
		last_refusal = &"no_game"
		return null
	var director := Director.new()
	if not director.begin(shots, region, rig, hud, host):
		director.free()
		return null
	return director


## The scene playing now (one that has begun and is not over), or null.
static func current() -> Director:
	return _current if is_instance_valid(_current) and _current.phase != Phase.DONE else null


## Forgets how many of each name were made (the dice of a spawned foe's brain): for tests.
static func reset_spawn_counts() -> void:
	_spawned.clear()


## Begins `shots` with the parts given: the `region` that spawned actors go into, the camera `rig`, the `hud`, and the `host`
## whose tree it is. True if the scene is taken (it may wait a little before it starts); false if it is refused, and then
## nothing at all has changed (no state, brain, node or camera) and Director.last_refusal says why.
func begin(shots: SceneShots, region: Node3D, rig: CameraRig, hud: Hud, _host: Node) -> bool:
	last_refusal = &""
	var reason := _refusal(shots, rig)
	if reason != &"":
		last_refusal = reason
		return false
	scene = shots
	_region = region
	_rig = rig
	_hud = hud
	_world_root = rig.get_parent()
	_resolve_cast()
	if not _build_timeline():
		last_refusal = &"no_timeline"
		return false
	_current = self
	phase = Phase.WAITING
	if _settled():
		_start_scene()
	return true


## Cuts the scene short, after a first viewing: the cast is put where the scene leaves it and the camera glides home in
## SKIP_LEAD_OUT frames from where it is. False when it did nothing (not seen before, waiting, over, or already skipping).
func skip() -> bool:
	if not is_skippable():
		return false
	_skipping = true
	_frozen_world = _snapshot_world()
	if is_instance_valid(_player):
		_player.stop()
	_overlay.close()
	_place_the_cast()
	_weight_from = _rig.cine_weight
	_bars_from = _camera.letterbox
	_hand_back(SKIP_LEAD_OUT)
	return true


## Whether skip() would do something now.
func is_skippable() -> bool:
	if scene == null or _skipping or (phase != Phase.LEAD_IN and phase != Phase.PLAY):
		return false
	return skip_always or StoryLog.seen(scene.id)


## The scene's length in frames, the glides included.
func total_frames() -> int:
	return scene.lead_in + scene.length() + _return_frames if scene != null else 0


func _exit_tree() -> void:
	if _current == self:
		_current = null
	if (phase == Phase.LEAD_IN or phase == Phase.PLAY) and not _handed_back:
		_give_back_control()


func _physics_process(_delta: float) -> void:
	match phase:
		Phase.WAITING:
			_wait()
		Phase.LEAD_IN, Phase.PLAY:
			_play_frame()
		Phase.LEAD_OUT:
			_lead_out_frame()


# --- refusing ---

# Why the scene is not taken, or &"" if it is (the reason, a colon and the actor's name for a cast problem).
func _refusal(shots: SceneShots, rig: CameraRig) -> StringName:
	if shots == null or shots.shots.is_empty():
		return &"empty_scene"
	if shots.kind == SceneShots.Kind.MOMENT:
		return &"moment_not_built"  # a combat moment is Task 4's
	if Game.state != Game.State.PLAY and not allow_any_state:
		return &"not_playing"
	if current() != null:
		return &"already_playing"
	for entry in shots.cast:
		var reason := _cast_problem(entry, rig)
		if reason == &"":
			continue
		if not entry.required and (reason == &"cast_absent" or reason == &"cast_dead"):
			continue
		return StringName("%s:%s" % [reason, entry.actor])
	return &""


# What is wrong with one cast entry, or &"".
func _cast_problem(entry: CastEntry, rig: CameraRig) -> StringName:
	if entry.source == CastEntry.Source.SPAWN:
		return &"no_def" if entry.def == null or entry.def.rig_scene == null else &""
	var found := _find_live(entry, rig)
	if found == null:
		return &"cast_absent"
	if found.def == null or found.def.rig_scene == null:
		return &"no_def"
	if found.dead:
		return &"cast_dead"
	if found.paired_with != null and _pair_frames_left(found) > PAIR_WAIT:
		return &"cast_busy"
	return &""


# The live actor a cast entry names (null for a spawn, or one that is not in the game).
func _find_live(entry: CastEntry, rig: CameraRig) -> Actor:
	var root := rig.get_parent()
	if entry.source == CastEntry.Source.LIVE_PLAYER:
		var held := rig.target as Actor
		if held != null and is_instance_valid(held) and held.is_inside_tree():
			return held
	for node in root.get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor == null or not root.is_ancestor_of(actor):
			continue
		if entry.source == CastEntry.Source.LIVE_PLAYER and actor.def != null and actor.def.team == ActorDef.Team.PLAYER:
			return actor
		if entry.source == CastEntry.Source.LIVE_NAMED and actor.name == entry.node_name:
			return actor
	return null


# Frames a pair has left, as far as the move in it says; 0 when that cannot be known (it is then waited for, and given up after
# PAIR_WAIT).
func _pair_frames_left(actor: Actor) -> int:
	var runner := actor.runner
	if runner.current == null or not actor.rig.tree.has_animation(runner.current.clip):
		return 0
	return maxi(ceili((actor.rig.tree.get_animation(runner.current.clip).length - runner.time) * 60.0), 0)


# --- the cast, the marks and the timeline ---

# Who is in the scene: the live actors found, the dropped optional ones left out. The spawns are made when it starts.
func _resolve_cast() -> void:
	for entry in scene.cast:
		if entry.source == CastEntry.Source.SPAWN:
			continue
		var found := _find_live(entry, _rig)
		if found == null or found.dead:
			_dropped[entry.actor] = true
		else:
			cast[entry.actor] = found


# The timeline's player, in a Cutscene root added in the world (which stops when the game is paused), with this node in it as
# `Director`.
func _build_timeline() -> bool:
	var player := TimelineBuilder.player_for(scene)
	if player == null:
		return false
	_player = player
	_root = player.get_parent()
	_camera = _root.get_node(NodePath(TimelineBuilder.CAMERA)) as CineCamera
	name = TimelineBuilder.CUE_NODE
	process_physics_priority = -10
	player.process_physics_priority = -20
	_root.add_child(self)
	_camera.scene = scene
	_camera.world = _where
	_camera.rig = _rig
	_camera.hud = _hud
	_world_root.add_child(_root)
	return true


# Where a name is, as CinePose.solve asks: a cast member's feet, a mark, `name@start`; null for anything else.
func _where(target: StringName) -> Variant:
	if _skipping and _frozen_world.has(target):
		return _frozen_world[target]
	var text := String(target)
	if text.ends_with("@start"):
		return _place_at_start(StringName(text.trim_suffix("@start")))
	var actor := cast.get(target) as Actor
	if actor != null and is_instance_valid(actor) and actor.is_inside_tree():
		return actor.global_position
	return _mark_place(target)


# Where a mark is in the region; null for a name that is not a mark (or a place that is not known yet).
func _mark_place(mark_name: StringName) -> Variant:
	if _marks.has(mark_name):
		return _marks[mark_name]
	var mark := scene.mark(mark_name)
	if mark == null or String(mark.name).begins_with(ShotChecker.REHEARSAL):
		return null
	var at: Variant = null
	if mark.space == SceneMark.Space.REGION:
		at = mark.position
	elif mark.space == SceneMark.Space.ACTOR_START:
		var origin: Variant = _start_transform(mark.actor)
		if origin is Transform3D:
			at = (origin as Transform3D) * mark.position
	if at is Vector3:
		_marks[mark_name] = at
	return at


# Where a cast name, or a mark, stood when the scene began; null if it is not known.
func _place_at_start(target: StringName) -> Variant:
	var start: Variant = _start_transform(target)
	if start is Transform3D:
		return (start as Transform3D).origin
	return _mark_place(target)


# The transform a cast member had when the scene began: a live actor's own (written down when the scene starts), or a spawned
# one's mark, turned toward the first thing it is to walk to or face when the mark names no turn of its own.
func _start_transform(actor_name: StringName) -> Variant:
	if _starts.has(actor_name):
		return _starts[actor_name]
	var entry := scene.cast_entry(actor_name)
	if entry == null or _dropped.has(actor_name):
		return null
	if entry.source != CastEntry.Source.SPAWN:
		var live := cast.get(actor_name) as Actor
		return live.global_transform if live != null else null
	var mark := scene.mark(entry.spawn_mark)
	if mark == null:
		return null
	var at: Vector3 = mark.position
	var yaw := deg_to_rad(mark.yaw_deg)
	if mark.space == SceneMark.Space.ACTOR_START:
		var base: Variant = _start_transform(mark.actor) if mark.actor != actor_name else null
		if not base is Transform3D:
			return null
		at = (base as Transform3D) * mark.position
		yaw += (base as Transform3D).basis.get_euler().y
	if mark.yaw_deg == 0.0:
		var to: Variant = _first_target_place(actor_name)
		if to is Vector3 and Vector2((to as Vector3).x - at.x, (to as Vector3).z - at.z).length() > 0.01:
			yaw = Locomotion.yaw_of(Vector2((to as Vector3).x - at.x, (to as Vector3).z - at.z))
	var transform := Transform3D(Basis(Vector3.UP, yaw), at)
	_starts[actor_name] = transform
	return transform


# Where the first thing an actor is to walk to or face is, if that is a mark (or another actor's start).
func _first_target_place(actor_name: StringName) -> Variant:
	for shot in scene.shots:
		for beat in shot.beats:
			if beat.actor != actor_name:
				continue
			var target := beat.move_to if beat.move_to != &"" else beat.face
			if target == &"":
				continue
			if scene.cast_entry(target) != null:
				return null if target == actor_name else _place_at_start(target)
			return _mark_place(target)
	return null


# --- waiting, and starting ---

func _wait() -> void:
	if _settled():
		_start_scene()
		_play_frame()
	elif _waited < START_WAIT:
		_waited += 1
	elif _paired():
		if _waited < PAIR_WAIT:
			_waited += 1
		else:
			_give_up(&"cast_busy")
	else:
		_start_scene()
		_play_frame()


# Whether nothing the scene must not cut is going on: no live actor of the cast frozen, no slow-down, every live actor on the
# floor and out of a pair, and at rest unless in a move (the scene stops that).
func _settled() -> bool:
	if Melee.slowed():
		return false
	for key: Variant in cast.values():
		if not is_instance_valid(key):
			continue
		var actor := key as Actor
		if actor.frozen > 0 or actor.paired_with != null or not actor.is_on_floor():
			return false
		if not actor.runner.busy() and actor.locomotion.speed > 0.0:
			return false
	return true


func _paired() -> bool:
	for key: Variant in cast.values():
		if is_instance_valid(key) and (key as Actor).paired_with != null:
			return true
	return false


# The scene is given up while it waits: nothing has been changed, so nothing is given back.
func _give_up(reason: StringName) -> void:
	last_refusal = reason
	phase = Phase.DONE
	if _current == self:
		_current = null
	refused.emit(reason)
	_root.queue_free()


# The clock starts: the fight is taken as it is, the cast is given its brains, the spawns are made, the overlay and the Hud
# and the game state take their scene form, and the timeline plays.
func _start_scene() -> void:
	_take_the_live_actors()
	_make_the_spawns()
	_stand_the_world_down()
	_overlay = CineOverlay.new()
	var holder := _hud.get_parent()
	holder.add_child(_overlay)
	var menu := holder.get_node_or_null("Menu")
	if menu != null:
		holder.move_child(_overlay, menu.get_index())  # under the pause menu, never over it
	_camera.overlay = _overlay
	_hud.suppressed = true
	if Game.state == Game.State.PLAY:
		Game.change(Game.State.CUTSCENE)
	_return_frames = TimelineBuilder.return_frames(scene, _where)
	frame = 0
	phase = Phase.LEAD_IN
	_player.play(TimelineBuilder.animation_of(_player))
	started.emit(scene.id)


# Each live actor of the cast: what it was in the middle of is over, its blows with it; what it had pressed is forgotten; its
# bars and clocks are written down to be given back; its brain is the scene's.
func _take_the_live_actors() -> void:
	for entry in scene.cast:
		var actor := cast.get(entry.actor) as Actor
		if actor == null or entry.source == CastEntry.Source.SPAWN:
			continue
		_starts[entry.actor] = actor.global_transform
		actor.runner.stop(0.1)
		actor.buffer.clear()
		actor.frozen = 0
		AttackTokens.give_back_for(actor)
		_was_guarding[actor] = actor.guarding
		_bars[actor] = actor.stats.save()
		_old_brains[actor] = actor.brain
		var brain := DirectorBrain.new()
		_brains[actor] = brain
		actor.set_brain(brain)


# Makes the spawned actors, each with its DirectorBrain before it is in the tree (so the def's own brain never thinks).
func _make_the_spawns() -> void:
	for entry in scene.cast:
		if entry.source != CastEntry.Source.SPAWN:
			continue
		var start: Variant = _start_transform(entry.actor)
		if not start is Transform3D:
			_dropped[entry.actor] = true
			continue
		var actor := (load(ACTOR_SCENE) as PackedScene).instantiate() as Actor
		actor.name = String(entry.actor).capitalize().replace(" ", "")
		actor.def = entry.def
		actor.spawn_count = _spawned.get(actor.name, 0)
		_spawned[actor.name] = actor.spawn_count + 1
		var brain := DirectorBrain.new()
		actor.set_brain(brain)
		actor.position = (start as Transform3D).origin
		_region.add_child(actor)
		actor.place(start)
		cast[entry.actor] = actor
		_brains[actor] = brain


# The foes that are not in the scene stand still for it: a swing they were in the middle of is stopped, what they were planning
# is dropped, and their minds are quiet until control is back.
func _stand_the_world_down() -> void:
	for actor in _outsiders():
		if actor.runner.busy() and actor.runner.current.kind != MoveData.Kind.REACTION:
			actor.runner.stop(0.1)
			_settling[actor] = frame + SETTLE_FRAMES
		AttackTokens.give_back_for(actor)
		if actor.brain is EnemyBrain:
			(actor.brain as EnemyBrain).stand_down_for_scene(actor)
		_held_brains[actor] = actor.brain
		actor.set_brain(Brain.new())


# The living actors of the world that are not in the cast.
func _outsiders() -> Array[Actor]:
	var out: Array[Actor] = []
	var members := cast.values()
	for node in get_tree().get_nodes_in_group(Actor.GROUP):
		var actor := node as Actor
		if actor != null and not actor.dead and _world_root.is_ancestor_of(actor) and not members.has(actor):
			out.append(actor)
	return out


# --- the scene's frames ---

func _play_frame() -> void:
	var now := frame
	if phase == Phase.LEAD_IN and now >= scene.lead_in:
		phase = Phase.PLAY
	if phase == Phase.PLAY and now >= scene.lead_in + scene.length():
		_hand_back(_return_frames)
		_lead_out_frame()
		return
	_rig.cine_weight = clampf(float(now) / float(maxi(scene.lead_in, 1)), 0.0, 1.0)
	_hold_the_world(now)
	_steer_the_cast()
	_drive_the_clips(now)
	frame += 1


func _hold_the_world(now: int) -> void:
	for actor in _outsiders():
		if _settling.has(actor) and now < _settling[actor]:
			continue
		actor.freeze(2)


# What the cast looks at and faces follows its target as the target moves.
func _steer_the_cast() -> void:
	for key: Variant in _brains:
		if not is_instance_valid(key):
			continue
		var brain := _brains[key] as DirectorBrain
		if _face_at.has(key):
			brain.face = _where(_face_at[key])
		if _look_at.has(key):
			brain.look = _look_point(_look_at[key])


func _look_point(target: StringName) -> Variant:
	var actor := cast.get(target) as Actor
	if actor != null and is_instance_valid(actor):
		return actor.head_point()
	var at: Variant = _where(target)
	return (at as Vector3) + Vector3.UP * LOOK_HEIGHT if at is Vector3 else null


# Each clip the timeline has begun is shown at its own time, before the actors tick (the rig is ticked in the actor's frame).
func _drive_the_clips(now: int) -> void:
	for key: Variant in _clips.keys():
		if not is_instance_valid(key):
			_clips.erase(key)
			continue
		var actor := key as Actor
		var clip: Dictionary = _clips[key]
		if clip.until >= 0 and now > clip.until:
			_clips.erase(key)
			continue
		var seconds := float(now - clip.from) / 60.0
		if clip.loop:
			seconds = fposmod(seconds, maxf(clip.length, 0.001))
		actor.rig.set_move_time(minf(seconds, clip.length))


# --- the timeline's calls ---

func _cue(kind: StringName, payload: Dictionary) -> void:
	match kind:
		&"beat":
			_beat(payload)
		&"line":
			_line(payload)
		&"sound":
			Sfx.play(payload.id, _point_of(payload.at_ref), 1.0)
		&"music":
			music_cue.emit(payload.id)
		&"end":
			_end_clips()


func _beat(payload: Dictionary) -> void:
	var actor := cast.get(payload.actor) as Actor
	if actor == null or not is_instance_valid(actor) or not _brains.has(actor):
		return  # a dropped actor's beats are dropped with it
	var brain := _brains[actor] as DirectorBrain
	if payload.clip != &"":
		_play_clip(actor, payload)
	if payload.move_to != &"":
		_walk(actor, brain, payload)
	if payload.face != &"":
		_face_at[actor] = payload.face
		brain.face = _where(payload.face)
	if payload.look != &"":
		_look_at[actor] = payload.look
		brain.look = _look_point(payload.look)


# A clip is laid over the actor's rig and shown at the time the timeline gives it: no move runs, so no mark of the clip fires.
func _play_clip(actor: Actor, payload: Dictionary) -> void:
	var clip: StringName = payload.clip
	if not actor.rig.tree.has_animation(clip):
		return  # a placeholder: the actor holds his stance
	actor.rig.play_move(clip, payload.blend)
	_clips[actor] = {clip = clip, loop = payload.loop, from = frame, length = actor.rig.tree.get_animation(clip).length, until = -1}


# A walk begins: from where the body is, to the mark, at the gait's push, let go where StoryWalk says it will come to rest on it.
func _walk(actor: Actor, brain: DirectorBrain, payload: Dictionary) -> void:
	var to: Variant = _where(payload.move_to)
	if not to is Vector3:
		return
	var metres := Vector2((to as Vector3).x - actor.global_position.x, (to as Vector3).z - actor.global_position.z).length()
	var pace: ActorBeat.Pace = payload.pace
	var release := StoryWalk.release_distance(actor.def.locomotion, pace, metres)
	brain.walk_to(to, StoryWalk.push_of(pace), release)


func _line(payload: Dictionary) -> void:
	var speaker := Registry.fetch(&"speakers", payload.speaker) as Speaker
	_overlay.show_line(speaker, payload.text, payload.expr, payload.hold)
	line_shown.emit(payload.speaker, payload.text)


# Where a sound is heard: a cast member's chest, a mark; null for anywhere (not placed in the world).
func _point_of(target: StringName) -> Variant:
	if target == &"":
		return null
	var actor := cast.get(target) as Actor
	if actor != null and is_instance_valid(actor):
		return actor.chest_point()
	return _where(target)


# The last shot is ending: every clip fades back to locomotion over RETURN_BLEND frames, still shown at its own time while it does.
func _end_clips() -> void:
	for key: Variant in cast.values():
		if is_instance_valid(key):
			(key as Actor).rig.stop_move(float(RETURN_BLEND) / 60.0)
	for key: Variant in _clips:
		_clips[key].until = frame + RETURN_BLEND


# --- handing back ---

# Control comes back at once: the old brains, the spawns' `after`, the state, the Hud; and the camera begins its glide home.
func _hand_back(glide_frames: int) -> void:
	_lead_out_at = frame
	_lead_out_length = maxi(glide_frames, 1)
	if not _skipping:
		_weight_from = 1.0
		_bars_from = _camera.letterbox
	_clips.clear()
	phase = Phase.LEAD_OUT
	_give_back_control()
	_hud.suppressed = false
	_set_up_the_after()


# The part of the hand-back that is the fight's again.
func _give_back_control() -> void:
	_handed_back = true
	for key: Variant in _old_brains:
		if is_instance_valid(key):
			var actor := key as Actor
			actor.set_brain(_old_brains[key])
			actor.stats.restore(_bars[key])
	for key: Variant in _held_brains:
		if is_instance_valid(key):
			var actor := key as Actor
			actor.set_brain(_held_brains[key])
			if actor.brain is EnemyBrain:
				(actor.brain as EnemyBrain).rest_for(float(REST_FRAMES) / 60.0)
	if Game.state == Game.State.CUTSCENE:
		Game.change(Game.State.PLAY)
	Inputs.quarantine()


# What each spawned actor is left as: KEEP stands there with no brain, FREE goes once the camera is home, ENEMY_BRAIN fights.
func _set_up_the_after() -> void:
	for entry in scene.cast:
		var actor := cast.get(entry.actor) as Actor
		if actor == null or entry.source != CastEntry.Source.SPAWN or not is_instance_valid(actor):
			continue
		if entry.after == CastEntry.After.ENEMY_BRAIN and actor.def.brain != null:
			actor.set_brain(EnemyBrain.new(actor.def.brain, hash("%s#%d" % [actor.name, actor.spawn_count])))
		else:
			actor.set_brain(Brain.new())


func _lead_out_frame() -> void:
	var n := frame - _lead_out_at
	var t := clampf(float(n) / float(_lead_out_length), 0.0, 1.0)
	_rig.cine_weight = _weight_from * (1.0 - t)
	if _skipping:
		_camera.letterbox = _bars_from * (1.0 - t)
	frame += 1
	if n >= _lead_out_length:
		_finish()


func _finish() -> void:
	_rig.cine_weight = 0.0
	phase = Phase.DONE
	for entry in scene.cast:
		var actor := cast.get(entry.actor) as Actor
		if actor != null and is_instance_valid(actor) and entry.source == CastEntry.Source.SPAWN and entry.after == CastEntry.After.FREE:
			actor.get_parent().remove_child(actor)
			actor.queue_free()
	StoryLog.mark_seen(scene.id)
	if _current == self:
		_current = null
	_camera.release()
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_root.queue_free()
	finished.emit(_skipping)


# --- skipping ---

# Where every name the camera may look at is now: the picture holds still while the cast is put where the scene leaves it.
func _snapshot_world() -> Dictionary:
	var out := {}
	for entry in scene.cast:
		var at: Variant = _where(entry.actor)
		if at is Vector3:
			out[entry.actor] = at
	for mark in scene.marks:
		var at: Variant = _where(mark.name)
		if at is Vector3:
			out[mark.name] = at
	return out


# The cast stands where the scene leaves it: at the mark of its last walk, facing what it last faced (or the way it last
# walked); a live actor with no walk keeps its place.
func _place_the_cast() -> void:
	for entry in scene.cast:
		var actor := cast.get(entry.actor) as Actor
		if actor == null or not is_instance_valid(actor):
			continue
		actor.runner.stop(0.1)
		actor.place(_final_place(entry.actor, actor))
		actor.rig.stop_move(0.1)


# The transform the scene leaves `actor_name` in.
func _final_place(actor_name: StringName, actor: Actor) -> Transform3D:
	var at := actor.global_position
	var yaw := actor.rotation.y
	var walked := false
	var facing: StringName = &""
	var way := Vector2.ZERO
	var from := at
	for shot in scene.shots:
		for beat in shot.beats:
			if beat.actor != actor_name:
				continue
			if beat.move_to != &"":
				var to: Variant = _where(beat.move_to)
				if to is Vector3:
					way = Vector2((to as Vector3).x - from.x, (to as Vector3).z - from.z)
					from = to
					walked = true
			if beat.face != &"":
				facing = beat.face
	if walked:
		at = from
	if facing != &"":
		var target: Variant = _where(facing)
		if target is Vector3 and Vector2((target as Vector3).x - at.x, (target as Vector3).z - at.z).length() > 0.01:
			yaw = Locomotion.yaw_of(Vector2((target as Vector3).x - at.x, (target as Vector3).z - at.z))
	elif way.length() > 0.01:
		yaw = Locomotion.yaw_of(way)
	return Transform3D(Basis(Vector3.UP, yaw), at)
