class_name ClipBuilder
extends RefCounted
## Turns the Quaternius clips into Abarax's clips: reads them out of a glTF, points their bone
## tracks at his skeleton, retimes them, measures how fast they travel, and writes them as text
## .tres files plus an AnimationLibrary. tools/anim/build_library.gd is the command-line front end.
##
## Every function here works on data only; nothing is imported into the project and nothing from the
## downloaded packs is run.
##
## A clip's bone tracks end up as "Model/<skeleton path>:<bone>", where Model is the node the rig puts
## Abarax's scene under and the skeleton path is skeleton_path(abarax.glb). Of the three kinds of
## bone track, rotation tracks are kept for every bone; position tracks only for root and pelvis, and
## scale tracks only if they change (ruling R4). The clips were authored on the Quaternius mannequin,
## and another bone's position track would impose that mannequin's bone lengths on Abarax.
##
## The root and pelvis position tracks are also scaled by the hip ratio, Abarax's rest pelvis height over
## the mannequin's (ruling R5). His legs are longer, so the pelvis has to ride higher for his feet to meet
## the ground, and the root's travel (and so every ground speed) grows with his stride.
##
## A clip can be made from more than one of the Quaternius clips, in this order: the clip and the clips
## `then` appended to it are joined end to end (join); the joined clip is then retimed to `length`, or
## time-warped by `warp` (apply_warp); last, a hand-keyed `layer` of bone rotations is laid over it
## (apply_layer). The keys of clips.cfg are listed at build.

## The node the rig puts the model under; the first part of every bone track's path.
const MODEL_NODE := "Model"
## The bones whose position tracks are kept.
const POSITION_BONES: PackedStringArray = ["root", "pelvis"]
## A scale track whose every key is within this of Vector3.ONE is dropped.
const IDENTITY_SCALE_EPSILON := 1e-4
## ground_speed is rounded to this many decimals (m/s) before it is stored.
const GROUND_SPEED_DECIMALS := 3
## The bone whose rest height is the hip height.
const HIP_BONE := "pelvis"
## The marks live on the method track(s) that moves/marks.gd names and knows how to find. By path rather
## than by class name, so the builder also runs before the project has been imported.
const _Marks := preload("res://moves/marks.gd")

## The bone whose position track carries a clip's travel over the ground. A joined clip continues it.
const ROOT_BONE := "root"
## A warped clip, and every layered bone, is written with a key at this rate (Hz): the grid the marks use.
const KEY_RATE := _Marks.RATE
## The rates a clip can be played stepped at (step_fps); 0 is smooth.
const STEP_RATES: PackedInt32Array = [0, 12, 24]
## Frames in a layer are compared to its keys within this.
const FRAME_EPSILON := 1e-4

## The keys a `then` entry written as a dictionary may have besides its clip (see join_parts).
const THEN_KEYS: PackedStringArray = ["from", "to", "fade", "root_from"]
const _SECTION_KEYS: PackedStringArray = ["source", "clip", "loop", "length", "step_fps", "ground_speed_from",
		"then", "warp", "layer"]


## Reads every animation in a glTF/GLB file and returns {name: Animation}; see load_gltf.
static func load_gltf_animations(path: String) -> Dictionary:
	return load_gltf(path)["clips"]


## Reads a glTF/GLB file and returns {"clips": {name: Animation}, "hip_height": float}: its animations,
## and the rest height of the pelvis of its (first) skeleton, 0 if it has none. The file is parsed with
## GLTFDocument and turned into a scene that is thrown away again; it is not imported into the project.
## The tracks are named as the glTF scene names them (e.g. "Armature/Skeleton3D:pelvis").
## If the file cannot be read it raises an error and the clips are empty.
static func load_gltf(path: String) -> Dictionary:
	var pack := {"clips": {}, "hip_height": 0.0}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_file(path, state)
	if err != OK:
		push_error("ClipBuilder: cannot read '%s': %s" % [path, error_string(err)])
		return pack
	var scene := document.generate_scene(state)
	if scene == null:
		push_error("ClipBuilder: '%s' made no scene" % path)
		return pack
	var clips: Dictionary = pack["clips"]
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for clip_name in player.get_animation_list():
			clips[String(clip_name)] = player.get_animation(clip_name)
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		pack["hip_height"] = hip_height(skeletons[0])
	scene.free()
	return pack


## The height of the pelvis in the skeleton's rest pose (in the skeleton's own units), or 0 if it has
## no pelvis. The ratio of two skeletons' hip heights is the scale for position tracks moved from one to
## the other.
static func hip_height(skeleton: Skeleton3D) -> float:
	var hip := skeleton.find_bone(HIP_BONE)
	return 0.0 if hip < 0 else skeleton.get_bone_global_rest(hip).origin.y


## The path from `model`'s root node to its Skeleton3D (the first one, if there are several), or an
## empty NodePath if it has none.
static func skeleton_path(model: PackedScene) -> NodePath:
	var root := model.instantiate()
	var path := NodePath()
	var found := root.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		path = root.get_path_to(found[0])
	root.free()
	return path


