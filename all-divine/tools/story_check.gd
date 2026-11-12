extends SceneTree
## The shot checker on the command line:
##   tools/godot.sh -s res://tools/story_check.gd [--final] [--scene=<id>] [-- <file.tres> ...]
## Checks every scene folder under res://scenes/story, or the one named (`--scene=<id>`), or the shots.tres files named
## after the `--` (Godot takes a bare .tres on its command line for a scene to run, so paths follow `--`; a path is
## res://..., user://..., absolute, or relative to the project). Each scene's rules are ShotChecker's; each is also
## checked in its place (the region loaded here, `region` of the scene, or the training yard when it names none: the
## floor under every mark, room for a body, the walks' lines clear). Prints each problem as
## "story_check: <scene>/<shot or ->: <problem>" and exits 1; otherwise prints "story_check: N scenes OK (P placeholders)"
## and exits 0. A placeholder (a beat marked `placeholder` whose clip is not made yet) is listed but is not a problem in a
## draft; it is one in an approved scene, or with --final. Exits 2 for a wrong command line. The options may stand
## before or after `--`. A scene the checker could not finish is a problem, never OK.
## Run `tools/godot.sh --import` first when classes or data have been added.
##
## A script run with -s is compiled before the autoloads are known as names, and the checker reads the Registry
## autoload; so the checker is loaded at run time (not named in this file) and the Registry is fetched from the tree.
## The Registry has not run its own scan by then, so this scans it.

const CHECKER := "res://story/shot_checker.gd"
const SCENES := "res://scenes/story"
## The place of a scene that names no region: the game starts in the yard.
const DEFAULT_REGION := "res://world/training_yard/training_yard.tscn"
const SCRIPT := "res://tools/story_check.gd"
const USAGE := "usage: tools/godot.sh -s res://tools/story_check.gd [--final] [--scene=<id>] [-- <file.tres> ...]"


func _initialize() -> void:
	quit(await _run(_own_args()))


# The arguments that are the tool's: those after its own name on Godot's command line, and those after `--`.
func _own_args() -> PackedStringArray:
	var mine := PackedStringArray()
	var all := OS.get_cmdline_args()
	var at := all.find(SCRIPT)
	if at >= 0:
		mine.append_array(all.slice(at + 1))
	mine.append_array(OS.get_cmdline_user_args())
	return mine


func _run(args: PackedStringArray) -> int:
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
			return 2
		else:
			files.append(arg)
	var registry := root.get_node("Registry")
	var problems := PackedStringArray()
	for problem: String in registry.scan():
		problems.append("registry: " + problem)
	var checker: RefCounted = (load(CHECKER) as GDScript).new()
	# What to check: {name, lines (problems of the data), scene (null if it did not load)}.
	var jobs: Array[Dictionary] = []
	if files.is_empty():
		var folders: PackedStringArray = checker.scene_folders(SCENES)
		if only != "":
			if not folders.has(only):
				printerr("story_check: no scene folder '%s' under %s (there are: %s)" % [only, SCENES, ", ".join(folders)])
				return 1
			folders = PackedStringArray([only])
		for folder in folders:
			jobs.append({lines = checker.check_folder(SCENES.path_join(folder)), path = SCENES.path_join(folder).path_join("shots.tres")})
	else:
		for file in files:
			var path := file if file.begins_with("res://") or file.begins_with("user://") or file.begins_with("/") else "res://" + file
			jobs.append({lines = checker.check_file(path), path = path})
	var regions := {}   # region path -> the instanced region, kept for the place checks
	var placeholders := PackedStringArray()
	for job in jobs:
		var lines: PackedStringArray = job.lines
		var scene := ResourceLoader.load(job.path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
		if scene != null and scene.get_script() == load("res://story/scene_shots.gd"):
			lines.append_array(await _place_lines(checker, scene, regions))
		for line in lines:
			if checker.is_placeholder(line) and not final:
				placeholders.append(line)
			else:
				problems.append(line)
	for region: Node in regions.values():
		region.queue_free()
	for line in placeholders:
		print("story_check: " + line)
	if not problems.is_empty():
		for problem in problems:
			printerr("story_check: " + problem)
		return 1
	print("story_check: %d scenes OK (%d placeholders)" % [jobs.size(), placeholders.size()])
	return 0


# The place check of one scene: its region instanced in the tree (once per region) and a physics frame waited for.
func _place_lines(checker: RefCounted, scene: Resource, regions: Dictionary) -> PackedStringArray:
	var path: String = scene.get("region")
	if path == "":
		path = DEFAULT_REGION
	if not regions.has(path):
		var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
		if packed == null:
			return PackedStringArray()   # a region that does not exist is the checker's own line
		var region := packed.instantiate() as Node3D
		root.add_child(region)
		regions[path] = region
		await physics_frame
		await physics_frame
	var region: Node3D = regions[path]
	return checker.check_place(scene, region.get_world_3d().direct_space_state)
