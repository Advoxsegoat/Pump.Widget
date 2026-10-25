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

const _SECTION_KEYS: PackedStringArray = ["source", "clip", "loop", "length", "step_fps", "ground_speed_from"]


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


## Builds the animation library.
##
## `cfg_path` is the clip list (assets/anim/clips.cfg): one section per clip, named as the clip will
## be, with `source` (a key of `sources`) and `clip` (its name there) and optionally
##   loop=true            LOOP_LINEAR (otherwise the clip plays once)
##   length=<seconds>     retime to this length
##   step_fps=<int>       played stepped at this rate; 0 or absent means smooth
##   ground_speed_from=<source key>   measure the clip's ground speed on the clip of the same name there
## `sources` maps each source key to a glTF/GLB file. The bone names and the hip height come from the
## model at `model_path`; each source's clips are scaled by the model's hip height over the source
## skeleton's (see the top of this file), also where `ground_speed_from` measures them. Writes <out_dir>/<name>.tres for every section and <out_dir>/library.tres, and puts
## the metadata `step_fps` (int) on every clip and `ground_speed` (m/s) where asked for.
##
## If a clip's file already exists, its non-bone tracks (the marks) are merged into the new clip.
## Nothing is written unless every clip could be built. Returns OK, or the error it raised.
static func build(cfg_path: String, sources: Dictionary, out_dir: String, model_path: String) -> Error:
	var cfg := ConfigFile.new()
	var err := cfg.load(cfg_path)
	if err != OK:
		push_error("ClipBuilder: cannot read '%s': %s" % [cfg_path, error_string(err)])
		return err
	var model := load(model_path) as PackedScene
	if model == null:
		push_error("ClipBuilder: cannot load the model '%s'" % model_path)
		return ERR_FILE_NOT_FOUND
	var skel := skeleton_path(model)
	var abarax := _inspect(model, skel)
	if abarax["bones"].is_empty() or float(abarax["hip_height"]) <= 0.0:
		push_error("ClipBuilder: '%s' has no skeleton with a pelvis" % model_path)
		return ERR_INVALID_DATA

	var packs := {}  # source key -> what load_gltf returned, each source read once
	var built := {}  # clip name -> Animation
	for section in cfg.get_sections():
		var problem := _check_section(cfg, section)
		if problem != "":
			push_error("ClipBuilder: %s: %s" % [cfg_path, problem])
			return ERR_INVALID_DATA
		var source := str(cfg.get_value(section, "source"))
		var clip_name := str(cfg.get_value(section, "clip"))
		var length := float(cfg.get_value(section, "length", 0.0))
		var anim := _abarax_clip(packs, sources, source, clip_name, skel, abarax, length)
		if anim == null:
			return ERR_INVALID_DATA
		anim.loop_mode = Animation.LOOP_LINEAR if bool(cfg.get_value(section, "loop", false)) else Animation.LOOP_NONE
		anim.set_meta("step_fps", int(cfg.get_value(section, "step_fps", 0)))
		if cfg.has_section_key(section, "ground_speed_from"):
			var measured := _abarax_clip(packs, sources, str(cfg.get_value(section, "ground_speed_from")), clip_name, skel, abarax, length)
			if measured == null:
				return ERR_INVALID_DATA
			var speed := ground_speed(measured, skel)
			if speed <= 0.0:
				push_error("ClipBuilder: [%s]: '%s' does not travel, so it has no ground speed" % [section, clip_name])
				return ERR_INVALID_DATA
			anim.set_meta("ground_speed", String.num(speed, GROUND_SPEED_DECIMALS).to_float())
		var file := _clip_file(out_dir, section)
		if FileAccess.file_exists(file):
			var old := ResourceLoader.load(file, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
			if old == null:
				push_error("ClipBuilder: cannot read the existing clip '%s'" % file)
				return ERR_FILE_CORRUPT
			merge_kept_tracks(anim, old)
		built[section] = anim

	err = DirAccess.make_dir_recursive_absolute(out_dir)
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

# A clip with nothing in it but the properties of `anim` (length, loop mode, step, metadata).
static func _empty_like(anim: Animation) -> Animation:
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	out.step = anim.step
	for key in anim.get_meta_list():
		out.set_meta(key, anim.get_meta(key))
	return out


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
# ratio, then retimed if `length` is above 0. `abarax` is what _inspect returned. Raises an error and
# returns null if the source has no such clip or no pelvis.
static func _abarax_clip(packs: Dictionary, sources: Dictionary, key: String, clip_name: String, skel: NodePath,
		abarax: Dictionary, length: float) -> Animation:
	var clip := _clip(packs, sources, key, clip_name)
	if clip == null:
		return null
	var ratio := _hip_ratio(packs, key, abarax["hip_height"])
	if ratio <= 0.0:
		return null
	var out := rewrite_paths(clip, skel, abarax["bones"], ratio)
	return retime(out, length) if length > 0.0 else out


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


# `target_hip` over the hip height of the skeleton in the source `key`, which must have been read.
# Raises an error and returns 0 if that skeleton has no pelvis.
static func _hip_ratio(packs: Dictionary, key: String, target_hip: float) -> float:
	var source_hip: float = packs[key]["hip_height"]
	if source_hip <= 0.0:
		push_error("ClipBuilder: the skeleton in source '%s' has no pelvis, so its clips cannot be scaled" % key)
		return 0.0
	return target_hip / source_hip


# The clip called `clip_name` in the source `key`, reading the source file the first time it is asked
# for. Raises an error and returns null if there is no such source or clip.
static func _clip(packs: Dictionary, sources: Dictionary, key: String, clip_name: String) -> Animation:
	if not packs.has(key):
		if not sources.has(key):
			push_error("ClipBuilder: no source '%s' (known: %s)" % [key, ", ".join(PackedStringArray(sources.keys()))])
			return null
		packs[key] = load_gltf(str(sources[key]))
	var clips: Dictionary = packs[key]["clips"]
	if not clips.has(clip_name):
		push_error("ClipBuilder: source '%s' has no clip '%s'" % [key, clip_name])
		return null
	return clips[clip_name]


# What is wrong with a config section, or "" if it is fine.
static func _check_section(cfg: ConfigFile, section: String) -> String:
	if not section.is_valid_filename():
		return "[%s] cannot be a file name" % section
	for key in cfg.get_section_keys(section):
		if not _SECTION_KEYS.has(key):
			return "[%s] has an unknown key '%s'" % [section, key]
	for key in ["source", "clip"]:
		if not cfg.has_section_key(section, key):
			return "[%s] has no '%s'" % [section, key]
	return ""


static func _clip_file(out_dir: String, clip_name: String) -> String:
	return out_dir.path_join(clip_name + ".tres")
