extends TestCase
## The exports. export_presets.cfg has the three builds CI makes (Linux, Windows Desktop, Web), each written
## where it should be, each leaving out tests/ and tools/, and no preset filters out what the game boots with.
## And every scene comes through the export with all its nodes.
##
## The game's first autoload (core/self_test.gd) uses TestLogger, which lives in core/ for that reason: the
## builds have no tools/, so nothing the game loads may be there (no path into it, no class declared in it).
##
## The export turns each scene into a binary one, and what comes out is what instantiating the scene and
## packing it again gives. Packing leaves out every node that hangs under a node of an instanced scene unless
## that instance is marked editable ([editable path="..."] in the .tscn; "Editable Children" in the editor). A
## scene that works when run from the project can lose those nodes in the build, and the game then fails at
## startup (main.tscn once did: its Region, Player and CameraRig hang under PixelStage/World).

const PRESETS := "res://export_presets.cfg"
## A file the shipped game loads at startup (the self-test autoload's logger).
const BOOT_FILE := "core/test_logger.gd"

const FIXTURE := "user://export_fixture"

## Each preset by name: its platform and where it is exported to (relative to the project folder).
const EXPECTED := {
	"Linux": {"platform": "Linux", "path": "out/linux/all-divine.x86_64"},
	"Windows Desktop": {"platform": "Windows Desktop", "path": "out/windows/all-divine.exe"},
	"Web": {"platform": "Web", "path": "out/web/index.html"},
}


func after_each() -> void:
	Presets.wipe(FIXTURE)


func test_presets_exist_with_paths_and_single_threaded_web() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK, "%s is missing or does not parse" % PRESETS)
	var sections := Presets.sections_by_name(cfg)
	for preset_name in EXPECTED:
		assert_true(sections.has(preset_name), "no preset named '%s' (found: %s)" % [preset_name, ", ".join(sections.keys())])
		if not sections.has(preset_name):
			continue
		var section: String = sections[preset_name]
		assert_eq(cfg.get_value(section, "platform"), EXPECTED[preset_name].platform, "%s: platform" % preset_name)
		assert_eq(cfg.get_value(section, "export_path"), EXPECTED[preset_name].path, "%s: export_path" % preset_name)
		assert_eq(cfg.get_value(section, "runnable"), true, "%s: runnable (the one-click Run needs it)" % preset_name)
	assert_eq(sections.size(), EXPECTED.size(), "presets other than the three expected ones: %s" % ", ".join(sections.keys()))
	if sections.has("Web"):
		assert_eq(cfg.get_value(sections["Web"] + ".options", "variant/thread_support"), false,
			"the web build is single-threaded: threads need cross-origin isolation headers that many hosts do not send")


func test_every_export_goes_under_out_which_git_ignores() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	var sections := Presets.sections_by_name(cfg)
	assert_false(sections.is_empty(), "no presets to check")
	for preset_name in sections:
		var path: String = cfg.get_value(sections[preset_name], "export_path", "")
		assert_true(path.begins_with("out/"), "%s exports to '%s', outside out/ (git-ignored, with a .gdignore)" % [preset_name, path])


func test_no_preset_filters_out_the_scripts_the_game_boots_with() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	var sections := Presets.sections_by_name(cfg)
	assert_false(sections.is_empty(), "no presets to check")
	for preset_name in sections:
		var section: String = sections[preset_name]
		assert_eq(cfg.get_value(section, "export_filter"), "all_resources",
			"%s: a preset that picks resources by hand can leave out %s" % [preset_name, BOOT_FILE])
		var exclude: String = cfg.get_value(section, "exclude_filter", "")
		assert_false(Presets.excludes(exclude, BOOT_FILE),
			"%s: exclude_filter '%s' removes %s, and the game cannot start without it" % [preset_name, exclude, BOOT_FILE])


func test_every_preset_leaves_out_tests_and_tools() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	var sections := Presets.sections_by_name(cfg)
	assert_false(sections.is_empty(), "no presets to check")
	for preset_name in sections:
		var exclude: String = cfg.get_value(sections[preset_name], "exclude_filter", "")
		for file in ["tests/core/test_layers.gd", "tools/test/run.gd", "tools/clip_checker.gd"]:
			assert_true(Presets.excludes(exclude, file), "%s: exclude_filter '%s' keeps %s in the build" % [preset_name, exclude, file])


