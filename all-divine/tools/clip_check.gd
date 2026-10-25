extends SceneTree
## The clip checker on the command line:
##   tools/godot.sh -s res://tools/clip_check.gd [-- --data=res://data]
## Checks every actor and move under the data folder (default res://data; see ClipChecker for the rules)
## and prints each problem as "clip_check: <id>: <problem>" and exits 1; otherwise prints
## "clip_check: N moves, M actors OK" and exits 0. Exits 2 for a wrong command line.
## Run `tools/godot.sh --import` first when classes or data have been added.
##
## A script run with -s is compiled before the autoloads are known as names, and the checker reads the
## Registry autoload; so the checker is loaded at run time (not named in this file) and the Registry is
## fetched from the tree. The Registry has not run its own scan by then, so this scans it.

const CHECKER := "res://tools/clip_checker.gd"
const DEFAULT_DATA := "res://data"


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var data := DEFAULT_DATA
	for arg in args:
		if arg.begins_with("--data="):
			data = arg.trim_prefix("--data=")
		else:
			printerr("clip_check: unknown argument '%s'" % arg)
			printerr("usage: tools/godot.sh -s res://tools/clip_check.gd [-- --data=res://data]")
			return 2
	var registry := root.get_node("Registry")
	var problems := PackedStringArray()
	for problem: String in registry.scan(data):
		problems.append("registry: " + problem)
	var checker: RefCounted = (load(CHECKER) as GDScript).new()
	problems.append_array(checker.check_all())
	if not problems.is_empty():
		for problem in problems:
			printerr("clip_check: " + problem)
		return 1
	print("clip_check: %d moves, %d actors OK" % [registry.ids(&"moves").size(), registry.ids(&"actors").size()])
	return 0
