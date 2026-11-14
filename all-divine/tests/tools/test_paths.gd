extends TestCase
## Every res:// path written in a scene, resource, script, shader or config must
## name an existing file or folder with exactly that spelling. Linux is
## case-sensitive, Windows and macOS are not, so a wrong-case path works here
## and breaks in a player's export.

const FIXTURE := "user://path_fixture"
## The paths below are joined at run time, so the scan of res:// does not find them in this file.
const RES := "res://"


func after_each() -> void:
	_wipe(FIXTURE)


func test_every_res_path_matches_case_exactly() -> void:
	var bad := PathCheck.mismatches("res://")
	assert_eq(bad, PackedStringArray(), "\n".join(bad))
	assert_true(PathCheck.checked > 0, "the scan found no res:// paths at all")


# The check itself: a scan that cannot fail would prove nothing. Files under user:// (outside res://, so the
# real scan never sees them) that point into the project, with right and wrong spellings.
func test_a_wrong_case_path_is_caught() -> void:
	var scene := FIXTURE.path_join("scene.tscn")
	_write(scene, "\n".join([
		'[ext_resource type="Script" path="%s" id="1"]' % (RES + "core/inputs.gd"),       # right
		'[ext_resource type="Script" path="%s" id="2"]' % (RES + "Core/inputs.gd"),       # a folder in the wrong case
		'[ext_resource type="Script" path="%s" id="3"]' % (RES + "core/Inputs.gd"),       # a file in the wrong case
		'[ext_resource type="Script" path="%s" id="4"]' % (RES + "core/no_such_file.gd"), # missing
	]))
	var script := FIXTURE.path_join("sub/tool.gd")
	_write(script, "\n".join([
		"# %s is in a comment, which is not checked" % (RES + "CORE/inputs.gd"),
		'const A := preload("%s")' % (RES + "main/Main.tscn"),                             # a file in the wrong case
		'const B := "%s"' % (RES + "main/main.tscn"),                                       # right
	]))
	_write(FIXTURE.path_join("notes.txt"), RES + "NOT/scanned.gd")  # not a kind of file that is scanned
	var bad := PathCheck.mismatches(FIXTURE)
	assert_eq(bad, PackedStringArray([
		"%s: %s" % [script, RES + "main/Main.tscn"],
		"%s: %s" % [scene, RES + "Core/inputs.gd"],
		"%s: %s" % [scene, RES + "core/Inputs.gd"],
		"%s: %s" % [scene, RES + "core/no_such_file.gd"],
	]), "\n".join(bad))
	assert_eq(PathCheck.checked, 6, "six paths: four in the scene, two in the script outside its comment")


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


class PathCheck:
	const SCANNED_EXTENSIONS: PackedStringArray = ["tscn", "tres", "gd", "gdshader", "cfg"]
	# Characters that end a path inside a string or a scene file.
	const PATH_ENDERS := "\"'<>()[]{}:;,|*?%$#`\\^"

	## How many res:// paths the last scan looked at.
	static var checked := 0
	static var _listings := {}

	## One line per res:// path under `root` that does not exist with exactly that case.
	static func mismatches(root: String) -> PackedStringArray:
		checked = 0
		_listings.clear()
		var bad := PackedStringArray()
		_scan(root, bad)
		return bad

	static func _scan(dir: String, bad: PackedStringArray) -> void:
		if FileAccess.file_exists(dir.path_join(".gdignore")):
			return
		for sub in DirAccess.get_directories_at(dir):
			_scan(dir.path_join(sub), bad)
		for file in DirAccess.get_files_at(dir):
			if not _is_scanned(file):
				continue
			var path := dir.path_join(file)
			for reference in _references(path):
				checked += 1
				if not _exists_with_exact_case(reference):
					bad.append("%s: %s" % [path, reference])

	static func _is_scanned(file: String) -> bool:
		return file == "project.godot" or SCANNED_EXTENSIONS.has(file.get_extension())

	# What starts a comment line in this kind of file.
	static func _comment_marker(file: String) -> String:
		match file.get_extension():
			"gd":
				return "#"
			"gdshader":
				return "//"
			"cfg", "godot":
				return ";"
		return ""

	# Every res:// string in the file, outside whole-line comments.
	static func _references(path: String) -> PackedStringArray:
		var marker := _comment_marker(path.get_file())
		var found := PackedStringArray()
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if marker != "" and line.strip_edges(true, false).begins_with(marker):
				continue
			var from := 0
			while true:
				var start := line.find("res://", from)
				if start < 0:
					break
				var end := start + "res://".length()
				while end < line.length() and line[end].strip_edges() != "" and not PATH_ENDERS.contains(line[end]):
					end += 1
				found.append(line.substr(start, end - start))
				from = end
		return found

	static func _exists_with_exact_case(path: String) -> bool:
		var current := "res://"
		for part in path.trim_prefix("res://").split("/", false):
			if not _entries(current).has(part):
				return false
			current = current.path_join(part)
		return true

	# Names of everything directly inside `dir`, hidden entries too (cached).
	static func _entries(dir: String) -> PackedStringArray:
		if not _listings.has(dir):
			var names := PackedStringArray()
			if DirAccess.dir_exists_absolute(dir):
				var access := DirAccess.open(dir)
				access.include_hidden = true
				names.append_array(access.get_directories())
				names.append_array(access.get_files())
			_listings[dir] = names
		return _listings[dir]
