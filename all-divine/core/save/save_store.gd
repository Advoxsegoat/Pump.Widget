class_name SaveStore
extends RefCounted
## The saved game's file: one JSON file with a check and a version, a backup of the one before, and a way of writing
## that always leaves a usable file on disk.
##
## The file is `{"check": <sha256 of the text that follows>, "version": 1, <the fields of SaveData>}`, the check first,
## every other key sorted, no spaces: the same game is the same text every time, and one changed character fails the check.
##
## Writing goes temp, verify, backup, rename (see `write`), so a crash or a full disk at any step leaves the main file,
## the backup or the verified temp file whole. A file from a newer game is never read and never overwritten: it is moved
## aside as `save.v<its version>.json`. Reading never raises an error and never crashes: the main file, else the backup,
## else nothing (the game starts a new one).
##
## The player's own folder is the game's alone: not a test, not a `-s` script, not the self-test and not a run that says
## `--no-player-settings` reads or writes it (`may_use`, as `Settings` does for its file).

## The player's folder.
const PLAYER_DIR := "user://save"
## The saved game.
const MAIN := "save.json"
## The one before it.
const BACKUP := "save.bak.json"
## Where a write is made and checked before it replaces anything.
const TEMP := "save.tmp"

## Which file the last `read` took its game from.
enum Source { NONE, MAIN, BACKUP }

## The folder the files are in.
var dir := PLAYER_DIR
## Where the last `read` found its game.
var last_source := Source.NONE
## One line on what the last `read` found wrong with a file, "" when it found nothing wrong (including when there was
## nothing at all: a first game).
var last_problem := ""


func _init(save_dir: String = PLAYER_DIR) -> void:
	dir = save_dir


## Whether this run may read and write the files in `dir`. The player's folder is not for the self-test, a script run
## with -s (the tests and the tools) or a run that says it is not the player's game; any other folder is anyone's.
func may_use() -> bool:
	if dir != PLAYER_DIR:
		return true
	return not SelfTest.active and not Settings.scripted_run and not Settings.user_args.has(Settings.NO_PLAYER_SETTINGS)


## Saves `data`: encodes it, writes it to the temp file, reads that back and decodes it (a temp that does not decode is
## removed and the old files are left as they were); then the main file, if it is a usable save, becomes the backup,
## or, if it is a newer game's, is moved to `save.v<version>.json` (never to the backup, never over another file);
## then the temp file becomes the main one. At every step at least one usable file is on disk. OK and nothing written
## when `may_use` is false; otherwise the error of the step that failed.
func write(data: SaveData) -> Error:
	if not may_use():
		return OK
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return made
	var temp := dir.path_join(TEMP)
	var main := dir.path_join(MAIN)
	var backup := dir.path_join(BACKUP)
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(encode(data))
	file.flush()
	var stored := file.get_error()
	file.close()
	if stored != OK:
		DirAccess.remove_absolute(temp)
		return stored
	if decode(_text_of(temp)) == null:
		DirAccess.remove_absolute(temp)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(main):
		var seen := _inspect(_text_of(main))
		var moved := OK
		if int(seen["newer"]) > 0:
			moved = DirAccess.rename_absolute(main, _free_name(int(seen["newer"])))
		elif seen["data"] != null:
			# The backup is removed first, not renamed over: a rename onto a file is not the same on every system.
			# The main file is still whole while it is gone.
			DirAccess.remove_absolute(backup)
			moved = DirAccess.rename_absolute(main, backup)
		else:
			DirAccess.remove_absolute(main)
		if moved != OK:
			DirAccess.remove_absolute(temp)
			return moved
	var renamed := DirAccess.rename_absolute(temp, main)
	if renamed != OK:
		DirAccess.remove_absolute(temp)
	return renamed


## The saved game: the main file's, else the backup's, else null (nothing usable: the caller starts a new game). Sets
## `last_source` and `last_problem`. Never raises an error, whatever is in the files.
func read() -> SaveData:
	last_source = Source.NONE
	last_problem = ""
	if not may_use():
		return null
	var problems: Array[String] = []
	var main := dir.path_join(MAIN)
	var backup := dir.path_join(BACKUP)
	var main_exists := FileAccess.file_exists(main)
	if main_exists:
		var seen := _inspect(_text_of(main))
		if seen["data"] != null:
			last_source = Source.MAIN
			return seen["data"]
		problems.append("%s: %s" % [MAIN, seen["problem"]])
	if FileAccess.file_exists(backup):
		var seen := _inspect(_text_of(backup))
		if seen["data"] != null:
			last_source = Source.BACKUP
			if not main_exists:
				problems.append("%s is missing" % MAIN)
			last_problem = "; ".join(problems)
			return seen["data"]
		problems.append("%s: %s" % [BACKUP, seen["problem"]])
	last_problem = "; ".join(problems)
	return null


