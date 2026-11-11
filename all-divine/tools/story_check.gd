extends SceneTree
## The shot checker on the command line:
##   tools/godot.sh -s res://tools/story_check.gd [-- --scene=<id>] [--final]
## Checks every scene folder under res://scenes/story (or the one named) and prints each problem as
## "story_check: <scene>/<shot or ->: <problem>" and exits 1; otherwise prints "story_check: N scenes OK (P placeholders)"
## and exits 0. A placeholder (a beat marked `placeholder` whose clip is not made yet) is listed but is not a problem in
## a draft; it is one in an approved scene, or with --final. Exits 2 for a wrong command line.
## Run `tools/godot.sh --import` first when classes or data have been added.
##
## A script run with -s is compiled before the autoloads are known as names, and the checker reads the Registry
## autoload; so the checker is loaded at run time (not named in this file) and the Registry is fetched from the tree.
## The Registry has not run its own scan by then, so this scans it.

const CHECKER := "res://story/shot_checker.gd"
const SCENES := "res://scenes/story"
const USAGE := "usage: tools/godot.sh -s res://tools/story_check.gd [-- --scene=<id>] [--final]"


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var only := ""
	var final := false
	for arg in args:
		if arg.begins_with("--scene="):
			only = arg.trim_prefix("--scene=")
		elif arg == "--final":
			final = true
		else:
			printerr("story_check: unknown argument '%s'" % arg)
			printerr(USAGE)
			return 2
	var registry := root.get_node("Registry")
	var problems := PackedStringArray()
	for problem: String in registry.scan():
		problems.append("registry: " + problem)
	var checker: RefCounted = (load(CHECKER) as GDScript).new()
	var folders: PackedStringArray = checker.scene_folders(SCENES)
	if only != "":
		if not folders.has(only):
			printerr("story_check: no scene folder '%s' under %s (there are: %s)" % [only, SCENES, ", ".join(folders)])
			return 1
		folders = PackedStringArray([only])
	var placeholders := PackedStringArray()
	for folder in folders:
		for line: String in checker.check_folder(SCENES.path_join(folder)):
			if checker.is_placeholder(line) and not final:
				placeholders.append(line)
			else:
				problems.append(line)
	for line in placeholders:
		print("story_check: " + line)
	if not problems.is_empty():
		for problem in problems:
			printerr("story_check: " + problem)
		return 1
	print("story_check: %d scenes OK (%d placeholders)" % [folders.size(), placeholders.size()])
	return 0
