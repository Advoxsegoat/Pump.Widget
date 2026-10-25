extends SceneTree
## Builds Abarax's animation library from the Quaternius clips (assets/anim/clips.cfg):
##   tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 <dir>
## where <dir> is the extracted Universal Animation Library, which
##   python3 -I tools/assets/fetch.py path ual1
## prints. Writes assets/anim/abarax/<clip>.tres and library.tres, and keeps the marks on clips that
## already exist (see ClipBuilder.build). Run `tools/godot.sh --import` afterwards.
## Exits 0 on success, 1 if the build failed, 2 for a wrong command line.
##
## The pack is read as data (GLTFDocument); nothing in it is run. The importer may print some noise
## about the pack's files while this runs.

# By path rather than by class name, so the tool also runs before the project has been imported.
const Builder := preload("res://tools/anim/clip_builder.gd")

const CONFIG := "res://assets/anim/clips.cfg"
const OUT_DIR := "res://assets/anim/abarax"
const MODEL := "res://assets/characters/abarax/abarax.glb"
# Where the two files are inside the extracted pack.
const UAL1_FILES := {
	"ual1": "Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb",
	"ual1_rm": "Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard_RM.glb",
}


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var ual1 := ""
	var i := 0
	while i < args.size():
		if args[i] == "--ual1" and i + 1 < args.size():
			ual1 = args[i + 1]
			i += 2
		elif args[i].begins_with("--ual1="):
			ual1 = args[i].trim_prefix("--ual1=")
			i += 1
		else:
			printerr("build_library.gd: unknown argument '%s'" % args[i])
			return _usage()
	if ual1 == "":
		return _usage()
	var sources := {}
	for key: String in UAL1_FILES:
		sources[key] = ual1.path_join(UAL1_FILES[key])
		if not FileAccess.file_exists(sources[key]):
			printerr("build_library.gd: no '%s'" % sources[key])
			return 2
	var err := Builder.build(CONFIG, sources, OUT_DIR, MODEL)
	if err != OK:
		printerr("build_library.gd: the build failed (%s)" % error_string(err))
		return 1
	print("build_library.gd: wrote %s/library.tres" % OUT_DIR)
	return 0


func _usage() -> int:
	printerr("usage: tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 <extracted Universal Animation Library>")
	return 2
