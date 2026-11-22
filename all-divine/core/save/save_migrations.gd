class_name SaveMigrations
extends RefCounted
## Brings a saved game written by an older version of the game up to the current one, one version at a time.
##
## `STEPS[i]` takes a dictionary of version i + 1 and returns the one of version i + 2 (it sets `version` itself, so a
## step that forgets is caught). The game has shipped no save, so the chain is empty; the first change to what a save
## holds that cannot be read by the old code adds the first step here, and bumps `SaveData.VERSION`.

const STEPS: Array[Callable] = []


## `d` brought to the newest version `steps` reach (`steps.size() + 1`), or `{}` when it cannot be: a `version` that is
## missing, not a whole number, below 1 or above the newest, or a step that returns anything but a dictionary of the
## next version. `d` itself is never changed.
static func upgrade(d: Dictionary, steps: Array[Callable] = STEPS) -> Dictionary:
	var version := whole_version(d.get("version"))
	if version < 1 or version > steps.size() + 1:
		return {}
	var out := d.duplicate(true)
	out["version"] = version
	while version <= steps.size():
		var stepped: Variant = steps[version - 1].call(out.duplicate(true))
		if typeof(stepped) != TYPE_DICTIONARY:
			return {}
		var next: Dictionary = stepped
		if whole_version(next.get("version")) != version + 1:
			return {}
		out = next
		out["version"] = version + 1
		version += 1
	return out


## `v` as a whole number (a version that came back from JSON is a float), or 0 when it is not one.
static func whole_version(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and is_finite(v) and is_equal_approx(floorf(v), v) and absf(v) < 1.0e9:
		return int(v)
	return 0
