extends SceneTree
## Builds the courtyard from its layout, as it was made once:
##   tools/godot.sh -s res://tools/world/build_courtyard.gd
## reads world/courtyard/layout.txt and writes world/courtyard/courtyard.tscn through tools/world/build_region.gd, which
## does the work for any region (and says what a layout can hold). The scene is the source from then on, and building
## again would overwrite whatever was changed in it. Exits 0, or 1 on a problem.

const BUILD_REGION := preload("res://tools/world/build_region.gd")
const LAYOUT := "res://world/courtyard/layout.txt"
const OUT := "res://world/courtyard/courtyard.tscn"


func _initialize() -> void:
	quit(BUILD_REGION.build(LAYOUT, OUT))
