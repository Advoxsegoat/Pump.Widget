extends TestCase
## Every res:// path written in a scene, resource, script, shader or config must
## name an existing file or folder with exactly that spelling. Linux is
## case-sensitive, Windows and macOS are not, so a wrong-case path works here
## and breaks in a player's export.

func test_every_res_path_matches_case_exactly() -> void:
	var bad := PathCheck.mismatches("res://")
	assert_eq(bad, PackedStringArray(), "\n".join(bad))
	assert_true(PathCheck.checked > 0, "the scan found no res:// paths at all")


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