## A copy of `anim` for Abarax: its bone tracks (and only those) retargeted to "Model/<skel>:<bone>".
## A track is dropped if it is not a position, rotation or scale track on a bone, if the bone is not
## in `bones`, if it is a position track on a bone other than root and pelvis, or if it is a scale
## track that never leaves Vector3.ONE (see the top of this file). The values of the position tracks that
## stay are multiplied by `hip_ratio`. Length, loop mode and step carry over.
static func rewrite_paths(anim: Animation, skel: NodePath, bones: PackedStringArray, hip_ratio := 1.0) -> Animation:
	var out := _empty_like(anim)
	for i in anim.get_track_count():
		var type := anim.track_get_type(i)
		var path := anim.track_get_path(i)
		if not _is_bone_track(anim, i) or path.get_subname_count() != 1:
			continue
		var bone := String(path.get_subname(0))
		if not bones.has(bone):
			continue
		if type == Animation.TYPE_POSITION_3D and not POSITION_BONES.has(bone):
			continue
		if type == Animation.TYPE_SCALE_3D and _stays_at_identity(anim, i):
			continue
		anim.copy_track(i, out)
		var copy := out.get_track_count() - 1
		out.track_set_path(copy, NodePath("%s/%s:%s" % [MODEL_NODE, skel, bone]))
		out.track_set_imported(copy, false)
		if type == Animation.TYPE_POSITION_3D and hip_ratio != 1.0:
			for k in out.track_get_key_count(copy):
				var position: Vector3 = out.track_get_key_value(copy, k)
				out.track_set_key_value(copy, k, position * hip_ratio)
	return out


## A copy of `anim` that is `length` seconds long, with every key time scaled by length / anim.length.
## Key values are not touched. (Bezier handles are not rescaled; the clips have no bezier tracks.)
static func retime(anim: Animation, length: float) -> Animation:
	var out := _empty_like(anim)
	out.length = length
	for i in anim.get_track_count():
		anim.copy_track(i, out)
	if anim.length <= 0.0 or is_equal_approx(anim.length, length):
		return out
	var factor := length / anim.length
	for t in out.get_track_count():
		var keys := out.track_get_key_count(t)
		# Move the keys the way that never lands one on another that has not moved yet.
		var order := range(keys) if factor < 1.0 else range(keys - 1, -1, -1)
		for k in order:
			out.track_set_key_time(t, k, minf(out.track_get_key_time(t, k) * factor, length))
	return out


## The source time that output time `out_t` plays, by the warp `[out0, src0, out1, src1, ...]`: a line
## through the points, so between two of them the clip plays at a steady speed (faster than normal if the
## source times are closer together than the output times, slower if further apart). A source time that
## repeats is a hold and one that goes back is a reverse. Before the first point it stays at the first source
## time and after the last at the last. An odd last number is ignored; no points give 0.
static func warp_time(warp: PackedFloat32Array, out_t: float) -> float:
	var points := warp.size() >> 1
	if points == 0:
		return 0.0
	if out_t <= warp[0]:
		return warp[1]
	for i in range(1, points):
		var out1 := warp[i * 2]
		if out_t <= out1:
			var out0 := warp[i * 2 - 2]
			var src0 := warp[i * 2 - 1]
			var src1 := warp[i * 2 + 1]
			return src1 if out1 <= out0 else lerpf(src0, src1, (out_t - out0) / (out1 - out0))
	return warp[points * 2 - 1]


## The clips played one after another as one clip. Each starts, track by track, when the one before it
## ends, so the length is the lengths added up; where one ends and the next begins at the same instant,
## the next one's first key is the pose. A track that only some of the clips have holds its first value
## before them and its last value after them.
##
## The root's position track is shifted for each clip after the first, so that the root starts where the
## clips before it left it: a slide that ends 4 m along is followed by a stop that goes on from there, not
## from the origin. (The pelvis is in the root's space, so it moves with the root and is not touched.) Only
## the root's position is carried on, not its turn.
##
## Takes clips as rewrite_paths makes them: only their bone tracks are joined. Length, loop mode, step and
## metadata are the first clip's. The input clips are left alone.
static func join(clips: Array[Animation]) -> Animation:
	if clips.is_empty():
		return Animation.new()
	var out := _empty_like(clips[0])
	var start := 0.0
	for clip in clips:
		for i in clip.get_track_count():
			if not _is_bone_track(clip, i):
				continue
			var type := clip.track_get_type(i)
			var t := out.find_track(clip.track_get_path(i), type)
			if t < 0:
				t = _blank_track_like(clip, i, out)
			var is_root_position := type == Animation.TYPE_POSITION_3D and _bone_of(clip, i) == ROOT_BONE
			var shift := Vector3.ZERO
			if is_root_position and out.track_get_key_count(t) > 0 and clip.track_get_key_count(i) > 0:
				var last: Vector3 = out.track_get_key_value(t, out.track_get_key_count(t) - 1)
				shift = last - (clip.track_get_key_value(i, 0) as Vector3)
			for k in clip.track_get_key_count(i):
				var value: Variant = clip.track_get_key_value(i, k)
				if is_root_position:
					value = (value as Vector3) + shift
				_insert_key(out, t, type, start + clip.track_get_key_time(i, k), value)
		start += clip.length
	out.length = start
	return out


