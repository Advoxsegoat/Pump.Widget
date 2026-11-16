extends Node
## Finds the game's content resources and looks them up by kind and id.
##
## Autoload "Registry". A kind is a folder directly under the data root (res://data/moves/ is the
## kind "moves"); the resources under it, at any depth, are indexed by their `id` property.
## A resource without an `id` property is not content and is skipped.

const EXTENSIONS: PackedStringArray = ["tres", "res"]

# kind -> {id -> Resource}
var _kinds := {}


func _ready() -> void:
	scan()


## Reads every resource under `root` and replaces the index with them. Returns the problems it
## found, one text each (it also push_errors each): a duplicate id (the first one found stays), an
## empty id, or a resource that did not load. Lists folders with ResourceLoader, so it works in
## an exported build, where the files are packed.
func scan(root := "res://data") -> PackedStringArray:
	var problems := PackedStringArray()
	_kinds = {}
	var base := root.trim_suffix("/")
	for entry in _list(base):
		if entry.ends_with("/"):
			var kind := StringName(entry.trim_suffix("/"))
			_scan_folder(kind, base.path_join(entry.trim_suffix("/")), problems)
	for problem in problems:
		push_error(problem)
	return problems


## The resource of `kind` whose `id` is `id`. Raises an error and returns null if there is none.
func fetch(kind: StringName, id: StringName) -> Resource:
	var resource: Resource = _kinds.get(kind, {}).get(id)
	if resource == null:
		push_error("Registry: no %s '%s'" % [kind, id])
	return resource


## Every id of `kind`, in the order the scan found them. Empty for an unknown kind.
func ids(kind: StringName) -> PackedStringArray:
	var found := PackedStringArray()
	for id in _kinds.get(kind, {}):
		found.append(id)
	return found


func _scan_folder(kind: StringName, folder: String, problems: PackedStringArray) -> void:
	for entry in _list(folder):
		var path := folder.path_join(entry.trim_suffix("/"))
		if entry.ends_with("/"):
			_scan_folder(kind, path, problems)
		elif EXTENSIONS.has(entry.get_extension()):
			_add(kind, path, problems)


func _add(kind: StringName, path: String, problems: PackedStringArray) -> void:
	var resource := load(path) as Resource
	if resource == null:
		problems.append("Registry: could not load %s" % path)
		return
	if not _has_property(resource, &"id"):
		return
	var id := StringName(resource.get(&"id"))
	if id.is_empty():
		problems.append("Registry: empty id in %s" % path)
		return
	if not _kinds.has(kind):
		_kinds[kind] = {}
	var of_kind: Dictionary = _kinds[kind]
	if of_kind.has(id):
		problems.append("Registry: duplicate id '%s' in %s (kept %s)" % [id, path, of_kind[id].resource_path])
		return
	of_kind[id] = resource


func _has_property(resource: Resource, property: StringName) -> bool:
	for info in resource.get_property_list():
		if info.name == property:
			return true
	return false


# A folder's entries, sorted so the scan (and so which duplicate is kept) is the same everywhere.
func _list(folder: String) -> PackedStringArray:
	var entries := ResourceLoader.list_directory(folder)
	entries.sort()
	return entries
