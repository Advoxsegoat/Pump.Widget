extends TestCase
## The licence ledger. Every file under res://assets has a row in res://ASSETS.md, and every row
## names something that exists (with exactly that case) and a licence we allow.
##
## ASSETS.md holds a table, | Path | Source | Licence | Changes |. A path is relative to the
## project folder; one that ends in "/" covers everything under that folder.

const LEDGER := "res://ASSETS.md"
const FIXTURE := "user://ledger_fixture"


func after_each() -> void:
	Ledger.wipe(FIXTURE)


func test_every_asset_file_has_a_ledger_row() -> void:
	var missing := Ledger.unlisted("res://assets", LEDGER)
	assert_eq(missing, PackedStringArray(), "\n".join(missing))
	assert_true(Ledger.scanned > 0, "the scan found no files under res://assets")


func test_ledger_rows_name_existing_paths_and_allowed_licences() -> void:
	var problems := Ledger.problems(LEDGER, "res://")
	assert_eq(problems, PackedStringArray(), "\n".join(problems))
	assert_true(Ledger.rows(LEDGER).size() > 0, "ASSETS.md has no rows")


# --- the helper itself: a check that cannot fail would prove nothing ---

func test_unlisted_reports_files_no_row_covers_and_skips_import_files() -> void:
	Ledger.write(FIXTURE + "/assets/env/town/wall.glb", "x")
	Ledger.write(FIXTURE + "/assets/env/town/wall.glb.import", "x")
	Ledger.write(FIXTURE + "/assets/env/town/Textures/colormap.png", "x")
	Ledger.write(FIXTURE + "/assets/ours/a.png", "x")
	Ledger.write(FIXTURE + "/assets/ours/a.png.import", "x")
	Ledger.write(FIXTURE + "/assets/ours/b.png", "x")        # only a.png has a row
	Ledger.write(FIXTURE + "/assets/stray.png", "x")
	Ledger.write(FIXTURE + "/assets/env/townhall/x.png", "x")  # a sibling folder is not "env/town/"
	Ledger.write(FIXTURE + "/ASSETS.md", "\n".join([
		"| Path | Source | Licence | Changes |",
		"|---|---|---|---|",
		"| assets/env/town/ | Somebody, https://example.com | CC0 1.0 | none |",
		"| `assets/ours/a.png` | us | ours | none |",
	]))
	var missing := Ledger.unlisted(FIXTURE + "/assets", FIXTURE + "/ASSETS.md")
	assert_eq(missing, PackedStringArray([
		"assets/env/townhall/x.png", "assets/ours/b.png", "assets/stray.png"]))
	assert_eq(Ledger.scanned, 6, "six files, not counting the two .import files")


func test_a_missing_ledger_is_reported_even_when_there_is_nothing_to_list() -> void:
	var missing := Ledger.unlisted(FIXTURE + "/assets", FIXTURE + "/ASSETS.md")
	assert_eq(missing.size(), 1)
	assert_true(missing[0].contains("missing"), missing[0])
	var problems := Ledger.problems(FIXTURE + "/ASSETS.md", FIXTURE)
	assert_eq(problems.size(), 1)
	assert_true(problems[0].contains("missing"), problems[0])


func test_problems_reports_every_kind_of_bad_row() -> void:
	Ledger.write(FIXTURE + "/assets/env/town/wall.glb", "x")
	Ledger.write(FIXTURE + "/assets/ours/a.png", "x")
	Ledger.write(FIXTURE + "/ASSETS.md", "\n".join([
		"# Ledger",
		"",
		"| Path | Source | Licence | Changes |",
		"|---|---|---|---|",
		"| assets/env/town/ | Somebody | CC0 1.0 | none |",                    # fine
		"| assets/ours/a.png | us | CMU (free for any use) | none |",          # fine
		"| assets/env/town/ | Somebody | MIT | none |",                        # licence not allowed
		"| assets/gone/ | Somebody | CC0 1.0 | none |",                        # no such folder
		"| assets/Ours/a.png | us | ours | none |",                            # wrong case
		"| assets/ours/a.png/ | us | ours | none |",                           # a file written as a folder
		"| assets/env/town | us | ours | none |",                              # a folder written as a file
		"| assets/ours/a.png | us | ours |",                                   # three columns
		"| assets/ours/a.png | | ours | none |",                               # empty source
		"| ../outside.png | us | ours | none |",                               # leaves the project
	]))
	var found := Ledger.problems(FIXTURE + "/ASSETS.md", FIXTURE)
	var text := "\n".join(found)
	assert_eq(found.size(), 8, text)
	assert_true(text.contains("MIT"), text)
	assert_true(text.contains("assets/gone/"), text)
	assert_true(text.contains("assets/Ours/a.png"), text)
	assert_true(text.contains("assets/ours/a.png/"), text)
	assert_true(text.contains("assets/env/town does not exist"), text)
	assert_true(text.contains("4 columns"), text)
	assert_true(text.contains("empty"), text)
	assert_true(text.contains("../outside.png"), text)


func test_a_clean_ledger_has_no_problems() -> void:
	Ledger.write(FIXTURE + "/assets/env/town/wall.glb", "x")
	Ledger.write(FIXTURE + "/ASSETS.md", "\n".join([
		"| Path | Source | Licence | Changes |",
		"| --- | --- | --- | --- |",
		"| assets/env/town/ | Somebody, https://example.com | CC0 1.0 | pieces copied unchanged |",
	]))
	assert_eq(Ledger.problems(FIXTURE + "/ASSETS.md", FIXTURE), PackedStringArray())
	assert_eq(Ledger.rows(FIXTURE + "/ASSETS.md").size(), 1)