## The clips of `parts` played one after another as one clip, as join does, but each part may be cut and may fade
## in over the end of the one before. A part is {"anim": Animation, "from": seconds, "to": seconds, "fade": seconds}:
## it plays its clip from `from` (default 0) to `to` (default its length), and starts `fade` seconds (default 0) before
## the part before it ends, blending from that part's pose into its own over the overlap (smoothstep: no kink at
## either end). So the length is the parts' spans added up, less the fades. The root goes on unbroken: each part's
## root travel is moved to carry on from where the root is when that part begins, and blends with the part before it
## over the fade; the other bones' poses blend as they are. A cut first part's root starts where its clip's does.
## A part may say which time of its clip lines up with that root instead ("root_from", default `from`): with
## "root_from": 0, the travel of the span cut away is kept, so feet that stand still in the clip while its root moves
## stay where the part before left them as it fades in.
##
## With nothing cut or faded, this is join. Otherwise every bone track is sampled at KEY_RATE (and at the end), since
## a blend has no keys of its own. A bone a part has no track for holds the value of the part before it (or of the
## first part after it that has one). The first part's fade is ignored. The input clips are left alone.
static func join_parts(parts: Array) -> Animation:
	var clips: Array[Animation] = []
	var plain := true
	for i in parts.size():
		var part: Dictionary = parts[i]
		var anim: Animation = part["anim"]
		clips.append(anim)
		if float(part.get("from", 0.0)) > 0.0 or (part.has("to") and float(part["to"]) < anim.length) \
				or (i > 0 and float(part.get("fade", 0.0)) > 0.0) or part.has("root_from"):
			plain = false
	if plain:
		return join(clips)
	var spans: Array[Dictionary] = []  # each part: anim, from, to, fade, start (output time), root offset
	var start := 0.0
	for i in parts.size():
		var part: Dictionary = parts[i]
		var anim: Animation = part["anim"]
		var from := float(part.get("from", 0.0))
		var to := float(part.get("to", anim.length))
		var fade := float(part.get("fade", 0.0)) if i > 0 else 0.0
		var span := {"anim": anim, "from": from, "to": to, "fade": fade, "start": maxf(start - fade, 0.0), "shift": Vector3.ZERO}
		var root_from := float(part.get("root_from", from))
		if i > 0:
			span["shift"] = _root_at(spans, i - 1, span["start"]) - _root_local(anim, root_from)
		else:
			span["shift"] = _root_local(anim, 0.0) - _root_local(anim, from)  # a cut first part starts where its clip does
		spans.append(span)
		start = span["start"] + (to - from)
	var out := _empty_like(clips[0])
	out.length = start
	var times := _frame_times(start)
	var tracks := {}  # [path, type] -> out track
	for anim in clips:
		for i in anim.get_track_count():
			if not _is_bone_track(anim, i):
				continue
			var key := [anim.track_get_path(i), anim.track_get_type(i)]
			if not tracks.has(key):
				tracks[key] = _blank_track_like(anim, i, out)
	for key: Array in tracks:
		var path: NodePath = key[0]
		var type: Animation.TrackType = key[1]
		for time in times:
			_insert_key(out, tracks[key], type, time, _parts_value(spans, path, type, time))
	return out


# The value of the track `path` of `type` at output time `time` of the parts `spans` (see join_parts).
static func _parts_value(spans: Array[Dictionary], path: NodePath, type: Animation.TrackType, time: float) -> Variant:
	var current := 0
	while current + 1 < spans.size() and time >= float(spans[current + 1]["start"]) - FRAME_EPSILON:
		current += 1
	var value: Variant = _span_value(spans, current, path, type, time)
	var span: Dictionary = spans[current]
	var into := time - float(span["start"])
	if current > 0 and float(span["fade"]) > 0.0 and into < float(span["fade"]):
		var weight := smoothstep(0.0, 1.0, into / float(span["fade"]))
		var before: Variant = _span_value(spans, current - 1, path, type, time)
		if type == Animation.TYPE_ROTATION_3D:
			value = (before as Quaternion).slerp(value as Quaternion, weight)
		else:
			value = (before as Vector3).lerp(value as Vector3, weight)
	return value


# The value of the track `path` of `type` in the part `index` of `spans` at output time `time` (held past the ends of
# its span): the root position with the part's shift; a track the part has not, from the nearest part that has it.
static func _span_value(spans: Array[Dictionary], index: int, path: NodePath, type: Animation.TrackType, time: float) -> Variant:
	var order := [index]
	for d in range(1, spans.size()):
		if index - d >= 0:
			order.append(index - d)
		if index + d < spans.size():
			order.append(index + d)
	for i: int in order:
		var span: Dictionary = spans[i]
		var anim: Animation = span["anim"]
		var track := anim.find_track(path, type)
		if track < 0:
			continue
		var local := clampf(float(span["from"]) + time - float(span["start"]), float(span["from"]), float(span["to"]))
		if i < index:
			local = float(span["to"])
		elif i > index:
			local = float(span["from"])
		var value: Variant = _sample(anim, track, local)
		if type == Animation.TYPE_POSITION_3D and _bone_of(anim, track) == ROOT_BONE:
			value = (value as Vector3) + (span["shift"] as Vector3)
		return value
	return Quaternion.IDENTITY if type == Animation.TYPE_ROTATION_3D else (Vector3.ONE if type == Animation.TYPE_SCALE_3D else Vector3.ZERO)


# Where the root is in the part `index` of `spans` at output time `time`, shift and all (see join_parts).
static func _root_at(spans: Array[Dictionary], index: int, time: float) -> Vector3:
	var span: Dictionary = spans[index]
	var local := clampf(float(span["from"]) + time - float(span["start"]), float(span["from"]), float(span["to"]))
	return _root_local(span["anim"], local) + (span["shift"] as Vector3)


# The root bone's position in `anim` at `time`, or zero when it has no root position track.
static func _root_local(anim: Animation, time: float) -> Vector3:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and _is_bone_track(anim, i) and _bone_of(anim, i) == ROOT_BONE:
			return anim.position_track_interpolate(i, time)
	return Vector3.ZERO


## A copy of `anim` played to the time warp `warp` (see warp_time): its length is the last output time, and
## every bone track is sampled at KEY_RATE for it, so the new keys follow the warp however it bends (the
## source's keys are 30 Hz, and a hold or a reverse needs the finer grid). A key is also put at the length,
## when that falls between two frames. The input is left alone.
static func apply_warp(anim: Animation, warp: PackedFloat32Array) -> Animation:
	var out := _empty_like(anim)
	out.length = warp[(warp.size() >> 1) * 2 - 2] if warp.size() >= 2 else 0.0
	var times := _frame_times(out.length)
	for i in anim.get_track_count():
		if not _is_bone_track(anim, i):
			continue
		var type := anim.track_get_type(i)
		var t := _blank_track_like(anim, i, out)
		for time in times:
			_insert_key(out, t, type, time, _sample(anim, i, warp_time(warp, time)))
	return out