## `data` as the text of a file.
static func encode(data: SaveData) -> String:
	return seal(data.to_dict())


## `fields` as the text of a file of `version`: the version added, the check first. For `encode`, and for a test that
## makes a file the game did not (an odd field, a newer version) with its check right.
static func seal(fields: Dictionary, version: int = SaveData.VERSION) -> String:
	var body := fields.duplicate()
	body.erase("check")
	body["version"] = version
	var text := JSON.stringify(body, "", true)
	return "{\"check\":\"%s\",%s" % [text.sha256_text(), text.substr(1)]


## The saved game in `text`, or null when it is not a usable one: not data, no whole version of 1 or more, a version
## newer than this game's, a check that does not match, or a version that cannot be brought up to date.
static func decode(text: String) -> Variant:
	return _inspect(text)["data"]


# What `text` is, as `{data: SaveData or null, problem: String, newer: int}`; `newer` is the version when it is a newer
# game's file (found by its version alone: a newer game's check may be a different kind).
static func _inspect(text: String) -> Dictionary:
	var out := {"data": null, "problem": "", "newer": 0}
	var trimmed := text.strip_edges()
	var json := JSON.new()
	if trimmed == "":
		out["problem"] = "empty"
		return out
	if json.parse(trimmed) != OK or typeof(json.data) != TYPE_DICTIONARY:
		out["problem"] = "cannot be read as a saved game"
		return out
	var d: Dictionary = json.data
	var version := SaveMigrations.whole_version(d.get("version"))
	if version < 1:
		out["problem"] = "no usable version"
		return out
	if version > SaveData.VERSION:
		out["newer"] = version
		out["problem"] = "written by a newer game (version %d)" % version
		return out
	var check: Variant = d.get("check")
	var prefix := "{\"check\":\"%s\"," % check
	if typeof(check) != TYPE_STRING or not trimmed.begins_with(prefix) \
			or ("{" + trimmed.substr(prefix.length())).sha256_text() != check:
		out["problem"] = "fails its check (cut short or changed)"
		return out
	d.erase("check")
	var upgraded := SaveMigrations.upgrade(d)
	if upgraded.is_empty():
		out["problem"] = "cannot be brought up to date"
		return out
	out["data"] = SaveData.from_dict(upgraded)
	return out


# The text of the file at `path`, "" when it is not valid UTF-8 (a file of random bytes): the engine prints an error for
# each bad byte when it is asked to make text of them, and a bad file must cost the player nothing, not even a log line.
static func _text_of(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	return bytes.get_string_from_utf8() if _is_utf8(bytes) else ""


# Whether `bytes` is well-formed UTF-8 (no stray, truncated or overlong sequence, no surrogate, nothing past U+10FFFF).
static func _is_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	var n := bytes.size()
	while i < n:
		var b := bytes[i]
		var extra := 0
		var low := 0x80
		var high := 0xBF
		if b < 0x80:
			i += 1
			continue
		elif b >= 0xC2 and b <= 0xDF:
			extra = 1
		elif b == 0xE0:
			extra = 2
			low = 0xA0
		elif b == 0xED:
			extra = 2
			high = 0x9F
		elif b >= 0xE1 and b <= 0xEF:
			extra = 2
		elif b == 0xF0:
			extra = 3
			low = 0x90
		elif b == 0xF4:
			extra = 3
			high = 0x8F
		elif b >= 0xF1 and b <= 0xF3:
			extra = 3
		else:
			return false
		if i + extra >= n:
			return false
		if bytes[i + 1] < low or bytes[i + 1] > high:
			return false
		for k in range(2, extra + 1):
			if bytes[i + k] < 0x80 or bytes[i + k] > 0xBF:
				return false
		i += extra + 1
	return true


# A name for a newer game's file that no file has: `save.v99.json`, else `save.v99.1.json`, and so on.
func _free_name(version: int) -> String:
	var name := dir.path_join("save.v%d.json" % version)
	var n := 0
	while FileAccess.file_exists(name):
		n += 1
		name = dir.path_join("save.v%d.%d.json" % [version, n])
	return name