class Ledger:
	const ALLOWED_LICENCES: PackedStringArray = ["CC0 1.0", "ours", "CMU (free for any use)"]
	const COLUMNS := 4

	## How many files the last `unlisted` scan looked at (`.import` files are not counted).
	static var scanned := 0

	## The table rows of `ledger_path`: {path, source, licence, changes, cells, line}. The header
	## and the separator line are not rows. A path in backticks is read without them.
	static func rows(ledger_path: String) -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		if not FileAccess.file_exists(ledger_path):
			return found
		var lines := FileAccess.get_file_as_string(ledger_path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if not line.begins_with("|"):
				continue
			var cells := PackedStringArray()
			for cell in line.trim_prefix("|").trim_suffix("|").split("|"):
				cells.append(cell.strip_edges())
			if _is_separator(cells) or cells[0].to_lower() == "path":
				continue
			var path := cells[0].trim_prefix("`").trim_suffix("`").strip_edges()
			found.append({
				"path": path,
				"source": cells[1] if cells.size() > 1 else "",
				"licence": cells[2] if cells.size() > 2 else "",
				"changes": cells[3] if cells.size() > 3 else "",
				"cells": cells.size(),
				"line": i + 1,
			})
		return found

	## Files under `assets_dir` that no row covers, as paths relative to the folder that holds
	## `assets_dir` (so "assets/env/x.glb"), sorted. `.import` files are skipped. A missing
	## ledger is reported as a single entry, so it fails even when there is nothing to list.
	static func unlisted(assets_dir: String, ledger_path: String) -> PackedStringArray:
		scanned = 0
		if not FileAccess.file_exists(ledger_path):
			return PackedStringArray([ledger_path + " is missing"])
		var covering := PackedStringArray()
		for row in rows(ledger_path):
			if row.path != "":
				covering.append(row.path)
		var base := assets_dir.get_base_dir()
		if not base.ends_with("/"):
			base += "/"
		var missing := PackedStringArray()
		for file in _files(assets_dir):
			scanned += 1
			var relative := file.trim_prefix(base)
			if not _covered(relative, covering):
				missing.append(relative)
		missing.sort()
		return missing

	## One line per bad row: wrong column count, an empty cell, a path that does not exist with
	## exactly that case (a trailing "/" means a folder), or a licence that is not allowed.
	## `root` is the folder the paths are relative to.
	static func problems(ledger_path: String, root: String) -> PackedStringArray:
		if not FileAccess.file_exists(ledger_path):
			return PackedStringArray([ledger_path + " is missing"])
		var found := PackedStringArray()
		for row in rows(ledger_path):
			var where := "%s:%d" % [ledger_path.get_file(), row.line]
			if row.cells != COLUMNS:
				found.append("%s: expected %d columns, found %d" % [where, COLUMNS, row.cells])
				continue
			if row.path == "" or row.source == "" or row.licence == "" or row.changes == "":
				found.append("%s: a cell is empty (%s)" % [where, row.path])
				continue
			if not _exists_exactly(root, row.path):
				found.append("%s: %s does not exist (or not with that exact case, or is not a %s)" % [
					where, row.path, "folder" if row.path.ends_with("/") else "file"])
			if not ALLOWED_LICENCES.has(row.licence):
				found.append("%s: licence '%s' is not one of %s" % [where, row.licence, ", ".join(ALLOWED_LICENCES)])
		return found

	static func write(path: String, text: String) -> void:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()

	## Deletes `dir` and everything in it.
	static func wipe(dir: String) -> void:
		var access := DirAccess.open(dir)
		if access == null:
			return
		access.include_hidden = true
		for sub in access.get_directories():
			wipe(dir.path_join(sub))
		for file in access.get_files():
			access.remove(file)
		DirAccess.remove_absolute(dir)

	static func _is_separator(cells: PackedStringArray) -> bool:
		for cell in cells:
			if cell == "" or cell.strip_edges().trim_prefix(":").trim_suffix(":").replace("-", "") != "":
				return false
		return true

	# A row path ending in "/" covers everything under it; any other row covers exactly that file.
	# Comparison is case-sensitive.
	static func _covered(relative: String, covering: PackedStringArray) -> bool:
		for path in covering:
			if relative == path or (path.ends_with("/") and relative.begins_with(path)):
				return true
		return false

	# Every file under `dir` (hidden ones too) except *.import, as full paths.
	static func _files(dir: String) -> PackedStringArray:
		var found := PackedStringArray()
		var access := DirAccess.open(dir)
		if access == null:
			return found
		access.include_hidden = true
		for sub in access.get_directories():
			found.append_array(_files(dir.path_join(sub)))
		for file in access.get_files():
			if file.get_extension() != "import":
				found.append(dir.path_join(file))
		return found

	# True when `relative` (a path under `root`) exists with exactly that spelling. With a
	# trailing "/" it must be a folder, otherwise a file.
	static func _exists_exactly(root: String, relative: String) -> bool:
		var parts := relative.split("/", false)
		if parts.is_empty():
			return false
		var current := root
		for i in parts.size():
			var access := DirAccess.open(current)
			if access == null:
				return false
			access.include_hidden = true
			var wants_folder := i < parts.size() - 1 or relative.ends_with("/")
			var names := access.get_directories() if wants_folder else access.get_files()
			if not names.has(parts[i]):
				return false
			current = current.path_join(parts[i])
		return true