## A copy of `anim` with the hand-keyed rotations of `layer` laid over it. `layer` is what a layer file
## holds, {bone: [[frame, x_deg, y_deg, z_deg], ...]}: for each bone, rotations as Euler degrees (in YXZ
## order, in the bone's own space), at frames of KEY_RATE, and linear between one key and the next. Before
## the first key and after the last the layer is no rotation at all. At each frame the layer is multiplied
## on after the clip's own rotation, so it turns the bone from wherever the clip has put it.
##
## A layered bone's rotation track is sampled at KEY_RATE, so the layer lands on its frames however the
## clip's own keys are spaced; every other track is copied as it is. A bone with no rotation track in `anim`
## is left out (check says so). The input is left alone.
static func apply_layer(anim: Animation, layer: Dictionary) -> Animation:
	var out := _empty_like(anim)
	var times := _frame_times(anim.length)
	for i in anim.get_track_count():
		var bone := _bone_of(anim, i)
		if not _is_bone_track(anim, i) or anim.track_get_type(i) != Animation.TYPE_ROTATION_3D or not layer.has(bone):
			anim.copy_track(i, out)
			continue
		var keys: Array = layer[bone]
		var t := _blank_track_like(anim, i, out)
		for time in times:
			var turn := anim.rotation_track_interpolate(i, time) * _layer_rotation(keys, time * KEY_RATE)
			out.rotation_track_insert_key(t, time, turn)
	return out


## Metres per second the clip travels over the ground: the horizontal (XZ) distance between the
## first and the last key of the root bone's position track, divided by the clip's length. Meant for
## the Quaternius root-motion clips, where that track carries the travel. Finds the track whether the
## clip went through rewrite_paths ("Model/<skel>:root") or not ("<skel>:root"). Returns 0 if the clip
## has no such track or does not move.
static func ground_speed(rm_anim: Animation, skel: NodePath) -> float:
	if rm_anim.length <= 0.0:
		return 0.0
	var t := rm_anim.find_track(NodePath("%s/%s:root" % [MODEL_NODE, skel]), Animation.TYPE_POSITION_3D)
	if t < 0:
		t = rm_anim.find_track(NodePath("%s:root" % skel), Animation.TYPE_POSITION_3D)
	if t < 0 or rm_anim.track_get_key_count(t) < 2:
		return 0.0
	var first: Vector3 = rm_anim.track_get_key_value(t, 0)
	var last: Vector3 = rm_anim.track_get_key_value(t, rm_anim.track_get_key_count(t) - 1)
	return Vector2(last.x - first.x, last.z - first.z).length() / rm_anim.length


## Copies every track of `old_anim` that is not a bone track (position, rotation or scale) into
## `new_anim`, the Marks method tracks first (see Marks.TRACK). This is how hand-added tracks survive a rebuild.
static func merge_kept_tracks(new_anim: Animation, old_anim: Animation) -> void:
	for want_marks in [true, false]:
		for i in old_anim.get_track_count():
			if _is_bone_track(old_anim, i):
				continue
			if _Marks.is_marks_track(old_anim, i) == want_marks:
				old_anim.copy_track(i, new_anim)


## Everything wrong with the clip list at `cfg_path`, one line per problem, each starting with the name of
## its section in brackets ("[palm_hook] warp has ..."). Empty means build would accept it. This builds
## every clip in memory, as build does, so it also finds what only shows against the packs and the model: a
## clip that is not in a source, a layer bone that is not a bone of the model, a ground speed that is zero.
## It writes nothing, and (apart from a pack that cannot be read, which load_gltf raises) raises no errors.
static func check(cfg_path: String, sources: Dictionary, model_path: String) -> PackedStringArray:
	return _compile(cfg_path, sources, model_path)["problems"]


