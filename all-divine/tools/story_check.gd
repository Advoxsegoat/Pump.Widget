extends SceneTree
## The shot checker on the command line:
##   tools/godot.sh -s res://tools/story_check.gd [--final] [--scene=<id>] [-- <file.tres> ...]
## Checks every scene folder under res://scenes/story, or the one named (`--scene=<id>`), or the shots.tres files named
## after the `--` (Godot takes a bare .tres on its command line for a scene to run, so paths follow `--`; a path is
## res://..., user://..., absolute, or relative to the project). `--scene` and paths do not go together (usage, exit 2).
## Each scene's rules are ShotChecker's; each is also checked in its place (the region loaded here, `region` of the
## scene, or the training yard when it names none: the floor under every mark, room for a body, a body able to walk to
## it from the region's Spawn, the walks' lines clear). Prints each problem as
## "story_check: <scene>/<shot or ->: <problem>" and exits 1; otherwise prints "story_check: N scenes OK (P placeholders)"
## and exits 0. A placeholder (a beat marked `placeholder` whose clip is not made yet) is listed but is not a problem in a
## draft; it is one in an approved scene, or with --final. Exits 2 for a wrong command line. The options may stand
## before or after `--`. OK is printed only for a scene the checker finished (StoryCheckJob); and if this tool itself hit
## a script error, it says so and exits 3: it never exits 0 after one.
## Run `tools/godot.sh --import` first when classes or data have been added.
##
## A script run with -s is compiled before the autoloads are known as names, and the checker reads the Registry
## autoload; so the checker is loaded at run time (not named in this file) and the Registry is fetched from the tree.
## The Registry has not run its own scan by then, so this scans it. Every function here enters by `_enter` and leaves by
## `_leave` (CheckTrace), and has no static function or lambda: tests/story/test_shot_checker_trace.gd reads this file.

const CHECKER := "res://story/shot_checker.gd"
const JOB := "res://story/story_check_job.gd"
const SCENES := "res://scenes/story"
## The place of a scene that names no region: the game starts in the yard.
const DEFAULT_REGION := "res://world/training_yard/training_yard.tscn"
const SCRIPT := "res://tools/story_check.gd"
const USAGE := "usage: tools/godot.sh -s res://tools/story_check.gd [--final] [--scene=<id>] [-- <file.tres> ...]"

var _t := CheckTrace.new()


func _initialize() -> void:
	var done: Variant = await _run(_own_args())
	if done is Dictionary and done.has("code"):
		quit(done.code)
	else:
		printerr("story_check: the tool stopped before it finished (a script error; see the engine's lines above)")
		quit(3)


func _enter(function: StringName) -> void:
	_t.enter(function)


func _leave(function: StringName, value: Variant = null) -> Variant:
	return _t.leave(function, value)


# The arguments that are the tool's: those after its own name on Godot's command line, and those after `--`.
func _own_args() -> PackedStringArray:
	_enter(&"_own_args")
	var mine := PackedStringArray()
	var all := OS.get_cmdline_args()
	var at := all.find(SCRIPT)
	if at >= 0:
		mine.append_array(all.slice(at + 1))
	mine.append_array(OS.get_cmdline_user_args())
	return _leave(&"_own_args", mine)


# {code} when the run reached its end; anything else means the tool itself stopped.
func _run(args: PackedStringArray) -> Dictionary:
	_enter(&"_run")
	var only := ""
	var final := false
	var files := PackedStringArray()
	for arg in args:
		if arg.begins_with("--scene="):
			only = arg.trim_prefix("--scene=")
		elif arg == "--final":
			final = true
		elif arg == "--":
			continue
		elif arg.begins_with("-"):
			printerr("story_check: unknown argument '%s'" % arg)
			printerr(USAGE)
			return _leave(&"_run", {code = 2})
		else:
			files.append(arg)
	if only != "" and not files.is_empty():
		printerr("story_check: --scene and file paths do not go together")
		printerr(USAGE)
		return _leave(&"_run", {code = 2})
	var registry := root.get_node("Registry")
	var problems := PackedStringArray()
	for problem: String in registry.scan():
		problems.append("registry: " + problem)
	var checker: RefCounted = (load(CHECKER) as GDScript).new()
	var job: RefCounted = (load(JOB) as GDScript).new()
	# What to check: {lines (problems of the data), scene (null if it did not load: the file is read once)}.
	var jobs: Array[Dictionary] = []
	if files.is_empty():
		var folders: PackedStringArray = checker.scene_folders(SCENES)
		if only != "":
			if not folders.has(only):
				printerr("story_check: no scene folder '%s' under %s (there are: %s)" % [only, SCENES, ", ".join(folders)])
				return _leave(&"_run", {code = 1})
			folders = PackedStringArray([only])
		for folder in folders:
			var lines: PackedStringArray = job.folder_lines(checker, SCENES.path_join(folder))
			jobs.append({lines = lines, scene = checker.loaded_scene})
	else:
		for file in files:
			var path := file if file.begins_with("res://") or file.begins_with("user://") or file.begins_with("/") else "res://" + file
			var lines: PackedStringArray = job.file_lines(checker, path)
			jobs.append({lines = lines, scene = checker.loaded_scene})
	var regions := {}   # region path -> the instanced region, kept for the place checks
	var placeholders := PackedStringArray()
	for each in jobs:
		var lines: PackedStringArray = each.lines
		if each.scene != null:
			lines.append_array(await _place_lines(job, checker, each.scene, regions))
		for line in lines:
			if checker.is_placeholder(line) and not final:
				placeholders.append(line)
			else:
				problems.append(line)
	for region: Node in regions.values():
		region.queue_free()
	for line in placeholders:
		print("story_check: " + line)
	var stopped := _t.stopped_in(&"_run", 0)
	if stopped != "":
		problems.append("the tool stopped before it finished: in %s (a script error; see the engine's lines above)" % stopped)
	if not problems.is_empty():
		for problem in problems:
			printerr("story_check: " + problem)
		return _leave(&"_run", {code = 1})
	print("story_check: %d scenes OK (%d placeholders)" % [jobs.size(), placeholders.size()])
	return _leave(&"_run", {code = 0})


# The place check of one scene: its region instanced in the tree (once per region) and a physics frame waited for.
func _place_lines(job: RefCounted, checker: RefCounted, scene: Resource, regions: Dictionary) -> PackedStringArray:
	_enter(&"_place_lines")
	var path: String = scene.get("region")
	if path == "":
		path = DEFAULT_REGION
	if not regions.has(path):
		var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
		if packed == null:
			return _leave(&"_place_lines", PackedStringArray())   # a region that does not exist is the checker's own line
		var region := packed.instantiate() as Node3D
		root.add_child(region)
		regions[path] = region
		await physics_frame
		await physics_frame
	var region: Node3D = regions[path]
	var marker := region.get_node_or_null("Spawn") as Node3D
	return _leave(&"_place_lines", job.place_lines(checker, scene, region.get_world_3d().direct_space_state, marker.global_position if marker != null else null))
