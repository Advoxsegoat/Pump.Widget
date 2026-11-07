extends SceneTree
## Builds Abarax's animation library from the Quaternius clips (assets/anim/clips.cfg):
##   tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 <dir> --ual2 <dir>
## where <dir> is the extracted pack, which
##   python3 -I tools/assets/fetch.py path ual1   (and ual2)
## prints: ual1 is the Universal Animation Library and ual2 the Universal Animation Library 2. Writes
## assets/anim/abarax/<clip>.tres and library.tres, and keeps the marks on clips that already exist (see
## ClipBuilder.build). Run `tools/godot.sh --import` afterwards.
## Exits 0 on success, 1 if the build failed, 2 for a wrong command line.
##
## The packs are read as data (GLTFDocument); nothing in them is run. The importer may print some noise
## about the packs' files while this runs.

# By path rather than by class name, so the tool also runs before the project has been imported.
const Builder := preload("res://tools/anim/clip_builder.gd")

const CONFIG := "res://assets/anim/clips.cfg"
const OUT_DIR := "res://assets/anim/abarax"
const MODEL := "res://assets/characters/abarax/abarax.glb"
# Each pack (named by its command-line flag and its id in tools/assets/sources.json): the source keys that
# clips.cfg uses for the two files in it, and where they are inside the extracted pack.
const PACKS := {
	"ual1": {
		"ual1": "Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb",
		"ual1_rm": "Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard_RM.glb",
	},
	"ual2": {
		"ual2": "Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb",
		"ual2_rm": "Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard_RM.glb",
	},
}


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var dirs := {}  # pack -> where it was extracted
	var i := 0
	while i < args.size():
		var flag := args[i].split("=", true, 1)  # ["--ual1", "<dir>"], or just ["--ual1"] with the dir in the next argument
		var pack := flag[0].trim_prefix("--")
		if not flag[0].begins_with("--") or not PACKS.has(pack):
			printerr("build_library.gd: unknown argument '%s'" % args[i])
			return _usage()
		if flag.size() == 2:
			dirs[pack] = flag[1]
			i += 1
		elif i + 1 < args.size():
			dirs[pack] = args[i + 1]
			i += 2
		else:
			return _usage()
	var sources := {}
	for pack: String in PACKS:
		if not dirs.has(pack):
			return _usage()
		for key: String in PACKS[pack]:
			sources[key] = String(dirs[pack]).path_join(PACKS[pack][key])
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
	printerr("usage: tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 <extracted Universal Animation Library> --ual2 <extracted Universal Animation Library 2>")
	return 2
