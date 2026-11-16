extends SceneTree
## Writes a scene's timeline out to be edited in the Godot editor:
##   tools/godot.sh -s res://tools/story/bake_timeline.gd -- --scene=<id> [--out=<path.tscn>]
## The file is scenes/story/<id>/timeline.tscn unless --out names another: a `Cutscene` node holding the AnimationPlayer with
## the generated animation (TimelineBuilder), a CineCamera and a bare `Director` node for the method track to point at in
## the editor. Open it, change the keys (the shot and progress tracks are the camera; the calls on Director are what
## the cast does), save it, and point the scene's `timeline` (in shots.tres) at the saved copy by hand: from then on that
## plays instead of the generated one. Nothing is committed until the owner wants an override.
## Exits 0 after writing the file, 1 when the scene's timing cannot be built (the reason is printed), 2 for a wrong
## command line.
##
## A script run with -s is compiled before the autoloads are known as names, and the builder reaches the Registry
## through the checker; so the builder is loaded at run time (not named here) and the Registry is scanned from the tree.

const USAGE := "usage: tools/godot.sh -s res://tools/story/bake_timeline.gd -- --scene=<id> [--out=<path.tscn>]"
const BUILDER := "res://story/timeline_builder.gd"


func _initialize() -> void:
	quit(_bake(OS.get_cmdline_user_args()))


func _bake(args: PackedStringArray) -> int:
	var id := ""
	var out := ""
	for arg in args:
		if arg.begins_with("--scene="):
			id = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		else:
			printerr("bake_timeline: unknown argument '%s'\n%s" % [arg, USAGE])
			return 2
	if id == "":
		printerr("bake_timeline: no --scene\n%s" % USAGE)
		return 2
	if out == "":
		out = "res://scenes/story/%s/timeline.tscn" % id
	var path := "res://scenes/story/%s/shots.tres" % id
	if not ResourceLoader.exists(path):
		printerr("bake_timeline: no scene '%s' (%s is missing)" % [id, path])
		return 2
	var scene := load(path) as SceneShots
	if scene == null:
		printerr("bake_timeline: %s is not a SceneShots" % path)
		return 2
	for problem: String in root.get_node("Registry").scan():
		printerr("bake_timeline: registry: %s" % problem)
	var builder: GDScript = load(BUILDER)
	var player: AnimationPlayer = builder.player_for(scene)
	if player == null:
		printerr("bake_timeline: %s" % builder.last_error)
		return 1
	var cutscene := player.get_parent()
	for node in cutscene.get_children():
		node.owner = cutscene
	var director := Node.new()
	director.name = "Director"
	cutscene.add_child(director)
	director.owner = cutscene
	var packed := PackedScene.new()
	var packed_ok := packed.pack(cutscene)
	cutscene.free()
	if packed_ok != OK or ResourceSaver.save(packed, out) != OK:
		printerr("bake_timeline: could not write %s" % out)
		return 1
	print("bake_timeline: wrote %s" % out)
	return 0