# What the comments here and in export_presets.cfg say: of the game's own scripts (outside tools/ and tests/),
# only the self-test autoload uses TestLogger, and the file that declares it is where the self-test expects.
func test_only_the_self_test_boots_with_test_logger() -> void:
	var users := PackedStringArray()
	for path in Presets.game_files("res://", [".gd"]):
		if path != "res://" + BOOT_FILE and FileAccess.get_file_as_string(path).contains("TestLogger"):
			users.append(path)
	assert_eq(users, PackedStringArray(["res://core/self_test.gd"]))
	assert_true(FileAccess.get_file_as_string("res://" + BOOT_FILE).contains("class_name TestLogger"), "%s declares TestLogger" % BOOT_FILE)


# The builds have no tools/, so the game must not reach into it: no path to a file there, in a script, a scene,
# a resource or the project; and no use of a class declared there (the name is found outside comments).
func test_nothing_the_game_loads_lives_in_tools() -> void:
	var tool_classes := Presets.class_names("res://tools")
	assert_true(tool_classes.has("TestCase") and tool_classes.has("ClipChecker"), "the scan finds the classes in tools/ (found %s)" % ", ".join(tool_classes))
	var reaches := PackedStringArray()
	for path in Presets.game_files("res://", [".gd", ".tscn", ".tres", ".godot"]):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("res://tools/"):
			reaches.append("%s: a path into tools/" % path)
		if path.ends_with(".gd"):
			var code := Presets.without_comments(text)
			for tool_class in tool_classes:
				if code.contains(tool_class):
					reaches.append("%s: uses %s, declared in tools/" % [path, tool_class])
	assert_eq(reaches, PackedStringArray(), "\n".join(reaches))


func test_every_scene_keeps_all_its_nodes_through_the_exports_repack() -> void:
	var scenes := Presets.scenes("res://")
	assert_true(scenes.has("res://main/main.tscn"), "the scan did not find the main scene (found %d scenes)" % scenes.size())
	var lost := PackedStringArray()
	for path in scenes:
		for node_path in Presets.lost_in_repack(load(path) as PackedScene):
			lost.append("%s: %s" % [path, node_path])
	assert_eq(lost, PackedStringArray(),
		"nodes the export would drop (add [editable path=\"...\"] for the instance they hang under):\n" + "\n".join(lost))


# --- the helpers themselves: a check that cannot fail would prove nothing ---

func test_excludes_follows_the_engines_filter_rules() -> void:
	assert_true(Presets.excludes("core/*", BOOT_FILE), "a folder glob matches below it")
	assert_true(Presets.excludes("tests/*, core/*", BOOT_FILE), "patterns are comma-separated and trimmed")
	assert_true(Presets.excludes("res://core/test_logger.gd", BOOT_FILE), "a res:// pattern is the same path")
	assert_true(Presets.excludes("*/TEST_LOGGER.GD", BOOT_FILE), "matching ignores case, as the engine's matchn does")
	assert_false(Presets.excludes("tests/*, tools/*", BOOT_FILE), "other folders do not match")
	assert_false(Presets.excludes("", BOOT_FILE), "an empty filter excludes nothing")
	assert_false(Presets.excludes(" , ", BOOT_FILE), "blank patterns exclude nothing")


func test_sections_by_name_pairs_each_preset_with_its_section_and_skips_options() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("preset.0", "name", "A")
	cfg.set_value("preset.0.options", "name", "not a preset")
	cfg.set_value("preset.1", "name", "B")
	cfg.set_value("other", "name", "not a preset either")
	assert_eq(Presets.sections_by_name(cfg), {"A": "preset.0", "B": "preset.1"})


func test_lost_in_repack_finds_nodes_under_an_instance_that_is_not_editable() -> void:
	assert_eq(Presets.lost_in_repack(Presets.outer_scene(FIXTURE, false)), PackedStringArray(["Inner/World/Extra"]))
	assert_eq(Presets.lost_in_repack(Presets.outer_scene(FIXTURE, true)), PackedStringArray(),
		"an editable instance keeps the nodes under it")


func test_scenes_lists_scenes_below_the_project_but_not_the_tests() -> void:
	var scenes := Presets.scenes("res://")
	assert_true(scenes.has("res://world/courtyard/courtyard.tscn"))
	for path in scenes:
		assert_false(path.begins_with("res://tests/"), "%s is a test fixture, not part of the build" % path)