## Builds the animation library.
##
## `cfg_path` is the clip list (assets/anim/clips.cfg): one section per clip, named as the clip will
## be, with `source` (a key of `sources`) and `clip` (its name there) and optionally
##   loop=true            LOOP_LINEAR (otherwise the clip plays once)
##   length=<seconds>     retime to this length (not negative; 0 leaves the clip as long as it is)
##   step_fps=<int>       played stepped at this rate: 0 (or absent) for smooth, 12 or 24
##   ground_speed_from=<source key>   measure the clip's ground speed on the clip of the same name there
##   then=["Clip", "source:Clip"]   clips appended end to end after `clip`, each from the section's own
##                        source or, with a "source:" in front, from another (see join). A single
##                        "Clip" instead of a list is the same. Joined before `length` or `warp` apply. An
##                        entry may instead be {"clip": "source:Clip", "from": s, "to": s, "fade": s}: only
##                        that span of the clip, fading in over the end of the clip before (see join_parts);
##                        "root_from": s says which time of the clip its root carries on from
##   warp=[out0, src0, out1, src1, ...]   plays the joined clip along a line through these points: output
##                        time to source time, both in seconds (see warp_time and apply_warp). The first
##                        output time is 0 and they increase; the clip is as long as the last one. It
##                        takes the place of `length`, so the two cannot both be given
##   layer="res://assets/anim/layers/<name>.json"   rotations laid over the bones after all this
##                        (see apply_layer)
## `sources` maps each source key to a glTF/GLB file. The bone names and the hip height come from the
## model at `model_path`; each source's clips are scaled by the model's hip height over the source
## skeleton's (see the top of this file), also where `ground_speed_from` measures them (which follows
## `then` and `warp` too, on the pack it names). Writes <out_dir>/<name>.tres for every section and
## <out_dir>/library.tres, and puts the metadata `step_fps` (int) on every clip and `ground_speed` (m/s)
## where asked for.
##
## If a clip's file already exists, its non-bone tracks (the marks) are merged into the new clip.
## Nothing is written unless every clip could be built: the problems with the list (see check) are each
## raised as an error and the build returns ERR_INVALID_DATA. Returns OK, or the error it raised.
static func build(cfg_path: String, sources: Dictionary, out_dir: String, model_path: String) -> Error:
	var plan := _compile(cfg_path, sources, model_path)
	var problems: PackedStringArray = plan["problems"]
	if not problems.is_empty():
		for problem in problems:
			push_error("ClipBuilder: %s: %s" % [cfg_path, problem])
		return plan["error"]
	var built: Dictionary = plan["clips"]
	for clip_name: String in built:
		var file := _clip_file(out_dir, clip_name)
		if FileAccess.file_exists(file):
			var old := ResourceLoader.load(file, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
			if old == null:
				push_error("ClipBuilder: cannot read the existing clip '%s'" % file)
				return ERR_FILE_CORRUPT
			merge_kept_tracks(built[clip_name], old)

	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK:
		push_error("ClipBuilder: cannot make '%s': %s" % [out_dir, error_string(err)])
		return err
	var library := AnimationLibrary.new()
	for clip_name: String in built:
		var anim: Animation = built[clip_name]
		var file := _clip_file(out_dir, clip_name)
		anim.take_over_path(file)
		err = ResourceSaver.save(anim, file)
		if err != OK:
			push_error("ClipBuilder: cannot write '%s': %s" % [file, error_string(err)])
			return err
		library.add_animation(clip_name, anim)
	err = ResourceSaver.save(library, out_dir.path_join("library.tres"))
	if err != OK:
		push_error("ClipBuilder: cannot write the library: %s" % error_string(err))
	return err


# --- helpers ---

# What one pass over the clip list looks things up in: the sources (each read the first time it is asked
# for), what the model has, and the problems found so far.
class _Env:
	var sources: Dictionary
	var packs := {}  # source key -> what load_gltf returned
	var skel: NodePath
	var bones: PackedStringArray
	var hip_height: float
	var problems := PackedStringArray()


# Builds every clip of the list in memory. Returns {"clips": {name: Animation}, "problems": the lines of
# check, "error": what build returns if there are problems}. The clips are only complete if there are none.
static func _compile(cfg_path: String, sources: Dictionary, model_path: String) -> Dictionary:
	var plan := {"clips": {}, "problems": PackedStringArray(), "error": ERR_INVALID_DATA}
	var problems: PackedStringArray = plan["problems"]
	var cfg := ConfigFile.new()
	var err := cfg.load(cfg_path)
	if err != OK:
		problems.append("cannot read the clip list: %s" % error_string(err))
		plan["error"] = err
		return plan
	var model := load(model_path) as PackedScene
	if model == null:
		problems.append("cannot load the model '%s'" % model_path)
		plan["error"] = ERR_FILE_NOT_FOUND
		return plan
	var env := _Env.new()
	env.sources = sources
	env.skel = skeleton_path(model)
	var abarax := _inspect(model, env.skel)
	env.bones = abarax["bones"]
	env.hip_height = abarax["hip_height"]
	if env.bones.is_empty() or env.hip_height <= 0.0:
		problems.append("the model '%s' has no skeleton with a pelvis" % model_path)
		return plan

	var clips: Dictionary = plan["clips"]
	for section in cfg.get_sections():
		var found := _check_section(cfg, section)
		if not found.is_empty():
			env.problems.append_array(found)
			continue
		var anim := _section_clip(env, cfg, section)
		if anim != null:
			clips[section] = anim
	problems.append_array(env.problems)
	return plan


# The clip of one section, finished (layered, with its loop mode and metadata), or null with the problems
# in `env`. The section has passed _check_section.
static func _section_clip(env: _Env, cfg: ConfigFile, section: String) -> Animation:
	var anim := _assemble(env, cfg, section, str(cfg.get_value(section, "source")))
	if anim == null:
		return null
	if cfg.has_section_key(section, "layer"):
		anim = _layered(env, section, anim, str(cfg.get_value(section, "layer")))
		if anim == null:
			return null
	anim.loop_mode = Animation.LOOP_LINEAR if bool(cfg.get_value(section, "loop", false)) else Animation.LOOP_NONE
	anim.set_meta("step_fps", int(cfg.get_value(section, "step_fps", 0)))
	if cfg.has_section_key(section, "ground_speed_from"):
		var measured := _assemble(env, cfg, section, str(cfg.get_value(section, "ground_speed_from")))
		if measured == null:
			return null
		var speed := ground_speed(measured, env.skel)
		if speed <= 0.0:
			env.problems.append("[%s] '%s' does not travel, so it has no ground speed" % [section, cfg.get_value(section, "clip")])
			return null
		anim.set_meta("ground_speed", String.num(speed, GROUND_SPEED_DECIMALS).to_float())
	return anim


# The clip of a section as Abarax plays it, before its layer: `clip` of the source `key`, the `then` clips
# joined on (those without a source of their own from `key` too), then warped, or retimed to `length`.
# Returns null with the problems in `env` if a clip is missing.
static func _assemble(env: _Env, cfg: ConfigFile, section: String, key: String) -> Animation:
	var pieces: Array[Animation] = []
	var first := _abarax_clip(env, section, key, str(cfg.get_value(section, "clip")))
	if first == null:
		return null
	pieces.append(first)
	var complete := true
	var parts: Array = [{"anim": first}]
	for entry: Dictionary in _then_entries(cfg.get_value(section, "then", PackedStringArray())):
		var named := String(entry["clip"]).split(":", true, 1)
		var piece := _abarax_clip(env, section, named[0] if named.size() == 2 else key, named[named.size() - 1])
		if piece == null:
			complete = false
		else:
			pieces.append(piece)
			var part := entry.duplicate()
			part.erase("clip")
			part["anim"] = piece
			parts.append(part)
	if not complete or not _spans_fit(env, section, parts):
		return null
	var joined := first if pieces.size() == 1 else join_parts(parts)
	if cfg.has_section_key(section, "warp"):
		return apply_warp(joined, _floats(cfg.get_value(section, "warp")))
	var length := float(cfg.get_value(section, "length", 0.0))
	return retime(joined, length) if length > 0.0 else joined


# `anim` with the layer file at `path` laid over it (see apply_layer), or null with the problems in `env`.
static func _layered(env: _Env, section: String, anim: Animation, path: String) -> Animation:
	if not FileAccess.file_exists(path):
		env.problems.append("[%s] the layer file '%s' does not exist" % [section, path])
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		env.problems.append("[%s] '%s' is not JSON (line %d: %s)" % [section, path.get_file(), json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		env.problems.append("[%s] '%s' must be a JSON object of bone: keys" % [section, path.get_file()])
		return null
	var layer: Dictionary = json.data
	var found := PackedStringArray()
	for bone: String in layer:
		var why := _layer_keys_problem(layer[bone])
		if why == "" and not env.bones.has(bone):
			why = "the model has no such bone"
		elif why == "" and anim.find_track(NodePath("%s/%s:%s" % [MODEL_NODE, env.skel, bone]), Animation.TYPE_ROTATION_3D) < 0:
			why = "the clip has no rotation track for it, so there is nothing to lay it on"
		if why != "":
			found.append("[%s] layer '%s', bone '%s': %s" % [section, path.get_file(), bone, why])
	env.problems.append_array(found)
	return apply_layer(anim, layer) if found.is_empty() else null


# What is wrong with the keys of a layer bone ([[frame, x, y, z], ...]), or "".
static func _layer_keys_problem(keys: Variant) -> String:
	if not keys is Array or (keys as Array).is_empty():
		return "it needs a list of [frame, x_deg, y_deg, z_deg] keys"
	var previous := -1.0
	for key: Variant in keys:
		if not key is Array or (key as Array).size() != 4:
			return "a key must be [frame, x_deg, y_deg, z_deg]"
		for number: Variant in key:
			if typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT:
				return "a key must be four numbers"
		if float(key[0]) < 0.0:
			return "frames start at 0"
		if float(key[0]) <= previous:
			return "frames must increase from one key to the next"
		previous = float(key[0])
	return ""


# The rotation of the layer keys at `frame`: the Euler angles between the two keys around it, none before
# the first and after the last.
static func _layer_rotation(keys: Array, frame: float) -> Quaternion:
	if keys.is_empty() or frame < float(keys[0][0]) - FRAME_EPSILON or frame > float(keys[keys.size() - 1][0]) + FRAME_EPSILON:
		return Quaternion.IDENTITY
	var degrees := _key_degrees(keys[keys.size() - 1])
	for i in keys.size() - 1:
		if frame <= float(keys[i + 1][0]) + FRAME_EPSILON:
			var span := float(keys[i + 1][0]) - float(keys[i][0])
			var weight := clampf((frame - float(keys[i][0])) / span, 0.0, 1.0) if span > 0.0 else 1.0
			degrees = _key_degrees(keys[i]).lerp(_key_degrees(keys[i + 1]), weight)
			break
	return Basis.from_euler(degrees * (PI / 180.0), EULER_ORDER_YXZ).get_rotation_quaternion()


# The x, y and z angles of a layer key [frame, x_deg, y_deg, z_deg], in degrees.
static func _key_degrees(key: Array) -> Vector3:
	return Vector3(float(key[1]), float(key[2]), float(key[3]))


# A clip with nothing in it but the properties of `anim` (length, loop mode, step, metadata).
static func _empty_like(anim: Animation) -> Animation:
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	out.step = anim.step
	for key in anim.get_meta_list():
		out.set_meta(key, anim.get_meta(key))
	return out


# A new track in `out` with the type, path and settings of track `track` of `anim`, and no keys. Returns its index.
static func _blank_track_like(anim: Animation, track: int, out: Animation) -> int:
	var t := out.add_track(anim.track_get_type(track))
	out.track_set_path(t, anim.track_get_path(track))
	out.track_set_interpolation_type(t, anim.track_get_interpolation_type(track))
	out.track_set_interpolation_loop_wrap(t, anim.track_get_interpolation_loop_wrap(track))
	out.track_set_enabled(t, anim.track_is_enabled(track))
	out.track_set_imported(t, false)
	return t


# The times of a key every 1/KEY_RATE s from 0 up to the length, and one at the length itself.
static func _frame_times(length: float) -> PackedFloat64Array:
	var times := PackedFloat64Array()
	var frame := 0
	while frame / float(KEY_RATE) < length - FRAME_EPSILON:
		times.append(frame / float(KEY_RATE))
		frame += 1
	times.append(length)
	return times


# What the bone track `track` of `anim` holds at `time`.
static func _sample(anim: Animation, track: int, time: float) -> Variant:
	match anim.track_get_type(track):
		Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return anim.rotation_track_interpolate(track, time)
	return anim.scale_track_interpolate(track, time)


# Puts a key of `value` at `time` on the bone track `track` of `anim`, which is of the kind `type`.
static func _insert_key(anim: Animation, track: int, type: Animation.TrackType, time: float, value: Variant) -> void:
	match type:
		Animation.TYPE_POSITION_3D:
			anim.position_track_insert_key(track, time, value)
		Animation.TYPE_ROTATION_3D:
			anim.rotation_track_insert_key(track, time, value)
		_:
			anim.scale_track_insert_key(track, time, value)


# The bone a track is on (its subname), "" if it is not on one.
static func _bone_of(anim: Animation, track: int) -> String:
	return str(anim.track_get_path(track).get_concatenated_subnames())


# A bone track is a position, rotation or scale track with a subname (the bone): the only tracks
# the builder makes. Anything else in a clip was added by hand.
static func _is_bone_track(anim: Animation, track: int) -> bool:
	var type := anim.track_get_type(track)
	var transform := type == Animation.TYPE_POSITION_3D or type == Animation.TYPE_ROTATION_3D \
		or type == Animation.TYPE_SCALE_3D
	return transform and anim.track_get_path(track).get_subname_count() > 0


static func _stays_at_identity(anim: Animation, track: int) -> bool:
	for k in anim.track_get_key_count(track):
		var scale: Vector3 = anim.track_get_key_value(track, k)
		if absf(scale.x - 1.0) > IDENTITY_SCALE_EPSILON or absf(scale.y - 1.0) > IDENTITY_SCALE_EPSILON \
				or absf(scale.z - 1.0) > IDENTITY_SCALE_EPSILON:
			return false
	return true


# The clip `clip_name` of the source `key` as Abarax plays it: its tracks retargeted and scaled by the hip
# ratio. Raises no error: returns null, with the problem in `env`, if the source has no such clip or no pelvis.
static func _abarax_clip(env: _Env, section: String, key: String, clip_name: String) -> Animation:
	var clip := _clip(env, section, key, clip_name)
	if clip == null:
		return null
	var ratio := _hip_ratio(env, section, key)
	if ratio <= 0.0:
		return null
	return rewrite_paths(clip, env.skel, env.bones, ratio)


# {"bones": the names of the bones of the skeleton at `skel` in `model`, "hip_height": its hip height}.
static func _inspect(model: PackedScene, skel: NodePath) -> Dictionary:
	var info := {"bones": PackedStringArray(), "hip_height": 0.0}
	if skel.is_empty():
		return info
	var root := model.instantiate()
	var skeleton := root.get_node_or_null(skel) as Skeleton3D
	if skeleton != null:
		var names := PackedStringArray()
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
		info["bones"] = names
		info["hip_height"] = hip_height(skeleton)
	root.free()
	return info


# The model's hip height over the hip height of the skeleton in the source `key`, which must have been read.
# Returns 0, with the problem in `env`, if that skeleton has no pelvis.
static func _hip_ratio(env: _Env, section: String, key: String) -> float:
	var source_hip: float = env.packs[key]["hip_height"]
	if source_hip <= 0.0:
		env.problems.append("[%s] the skeleton in source '%s' has no pelvis, so its clips cannot be scaled" % [section, key])
		return 0.0
	return env.hip_height / source_hip


# The clip called `clip_name` in the source `key`, reading the source file the first time it is asked
# for. Returns null, with the problem in `env`, if there is no such source or clip.
static func _clip(env: _Env, section: String, key: String, clip_name: String) -> Animation:
	if not env.packs.has(key):
		if not env.sources.has(key):
			env.problems.append("[%s] no source '%s' (known: %s)" % [section, key, ", ".join(PackedStringArray(env.sources.keys()))])
			return null
		env.packs[key] = load_gltf(str(env.sources[key]))
	var clips: Dictionary = env.packs[key]["clips"]
	if not clips.has(clip_name):
		env.problems.append("[%s] source '%s' has no clip '%s'" % [section, key, clip_name])
		return null
	return clips[clip_name]


# The values of a config key that is a list of strings, or one string (which is a list of one), as a
# PackedStringArray; empty if it is neither.
# Whether the parts of a section's join (as _assemble makes them for join_parts) fit their clips: from and to within
# the clip, and each fade no longer than its part or the part before it. Each that does not is a problem in `env`.
static func _spans_fit(env: _Env, section: String, parts: Array) -> bool:
	var fits := true
	var before := INF
	for part: Dictionary in parts:
		var anim: Animation = part["anim"]
		var from := float(part.get("from", 0.0))
		var to := float(part.get("to", anim.length))
		if to > anim.length + FRAME_EPSILON or from >= to:
			env.problems.append("[%s] then cuts %s s to %s s of a clip %s s long" % [section, from, to, anim.length])
			fits = false
		var fade := float(part.get("fade", 0.0))
		if fade > minf(before, to - from) + FRAME_EPSILON:
			env.problems.append("[%s] then fades in over %s s, longer than the part (%s s) or the one before it (%s s)" % [section, fade, to - from, before])
			fits = false
		before = to - from
	return fits


# The entries of a section's `then` as {"clip": "Clip" or "source:Clip", and the "from", "to" and "fade" an entry
# gives (see join_parts)}: a String entry is just the clip. Entries that are neither are left out (check says so).
static func _then_entries(value: Variant) -> Array:
	var items: Array = [value] if value is String else (Array(value) if value is Array or value is PackedStringArray else [])
	var entries := []
	for item: Variant in items:
		if item is String:
			entries.append({"clip": item})
		elif item is Dictionary and (item as Dictionary).get("clip") is String:
			var entry := {"clip": item["clip"]}
			for key: String in THEN_KEYS:
				if (item as Dictionary).has(key) and _is_number(item[key]):
					entry[key] = float(item[key])
			entries.append(entry)
	return entries


# What is wrong with one entry of a section's `then`, as lines for check. An entry is "Clip", "source:Clip", or
# {"clip": either, "from": s, "to": s, "fade": s} with from and to within the clip (from before to) and a fade no longer
# than this part or the one before it, which only a built clip can say (see _check_then_spans).
static func _check_then_entry(section: String, item: Variant) -> PackedStringArray:
	var found := PackedStringArray()
	var clip: Variant = item
	if item is Dictionary:
		clip = (item as Dictionary).get("clip")
		for key in item:
			if not THEN_KEYS.has(key) and key != "clip":
				found.append("[%s] then entry %s has an unknown key '%s' (it can have clip, %s)" % [section, item, key, ", ".join(THEN_KEYS)])
		for key: String in THEN_KEYS:
			if (item as Dictionary).has(key) and (not _is_number(item[key]) or float(item[key]) < 0.0):
				found.append("[%s] then entry %s: %s must be a number of seconds, 0 or more" % [section, item, key])
		if _is_number(item.get("from", 0.0)) and _is_number(item.get("to", INF)) and float(item.get("from", 0.0)) >= float(item.get("to", INF)):
			found.append("[%s] then entry %s: from must come before to" % [section, item])
	if not clip is String:
		found.append("[%s] then entry %s needs a clip (Clip or source:Clip)" % [section, item])
		return found
	var parts := (clip as String).split(":", true, 1)
	if parts[0] == "" or parts[parts.size() - 1] == "":
		found.append("[%s] then '%s' must be Clip or source:Clip" % [section, clip])
	return found


static func _strings(value: Variant) -> PackedStringArray:
	var list := PackedStringArray()
	if value is String:
		list.append(value)
	elif value is Array or value is PackedStringArray:
		for item: Variant in value:
			if item is String:
				list.append(item)
	return list


# The values of a config key that is a list of numbers, as a PackedFloat32Array; empty if it is not one.
static func _floats(value: Variant) -> PackedFloat32Array:
	var list := PackedFloat32Array()
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array \
			or value is PackedInt32Array or value is PackedInt64Array:
		for item: Variant in value:
			if _is_number(item):
				list.append(item)
	return list


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


# How many items a config value holds if it is a list, -1 if it is not one.
static func _count(value: Variant) -> int:
	return value.size() if value is Array or value is PackedStringArray or value is PackedFloat32Array \
			or value is PackedFloat64Array or value is PackedInt32Array or value is PackedInt64Array else -1


# What is wrong with a config section by itself, as lines for check ("[section] ..."); none if it is fine.
# What can only be found out against the packs and the model is found when the clip is built.
static func _check_section(cfg: ConfigFile, section: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not section.is_valid_filename():
		found.append("[%s] cannot be a file name" % section)
		return found
	for key in cfg.get_section_keys(section):
		if not _SECTION_KEYS.has(key):
			found.append("[%s] has an unknown key '%s'" % [section, key])
	for key in ["source", "clip"]:
		if not cfg.has_section_key(section, key):
			found.append("[%s] has no '%s'" % [section, key])
	if cfg.has_section_key(section, "length"):
		var length: Variant = cfg.get_value(section, "length")
		if not _is_number(length):
			found.append("[%s] length must be a number of seconds, not %s" % [section, length])
		elif float(length) < 0.0:
			found.append("[%s] length is %s: it cannot be negative" % [section, length])
	if cfg.has_section_key(section, "step_fps"):
		var rate: Variant = cfg.get_value(section, "step_fps")
		if not _is_number(rate) or float(rate) != floorf(float(rate)) or not STEP_RATES.has(int(rate)):
			found.append("[%s] step_fps is %s: it must be one of %s" % [section, rate, STEP_RATES])
	if cfg.has_section_key(section, "then"):
		var then: Variant = cfg.get_value(section, "then")
		var items: Array = [then] if then is String else (Array(then) if then is Array or then is PackedStringArray else [])
		if items.is_empty() or items.size() != (1 if then is String else _count(then)):
			found.append("[%s] then must be a clip name or a list of them" % section)
		for item: Variant in items:
			found.append_array(_check_then_entry(section, item))
	if cfg.has_section_key(section, "warp"):
		if cfg.has_section_key(section, "length"):
			found.append("[%s] has both length and warp: the warp sets the length" % section)
		found.append_array(_check_warp(section, cfg.get_value(section, "warp")))
	if cfg.has_section_key(section, "layer"):
		var layer: Variant = cfg.get_value(section, "layer")
		if not layer is String or (layer as String).is_empty():
			found.append("[%s] layer must be the path of a layer file" % section)
	return found


# What is wrong with a warp, as at most one line for check.
static func _check_warp(section: String, warp: Variant) -> PackedStringArray:
	var found := PackedStringArray()
	var numbers := _floats(warp)
	if numbers.size() != _count(warp):
		found.append("[%s] warp must be a list of numbers" % section)
	elif numbers.size() % 2 != 0:
		found.append("[%s] warp has %d numbers: it needs pairs of output time and source time" % [section, numbers.size()])
	elif numbers.size() < 4:
		found.append("[%s] warp needs at least two points (output time and source time each)" % section)
	elif not is_zero_approx(numbers[0]):
		found.append("[%s] warp must start at 0 s of output time, not %s" % [section, numbers[0]])
	else:
		for i in range(2, numbers.size(), 2):
			if numbers[i] <= numbers[i - 2]:
				found.append("[%s] warp output times must increase, but %s does not come after %s" % [section, numbers[i], numbers[i - 2]])
				return found
		for i in range(1, numbers.size(), 2):
			if numbers[i] < 0.0:
				found.append("[%s] warp source times cannot be negative (%s)" % [section, numbers[i]])
				return found
	return found


static func _clip_file(out_dir: String, clip_name: String) -> String:
	return out_dir.path_join(clip_name + ".tres")