class Presets:
	## {preset name: its section ("preset.N")} for every preset in `cfg`; the "preset.N.options" sections are
	## not presets.
	static func sections_by_name(cfg: ConfigFile) -> Dictionary:
		var found := {}
		for section in cfg.get_sections():
			if section.begins_with("preset.") and not section.ends_with(".options"):
				found[cfg.get_value(section, "name", section)] = section
		return found

	## True if a preset's exclude_filter (comma-separated globs, matched case-insensitively against the
	## res:// path, as the engine does) removes `file`, a path relative to the project folder.
	static func excludes(filter: String, file: String) -> bool:
		var path := "res://" + file
		for pattern in filter.split(",", false):
			var glob := pattern.strip_edges()
			if glob.is_empty():
				continue
			if not glob.begins_with("res://") and not glob.begins_with("*"):
				glob = "res://" + glob
			if path.matchn(glob):
				return true
		return false

	## Every .tscn below `dir` (res:// paths, sorted) except those under tests/, which no build contains.
	static func scenes(dir: String) -> PackedStringArray:
		var found := PackedStringArray()
		for sub in DirAccess.get_directories_at(dir):
			if dir == "res://" and sub == "tests":
				continue
			if not FileAccess.file_exists(dir.path_join(sub).path_join(".gdignore")):
				found.append_array(scenes(dir.path_join(sub)))
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tscn"):
				found.append(dir.path_join(file))
		found.sort()
		return found

	## Every file the game is made of with one of the `endings` (".gd", ".tscn", ...): under `dir`, outside
	## tools/, tests/, folders that start with a dot and folders with a .gdignore.
	static func game_files(dir: String, endings: Array) -> PackedStringArray:
		var found := PackedStringArray()
		for sub in DirAccess.get_directories_at(dir):
			if dir == "res://" and (sub == "tests" or sub == "tools" or sub.begins_with(".")):
				continue
			if not FileAccess.file_exists(dir.path_join(sub).path_join(".gdignore")):
				found.append_array(game_files(dir.path_join(sub), endings))
		for file in DirAccess.get_files_at(dir):
			if endings.any(func(ending: String) -> bool: return file.ends_with(ending)):
				found.append(dir.path_join(file))
		found.sort()
		return found

	## The class_names declared by the .gd files under `dir`.
	static func class_names(dir: String) -> PackedStringArray:
		var found := PackedStringArray()
		for sub in DirAccess.get_directories_at(dir):
			if not sub.begins_with(".") and not FileAccess.file_exists(dir.path_join(sub).path_join(".gdignore")):
				found.append_array(class_names(dir.path_join(sub)))
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				for line in FileAccess.get_file_as_string(dir.path_join(file)).split("\n"):
					if line.begins_with("class_name "):
						found.append(line.trim_prefix("class_name ").strip_edges())
		return found

	## `text` of a script without what follows a # on each line: a comment, for the purpose of finding names.
	static func without_comments(text: String) -> String:
		var lines := PackedStringArray()
		for line in text.split("\n"):
			lines.append(line.get_slice("#", 0))
		return "\n".join(lines)

	## The paths (relative to the root) of the nodes `scene` has that the export would not keep. The export
	## instances the scene with its editable instances restored and packs it again; the node paths are compared
	## without the "./" that only some of them have.
	static func lost_in_repack(scene: PackedScene) -> PackedStringArray:
		var instance := scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var again := PackedScene.new()
		again.pack(instance)
		instance.free()
		var kept := {}
		var after := again.get_state()
		for i in after.get_node_count():
			kept[str(after.get_node_path(i)).trim_prefix("./")] = true
		var lost := PackedStringArray()
		var before := scene.get_state()
		for i in before.get_node_count():
			var node_path := str(before.get_node_path(i)).trim_prefix("./")
			if not kept.has(node_path):
				lost.append(node_path)
		return lost

	## Writes two scenes into `dir` and loads the second: "Outer" has an instance of "Inner" (which has a child
	## "World") and a node "Extra" under that World, the shape of main.tscn. `editable` adds the
	## [editable path="Inner"] line that makes packing keep Extra.
	static func outer_scene(dir: String, editable: bool) -> PackedScene:
		write(dir.path_join("inner.tscn"), "\n".join([
			"[gd_scene format=3]",
			"",
			"[node name=\"Inner\" type=\"Node\"]",
			"",
			"[node name=\"World\" type=\"Node\" parent=\".\"]",
			""]))
		var lines := PackedStringArray([
			"[gd_scene load_steps=2 format=3]",
			"",
			"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1\"]" % dir.path_join("inner.tscn"),
			"",
			"[node name=\"Outer\" type=\"Node\"]",
			"",
			"[node name=\"Inner\" parent=\".\" instance=ExtResource(\"1\")]",
			"",
			"[node name=\"Extra\" type=\"Node\" parent=\"Inner/World\"]",
			""])
		if editable:
			lines.append_array(["[editable path=\"Inner\"]", ""])
		write(dir.path_join("outer.tscn"), "\n".join(lines))
		return ResourceLoader.load(dir.path_join("outer.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene

	static func write(path: String, text: String) -> void:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()

	static func wipe(dir: String) -> void:
		if not DirAccess.dir_exists_absolute(dir):
			return
		for file in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)
